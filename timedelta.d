module timedelta;

import std.datetime;

struct TimeDelta {
	MonoTime now;
	long msPassed;
}

struct TimeDeltaFactory {
	private MonoTime previousNow;

	void reset() {
		previousNow = MonoTime.currTime;
	}

	TimeDelta create() {
		const now = MonoTime.currTime;
		const msPassed = (now - previousNow).total!"msecs";
		previousNow = now;
		return TimeDelta(now, msPassed);
	}
}

