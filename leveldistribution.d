module leveldistribution;
import util;
import core.time;
import std.math;
import std.algorithm;

class LevelHistory {
	float[] history;
	float[] averages;
	bool historyChanged = false;
	float accumulator = 0f;
	float avgLevel = 0f;
	float maxLevel = 0f;

	@property int writeIdx() {
		return historyIdx;
	}

	@property size_t writtenIdx() {
		return historyIdx == 0 ? history.length - 1 : historyIdx - 1;
	}

private:
	int historyIdx = 0;  // next write position in history
	Duration sampleDuration;
	MonoTime nextSampleTime;

	// short term ring buffer for an accurate reading of the actual peak
	enum peakBufferSize = 4;
	Duration peakBucketDuration = msecs(20/peakBufferSize);
	float[peakBufferSize] peakBuffer;
	MonoTime nextPeakTime;

public:
	this(int numSamples, int sampleDurationMs) {
		history.length = numSamples;
		averages.length = numSamples;
		sampleDuration = msecs(sampleDurationMs);
		nextSampleTime = nextPeakTime = MonoTime.currTime;
		foreach(ref h; history) h = 0f;
		foreach(ref h; peakBuffer) h = 0f;
		foreach(ref h; averages) h = 0f;
	}

	void add(float level) {
		accumulator = max(accumulator, level);

		// archive the accumulator in the history
		MonoTime now = MonoTime.currTime;
		historyChanged = now > nextSampleTime;
		if (historyChanged) {
			history[historyIdx] = accumulator;
			accumulator = 0f;
			nextSampleTime = now + sampleDuration;
		}

		// keep track of actual peak
		if (now > nextPeakTime) {
			peakBuffer[3] = peakBuffer[2];
			peakBuffer[2] = peakBuffer[1];
			peakBuffer[0] = 0f;
			nextPeakTime = now + peakBucketDuration;
		}
		peakBuffer[0] = max(peakBuffer[0], level);

		// compute some stats
		if (historyChanged) {
			avgLevel = history.sum / history.length;
			maxLevel = history.maxElement;
			averages[historyIdx] = avgLevel;

			historyIdx++;
			if (historyIdx >= history.length) historyIdx = 0;
		}
	}

	@property float lastWrittenSample() {
		return history.wrap(historyIdx-1);
	}

	// max signal level in last 20 milliseconds
	float currentPeak() {
		return peakBuffer[].maxElement;
	}
}


// Divides the range of level values into N buckets.
// It counts the number of hits in each bucket reached by the signal level.
final class LevelDistribution {
	private {
		LevelHistory history;
		int numBuckets;
		int[] buckets;
		double bucketSize;
		int bucketMaxHits = 0; // number of hits in the bucket with the most hits
		float mLoudness = 0f;
	}
	ubyte[] sampleClassifications;
	float[] loudnesses;

	enum LOW = 1;
	enum INCLUDED = 2;
	enum HIGH = 3;

	// range of levels used in the weighted average
	float minIncludeLevel = 0f;
	float maxIncludeLevel = 0f;
	float maxLevel;

	// ----------------

	this(LevelHistory history_, int numBuckets_) {
		history = history_;
		numBuckets = numBuckets_;
		buckets.length = numBuckets;
		bucketSize = 1.0 / numBuckets;
		sampleClassifications.length = history.history.length;
		loudnesses.length = history.history.length;
	}

	void processArchivedSample() {
		float[] samples = history.history;
		foreach(ref bucket; buckets) bucket = 0;

		// count for each buckets how many times it has been hit by the signal
		float threshold = history.avgLevel*0.9;
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
			mLoudness = history.avgLevel;
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
		loudnesses[history.writtenIdx] = mLoudness;


		// compute loudness by weighted average of the included samples
		mLoudness = 0f;
		int totalHits = 0;
		real acc = 0;
		foreach(i, ubyte classification; sampleClassifications) {
			if (classification == INCLUDED) {
				totalHits++;
				acc += samples[i];
			}
		}
		if (totalHits == 0) totalHits = 1;
		mLoudness = acc / totalHits;
	}

	@property float loudness() {
		return mLoudness;
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

unittest {
	// test bucketIdx
	auto ld = new LevelDistribution(new LevelHistory(20, 20), 10);
	assert(ld.bucketIdx(0) == -1);
	assert(ld.bucketIdx(0.01f) == 0);
	assert(ld.bucketLevel(9) <= 1.0f);
}

unittest {
	return;
	// test propagation of hits
	//auto ld = new LevelDistribution(10);
	//enum e = 0.0001;
	//ld.fillBuckets([0.0, 0.05, 0.1-e, 0.0, 0.0, 0.4-e, 0.5-e, 0, 0,0,0, 1.0+e]);
	//assert(ld.buckets[9] == 1); // 0.90001..1.0+
	//assert(ld.buckets[8] == 1); // 0.80001..0.9
	//assert(ld.buckets[7] == 1); // 0.70001..0.8
	//assert(ld.buckets[6] == 1); // 0.60001..0.7
	//assert(ld.buckets[5] == 1); // 0.50001..0.6
	//assert(ld.buckets[4] == 2); // 0.40001..0.5
	//assert(ld.buckets[3] == 3); // 0.30001..0.4
	//assert(ld.buckets[2] == 3); // 0.20001..0.3
	//assert(ld.buckets[1] == 3); // 0.10001..0.2
	//assert(ld.buckets[0] == 5); // 0.00001..0.1
	//assert(ld.levelHitCount(0f) == 0);
	//assert(ld.levelHitCount(0.01f) == 5);
	//assert(ld.levelHitCount(0.0999f) == 5);
	//assert(ld.levelHitCount(1.0f) == 1);
	//assert(ld.levelHitCount(1.1f) == 1);
}