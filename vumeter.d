module vumeter;

import std.math;
import std.algorithm;
import std.bitmanip;
import std.stdio;

import core.time;
import gdkpixbuf.Pixbuf;

import util;
import vumeterbase;

class VuMeter : VuMeterBase {
	bool enableRaster = true; // enables the raster like spacing between LEDs
	bool enableFade = true;   // enables the fading to the background color, making it easier to see the level
	bool enablePeak = true;

	this(int width, int height) {
		super(width, height);
	}

	void paint(float level, float orangeLevel, float redLevel) {
		paintLevel(level, orangeLevel, redLevel);
		paintPeak(level, orangeLevel, redLevel);
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
	enum RGBA bgGreen =   RGBA(0,   0xe0, 0    ) * 0.25;
	enum RGBA bgOrange =  RGBA(255, 0x80, 0x40 ) * 0.30;
	enum RGBA bgRed =     RGBA(255, 0,    0    ) * 0.25;

	// color for the space between the leds
	enum RGBA spGreen =   RGBA(0,   0xe0, 0    ) * 0.83;
	enum RGBA spOrange =  RGBA(255, 0x80, 0x40 ) * 0.83;
	enum RGBA spRed =     RGBA(255, 0,    0    ) * 0.83;

	void paintLevel(float vol, float orangeLevel, float redLevel) {
		vol = min(1,vol);
		orangeLevel = min(1,orangeLevel);
		redLevel = min(1,redLevel);

		// pixel to start the color on
		int xVol = levelToPixel(vol); //cast(int) ceil(vol * mWidth);
		int xOrange = levelToPixel(orangeLevel); //cast(int) floor(orangeLevel * mWidth);
		int xRed = levelToPixel(redLevel); //cast(int) floor(redLevel * mWidth);
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
			paintVerticalLine(cast(int) max(1,ceil(peak * mWidth)), col);
		}
	}

	void fillLeds(int begin, int end, RGBA rgba_, RGBA rasterColor_) {
		uint rgba = rgba_.toAbgr;
		uint rasterColor = rasterColor_.toAbgr;
		int stride = mPixbuf.getRowstride() /4;
		char[] cdata = mPixbuf.getPixelsWithLength();
		uint[] data = cast(uint[]) cdata;  // assuming rgba format ... (!)

		int idx = 0;
		foreach(y; 0..mHeight) {
			idx = y * stride + begin;
			bool raster = false; //(y&3)==3;
			foreach(x; begin .. end) {
				if ( raster || (x & 0x02) == 0x2)
					data[idx] = rasterColor;
				else
					data[idx] = rgba;
				idx++;
			}
		}
	}

	void fadeToColor(int begin, int end, RGBA rgba) {
		int stride = mPixbuf.getRowstride();
		char[] cdata = mPixbuf.getPixelsWithLength();
		ubyte[] data = cast(ubyte[]) cdata;  // assuming rgba format ... (!)

		int idx = 0;
		foreach(y; 0..mHeight) {
			idx = y * stride + begin*4;
			foreach(x; begin .. end) {
				data[idx] = cast(ubyte) max(rgba.r, data[idx]-30); idx++;
				data[idx] = cast(ubyte) max(rgba.g, data[idx]-32); idx++;
				data[idx] = cast(ubyte) max(rgba.b, data[idx]-28); idx++;
				data[idx++] = 0xff; //a
			}
		}
	}
}