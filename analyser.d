module analyser;
import util;
import core.time;
import std.math;
import std.algorithm;

final class Analyser {
	VisualPeak visualPeak;
	LevelHistory levelHistory;
	LevelFilter levelFilter;
	LoudnessComputer loudnessComputer;

	Duration sampleDuration;

	this(int numSamples, int sampleDurationMs) {
		sampleDuration = msecs(sampleDurationMs);
		visualPeak = new VisualPeak();
		levelHistory = new LevelHistory(numSamples, sampleDuration);
		levelFilter = new LevelFilter(levelHistory, 256);
		loudnessComputer = new LoudnessComputer(levelHistory, levelFilter);
	}

	bool processLevel(float level) {
		auto now = MonoTime.currTime;
		visualPeak.store(now, level);
		bool historyChanged = levelHistory.add(now, level);
		if (historyChanged) {
			levelFilter.classifySamples();
			loudnessComputer.computeLoudness();
		}
		return historyChanged;
	}

	@property float visualLevel() {
		return visualPeak.peak();
	}

	@property float loudness() {
		return loudnessComputer.loudness;
	}

	@property float level() {
		return levelHistory.accumulator;
	}

	private:


}


// short term shift buffer for an accurate visual reading of the level
final class VisualPeak {
	private {
		enum timeSpanMs = 44; // 40 = 25fps; 48 = 20fps; 44 = 22fps
		enum numSamples = 4;
		Duration sampleDuration = msecs(timeSpanMs/numSamples);
		float[numSamples] samples;
		MonoTime nextSampleTime;
		float mCurrentPeak;
	}

	this() {
		foreach(ref h; samples) h = 0f;
		mCurrentPeak = 0;
		nextSampleTime = MonoTime.currTime;
	}

	void store(MonoTime now, float level) {
		samples[0] = max(samples[0], level);
		mCurrentPeak = max(mCurrentPeak, level);

		if (now > nextSampleTime) {
			samples[3] = samples[2];
			samples[2] = samples[1];
			samples[1] = samples[0];
			samples[0] = 0f;
			nextSampleTime = now + sampleDuration;
			mCurrentPeak = samples[].maxElement;
		}
	}

	@property float peak() {
		return mCurrentPeak;
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


// Divides the range of level values into N buckets.
// It counts the number of hits in each bucket reached by the signal level.
final class LevelFilter {
	private {
		LevelHistory history;
		int numBuckets;
		int[] buckets;
		double bucketSize;
		int bucketMaxHits = 0; // number of hits in the bucket with the most hits
		float mLoudness = 0f;
	}
	ubyte[] sampleClassifications;
	float[] averages;

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

	this(LevelHistory history_, int numBuckets_) {
		history = history_;
		numBuckets = numBuckets_;
		buckets.length = numBuckets;
		bucketSize = 1.0 / numBuckets;
		sampleClassifications.length = history.history.length;
		averages.length = history.history.length;
		foreach(ref h; averages) h = 0f;
	}

	void classifySamples() {
		float[] samples = history.history;
	
		// compute average
		maxLevel = samples.maxElement;
		avgLevel = samples.sum / samples.length;
		averages[history.writtenIdx] = avgLevel;



		foreach(ref bucket; buckets) bucket = 0;

		// count for each buckets how many times it has been hit by the signal
		float threshold = avgLevel*0.9;
		bucketMaxHits = 0;
		int lowerBucketIdx = cast(int)(buckets.length - 1);
		int upperBucketIdx = 0;
		foreach(float level; samples) {
			if (level < threshold) continue;	

			int bucketIdx = bucketIdx(level);
			if (bucketIdx >= 0) {
				buckets[bucketIdx] = buckets[bucketIdx] + 1;
				lowerBucketIdx = min(lowerBucketIdx, bucketIdx);
				upperBucketIdx = max(upperBucketIdx, bucketIdx);
				bucketMaxHits = max(bucketMaxHits, buckets[bucketIdx]);
			}
		}

		// when history is empty, use the average
		if (lowerBucketIdx > upperBucketIdx) {
			bucketMaxHits = 0;
			mLoudness = avgLevel;
			minIncludeLevel = 0f;
			maxIncludeLevel = 1f;
			return;
		}

		// accumulate hits to lower buckets
		bucketMaxHits = 0;
		foreach_reverse(ref bucket; buckets[lowerBucketIdx .. upperBucketIdx+1]) {
			bucketMaxHits += bucket;
			bucket = bucketMaxHits;
		}

		// ignore levels that are hit less than 5% than the most hit level
		int minHits = cast(int) (bucketMaxHits * 0.05);
		int maxIncludeBucketIdx = 0;
		foreach(i, ref hits; buckets[lowerBucketIdx .. upperBucketIdx+1]) {
			if (hits > minHits) {
				int bucketIdx = cast(int)(i + lowerBucketIdx);
				if (bucketIdx > maxIncludeBucketIdx) maxIncludeBucketIdx = bucketIdx;
			}
		}

		// the new range to classify samples
		minIncludeLevel = max(0.001f, bucketLevel(lowerBucketIdx)); // 0.001 because sometimes there is a small signal when nothing is playing
		maxIncludeLevel = bucketLevel(maxIncludeBucketIdx+1);
		maxLevel = bucketLevel(upperBucketIdx+1);

		// classify the new sample
		size_t lastSampleIdx = history.writtenIdx;
		float s = samples[lastSampleIdx];
		ubyte c = LOW;
		if (s > minIncludeLevel) c = INCLUDED;
		if (s >= maxIncludeLevel) c = HIGH;
		sampleClassifications[history.writtenIdx] = c;

	}

	int levelHitCount(float level) {
		int bucketIdx = bucketIdx(level);
		if (bucketIdx < 0) return 0;
		return buckets[bucketIdx];
	}

	float levelHitCountNormalized(float level) {
		int bucketIdx = bucketIdx(level);
		if (bucketIdx < 0) return 0;
		return buckets[bucketIdx] / (cast(float) bucketMaxHits + 0.00001);
	}

	float bucketLevel(size_t bucketIdx) {
		return bucketIdx * bucketSize;
	}

	// returns -1 if level <= 0
	int bucketIdx(float level) {
		import std.math;
		int b = (cast(int)(ceil(level / bucketSize))) -1;
		return b < numBuckets ? b : numBuckets -1 ;
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

	this(LevelHistory levHistory_, LevelFilter levFilter_) {
		levHistory = levHistory_;
		levFilter = levFilter_;
		history.length = levHistory.history.length;
	}

	void computeLoudness() {
		int sampleCount = 0;
		real acc = 0;
		foreach(i, ubyte classification; levFilter.sampleClassifications) {
			if (classification == LevelFilter.INCLUDED) {
				sampleCount++;
				acc += levHistory.history[i];
			}
		}
		if (sampleCount == 0) sampleCount = 1;
		loudness = acc / sampleCount;
		history[levHistory.writtenIdx] = loudness;
	}
}