module psychoacoustics;


import std.math;
import std.algorithm;
import std.datetime;
import util;
import lookback;

final class PsychoAcoustics {
	private {
		HighPassLevelMeter _highPassMeter;
		int _sampleRate = 48000;
		float _windowSeconds = 1;
		bool _paramsChanged = true;
	}

	float lowGain = -6;
	const frequency = 700;
	float correction;
	
	// experimental determinated by checking correctionlevel with a sine tone at given frequency
	const freqOffset = 0;//300;

	float lowLevel = 0, highLevel = 0;

	this() {
		_highPassMeter = new HighPassLevelMeter();
		setSampleRate(_sampleRate);
	}

	void setSampleRate(int sampleRate) {
		_sampleRate = sampleRate;
		_paramsChanged = true;
	}

	void setTime(float seconds) {
		_windowSeconds = seconds;
		_paramsChanged = true;
	}

	@property float time() { return _windowSeconds; }

	void process(float[] data, float rawDb) {
		if (_paramsChanged) {
			_highPassMeter.setParams(frequency+freqOffset, _sampleRate, _windowSeconds);
			_paramsChanged = false;
		}

		_highPassMeter.processInput(data);
		highLevel = _highPassMeter.filteredLookback.avgValue.toDb;
		float level = _highPassMeter.inputLookback.avgValue.toDb;
		lowLevel = level + lowGain;
		float adjustedLevel = max(lowLevel, highLevel);

		correction = (adjustedLevel - level);
	}

	float dataToPeak(float[] data) {
		float pk = 0;
		foreach(ref const sample; data) {
			pk = max(pk, abs(sample));
		}
		return pk;
	}

}


final class HighPassLevelMeter {
private:
	HighPassFilter _leftFilter;
	HighPassFilter _rightFilter;
	float _sampleRate;
	float _frequency;

public:
	Lookback!(true,64) filteredLookback;
	Lookback!(true, 64) inputLookback;

	void setParams(float frequency, float sampleRate, float bufferSizeSeconds) {
		_frequency = frequency;
		_sampleRate = sampleRate;
		_leftFilter.setParams(frequency, sampleRate);
		_rightFilter.setParams(frequency, sampleRate);
		filteredLookback.totalMs = cast(uint) (bufferSizeSeconds * 1000);
		inputLookback.totalMs = cast(uint) (bufferSizeSeconds * 1000);
	}

	void processInput(float[] data) {
		auto now = MonoTime.currTime;
		size_t len = data.length & ~1;
		if (len == 0) return;
		float* p = data.ptr;
		float* end = p + len;
		float maxInput = 0;
		float maxFiltered = 0;
		do {
			maxInput = max(maxInput, max(abs(*p), abs(*(p+1))));
			float leftFiltered = _leftFilter.process(*p);
			float rightFiltered = _rightFilter.process(*(p+1));
			maxFiltered = max(maxFiltered, max(abs(leftFiltered), abs(rightFiltered)));
			p += 2;
		}while(p < end);

		inputLookback.put(now, maxInput);
		filteredLookback.put(now, maxFiltered);
	}
}



final class BandSplitter {

	private {
		LowPassFilter _lpf;
		HighPassFilter _hpf;
		float _sampleRate;
		float _frequency;

		long  _writeIdx = 0;
	}
	float[] lowpass;
	float[] highpass;

	void setParams(float frequency, float sampleRate, float bufferSizeSeconds) {
		const freqOverlap = 800;
		_frequency = frequency;
		_sampleRate = sampleRate;
		_lpf.setParams(frequency+freqOverlap, sampleRate);
		_hpf.setParams(frequency-freqOverlap, sampleRate);

		size_t size = cast(size_t)(bufferSizeSeconds * _sampleRate);
		lowpass.length = size;
		highpass.length = size;
		_writeIdx = 0;
	}

	void processStereo(float[] data) {
		size_t len = data.length & ~1;
		if (len == 0) return;

		float* p = data.ptr;
		float* end = p + len;

		do {
			float sample = *p; p++;
			sample += *p; p++;
			sample *= 0.5;
			lowpass[_writeIdx] = _lpf.process(sample);
			highpass[_writeIdx] = _hpf.process(sample);
			_writeIdx++;
			if (_writeIdx >= lowpass.length) {
				_writeIdx = 0;
			}
		}while(p < end);
	}
}

// https://github.com/ctrecordings/Ddsp/blob/master/filter/ddsp/filter/lowpass.d
struct LowPassFilter {

	void setParams(float frequency, float sampleRate) {
		_frequency = frequency;
		_sampleRate = sampleRate;
		calcCoefficients();
		reset();
	}

	void calcCoefficients() {
        _thetac = 2 * PI * _frequency / _sampleRate;
        _gamma = cos(_thetac) / (1 + sin(_thetac));
        _a0 = (1 - _gamma) / 2;
        _a1 = _a0;
        _a2 = 0.0;
        _b1 = -_gamma;
        _b2 = 0.0;
    }

	void reset() {
		_w = 0;
		_w1 = 0;
		_w2 = 0;
		_yn = 0;
	}

	float process(float input) {
		_w = input - _b1 * _w1 - _b2 * _w2;
		_yn = (_a0 * _w + _a1 *_w1 + _a2 * _w2) * _c0 + (input * _d0);
		_w2 = _w1;
		_w1 = _w;
		return _yn;
	}

    float _thetac;
    float _gamma;

	//Delay samples
	float _w = 0;
	float _w1 = 0;
	float _w2 = 0;
	float _yn = 0;

	//Biquad Coeffecients
	float _a0=0, _a1=0, _a2=0;
	float _b1=0, _b2=0;
	float _c0=1, _d0=0;

	float _sampleRate;
	float _frequency;
}

struct HighPassFilter {

	void setParams(float frequency, float sampleRate) {
		_frequency = frequency;
		_sampleRate = sampleRate;
		calcCoefficients();
		reset();
	}

	void calcCoefficients() {
        _thetac = 2 * PI * _frequency / _sampleRate;
        _gamma = cos(_thetac) / (1 + sin(_thetac));
        _a0 = (1 + _gamma) / 2;
        _a1 = -_a0;
        _a2 = 0.0;
        _b1 = -_gamma;
        _b2 = 0.0;
    }

	void reset() {
		_w = 0;
		_w1 = 0;
		_w2 = 0;
		_yn = 0;
	}

	float process(float input) {
		_w = input - _b1 * _w1 - _b2 * _w2;
		_yn = (_a0 * _w + _a1 *_w1 + _a2 * _w2) * _c0 + (input * _d0);
		_w2 = _w1;
		_w1 = _w;
		return _yn;
	}

    float _thetac;
    float _gamma;

	//Delay samples
	float _w = 0;
	float _w1 = 0;
	float _w2 = 0;
	float _yn = 0;

	//Biquad Coeffecients
	float _a0=0, _a1=0, _a2=0;
	float _b1=0, _b2=0;
	float _c0=1, _d0=0;

	float _sampleRate;
	float _frequency;
}

struct LowPassFilterOnePole {

	void setParams(float frequency, float sampleRate) {
		_frequency = frequency;
		_sampleRate = sampleRate;
		calcCoefficients();
		reset();
	}

	void calcCoefficients() {
        _thetac = 2 * PI * _frequency / _sampleRate;
        _gamma = 2 - cos(_thetac);
        _b1 = sqrt((_gamma * _gamma) - 1) - _gamma;
        _a0 = 1 + _b1;
    }

	void reset() {
        _yn1 = 0;
	}

	float process(float input) {
		float output = _a0 * input - _b1 * _yn1;
        _yn1 = input;
        return output;
	}

    float _thetac;
    float _gamma;

	//Delay samples
	float _yn1 = 0;

	//Biquad Coeffecients
	float _a0=0;
	float _b1=0;

	float _sampleRate;
	float _frequency;
}


struct HighPassFilterOnePole {

	void setParams(float frequency, float sampleRate) {
		_frequency = frequency;
		_sampleRate = sampleRate;
		calcCoefficients();
		reset();
	}

	void calcCoefficients() {
        _thetac = 2 * PI * _frequency / _sampleRate;
        _gamma = 2 + cos(_thetac);
        _b1 = _gamma - sqrt((_gamma * _gamma) - 1);
        _a0 = 1 - _b1;
    }

	void reset() {
        _yn1 = 0;
	}

	float process(float input) {
		float output = _a0 * input - _b1 * _yn1;
        _yn1 = input;
        return output;
	}

    float _thetac;
    float _gamma;

	//Delay samples
	float _yn1 = 0;

	//Biquad Coeffecients
	float _a0=0;
	float _b1=0;

	float _sampleRate;
	float _frequency;
}

