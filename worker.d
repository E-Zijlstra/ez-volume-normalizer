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
	// Meters and controls go this low
	enum minimumVolumeDbCutOff = -40f;

	float tempoDb = 2;
	float minStepDb = 0.1;
	bool interpolate = true;

	private {
		//StreamListener* mStream;
		float mTarget = 1f;
		float mTargetDb = 0f;
		float mVolume = 0f;
		float mVolumeDb = 0f;
		float mMinVolume = 0;
		float mMinVolumeDb = -40;
	}

	@property float minVolumeDb() { return mMinVolumeDb; }

	// set hardware capability
	void setMinVolumeDb(float db) {
		db = max(db, minimumVolumeDbCutOff);
		mMinVolumeDb = db;
		mMinVolume = toLinear(db);
	}

	void setTarget(float v) {
		mTarget = v;
		mTargetDb = toDb(v);
		mTarget = max(mTarget, mMinVolume);
		mTargetDb = max(mTargetDb, mMinVolumeDb);

		if (!interpolate) {
			mVolume = mTarget;
			mVolumeDb = mTargetDb;
		}
	}

	void setTargetDb(float v) {
		mTarget = toLinear(v);
		mTargetDb = v;
		mTarget = max(mTarget, mMinVolume);
		mTargetDb = max(mTargetDb, mMinVolumeDb);

		if (!interpolate) {
			mVolume = mTarget;
			mVolumeDb = mTargetDb;
		}
	}

	@property float volume() { return mVolume; }
	@property float volumeDb() { return mVolumeDb; }

	void tick(float dt) {
		if (interpolate) {
			interpolateDb(dt);
			mVolume = toLinear(mVolumeDb);
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

	void interpolateDb(float dt) {
		float diff = mTargetDb - mVolumeDb;

		if (abs(diff) <= minStepDb) {
			mVolumeDb = mTargetDb;
		}
		else {
			mVolumeDb += diff * tempoDb * dt;
		}
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
		volumeInterpolator.setMinVolumeDb(stream.minDb);

	}

	void stop() {
		stream.stop();
		while(stream.state != State.stopped) {
			Thread.sleep(dur!"msecs"(1));
		}
	}

	void setOverride(bool yes) {
		volumeInterpolator.interpolate = !yes;
		mOverrideVolume = yes;
		if (!yes) {
			setVolumeFromAnalyser();
		}
	}

	void setVolume(float v) {
		with(volumeInterpolator) {
			bool wasInterpolated = interpolate;
			interpolate = false;
			setTarget(v);
			interpolate = wasInterpolated;
		}

		setEndpointVolume();
		if (!mOverrideVolume) setVolumeFromAnalyser();
	}

	void setVolumeDb(float db) {
		with(volumeInterpolator) {
			bool wasInterpolated = interpolate;
			interpolate = false;
			setTargetDb(db);
			interpolate = wasInterpolated;
		}
		setEndpointVolume();
		if (!mOverrideVolume) setVolumeFromAnalyser();
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

	@property float signalDb() {
		return analyser.visualLevelDb();
	}

	@property float normalizedSignalDb() {
		return signalDb + volumeInterpolator.volumeDb;
	}

	@property float limitedSignalDb() {
		return signalDb + mLimiter.limitedVolumeDb;
	}

	float getOutputTarget() { return this.outputTarget; }

	void setOutputTarget(double v) {
		outputTarget = v;
		if (outputTarget < 0.001) outputTarget = 0.001;
		setVolumeFromAnalyser();
	}

	void setOutputTargetDb(double v) {
		outputTarget = toLinear(v);
		if (outputTarget < 0.001) outputTarget = 0.001;
		setVolumeFromAnalyser();
	}

	// --- limits / conversions
	// volume = outTarget / in

	// compute T and W parameters based on outputTarget, just for convience

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

		bool ticked = tick();
		if (ticked && !mOverrideVolume) {
			setVolumeFromAnalyser();
			volumeInterpolator.tick(1f/ticksPerSecond);
		}

		synchronized(mLimiter) {
			Limiter limiter = cast(Limiter)(mLimiter);
			limiter.setCurrentVolume(volumeInterpolator.volume, volumeInterpolator.volumeDb);
			if (ticked) limiter.release();
			limiter.process(now, pk);
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

	void setVolumeFromAnalyser() {
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


	private float previousEndpointVolume = 1;
	
	// resolution of endpoint is typacally 0.4db
	void setEndpointVolume() {
		float db = min(volumeInterpolator.volumeDb, mLimiter.limitedVolumeDb);
		db = quantize(db, 0.1f);
		if (db == previousEndpointVolume) return;
		previousEndpointVolume = db;

		stream.setVolumeDb(db);
	}


}
