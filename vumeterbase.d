module vumeterbase;

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
		uint rgba = rgba_.toUint;
   		int stride = mPixbuf.getRowstride() / 4;
		char[] cdata = mPixbuf.getPixelsWithLength();
		uint[] data = cast(uint[]) cdata;  // assuming rgba format ... (!)

		int idx = x;
		foreach(y; 0..mHeight) {
  			data[idx] = rgba;
			idx += stride;
		}
	}

	void paintVerticalLine(int x, int height, RGBA barColor, RGBA accentColor) {
		uint barRgba = barColor.toUint;
		uint accentRgba = accentColor.toUint;
	   	int stride = mPixbuf.getRowstride() / 4;
		char[] cdata = mPixbuf.getPixelsWithLength();
		uint[] data = cast(uint[]) cdata;  // assuming rgba format ... (!)

		int idx = (mHeight-1 - height) * stride + x;
		if (height > 0) {
			data[idx] = accentRgba;
			idx += stride;
		}
		foreach(y_; 1..height) {
  			data[idx] = barRgba;
			idx += stride;
		}
	}

	void paintPixel(int x, int y, RGBA color) {
		y = mHeightMinusOne - y;
		uint rgba = color.toUint;
		int idx = y * mPixbuf.getRowstride() / 4 + x;
		char[] cdata = mPixbuf.getPixelsWithLength();
		uint[] data = cast(uint[]) cdata;  // assuming rgba format ... (!)
		data[idx] = rgba;
	}

	int levelToPixel(float level) {
		return cast(int) ceil(level * (mWidth-1));
	}

}