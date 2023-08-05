module analysergraph;

import vumeterbase;
import analyser;

import util;

//version=paintAccents;

class AnalyserGraph : VuMeterBase {
	private {
	    Analyser analyser;

		int xToHistoryIdx(int x) {
			int idx = cast(int)( (cast(real)x) / mWidth * analyser.levelHistory.samples.length );
			idx += analyser.levelHistory.writeIdx; // at x = 0 this is the oldest sample (next to be overwritten)
			idx %= analyser.levelHistory.samples.length;
			return idx;
		}

	}

	this(int width, int height, Analyser analyser_) {
		super(width, height);
		analyser = analyser_;
	}

	const RGBA bgColor = RGBA(0, 0, 64);
	const RGBA ignoredColor = RGBA(0, 130, 0);
	const RGBA discardedColor = RGBA(0, 140, 0);
	const RGBA accountedColor = RGBA(0, 200, 0);
	const RGBA peakColor = RGBA(180, 60, 0);
	const RGBA averageColor = RGBA(200, 0, 200);
	const RGBA loudnessColor = RGBA(200, 200, 0); // yellow

	float levelMultiplier = 1f;


	void paint() {
		paintBlock(0, mWidth, bgColor);
		updateVerticalZoom();

		foreach(x; 0 .. mWidth) {
			int idx = xToHistoryIdx(x);
			float level = analyser.levelHistory.samples[idx];

			RGBA color;
			RGBA accentColor;
			ubyte classification = analyser.levelFilter.sampleClassification(idx);
			if (classification == LevelFilter.EXPIRED) {
				accentColor = color = discardedColor;
			}
			else if (classification == LevelFilter.LOW) {
				color = accentColor = ignoredColor;
			}
			else if (classification == LevelFilter.HIGH) {	
				color = ignoredColor;
				accentColor = peakColor;
			}
			else if (classification == LevelFilter.INCLUDED) {
				color = accentColor = accountedColor;
			}
			else {
				// unclassified, sample from before the beginning of time...
				accentColor = color = discardedColor;
			}


			int height = cast(int)( levelMultiplier * level * mHeight + 0.5f);
			if (classification == LevelFilter.INCLUDED && height < 1) height = 1;

			try {
				paintVerticalLine(x, height, color, accentColor);
			}catch(Throwable e) {
				info(e.message, "\n x:", x, "; height:", height, "; x: ", x, "; level:", level, "; multiplier:", levelMultiplier, "; idx:", idx);
			}

			paintPixel(x, levelToY(analyser.levelFilter.averages[idx]), averageColor);
			paintPixel(x, levelToY(analyser.loudnessComputer.history[idx]), loudnessColor);

		}
	}

	void updateVerticalZoom() {
		import std.algorithm : min, max;
		float zoomTarget = 1f / max(0.001, analyser.levelFilter.maxLevel);
		if (zoomTarget < levelMultiplier) {
			if (zoomTarget < 1.2) zoomTarget = 1f;
			levelMultiplier = zoomTarget;
		}
		// slowely increase zoom
		else if (zoomTarget-0.6 > levelMultiplier) { // 0.6 hysteresis
			float step = max(0.01, (zoomTarget - levelMultiplier) / 10); // 0.01 minimum step
			levelMultiplier = min(zoomTarget-0.3, levelMultiplier+step); // min(-0.3) to avoid overzooming
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