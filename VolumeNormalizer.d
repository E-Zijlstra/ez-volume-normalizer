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
import levelhistorymeter;
import streamlistener;

//version=decibels;
import core.runtime;
import core.sys.windows.windows;
import std.string;

// oncycle=ignore: if not ignored static constructors will trigger module dependency cycles
extern(C) __gshared string[] rt_options = [ "oncycle=ignore", "testmode=run-main" ];


debug {
	int main(string[] args) {
		main_(args);
		//readln();

		return 0;
	}
}
else {
	extern (Windows)int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance,
				LPSTR lpCmdLine, int nCmdShow)
	{
		int result;

		try {
			Runtime.initialize();
			result = main_([]);
			Runtime.terminate();
		}
		catch (Throwable e) {
			MessageBoxA(null, e.toString().toStringz(), null, MB_ICONEXCLAMATION);
			result = 0;     // failed
		}

		return result;
	}
}

int main_(string[] args) {
	Main.init(args);
	auto ui = new UI();
	ui.open();
	Main.run();
	return 0;
}

class UI {
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
	Image levelHistoryMeterImg;
	LevelHistoryMeter levelHistoryMeter;
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
	ComboBoxText uiLowVolumeBoost;

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
		win = new MainWindow("EZ Volume Normalizer 0.5  -  github.com/E-Zijlstra/ez-volume-normalizer");
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

		auto mainCtlBar = new Box(GtkOrientation.HORIZONTAL, 0);
		vleft.add(mainCtlBar);
		mainCtlBar.setBorderWidth(10);
		mainCtlBar.setSpacing(5);
		mainCtlBar.add(new Label("Power"));
		mainCtlBar.add(uiEnable = new Switch(), );
		uiEnable.addOnStateSet(&onEnable);

		mainCtlBar.add(uiDevice = new ComboBoxText(false));
		uiDevice.addOnChanged(&onDeviceChanged);
		foreach(ep; endpoints) {
			uiDevice.append(ep.id, ep.name);
		}
		uiDevice.setActive(cast(int) endpoints.countUntil!(ep => ep.isDefault));


		mainCtlBar.add(uiDeviceInfo = new Label(""));

		{	// input
			Box frame = addFrame(vleft, "input");

			frame.add(uiSignalVuImg = new Image());
			uiSignalVu = new VuMeter(vleftWidth - 38, vuMeterHeight );
			uiSignalVu.paint(0, worker.limitOutputStart, worker.limitOutputEnd);
			uiSignalVuImg.setFromPixbuf(uiSignalVu.pixbuf);
		}

		{   // target
			Box frame = addFrame(vleft, "normalizer target / limiter range");
			frame.add(uiTargetLevel = new Scale(GtkOrientation.HORIZONTAL, 0.01, 1, 0.01));
			uiTargetLevel.addOnValueChanged((Range r) { setOutputTarget(uiTargetLevel.getValue()); });
		}

		{	// normalizer
			Box frame = addFrame(vleft, "Normalizer");
			frame.setSpacing(5);

			frame.add(levelHistoryMeterImg = new Image());
			levelHistoryMeter = new LevelHistoryMeter(vleftWidth - 38, 60, worker.analyser);
			levelHistoryMeter.paint();
			levelHistoryMeterImg.setFromPixbuf(levelHistoryMeter.pixbuf);

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
			uiOutputVuImg.setFromPixbuf(uiOutputVu.pixbuf);
			uiOutputVu.paint(0, worker.limitOutputStart, worker.limitOutputEndPreLimiter);
		}



		{   // limiter
			Box frame = addFrame(vleft, "Limiter");

			frame.add(uiOutputLimitedVuImg = new Image());
			uiOutputLimitedVu = new VuMeter(vleftWidth - 38, vuMeterHeight);
			uiOutputLimitedVuImg.setFromPixbuf(uiOutputLimitedVu.pixbuf);
			uiOutputLimitedVu.paint(0, worker.limitOutputStart, worker.limitOutputEnd);

			frame.add(uiLimiter = levelMeter());
			uiLimiter.addStyle(limiterCss);
			uiLimiter.setMarginTop(0);

			Box hbox = new Box(GtkOrientation.HORIZONTAL, 0);
			frame.add(hbox);
			hbox.setBorderWidth(10); hbox.setSpacing(5);
			uiEnableLimiter = wrapTopLabel(hbox, "active", new CheckButton(null, (CheckButton b){ worker.mLimiter.enabled = b.getActive();} ));
			uiLimiterStart = wrapTopLabel(hbox, "start", new SpinButton(0.1, 6, 0.01));
			uiLimiterWidth = wrapTopLabel(hbox, "width", new SpinButton(0.01, 4, 0.01));
			uiLimiterRelease = wrapTopLabel(hbox, "release (dB/s)", new SpinButton(0.5, 18, 0.5));
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
			//volPane.add(volCtrl = new Box(GtkOrientation.HORIZONTAL, 0));
			volCtrl.add(uiMasterDecibel = new Label("0 dB"));
			volCtrl.add(uiMasterVolume = new Scale(GtkOrientation.VERTICAL, 0, 1, 0.05));
			uiMasterVolume.setVexpand(true);
			uiMasterVolume.setInverted(true);
			uiMasterVolume.setDrawValue(false);
			uiMasterVolume.addOnValueChanged(&volumeSliderChanged);
			uiMasterVolume.addOnButtonPress( (GdkEventButton* b, Widget) {
				if(b.button == 3) {
					volumePopup.showAll();
					volumePopup.popupAtPointer(null);
					return true;
				}
				return false;
			} );
		}

		uiLowVolumeBoost = new ComboBoxText(false);
		uiLowVolumeBoost.appendText("2.5");
		uiLowVolumeBoost.appendText("2.0");
		uiLowVolumeBoost.appendText("1.5");
		uiLowVolumeBoost.appendText("1.0");
		uiLowVolumeBoost.appendText("0.75");
		uiLowVolumeBoost.appendText("0.5");
		uiLowVolumeBoost.appendText("0.4");
		uiLowVolumeBoost.setTooltipText("Low Volume Boost");
		uiLowVolumeBoost.addOnChanged( (ComboBoxText c) {
			worker.lowVolumeBoost = c.getActiveText().to!float;
		} );
		volPane.add(uiLowVolumeBoost);

		// default values
		uiLimiterStart.setValue(1.15);
		uiLimiterWidth.setValue(0.3);
		uiLimiterRelease.setValue(6);
		uiLimiterLookback.setValue(1000);
		uiTargetLevel.setValue(0.18);
		uiEnableLimiter.setActive(true);
		uiEnableNormalizer.setActive(true);
		uiLowVolumeBoost.setActive(3);
		uiAvgLength.setValue(20);
		uiNumLoudnessBars.setValue(15);


		gdk.Threads.threadsAddTimeout(15, &idle, cast(void*)(this));
		win.addOnDestroy(&onDestroy);
		win.showAll();
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
			while(worker.state != Worker.State.stopped) {
				import core.thread : Thread;
				Thread.sleep(dur!"msecs"(1));
			}
			worker.start();
		}
		displayDeviceStatus();
	}

	void setLimiterParameters() {
		try {
			worker.limiterStart = uiLimiterStart.getValue();
			worker.limiterWidth = uiLimiterWidth.getValue();
			worker.syncLimiter( (l) {
				l.releasePerSecond = uiLimiterRelease.getValue();
				l.holdTimeMs = cast(uint) uiLimiterLookback.getValue();
			});
			updateLimiterMarks();
		} catch(Exception e) {}
	}

	void updateLimiterMarks() {
		uiTargetLevel.clearMarks();
		uiTargetLevel.addMark(min(1, worker.limitOutputStart), GtkPositionType.BOTTOM, "C");
		uiTargetLevel.addMark(min(1, worker.limitOutputEnd), GtkPositionType.BOTTOM, "L");
	}

	void setOutputTarget(float value) {
		worker.setOutputTarget(value); 
		updateLimiterMarks();
	}

	MonoTime processingStartedAt;

	bool onEnable(bool state, Switch sw) {
		if (state && worker.state == Worker.State.stopped) {
			// switch on
			//worker = new Worker(); problem is that LevelHistoryMeter etc still has references to old worker.
			worker.setOutputTarget(uiTargetLevel.getValue());
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

	float autoSetVolume = 0;

	void volumeSliderChanged(Range r) {
		float scalar = uiMasterVolume.getValue();
		if (scalar == autoSetVolume) return;

		if (volumeSliderInDb)
			worker.setVolumeDb(worker.volumeInterpolator.map01ToDb(scalar));
		else
			worker.setVolume(scalar);
	}

	uint analyserUpdateTicks =99;

	void displayProcessing() {
		import std.math.exponential;
		real v = worker.signal;

		uiSignalVu.paint(v, worker.limitSignalStart, worker.limitSignalEnd);
		uiSignalVuImg.setFromPixbuf(uiSignalVu.pixbuf);

		if (worker.analyser.updateTicks != analyserUpdateTicks) {
			analyserUpdateTicks = worker.analyser.updateTicks;
			levelHistoryMeter.paint();
			levelHistoryMeterImg.setFromPixbuf(levelHistoryMeter.pixbuf);
		}

		uiMasterDecibel.setLabel(format("%.1f dB", worker.actualVolumeDb));
		if (volumeSliderInDb)
			autoSetVolume = worker.volumeInterpolator.mapDbTo01(worker.volumeInterpolator.volumeDb);
		else
			autoSetVolume = worker.volumeInterpolator.volume;
		uiMasterVolume.setValue(autoSetVolume);

		//float volumeDifference = clamp01(worker.volumeInterpolator.volume - worker.mLimiter.limitedVolume);
		float normalizedAttenuation = 1f - worker.volumeInterpolator.mapDbTo01(worker.mLimiter.attenuationDb);
		uiLimiter.setValue(normalizedAttenuation);


		uiOutputVu.paint(worker.normalizedSignal, worker.limitOutputStart, worker.limitOutputEndPreLimiter);
		uiOutputVuImg.setFromPixbuf(uiOutputVu.pixbuf);

		uiOutputLimitedVu.paint(worker.limitedSignal, worker.limitOutputStart, worker.limitOutputEnd);
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
				info(" ******* idle exception *******");
				info(t.message);
				info(t.file);
				info(t.info);
			} catch(Throwable t) {}
			return 1;
		}
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