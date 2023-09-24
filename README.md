
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
v0.7.2
 - Fixed curve correction. 0.7.1 broke it.

v0.7.1
 - Fixed limiter overshooting when using attack.

V0.7
 - Various fixes and improvements
 - Limiter tracks normalizer downregulation. This prevents over attenuation when the normalizer reduces volume faster then the limiter releases.
 - Increased range to -50dB
 - Presets
 - Limiter attack time


# User manual

### Top row
- Power on/off
- Soundcard selection
- Device info and volume reported by the device
- Volume slider curve: Makes the volume slider curve a bit flatter by boosting lower levels. Can be used to preserve some of the original dynamics.
- Presets

### Level meters
- Input signal
- Output signal (input reduced by normalizer & limiter)

orange: limiter soft-knee range
red: fully limited

### Target level
![controls](doc/target.png)

The normalizer works by reducing the master volume.
Therefore you need to set target level to some low value, like -30dB, to give it room to increase the volume when needed; setting it to 0 effectively disables the software.

The slider also sets the limiter operating range, indicated with C and L.
These can be fine tuned with the limiter start/width setting.

### Normalizer
![controls](doc/normalizer.png)

The normalizer controls the volume slider to make the loudness match the target level.
If not active then you can set the volume yourself.

#### Settings
 - delay: higher values will cause a delay before the normalizer starts ramping down the volume.
 - slowness: higher values will make the normalizer move more slowely to the desired level, but also make it more stable.

For exact details read the next section.

#### Graphic display
Displays input signal over time. There are 5 bars per second.
- Delay (in seconds) is the length of the purple moving average. Samples above the average will be bright green.
- Slowness is the number of bright bars that are kept, older bars are discarded.
- The bright bars that are left over are averaged to determine the loudness of what is playing. This is displayed as a yellow line.

##### Summary
- Use higher delay to make the normalizer ignorant of the now.
- Use higher slowness to make the normalizer nostalgic, put more weight on the past. 


### Limiter
![controls](doc/limiter.png)

The limiter starts compressing at C (or the orange area of the level meters) and won't let the signal go above L (fully limited) (red area). You can shift these points with start/width controls.

The meter displays the signal after being processed by the limiter.
If you want to see red here, you need to disable the limiter ;)
Under the meter there is thin red bar, this is the reduction (dB) applied by the limiter.

The limiter does not affect the volume slider, that would make it impossible to disable the normalizer and manually set the volume.

#### Settings
- start/width: operating range, relative to the target level.
- attack: how quickly to reduce the volume when the signal goes above the start level
- hold
- release: how quickly to reduce the volume reduction


### Power off
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
