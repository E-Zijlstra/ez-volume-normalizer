module ui.VolumeNormalizer;

import std.stdio;
import std.conv;
import core.time;
import std.algorithm;

import ui.helpers;

import util;
import worker;
import ui.vumeter;
import ui.analysergraph;
import streamlistener;
import ui.settings;

import std.string;

class UI {
	static void start(string[] args) {
		Main.init(args);
		auto ui = new UI();
		ui.open();
		Main.run();
	}

	@property minDb() {
		return VolumeInterpolator.minimumVolumeDbCutOff;
	}

	const int vuMeterHeight = 20;
	MainWindow win;

	Switch uiEnable;
	ComboBoxText uiDevice;
	Label uiDeviceInfo;
	ComboBoxText uiSettings;
	CurveCorrection uiCurveCorrection;

	debug PsychoAccoustics uiPsychoAcoustics;

	Image   uiSignalVuImg;
	VuMeter uiSignalVu;
	Image uiOutputVuImg;
	VuMeter uiOutputVu;
	Scale uiTargetLevel;

	CheckButton uiEnableNormalizer;
	Image analyserGraphImg;
	AnalyserGraph analyserGraph;
	SpinButton uiAvgLength;
	SpinButton uiNumLoudnessBars;

	CheckButton uiEnableLimiter;
	SpinButton uiLimiterStart;
	SpinButton uiLimiterWidth;
	SpinButton uiLimiterRelease;
	SpinButton uiLimiterHold;
	SpinButton uiLimiterAttack;
	LevelBar uiLimiterAttn;

	Label uiMasterDecibel;
	Scale uiMasterVolume;

	ContextMenu uiContextMenu;
	Stats uiStats;

	Worker worker;
	StreamEndpoint[] endpoints;

	bool wasRunning = true;
	bool volumeSliderInDb = false;

	const limiterCss = "
		levelbar block.filled {
			background-color: red;
		}
		";

	void open() {
		worker = new Worker();
		endpoints = worker.stream.getEndpoints();
		win = new MainWindow("EZ Volume Normalizer 0.7.2  -  github.com/E-Zijlstra/ez-volume-normalizer");
		win.setDefaultSize(630, 300);
		win.modifyFont("Calibri", 8);

		Box mainVsplit = new Box(GtkOrientation.VERTICAL, 0);
		win.add(mainVsplit);
		Box topRow = new Box(GtkOrientation.HORIZONTAL, 0);
		mainVsplit.add(topRow);
		auto leftrightSplit = new Box(GtkOrientation.HORIZONTAL, 0);
		mainVsplit.add(leftrightSplit);
		Box vleft;
		const vleftWidth = 680 ;// 580;
		leftrightSplit.add(vleft = new Box(GtkOrientation.VERTICAL, 0));
		vleft.setProperty("width-request", vleftWidth);

		{	// device bar
			Box frame = topRow.addFrame("device").addHButtonBox();
			frame.setOrientation(GtkOrientation.HORIZONTAL);
			frame.add(uiEnable = new Switch());
			uiEnable.setValign(GtkAlign.CENTER);
			uiEnable.addOnStateSet(&onEnable);
			uiEnable.setTooltipText("Power");

			frame.add(uiDevice = new ComboBoxText(false));
			uiDevice.addOnChanged(&onDeviceChanged);
			foreach(ep; endpoints) {
				uiDevice.append(ep.id, ep.name);
			}
			uiDevice.setActive(cast(int) endpoints.countUntil!(ep => ep.isDefault));

			Box devInfo = new Box(GtkOrientation.VERTICAL, 0);
			devInfo.setSizeRequest(80,0);
			frame.add(devInfo);
			devInfo.setVexpand(false);
			devInfo.setValign(GtkAlign.CENTER);
			devInfo.add(uiDeviceInfo = new Label("No power"));
			devInfo.add(uiMasterDecibel = new Label("0 dB"));

			uiCurveCorrection = new CurveCorrection(this, frame);
		}

		{
			Box frame = topRow.addFrame("preset").addHButtonBox();
			frame.add(uiSettings = new ComboBoxText(false));
			uiSettings.addOnChanged(&onSettingsChanged);
			foreach(idx, ref const Settings* s; Settings.all) {
				uiSettings.appendText(s.name);
			}
		}

		debug uiPsychoAcoustics = new PsychoAccoustics(this, topRow);


		{	// vu meters
			Box frame = addFrame(vleft, "input / output");
			frame.add(uiSignalVuImg = new Image());
			uiSignalVu = new VuMeter(vleftWidth - 38, vuMeterHeight );
			uiSignalVuImg.setMarginBottom(1);
			frame.add(uiOutputVuImg = new Image());
			uiOutputVu = new VuMeter(vleftWidth - 38, vuMeterHeight);
		}

		{   // target
			Box frame = addFrame(vleft, "target");
			frame.add(uiTargetLevel = new Scale(GtkOrientation.HORIZONTAL, minDb, 0, 1));
			uiTargetLevel.addOnValueChanged((Range r) { setOutputTarget(uiTargetLevel.getValue()); });
		}

		{	// normalizer
			Box frame = addFrame(vleft, "normalizer");
			frame.setSpacing(5);

			frame.add(analyserGraphImg = new Image());
			analyserGraph = new AnalyserGraph(vleftWidth - 38, 60, worker.analyser);

			Box hbox = addHButtonBox(frame);
			uiEnableNormalizer = hbox.withTopLabel("active", new CheckButton("", (CheckButton b){ worker.setOverride(!b.getActive());} ));

			uiAvgLength = new SpinButton(1, 30, 1);
			hbox.withTopLabel("selector (s)", uiAvgLength, "Increase to ignore quiet parts");
			uiAvgLength.setMarginRight(15);
			uiAvgLength.addOnValueChanged((SpinButton e) { worker.analyser.setAverageLength(cast(int)e.getValue()); });

			uiNumLoudnessBars = new SpinButton(1, 30, 1);
			hbox.withTopLabel("stability (s)", uiNumLoudnessBars, "Decrease to converge more quickly");
			uiNumLoudnessBars.addOnValueChanged((SpinButton e) { worker.analyser.setNumLoudnessBars(cast(int)e.getValue()); });
		}



		{   // limiter
			Box frame = addFrame(vleft, "Limiter");

			frame.add(uiLimiterAttn = levelMeter(12));
			uiLimiterAttn.addStyle(limiterCss);
			uiLimiterAttn.setMarginTop(0);
			Box hbox0 = new Box(GtkOrientation.HORIZONTAL, 0);
			frame.add(hbox0);
			uiEnableLimiter = withTopLabel(hbox0, "active", new CheckButton(null, (CheckButton b){ worker.mLimiter.enabled = b.getActive();} ));

			Box vbox = new Box(GtkOrientation.VERTICAL, 0);
			hbox0.add(vbox);
			Box hbox1 = addHButtonBox(vbox);
			Box hbox2 = addHButtonBox(vbox);

			uiLimiterStart = withTopLabel(hbox1, "start offset (dB)", new SpinButton(-24, 24, 0.1));
			uiLimiterWidth = withTopLabel(hbox1, "width (dB)", new SpinButton(0.1, 24, 0.1));
			uiLimiterAttack = withTopLabel(hbox1, "attack (ms)", new SpinButton(0, 500, 5));
			uiLimiterHold = withTopLabel(hbox1, "hold (ms)", new SpinButton(0, 10000, 10));
			uiLimiterRelease = withTopLabel(hbox1, "release (dB/s)", new SpinButton(0.5, 80, 0.25));

			uiLimiterStart.addOnValueChanged( (SpinButton e) { setLimiterParameters(); } );
			uiLimiterWidth.addOnValueChanged( (SpinButton e) { setLimiterParameters(); } );
			uiLimiterAttack.addOnValueChanged( (SpinButton e) { setLimiterParameters(); } );
			uiLimiterRelease.addOnValueChanged( (SpinButton e) { setLimiterParameters(); } );
			uiLimiterHold.addOnValueChanged( (SpinButton e) { setLimiterParameters(); } );
			uiLimiterStart.setDigits(2);
			uiLimiterWidth.setDigits(2);
			uiLimiterRelease.setDigits(2);

		}
		// VOLUME CTRL
		Box volPanel;
		leftrightSplit.add(volPanel = new Box(GtkOrientation.VERTICAL, 0));
		Box volPane = addFrame(volPanel, "volume");
		volPane.setBorderWidth(4);
		volPane.setSpacing(5);

		{
			Box volCtrl = volPane;
			volCtrl.add(uiMasterVolume = new Scale(GtkOrientation.VERTICAL, minDb, 0, 0.1));
			uiMasterVolume.setVexpand(true);
			uiMasterVolume.setInverted(true);
			uiMasterVolume.setDrawValue(true);
			uiMasterVolume.addOnValueChanged(&volumeSliderChanged);
		}

		gdk.Threads.threadsAddTimeout(15, &idle, cast(void*)(this));
		win.addOnDestroy(&onDestroy);
		win.showAll();

		// default values
		uiSettings.setActive(0);
		uiTargetLevel.setValue(-28);
		uiEnableLimiter.setActive(true);
		uiEnableNormalizer.setActive(true);

		uiContextMenu = new ContextMenu(this, win);
		uiStats = new Stats(this);

		displayProcessing();


	}


	void onDestroy(Widget w) {
		worker.stop();
		Main.quit();
	}

	void onSettingsChanged(ComboBoxText combo) {
		applySettings(Settings.all[combo.getActive()]);
	}

	void applySettings(const Settings* s) {
		uiAvgLength.setValue(s.avgLength);
		uiNumLoudnessBars.setValue(s.numBars);
		uiLimiterStart.setValue(s.limiterOffset);
		uiLimiterWidth.setValue(s.limiterWidth);
		uiLimiterRelease.setValue(s.limiterDecay);
		uiLimiterHold.setValue(s.limiterHold);
		uiLimiterAttack.setValue(s.limiterAttack);
	}

	void onDeviceChanged(ComboBoxText combo) {
		worker.setDeviceId(combo.getActiveId());
		info("device changed to", combo.getActiveId());
		if (worker.state == Worker.State.running) {
			worker.stop();
			worker.start();
		}
		displayDeviceStatus();
	}

	void setLimiterParameters() {
		try {
			worker.syncLimiter( (l) {
				l.releasePerSecond = uiLimiterRelease.getValue();
				l.holdTimeMs = cast(uint) uiLimiterHold.getValue();
				l.limitT = limitT();
				l.limitW = limitW();
				l.attackMs = uiLimiterAttack.getValue();
			});
			showLimiterMarks();
		} catch(Exception e) {}
	}

	float clampVolume(float v) {
		return clampAB(v, minDb, 0);
	}

	void showLimiterMarks() {
		uiTargetLevel.clearMarks();
		uiTargetLevel.addMark(clampVolume(outputLimitStart), GtkPositionType.BOTTOM, "C");
		uiTargetLevel.addMark(clampVolume(outputLimitEnd), GtkPositionType.BOTTOM, "L");
	}

	void setOutputTarget(float value) {
		worker.setOutputTargetDb(value);
		setLimiterParameters();
		showLimiterMarks();
	}


	bool onEnable(bool state, Switch sw) {
		if (state && worker.state == Worker.State.stopped) {
			// switch on
			//worker = new Worker(); problem is that analyserGraph etc still has references to old worker.
			worker.setOutputTargetDb(outputTarget);
			worker.start();
		}
		else if (worker && worker.state == Worker.State.running) {
			worker.stop();
			info("worker disabled");
		}
		return false;
	}


	Worker.State wasState = Worker.State.stopped;

	void displayDeviceStatus() {
		Worker.State state = worker ? worker.state : Worker.State.stopped;

		if (wasState == state) return;
		wasState = state;

		if (!worker) {
			uiDeviceInfo.setLabel("Error");
			return;
		}
		switch(worker.state) {
			case Worker.State.stopped:
				uiDeviceInfo.setLabel("Stopped");
				//uiEnable.setState(false);
				break;
			case Worker.State.starting: uiDeviceInfo.setLabel("Starting"); break;
			case Worker.State.running:
				uiDeviceInfo.setLabel(worker.stream.sampleRate.tos ~ "Hz, " ~ worker.stream.bps.tos ~ "b " );
				//uiEnable.setState(true);
				break;
			case Worker.State.stopping: uiDeviceInfo.setLabel("Stopping"); break;
			default:
				assert(0);
		}
	}

	float autoSetVolume = 1;

	void volumeSliderChanged(Range r) {
		float sliderVolume = uiMasterVolume.getValue();
		if (sliderVolume == autoSetVolume) return;

		worker.setVolumeDb(sliderVolume);
	}

	uint analyserUpdateTicks =99;

	void displayProcessing() {
		uiMasterDecibel.setLabel(format("%06.2f dB", worker.actualVolumeDb));

		// input
		uiSignalVu.minDb = minDb;
		uiSignalVu.paintDb(worker.signalDb, inputLimitStart, inputLimitEnd);
		uiSignalVuImg.setFromPixbuf(uiSignalVu.pixbuf);

		// output
		uiOutputVu.minDb = minDb;
		uiOutputVu.paintDb(worker.limitedSignalDb, outputLimitStart, outputLimitEnd);
		uiOutputVuImg.setFromPixbuf(uiOutputVu.pixbuf);

		// analyser
		if (worker.analyser.updateTicks != analyserUpdateTicks) {
			analyserUpdateTicks = worker.analyser.updateTicks;
			analyserGraph.paint();
			analyserGraphImg.setFromPixbuf(analyserGraph.pixbuf);
		}

		// limiter
		float normalizedAttenuation = 1f - worker.volumeInterpolator.mapDbTo01(worker.mLimiter.attenuationDb);
		uiLimiterAttn.setValue(normalizedAttenuation);

		// volume slider
		autoSetVolume = worker.volumeInterpolator.volumeDb;
		uiMasterVolume.setValue(autoSetVolume);

		// other
		debug uiPsychoAcoustics.updateDisplay();
		uiStats.updateDisplay();
	}


	// https://github.com/gtkd-developers/GtkD/blob/master/demos/gtkD/DemoMultithread/DemoMultithread.d
	extern(C) nothrow static int idle(void* userData) {
		try{
			UI ui = cast(UI) userData;
			ui.displayDeviceStatus();

			if (ui.worker.state != Worker.State.stopped) {
				ui.displayProcessing();
			}

			return 1;
		} catch (Throwable t) {
			try {
				info("******* idle exception *******");
				info(t.message);
				info(t.file);
				info(t.info);
			} catch(Throwable t) {}
			return 1;
		}
	}


	@property float outputTarget() {
		return uiTargetLevel.getValue();
	}

	@property float limiterOffset() {
		return uiLimiterStart.getValue();
	}

	@property float limiterWidth() {
		return uiLimiterWidth.getValue();
	}

	@property float limitT() {
		return toLinear(outputTarget + limiterOffset) + limitW;
	}

	@property float limitW() {
		float start = outputTarget + limiterOffset;
		float end = start + limiterWidth;
		return (toLinear(end) - toLinear(start));
	}

	// limiter range on meters 

	@property float inputLimitStart() {
		return outputLimitStart - worker.volumeInterpolator.volumeDb;
	}

	@property float inputLimitEnd() {
		return outputLimitEndPreLimiter - worker.volumeInterpolator.volumeDb;
	}

	@property float outputLimitStart() {
		return outputTarget + limiterOffset;
	}

	@property float outputLimitEnd() {
		return outputTarget + limiterOffset + limiterWidth;
	}

	@property float outputLimitEndPreLimiter() {
		return outputTarget + limiterOffset + limiterWidth + limiterWidth;
	}

}


class CurveCorrection : ComboBoxText {
	private {
		UI vn;
	}

	this(UI vn_, Container parent) {
		vn = vn_;

		super(false);
		appendText(" 00 %");
		appendText(" 30 %");
		appendText(" 60 %");
		appendText("100 %");
		appendText("150 %"); 
		appendText("220 %");
		appendText("300 %");
		setTooltipText("Volume slider curve. Boosts lower levels. (% at -20dB)");
		addOnChanged(&onChanged);
		parent.add(this);
		setActive(0);
	}

	const float[] dbMultipliers = [1.0, 0.888, 0.8, 0.7, 0.6, 0.5, 0.4];

	void onChanged(ComboBoxText ct) {
		vn.worker.lowVolumeBoost = dbMultipliers[ct.getActive()].to!float;
		vn.worker.setEndpointVolumeForced();
	}
}

class PsychoAccoustics {
	private {
		UI vn;
		CheckButton uiEnable;
		LevelBar uiAdjustmentLevel;
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

		float perception = worker.psychoAcoustics.perception;
		uiAdjustmentLevel.setValue(perception);
	}

	this(UI vn_, Box parent) {
		vn = vn_;

		Box frame = parent.addFrame("low frequency boost").addHButtonBox();
		frame.setSizeRequest(200,0);
		uiAdjustmentLevel = levelMeter(5, false, false);
		uiAdjustmentLevel.setInverted(true);
		uiAdjustmentLevel.setMinValue(0);
		uiAdjustmentLevel.setMaxValue(1);
		uiAdjustmentLevel.setMarginTop(0);
		uiAdjustmentLevel.setMarginBottom(0);
		uiAdjustmentLevel.setVexpand(true);
		uiAdjustmentLevel.setValue(0.5);
		uiAdjustmentLevel.addOffsetValue(GTK_LEVEL_BAR_OFFSET_LOW, 0.0);
		uiAdjustmentLevel.addOffsetValue(GTK_LEVEL_BAR_OFFSET_HIGH, 0.5);
		uiAdjustmentLevel.addOffsetValue(GTK_LEVEL_BAR_OFFSET_FULL, 1);
		uiAdjustmentLevel.addStyle(levelCss);
		uiEnable = withTopLabel(frame, "active", new CheckButton(""));
		uiEnable.addOnToggled( (btn) {
			worker.psychoAcousticsEnabled = btn.getActive();
			worker.stream.highQuality = btn.getActive();
			uiAdjustmentLevel.setValue(0.5);
		});
		uiTime = withTopLabel(frame, "window (ms)", new SpinButton(50, 1000, 10));
		uiTime.addOnValueChanged((SpinButton btn) {
			worker.psychoAcoustics.setTime(btn.getValue()/1000.0);
		});
		uiTime.setValue(300f);

		frame.add(uiAdjustmentLevel);
	}
}

import gtk.CheckMenuItem;
class ContextMenu
{
	Menu menu;
	CheckMenuItem highQuality;
	UI vn;

	this(UI vn_, Window parent) {
		vn = vn_;

		menu = new Menu();
		MenuItem stats = new MenuItem("Stats") ;
		menu.append(stats);
		stats.addOnActivate( (MenuItem) => vn.uiStats.open() );

		highQuality = new CheckMenuItem("High Quality");
		highQuality.setActive(vn.worker.stream.highQuality);
		menu.append(highQuality);
		highQuality.addOnActivate( (MenuItem) {
			vn.worker.stream.highQuality = highQuality.getActive();
		});

		parent.addOnButtonPress( (GdkEventButton* b, Widget) {
			if(b.button == 3) {
				highQuality.setActive(vn.worker.stream.highQuality);
				menu.showAll();
				menu.popupAtPointer(null);
				return true;
			}
			else
				return false;
			}
		);
	}
}

class Stats {
	Window window;
	Label samplesPerSecond;
	int correction;
	UI vn;

	this(UI vn_) {
		vn = vn_;
	}

	void open() {
		if (window) return;

		window = new Window("device stats");
		Box vbox = new Box(GtkOrientation.VERTICAL, 5);
		window.add(vbox);
		vbox.add(samplesPerSecond = new Label("nothing here yet"));
		window.showAll();
		window.addOnDestroy( (Widget w) { window = null; });
	}

	void updateDisplay() {
		if (!window) return;
		int jmin = cast(int)vn.worker.deltaExpectedProcessedSamplesMin;
		int jmax = cast(int)vn.worker.deltaExpectedProcessedSamplesMax;
		int total = jmax - jmin + correction;
		if (total > 0) correction -= 1 + total/256;
		if (total < 0) correction += 1 - total/256;

		samplesPerSecond.setLabel("missed frames: " ~
								  total.tos  ~
								  " (" ~ (jmax-jmin).tos ~ ") " ~
								  " [" ~ jmin.tos ~ " ... " ~
								  jmax.tos ~ "]");
	}

}

