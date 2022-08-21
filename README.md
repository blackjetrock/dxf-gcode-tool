# dxf-gcode-tool
Tool to turn LibreCAD DXF files into gcode.

This is a very simple script that converts DXF files from LibreCAD into DXF files that can be used on a CNC engraver.
It is a VERY simple script that only supports:

Lines
Arcs
Circles
Points

It will only work with a 2D DXF file that is then machined as a set of 2D layers, so works for engraving or cutting sheets of material.

I use it to convert LibreCAD DXf files into .gcode files that I run on chilipeppr. It generates very simple GCODE so may work with other tools.
You may be able to use it.

You can specify repeated passes at different depths from the command line with the CUTZ option.

For example:

CUTZ=0.0:-0.5:-2.4

Will generate gcode that cuts the 2D profile starting at Z=0.0, then moving Z by -0.5 until it reaches -2.4.

============================
dxfgcode <file> <args>

   e.g. dxfgcode xyz.dxf CUTZ=-1.0 SAFEZ=5.0
   e.g. dxfgcode xyz.dxf CUTZ=-1.0:-1.0:-3.0 SAFEZ=5.0

   Layers called hidden or HIDDEN are ignored
   Layers called height_xxx are cut at height xxx

   optimisation is off, turn on with OPTIMISE=1

   Window truncation
   When specified, the output can be truncated so it lies within a range of Y co-ords

   e.g.
   dxfgcode.tcl test_dxf.dxf OPTIMISE=0 WINDOW_MIN_Y=60 WINDOW_MAX_Y=80 WINDOW_ON=1 SAFEZ=40

   NOTE:Currently only supports Y truncation (horizontal strips of output.
