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

import util;
import worker;
import vumeter;

//version=decibels;
import core.runtime;
import core.sys.windows.windows;
import std.string;

debug {
	int main(string[] args) {
		main_(args);
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
	Image   uiSignalVuImg;
	VuMeter uiSignalVu;

	Button button;
	Switch uiEnable;
	Label uiDeviceInfo;
	LevelBar uiPeakHold;
	LevelBar uiPeakMax;
	Scale uiTargetLevel;
	SpinButton uiLimiterStart;
	SpinButton uiLimiterWidth;
	SpinButton uiLimiterRelease;

	Image uiOutputVuImg;
	VuMeter uiOutputVu;
	CheckButton uiEnableLimiter;
	Image uiOutputLimitedVuImg;
	VuMeter uiOutputLimitedVu;
	LevelBar uiLimiter;
	Label uiMasterDecibel;
	Scale uiMasterVolume;
	CheckButton uiEnableVolume;
	ComboBoxText uiLowVolumeBoost;


	Worker worker;
	bool wasRunning = true;

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
		win = new MainWindow("Volume Normalizer 0.1  -  github.com/E-Zijlstra/ez-volume-normalizer");
		win.setDefaultSize(630, 300);
		//win.addGlobalStyle("window {background: rgb(82,74,67);} spinbutton {background: rgb(82,74,67)}");

		//import gtk.Settings;
		//Settings set = Settings.getDefault();
		//set.setData("gtk-theme-name", cast(void*)"Adwaita".ptr);

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
		mainCtlBar.add(uiDeviceInfo = new Label("No device"));

		{	// input
			Box frame = addFrame(vleft, "input / peaks");

			frame.add(uiSignalVuImg = new Image());
			uiSignalVu = new VuMeter(vleftWidth - 38, vuMeterHeight );
			uiSignalVuImg.setFromPixbuf(uiSignalVu.pixbuf);
			uiSignalVu.paint(0, worker.limitOutputStart, worker.limitOutputEnd);

			frame.add(uiPeakHold = levelMeter());
			frame.add(uiPeakMax = levelMeter());
		}

		{
			Box frame = addFrame(vleft, "target");
			frame.add(uiTargetLevel = new Scale(GtkOrientation.HORIZONTAL, 0, 1, 0.01));
			uiTargetLevel.addOnValueChanged((Range r) { setOutputTarget(uiTargetLevel.getValue()); });
		}

		{
			Box frame = addSmallFrame(vleft, "output");
			frame.add(uiOutputVuImg = new Image());
			uiOutputVu = new VuMeter(vleftWidth - 38, vuMeterHeight );
			uiOutputVuImg.setFromPixbuf(uiOutputVu.pixbuf);
			uiOutputVu.paint(0, worker.limitOutputStart, worker.limitOutputEndPreLimiter);
		}
		{   // limiter
			Box frame = addSmallFrame(vleft, null, 10);

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
			uiEnableLimiter = wrapTopLabel(hbox, "limiter", new CheckButton(null, (CheckButton b){ worker.mLimiter.enabled = b.getActive();} ));
			uiLimiterStart = wrapTopLabel(hbox, "start", new SpinButton(0.1, 6, 0.01));
			uiLimiterWidth = wrapTopLabel(hbox, "width", new SpinButton(0.01, 4, 0.01));
			uiLimiterRelease = wrapTopLabel(hbox, "Release/s", new SpinButton(0.02, 1, 0.02));
			uiLimiterStart.addOnValueChanged( (SpinButton e) { setLimiterThreshold(); } );
			uiLimiterWidth.addOnValueChanged( (SpinButton e) { setLimiterThreshold(); } );
			uiLimiterRelease.addOnValueChanged( (SpinButton e) { setLimiterThreshold(); } );
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
			volCtrl.add(uiMasterVolume = new Scale(GtkOrientation.VERTICAL, 0, 1, 0.05));
			uiMasterVolume.setVexpand(true);
			uiMasterVolume.setInverted(true);
			uiMasterVolume.addOnValueChanged((Range r) { worker.setVolume(uiMasterVolume.getValue()); });
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
		volPane.add(uiEnableVolume = new CheckButton("Auto", (CheckButton b){ worker.overrideVolume = !b.getActive();} ));

		// default values
		uiLimiterStart.setValue(1.0);
		uiLimiterWidth.setValue(0.4);
		uiLimiterRelease.setValue(0.14);
		uiTargetLevel.setValue(0.18);
		uiEnableLimiter.setActive(true);
		uiEnableVolume.setActive(true);
		uiLowVolumeBoost.setActive(3);


		gdk.Threads.threadsAddTimeout(15, &idle, cast(void*)(this));
		win.addOnDestroy(&onDestroy);
		win.showAll();
	}

	void onDestroy(Widget w) {
		worker.stop();
		Main.quit();
	}

	void setLimiterThreshold() {
		try {
			worker.limiterStart = uiLimiterStart.getValue();
			worker.limiterWidth = uiLimiterWidth.getValue();
			worker.syncLimiter( (l) {l.releasePerSecond = uiLimiterRelease.getValue(); });
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
		if (state && !worker.running) {
			// switch onf
			worker.setOutputTarget(uiTargetLevel.getValue());
			processingStartedAt = MonoTime.currTime;
			worker.processedFrames = 0;
			wasState = worker.state;
			worker.start();
		}
		else if (worker) {
			worker.stop();
			info("worker disabled");
		}
		return false;
	}

	Worker.State wasState = Worker.State.stopped;
	bool isStatusChanged() {
		Worker.State state = worker ? worker.state : Worker.State.stopped;
		
		bool yes = (state != wasState);
		wasState = state;
		return yes;
	}

	void displayStatus() {
		if (!worker || !worker.running) {
			uiDeviceInfo.setLabel("No device");
		}
		else {
			uiDeviceInfo.setLabel(worker.stream.sampleRate.tos ~ "Hz, " ~ worker.stream.bps.tos ~ "b " );
		}
	}

	void displayProcessing() {
		import std.math.exponential;
		real v = worker.signal;
		version(decibels) {
			v = 20* log10(worker.peak);
			v+= 60;
		}
		//uiSignal.setValue(v);
		uiSignalVu.paint(v, worker.limitSignalStart, worker.limitSignalEnd);
		uiSignalVuImg.setFromPixbuf(uiSignalVu.pixbuf);


		uiPeakHold.setValue(worker.peakMax);
		uiPeakMax.setValue(worker.peakMaxTrue);

		uiMasterVolume.setValue(worker.volume);

		float volumeDifference = clamp01(worker.volume - worker.mLimiter.limitedVolume);
		uiLimiter.setValue(volumeDifference);


		import std.format;

		uiOutputVu.paint(worker.volume * worker.signal, worker.limitOutputStart, worker.limitOutputEndPreLimiter);
		uiOutputVuImg.setFromPixbuf(uiOutputVu.pixbuf);

		uiOutputLimitedVu.paint(worker.mLimiter.limitedVolume * worker.signal, worker.limitOutputStart, worker.limitOutputEnd);
		uiOutputLimitedVuImg.setFromPixbuf(uiOutputLimitedVu.pixbuf);


	}


	// https://github.com/gtkd-developers/GtkD/blob/master/demos/gtkD/DemoMultithread/DemoMultithread.d
	extern(C) nothrow static int idle(void* userData) {
		try{
			UI ui = cast(UI) userData;
			if (ui.isStatusChanged()) ui.displayStatus();

			if (ui.worker.state != Worker.State.stopped) {
				ui.displayProcessing();
			} else {
				ui.uiEnable.setState(false);
			}

			return 1;
		} catch (Throwable t) {
			try { info(t.message); } catch(Throwable t) {}
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