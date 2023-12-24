module analyser;
import core.time;
import std.math;
import std.algorithm;
import std.range;


import util;
import lookback;
import timedelta;

version = wma;
version = sma;

// Bar: a 200ms of audio, that may or may not be selected (based on the average level) to be used for calculating the loudness

final class Analyser {

	// --------- settings ---------
	private {
		static const(float) minLevel = 0.0005; // -66dB
		enum samplesPerSecond = 5; // 1000/5 = 200ms TODO make this configurable
		Duration sampleDuration;
	}

	void setSelectorLength(int seconds) {
		loudnessAnalyzer.selectorLength = seconds*samplesPerSecond;
	}

	void setNumLoudnessBars(int seconds) {
		loudnessAnalyzer.numLoudnessBars = seconds * samplesPerSecond;
	}

	// --------- output --------- 
	LevelHistory levelHistory;
	LoudnessAnalyzer loudnessAnalyzer;
	uint updateTicks;

	@property float visualLevel() {
		return mCurrentPeak;
	}

	@property float visualLevelDb() {
		return mCurrentPeakDb;
	}

	@property float loudness() {
		return loudnessAnalyzer.loudness;
	}

	// this is a bit dubious, the timespan is not really defined
	@property float level() {
		return mCurrentPeak;
		//		return levelHistory.accumulator;
	}

	// --------- impl --------- 

	this(int numSamples, int sampleDurationMs) {
		lookback.totalMs = lookbackMs;

		sampleDuration = msecs(sampleDurationMs);
		levelHistory = new LevelHistory(numSamples, sampleDuration);
		loudnessAnalyzer = new LoudnessAnalyzer(levelHistory);
	}


	bool processLevel(ref const TimeDelta timeLapse, float level, float uncorrectedLevel) {
		storeVisualPeak(timeLapse, level);

		if (level < minLevel) return false;

		bool historyChanged = false;
		historyChanged = levelHistory.add(timeLapse.now, level, uncorrectedLevel);

		if (historyChanged) {
			loudnessAnalyzer.addSample();
			updateTicks++;
		}
		return historyChanged;
	}

	private:

	// capture the peak level of the last 40ms for display purposes

	MaxLookback lookback;
	enum lookbackMs = 60; // 60 ms = 16.6 Hz
	float mCurrentPeak = 0;
	float mCurrentPeakDb = -100;

	void storeVisualPeak(ref const TimeDelta timeLapse, float level) {
		lookback.put(timeLapse.now, level);
		if (mCurrentPeak == lookback.maxValue) return;

		mCurrentPeak = lookback.maxValue;
		mCurrentPeakDb = toDb(mCurrentPeak);
	}

}


class LevelHistory {
	float[] samples;
	float[] samplesUncorrected;

	@property int writeIdx() {
		return samplesIdx;
	}

	@property size_t writtenIdx() {
		return samplesIdx == 0 ? samples.length - 1 : samplesIdx - 1;
	}

	@property float lastWrittenSample() {
		return samples[writtenIdx];
	}

private:
	int samplesIdx = 0;  // next write position in history
	Duration sampleDuration;
	MonoTime nextSampleTime;
	float accumulator = 0f;
	float accumulatorUncorrected = 0f;


public:
	this(int numSamples, Duration sampleDuration_) {
		samples.length = numSamples;
		samplesUncorrected.length = numSamples;
		sampleDuration = sampleDuration_;
		nextSampleTime = MonoTime.currTime;
		foreach(ref h; samples) h = 0f;
		foreach(ref h; samplesUncorrected) h = 0f;
	}

	bool add(MonoTime now, float level, float levelUncorrected) {
		accumulator = max(accumulator, level);
		accumulatorUncorrected = max(accumulatorUncorrected, levelUncorrected);

		// archive the accumulator
		bool historyChanged = now > nextSampleTime;
		if (historyChanged) {
			samples[samplesIdx] = accumulator;
			samplesUncorrected[samplesIdx] = accumulatorUncorrected;
			accumulator = 0f;
			accumulatorUncorrected = 0f;
			nextSampleTime = now + sampleDuration;

			samplesIdx++;
			if (samplesIdx >= samples.length) samplesIdx = 0;
		}

		return historyChanged;
	}
}

float smax(float[] samples, int startIdx, int length) {
	return samples.cycle(startIdx).take(length).maxElement;
}

float sma(float[] samples, int startIdx, int length) {
	real sum = 0;
	int num = 0;
	foreach(s; samples.cycle(startIdx).take(length)) {
		if (s > Analyser.minLevel) {
			sum += s;
			num++;
		}
	}
	if (num == 0) num = 1;
	return sum / num;
}

float wma(float[] samples, int startIdx, int length) {
	real sum = 0;
	int num = 1;
	foreach(s; samples.cycle(startIdx).take(length)) {
		if (s > Analyser.minLevel) {
			num++;
			sum += s * num;
		}
	}
	if (num == 0) num = 1;
	float weight = num * (num+1) / 2;   // 1+2+3+4 = 10; n=4 => 10 = n * (n+1) / 2
	return sum / weight;
}

final class LoudnessAnalyzer {
	private {
		LevelHistory history;
	}
	bool _useWma = true;
	int selectorLength;
	int numLoudnessBars;

	private {
		ubyte[] sampleClassificationsSma;
		float[] selectorThresholdsSma;
		float[] loudnessesSma;

		ubyte[] sampleClassificationsWma;
		float[] selectorThresholdsWma;
		float[] loudnessesWma;
		float _resetDb = -100;
		float _resetLinear = 0;
	}

	@property void resetDb(float db) {
		_resetDb = db;
		_resetLinear = db.toLinear;
	}

	ubyte[] sampleClassifications;
	float[] selectorThresholds;
	float[] loudnesses;
	float[] floor;

	enum LOW = 1;
	enum INCLUDED = 2;
	enum HIGH = 3;
	enum EXPIRED = 4;

	// last values
	float maxLevel;
	float loudness = 0;

	// ----------------

	@property void useWma(bool yes) {
		_useWma = yes;
		if (_useWma) {
			sampleClassifications = sampleClassificationsWma;
			selectorThresholds = selectorThresholdsWma;
			loudnesses = loudnessesWma;
		}
		else {
			sampleClassifications = sampleClassificationsSma;
			selectorThresholds = selectorThresholdsSma;
			loudnesses = loudnessesSma;
		}
	}

	void reset() {
		expireAll();
	}

	// ----------------


	this(LevelHistory history_) {
		history = history_;
		version(sma) {
			sampleClassificationsSma.length = history.samples.length;
			selectorThresholdsSma.length = history.samples.length;
			foreach(ref h; selectorThresholdsSma) h = 0f;
			loudnessesSma.length = history.samples.length;
			foreach(ref h; loudnessesSma) h = 0f;
		}
		version(wma) {
			sampleClassificationsWma.length = history.samples.length;
			selectorThresholdsWma.length = history.samples.length;
			foreach(ref h; selectorThresholdsWma) h = 0f;
			loudnessesWma.length = history.samples.length;
			foreach(ref h; loudnessesWma) h = 0f;
		}

		useWma(_useWma);

		floor.length = history.samples.length;

	}

	void addSample() {
		const constantSignalGaurd = 0.99; // ensures that the bar is included if the input signal is constant
		version(wma) selectorThresholdsWma[history.writtenIdx] = wma(history.samples, idxForLastN(selectorLength), selectorLength) * constantSignalGaurd;
		version(sma) selectorThresholdsSma[history.writtenIdx] = sma(history.samples, idxForLastN(selectorLength), selectorLength) * constantSignalGaurd;

		// auto reset
		floor[history.writtenIdx] = loudness * _resetLinear;
		if (selectorThresholds[history.writtenIdx] < floor[history.writtenIdx]) {
			if (!selectorBelowFloor) {
				selectorBelowFloor = true;
				reset();
			}
		}
		else {
			selectorBelowFloor = false;
		}

		version(wma) sampleClassificationsWma[history.writtenIdx] = classifySample(history.samples[history.writtenIdx], selectorThresholdsWma[history.writtenIdx]);
		version(sma) sampleClassificationsSma[history.writtenIdx] = classifySample(history.samples[history.writtenIdx], selectorThresholdsSma[history.writtenIdx]);

		expireClassifications();

		version(wma) loudnessesWma[history.writtenIdx] = loudnessWMA();
		version(sma) loudnessesSma[history.writtenIdx] = loudnessSMA();
		loudness = loudnesses[history.writtenIdx];
	}

	private:

	bool selectorBelowFloor;
	
	// Returns the start index if we want to read the last n samples
	int idxForLastN(size_t n) {
		int startIdx = cast(int) history.writtenIdx;
		startIdx = startIdx - cast(int)(n) + 1;
		if (startIdx < 0) startIdx += history.samples.length;
		return startIdx;
	}

	ubyte classifySample(float sample, float threshold) {
		float minLevel = max(Analyser.minLevel, threshold);
		ubyte c = LOW;
		if (sample > minLevel) c = INCLUDED;
		if (sample > maxLevel) c = HIGH;

		// Do this last otherwise the HIGH clasification would never trigger
		maxLevel = history.samples.maxElement;

		return c;
	}

	void expireClassifications() {
		int includedCount = 0;
		int testedCount = 0;
		long idx = history.writtenIdx;
		// Go backwards the number of INCLUDED classifications to keep
		while(includedCount < numLoudnessBars && testedCount < history.samples.length) {
			if (sampleClassifications.warp(idx) == INCLUDED) includedCount++;
			testedCount++;
			idx--;
		}

		// Expire the remaining
		while(testedCount < history.samples.length) {
			sampleClassifications.warp(idx) = EXPIRED;
			testedCount++;
			idx--;
		}
	}

	void expireAll() {
		long idx = history.writtenIdx + 1;
		if (idx >= sampleClassifications.length) idx = 0;
		foreach(ref c; sampleClassifications.cycle(idx).take(sampleClassifications.length - 4)) {
			c = EXPIRED;
		}
	}

	float loudnessSMA() {
		int num = 0;
		real sum = 0;
		int idx = idxForLastN(history.samples.length);

		foreach(i; 0..history.samples.length) {	
			if (sampleClassificationsSma[idx] == INCLUDED) {
				num++;
				sum += history.samples[idx];
			}
			idx++;
			if (idx >= history.samples.length) idx = 0;
		}

		if (num == 0) {
			return smax(history.samples, idxForLastN(selectorLength), selectorLength);
		}
		return sum / num;
	}	

	float loudnessWMA() {
		int num = 0;
		real sum = 0;
		int idx = idxForLastN(history.samples.length);

		foreach(i; 0..history.samples.length) {	
			if (sampleClassificationsWma[idx] == INCLUDED) {
				num++;
				sum += history.samples[idx]; // * num;
			}
			idx++;
			if (idx >= history.samples.length) idx = 0;
		}

		if (num == 0) {
			return smax(history.samples, idxForLastN(selectorLength), selectorLength);
		}
		//int weight = num * (num+1) / 2;
		//return sum / weight;
		return sum / num;
	}
}
