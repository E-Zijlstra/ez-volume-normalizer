module limiter;

import std.math;
import std.algorithm;
import std.array;
import std.algorithm.searching;
import std.algorithm.iteration;


class Limiter {
	// settings
	int ticksPerSecond;
	bool enabled;
	float releasePerSecond = 0.2;
	float limitT = 0.5;
	float limitW = 0.1;

	// inputs
	float unlimitedVolume = 1f;

	// outputs
	float multiplier = 1f;    // volume multplier to limit the signal
	float limitedVolume = 1f;

	bool limiting = false;

	float[] signalHistory;
	int signalHistoryIdx = 0;

	this() {
		signalHistory.length = 4;
	}

	void process(float prevInputSignal, float inputSignal) {
		signalHistory[signalHistoryIdx++] = inputSignal;
		if (signalHistoryIdx >= signalHistory.length) signalHistoryIdx = 0;

		if (!enabled) {
			multiplier = 1f;
			limitedVolume = unlimitedVolume;
			return;
		}

		real signal = unlimitedVolume * signalHistory[].maxElement;
		real limited = softKneeLimit(signal);
		multiplier = min(multiplier, limited / signal);
		limitedVolume = multiplier * unlimitedVolume;
	}

	// soft knee function to compute desired output signal
	// https://dsp.stackexchange.com/questions/73619/how-to-derive-equation-for-second-order-interpolation-of-soft-knee-cutoff-in-a-c
	private real softKneeLimit(real signal) {
		if (limitW <= 0.001) return signal; // avoid division by zero

		real s2;
		if (signal <= limitT-limitW) s2 = signal;
		else if (signal >= limitT+limitW) s2 = limitT;
		else {
			s2= signal + sqr(signal-limitT + limitW) / (-4*limitW);
		}
		return s2;
	}

	// call on each tick
	void release() {
		if (multiplier == 1f) return;

		real step = (releasePerSecond / ticksPerSecond);
		multiplier = min(1f, multiplier + step);
	}

	static real sqr(real v) { return v*v; }
}