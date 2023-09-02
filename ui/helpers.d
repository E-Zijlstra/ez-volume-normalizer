module ui.helpers;

public {
import gtk.Widget;
import gtk.Container;
import gtk.Window;
import gdk.Display;
import gdk.Screen;
import gdk.Threads;
import gtk.MainWindow;
import gtk.Window;
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
}


public LevelBar levelMeter(int thickness=5, bool cols=false, bool horizontal = true) {
	auto lb = new LevelBar();

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

public void addStyle(W)(W bar, string style) {
	auto css_provider = new CssProvider();
	css_provider.loadFromData(style);
	bar.getStyleContext().addProvider(css_provider, gtk.c.types.STYLE_PROVIDER_PRIORITY_USER);
}

public void addGlobalStyle(Window bar, string style) {
	auto css_provider = new CssProvider();
	css_provider.loadFromData(style);
	Display display = bar.getDisplay();
	Screen screen = display.getDefaultScreen();
	bar.getStyleContext().addProviderForScreen(screen, css_provider, gtk.c.types.STYLE_PROVIDER_PRIORITY_USER);
}

public Box addFrame(Box parent, string title) {
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

public Box addHButtonBox(Container parent) {
	Box hbox = new Box(GtkOrientation.HORIZONTAL, 5);
	parent.add(hbox);
	hbox.setMarginLeft(10);
	hbox.setMarginRight(10);
	hbox.setMarginTop(1);
	hbox.setMarginBottom(1);
	return hbox;
}

public W withTopLabel(P, W: Widget )(P parent, string label, W widget, string hint="") {
	auto b = new Box(GtkOrientation.VERTICAL, 0);
	b.add(new Label(label));
	b.add(widget);
	widget.setHalign(GtkAlign.CENTER);
	widget.setValign(GtkAlign.CENTER);
	widget.setVexpand(true);
	parent.add(b);
	// set tooltip
	widget.setTooltipText(hint);
	return widget;
}


class LabeledCheckbox2 : CheckButton {
	import gtk.ToggleButton;

	this(string text, void delegate(bool active) onToggled_ = null) {
		super("");
		onToggled = onToggled_;
		box = new Box(Orientation.VERTICAL, 0);
		label = new Label(text);
		box.add(label);

		setHalign(GtkAlign.CENTER);
		setValign(GtkAlign.CENTER);
		setVexpand(true);
		box.add(super);

		super.addOnToggled(&toggled);
	}

	LabeledCheckbox2 addTo(Container container) {
		container.add(box);
		return this;
	}

private:
	Label label;
	Box box;
	void delegate(bool active) onToggled;

	void toggled(ToggleButton button) {
		if (onToggled) onToggled(button.getActive());
	}
}

