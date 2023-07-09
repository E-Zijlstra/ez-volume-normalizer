module main;

import core.sys.windows.windows;
import std.stdio;
import VolumeNormalizer;

// oncycle=ignore: if not ignored static constructors will trigger module dependency cycles
extern(C) __gshared string[] rt_options = [ "oncycle=ignore", "testmode=run-main" ];


debug {
	int main(string[] args) {
		startNormalizer(args);
		//readln();

		return 0;
	}
}
else {
	// https://wiki.dlang.org/D_for_Win32
	// Without this, Win32 will open a text console window whenever the application is run.
	extern (Windows)int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance,
								LPSTR lpCmdLine, int nCmdShow)
	{
		int result;

		try {
			Runtime.initialize();
			result = startNormalizer([]);
			Runtime.terminate();
		}
		catch (Throwable e) {
			MessageBoxA(null, e.toString().toStringz(), null, MB_ICONEXCLAMATION);
			result = 0;     // failed
		}

		return result;
	}
}

int startNormalizer(string[] args) {
	UI.start(args);
	return 0;
}
