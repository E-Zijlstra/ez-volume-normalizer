module timelapse;

import std.datetime;

struct TimeLapse {
	MonoTime now;
	long msPassed;
}

struct TimeLapser {
	private MonoTime previousNow;

	void reset() {
		previousNow = MonoTime.currTime;
	}

	TimeLapse elapse() {
		const now = MonoTime.currTime;
		const msPassed = (now - previousNow).total!"msecs";
		previousNow = now;
		return TimeLapse(now, msPassed);
	}
}

