module limiter;

import std.math;
import std.algorithm;
import std.array;
import std.algorithm.searching;
import std.algorithm.iteration;
import util;

import core.time;

final class Limiter {
	// settings
	int ticksPerSecond;
	bool enabled;
	float releasePerSecond = 0.2;
	float limitT = 0.5;
	float limitW = 0.1;
	uint holdTimeMs = 500;

	// outputs
	float attenuationDb = 0;
	float limitedVolumeDb = 0f;

	private {
		float[4] holdBuffer;
		int holdBufferIdx = 0;
		MonoTime holdSlotWrittenAt = MonoTime.zero;

		float unlimitedVolume = 1f;
		float unlimitedVolumeDb = 0;


	}

	@property uint holdSlotTimeMs() {
		return holdTimeMs / holdBuffer.length + 1;
	}

	void writeHistory(MonoTime now, float level) {
		float current = holdBuffer[holdBufferIdx] = max(holdBuffer[holdBufferIdx], level);

		ulong msPassed = (now - holdSlotWrittenAt).total!"msecs";
		ulong slotsPassed = min(holdBuffer.length, msPassed / holdSlotTimeMs);
		for(int i=0; i<slotsPassed; i++) {
			holdBufferIdx++;
			if (holdBufferIdx >= holdBuffer.length) holdBufferIdx = 0;
			holdBuffer[holdBufferIdx] = current;
		}
		if (slotsPassed > 0) {
			holdSlotWrittenAt = now;
			holdBuffer[holdBufferIdx] = 0;
		}
	}

	this() {
	}

	void setCurrentVolume(float linear, float db) {
		unlimitedVolumeDb = db;
		unlimitedVolume = linear;
	}

	@property float limitedVolume() {
		return toLinear(limitedVolumeDb);
	}

	void process(MonoTime now, float inputSignal) {
		//holdBuffer[holdBufferIdx++] = inputSignal;
		//if (holdBufferIdx >= holdBuffer.length) holdBufferIdx = 0;
		writeHistory(now, inputSignal);

		if (!enabled) {
			limitedVolumeDb = unlimitedVolumeDb;
			attenuationDb = 0f;
			return;
		}

		real signal = unlimitedVolume * holdBuffer[].maxElement;
		real limited = softKneeLimit(signal);
		//real attn = toDb(limited) - toDb(signal);
		real attn = toDb(limited/signal);
		attenuationDb = min(attenuationDb, attn);
		limitedVolumeDb = unlimitedVolumeDb + attenuationDb;
	}

	// soft knee function to compute desired output signal
	// https://dsp.stackexchange.com/questions/73619/how-to-derive-equation-for-second-order-interpolation-of-soft-knee-cutoff-in-a-c
	private real softKneeLimit(real signal) {
		if (limitW <= 0.001) return signal; // avoid division by zero

		static real sqr(real v) { return v*v; }

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
		if (attenuationDb == 0f) return;

		real step = (releasePerSecond / ticksPerSecond);
		attenuationDb = min(0, attenuationDb + step);
	}

}