module worker;

import std.stdio;
import std.math;

import core.time;
import core.thread.osthread;
import std.algorithm.comparison, std.math.algebraic, core.atomic;
import streamlistener;
import limiter, leveldistribution;

import util;

class Worker {

	// for slow processes (volume up/down, limiter release)
	const ticksPerSecond = 10;
	const tickInterval = dur!"msecs"(1000/ticksPerSecond);

	shared {
		float outputTarget; // where we want the final signal level to be.

		long  processedFrames;

		float volume;
		float volumeDb;
		bool overrideVolume = false;

		// -- limiter --
		// range where the limiter starts to work, 1.25 means 125% of the volumeTarget
		float limiterStart = 1.25f;
		float limiterWidth = 0.2f;
	}
	Limiter mLimiter;
	float lowVolumeBoost = 1;
	LevelHistory levelHistory;
	LevelDistribution levelDistribution;

	void syncLimiter(void delegate(Limiter l) synchronizedAction) {
		synchronized(mLimiter) {
			synchronizedAction(cast(Limiter)(mLimiter));
		}
	}

	StreamListener stream;

	alias State = StreamListener.State;
	@property StreamListener.State state() { return stream.state; }
	@property bool running() { return stream.state == StreamListener.State.running; }


	this() {
		volume = outputTarget = 0.3;
		mLimiter = new Limiter();
		mLimiter.ticksPerSecond = ticksPerSecond;
		enum samplesPerSecond = 5; // 1000/5 = 200ms
		enum msPerSample = 1000/samplesPerSecond;
		levelHistory = new LevelHistory(30*samplesPerSecond, msPerSample);
		levelDistribution = new LevelDistribution(levelHistory, 256);
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
		return levelHistory.currentPeak();
	}

	float getOutputTarget() { return this.outputTarget; }

	// for manual volume control
	public void setOutputTarget(double v) {
		outputTarget = v;
		if (outputTarget < 0.01) outputTarget = 0.01;
		updateTargetVolume();
	}

	// --- limits / conversions
	// volume = outTarget / in

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
		stream.loop(&processBlock);
		info("Worker exited");
	}

	// ---- block processing

	void processBlock(float[] data, uint numFramesAvailable) {
		now = MonoTime.currTime;
		float pk = floatDataToPeak(data, numFramesAvailable);

		levelHistory.add(pk);
		if (levelHistory.historyChanged) {
			levelDistribution.processArchivedSample();
			updateTargetVolume();
		}

		bool ticked = tick();
		if (ticked) {
			updateVolume();
			volumeDb = stream.getVolumeDb();
		}

		synchronized(mLimiter) {
			Limiter limiter = cast(Limiter)(mLimiter);
			limiter.unlimitedVolume = volume;
			limiter.limitT = limitT();
			limiter.limitW = limitW();
			if (ticked) limiter.release();
			limiter.process(levelHistory.accumulator);
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

	float targetVolume = 0;
	void updateTargetVolume() {
		float loudness = levelDistribution.loudness;
		float vol2 = loudness > 0.001 ? outputTarget / loudness : 0.1; // use low volume when audio is silence
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
		if (abs(v-previousEndpointVolume) < 0.005) return;
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

	
	@property auto chunkPeaks() { return levelHistory.history; }


}


bool update(T)(ref T store, T val)  {
	if (store == val) return false;
	store = val;
	return true;
}
