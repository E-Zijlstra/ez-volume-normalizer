module analyser;
import core.time;
import std.math;
import std.algorithm;

import util;
import lookback;
import timedelta;

final class Analyser {

	// capture the peak level of the last 40ms for display purposes
	private {
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

	LevelHistory levelHistory;
	LevelFilter levelFilter;
	LoudnessComputer loudnessComputer;
	uint updateTicks;

	enum samplesPerSecond = 5; // 1000/5 = 200ms TODO make this configurable
	Duration sampleDuration;

	this(int numSamples, int sampleDurationMs) {
		lookback.totalMs = lookbackMs;

		sampleDuration = msecs(sampleDurationMs);
		levelHistory = new LevelHistory(numSamples, sampleDuration);
		levelFilter = new LevelFilter(levelHistory);
		loudnessComputer = new LoudnessComputer(levelHistory, levelFilter);
	}

	//private const(float) minLevel = 0.000316; // -70dB = 0.000316
	//private const(float) minLevel = 0.000562; // -65dB = 0.000562
	private const(float) minLevel = 0.001; // -60dB = 0.001

	bool processLevel(ref const TimeDelta timeLapse, float level, float uncorrectedLevel) {
		storeVisualPeak(timeLapse, level);

		if (level < minLevel) return false;

		bool historyChanged = false;
		historyChanged = levelHistory.add(timeLapse.now, level, uncorrectedLevel);

		if (historyChanged) {
			levelFilter.classifySamples();
			loudnessComputer.computeLoudness();
			updateTicks++;
		}
		return historyChanged;
	}


	@property float visualLevel() {
		return mCurrentPeak;
	}

	@property float visualLevelDb() {
		return mCurrentPeakDb;
	}

	@property float loudness() {
		return loudnessComputer.loudness;
	}

	// this is a bit dubious, the timespan is not really defined
	 @property float level() {
		return mCurrentPeak;
//		return levelHistory.accumulator;
	}

	void setAverageLength(int seconds) {
		levelFilter.averageLength = seconds*samplesPerSecond;
	}

	void setNumLoudnessBars(int seconds) {
		loudnessComputer.numLoudnessBars = seconds * samplesPerSecond;
		levelFilter.numLoudnessBars = seconds * samplesPerSecond;
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


// Classifies samples.
final class LevelFilter {
	private {
		LevelHistory history;
	}
	ubyte[] sampleClassifications;
	float[] averages;
	int averageLength;
	int numLoudnessBars;

	enum LOW = 1;
	enum INCLUDED = 2;
	enum HIGH = 3;
	enum EXPIRED = 4;

	// range of levels used in the weighted average
	float minIncludeLevel = 0f;
	float maxIncludeLevel = 0f;

	// some stats
	float maxLevel;
	float avgLevel;

	// ----------------

	this(LevelHistory history_) {
		history = history_;
		sampleClassifications.length = history.samples.length;
		averages.length = history.samples.length;
		foreach(ref h; averages) h = 0f;
	}

	void classifySamples() {
		import std.range;
		float[] samples = history.samples;
	
		// compute average
		maxLevel = samples.maxElement;
		int startIdx = cast(int) history.writtenIdx;
		startIdx = startIdx - averageLength + 1; // sampling one sample will make us start at writtenIdx
		if (startIdx < 0) startIdx += samples.length;
		real sum = 0;
		int count = 0;
		foreach(s; samples.cycle(startIdx).take(averageLength)) { // TODO: cycle sum
			sum += s;
			count++;
		}
		if (count == 0) count = 1;
		avgLevel = sum / count;
		averages[history.writtenIdx] = avgLevel;
		float threshold = avgLevel*0.98;

	
		// ignore the max sample
		maxLevel = samples.maxElement;
		maxIncludeLevel = -1f;
		foreach(i, float level; samples) {
			if (level < maxLevel && level > maxIncludeLevel) {
				maxIncludeLevel = level;
			}
		}
		if (maxIncludeLevel == -1) {
			minIncludeLevel = 0f;
			maxIncludeLevel = 1f;
			return;
		}
		minIncludeLevel = max(0.0005f, threshold); // 0.001 because sometimes there is a small signal when nothing is playing


		// classify the new sample
		size_t lastSampleIdx = history.writtenIdx;
		float s = samples[lastSampleIdx];
		ubyte c = LOW;
		if (s > minIncludeLevel) c = INCLUDED;
		if (s > maxIncludeLevel) c = HIGH;
		sampleClassifications[history.writtenIdx] = c;

		expire();
	}

	ubyte sampleClassification(int idx) {
		return sampleClassifications[idx];
	}

	void expire() {
		int includedCount = 0;
		int testedCount = 0;
		long idx = history.writtenIdx;
		while(includedCount < numLoudnessBars && testedCount < history.samples.length) {
			if (sampleClassifications.warp(idx) == INCLUDED) includedCount++;
			testedCount++;
			idx--;
		}

		while(testedCount < history.samples.length) {
			sampleClassifications.warp(idx) = EXPIRED;
			testedCount++;
			idx--;
		}
	}
}

// calculates the loudness from the filtered samples
final class LoudnessComputer {
	private {
		LevelHistory levHistory;
		LevelFilter levFilter;
	}
	float[] history;
	float loudness = 1;
	int numLoudnessBars;

	this(LevelHistory levHistory_, LevelFilter levFilter_) {
		levHistory = levHistory_;
		levFilter = levFilter_;
		history.length = levHistory.samples.length;
	}

	void computeLoudness() {
		int accCount = 0;
		int checkCount = 0;
		real acc = 0;
		foreach(i, classification; levFilter.sampleClassifications) {
			if (classification == LevelFilter.INCLUDED) {
				accCount++;
				acc += levHistory.samples[i];
			}
		}

		if (accCount <4)
			loudness = levFilter.avgLevel;
		else
			loudness = acc / accCount;

		history[levHistory.writtenIdx] = loudness;
	}
}