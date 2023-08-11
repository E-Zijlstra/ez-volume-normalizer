module lookback;

import std.datetime;
import std.algorithm;
import std.math;


alias MaxLookback = Lookback!true;
alias MinLookback = Lookback!false;

struct Lookback(bool useMax = true) {

	uint totalMs = 100;

	private {
		float[8] slots;
		int writeIdx = 0;
		MonoTime slotWrittenAt = MonoTime.zero;
		float mMaxValue = 0;
		float mMinValue = 0;
	}

	@property ulong slotDuration() {
		ulong d = totalMs / slots.length;
		return d == 0 ? 1 : d;
	}

	void put(MonoTime now, float value) {
		static if (useMax)
			float currentAcc = slots[writeIdx] = max(slots[writeIdx], value);
		else
			float currentAcc = slots[writeIdx] = min(slots[writeIdx], value);

		ulong msPassed = (now - slotWrittenAt).total!"msecs";
		ulong slotsPassed = min(slots.length, msPassed / slotDuration);
		// free up a new slot if time has passed
		if (slotsPassed > 0) {
			for(int i=0; i<slotsPassed; i++) {
				writeIdx += 1;
				if (writeIdx >= slots.length) writeIdx = 0;
				slots[writeIdx] = currentAcc;
			}

			slots[writeIdx] = value;
			slotWrittenAt = now;
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
