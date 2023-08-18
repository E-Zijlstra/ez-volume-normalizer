module psychoacoustics;


import std.math;
import std.algorithm;
import util;

final class PsychoAcoustics {
	private {
		BandSplitter _splitter;
		int _sampleRate = 48000;
		float _time = 1;
		bool _paramsChanged = true;
	}

	float lowGain = -2;
	float highGain = 2;
	float gainOffset = 0;
	float lowLevel;
	float highLevel;
	float combinedLevel;
	float adjustedLevel;
	float correction;

	@property float perception() {
		return (2f+correction) / 4f;
	}

	this() {
		_splitter = new BandSplitter;
		setSampleRate(_sampleRate);
	}

	void setSampleRate(int sampleRate) {
		_sampleRate = sampleRate;
		_paramsChanged = true;
	}

	void setTime(float time_) {
		_time = time_;
		_paramsChanged = true;
	}

	@property float time() { return _time; }

	void process(float[] data) {
		if (_paramsChanged) {
			_splitter.setParams(900, _sampleRate, _time);
			_paramsChanged = false;
		}

		_splitter.processStereo(data);
		lowLevel = dataToPeak(_splitter.lowpass).toDb;
		highLevel = dataToPeak(_splitter.highpass).toDb;

		combinedLevel = max(lowLevel, highLevel);
		adjustedLevel = max(lowLevel + lowGain, highLevel + highGain);
		correction = adjustedLevel - combinedLevel + gainOffset;
	}

	float dataToPeak(float[] data) {
		float pk = 0;
		foreach(ref const sample; data) {
			pk = max(pk, abs(sample));
		}
		return pk;
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
		_frequency = frequency;
		_sampleRate = sampleRate;
		_lpf.setParams(frequency, sampleRate);
		_hpf.setParams(frequency, sampleRate);

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

