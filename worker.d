module worker;

import std.stdio;
import std.math;

import core.time;
import core.thread.osthread;
import std.algorithm.comparison, std.math.algebraic, core.atomic;
import streamlistener;
import limiter;

import util;

class Worker {

	// for smooth processes (volume up/down, limiter release)
	const ticksPerSecond = 10;
	const tickInterval = dur!"msecs"(1000/ticksPerSecond);

	shared {
		float mSignal = 0; // realtime informational-only peak value
		float outputTarget; // where we want the final signal level to be.

		float peakMax = 0; // observed max peak value
		float peakMaxTrue = 0;
		long  processedFrames;

		float volume;
		bool overrideVolume = false;

		// -- limiter --
		// range where the limiter starts to work, 1.25 means 125% of the volumeTarget
		float limiterStart = 1.25f;
		float limiterWidth = 0.2f;
	}
	Limiter mLimiter;
	float lowVolumeBoost = 1;

	void syncLimiter(void delegate(Limiter l) synchronizedAction) {
		synchronized(mLimiter) {
			synchronizedAction(cast(Limiter)(mLimiter));
		}
	}

	StreamListener stream;

	private /* ---- peak history */ {

		// peak volume for each chunk of audio data
		float[] chunkPeaks;
		int chunkPeaksWritePos;
		MonoTime peakCreatedAt;

		// round robin the chunkPeak index if it is out of bounds
		int overflowChunkIndex(int p) {
			if (p < 0) p += chunkPeaks.length;
			else if (p >= chunkPeaks.length) p -= chunkPeaks.length;
			return p;
		}
	}

	alias State = StreamListener.State;
	@property StreamListener.State state() { return stream.state; }
	@property bool running() { return stream.state == StreamListener.State.running; }


	this() {
		volume = outputTarget = 0.3;
		mLimiter = new Limiter();
		mLimiter.ticksPerSecond = ticksPerSecond;
	}

	void start() {
		if (stream.state != State.stopped) return;
		thread = new Thread(&run);
		thread.start();
	}

	void stop() {
		stream.stop();
	}

	void setVolume(float v) {
		volume = v;
		setEndpointVolume();
	}

	@property float signal() {
		return mSignal;
	}

	float getOutputTarget() { return this.outputTarget; }

	public void setOutputTarget(double v) {
		outputTarget = v;
		if (outputTarget < 0.01) outputTarget = 0.01;
		updateTargetVolume();
		updateVolume();
	}

	// --- limits / conversions
	// volume = outTarget / in

	float inputSignal() {
		return chunkPeaks[chunkPeaksWritePos];
	}

	float inputSignalPrev() {
		return chunkPeaks.wrap(chunkPeaksWritePos-1);
	}

	float outputSignal() {
		return volume*chunkPeaks[chunkPeaksWritePos];
	}


	// compute T and W parameters based on outputTarget, just for convience
	// https://dsp.stackexchange.com/questions/73619/how-to-derive-equation-for-second-order-interpolation-of-soft-knee-cutoff-in-a-c
	@property float limitT() {
		return outputTarget * (limiterStart + limiterWidth);
	}

	@property float limitW() {
		return outputTarget * limiterWidth;
	}

	@property float limitOutputStart() {
		return limitT - limitW;
	}

	@property float limitOutputEnd() {
		return limitT;
	}

	@property float limitOutputEndPreLimiter() {
		return limitT + limitW;
	}

	@property float limitSignalStart() {
		return limitOutputStart/(volume+0.0001);
	}

	@property float limitSignalEnd() {
		return limitOutputEndPreLimiter/(volume+0.0001);
	}


private:
	Thread thread;
	MonoTime now;

	void run() {
		configurePeakBuffer(70);
		stream.loop(&processBlock);
		info("Worker exited");
	}

	// ---- block processing

	void processBlock(float[] data, uint numFramesAvailable) {
		now = MonoTime.currTime;
		float pk = floatDataToPeak(data, numFramesAvailable);
		realtimePeak(pk, numFramesAvailable);

		bool historicDataChanged = storePeak(pk);
		if (historicDataChanged) {
			if (computeSignalPeak()) {
				updateTargetVolume();
			}
		}

		bool ticked = tick();
		if (ticked) updateVolume();

		synchronized(mLimiter) {
			Limiter limiter = cast(Limiter)(mLimiter);
			limiter.unlimitedVolume = volume;
			limiter.limitT = limitT();
			limiter.limitW = limitW();
			if (ticked) limiter.release();
			limiter.process(inputSignalPrev, inputSignal);
		}

		setEndpointVolume();
		
		processedFrames = processedFrames + numFramesAvailable;
	}

	float floatDataToPeak(float[] data, uint numFramesAvailable) {
		float pk = 0;
		foreach(ref const sample; data) {
			pk = max(pk, abs(sample));
		}
		return pk;
	}

	// ---- realtime signal (only for visualisation purposes)

	float mSignalTmp = 0;
	const int mSignalInterval_ms = 20;
	MonoTime mSignalSetAt = MonoTime.zero;

	void realtimePeak(float blockPeak, size_t numFrames) {
		if (now - mSignalSetAt > msecs(mSignalInterval_ms)) {
			mSignal = mSignalTmp;
			mSignalSetAt = now;
			mSignalTmp = 0;
		}
		mSignalTmp = max(mSignalTmp, blockPeak);
	}

	// --

	// true if history data is changed
	bool storePeak(float peak) {
		bool historyChanged;
		if ((now - peakCreatedAt) > msecs(250)) {
			if (++chunkPeaksWritePos >= chunkPeaks.length) chunkPeaksWritePos = 0;
			peakCreatedAt = now;
			chunkPeaks[chunkPeaksWritePos] = peak;
			historyChanged = true;
		}
		else {
			if (peak > chunkPeaks[chunkPeaksWritePos]) {
				chunkPeaks[chunkPeaksWritePos] = peak;
				historyChanged = true;
			}
		}
		return historyChanged;
	}

	float targetVolume = 0;
	void updateTargetVolume() {
		float vol2 = peakMax > 0.001 ? outputTarget / peakMax : 0.1; // use low volume when audio is silence
		targetVolume = min(1f, vol2);
	}

	MonoTime lastTickExecuted;
	bool tick() {
		if (now - lastTickExecuted < tickInterval) return false;
		lastTickExecuted = now;
		return true;
	}

	// --

	// call on each tick
	void updateVolume() {
		if (volume == targetVolume || overrideVolume) return;

		float vol2 = targetVolume;
		float tempo = 0.1;
		if (vol2 > volume) vol2 = (vol2 - volume)*tempo + volume; // increase volume
		if (vol2 < volume) vol2 = volume - (volume - vol2) * tempo; // decrease volume

		volume = min(1.0, vol2);
	}

	private float previousEndpointVolume = -1;
		
	void setEndpointVolume() {
		import core.stdc.math: pow, cpow = pow;
		float v = min(volume, mLimiter.limitedVolume);
		if (abs(v-previousEndpointVolume) < 0.002) return;
		previousEndpointVolume = v;

		// wolfram results for: y = a+log(x+b), 0 = a+log(b), 1 = a+log(1+b)
		//enum a = 0.11111;
		//enum b = 0.954243;
		//
		//if (volumeProfile == 1) v = v*v;
		//if (volumeProfile == 2) v = log10(v+a) + b;
		//if (volumeProfile == 3) v = sqrt(v);
		//if (volumeProfile == 4) v = cpow(v, 1/2.5);

		v = cpow(v, 1.0/lowVolumeBoost);

		stream.setVolume(clamp01(v));
	}


	import std.algorithm.searching, std.array, std.algorithm.iteration;

	bool computeSignalPeak() {
		auto t = peakMax;
		removePulses();
		auto avg = computeAvgSignal();
		auto peakAboveAvg = computeAboveAvgPeak(avg);
		peakMaxTrue = min(1.0, computeTruePeakMax());
		peakMax = max(avg*0.5 + peakMaxTrue*0.5, peakAboveAvg); // signal level
		return t != peakMax;
	}

	float computeAboveAvgPeak(float avgPeak) {
		real pk = 0;
		int numPk = 0;
		foreach(ref s; chunkPeaks) {
			if (s > avgPeak) {
				numPk++;
				pk+= s;
			}
		}
		if (numPk == 0) return 0f;
		return pk / numPk;
	}

	float computeTruePeakMax() {
		return chunkPeaks.maxElement;
	}

	float computeTruePeakMin() {
		return chunkPeaks.minElement;
	}

	float computeAvgSignal() {
		return chunkPeaks.sum / chunkPeaks.length;
	}

	void removePulses() {
		import std.range;

		int i = 1;
		foreach(window; chunkPeaks.cycle(chunkPeaksWritePos+1).take(chunkPeaks.length-1).slide(5)) {
			float s = window[2];
			bool shortPulse = (s > 2.0*window[0] && s > 2.0*window[4]);
			if (shortPulse) {
				window[2] = s = 0.333333*(window[0] + window[2] + window[4]);
			}
		}
	}


	void configurePeakBuffer(int holdtimeSec) {
		chunkPeaks.length = holdtimeSec;
		foreach(ref pk; chunkPeaks) pk = 0.0;
		chunkPeaksWritePos = 0;
		peakCreatedAt = MonoTime.currTime;
	}



}


bool update(T)(ref T store, T val)  {
	if (store == val) return false;
	store = val;
	return true;
}
