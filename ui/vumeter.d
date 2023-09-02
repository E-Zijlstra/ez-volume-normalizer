module ui.vumeter;

import std.math;
import std.algorithm;
import std.bitmanip;
import std.stdio;

import core.time;

import util;
import ui.vumeterbase;

class VuMeter : VuMeterBase {
	bool enableRaster = true; // enables the raster like spacing between LEDs
	bool enableFade = true;   // enables the fading to the background color, making it easier to see the level
	bool enablePeak = true;
	float minDb = -40;

	this(int width, int height) {
		super(width, height);
	}

	void paint(float level, float orangeLevel, float redLevel) {
		level = clamp01(level);
		orangeLevel = clamp01(orangeLevel);
		redLevel = clamp01(redLevel);
		paintLevel(level, orangeLevel, redLevel);
		paintPeak(level, orangeLevel, redLevel);
	}

	void paintDb(float level, float orangeLevel, float redLevel) {
		level = mapDbTo01(level);
		orangeLevel = mapDbTo01(orangeLevel);
		redLevel = mapDbTo01(redLevel);
		paint(level, orangeLevel, redLevel);
	}

private:
	// returns a value between 0 and 1, where 0 equals minDb, and 1 equals maxDb
	float mapDbTo01(float db) {
		enum maxDb = 0;
		return (db - minDb) / (maxDb - minDb);
	}

	// inverse of mapDbTo01
	float map01ToDb(float s) {
		enum maxDb = 0;
		return s * (maxDb - minDb) + minDb;
	}


private:
	double peak = 0;
	const peakHoldTime = dur!"msecs"(5000);
	const peakDecayPerSec = 0.2;
	MonoTime tLastPeakPaint, tLastPeakBump;
	bool peakDecaying;

	enum RGBA green =  RGBA(  0, 0xe0, 0);
	enum RGBA orange = RGBA(255, 0x80, 0x40);
	enum RGBA red =    RGBA(255, 0,0);
	enum RGBA blank =  RGBA(0,0,0);

	// background colors
	enum RGBA bgGreen =   RGBA(0,   0xe0, 0    ) * 0.22;
	enum RGBA bgOrange =  RGBA(255, 0x80, 0x40 ) * 0.38;
	enum RGBA bgRed =     RGBA(255, 0,    0    ) * 0.35;

	// color for the space between the leds
	enum RGBA spGreen =   RGBA(0,   0xe0, 0    ) * 0.83;
	enum RGBA spOrange =  RGBA(255, 0x80, 0x40 ) * 0.83;
	enum RGBA spRed =     RGBA(255, 0,    0    ) * 0.83;

	void paintLevel(float vol, float orangeLevel, float redLevel) {
		// pixel to start the color on
		int xVol = levelToPixel(vol);
		int xOrange = levelToPixel(orangeLevel);
		int xRed = levelToPixel(redLevel);
		int xEnd = mWidth;

		// clear/fade to background color
		void delegate(int, int, RGBA) clearFunction;
		clearFunction = enableFade ? &fadeToColor : &paintBlock;
		clearFunction(0, xOrange, bgGreen);
		clearFunction(xOrange, xRed, bgOrange);
		clearFunction(xRed, mWidth, bgRed);

		// paint the level bar
		if (enableRaster) {
			fillLeds(0, min(xOrange, xVol), green, spGreen);
			fillLeds(xOrange, min(xRed, xVol), orange, spOrange);
			fillLeds(xRed, min(xEnd, xVol), red, spRed);
		}
		else {
			paintBlock(0, min(xOrange, xVol), green);
			paintBlock(xOrange, min(xRed, xVol), orange);
			paintBlock(xRed, min(xEnd, xVol), red);
		}
	}


	void paintPeak(float vol, float orangeLevel, float redLevel) {
		auto t = MonoTime.currTime;
		auto timePassed = t - tLastPeakPaint;
		tLastPeakPaint = t;

		if (vol > peak) {
			peakDecaying = false;
			peak = vol;
			tLastPeakBump = t;
		}
		else if (!peakDecaying && (t-tLastPeakBump > peakHoldTime)) {
			peakDecaying = true;
		}

		if (peakDecaying) {
			long msPassed = timePassed.total!"msecs";
			float step = peakDecayPerSec * msPassed / 1000f;
			peak = max(0, peak - step);
		}

		if (peak > 0.001) {
			RGBA col = green;
			if (peak > orangeLevel)  { col = orange; }
			if (peak > redLevel) { col = red; }
			paintVerticalLine(levelToPixel(peak), col);
		}
	}

	void fillLeds(int begin, int end, RGBA rgba_, RGBA rasterColor_) {
		if (begin >= end) return;

		uint rgba = rgba_.toUint;
		uint rasterColor = rasterColor_.toUint;
		int stride = mPixbuf.getRowstride() /4;
		char[] cdata = mPixbuf.getPixelsWithLength();
		uint[] data = cast(uint[]) cdata;

		int idx = 0;
		foreach(y; 0..mHeight) {
			idx = y * stride + begin;
			foreach(x; begin .. end) {
				data[idx++] = ( (x & 0x02) == 0x2) ? rasterColor : rgba;
			}
		}
	}

	void fadeToColor(int begin, int end, RGBA rgba) {
		int stride = mPixbuf.getRowstride();
		char[] cdata = mPixbuf.getPixelsWithLength();
		ubyte[] data = cast(ubyte[]) cdata;

		int idx = 0;
		foreach(y; 0..mHeight) {
			idx = y * stride + begin*4;
			foreach(x; begin .. end) {
				//data[idx] = cast(ubyte) max(rgba.r, data[idx]-28); idx++;
				//data[idx] = cast(ubyte) max(rgba.g, data[idx]-28); idx++;
				//data[idx] = cast(ubyte) max(rgba.b, data[idx]-28); idx++;
				data[idx] = (rgba.r + data[idx]+ data[idx]+ data[idx]) >> 2; idx++;
				data[idx] = (rgba.g + data[idx]+ data[idx]+ data[idx]) >> 2; idx++;
				data[idx] = (rgba.b + data[idx]+ data[idx]+ data[idx]) >> 2; idx++;
				data[idx++] = 0xff; //a
			}
		}
	}
}