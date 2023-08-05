module lookback;

import std.datetime;
import std.algorithm;
import std.math;

struct Lookback {

	uint totalMs = 100;

	private {
		float[8] slots;
		int writeIdx = 0;
		MonoTime slotWrittenAt = MonoTime.zero;
		float mMaxValue = 0;
	}

	@property ulong slotDuration() {
		ulong d = totalMs / slots.length;
		return d == 0 ? 1 : d;
	}

	void put(MonoTime now, float value) {
		float currentAcc = slots[writeIdx] = max(slots[writeIdx], value);

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
			mMaxValue = slots[].maxElement;
		}
		else {
			mMaxValue = max(mMaxValue, value);
		}
	}

	@property float maxValue() {
		return mMaxValue;
	}
}
