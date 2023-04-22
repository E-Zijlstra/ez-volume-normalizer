module leveldistribution;
import util;
import core.time;
import std.math;
import std.algorithm;

version=propagate;

class LevelHistory {
	float[] history;
	bool historyChanged = false;
	float accumulator = 0f;
	float avgLevel = 0f;
	float maxLevel = 0f;

private:
	int historyIdx = 0;
	Duration bucketTime;
	MonoTime nextBucketTime;

	// short term ring buffer for an accurate reading of the actual peak
	enum peakBufferSize = 4;
	Duration peakBucketDuration = msecs(20/peakBufferSize);
	float[peakBufferSize] peakBuffer;
	MonoTime nextPeakTime;

public:
	this(int numBuckets, int bucketTimeMs) {
		history.length = numBuckets;
		bucketTime = msecs(bucketTimeMs);
		nextBucketTime = nextPeakTime = MonoTime.currTime;
		foreach(ref h; history) h = 0f;
		foreach(ref h; peakBuffer) h = 0f;
	}

	//int samplesInBucket=0;
	
	void add(float level) {
		accumulator = max(accumulator, level);

		// archive the accumulator in the history
		MonoTime now = MonoTime.currTime;
		historyChanged = now > nextBucketTime;
		//samplesInBucket++;
		if (historyChanged) {
			history[historyIdx++] = accumulator;
			if (historyIdx >= history.length) historyIdx = 0;
			accumulator = 0f;
			nextBucketTime = now + bucketTime;
			//samplesInBucket = 0;
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
		}
	}


	// max signal level in last 20 milliseconds
	float currentPeak() {
		return peakBuffer[].maxElement;
	}
}


// Divides the range of level values into N buckets.
// It counts the number of hits in each bucket reached by the signal level.
class LevelDistribution {
	private {
		int numBuckets;
		int[] buckets;
		double bucketSize;
		int bucketMaxHits = 0; // number of hits in the bucket with the most hits
		float mLoudness = 0f;

		float bucketLevel(int bucketIdx) {
			return bucketIdx * bucketSize;
		}

		// returns -1 if level <= 0
		int bucketIdx(float level) {
			import std.math;
			int b = (cast(int)(ceil(level / bucketSize))) -1;
			return b < numBuckets ? b : numBuckets -1 ;
		}
	}

	size_t lowerBucketIdx;
	size_t upperBucketIdx;

	// ---

	this(int numBuckets_) {
		numBuckets = numBuckets_;
		buckets.length = numBuckets;
		bucketSize = 1.0 / numBuckets;
	}

	void fillBuckets(LevelHistory history) {
		float[] peakHistory = history.history;
		foreach(ref bucket; buckets) bucket = 0;

		// count for each buckets how many times it has been hit by the signal
		float threshold = history.avgLevel;
		real levelSum = 0;
		bucketMaxHits = 0;
		lowerBucketIdx = buckets.length - 1;
		upperBucketIdx = 0;
		float peakAvg = 0f;  // average of levels above peakThreshold
		int peakCount = 0;

		foreach(float level; peakHistory) {
			if (level < threshold) continue;

			int bucketIdx = bucketIdx(level);
			if (bucketIdx >= 0) {
				peakAvg += level;
				peakCount++;
				lowerBucketIdx = min(lowerBucketIdx, bucketIdx);
				upperBucketIdx = max(upperBucketIdx, bucketIdx);
				buckets[bucketIdx] = buckets[bucketIdx] + 1;
				if (buckets[bucketIdx] > bucketMaxHits) bucketMaxHits = buckets[bucketIdx];
			}
		}
		if (peakCount > 0) peakAvg /= peakCount;

		// empty history case
		if (lowerBucketIdx > upperBucketIdx) {
			bucketMaxHits = 0;
			mLoudness = history.avgLevel;
			return;
		}

		// propagate hits to lower buckets
		bucketMaxHits = 0;
		foreach_reverse(ref bucket; buckets[lowerBucketIdx .. upperBucketIdx+1]) {
			bucketMaxHits += bucket;
			bucket = bucketMaxHits;
		}

		// compute loudness
		mLoudness = 0f;
		int totalHits = 0;
		int cutoffHits = cast(int) (bucketMaxHits * 0.30); // ignore the levels that are hit less than 75% 
		foreach(i, ref hits; buckets[lowerBucketIdx .. upperBucketIdx+1]) {
			if (hits > cutoffHits) {
				totalHits += hits;
				mLoudness += hits * levelByBucketIdx(i + lowerBucketIdx);
			}
		}
		mLoudness = mLoudness / totalHits;
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

	float levelByBucketIdx(size_t idx) {
		return idx * bucketSize;
	}
}

unittest {
	// test bucketIdx
	auto ld = new LevelDistribution(10);
	assert(ld.bucketIdx(0) == -1);
	assert(ld.bucketIdx(0.01f) == 0);
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