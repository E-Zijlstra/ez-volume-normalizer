module ui.vumeterbase;

import std.math;

import gdkpixbuf.Pixbuf;
import util;

class VuMeterBase {
public:
	@property Pixbuf pixbuf() { return mPixbuf; }

protected:
final:
	Pixbuf mPixbuf;
	int mWidth, mHeight, mHeightMinusOne;

	this(int width, int height) {
		mPixbuf = new Pixbuf(GdkColorspace.RGB, true, 8, width, height);
		this.mWidth = width;
		this.mHeight = height;
		this.mHeightMinusOne = height - 1;
	}

	void paintBlock(int begin, int end, RGBA rgba_) {
		uint rgba = rgba_.toUint;
		int stride = mPixbuf.getRowstride() / 4;
		char[] cdata = mPixbuf.getPixelsWithLength();
		uint[] data = cast(uint[]) cdata;

		int idx = 0;
		foreach(y; 0..mHeight) {
			idx = y * stride + begin;
			foreach(x; begin .. end) {
				data[idx++] = rgba;
			}
		}
	}

	void paintVerticalLine(int x, RGBA rgba_) {
		uint rgba = rgba_.toUint;
   		int stride = mPixbuf.getRowstride() / 4;
		char[] cdata = mPixbuf.getPixelsWithLength();
		uint[] data = cast(uint[]) cdata;

		int idx = x;
		foreach(y; 0..mHeight) {
  			data[idx] = rgba;
			idx += stride;
		}
	}

	void paintVerticalLine(int x, int y0, int y1, RGBA rgba_) {
		assert(y1 >= y0);
		int height = y1 - y0 +1;
		if (height <= 0) return;

		uint rgba = rgba_.toUint;
	   	int stride = mPixbuf.getRowstride() / 4;
		uint[] data = cast(uint[]) mPixbuf.getPixelsWithLength();

		int idx = (mHeight - y1 - 1) * stride + x;

		foreach(y_; 0..height) {
  			data[idx] = rgba;
			idx += stride;
		}
	}


	void paintPixel(int x, int y, RGBA color) {
		y = mHeightMinusOne - y;
		uint rgba = color.toUint;
		int idx = y * mPixbuf.getRowstride() / 4 + x;
		char[] cdata = mPixbuf.getPixelsWithLength();
		uint[] data = cast(uint[]) cdata;
		data[idx] = rgba;
	}

	int levelToPixel(float level) {
		return cast(int) ceil(level * (mWidth-1));
	}

}