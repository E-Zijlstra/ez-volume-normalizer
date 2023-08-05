module VolumeNormalizer;

import std.stdio;
import std.conv;
import core.time;
import std.algorithm;

import gdk.Threads;
import gtk.MainWindow;
import gtk.Label;
import gtk.LevelBar;
import gtk.Box;
import gtk.Button;
import gtk.Main;
import gtk.Switch;
import gtk.Range;
import gtk.Scale;
import gtk.Entry;
import gtk.SpinButton;
import gtk.CssProvider;
import gtk.StyleContext;
import gtk.Frame;
import gtk.HSeparator;
import gtk.Image;
import gtk.CheckButton;
import gtk.ComboBoxText;
import gtk.Menu;
import gtk.MenuItem;

import util;
import worker;
import vumeter;
import analysergraph;
import streamlistener;
import settings;

import core.sys.windows.windows;
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

	Menu volumePopup;

	Worker worker;
	StreamEndpoint[] endpoints;

	bool wasRunning = true;
	bool volumeSliderInDb = false;

	const levelCss = "
		levelbar block.full {
		background-color: red;
		border-style: solid;
		border-color: black;
		border-width: 1px;
		}
		levelbar block.high {
		background-color: green;
		border-style: solid;
		border-color: black;
		border-width: 1px;
		}
	";

	const limiterCss = "
		levelbar block.filled {
			background-color: red;
		}
		";

	void open() {
		worker = new Worker();
		endpoints = worker.stream.getEndpoints();
		win = new MainWindow("EZ Volume Normalizer 0.7  -  github.com/E-Zijlstra/ez-volume-normalizer");
		win.setDefaultSize(630, 300);

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
			hbox.add(uiEnableNormalizer = new CheckButton("active", (CheckButton b){ worker.setOverride(!b.getActive());} ));

			hbox.add(new Label("down delay\n(seconds):"));
			hbox.add(uiAvgLength = new SpinButton(1, 30, 1));
			uiAvgLength.setMarginRight(15);
			hbox.add(new Label("slowness\n(bars x5):"));
			hbox.add(uiNumLoudnessBars = new SpinButton(1, 30, 1));
			uiAvgLength.addOnValueChanged((SpinButton e) { worker.analyser.setAverageLength(cast(int)e.getValue()); });
			uiNumLoudnessBars.addOnValueChanged((SpinButton e) { worker.analyser.setNumLoudnessBars(cast(int)e.getValue()); });
		}



		{   // limiter
			Box frame = addFrame(vleft, "Limiter");

			frame.add(uiLimiterAttn = levelMeter(12));
			uiLimiterAttn.addStyle(limiterCss);
			uiLimiterAttn.setMarginTop(0);
			Box hbox0 = new Box(GtkOrientation.HORIZONTAL, 0);
			frame.add(hbox0);
			uiEnableLimiter = wrapTopLabel(hbox0, "active", new CheckButton(null, (CheckButton b){ worker.mLimiter.enabled = b.getActive();} ));

			Box vbox = new Box(GtkOrientation.VERTICAL, 0);
			hbox0.add(vbox);
			Box hbox1 = addHButtonBox(vbox);
			Box hbox2 = addHButtonBox(vbox);

			uiLimiterStart = wrapTopLabel(hbox1, "start offset (dB)", new SpinButton(-24, 24, 0.1));
			uiLimiterWidth = wrapTopLabel(hbox1, "width (dB)", new SpinButton(0.1, 24, 0.1));
			uiLimiterAttack = wrapTopLabel(hbox1, "attack (ms)", new SpinButton(0, 1000, 10));
			uiLimiterHold = wrapTopLabel(hbox1, "lookback (ms)", new SpinButton(0, 10000, 10));
			uiLimiterRelease = wrapTopLabel(hbox1, "release (dB/s)", new SpinButton(0.5, 80, 0.25));

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
			//uiMasterVolume.addOnButtonPress( (GdkEventButton* b, Widget) {
			//    if(b.button == 3) {
			//        volumePopup.showAll();
			//        volumePopup.popupAtPointer(null);
			//        return true;
			//    }
			//    return false;
			//} );
		}

		gdk.Threads.threadsAddTimeout(15, &idle, cast(void*)(this));
		win.addOnDestroy(&onDestroy);
		win.showAll();

		// default values
		uiSettings.setActive(0);
		uiTargetLevel.setValue(-25);
		uiEnableLimiter.setActive(true);
		uiEnableNormalizer.setActive(true);

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
		worker.stream.deviceId = combo.getActiveId();
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

	MonoTime processingStartedAt;

	bool onEnable(bool state, Switch sw) {
		if (state && worker.state == Worker.State.stopped) {
			// switch on
			//worker = new Worker(); problem is that analyserGraph etc still has references to old worker.
			worker.setOutputTargetDb(outputTarget);
			processingStartedAt = MonoTime.currTime;
			worker.processedFrames = 0;
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
		import std.math.exponential;

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

private LevelBar levelMeter(int thickness=5, bool cols=false, bool horizontal = true) {
	auto lb = new LevelBar();
	version(decibels) {
		lb.setMinValue(0);
		lb.setMaxValue(60);
	}
	if (horizontal)
		lb.setProperty("height-request", thickness);
	else {
		lb.setProperty("width-request", thickness);
		lb.setOrientation(GtkOrientation.VERTICAL);
		lb.setInverted(true);
	}
	
	lb.setProperty("margin-left", 10);
	lb.setProperty("margin-right", 10);

	if (!cols) {
		lb.removeOffsetValue(GTK_LEVEL_BAR_OFFSET_LOW);
		lb.removeOffsetValue(GTK_LEVEL_BAR_OFFSET_HIGH);
		lb.removeOffsetValue(GTK_LEVEL_BAR_OFFSET_FULL);
	}

	return lb;
}

private void addStyle(W)(W bar, string style) {
	auto css_provider = new CssProvider();
	css_provider.loadFromData(style);
	bar.getStyleContext().addProvider(css_provider, gtk.c.types.STYLE_PROVIDER_PRIORITY_USER);
}
import gtk.Window;
import gdk.Display;
import gdk.Screen;

private void addGlobalStyle(Window bar, string style) {
	auto css_provider = new CssProvider();
	css_provider.loadFromData(style);
	Display display = bar.getDisplay();
	Screen screen = display.getDefaultScreen();
	bar.getStyleContext().addProviderForScreen(screen, css_provider, gtk.c.types.STYLE_PROVIDER_PRIORITY_USER);
}

private Box addFrame(Box parent, string title) {
	Frame frame = new Frame(title);
	frame.setMarginTop(5);
	frame.setMarginBottom(5);
	frame.setMarginLeft(5);
	frame.setMarginRight(5);
	frame.setLabelAlign(0.05, 0.5);

	parent.add(frame);
	auto vbox = new Box(GtkOrientation.VERTICAL, 0);
	vbox.setMarginTop(4);
	vbox.setMarginBottom(5);
	frame.add(vbox);
	return vbox;
}

import gtk.Widget;
import gtk.Container;
private Box addHButtonBox(Container parent) {
	Box hbox = new Box(GtkOrientation.HORIZONTAL, 5);
	parent.add(hbox);
	hbox.setMarginLeft(10);
	hbox.setMarginRight(10);
	hbox.setMarginTop(1);
	hbox.setMarginBottom(1);
	return hbox;
}

private W wrapTopLabel(P, W: Widget )(P parent, string label, W widget) {
	auto b = new Box(GtkOrientation.VERTICAL, 0);
	b.add(new Label(label));
	b.add(widget);
	widget.setHalign(GtkAlign.CENTER);
	widget.setValign(GtkAlign.CENTER);
	widget.setVexpand(true);
	parent.add(b);
	return widget;
}


class CurveCorrection : ComboBoxText {
	private {
		UI vn;
	}

	this(UI vn_, Container cont) {
		vn = vn_;

		super(false);
		appendText("4");
		appendText("3.5");
		appendText("3.0");
		appendText("2.5");
		appendText("2.0");
		appendText("1.5");
		appendText("1.0");
		appendText("0.75");
		appendText("0.5");
		setTooltipText("Curve correction");
		addOnChanged(&onChanged);
		cont.add(this);
		setActive(6);
	}

	void onChanged(ComboBoxText ct) {
		vn.worker.lowVolumeBoost = ct.getActiveText().to!float;
		vn.worker.setVolumeDb(vn.worker.volumeInterpolator.volumeDb-0.1); // trigger
	}

}

