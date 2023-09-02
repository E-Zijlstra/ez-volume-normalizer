module ui.analysergraph;

import ui.vumeterbase;
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
	const RGBA discardedColor = RGBA(0, 135, 0);
	const RGBA accountedColor = RGBA(0, 200, 0);
	const RGBA boostedColor = RGBA(0, 240, 0);
	const RGBA deboostedColor = RGBA(0, 100, 0);
	const RGBA boostedColorInactive = RGBA(0, 160, 0);
	const RGBA deboostedColorInactive = RGBA(0, 90, 0);

	const RGBA averageColor = RGBA(200, 0, 200);
	const RGBA loudnessColor = RGBA(200, 200, 0); // yellow

	float levelMultiplier = 1f;


	void paint() {
		paintBlock(0, mWidth, bgColor);
		updateVerticalZoom();

		foreach(x; 0 .. mWidth) {
			int idx = xToHistoryIdx(x);
			float level = clamp01(analyser.levelHistory.samples[idx]);
			float levelUncorrected = clamp01(analyser.levelHistory.samplesUncorrected[idx]);

			RGBA color;
			ubyte classification = analyser.levelFilter.sampleClassification(idx);
			if (classification == LevelFilter.EXPIRED) {
				color = discardedColor;
			}
			else if (classification == LevelFilter.LOW) {
				color = ignoredColor;
			}
			else if (classification == LevelFilter.HIGH) {	
				color = ignoredColor;
			}
			else if (classification == LevelFilter.INCLUDED) {
				color = accountedColor;
			}
			else {
				// unclassified, sample from before before starting the analyser
				color = discardedColor;
			}

			int y = levelToY(level);
			int yUncorrected = levelToY(levelUncorrected);

			try {
				// deboosted level
				if (y < yUncorrected) {
					paintVerticalLine(x, 0, y, color);
					paintVerticalLine(x, y+1, yUncorrected, classification == LevelFilter.INCLUDED ? deboostedColor : deboostedColorInactive);
				}
				// boosted level
				else if (y > yUncorrected) {
					paintVerticalLine(x, 0, yUncorrected, color);
					paintVerticalLine(x, yUncorrected+1, y, classification == LevelFilter.INCLUDED ? boostedColor : boostedColorInactive);
				}	
				else {
					paintVerticalLine(x, 0, y, color);
				}
			}catch(Throwable e) {
				info(e.info);
				info(e.message, "\n mHeight:", mHeight, "; x:", x, "; y:", y, "; yUncorrected: ", yUncorrected, "; level:", level, "; multiplier:", levelMultiplier, "; idx:", idx);
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