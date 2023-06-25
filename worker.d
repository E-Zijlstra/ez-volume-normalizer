module worker;

import std.stdio;
import std.math;

import core.time;
import core.thread.osthread;
import std.algorithm.comparison, std.math.algebraic, core.atomic;
import streamlistener;
import limiter, analyser;

import util;


struct VolumeInterpolator {
	float tempoDb = 0.25;
	float minStepDb = 0.25;
	bool interpolate = true;

	//float curve = 1.0;
	float tempo = 0.1;

	private {
		StreamListener* mStream;
		float mTarget = 0f;
		float mTargetDb = -40f;
		float mVolume = 0f;
		float mVolumeDb = -40f;
		float mMinVolume = 0;
		float mMinVolumeDb = -40;
	}

	void setMinVolumeDb(float db) {
		mMinVolumeDb = db;
		mMinVolume = pow(10, db/20);
	}

	void setTarget(float v) {
		if (v < 0.00001) v = 0.00001;
		mTarget = v;
		mTargetDb = 20*log10(v);
		mTarget = max(mTarget, mMinVolume);
		mTargetDb = max(mTargetDb, mMinVolumeDb);
	}

	void setTargetDb(float v) {
		mTarget = pow(10, v/20);
		mTargetDb = v;
		mTarget = max(mTarget, mMinVolume);
		mTargetDb = max(mTargetDb, mMinVolumeDb);
	}

	@property float volume() { return mVolume; }
	@property float volumeDb() { return mVolumeDb; }

	void tick() {
		if (interpolate) {
			interpolateDb();
		}
		else {
			mVolume = mTarget;
			mVolumeDb = mTargetDb;
		}
	}

	// returns a value between 0 and 1, where 0 equals minDb, and 1 equals maxDb
	float mapDbTo01(float db) {
		enum maxDb = 0;
		return (db- mMinVolumeDb) / (maxDb - mMinVolumeDb);
	}

	// inverse of mapDbTo01
	float map01ToDb(float s) {
		enum maxDb = 0;
		return s * (maxDb - mMinVolumeDb) + mMinVolumeDb;
	}

	
private:
	void interpolateLinear() {
		float v = mVolume + (mTarget - mVolume) * tempo;
		mVolume = clamp01(v);
		mVolumeDb = 20*log10(mVolume);
	}

	void interpolateDb() {
		float diff = mTargetDb - mVolumeDb;
		float aDiff = abs(diff);

		if (aDiff <= minStepDb) {
			mVolumeDb = mTargetDb;
		}
		else {
			float sign = sgn(diff);
			float step = aDiff * tempoDb;
			step = max(step, minStepDb);
			mVolumeDb += sign * step;
		}

		mVolume = pow(10, mVolumeDb/20);
	}

}

class Worker {

	// for slow processes (volume up/down, limiter release)
	const ticksPerSecond = 10;
	const tickInterval = dur!"msecs"(1000/ticksPerSecond);

	shared {
		float outputTarget = 0.18f; // where we want the final signal level to be.

		long  processedFrames;

		float actualVolumeDb;
		bool mOverrideVolume = false;

		// -- limiter --
		// range where the limiter starts to work, 1.25 means 125% of the volumeTarget
		float limiterStart = 1.25f;
		float limiterWidth = 0.2f;
	}

	float lowVolumeBoost = 1;
	Limiter mLimiter;
	Analyser analyser;
	VolumeInterpolator volumeInterpolator;


	void syncLimiter(void delegate(Limiter l) synchronizedAction) {
		synchronized(mLimiter) {
			synchronizedAction(cast(Limiter)(mLimiter));
		}
	}

	StreamListener stream;

	alias State = StreamListener.State;
	@property StreamListener.State state() { return stream.state; }


	this() {
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
		volumeInterpolator.setMinVolumeDb(max(-40f, stream.minDb));

	}

	void stop() {
		stream.stop();
	}

	void setOverride(bool yes) {
		volumeInterpolator.interpolate = !yes;
		mOverrideVolume = yes;
	}

	void setVolume(float v) {
		with(volumeInterpolator) {
			bool wasInterpolated = interpolate;
			interpolate = false;
			setTarget(v);
			tick();
			interpolate = wasInterpolated;
		}

		setEndpointVolume();
	}

	void setVolumeDb(float db) {
		with(volumeInterpolator) {
			bool wasInterpolated = interpolate;
			interpolate = false;
			setTargetDb(db);
			tick();
			interpolate = wasInterpolated;
		}
		setEndpointVolume();
	}

	@property float signal() {
		return analyser.visualLevel();
	}

	@property float normalizedSignal() {
		return signal * volumeInterpolator.volume;
	}

	@property float limitedSignal() {
		return signal * mLimiter.limitedVolume;
	}

	float getOutputTarget() { return this.outputTarget; }

	void setOutputTarget(double v) {
		outputTarget = v;
		if (outputTarget < 0.01) outputTarget = 0.01;
		normalizeLoudness();
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
		return limitOutputStart/(volumeInterpolator.volume+0.0001);
	}

	@property float limitSignalEnd() {
		return limitOutputEndPreLimiter/(volumeInterpolator.volume+0.0001);
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
		// info(data.length); // about 10ms of data
		now = MonoTime.currTime;
		float pk = floatDataToPeak(data, numFramesAvailable);

		bool loudnessChanged = analyser.processLevel(pk);
		if (loudnessChanged) {
			normalizeLoudness();
		}

		bool ticked = tick();
		if (ticked && !mOverrideVolume) {
			volumeInterpolator.tick();
		}

		synchronized(mLimiter) {
			Limiter limiter = cast(Limiter)(mLimiter);
			limiter.unlimitedVolume = volumeInterpolator.volume;
			limiter.limitT = limitT();
			limiter.limitW = limitW();
			if (ticked) limiter.release();
			limiter.process(analyser.level);
		}
		
		setEndpointVolume();
		if (ticked) {
			actualVolumeDb = stream.getVolumeDb();
		}
		
		processedFrames = processedFrames + numFramesAvailable;
	}

	float floatDataToPeak(float[] data, uint numFramesAvailable) {
		float pk = 0;
		foreach(ref const sample; data) {
			pk = max(pk, abs(sample));
		}
		return pk;
	}

	void normalizeLoudness() {
		float loudness = analyser.loudness;
		float ratio = loudness > 0.0001 ? outputTarget / loudness : 0.0001; // use low volume when audio is silence
		ratio = min(1f, ratio);
		volumeInterpolator.setTarget(ratio);
	}

	MonoTime lastTickExecuted;
	bool tick() {
		if (now - lastTickExecuted < tickInterval) return false;
		lastTickExecuted = now;
		return true;
	}

	// --


	private float previousEndpointVolume = -1;
		
	void setEndpointVolume() {
		import core.stdc.math: pow, cpow = pow;
		float v = min(volumeInterpolator.volume, mLimiter.limitedVolume);
		if (abs(v-previousEndpointVolume) < 0.001) return;
		previousEndpointVolume = v;

		if (lowVolumeBoost != 1)
			v = cpow(v, 1.0/lowVolumeBoost);

		stream.setVolume(clamp01(v));
	}


}
