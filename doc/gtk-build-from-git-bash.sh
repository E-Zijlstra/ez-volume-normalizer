# 1. install the run times: https://gtkd.org/Downloads/runtime/gtk3-runtime_3.24.8_64bit.exe

# 2. Get 3.10.0 of the code: https://github.com/gtkd-developers/GtkD
# 3. build the libs:
PATH=/c/D/dmd-2.100.2/windows/bin64/:/c/D/dmd-2.100.2/windows/bin:$PATH
rdmd.exe -m64 ./Build.d

# 4.do some copying to the D folder: https://github.com/gtkd-developers/GtkD/wiki/Installing-on-Windows
# Then configure the stuff you copied in Visual Studio:
# 5.in VisualStudio add in tools->options->dmd directories:
#   import paths: C:\D\dmd-2.100.2\src\gtkd
# 6. in project properties -> linker -> general , add the 2 lib files to 'library files'
# The field would look something like this: C:\D\dmd-2.100.2\windows\lib64\gtkd.lib C:\D\dmd-2.100.2\windows\lib64\gtkdsv.lib;C:\D\dmd-2.100.2\windows\lib64\mingw\ole32.lib