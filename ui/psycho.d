module ui.psycho;

import std.stdio;
import std.conv;
import core.time;
import std.algorithm;

import util;
import worker;

import ui.helpers;
import ui.VolumeNormalizer;
import ui.vumeter;


class PsychoAccoustics {
	private {
		UI vn;
		CheckButton uiEnable;
		LevelBar uiLevel;
		LevelBar uiHighLevel;
		LevelBar uiCorrection;
		SpinButton uiTime;

		const levelCss = "
			levelbar block.full {
			background-color: red;
			border-style: solid;
			border-color: black;
			border-width: 1px;
			}
			levelbar block.high {
			background-color: lime;
			border-style: solid;
			border-color: black;
			border-width: 1px;
			}
			levelbar block.low {
			background-color: lime;
			border-style: solid;
			border-color: black;
			border-width: 1px;
			}
			";
	}

	@property bool enabled() { return uiEnable.getActive(); }
	@property Worker worker() { return vn.worker; }

	void updateDisplay() {
		if (!enabled) return;

		Worker worker = this.worker;
		float l = worker.psychoAcoustics.lowLevel.remapDb(-30);
		float h = worker.psychoAcoustics.highLevel.remapDb(-30);
		float c = 1 - worker.psychoAcoustics.correction.remapDb(worker.psychoAcoustics.lowGain);
		uiLevel.setValue(l);
 		uiHighLevel.setValue(h);
		uiCorrection.setValue(c);
	}

	this(UI vn_, Box parent) {
		vn = vn_;

		Box frame = parent.addFrame("low boost").addHButtonBox();
		frame.setSizeRequest(200,0);
		uiEnable = withTopLabel(frame, "active", new CheckButton(""));
		uiEnable.addOnToggled( (btn) {
			worker.psychoAcousticsEnabled = btn.getActive();
			worker.stream.highQuality = btn.getActive();
			uiLevel.setValue(0.5);
		});
		uiTime = withTopLabel(frame, "window (ms)", new SpinButton(100, 5000, 100));
		uiTime.addOnValueChanged((SpinButton btn) {
			worker.psychoAcoustics.setTime(btn.getValue()/1000.0);
		});
		uiTime.setValue(300f);

		uiLevel = makeLevelMeter();
		frame.add(uiLevel);
		uiHighLevel = makeLevelMeter();
		frame.add(uiHighLevel);
		uiCorrection = makeLevelMeter(false);
		frame.add(uiCorrection);
	}

	LevelBar makeLevelMeter(bool inverted = true) {
		auto bar = levelMeter(5, false, false);
		bar.setInverted(inverted);
		bar.setMinValue(0);
		bar.setMaxValue(1);
		bar.setMarginTop(0);
		bar.setMarginBottom(0);
		bar.setVexpand(true);
		bar.setValue(0.5);
		bar.setMarginLeft(1);
		//bar.addStyle(levelCss);
		return bar;
	}

}
