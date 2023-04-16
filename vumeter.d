module vumeter;

import std.math;
import std.algorithm;
import std.bitmanip;
import std.stdio;

import core.time;
import gdkpixbuf.Pixbuf;

import util;


class VuMeter {
	bool enableRaster = true;
	bool enableFade = true;
	bool enablePeak = true;

	this(int width, int height) {
		mPixbuf = new Pixbuf(GdkColorspace.RGB, true, 8, width, height);
		this.mWidth = width;
		this.mHeight = height;

	}

	@property Pixbuf pixbuf() { return mPixbuf; }

	void paint(float vol, float lim, float lim2) {
		paintLevel(vol, lim, lim2);
		paintPeak(vol, lim, lim2);
	}

	void paintPeak(float vol, float lim, float lim2) {
		auto tSinceSet = MonoTime.currTime - peakSetAt;

		if (vol > peak) {
			peakDecaying = false;
			peak = vol;
			peakSetAt = MonoTime.currTime;
		}
		else if (!peakDecaying && tSinceSet > peakHoldTime) {
			// switch to decay
			peakDecaying = true;
			peakSetAt = MonoTime.currTime;
		}
		else if (peakDecaying) {
			long msPassed = tSinceSet.total!"msecs";
			float step = peakDecayPerSec * msPassed / 1000f;
			peak = max(0, peak - step);
			peakSetAt = MonoTime.currTime;
		}

		if (peak > 0.01) {
			uint col = green;
			uint rcol = rgreen;
			if (peak > lim)  { col = orange; rcol = rorange; }
			if (peak > lim2) { col = red; rcol = rred; }
			paintVerticalBar(cast(int) max(1,ceil(peak * mWidth)), col, rcol);
		}
	}


private:
	Pixbuf mPixbuf;
	int mWidth, mHeight;

	double peak = 0;
	const peakHoldTime = dur!"msecs"(5000);
	const peakDecayPerSec = 0.2;
	MonoTime peakSetAt;
	bool peakDecaying;

	enum uint green = rgba(0,0xe0, 0);
	enum uint orange = rgba(255, 0x80, 0x40);
	enum uint red = rgba(255,0,0);
	enum uint blank = 0x000000ff;

	enum uint hgreen =   rgba(0,   0xe0, 0,    0.25);
	enum uint horange =  rgba(255, 0x80, 0x40, 0.30);
	enum uint hred =     rgba(255, 0,    0,    0.25);

	enum uint rgreen =   rgba(0,   0xe0, 0,    0.75);
	enum uint rorange =  rgba(255, 0x80, 0x40, 0.75);
	enum uint rred =     rgba(255, 0,    0,    0.75);
	const uint hblank =  0x000000ff;

	void paintLevel(float vol, float lim, float lim2) {
		vol = min(1,vol);
		lim = min(1,lim);
		lim2 = min(1,lim2);

		// pixel to start the color on (exclusive)
		int xVol = cast(int) ceil(vol * mWidth);
		int xOrange = cast(int) floor(lim * mWidth);
		int xRed = cast(int) floor(lim2 * mWidth);
		int xEnd = mWidth;

		////clear
		if (enableFade) {
			fillAndFade(0, xOrange, hgreen);
			fillAndFade(xOrange, xRed, horange);
			fillAndFade(xRed, mWidth, hred);

		}
		else {
			fillPlain(0, xOrange, hgreen);
			fillPlain(xOrange, xRed, horange);
			fillPlain(xRed, mWidth, hred);
		}
		//fade();

		// fill
		if (xVol < xOrange) {
			fill(0, xVol, green, rgreen);
		}
		else if (xVol < xRed) {
			fill(0, xOrange, green, rgreen);
			fill(xOrange, xVol, orange, rorange);
		}
		else {
			fill(0, xOrange, green, rgreen);
			fill(xOrange, xRed, orange, rorange);
			fill(xRed, xVol, red, rred);
		}

		// clear
//		fill(xVol+1, xEnd, blank);
	}

	void fill(int begin, int end, uint rgba_, uint rasterColor_) {
		if (enableRaster)
			fillRaster(begin, end, rgba_, rasterColor_);
		else
			fillPlain(begin, end, rgba_);
	}

	void fillRaster(int begin, int end, uint rgba_, uint rasterColor_) {
		uint rgba = swapEndian(rgba_);
		uint rasterColor = swapEndian(rasterColor_);
		int stride = mPixbuf.getRowstride() /4;
		char[] cdata = mPixbuf.getPixelsWithLength();
		uint[] data = cast(uint[]) cdata;  // assuming rgba format ... (!)

		int idx = 0;
		foreach(y; 0..mHeight) {
			idx = y * stride + begin;
			bool raster = (y&3)==3;
			foreach(x; begin .. end) {
				if ( raster || (x & 0x07) == 0x7)
					data[idx] = rasterColor;
				else
					data[idx] = rgba;
				idx++;
			}
		}
	}


	void fillPlain(int begin, int end, uint rgba_) {
		uint rgba = swapEndian(rgba_);
		int stride = mPixbuf.getRowstride() /4;
		char[] cdata = mPixbuf.getPixelsWithLength();
		uint[] data = cast(uint[]) cdata;  // assuming rgba format ... (!)

		int idx = 0;
		foreach(y; 0..mHeight) {
			idx = y * stride + begin;
			foreach(x; begin .. end) {
				data[idx++] = rgba;
			}
		}
	}

	void paintVerticalBar(int x, uint rgba_, uint rcol_) {
		fill(x,x+1,rgba_, rcol_);
		//uint rgba = swapEndian(rgba_);
		//int stride = mPixbuf.getRowstride() /4;
		//char[] cdata = mPixbuf.getPixelsWithLength();
		//uint[] data = cast(uint[]) cdata;  // assuming rgba format ... (!)
		//
		//foreach(y; 0..mHeight) {
		//    size_t idx = y * stride + x;
		//    data[idx] = rgba;
		//}
	}

	void fillAndFade(int begin, int end, uint rgba_) {
		uint rgba = swapEndian(rgba_);
		int stride = mPixbuf.getRowstride();
		char[] cdata = mPixbuf.getPixelsWithLength();
		ubyte[] data = cast(ubyte[]) cdata;  // assuming rgba format ... (!)

		ubyte r = (rgba_ >> 24) & 0xff;
		ubyte g = (rgba_ >> 16) & 0xff;
		ubyte b = (rgba_ >>  8) & 0xff;

		int idx = 0;
		foreach(y; 0..mHeight) {
			idx = y * stride + begin*4;
			foreach(x; begin .. end) {
				data[idx] = cast(ubyte) max(r, data[idx]-30); idx++;
				data[idx] = cast(ubyte) max(g, data[idx]-32); idx++;
				data[idx] = cast(ubyte) max(b, data[idx]-28); idx++;
				data[idx++] = 0xff; //a
			}
		}
	}

	void fade() {
		char[] cdata = mPixbuf.getPixelsWithLength();
		ubyte[] data = cast(ubyte[]) cdata;  // assuming rgba format ... (!)
		int stride = mPixbuf.getRowstride();
		int idx;

		foreach(y; 0..mHeight) {
			idx = y * stride;
			foreach(x; 0 .. mWidth) {
				// ABGR
				data[idx] = cast(ubyte) max(0, data[idx]-30); idx++;
				data[idx] = cast(ubyte) max(0, data[idx]-32); idx++;
				data[idx] = cast(ubyte) max(0, data[idx]-28); idx++;
				idx++;
			}
		}

	}

}