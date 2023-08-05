module limiter;

import std.math;
import std.algorithm;
import std.array;
import std.algorithm.searching;
import std.algorithm.iteration;
import util;

import core.time;
import lookback;

// https://dsp.stackexchange.com/questions/73619/how-to-derive-equation-for-second-order-interpolation-of-soft-knee-cutoff-in-a-c
final class Limiter {
	// settings
	int ticksPerSecond;
	bool enabled;
	float releasePerSecond = 0.2;
	float limitT = 0.5;
	float limitW = 0.1;
	float limitTdb = 0.5;
	float limitWdb = 0.1;
	float attackMs = 0;

	// outputs
	float attenuationDb = 0;
	float limitedVolumeDb = 0f;

	private {
		Lookback hold;
		float prevUnlimitedVolumeDb = 0;
		float unlimitedVolume = 1f;
		float unlimitedVolumeDb = 0;

		bool releasable = true;
		MonoTime lastProcess = MonoTime.zero;
	}

	@property void holdTimeMs(uint ms) {
		hold.totalMs = ms;
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
		ulong msPassed = (now - lastProcess).total!"msecs";
		hold.put(now, inputSignal);

		if (!enabled) {
			limitedVolumeDb = unlimitedVolumeDb;
			attenuationDb = 0f;
			return;
		}

		float peak = hold.totalMs == 0 ? inputSignal : hold.maxValue;
		real normalizedSig = unlimitedVolume * peak;
		real limitedSig = softKneeLimit(normalizedSig);

		// avoid division by zero 
		//real attn = toDb(limitedSig) - toDb(normalizedSig); assert(attn <= 0.0);
		real attn = toDb(limitedSig/normalizedSig);
		real attnTravel = attn - attenuationDb;
		if (attackMs == 0) {
			attenuationDb = min(attenuationDb, attn);
		}
		else {
			attenuationDb = attenuationDb + min(0, attnTravel) * (msPassed / attackMs);
		}

		// correct for volume reductions by the normalizer
		real volumeChange = unlimitedVolumeDb - prevUnlimitedVolumeDb;
		if (volumeChange < 0) {
			attenuationDb = min(0, attenuationDb - volumeChange);
			releasable = false;
		}
		else {
			releasable = attnTravel > 0;
		}

		limitedVolumeDb = unlimitedVolumeDb + attenuationDb;
		prevUnlimitedVolumeDb = unlimitedVolumeDb;
		lastProcess = now;
	}

	// soft knee function to compute desired output signal
	// https://dsp.stackexchange.com/questions/73619/how-to-derive-equation-for-second-order-interpolation-of-soft-knee-cutoff-in-a-c
	private real softKneeLimit(real signal) {
		if (limitW <= 0.0001) return signal; // avoid division by zero

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
		alias attn = attenuationDb;
		if (attn == 0f || !releasable) return;

		real step = (releasePerSecond / ticksPerSecond);
		attn = min(0, attn + step);
	}

}