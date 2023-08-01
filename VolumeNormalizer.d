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

version=useDecibels;
import core.sys.windows.windows;
import std.string;

class UI {
	static void start(string[] args) {
		Main.init(args);
		auto ui = new UI();
		ui.open();
		Main.run();
	}

	// for controls, meters
	//enum minDb = -60;

	@property minDb() {
		return VolumeInterpolator.minimumVolumeDbCutOff;
		// return worker.volumeInterpolator.minVolumeDb;
	}

	const int vuMeterHeight = 20;
	MainWindow win;

	Button button;
	Switch uiEnable;
	ComboBoxText uiDevice;
	Label uiDeviceInfo;
	Image   uiSignalVuImg;
	VuMeter uiSignalVu;
	Scale uiTargetLevel;

	CheckButton uiEnableNormalizer;
	Image analyserGraphImg;
	AnalyserGraph analyserGraph;
	Image uiOutputVuImg;
	VuMeter uiOutputVu;
	SpinButton uiAvgLength;
	SpinButton uiNumLoudnessBars;

	CheckButton uiEnableLimiter;
	SpinButton uiLimiterStart;
	SpinButton uiLimiterWidth;
	SpinButton uiLimiterRelease;
	SpinButton uiLimiterLookback;
	Image uiOutputLimitedVuImg;
	VuMeter uiOutputLimitedVu;
	LevelBar uiLimiter;

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
		win = new MainWindow("EZ Volume Normalizer 0.6b  -  github.com/E-Zijlstra/ez-volume-normalizer");
		win.setDefaultSize(630, 300);
		//win.addGlobalStyle("window {background: rgb(82,74,67);} spinbutton {background: rgb(82,74,67)}");

		//import gtk.Settings;
		//Settings set = Settings.getDefault();
		//set.setData("gtk-theme-name", cast(void*)"Adwaita".ptr);


		volumePopup = new Menu();
		volumePopup.setTitle("Volume");
		MenuItem uiVolLinear, uiVolLog;
		volumePopup.append(uiVolLinear = new MenuItem("Linear"));
		volumePopup.append(uiVolLog = new MenuItem("Log"));
		uiVolLinear.addOnActivate( (MenuItem) { volumeSliderInDb = false; });
		uiVolLog.addOnActivate( (MenuItem){ volumeSliderInDb = true; });

		auto leftrightSplit = new Box(GtkOrientation.HORIZONTAL, 0);
		win.add(leftrightSplit);
		Box vleft;
		const vleftWidth = 580;
		leftrightSplit.add(vleft = new Box(GtkOrientation.VERTICAL, 0));
		vleft.setProperty("width-request", vleftWidth);

		{	// device bar
			auto frame = new Box(GtkOrientation.HORIZONTAL, 0);
			vleft.add(frame);
			frame.setBorderWidth(10);
			frame.setSpacing(5);
			frame.add(new Label("Power"));
			frame.add(uiEnable = new Switch(), );
			uiEnable.addOnStateSet(&onEnable);

			frame.add(uiDevice = new ComboBoxText(false));
			uiDevice.addOnChanged(&onDeviceChanged);
			foreach(ep; endpoints) {
				uiDevice.append(ep.id, ep.name);
			}
			uiDevice.setActive(cast(int) endpoints.countUntil!(ep => ep.isDefault));

			frame.add(uiDeviceInfo = new Label(""));

			frame.add(uiMasterDecibel = new Label("0 dB"));
		}

		{	// input
			Box frame = addFrame(vleft, "input");

			frame.add(uiSignalVuImg = new Image());
			uiSignalVu = new VuMeter(vleftWidth - 38, vuMeterHeight );
		}

		{   // target
			Box frame = addFrame(vleft, "normalizer target / limiter range");
			version(useDecibels) {
				frame.add(uiTargetLevel = new Scale(GtkOrientation.HORIZONTAL, minDb, 0, 1));
			}else {
				frame.add(uiTargetLevel = new Scale(GtkOrientation.HORIZONTAL, 0.01, 1, 0.01));
			}
			uiTargetLevel.addOnValueChanged((Range r) { setOutputTarget(uiTargetLevel.getValue()); });
		}

		{	// normalizer
			Box frame = addFrame(vleft, "Normalizer");
			frame.setSpacing(5);

			frame.add(analyserGraphImg = new Image());
			analyserGraph = new AnalyserGraph(vleftWidth - 38, 60, worker.analyser);

			Box hbox = new Box(GtkOrientation.HORIZONTAL, 6);
			frame.add(hbox);
			hbox.add(uiEnableNormalizer = new CheckButton("active", (CheckButton b){ worker.setOverride(!b.getActive());} ));

			hbox.add(new Label("down delay\n(seconds):"));
			hbox.add(uiAvgLength = new SpinButton(1, 30, 1));
			uiAvgLength.setMarginRight(15);
			hbox.add(new Label("slowness\n(bars x5):"));
			hbox.add(uiNumLoudnessBars = new SpinButton(1, 30, 1));
			uiAvgLength.addOnValueChanged((SpinButton e) { worker.analyser.setAverageLength(cast(int)e.getValue()); });
			uiNumLoudnessBars.addOnValueChanged((SpinButton e) { worker.analyser.setNumLoudnessBars(cast(int)e.getValue()); });


			frame.add(uiOutputVuImg = new Image());
			uiOutputVu = new VuMeter(vleftWidth - 38, vuMeterHeight );
		}



		{   // limiter
			Box frame = addFrame(vleft, "Limiter");

			frame.add(uiOutputLimitedVuImg = new Image());
			uiOutputLimitedVu = new VuMeter(vleftWidth - 38, vuMeterHeight);

			frame.add(uiLimiter = levelMeter());
			uiLimiter.addStyle(limiterCss);
			uiLimiter.setMarginTop(0);

			Box hbox = new Box(GtkOrientation.HORIZONTAL, 0);
			frame.add(hbox);
			hbox.setBorderWidth(10); hbox.setSpacing(5);
			uiEnableLimiter = wrapTopLabel(hbox, "active", new CheckButton(null, (CheckButton b){ worker.mLimiter.enabled = b.getActive();} ));
			uiLimiterStart = wrapTopLabel(hbox, "start offset (dB)", new SpinButton(-24, 24, 0.1));
			uiLimiterWidth = wrapTopLabel(hbox, "width (dB)", new SpinButton(0.1, 24, 0.1));
			uiLimiterRelease = wrapTopLabel(hbox, "release (dB/s)", new SpinButton(0.5, 80, 0.5));
			uiLimiterLookback = wrapTopLabel(hbox, "look back (ms)", new SpinButton(20, 10000, 10));
			uiLimiterStart.addOnValueChanged( (SpinButton e) { setLimiterParameters(); } );
			uiLimiterWidth.addOnValueChanged( (SpinButton e) { setLimiterParameters(); } );
			uiLimiterRelease.addOnValueChanged( (SpinButton e) { setLimiterParameters(); } );
			uiLimiterLookback.addOnValueChanged( (SpinButton e) { setLimiterParameters(); } );
			uiLimiterStart.setDigits(2);
			uiLimiterWidth.setDigits(2);
			uiLimiterRelease.setDigits(2);

		}
		// VOLUME CTRL
		Box volPanel;
		leftrightSplit.add(volPanel = new Box(GtkOrientation.VERTICAL, 0));
		Box volPane = addFrame(volPanel, "volume", 10);
		volPane.setBorderWidth(4);
		volPane.setSpacing(5);

		{
			Box volCtrl = volPane;
			version(useDecibels) {
				volCtrl.add(uiMasterVolume = new Scale(GtkOrientation.VERTICAL, minDb, 0, 0.1));
			} else {
				volCtrl.add(uiMasterVolume = new Scale(GtkOrientation.VERTICAL, 0, 1, 0.05));
			}
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
		uiLimiterStart.setValue(1.2);
		uiLimiterWidth.setValue(2.0);
		uiLimiterRelease.setValue(6);
		uiLimiterLookback.setValue(1000);
		uiTargetLevel.setValue(-20);
		uiEnableLimiter.setActive(true);
		uiEnableNormalizer.setActive(true);
		uiAvgLength.setValue(15);
		uiNumLoudnessBars.setValue(15);

		displayProcessing();
	}

	void onDestroy(Widget w) {
		worker.stop();
		Main.quit();
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
				l.holdTimeMs = cast(uint) uiLimiterLookback.getValue();
				l.limitT = limitT();
				l.limitW = limitW();
			});
			showLimiterMarks();
		} catch(Exception e) {}
	}

	float clampVolume(float v) {
		version(useDecibels) {
			return clampAB(v, minDb, 0);
		}else {
			return clamp01(v);
		}
	}

	void showLimiterMarks() {
		uiTargetLevel.clearMarks();
		uiTargetLevel.addMark(clampVolume(outputLimitStart), GtkPositionType.BOTTOM, "C");
		uiTargetLevel.addMark(clampVolume(outputLimitEnd), GtkPositionType.BOTTOM, "L");
	}

	void setOutputTarget(float value) {
		version(useDecibels) {
			worker.setOutputTargetDb(value);
		}
		else {
			worker.setOutputTarget(value); 
		}
		setLimiterParameters();
		showLimiterMarks();
	}

	MonoTime processingStartedAt;

	bool onEnable(bool state, Switch sw) {
		if (state && worker.state == Worker.State.stopped) {
			// switch on
			//worker = new Worker(); problem is that analyserGraph etc still has references to old worker.
			version(useDecibels) {
				worker.setOutputTargetDb(outputTarget);
			}else {
				worker.setOutputTarget(uiTargetLevel.getValue());
			}
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

		version(useDecibels) {
			worker.setVolumeDb(sliderVolume);
		}
		else {
			if (volumeSliderInDb)
				worker.setVolumeDb(worker.volumeInterpolator.map01ToDb(scalar));
			else
				worker.setVolume(scalar);
		}
	}

	uint analyserUpdateTicks =99;

	void displayProcessing() {
		import std.math.exponential;

		version(useDecibels) {
			uiSignalVu.minDb = minDb;
			uiSignalVu.paintDb(worker.signalDb, inputLimitStart, inputLimitEnd);
		}
		else
			uiSignalVu.paint(worker.signal, inputLimitStart, inputLimitEnd);
		uiSignalVuImg.setFromPixbuf(uiSignalVu.pixbuf);

		if (worker.analyser.updateTicks != analyserUpdateTicks) {
			analyserUpdateTicks = worker.analyser.updateTicks;
			analyserGraph.paint();
			analyserGraphImg.setFromPixbuf(analyserGraph.pixbuf);
		}

		uiMasterDecibel.setLabel(format("%.2f dB", worker.actualVolumeDb));
		version(useDecibels) {
			autoSetVolume = worker.volumeInterpolator.volumeDb;
		}
		else {
			if (volumeSliderInDb)
				autoSetVolume = worker.volumeInterpolator.mapDbTo01(worker.volumeInterpolator.volumeDb);
			else
				autoSetVolume = worker.volumeInterpolator.volume;
		}

		uiMasterVolume.setValue(autoSetVolume);

		//float volumeDifference = clamp01(worker.volumeInterpolator.volume - worker.mLimiter.limitedVolume);
		float normalizedAttenuation = 1f - worker.volumeInterpolator.mapDbTo01(worker.mLimiter.attenuationDb);
		uiLimiter.setValue(normalizedAttenuation);


		version(useDecibels) {
			uiOutputVu.minDb = minDb;
			uiOutputVu.paintDb(worker.normalizedSignalDb, outputLimitStart, outputLimitEndPreLimiter);
		}
		else
			uiOutputVu.paint(worker.normalizedSignal, outputLimitStart, outputLimitEndPreLimiter);
		uiOutputVuImg.setFromPixbuf(uiOutputVu.pixbuf);

		version(useDecibels) {
			uiOutputLimitedVu.minDb = minDb;
			uiOutputLimitedVu.paintDb(worker.limitedSignalDb, outputLimitStart, outputLimitEnd);
		}
		else
			uiOutputLimitedVu.paint(worker.limitedSignal, outputLimitStart, outputLimitEnd);
		uiOutputLimitedVuImg.setFromPixbuf(uiOutputLimitedVu.pixbuf);
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
		version(useDecibels)
			return uiTargetLevel.getValue();
		else
			return worker.outputTarget;
	}

	@property float limiterOffset() {
		version(useDecibels)
			return uiLimiterStart.getValue();
		else
			return toLinear(uiLimiterStart.getValue());
	}

	@property float limiterWidth() {
		version(useDecibels)
			return uiLimiterWidth.getValue();
		else
			return toLinear(uiLimiterWidth.getValue())-1.0;
	}

	@property float limitT() {
		version(useDecibels) {
			return toLinear(outputTarget + limiterOffset) + limitW;
		}
		else {
			return outputTarget * (limiterOffset + limiterWidth);
		}
	}

	@property float limitW() {
		version(useDecibels) {
			float start = outputTarget + limiterOffset;
			float end = start + limiterWidth;
			return (toLinear(end) - toLinear(start));
		} else {
			return outputTarget * limiterWidth;
		}
	}

	// limiter range on meters 

	@property float inputLimitStart() {
		version(useDecibels) {
			return outputLimitStart - worker.volumeInterpolator.volumeDb;
		}
		else {
			return outputLimitStart/(worker.volumeInterpolator.volume+0.0001);
		}
	}

	@property float inputLimitEnd() {
		version(useDecibels) {
			return outputLimitEndPreLimiter - worker.volumeInterpolator.volumeDb;
		}
		else {
			return outputLimitEndPreLimiter/(worker.volumeInterpolator.volume+0.0001);
		}
	}

	@property float outputLimitStart() {
		version(useDecibels)
			return outputTarget + limiterOffset;
		else
			return limitT - limitW;
	}

	@property float outputLimitEnd() { //!
		version(useDecibels)
			return outputTarget + limiterOffset + limiterWidth;
		else
			return limitT;
	}

	@property float outputLimitEndPreLimiter() { //!
		version(useDecibels)
			return outputTarget + limiterOffset + limiterWidth + limiterWidth;
		else
			return limitT + limitW;
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

private Box addFrame(Box parent, string title, int bottomMargin = 5) {
	Frame frame = new Frame(title);
	//frame.setBorderWidth(5);
	frame.setMarginTop(5); // outside padding
	frame.setMarginBottom(bottomMargin);
	frame.setMarginLeft(5);
	frame.setMarginRight(5);

	parent.add(frame);
	auto vbox = new Box(GtkOrientation.VERTICAL, 0);
	vbox.setMarginTop(5);
	vbox.setMarginBottom(5);
	frame.add(vbox);
	frame.setLabelAlign(0.02, 0.5);
	return vbox;
}

private Box addSmallFrame(Box parent, string title, int bottomMargin =1) {
	Frame frame = new Frame(title);
	//frame.setBorderWidth(1);
	frame.setMarginTop(1); // outside padding
	frame.setMarginBottom(bottomMargin);
	frame.setMarginLeft(5);
	frame.setMarginRight(5);
	parent.add(frame);
	auto vbox = new Box(GtkOrientation.VERTICAL, 0);
	vbox.setMarginTop(4); // inside padding
	vbox.setMarginBottom(4);
	frame.add(vbox);
	frame.setLabelAlign(0.02, 0.5);
	return vbox;
}

import gtk.Widget;
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