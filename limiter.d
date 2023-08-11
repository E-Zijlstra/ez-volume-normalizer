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
		MaxLookback hold;
		MinLookback attnHold;
		float prevUnlimitedVolumeDb = 0;
		float unlimitedVolume = 1f;
		float unlimitedVolumeDb = 0;
		MonoTime lastProcess = MonoTime.zero;
	}

	@property void holdTimeMs(uint ms) {
		hold.totalMs = ms;
		attnHold.totalMs = ms;
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

		if (!enabled) {
			limitedVolumeDb = unlimitedVolumeDb;
			attenuationDb = 0f;
			return;
		}

		hold.put(now, inputSignal);
		float peak;
		if (attackMs == 0)
			peak = hold.totalMs == 0 ? inputSignal : hold.maxValue;
		else
			peak = inputSignal;

		// reduce attenuation by what the normalizer already did
		real volumeChange = unlimitedVolumeDb - prevUnlimitedVolumeDb;
		if (volumeChange < 0) {
			attenuationDb = min(0, attenuationDb - volumeChange);
		}
		prevUnlimitedVolumeDb = unlimitedVolumeDb;

		real msPassed = (now - lastProcess).total!"msecs";
		real normalizedSig = unlimitedVolume * peak;
		real limitedSig = softKneeLimit(normalizedSig);
		real desiredAttn = min(toDb(limitedSig/normalizedSig), 0); // div zero doesn't seem to have an effect. alt: toDb(limitedSig) - toDb(normalizedSig);
		real releaseCeil = 0;
		if (attackMs == 0) {
			attenuationDb = min(desiredAttn, attenuationDb);
			releaseCeil = desiredAttn;
		}
		else {
			if (desiredAttn < attenuationDb) {
				real attnTravel = desiredAttn - attenuationDb;
				real attackedAttn = attenuationDb + attnTravel * min(1, msPassed / attackMs);
				attenuationDb = min(attenuationDb, attackedAttn);
				// attack done, store full attenuation so the level will be held
				attnHold.put(now, attackedAttn);
			}
			else {
				attnHold.put(now, 0);
			}
			releaseCeil = attnHold.minValue;
		}

		// release
		if (desiredAttn > attenuationDb) {
			real step = releasePerSecond * msPassed / 1000.0;
			attenuationDb = min(attenuationDb + step, releaseCeil);
		}

		limitedVolumeDb = unlimitedVolumeDb + attenuationDb;
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


}