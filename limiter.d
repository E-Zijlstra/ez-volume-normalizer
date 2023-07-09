module limiter;

import std.math;
import std.algorithm;
import std.array;
import std.algorithm.searching;
import std.algorithm.iteration;
import util;

import core.time;
import lookback;

final class Limiter {
	// settings
	int ticksPerSecond;
	bool enabled;
	float releasePerSecond = 0.2;
	float limitT = 0.5;
	float limitW = 0.1;
	float limitTdb = 0.5;
	float limitWdb = 0.1;

	// outputs
	float attenuationDb = 0;
	float limitedVolumeDb = 0f;

	private {
		Lookback hold;
		float unlimitedVolume = 1f;
		float unlimitedVolumeDb = 0;
	}

	@property void holdTimeMs(uint ms) {
		hold.totalMs = ms;
	}

	this() {
	}

	@property void Tdb(float t) {
		limitTdb = t;
		limitT = toLinear(t);
		info("limitT ", limitT);
	}

	@property void Wdb(float t) {
		limitWdb = t;
		limitW = toLinear(t) - 1f;
		info("limitW ", limitW);
	}

	@property float Tdb() {
		return limitTdb;
	}

	@property float Wdb() {
		return limitWdb;
	}


	void setCurrentVolume(float linear, float db) {
		unlimitedVolumeDb = db;
		unlimitedVolume = linear;
	}

	@property float limitedVolume() {
		return toLinear(limitedVolumeDb);
	}

	void process(MonoTime now, float inputSignal) {
		hold.put(now, inputSignal);

		if (!enabled) {
			limitedVolumeDb = unlimitedVolumeDb;
			attenuationDb = 0f;
			return;
		}

		real signal = unlimitedVolume * hold.maxValue;
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