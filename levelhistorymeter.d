module levelhistorymeter;

import vumeterbase;
import analyser;

import util;

//version=paintAccents;

class LevelHistoryMeter : VuMeterBase {
	private {
	    Analyser analyser;

		int xToHistoryIdx(int x) {
			int idx = cast(int)( (cast(real)x) / mWidth * analyser.levelHistory.history.length );
			idx += analyser.levelHistory.writeIdx;
			idx %= analyser.levelHistory.history.length;
			return idx;
		}

	}

	this(int width, int height, Analyser analyser_) {
		super(width, height);
		analyser = analyser_;
	}

	const RGBA bgColor = RGBA(0, 0, 64);
	const RGBA ignoredColor = RGBA(0, 130, 0);
	const RGBA accountedColor = RGBA(0, 200, 0);
	const RGBA peakColor = RGBA(180, 60, 0);
	const RGBA averageColor = RGBA(128, 0, 128);
	const RGBA loudnessColor = RGBA(200, 200, 0); // yellow

	float levelMultiplier = 1f;

	bool zoom2x, zoom4x;

	void paint() {
		paintBlock(0, mWidth, bgColor);

		if (analyser.levelFilter.maxLevel < 0.5) zoom2x = true;
		if (analyser.levelFilter.maxLevel < 0.25) zoom4x = true;

		if (zoom2x && analyser.levelFilter.maxLevel > 0.6) zoom2x = false;
		if (zoom4x && analyser.levelFilter.maxLevel > 0.35) zoom4x = false;

		if (zoom4x)
			levelMultiplier = 1f/0.35; // 1/0.35 = 2.857
		else if (zoom2x)
			levelMultiplier = 1f/0.6;  // 1/0.6 = 1.6666
		else
			levelMultiplier = 1f;

		foreach(x; 0 .. mWidth) {
			int idx = xToHistoryIdx(x);
			float level = analyser.levelHistory.history[idx];
	
			RGBA color = accountedColor;
			RGBA accentColor = color;
			ubyte classification = analyser.levelFilter.sampleClassification(idx);
			if (classification == LevelFilter.LOW) {
				color = accentColor = ignoredColor;
			}
			else if (classification == LevelFilter.HIGH) {	
				color = ignoredColor;
				accentColor = peakColor;
			}

			int height = cast(int)( levelMultiplier * level * mHeight + 0.5f);
			if (classification == LevelFilter.INCLUDED && height < 1) height = 1;
			if (height > mHeight) {
				info("height > mHeight: ", height, " > ", mHeight, "; level:", level, "; multiplier:", levelMultiplier);
				height = mHeight;
			}
			paintVerticalLine(x, height, color, accentColor);

			paintPixel(x, levelToY(analyser.levelFilter.averages[idx]), averageColor);
			paintPixel(x, levelToY(analyser.loudnessComputer.history[idx]), loudnessColor);

		}
	}

	int levelToY(float level) {
		int y = cast(int)( levelMultiplier * level * (mHeight-1) + 0.5f);
		if (y < 0) y = 0;
		if (y >= mHeight) y = mHeight-1;
		return y;
	}
}

unittest {
	float level = 1.0f;
	foreach(mHeight; 0 .. 200) {
		int height = cast(int)( level * mHeight + 0.5f);
		assert(height == mHeight);
	}
}