## Installing

- Install GTKD runtime 3.24.8 from here: https://gtkd.org/Downloads/runtime/gtk3-runtime_3.24.8_64bit.exe
- Run the executable that you find under releases, or compile the source code yourself.

## Compiling
- Checkout GTKD : https://github.com/gtkd-developers/GtkD/
- Build the GTKD libs, something like this:
```
PATH=/c/D/dmd-2.100.2/windows/bin64/:/c/D/dmd-2.100.2/windows/bin:$PATH
rdmd.exe -m64 ./Build.d
```
- Copy the folder 'generated\gtkd' to your D installation. 'C:\D\dmd-2.100.2\src\gtkd'
- In VisualStudio goto tools -> options -> dmd and add the import path: C:\D\dmd-2.100.2\src\gtkd
- Also copy the two generated lib files to C:\D\dmd-2.100.2\windows\lib64\gtkd.lib C:\D\dmd-2.100.2\windows\lib64\gtkdsv.lib
- Open the project in visual studio 2022
- In project properties -> linker -> general add the 2 generated lib files to 'library files'
- compile and run
- Full/slightly different instructions to install GTKD: https://github.com/gtkd-developers/GtkD/wiki/Installing-on-Windows

## User manual
First look at the image doc/controls.png, that should explain most.

This normalizer works by reducing the master volume.
Therefore you need to set target level to some low value, like 0.2; setting it to 1 effectively disables the normalizer, it cannot boost sound.
The volume slider will be automatically updated to make the output sound match the target level.
This is not an immediate process, it will take a few seconds to reach the target level, because of that there is also a limiter.

The target level also set the limiter operating range, which can be finetuned with the limiter threshold setting.
The orange area of the level meters indicate the limiter operating range, it uses a soft-knee formula so if the signal is slightly above the threshold it is only attenuated slightly.
The target slider has an C and L indicator, it indicates where the limiter starts compressing (C) and where it is fully attenuating (L).

You can disable the limiter and normalizer individually.

Unticking the `auto` checkbox disables the normalizer and allows you to set the volume manually, the limiter will continue to operate unless you disable it too.
The limiter does not affect the volume slider, that would be confusing in manual mode.

## Warning
This normalizer is experimental and may blow up your speakers or ears.

## Power off
- Untick auto
- Set volume to your desired level
- Toggle the power button, or close the program

## Low volume boost
If your sound card doesn't behave linearly you can compensate for that with this setting.
The formula is: y = x^(1/f), where x is the input volume and f is the value you select, ideally it would be 1.0, but you can try different values to see what works best for you.

On my desktop I use 1.0 and on my laptop I use 1.5. So, yes, devices have different volume curves.

# Acknowledgements
- I borrowed windows.d for the WASPI bindings from here: https://github.com/ZILtoid1991/iota/tree/main/source/iota/audio/backend

