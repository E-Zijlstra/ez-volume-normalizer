
# Overview
This is a volume normalizer and/or limiter for Microsoft Windows.
It works by reducing the windows master volume, it can not boost your audio.
- Requirements: 64 bit windows.
- Tested on: Windows 10.

![controls](doc/controls.png)

## Warning
This software has not been tested on many devices, so be careful at first, don't blow up your ears.
Use at your own risk.


# Installing
- Install GTKD runtime 3.24.8 from here: https://gtkd.org/Downloads/runtime/gtk3-runtime_3.24.8_64bit.exe
  (It's needed for the GUI)
- Run the executable that you find under releases, or compile the source code yourself. (see below)

# Changelog
v0.8.0
 - Added auto reset to respond faster to quiet parts.


# User manual

### Top row
- Power on/off
- Soundcard selection
- Device info and volume reported by the device
- Volume adjustment: At 50% it wil send -3dB to your soundcard instead of -6dB.  
  Can be used to retain some of the original dynamics.  
  This is done in the last stage, so visually you won't see any difference.
- Presets

### Level meters
- Input signal
- Output signal

Orange: limiter operating range (soft knee)  
Red: fully limited

### Target level
![controls](doc/target.png)

The normalizer works by reducing the master volume.
Therefore you need to set target level to some low value, like -30dB, to give it room to increase the volume when needed; setting it to 0 effectively disables the software.

The slider also sets the limiter operating range, indicated with C and L.
These can be fine tuned with the limiter start/width setting.

### Normalizer
![controls](doc/normalizer.png)

The normalizer controls the volume setpoint to make the output signal match the target level.  
If not active then you can set the setpoint yourself. (volume slider on the right)

#### Graphic display
Displays input signal over time. There are 5 bars per second.
- purple line: A moving average that selects bars, these will be bright green
- yellow line: The average of the bright green bars, this is the loudness of what is playing.

#### Settings
 - selector: Length of the purple average.  
   Increase this to ignore quiet parts.
 - WMA: Makes the selector respond faster to recent changes. (Weighted moving average)
 - average: How many green bars to use to compute the average loudness.  
   Decrease this to converge more quickly to a new level.
 - auto reset: If the selector falls this many dB below then the average will be reset.  

### Limiter
![controls](doc/limiter.png)

Because the normalizer is relatively slow, there is also a limiter.

The limiter starts compressing at C (or the orange area of the level meters) and won't let the signal go above L (fully limited) (red area). You can shift these points with start/width controls.

The thin red bar show the reduction applied by the limiter (in dB).

The limiter does not affect the volume slider, that would make it impossible to disable the normalizer and manually set the volume.

#### Settings
- start/width: operating range, relative to the target level.
- attack: how quickly to reduce the volume when the signal goes above the start level
- hold
- release: how quickly to reduce the volume reduction


### Power off
To set the volume before exiting the program:
- Disable normalizer
- Set volume to your desired level
- Toggle the power button, or close the program



# Compiling
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

## Acknowledgements
- I borrowed windows.d for the WASPI bindings from here: https://github.com/ZILtoid1991/iota/tree/main/source/iota/audio/backend
