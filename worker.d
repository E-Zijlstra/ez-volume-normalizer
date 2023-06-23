module worker;

import std.stdio;
import std.math;

import core.time;
import core.thread.osthread;
import std.algorithm.comparison, std.math.algebraic, core.atomic;
import streamlistener;
import limiter, analyser;

import util;

class Worker {

	// for slow processes (volume up/down, limiter release)
	const ticksPerSecond = 10;
	const tickInterval = dur!"msecs"(1000/ticksPerSecond);

	shared {
		float outputTarget; // where we want the final signal level to be.

		long  processedFrames;

		float volume;
		float actualVolumeDb;
		bool overrideVolume = false;

		// -- limiter --
		// range where the limiter starts to work, 1.25 means 125% of the volumeTarget
		float limiterStart = 1.25f;
		float limiterWidth = 0.2f;
	}

	float lowVolumeBoost = 1;
	Limiter mLimiter;
	Analyser analyser;

	@property volumeDb() {
		return 20*log10(volume);
	}

	void syncLimiter(void delegate(Limiter l) synchronizedAction) {
		synchronized(mLimiter) {
			synchronizedAction(cast(Limiter)(mLimiter));
		}
	}

	StreamListener stream;

	alias State = StreamListener.State;
	@property StreamListener.State state() { return stream.state; }


	this() {
		volume = outputTarget = 0.3;
		mLimiter = new Limiter();
		mLimiter.ticksPerSecond = ticksPerSecond;
		enum samplesPerSecond = 5; // 1000/5 = 200ms
		enum msPerSample = 1000/samplesPerSecond;
		analyser = new Analyser(30*samplesPerSecond, msPerSample);
	}

	void start() {
		if (stream.state != State.stopped) return;
		stream.state = State.starting;
		thread = new Thread(&run);
		thread.start();
		while(stream.state == State.starting) {
		}
		// -36 is max attenuation when target is set to 0.01. Clip it so we can use the full range of the volume slider.
		if (stream.minDb < -40) stream.minDb = -40;

	}

	void stop() {
		stream.stop();
	}

	void setVolume(float v) {
		volume = v;
		setEndpointVolume();
	}

	void setVolumeDb(float db) {
		volume = pow(10, db/20);
		//info("setVolumeDb: ", db, " -> ", volume);
		setEndpointVolume();
	}

	@property float signal() {
		return analyser.visualLevel();
	}

	float getOutputTarget() { return this.outputTarget; }

	public void setOutputTarget(double v) {
		outputTarget = v;
		if (outputTarget < 0.01) outputTarget = 0.01;
		updateNormalizedVolume();
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
	float normalizedVolume = 0;

	void run() {
		stream.loop(&processBlock);
		info("Worker exited");
	}

	// ---- block processing

	void processBlock(float[] data, uint numFramesAvailable) {
		// info(data.length); // about 10ms of data
		now = MonoTime.currTime;
		float pk = floatDataToPeak(data, numFramesAvailable);

		if (analyser.processLevel(pk)) {
			updateNormalizedVolume();
		}

		bool ticked = tick();
		if (ticked) {
			updateVolume();
			actualVolumeDb = stream.getVolumeDb();
		}

		synchronized(mLimiter) {
			Limiter limiter = cast(Limiter)(mLimiter);
			limiter.unlimitedVolume = volume;
			limiter.limitT = limitT();
			limiter.limitW = limitW();
			if (ticked) limiter.release();
			limiter.process(analyser.level);
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

	void updateNormalizedVolume() {
		float loudness = analyser.loudness;
		float vol2 = loudness > 0.001 ? outputTarget / loudness : 0.1; // use low volume when audio is silence
		normalizedVolume = min(1f, vol2);
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
		if (volume == normalizedVolume || overrideVolume) return;

		float vol2 = normalizedVolume;
		float tempo = 0.1;
		if (vol2 > volume) vol2 = (vol2 - volume)*tempo + volume; // increase volume
		if (vol2 < volume) vol2 = volume - (volume - vol2) * tempo; // decrease volume

		volume = min(1.0, vol2);
	}

	private float previousEndpointVolume = -1;
		
	void setEndpointVolume() {
		import core.stdc.math: pow, cpow = pow;
		float v = min(volume, mLimiter.limitedVolume);
		if (abs(v-previousEndpointVolume) < 0.001) return;
		previousEndpointVolume = v;

		if (lowVolumeBoost != 1)
			v = cpow(v, 1.0/lowVolumeBoost);

		stream.setVolume(clamp01(v));
	}


}
