module vumeterbase;

import std.math;

import gdkpixbuf.Pixbuf;
import util;

class VuMeterBase {
public:
	@property Pixbuf pixbuf() { return mPixbuf; }

protected:

	Pixbuf mPixbuf;
	int mWidth, mHeight;

	this(int width, int height) {
		mPixbuf = new Pixbuf(GdkColorspace.RGB, true, 8, width, height);
		this.mWidth = width;
		this.mHeight = height;
	}

	void paintBlock(int begin, int end, RGBA rgba_) {
		uint rgba = rgba_.toAbgr;
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

	void paintVerticalLine(int x, RGBA rgba_) {
		paintBlock(x,x+1,rgba_);
	}

	int levelToPixel(float level) {
		return cast(int) ceil(level * (mWidth-1));
	}

}