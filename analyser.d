module analyser;
import core.time;
import std.math;
import std.algorithm;

import util;
import lookback;

final class Analyser {

	// visual peak captures the peak level of the last 40ms for display purposes
	private {
		Lookback lookback;
		enum lookbackMs = 60; // 40 = 25fps;
		float mCurrentPeak = 0;
		float mCurrentPeakDb = -100;

		void storeVisualPeak(MonoTime now, float level) {
			lookback.put(now, level);
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

	bool processLevel(float level) {
		auto now = MonoTime.currTime;
		storeVisualPeak(now, level);
		bool historyChanged = levelHistory.add(now, level);
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
	}
}


class LevelHistory {
	float[] history;

	@property int writeIdx() {
		return historyIdx;
	}

	@property size_t writtenIdx() {
		return historyIdx == 0 ? history.length - 1 : historyIdx - 1;
	}

	@property float lastWrittenSample() {
		return history[writtenIdx];
	}

private:
	int historyIdx = 0;  // next write position in history
	Duration sampleDuration;
	MonoTime nextSampleTime;
	float accumulator = 0f;


public:
	this(int numSamples, Duration sampleDuration_) {
		history.length = numSamples;
		sampleDuration = sampleDuration_;
		nextSampleTime = MonoTime.currTime;
		foreach(ref h; history) h = 0f;
	}


	bool add(MonoTime now, float level) {
		accumulator = max(accumulator, level);

		// archive the accumulator
		bool historyChanged = now > nextSampleTime;
		if (historyChanged) {
			history[historyIdx] = accumulator;
			accumulator = 0f;
			nextSampleTime = now + sampleDuration;

			historyIdx++;
			if (historyIdx >= history.length) historyIdx = 0;
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

	enum LOW = 1;
	enum INCLUDED = 2;
	enum HIGH = 3;

	// range of levels used in the weighted average
	float minIncludeLevel = 0f;
	float maxIncludeLevel = 0f;

	// some stats
	float maxLevel;
	float avgLevel;

	// ----------------

	this(LevelHistory history_) {
		history = history_;
		sampleClassifications.length = history.history.length;
		averages.length = history.history.length;
		foreach(ref h; averages) h = 0f;
	}

	void classifySamples() {
		import std.range;
		float[] samples = history.history;
	
		// compute average
		maxLevel = samples.maxElement;
		int startIdx = cast(int) history.writtenIdx;
		startIdx = startIdx - averageLength + 1; // sampling one sample will make us start at writtenIdx
		if (startIdx < 0) startIdx += samples.length;
		real sum = 0;
		int count = 0;
		foreach(s; samples.cycle(startIdx).take(averageLength)) {
			if (s > 0.0005) { // ignore almost total silence -66 dB
				sum += s;
				count++;
			}
		}
		if (count == 0) count = 1;
		avgLevel = sum / count;
		averages[history.writtenIdx] = avgLevel;
		float threshold = avgLevel*0.95;

	
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

	}

	ubyte sampleClassification(int idx) {
		return sampleClassifications[idx];
	}
}

// calculates the loudness from the filtered samples
final class LoudnessComputer {
	private {
		LevelHistory levHistory;
		LevelFilter levFilter;
	}
	float[] history;
	float loudness;
	int numLoudnessBars;
	int lastLoudnessBarIdx;

	this(LevelHistory levHistory_, LevelFilter levFilter_) {
		levHistory = levHistory_;
		levFilter = levFilter_;
		history.length = levHistory.history.length;
	}

	void computeLoudness() {
		int sampleCount = 0;
		int checkCount = 0;
		real acc = 0;
		int i = cast(int) levHistory.writtenIdx;
		do {
			ubyte classification = levFilter.sampleClassifications[i];
			if (classification == LevelFilter.INCLUDED) {
				sampleCount++;
				acc += levHistory.history[i];
			}
			checkCount++;
			i--;
			if (i < 0) i = cast(int) levHistory.history.length - 1;
		}while(sampleCount < numLoudnessBars && checkCount < levHistory.history.length);

		if (sampleCount <4)
			loudness = levFilter.avgLevel;
		else
			loudness = acc / sampleCount;

		history[levHistory.writtenIdx] = loudness;

		lastLoudnessBarIdx = i+1;
		if (lastLoudnessBarIdx == levHistory.history.length) lastLoudnessBarIdx = 0;
	}
}