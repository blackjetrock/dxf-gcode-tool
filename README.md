# dxf-gcode-tool
Tool to turn LibreCAD DXF files into gcode.

This is a very simple script that converts DXF files from LibreCAD into DXF files that can be used on a CNC engraver.
It is a VERY simple script that only supports:

Lines
Arcs
Circles
Points

It will only work with a 2D DXf file that is then machined as a set of 2D layers, so works for engraving or cutting sheets of material.

I use it to convert LibreCAD DXf files into .gcode files that I run on chilipeppr. It generates very simple GCODE so may work with other tools.
You may be able to use it.

You can specify repeated passes at different depths from the command line with the CUTZ option.

For example:

CUTZ=0.0:-0.5:-2.4

Will generate gcode that cuts the 2D profile starting at Z=0.0, then moving Z by -0.5 until it reaches -2.4.
