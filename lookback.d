module lookback;

import std.datetime;
import std.algorithm;
import std.math;


alias MaxLookback = Lookback!true;
alias MinLookback = Lookback!false;

struct SumLookback {
	uint totalMs = 60000;

	private {
		int acc;
		int[60] slots;
		int writeIdx = 0;
		MonoTime nextWriteAt = MonoTime.zero;
	}

	@property Duration slotDuration() {
		ulong d = totalMs / slots.length;
		return dur!"msecs"(d);
	}

	void add(MonoTime now, int value) {
		acc += value;

		if ((now - nextWriteAt).total!"msecs" > 2000) {
			nextWriteAt = now;
		}

		while (now >= nextWriteAt) {
			slots[writeIdx] = acc;
			acc = 0;
			writeIdx++;
			if (writeIdx >= slots.length) writeIdx = 0;
			nextWriteAt = nextWriteAt + slotDuration;
		}
	}
	
	int avgPerSecond() {
		return cast(int) (slots[].sum()*1000 / totalMs);
	}
}

struct Lookback(bool useMax = true, int NUMSLOTS = 16) {

	uint _totalMs = 100;

	private {
		float[NUMSLOTS] slots;
		int writeIdx = 0;
		MonoTime nextWriteAt = MonoTime.zero;
		float mValue = 0;
		float mAvgValue = 0;
		Duration slotDuration = dur!"msecs"(100);
	}

	@property totalMs(uint totalMs) {
		_totalMs = totalMs;
		slotDuration = dur!"msecs"(totalMs/slots.length);
	}

	@property uint totalMs() { return _totalMs; }

	void put(MonoTime now, float value) {
		if (now >= nextWriteAt) {
			// Write value into next slot
			int slotsWritten = 0;
			while (now >= nextWriteAt && slotsWritten < slots.length) {
				slotsWritten++;
				writeIdx++;
				if (writeIdx >= slots.length) writeIdx = 0;
				slots[writeIdx] = value;
				nextWriteAt = nextWriteAt + slotDuration;
			}

			// nextWriteAt would be incorrect if more time passed than the totalMs
			if (slotsWritten == slots.length) {
				nextWriteAt = now + slotDuration;
			}

			static if (useMax) {
				mValue = slots[].maxElement;
			} else {
				mValue = slots[].minElement;
			}
			mAvgValue = slots[].sum / slots.length;
		}
		else {
			// update last written slot
			static if (useMax) {
				slots[writeIdx] = max(slots[writeIdx], value);
				mValue = max(mValue, value);
			} else {
				slots[writeIdx] = min(slots[writeIdx], value);
				mValue = min(mValue, value);
			}
		}
	}

	static if (useMax) {
		@property float maxValue() {
			return mValue;
		}
	} else {
		@property float minValue() {
			return mValue;
		}
	}

	@property float avgValue() {
		return mAvgValue;
	}
}
