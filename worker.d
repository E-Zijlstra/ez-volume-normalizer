module worker;

import std.stdio;
import std.math;

import core.time;
import core.thread.osthread;
import std.algorithm.comparison, std.math.algebraic, core.atomic;
import streamlistener;
import limiter, analyser, psychoacoustics;

import util;


struct VolumeInterpolator {
	// Meters and controls go this low
	enum minimumVolumeDbCutOff = -50f;

	float tempoDb = 2;
	float minStepDb = 0.1;
	bool interpolate = true;

	private {
		float mTarget = 1f;
		float mTargetDb = 0f;
		float mVolume = 0.1; 
		float mVolumeDb = -30f;
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

	void setTargetDb(float v) {
		v = min(0, v); // can't boost volume
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
		float outputTargetDb = -30;
		float actualVolumeDb;
		bool mOverrideVolume = false;
		float lowVolumeBoost = 1;
	}

	import timedelta;
	private TimeDeltaFactory timeDeltaFactory;

	StreamListener stream;
	Analyser analyser;
	Limiter mLimiter;
	VolumeInterpolator volumeInterpolator;
	PsychoAcoustics psychoAcoustics;
	bool psychoAcousticsEnabled;

	void syncLimiter(void delegate(Limiter l) synchronizedAction) {
		synchronized(mLimiter) {
			synchronizedAction(cast(Limiter)(mLimiter));
		}
	}


	alias State = StreamListener.State;
	@property StreamListener.State state() { return stream.state; }


	this() {
		mLimiter = new Limiter();
		mLimiter.ticksPerSecond = ticksPerSecond;
		enum samplesPerSecond = 5; // 1000/5 = 200ms
		enum msPerSample = 1000/samplesPerSecond;
		analyser = new Analyser(30*samplesPerSecond, msPerSample);
		psychoAcoustics = new PsychoAcoustics();
	}

	void start() {
		if (stream.state != State.stopped) return;
		stream.state = State.starting;
		thread = new Thread(&run);
		thread.start();

		timeDeltaFactory.reset();
		while(stream.state == State.starting) { }

		volumeInterpolator.setMinVolumeDb(stream.minDb);
		psychoAcoustics.setSampleRate(stream.sampleRate);
	}

	void stop() {
		stream.stop();
		while(stream.state != State.stopped) {
			Thread.sleep(dur!"msecs"(1));
		}
	}

	void setDeviceId(string id) {
		stream.deviceId = id;
	}

	// control

	void setOutputTargetDb(double v) {
		outputTargetDb = v;
		setVolumeFromAnalyser();
	}

	void setOverride(bool yes) {
		volumeInterpolator.interpolate = !yes;
		mOverrideVolume = yes;
		if (!yes) {
			setVolumeFromAnalyser();
		}
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

	// informational

	@property float signalDb() {
		return analyser.visualLevelDb();
	}

	@property float normalizedSignalDb() {
		return signalDb + volumeInterpolator.volumeDb;
	}

	@property float limitedSignalDb() {
		return signalDb + mLimiter.limitedVolumeDb;
	}



private:
	// ---- audio processing

	Thread thread;

	void run() {
		try {
			resetDeltaExpectedProcessedSamples();
			stream.loop(&processBlock);
		}
		catch(Throwable e) {
			error(e.info);
			error(e.msg);
		}
		stream.state = State.stopped;
		info("Worker exited");
	}

	long samplesProcessed = 0;
	MonoTime startProcessing;
	public long deltaExpectedProcessedSamples;
	public float deltaExpectedProcessedSamplesMin;
	public float deltaExpectedProcessedSamplesMax;

	void updateDeltaExpectedProcessedSamples(MonoTime now, uint numFramesAvailable) {
		if (numFramesAvailable == 0) return;
		if (startProcessing == MonoTime.zero) {
			startProcessing = now;
			return;
		}
		samplesProcessed += numFramesAvailable;
		long expected = (now - startProcessing).total!"msecs" * stream.sampleRate / 1000;
		deltaExpectedProcessedSamples = samplesProcessed - expected;
		deltaExpectedProcessedSamplesMin += abs(deltaExpectedProcessedSamplesMin / 4000f);
		deltaExpectedProcessedSamplesMax -= abs(deltaExpectedProcessedSamplesMax / 4000f);
		float dps = deltaExpectedProcessedSamples;
		deltaExpectedProcessedSamplesMin = min(deltaExpectedProcessedSamplesMin, dps);
		deltaExpectedProcessedSamplesMax = max(deltaExpectedProcessedSamplesMax, dps);
	}
	void resetDeltaExpectedProcessedSamples() {
		startProcessing = MonoTime.zero;
		samplesProcessed = 0;
		deltaExpectedProcessedSamples = 0;
		deltaExpectedProcessedSamplesMin = 10000;
		deltaExpectedProcessedSamplesMax = -10000;
	}


	// about 10ms of data (480 frames), data is processed within 1ms
	void processBlock(float[] data, uint numFramesAvailable) {
		TimeDelta timeDelta = timeDeltaFactory.create();
		updateDeltaExpectedProcessedSamples(timeDelta.now, numFramesAvailable);
		float pk = floatDataToPeak(data);
		float pkBeforeCorrection = pk;
		if (psychoAcousticsEnabled) {
			psychoAcoustics.process(data, pk.toDb);
			float accousticCorrectionFactor = psychoAcoustics.correction.toLinear;
			pk *= accousticCorrectionFactor;
		}

		bool loudnessChanged = analyser.processLevel(timeDelta, pk, pkBeforeCorrection);

		bool ticked = tick(timeDelta);
		if (ticked && !mOverrideVolume) {
			setVolumeFromAnalyser();
			volumeInterpolator.tick(1f/ticksPerSecond);
		}

		synchronized(mLimiter) {
			Limiter limiter = cast(Limiter)(mLimiter);
			limiter.setCurrentVolume(volumeInterpolator.volume, volumeInterpolator.volumeDb);
			limiter.process(timeDelta, pk);
		}
		
		setEndpointVolume();
		if (ticked) {
			actualVolumeDb = stream.getVolumeDb();
		}
		
		//auto processMs = (timeDelta.now - MonoTime.currTime).total!"usecs";
		//info(processMs);
	}

	float floatDataToPeak(float[] data) {
		float pk = 0;
		foreach(ref const sample; data) {
			pk = max(pk, abs(sample));
		}
		return pk;
	}

	void setVolumeFromAnalyser() {
		float diff = outputTargetDb - toDb(analyser.loudness);
		if (analyser.loudness < 0.0001) diff = -40;
		volumeInterpolator.setTargetDb(diff);
	}

	MonoTime lastTickExecuted;
	bool tick(ref const TimeDelta timeDelta) {
		if (timeDelta.now - lastTickExecuted < tickInterval) return false;
		lastTickExecuted = timeDelta.now;
		return true;
	}

	// --


	float previousEndpointVolume = 1;
	
	// resolution of endpoint is typically 0.4db
	void setEndpointVolume() {
		import std.math: pow;
		//import core.stdc.math: cpow = pow;

		float db = min(volumeInterpolator.volumeDb, mLimiter.limitedVolumeDb);
		db = quantize(db, 0.1f);
		if (db == previousEndpointVolume) return;
		previousEndpointVolume = db;
		setEndpointVolumeForced();
	}

	public void setEndpointVolumeForced() {
		float db = previousEndpointVolume * lowVolumeBoost;
		stream.setVolumeDb(db);
	}
}
