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

struct Lookback(bool useMax = true) {

	uint _totalMs = 100;

	private {
		float[8] slots;
		int writeIdx = 0;
		MonoTime nextWriteAt = MonoTime.zero;
		float mMaxValue = 0;
		float mMinValue = 0;
		Duration slotDuration = dur!"msecs"(100);
	}

	@property totalMs(uint totalMs) {
		_totalMs = totalMs;
		slotDuration = dur!"msecs"(totalMs/slots.length);
	}

	@property uint totalMs() { return _totalMs; }

	void put(MonoTime now, float value) {
		static if (useMax)
			float acc = slots[writeIdx] = max(slots[writeIdx], value);
		else
			float acc = slots[writeIdx] = min(slots[writeIdx], value);

		if (now >= nextWriteAt) {
			int slotsWritten = 0;
			while (now >= nextWriteAt && slotsWritten < slots.length) {
				slotsWritten++;
				writeIdx++;
				if (writeIdx >= slots.length) writeIdx = 0;
				slots[writeIdx] = value;
				nextWriteAt = nextWriteAt + slotDuration;
			}

			if (slotsWritten == slots.length) {
				nextWriteAt = now + slotDuration;
			}

			if (useMax)
				mMaxValue = slots[].maxElement;
			else
				mMinValue = slots[].minElement;
		}
		else {
			static if (useMax)
				mMaxValue = max(mMaxValue, value);
			else
				mMinValue = min(mMinValue, value);
		}
	}

	static if (useMax) {
		@property float maxValue() {
			return mMaxValue;
		}
	} else {
		@property float minValue() {
			return mMinValue;
		}
	}
}
