module distributionmeter;

import vumeterbase;
import leveldistribution;

import util;

class DistributionMeter : VuMeterBase {
	private {
		LevelDistribution distribution;
	}

	this(int width, int height, LevelDistribution levDist) {
		super(width, height);
		distribution = levDist;
	}

	const RGBA color = RGBA(0, 0xff, 0);
	const RGBA bgColor = RGBA(0, 0, 128);
	const RGBA loudnessColor = RGBA(200, 0, 0);

	void paint(float loudness) {
		paintBlock(0, mWidth, bgColor);

		real step = 1.0 / mWidth; // step in level per pixel
		int x0 = cast(int)( distribution.levelByBucketIdx(distribution.lowerBucketIdx  ) * mWidth );
		int x1 = cast(int)( distribution.levelByBucketIdx(distribution.upperBucketIdx+1) * mWidth );
		float level = ((cast(float)x0)+0.5f) * step;  // level in the middle of the pixel
		foreach(xPixel; x0 .. x1) {
			float brightness = distribution.levelHitCountNormalized(level);
			assert(brightness <= 1f);
			paintVerticalLine(xPixel, color * cast(float)brightness);
			level += step;
		}

		int xLoudness = cast(int)( loudness * mWidth );
		paintVerticalLine(xLoudness, loudnessColor);
	}


}