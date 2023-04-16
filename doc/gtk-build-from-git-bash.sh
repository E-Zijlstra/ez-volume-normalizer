# 1. install the run times: https://gtkd.org/Downloads/runtime/gtk3-runtime_3.24.8_64bit.exe

# 2. build the libs:
PATH=/c/D/dmd-2.100.2/windows/bin64/:/c/D/dmd-2.100.2/windows/bin:$PATH
rdmd.exe -m64 ./Build.d

# 3.do some copying to the D folder: https://github.com/gtkd-developers/GtkD/wiki/Installing-on-Windows
# then configure:
# 4.in VisualStudio add in tools->options->dmd directories:
#   import paths: C:\D\dmd-2.100.2\src\gtkd
# 5. in project properties -> linker -> general , add the 2 lib files to 'library files'