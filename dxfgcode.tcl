#!/usr/bin/wish
#
# Takes a DXF file and creates a GCODE file
# Does not order cuts so not optimal.
# 2D only
#

set ::OBJECTS ""
set ::DOT_DISTANCE 2.5

# Global values, override on command line
set ::SAFEZ 1.0
set ::CUTZ -1.5
set ::GFEED 50
set ::FEEDZ 100
set ::FASTFEEDX 1800
set ::FASTFEEDY 1800

set ::WINDOW_MIN_X    -10000.0
set ::WINDOW_MAX_X     10000.0
set ::WINDOW_MIN_Y    -10000.0
set ::WINDOW_MAX_Y     10000.0
set ::WINDOW_ON        0
set ::WINDOW_RE_ORIGIN 0

# Window of allowable object ranges for the Y axis
# Any object which lies partley or fully within the window is allowed through
# processing ot the output file. Any other object is not.
# This is not a  strict cut off that truncates objects, just a simple discarding
# so that tim eis not wasted on objects that won't cut a workpiece.

# Syntax is Tcl expression with $y as the variable to test
# e.g.
# "($y > 23.4) && ($y <27.9)"

set ::YWINDOW "1"

set ::FINISH_FN ""

set ::OPTIMISE 1

# Convert curves (circles and arcs) to lines. This allows windows to work on them as well as lines, as they
# are lines.

set ::CONVERT_CURVES  1

################################################################################
#
# tests that Y co-ord is within window
#

proc y_within_window {y} {

    set res 0
    if { ($y >= $::WINDOW_MIN_Y) && ($y <= $::WINDOW_MAX_Y) } {
	set res 1
    }
    
    return $res
}

proc y_below_window {y} {

    set res 0
    if { ($y < $::WINDOW_MIN_Y)} {
	set res 1
    }
    
    return $res
}
proc y_above_window {y} {

    set res 0
    if { ($y > $::WINDOW_MAX_Y)} {
	set res 1
    }
    
    return $res
}

################################################################################
#
# Generate a list of Z values, ensuring the last value is included whatever
# the step

proc get_z_list {zstart zstep zend} {
    set result ""
    
    for { set cutz $zstart } { $cutz >= $zend} { set cutz [expr $cutz+$zstep]} {
	lappend result $cutz
    }
    
    # We must have the end Z value
    if { [lsearch $result $zend]== -1 } {
	puts "CUTZ*** $cutz $zend"
	lappend result $zend
    }
    puts "CUTZ list = $result"
    return $result
}

################################################################################

proc to_rad {a} {
    return [expr $a/180.0*3.1415926]
}

set ::convert_angle_step [to_rad 3]

################################################################################
#
# Store line details
#
# Window: if start or end are within window then let it through

proc store_current_line {} {

    # Valid?
    if { ! $::inline } {
	return 
    }

    # Hidden?
    if { $::HIDDEN_LAYER } {
	return
    }
    
    #    puts "procline"
    
    # If the line is on a layer called 'dotted' then we convert it into
    # a sequence of points a certain distance apart
    
    if { [string compare $::lname "dotted"]== 0 } {
	# Don't add a line, add several points instead
	# Start and end
	lappend ::OBJECTS "point $::x1coord $::y1coord"
	lappend ::OBJECTS "point $::x2coord $::y2coord"
	# Add points $::DOT_DISTANCE apart
	# use unit vectors to move along line
	set mod [expr sqrt(($::x2coord-$::x1coord)*($::x2coord-$::x1coord)+($::y2coord-$::y1coord)*($::y2coord-$::y1coord))]
	#puts "mod= $mod"
	if { $mod == 0 } {
	    puts "MOD=0"
	} else {
	    
	    set ux [expr 1.0*($::x2coord - $::x1coord)/$mod]
	    set uy [expr 1.0*($::y2coord - $::y1coord)/$mod]
	    
	    for {set d 0; set x $::x1coord; set y $::y1coord} {$d <= $mod} {set x [expr $x+$::DOT_DISTANCE*$ux]; set y [expr $y+$::DOT_DISTANCE*$uy]; set d [expr $d+1.0*$::DOT_DISTANCE]} {
		# Move along the line
		
		lappend ::OBJECTS "point $x $y"
	    }
	}
	
    } else {
	
	# Drop the lines that would cause the profile to cut the blank
	#if { ($::y1coord == 0) || ($::y2coord == 0) } {
	#	return;
	#   }
	
	if { [info exists ::x1coord] && [info exists ::x2coord] && [info exists ::y1coord] && [info exists ::y2coord] } {
	    lappend ::OBJECTS "line $::x1coord $::y1coord $::x2coord $::y2coord"
	}
    }
}

proc store_current_point {} {
    # Valid?
    if { ! $::inpoint } {
	return 
    }

    # Hidden?
    if { $::HIDDEN_LAYER } {
	return
    }

    puts "procpoint"

    # Drop the lines that would cause the profile to cut the blank
    #if { ($::y1coord == 0) || ($::y2coord == 0) } {
    #	return;
    #   }

    if { [info exists ::x1coord] && [info exists ::x2coord] } {
	lappend ::OBJECTS "point $::x1coord $::y1coord"
    }
}

# We do circles as an arc

proc store_current_circle {} {
    puts "CIRCLE"
    # Valid?
    if { ! $::incircle } {
	return 
    }

    # Hidden?
    if { $::HIDDEN_LAYER } {
	return
    }

    puts "proc circle at $::x1coord$::y1coord"

    # If the arc is on a layer called 'dotted' then we convert it into
    # a sequence of points a certain distance apart
    
    if { [string compare $::lname "dotted"]== 0 } {
	# Create a sequence of points at fixed distances along the arc
	# Step in angle for each dot
	
	set angle_step [expr $::DOT_DISTANCE/$::radius]

	# Points at start and end of arc
	set x1 [lindex [get_arc_start_coords $::x1coord $::y1coord $::radius 0 359.99] 0]
	set y1 [lindex [get_arc_start_coords $::x1coord $::y1coord $::radius 0 359.99] 1]
	set ex1 [lindex [get_arc_end_coords $::x1coord $::y1coord $::radius  0 359.99] 0]
	set ey1 [lindex [get_arc_end_coords $::x1coord $::y1coord $::radius  0 359.99] 1]

	lappend ::OBJECTS "point $x1 $y1"
	lappend ::OBJECTS "point $ex1 $ey1"
	if { 0 < 359.9 } {
	    for {set a [to_rad 0]} {$a <= [to_rad 359.99]} {set a [expr $a+$angle_step]} {
		set x [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 0]
		set y [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 1]
		lappend ::OBJECTS "point $x $y"
	    }
	} else {
	    
	    for {set a [expr [to_rad 0]-3.1415926*2]} {$a <= [to_rad 359.99]} {set a [expr $a+$angle_step]} {
		set x [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 0]
		set y [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 1]
		lappend ::OBJECTS "point $x $y"
	    }
	}

	
	
    } else {
	
	if { [info exists ::x1coord] && [info exists ::y1coord] && [info exists ::radius] } {
	    if { $::CONVERT_CURVES } {
		# Convert arc to a series of lines
		
		set angle_step [expr $::DOT_DISTANCE/$::radius]
		set angle_step 3
	       
		set first_point 1

		puts "Add circle first point flag set"
		# Points at start and end of arc
		set x1  [lindex [get_arc_start_coords $::x1coord $::y1coord $::radius 0 359.99] 0]
		set y1  [lindex [get_arc_start_coords $::x1coord $::y1coord $::radius 0 359.99] 1]
		set ex1 [lindex [get_arc_end_coords   $::x1coord $::y1coord $::radius 0 359.99] 0]
		set ey1 [lindex [get_arc_end_coords   $::x1coord $::y1coord $::radius 0 359.99] 1]
		
		#lappend ::OBJECTS "point $x1 $y1"
		#lappend ::OBJECTS "point $ex1 $ey1"
		if { 0 < 359.99 } {
		    for {set a [to_rad 0]} {$a <= [to_rad 359.99]} {set a [expr $a+$::convert_angle_step]} {
			set x [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 0]
			set y [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 1]
			if { !$first_point } {
			    lappend ::OBJECTS "line $last_x $last_y $x $y"
			    puts "Add circle $last_x $last_y $x $y"
			} else {
			    # Store for last line segment, which joins circle together
			    set first_x $x
			    set first_y $y
			}
			set last_x $x
			set last_y $y
			set first_point 0
		    }
		    lappend ::OBJECTS "line $last_x $last_y $first_x $first_y"
		} else {
		    
		    for {set a [expr [to_rad $::start_angle]-3.1415926*2]} {$a <= [to_rad $::end_angle]} {set a [expr $a+$angle_step]} {
			set x [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 0]
			set y [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 1]
			
			if { !$first_point } {
			    lappend ::OBJECTS "line $last_x $last_y $x $y"
			} else {
			}
			set last_x $x
			set last_y $y
			set first_point 0
		    }
		}
	    } else  {
		lappend ::OBJECTS "arc $::x1coord $::y1coord $::radius 0 359.99"
	    }
	}
    }
puts "Add circle done"	
}


proc store_current_arc {} {
    #puts "ARC"
    # Valid?
    if { ! $::inarc } {
	return 
    }

    # Hidden?
    if { $::HIDDEN_LAYER } {
	return
    }

    #puts "proc arc at $::x1coord$::y1coord"

    # If the arc is on a layer called 'dotted' then we convert it into
    # a sequence of points a certain distance apart
    
    if { [string compare $::lname "dotted"]== 0 } {
	# Create a sequence of points at fixed distances along the arc
	# Step in angle for each dot
	
	set angle_step [expr $::DOT_DISTANCE/$::radius]

	# Points at start and end of arc
	set x1 [lindex [get_arc_start_coords $::x1coord $::y1coord $::radius $::start_angle $::end_angle] 0]
	set y1 [lindex [get_arc_start_coords $::x1coord $::y1coord $::radius $::start_angle $::end_angle] 1]
	set ex1 [lindex [get_arc_end_coords $::x1coord $::y1coord $::radius $::start_angle $::end_angle] 0]
	set ey1 [lindex [get_arc_end_coords $::x1coord $::y1coord $::radius $::start_angle $::end_angle] 1]

	lappend ::OBJECTS "point $x1 $y1"
	lappend ::OBJECTS "point $ex1 $ey1"
	if { $::start_angle < $::end_angle } {
	    for {set a [to_rad $::start_angle]} {$a <= [to_rad $::end_angle]} {set a [expr $a+$angle_step]} {
		set x [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 0]
		set y [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 1]
		lappend ::OBJECTS "point $x $y"
	    }
	} else {
	    
	    for {set a [expr [to_rad $::start_angle]-3.1415926*2]} {$a <= [to_rad $::end_angle]} {set a [expr $a+$angle_step]} {
		set x [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 0]
		set y [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 1]
		lappend ::OBJECTS "point $x $y"
	    }
	}

	
	
    } else {
	
	if { [info exists ::x1coord] && [info exists ::y1coord] && [info exists ::radius] && [info exists ::start_angle] && [info exists ::end_angle] } {
	    if { $::CONVERT_CURVES } {
		# Convert arc to a series of lines
		
		set angle_step [expr $::DOT_DISTANCE/$::radius]
		set angle_step 3

		set first_point 1
		
		# Points at start and end of arc
		set x1 [lindex [get_arc_start_coords $::x1coord $::y1coord $::radius $::start_angle $::end_angle] 0]
		set y1 [lindex [get_arc_start_coords $::x1coord $::y1coord $::radius $::start_angle $::end_angle] 1]
		set ex1 [lindex [get_arc_end_coords $::x1coord $::y1coord $::radius $::start_angle $::end_angle] 0]
		set ey1 [lindex [get_arc_end_coords $::x1coord $::y1coord $::radius $::start_angle $::end_angle] 1]
		
		#lappend ::OBJECTS "point $x1 $y1"
		#lappend ::OBJECTS "point $ex1 $ey1"
		if { $::start_angle < $::end_angle } {
		    for {set a [to_rad $::start_angle]} {$a <= [to_rad $::end_angle]} {set a [expr $a+$::convert_angle_step]} {
			set x [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 0]
			set y [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 1]
			if { !$first_point } {
			    lappend ::OBJECTS "line $last_x $last_y $x $y"
			} else {
			}
			set last_x $x
			set last_y $y
			set first_point 0
			lappend ::OBJECTS "line $last_x $last_y $x $y"
		    }
		} else {
		    
		    for {set a [expr [to_rad $::start_angle]-3.1415926*2]} {$a <= [to_rad $::end_angle]} {set a [expr $a+$::convert_angle_step]} {
			set x [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 0]
			set y [lindex [get_arc_coords_rad $::x1coord $::y1coord $::radius $a] 1]
			
			if { !$first_point } {
			    lappend ::OBJECTS "line $last_x $last_y $x $y"
			} else {
			}
			set last_x $x
			set last_y $y
			set first_point 0
			lappend ::OBJECTS "line $last_x $last_y $x $y"
		    }
		}
	    }
	} else	{
	    lappend ::OBJECTS "arc $::x1coord $::y1coord $::radius $::start_angle $::end_angle"
	}
    }
}


#
# Stores layer object
#
# Any layer called hidden is ignored
#

set ::HIDDEN_LAYER 0

proc store_current_layer {} {
    #puts "LAYER"
    # Valid?
    #    if { ! $::inlayer } {
    #	return 
    #    }

    #puts "proc layer at $::lname"

    if { [regexp -- "(hidden)|(HIDDEN)" $::lname] } {
	set ::HIDDEN_LAYER 1
	puts "Not storing hidden layer $::lname"
	
	# Do not store this layer
	return
    } else {
	set ::HIDDEN_LAYER 0
    }
    
    
    if { [info exists ::lname] } {
	lappend ::OBJECTS "layer $::lname"
    }
}

################################################################################

set ::TOOLWIDTH 0.0
set ::HALFTW    [expr $::TOOLWIDTH/2.0]

proc CreateToolPathWithComp {} {

    #puts "Creating toolpath"

    # Each line is modified by the tool width depending on its layer (todo)
    # For now no tool compensation

    foreach line $::OBJECTS {
	set type [lindex $line 0]
	set x1 [lindex $line 1]
	set y1 [lindex $line 2]
	set x2 [lindex $line 3]
	set y2 [lindex $line 4]

	if { $y2 == $y1 } {
	    set m h
	} else {
	    if { $x2 == $x1 } {
		set m v
	    } else {
		set m [expr ($y2-$y1) / ($x2 - $x1)]
		
		if { $m > 0 } {
		    set m +ve
		} else {
		    set m -ve
		}
	    }
	}

	#puts "$x1 $y1 $x2 $y2 m=$m"

	# Now adjust the line
	switch $m {
	    h {
		set x1 [expr $x1 + $::HALFTW]
		set x2 [expr $x2 - $::HALFTW]
	    }

	    v {
		# We ignore vertical lines
		continue
	    }

	    -ve {
		set x1 [expr $x1 + $::HALFTW]
		set x2 [expr $x2 + $::HALFTW]
	    }

	    +ve {
		set x1 [expr $x1 - $::HALFTW]
		set x2 [expr $x2 - $::HALFTW]
	    }
	}

	lappend ::TWLINES "$x1 $y1 $x2 $y2"
    }

    # Copy to lines
    set ::OBJECTS $::TWLINES
    #puts $::OBJECTS
}

################################################################################

proc CreateToolPathNoComp {} {

    puts "Creating toolpath without tool compensation"

    # Each line is modified by the tool width depending on its layer (todo)
    # For now no tool compensation

    foreach line $::OBJECTS {
	set type [lindex $line 0]

	switch $type {
	    line {
		set x1 [lindex $line 1]
		set y1 [lindex $line 2]
		set x2 [lindex $line 3]
		set y2 [lindex $line 4]
		lappend ::OBJECTS "line $x1 $y1 $x2 $y2"
	    }
	    
	    arc {
		set x1 [lindex $line 1]
		set y1 [lindex $line 2]
		set radius [lindex $line 3]
		set start_angle [lindex $line 4]
		set end_angle [lindex $line 5]
		lappend ::OBJECTS "arc $x1 $y1 $radius $start_angle $end_angle"
	    }
	}
    }

    # Copy to lines
    set ::OBJECTS $::TWLINES
    #puts $::OBJECTS
}

proc finish_current {} {
    if { $::inline } {
	store_current_line 
	set ::inline 0
    }
    if { $::inarc } {
	store_current_arc 
	set ::inarc 0
    }
    if { $::incircle } {
	store_current_circle
	set ::incircle 0
    }

    if { $::inpoint } {
	store_current_point
	set ::inpoint 0
    }
    
}

################################################################################

# Read a DXF file and get the info we want
# Most of it we ignore as we are just after a profile line

set ::dxf_lines 0
set ::dxf_arcs 0
set dxf_circles 0

proc read_dxf {filename} {

    set f [open $filename]
    set dxf_txt [read $f]
    close $f

    # Process the file.
    # Group code followed by value

    set ::inline 0
    set ::inarc 0
    set ::inpoint 0
    set ::incircle 0
    
    set phase grpcode

    foreach line [split $dxf_txt "\n"] {

	set line [string trim $line]

	switch $phase {

	    grpcode {
		switch $line {
		    999 {
			set group comment
		    }
		    0 {
			set group startof
		    }
		    2 {
			set group name
		    }
		    
		    8 {
			set group layer
		    }
		    
		    10 {
			set group x1
		    }
		    20 {
			set group y1
		    }
		    40 {
			set group radius
		    }
		    50 {
			set group start_angle
		    }
		    51 {
			set group end_angle
		    }
		    11 {
			set group x2
		    }
		    21 {
			set group y2
		    }

		    default {
			set group ???
		    }

		}

		set phase grpvalue
	    }

	    grpvalue {
		switch $group {
		    x1 {
			puts -nonewline " x1=$line"
			set ::x1coord $line
		    }
		    y1 {
			puts -nonewline " y1=$line"
			set ::y1coord $line
		    }
		    x2 {
			puts -nonewline " x2"
			set ::x2coord $line
		    }
		    y2 {
			puts -nonewline " y2"
			set ::y2coord $line
		    }
		    radius {
			puts -nonewline " radius"
			set ::radius $line
		    }
		    start_angle {
			puts -nonewline " st angle"
			set ::start_angle $line
		    }
		    end_angle {
			set ::end_angle $line
		    }
		    layer {
			set ::lname $line
			#puts "Found layer $::lname"

			# Add a layer type to object list
			store_current_layer
		    }

		    name {
			puts " $line"
		    }
		    
		    comment {
			#puts "Comment $line"
		    }
		    startof {
			puts -nonewline "\nStart of '$line'"

			switch $line {
			    SECTION {
				puts " SECTION"
			    }

			    # We don't process circles but need to end section when
			    # one appears
			    CIRCLE {
				puts " CIRCLE"
				incr ::dxf_circles 1

				finish_current
				
				set ::incircle 1
			    }
			    
			    ARC {
				puts " ARC"
				incr ::dxf_arcs 1

				finish_current
				
				set ::inarc 1
			    }
			    
			    LINE {
				puts " LINE"
				incr ::dxf_lines 1

				finish_current
				
				set ::inline 1
			    }
			    POINT {
				puts " POINT"

				finish_current
				
				set ::inpoint 1
			    }
			    ENDSEC {
				puts "ENDSEC"
				finish_current
			    }
			}
		    }
		}

		set phase grpcode

	    }
	}
    }

    puts "DXF file contains $::dxf_lines lines, $::dxf_arcs arcs and $::dxf_circles circles"
}


proc CreateCanvasWindow {name title} {

    set w $name
    catch {destroy $w}
    toplevel $w

    wm title $w $title

    set c $w.frame.c

    frame $w.frame -borderwidth .5c
    pack $w.frame -side top -expand yes -fill both

    scrollbar $w.frame.hscroll -orient horiz -command "$c xview"
    scrollbar $w.frame.vscroll -command "$c yview"

    canvas $c -relief sunken -borderwidth 2 -scrollregion {0c 0c 60c 500c}\
	-xscrollcommand "$w.frame.hscroll set" \
	-yscrollcommand "$w.frame.vscroll set"


    pack $w.frame.hscroll -side bottom -fill x
    pack $w.frame.vscroll -side right -fill y
    pack $c -expand yes -fill both
}

set ::dispx 200
set ::dispy 200

proc scalex {x} {
    return [expr (($x - $::minx) * $::dispx / $::maxx) + 10]
}

proc scaley {y} {
    return [expr $::dispy - (($y - $::minx) * $::dispy / $::maxx) + 10]
}

proc DrawProfile {} {
    set w .profile 

    set ::maxx 0
    set ::maxy 0
    set ::minx 0
    set ::miny 0

    CreateCanvasWindow $w "Profile"
    # Scale segments
    foreach line $::OBJECTS {
	set x1 [lindex $line 0]
	set y1 [lindex $line 1]
	set x2 [lindex $line 2]
	set y2 [lindex $line 3]

	if { $x1 > $::maxx } {
	    set ::maxx $x1
	}
	if { $y1 > $::maxy } {
	    set ::maxy $y1
	}
	if { $x2 > $::maxx } {
	    set ::maxx $x2
	}
	if { $y2 > $::maxy } {
	    set ::maxy $y2
	}

	if { $x1 < $::minx } {
	    set ::minx $x1
	}
	if { $y1 < $::miny } {
	    set ::miny $y1
	}
	if { $x2 < $::minx } {
	    set ::minx $x2
	}
	if { $y2 < $::miny } {
	    set ::miny $y2
	}

    }

    #puts "Min x: $::minx"
    #puts "Min y: $::miny"
    #puts "Max x: $::maxx"
    #puts "Max y: $::maxy"

    # Draw line segments
    foreach line $::OBJECTS {
	set x1 [lindex $line 0]
	set y1 [lindex $line 1]
	set x2 [lindex $line 2]
	set y2 [lindex $line 3]

	$w.frame.c create line [scalex $x1] [scaley $y1] [scalex $x2] [scaley $y2]
    }

    # Shift so maxy is at 0
    #    NormaliseZ

    # Account for tool width
    CreateToolPathNoComp
}

################################################################################

# Absolute move on axis
proc MoveTo {axis position {axis2 ""} {position2 ""}} {
    puts $::NGC "G90"
    puts $::NGC "G1 $axis$position $axis2$position2 F$::FEED($axis)"
}

# Incremental move
proc IncTo {axis position} {
    puts $::NGC "G91 G1 $axis$position F$::FEED($axis)"
}



# set feed
proc SetFeed {axis rate} {
    set ::FEED($axis) $rate
    #puts $::NGC "F$rate"
}

# Do an arc
proc get_arc_start_coords {x y r sa ea} {
    set x1 [expr $x+$r*cos($sa/180.0*3.1415926)]
    set y1 [expr $y+$r*sin($sa/180.0*3.1415926)]
    return [list $x1 $y1]
}

proc get_arc_end_coords {x y r sa ea} {
    set x1 [expr $x+$r*cos($ea/180.0*3.1415926)]
    set y1 [expr $y+$r*sin($ea/180.0*3.1415926)]
    return [list $x1 $y1]
}

proc get_arc_coords_rad {x y r a} {
    set x1 [expr $x+$r*cos($a)]
    set y1 [expr $y+$r*sin($a)]
    return [list $x1 $y1]
}

# This arc code uses the I and J Gcodes. It doesn't seem to work on the duet, so there's another
# proc that uses line segments.

proc Arc {x y r sa ea} {
    set x1 [lindex [get_arc_start_coords $x $y $r $sa $ea] 0]
    set y1 [lindex [get_arc_start_coords $x $y $r $sa $ea] 1]
    set ex1 [lindex [get_arc_end_coords $x $y $r $sa $ea] 0]
    set ey1 [lindex [get_arc_end_coords $x $y $r $sa $ea] 1]
    
    puts $::NGC "; ARC $x,$y r=$r start_angle =$sa end=$ea"
    puts $::NGC ";     $x1,$y1 $ex1,$ey1"

    # Move to start of arc
    #MoveTo X $x1 Y $y1

    # I and J are offsets to centre from start of arc
    # X and Y are end coords
    set cxo [expr $x-$x1]
    set cyo [expr $y-$y1]

    # Clockwise or counter clockwise
    if { $sa == $sa } {
	puts $::NGC "G3 I$cxo J $cyo X $ex1 Y $ey1 F$::FEED(X)"
    } else {
	puts $::NGC "G2 I$cxo J $cyo X $ex1 Y $ey1 F$::FEED(X)"
    }
}

# Uses line segments to draw arcs
#
proc ArcNotFinished {x y r sa ea} {
    set x1 [lindex [get_arc_start_coords $x $y $r $sa $ea] 0]
    set y1 [lindex [get_arc_start_coords $x $y $r $sa $ea] 1]
    set ex1 [lindex [get_arc_end_coords $x $y $r $sa $ea] 0]
    set ey1 [lindex [get_arc_end_coords $x $y $r $sa $ea] 1]
    
    puts $::NGC "; ARC $x,$y r=$r start_angle =$sa end=$ea"
    puts $::NGC ";     $x1,$y1 $ex1,$ey1"
    
    # Move to start of arc
    #MoveTo X $x1 Y $y1
    
    # I and J are offsets to centre from start of arc
    # X and Y are end coords
    set cxo [expr $x-$x1]
    set cyo [expr $y-$y1]
    
    # Clockwise
    
    for {set a $sa} {$a <$ea } { incr a 1} {
	puts $::NGC "G3 I$cxo J $cyo X $ex1 Y $ey1"
    }
}

################################################################################

set ::SegINDEX 0
set ::SEGX 0

proc StartSegment {} {
    
    set ::SEGINDEX 0
    set ::SEGX [lindex [lindex $::OBJECTS $::SEGINDEX] 0]
    set ::NUMSEG [llength $::OBJECTS]
    #puts "Numseg:$::NUMSEG"
    
    return $::SEGX
    
}

proc MoreSegments {} {
    
    set rc [expr $::SEGINDEX <= [llength $::OBJECTS]]
    #puts "MoreSegments: $rc"
    return $rc
}

# return next X co-ord we will mill Z for
proc NextSegment {} {
    
    # Where does this segment end?
    set endx [lindex [lindex $::OBJECTS $::SEGINDEX] 2]
    #puts "NextSegIn: SEGINDEX=$::SEGINDEX SEGX=$::SEGX endx=$endx"
    
    # Have we done last part of segment?
    if { $::SEGX == $endx } {
	
	# Segment done, move to next one
	incr ::SEGINDEX 1
	
	# All segments done?
	if { $::SEGINDEX >= [llength $::OBJECTS] } {
	    # All done
	} else {
	    # Start of new segment
	    set ::SEGX [lindex [lindex $::OBJECTS $::SEGINDEX] 0]
	}
    } else {
	# Move to next step of segemnt
	set ::SEGX [expr $::SEGX + $::stepx]

	# Off end?
	if { $::SEGX >= $endx } {
	    # set to end
	    set ::SEGX $endx
	}
    }
    
    #puts "NextSegOut: SEGINDEX=$::SEGINDEX SEGX=$::SEGX"
    
    return $::SEGX
}

####################################################################################################
# Are these two numbers effectively equal, i.e. within a delta of each other

set ::DELTA 0.1

proc eff_equal {a b} {
    puts "'$a' '$b'"
    set equal [expr abs($a-$b)<$::DELTA]

    return $equal
}

################################################################################

# Gets start and end co-ords of an object

proc get_start_end {object} {
    set type [lindex $object 0]

    set result ""
    
    switch $type {
	layer {
	    set result -
	}
	
	line {   
	    lappend result [lindex $object 1]
	    lappend result [lindex $object 2]
	    lappend result [lindex $object 3]
	    lappend result [lindex $object 4]
	}
	
	point {   
	    set x1 [lindex $object 1]
	    set y1 [lindex $object 2]
	    lappend result $x1
	    lappend result $y1
	    lappend result $x1
	    lappend result $y1
	}
	
	arc {
	    set x [lindex $object 1]
	    set y [lindex $object 2]
	    set radius [lindex $object 3]
	    set start_angle [lindex $object 4]
	    set end_angle [lindex $object 5]
	    
	    set x1 [lindex [get_arc_start_coords $x $y $radius $start_angle $end_angle] 0]
	    set y1 [lindex [get_arc_start_coords $x $y $radius $start_angle $end_angle] 1]
	    set ex1 [lindex [get_arc_end_coords $x $y $radius  $start_angle $end_angle] 0]
	    set ey1 [lindex [get_arc_end_coords $x $y $radius  $start_angle $end_angle] 1]
	    
	    lappend result $x1
	    lappend result $y1
	    lappend result $ex1
	    lappend result $ey1
	    
	}
    }
    
    return $result
}


# Tries to move an object in :
#

proc try_move_object {obj_idx startx starty} {

    
}

################################################################################
#
# Matrix operations

if { 0 } {
    proc mul_2x2 {a b c d e f g h} {

	set a2 [expr $a*$e+$b*$g]
	set b2 [expr $a*$f+$b*$h]
	set c2 [expr $c*$e+$d*$g]
	set d2 [expr $c*$f+$d*$h]
    }
}

proc mul_2x2 {a b} {

    set a2 [expr [lindex $a 0]*[lindex $b 0]+[lindex $a 1]*[lindex $b 2]]
    set b2 [expr [lindex $a 0]*[lindex $b 1]+[lindex $a 1]*[lindex $b 3]]
    set c2 [expr [lindex $a 2]*[lindex $b 0]+[lindex $a 3]*[lindex $b 2]]
    set d2 [expr [lindex $a 2]*[lindex $b 1]+[lindex $a 3]*[lindex $b 3]]

}

# Multiply 2x2 matrix by constant k
proc k_2x2 {k a} {
    set a0 [expr $k*[lindex $a 0]]
    set a1 [expr $k*[lindex $a 1]]
    set a2 [expr $k*[lindex $a 2]]
    set a3 [expr $k*[lindex $a 3]]

    set res [list $a0 $a1 $a2 $a3]
    return $res
}


proc det_2x2 {a b c d} {
    expr [$a*$d-$b*$c]
}

# Divide matrix a by matrix b

proc div_2x2_lst {a b} {
    set detb [det_2x2 [lindex $b 0] [lindex $b 1] [lindex $b 2] [lindex $b 3]]
    set invb [k_2x2 $det $b]

    # Divide a by b
    set res [mul_2x2 $a $invb]
    return $res
}

################################################################################
#
# Move window so bottom of slice is at 0,0 if re-origin feature is on
#
################################################################################

proc re_origin_object_to_window {object} {
    if { $::WINDOW_RE_ORIGIN } {
	# Subtract WINDOW_MIN_Y from object Y co-ords
	lappend new_object       [lindex $object 0]
	lappend new_object       [lindex $object 1]
	lappend new_object [expr [lindex $object 2] - $::WINDOW_MIN_Y]
	lappend new_object       [lindex $object 3]
	lappend new_object [expr [lindex $object 4] - $::WINDOW_MIN_Y]
	return $new_object
    }

    return $object
}



################################################################################

# Calculate determinants and see if denominators are zero
# l1 and l2 are lines defined by two points (x1, y1) (x2, y2)

proc intersection_exists {l1 l2} {
    set x1 [lindex $l1 0]
    set y1 [lindex $l1 1]
    set x2 [lindex $l1 2]
    set y2 [lindex $l1 3]

    set x3 [lindex $l2 0]
    set y3 [lindex $l2 1]
    set x4 [lindex $l2 2]
    set y4 [lindex $l2 3]

    # Calculate denominator
    set d [expr ($x1-$x2)*($y3-$y4)-($y1-$y2)*($x3-$x4)]

    # return invalid if d is zero
    return [expr ($d != 0)]    
}

# Calculate intersection point of two lines
# Check it is valid before calling this proc

proc line_intersection_of {l1 l2} {
    set x1 [lindex $l1 0]
    set y1 [lindex $l1 1]
    set x2 [lindex $l1 2]
    set y2 [lindex $l1 3]

    set x3 [lindex $l2 0]
    set y3 [lindex $l2 1]
    set x4 [lindex $l2 2]
    set y4 [lindex $l2 3]

    # Calculate denominator
    set d [expr ($x1-$x2)*($y3-$y4)-($y1-$y2)*($x3-$x4)]

    # Calculate numerators
    set nx [expr ($x1*$y2-$y1*$x2)*($x3-$x4)-($x1-$x2)*($x3*$y4-$y3*$x4)]
    set ny [expr ($x1*$y2-$y1*$x2)*($y3-$y4)-($y1-$y2)*($x3*$y4-$y3*$x4)]

    set res "[expr $nx/$d] [expr $ny/$d]"
    return $res
}

################################################################################
#
# Truncate objects  to the windows given
#
################################################################################
#
# The window is currently defined as a rectange, but could be any linearly
# defined area. Code truncates lines if needed.

proc window_truncation {} {

    puts "Truncating to window..."

    if { ![info exists ::OBJECTS] } {
	puts "No objects"
	return
    }

    set new_object_list ""
    
    for {set object_idx 0} {$object_idx < [llength $::OBJECTS]} {incr object_idx 1}  {

	puts -nonewline "T$object_idx  "
	
	set object [lindex $::OBJECTS $object_idx]
	set start_end [get_start_end $object]
	
	# Ignore layers etc
	if { $start_end == "-" } {
	    continue
	}
	
	set x1 [lindex $start_end 0]
	set y1 [lindex $start_end 1]
	set x2 [lindex $start_end 2]
	set y2 [lindex $start_end 3]

	set line_min_y [list -10000.0 $::WINDOW_MIN_Y 10000.0 $::WINDOW_MIN_Y]
	set line_max_y [list -10000.0 $::WINDOW_MAX_Y 10000.0 $::WINDOW_MAX_Y]
	set x3 [lindex $line_min_y 0]
	set y3 [lindex $line_min_y 1]
	set x4 [lindex $line_min_y 2]
	set y4 [lindex $line_min_y 3]
	
	# Calculate denominator
	set d [expr ($x1-$x2)*($y3-$y4)-($y1-$y2)*($x3-$x4)]
	
	set startx [lindex $start_end 0]
	set starty [lindex $start_end 1]
	set endx   [lindex $start_end 2]
	set endy   [lindex $start_end 3]
	
	set test_line [list $startx $starty $endx $endy]

	
	switch [lindex $object 0] {
	    line {
		puts "window line"

		# See if line intersects with min Y
		#		if  [intersection_exists $test_line $line_min_y],0 
		if { 1 } {
		    puts "Intersection between $test_line and $line_min_y"

		    # There is an intersection but it may not be on either line as we calculate
		    # using infinitely long lines through the defining points. Check that the
		    # intersection is on the test line. If not, don't truncate.

		    # The start may be above or below the min Y, we only want the part of the
		    # test line that is above MIN Y
		    # First check for lines that are fully inside the window, they remain unchanged
		    
		    if { ($starty <= $::WINDOW_MAX_Y) && ($starty >= $::WINDOW_MIN_Y) } {
			if { ($endy <= $::WINDOW_MAX_Y) && ($endy >= $::WINDOW_MIN_Y) } {
			    # Fully within window, pass it through unchanged
			    lappend new_object_list [re_origin_object_to_window $object]
			    puts " fully inside"
			    continue
			}
		    }

		    # If fully below the window then lose the line
		    if { ($starty < $::WINDOW_MIN_Y) } {
			if { ($endy < $::WINDOW_MIN_Y) } {
			    # Below window, don't pass through
			    puts " fully below 1"
			    continue
			}
		    }

		    # If fully above the window then lose the line
		    if { ($starty > $::WINDOW_MAX_Y) } {
			if { ($endy > $::WINDOW_MAX_Y) } {
			    # Below window, don't pass through
			    puts " fully above"
			    continue
			}
		    }

		    # Does line straddle the window, i.e. both start and end outside window on opposite sides?
		    if { (($starty < $::WINDOW_MIN_Y) && ($endy   > $::WINDOW_MAX_Y)) ||
			 (($endy   < $::WINDOW_MIN_Y) && ($starty > $::WINDOW_MAX_Y))  } {
			# Straddles window, truncate both ends to the window lines
			set i1 [line_intersection_of $test_line $line_min_y]
			set i2 [line_intersection_of $test_line $line_max_y]

			puts "starty<minyi1=$i1, i2=$i2"
			
			# replace line with truncated line
			set new_object ""
			lappend new_object line
			lappend new_object [lindex $i1 0]
			lappend new_object [lindex $i1 1]
			lappend new_object [lindex $i2 0]
			lappend new_object [lindex $i2 1]
			
			lappend new_object_list [re_origin_object_to_window $new_object]
			puts " straddle ($object) ==> ($new_object)"
			continue
		    }

		    # Is one end inside the window and the other outside?
		    # This case is the start inside the window and end above
		    
		    if { [y_within_window $starty] &&
			 [y_above_window $endy] } {
			
			# Truncate the end
			set intersection [line_intersection_of $test_line $line_max_y]

			puts "start inside, end above"
			
			# replace line with truncated line
			set new_object ""
			lappend new_object line
			lappend new_object $startx
			lappend new_object $starty
			lappend new_object [lindex $intersection 0]
			lappend new_object [lindex $intersection 1]
			
			lappend new_object_list [re_origin_object_to_window $new_object]
			puts " start inside, end above ($object) ==> ($new_object)"
			continue
		    }

		    # Is one end inside the window and the other outside?
		    # This case is the start inside the window and end below
		    
		    if { [y_within_window $starty] &&
			 [y_below_window $endy] } {
			
			# Truncate the end
			set intersection [line_intersection_of $test_line $line_min_y]

			puts "start inside, end below"
			
			# replace line with truncated line
			set new_object ""
			lappend new_object line
			lappend new_object $startx
			lappend new_object $starty
			lappend new_object [lindex $intersection 0]
			lappend new_object [lindex $intersection 1]
			
			lappend new_object_list [re_origin_object_to_window $new_object]
			puts " start inside, end below ($object) ==> ($new_object)"
			continue
		    }

 		    # Is one end inside the window and the other outside?
		    # This case is the end inside the window and start above
		    
		    if { [y_within_window $endy] &&
			 [y_above_window $starty] } {
			
			# Truncate the end
			set intersection [line_intersection_of $test_line $line_max_y]

			puts "end inside, start above"
			
			# replace line with truncated line
			set new_object ""
			lappend new_object line
			lappend new_object [lindex $intersection 0]
			lappend new_object [lindex $intersection 1]
			lappend new_object $endx
			lappend new_object $endy
			
			lappend new_object_list [re_origin_object_to_window $new_object]
			puts " end inside, start above ($object) ==> ($new_object)"
			continue
		    }

 		    # Is one end inside the window and the other outside?
		    # This case is the end inside the window and start below
		    
		    if { [y_within_window $endy] &&
			 [y_below_window $starty] } {
			
			# Truncate the end
			set intersection [line_intersection_of $test_line $line_min_y]

			puts "end inside, start above"
			
			# replace line with truncated line
			set new_object ""
			lappend new_object line
			lappend new_object [lindex $intersection 0]
			lappend new_object [lindex $intersection 1]
			lappend new_object $endx
			lappend new_object $endy
			
			lappend new_object_list [re_origin_object_to_window $new_object]
			puts " end inside, start below ($object) ==> ($new_object)"
			continue
		    }

		}
	    }
	    
	    arc {
		puts "window arc"
		lappend new_object_list [re_origin_object_to_window $object]
		continue
	    }
	}

	lappend new_object_list $object
    }
    
    set ::OBJECTS $new_object_list


    set numobj [llength $::OBJECTS]
    puts "$numobj objects after window"
    puts "Done."
}


################################################################################
#
# Tries to optimise objects by putting the end of one line at the start of the next
#
################################################################################

proc optimise_objects {} {

    puts "Optimising..."
    
    if { ![info exists ::OBJECTS] } {
	return
    }

    # Build a new list, only add objects to it after and object that ends at the
    # new object start.

    set ordered_objects ""

    # We iterate until nothing has moved, then stop
    set done 0
    set loops 0
    set moved_any 0
    set arcs_moved 0
    
    while { !$done } {
	incr loops 1
	if { $loops > 10 } {
	    set done 1
	}
	
	puts "  Loop $loops  (moved $moved_any arcs moved:$arcs_moved)"
	set moved_any 0
	for {set object_idx 0} {$object_idx < [llength $::OBJECTS]} {incr object_idx 1}  {

	    set line [lindex $::OBJECTS $object_idx]

	    
	    set start_end [get_start_end $line]

	    # Ignore layers etc
	    if { $start_end == "-" } {
		continue
	    }
	    
	    set startx [lindex $start_end 0]
	    set starty [lindex $start_end 1]
	    set endx   [lindex $start_end 2]
	    set endy   [lindex $start_end 3]
	    
	    # See if we can move this object somewhere where it's start is the previous object's end

	    for {set s_idx 0} {$s_idx < [llength $::OBJECTS]} {incr s_idx 1} {
		set sline [lindex $::OBJECTS $s_idx]
		
		# Don't move the object to the position it is already in
		if { $s_idx == [expr $object_idx - 1] } {
		    continue
		}
		
		# Don't compare object with itself
		if { $s_idx == $object_idx } {
		    continue
		}
		
		# Does end of this object match the start of the one we are looking at?
		set s_start_end [get_start_end $sline]

		# Ignore layers etc
		if { $s_start_end == "-" } {
		    continue
		}
		
		set s_end_x [lindex $s_start_end 2]
		set s_end_y [lindex $s_start_end 3]
		
		#puts "$s_end_x $s_end_y $startx $starty"
		if { [eff_equal $startx $s_end_x] && [eff_equal $starty $s_end_y] } {
		    
		    #puts "Can move object $line to after $sline sidx=$s_idx object_idx = $object_idx"
		    #puts "   sx,sy = $startx, $starty  ssx,ssy= $s_end_x, $s_end_y"
		    #puts "   $start_end : $s_start_end"
		    
		    incr moved_any 1

		    #if { [lindex $object 0] == "arc" } {
		    #	incr arcs_moved 1
		    #   }
		    
		    
		    # Yes, we can move the object after the 'S' object
		    set object [lindex $::OBJECTS $object_idx]
		    set ::OBJECTS [lreplace $::OBJECTS $object_idx $object_idx "delete_this"]
		    set ::OBJECTS [linsert $::OBJECTS [expr $s_idx+1] $object]

		    set idx -1
		    foreach object $::OBJECTS {
			incr idx 1
			if { [lindex $::OBJECTS $idx]=="delete_this" } {
			    #puts "Deleted old object"
			    set ::OBJECTS [lreplace $::OBJECTS $idx $idx]
			}
		    }
		}

		# If it's a line then see if we can move it if we reverse direction
		set object [lindex $::OBJECTS $object_idx]

		if { ([lindex $object 0] == "line") && [eff_equal $endx $s_end_x] && [eff_equal $endy $s_end_y] } {
		    
		    #puts "Can move object $line to after $sline sidx=$s_idx object_idx = $object_idx"
		    #puts "   sx,sy = $startx, $starty  ssx,ssy= $s_end_x, $s_end_y"
		    #puts "   $start_end : $s_start_end"
		    
		    set moved_any 1
		    # Yes, we can move the object after the 'S' object
		    set object [lindex $::OBJECTS $object_idx]

		    # Reverse direction, i.e. swap start and enbd co-ords
		    set object [list [lindex $object 0] [lindex $object 3] [lindex $object 4] [lindex $object 1] [lindex $object 2]]
		    
		    set ::OBJECTS [lreplace $::OBJECTS $object_idx $object_idx "delete_this"]
		    set ::OBJECTS [linsert $::OBJECTS [expr $s_idx+1] $object]

		    set idx -1
		    foreach object $::OBJECTS {
			incr idx 1
			if { [lindex $::OBJECTS $idx]=="delete_this" } {
			    #puts "Deleted old object"
			    set ::OBJECTS [lreplace $::OBJECTS $idx $idx]
			}
		    }
		}

		# Untested so far
		if { 0 } {
		    # If it's an arc then see if we can move it if we reverse direction
		    set object [lindex $::OBJECTS $object_idx]
		    
		    if { ([lindex $object 0] == "arc") && [eff_equal $endx $s_end_x] && [eff_equal $endy $s_end_y] } {
			
			#puts "Can move arc object $line to after $sline sidx=$s_idx object_idx = $object_idx"
			#puts "   sx,sy = $startx, $starty  ssx,ssy= $s_end_x, $s_end_y"
			#puts "   $start_end : $s_start_end"
			
			set moved_any 1
			
			# Yes, we can move the object after the 'S' object
			set object [lindex $::OBJECTS $object_idx]
			
			# Reverse direction, i.e. swap start and enbd co-ords
			set object [list [lindex $object 0] [lindex $object 1] [lindex $object 2] [lindex $object 3] [lindex $object 5] [lindex $object 4]]
			
			set ::OBJECTS [lreplace $::OBJECTS $object_idx $object_idx "delete_this"]
			set ::OBJECTS [linsert $::OBJECTS [expr $s_idx+1] $object]
			
			set idx -1
			foreach object $::OBJECTS {
			    incr idx 1
			    if { [lindex $::OBJECTS $idx]=="delete_this" } {
				#puts "Deleted old object"
				set ::OBJECTS [lreplace $::OBJECTS $idx $idx]
			    }
			}
		    }
		}
	    }
	}

	if { !$moved_any } {
	    set done 1
	}
	
    }	
}

################################################################################

#
# Takes LINES and outputs gcode to wrap it round a cylinder
#

proc CreateGcode {filename} {
    # For now we cut down by 1mm and safe Z is 5mm
    puts "Creating gcode in file $filename"
    if { ![info exists ::OBJECTS] } {
	return
    }

    #    puts "Lines found"
    set ::NGC [open $filename w]

    # Prefix
    puts $::NGC "

G90	; disable incremental moves
G21	; metric
G61	; exact path mode
M3	; start spindle
G04 P3	; wait for 3 seconds
;G0 X0 Y0 Z$::SAFEZ F800"

    SetFeed Z $::FEEDZ
    MoveTo  Z $::SAFEZ

    SetFeed X $::FASTFEEDX
    SetFeed Y $::FASTFEEDY
    MoveTo X 0
    MoveTo Y 0
    
    set lastx 10000000
    set lasty 10000000

    set hidden_layer 0
    
    foreach line $::OBJECTS {
	set type [lindex $line 0]

	switch $type {
	    layer {

		# Turn off any hidden layer switch as we have a new layer now
		set hidden_layer 0
		
		# Layers of the format height_x cause the Z height for the cut to be x
		set lname [lindex $line 1]
		puts "** Layer $lname found"
		
		switch -regexp $lname {
		    "height_\[0-9.-\]+" {
			if {[regexp -- "height_(\[0-9.-\]+)" $lname all h] } {
			    puts "**Height override from layer name: $h"
			    set ::CUTZ $h
			} else {

			}
		    }
		    "(hidden)|(HIDDEN)" {
			# Ignore this layer
			set hidden_layer 1
			puts "Ignoring layer $lname"
		    }
		    
		    default {

		    }
		}
	    }
	    
	    line {
		if { !$hidden_layer } {
		    set x1 [lindex $line 1]
		    set y1 [lindex $line 2]
		    set x2 [lindex $line 3]
		    set y2 [lindex $line 4]
		    
		    # If lastx,lasty doesn't equal the start of this line then move Z up, move to position and down again
		    if { [eff_equal $lastx $x1] && [eff_equal $lasty $y1] } {
			# Nothing to do, we are already here
		    } else {
			# Move up to safe height
			
			SetFeed Z $::FEEDZ
			MoveTo Z $::SAFEZ
			
			# Move to start position of line
			SetFeed X $::FASTFEEDX
			SetFeed Y $::FASTFEEDY
			
			MoveTo X $x1 Y $y1
			
			# Move back down
			SetFeed Z $::FEEDZ
			MoveTo Z $::CUTZ
		    }

		    puts "LINE x1=$x1 y1=$y1 x2=$x2 y2=$y2 "
		    
		    # Mill to the z position
		    SetFeed X $::FEEDX
		    SetFeed Y $::FEEDY
		    
		    set lastx $x1
		    set lasty $y1
		    
		    MoveTo X $x2 Y $y2
		    
		    # Store end point for next segment
		    set lastx $x2
		    set lasty $y2
		}
	    }

	    point {
		if { !$hidden_layer } {
		    set x1 [lindex $line 1]
		    set y1 [lindex $line 2]
		    
		    # Move up to safe height
		    
		    SetFeed Z $::FEEDZ
		    MoveTo Z $::SAFEZ
		    
		    # Move to start position of line
		    SetFeed X $::FASTFEEDX
		    SetFeed Y $::FASTFEEDY
		    
		    MoveTo X $x1 Y $y1
		    
		    # Move back down
		    SetFeed Z $::FEEDZ
		    MoveTo Z $::CUTZ
		    
		    MoveTo X $x1 Y $y1
		    
		    SetFeed Z $::FEEDZ
		    MoveTo Z $::SAFEZ
		    
		    # Store end point for next segment
		    set lastx $x1
		    set lasty $y1
		}
	    }
	    
	    arc {
		if { !$hidden_layer } {
		    set x [lindex $line 1]
		    set y [lindex $line 2]
		    set radius [lindex $line 3]
		    set start_angle [lindex $line 4]
		    set end_angle [lindex $line 5]
		    
		    set x1 [lindex [get_arc_start_coords $x $y $radius $start_angle $end_angle] 0]
		    set y1 [lindex [get_arc_start_coords $x $y $radius $start_angle $end_angle] 1]
		    set ex1 [lindex [get_arc_end_coords $x $y $radius  $start_angle $end_angle] 0]
		    set ey1 [lindex [get_arc_end_coords $x $y $radius  $start_angle $end_angle] 1]

		    puts "ARC x=$x y=$y"
		    puts "ARC x1=$x1 y1=$y1 ex1=$ex1 ey1=$ey1 r=$radius sa=$start_angle ea=$end_angle"
		    
		    # If lastx,lasty doesn't equal the start of this line then move Z up, move to position and down again
		    if { [eff_equal $lastx $x1] && [eff_equal $lasty $y1] } {
			# Nothing to do, we are already here
		    } else {
			# Move up to safe height
			
			SetFeed Z $::FEEDZ
			MoveTo Z $::SAFEZ
			
			# Move to start position of arc
			SetFeed X $::FASTFEEDX
			SetFeed Y $::FASTFEEDY
			MoveTo X $x1 Y $y1
			
			# Move back down
			SetFeed Z $::FEEDZ
			MoveTo Z $::CUTZ
		    }
		    
		    # Mill to the z position
		    SetFeed X $::FEEDX
		    SetFeed Y $::FEEDY
		    
		    set lastx $x1
		    set lasty $y1
		    
		    Arc $x $y $radius $start_angle $end_angle
		    
		    # Store end point for next segment
		    set lastx $ex1
		    set lasty $ey1
		}
	    }
	}
    }	
    
    # Suffix
    
    puts $::NGC "
G0 Z$::SAFEZ     ; Z now safe
G28  X         ; home X
;  M1	; end program
"
    
    close $::NGC
    
}

################################################################################
#
# File name manipulations
#
################################################################################

# Delete the output file, ready for a new one
proc delete_output_file {} {
#    set ::OUT_DEST_FILENAME [string map {.dxf .gcode} $::FILENAME]
    set ::OUT_DEST_FILENAME [create_out_filename $::FILENAME]
    
    file delete -force $::OUT_DEST_FILENAME
    set f [open $::OUT_DEST_FILENAME w]
    puts $f ""
    close $f
}

# Adds text to output file
proc add_to_output_file {text} {
#    set ::OUT_DEST_FILENAME [string map {.dxf .gcode} $::FILENAME]
    set ::OUT_DEST_FILENAME [create_out_filename $::FILENAME]
    
    set f [open $::OUT_DEST_FILENAME a]
    puts $f $text
    close $f
}

# Adjusts a number so we can insert it in a file name
proc file_name_adjust {num} {
    #set a_num [string map {"." "p"} $num]
    #set a_num [string map {"-" "m"} $num]

    return $num
}

# Turn filename into output file name

proc create_out_filename {fn} {
    set ofn $fn
    
    if { $::WINDOW_ON } {

	set wmaxy [file_name_adjust $::WINDOW_MAX_Y]
	set wminy [file_name_adjust $::WINDOW_MIN_Y]

	set window_range "_WY($wminy-$wmaxy\)"
	set ofn [string map ".dxf $window_range\.gcode" $fn]
    } else {
	set ofn [string map {.dxf .gcode} $fn]
    }
    
    return $ofn
}

################################################################################

# Generate one pass from dxf file. Concat file if asked to
proc generate_one_pass {{concat_output 0}} {
    puts "Gcode pass"
    # 
    # Same values set from others
    set ::FEEDX $::GFEED
    set ::FEEDY $::GFEED
    
    
    # If concatenating file then use temporary output file
    if { $concat_output } {
	set ::OUT_FILENAME concat_file.gcode
	#set ::OUT_DEST_FILENAME [string map {.dxf .gcode} $::FILENAME]
	set ::OUT_DEST_FILENAME [create_out_filename $::FILENAME]

	puts "Concatenating output"
    } else {
	# Set output filename
	#set ::OUT_FILENAME [string map {.dxf .gcode} $::FILENAME]
	set ::OUT_FILENAME [create_out_filename $::FILENAME]
	puts "Output filename: $::OUT_FILENAME\n"
    }
    
    #DrawProfile
    CreateGcode $::OUT_FILENAME
    
    # Concatenate if required
    if { $concat_output } {
	# get new file data
	set f [open $::OUT_FILENAME]
	set ftxt1 [read $f]
	close $f

	# get current file contents
	set f [open $::OUT_DEST_FILENAME]
	set ftxt2 [read $f]
	close $f

	set ntxt "$ftxt2$ftxt1"

	#Write to output file
	set f [open $::OUT_DEST_FILENAME w]
	puts $f $ntxt
	close $f
    }
}


################################################################################
#
# Command line arguments
#
# First argument is dxf file
#
# remaining args ar eof form val=xxx
#
# which sets various things:

if { [llength $argv] == 0 } {
    puts "dxfgcode <file> <args>"
    puts ""
    puts "   e.g. dxfgcode xyz.dxf CUTZ=-1.0 SAFEZ=5.0"
    puts "   e.g. dxfgcode xyz.dxf CUTZ=-1.0:-1.0:-3.0 SAFEZ=5.0"
    puts ""
    puts "   Layers called hidden or HIDDEN are ignored"
    puts "   Layers called height_xxx are cut at height xxx"
    puts ""
    puts "   optimisation is off, turn on with OPTIMISE=1"
    puts ""
    puts "   Window truncation"
    puts "   When specified, the output can be truncated so it lies within a range of Y co-ords"
    puts ""
    puts "   e.g."
    puts "   dxfgcode.tcl test_dxf.dxf OPTIMISE=0 WINDOW_MIN_Y=60 WINDOW_MAX_Y=80 WINDOW_ON=1 SAFEZ=40"
    puts ""
    puts "   NOTE:Currently only supports Y truncation (horizontal strips of output."
    exit
    
}

# zsafe : Safe Z height
# zcut :   Z cut depth


set ::FILENAME [lindex $argv 0]

# Remaining args
foreach arg [lrange $argv 1 end] {
    puts "arg='$arg'"
    
    if { [regexp -- {([a-zA-Z0-9_-]+)=(.*)} $arg all name value] } {
	# Set value
	set ::$name $value
	puts "Value ::$name = $value"
    } else {
	puts "UNKNOWN argument: '$arg'"
    }
}


#--------------------------------------------------------------------------------
#
# Read the DXf file. We only need do this once
# then generate whatever gcode we want from it
#
# DXF file name
read_dxf $::FILENAME

# If windows are on then we truncate objects to lie within windows
if { $::WINDOW_ON } {

    window_truncation
}

# We have a go at optimising the objects to minimize time and Z moves

if { $::OPTIMISE } {
    optimise_objects
}

#--------------------------------------------------------------------------------
# Z can have multiple values for multiple passes
#
# Format ZCUT=start:step:end
#
# Process and set flags for multiple passes
#

set ::MULTIPLE_Z 0
set ::MULTIPLE_GFEED 0

if { [regexp -- {([0-9.-]+):([0-9.-]+):([0-9.-]+)} $::CUTZ all ::ZSTART ::ZSTEP ::ZEND] } {
    # Multiple Z, we generate each value then concatenate file
    set ::MULTIPLE_Z 1
}

if { [regexp -- {([0-9.-]+):([0-9.-]+):([0-9.-]+)} $::GFEED all ::GFEEDSTART ::GFEEDSTEP ::GFEEDEND] } {
    # Multiple Z, we generate each value then concatenate file
    set ::MULTIPLE_GFEED 1
}

set ::MULT_DONE 0

# generate passes as required
if { $::MULTIPLE_GFEED } {
    puts "Multiple GFEED $::GFEEDSTART $::GFEEDSTEP $::GFEEDEND"
    delete_output_file
    
    for { set ::GFEED $::GFEEDSTART } { $::GFEED <= $::GFEEDEND} { set ::GFEED [expr $::GFEED+$::GFEEDSTEP]} {
	puts "GFEED now $::GFEED"
	generate_one_pass 1
	set ::MULT_DONE 1
    }
    
}

# generate passes as required
if { $::MULTIPLE_Z } {
    puts "Multiple CUTZ $::ZSTART $::ZSTEP $::ZEND"
    delete_output_file

    foreach ::CUTZ [get_z_list $::ZSTART $::ZSTEP $::ZEND] {
	puts "CUTZ now $::CUTZ"
	generate_one_pass 1
	set ::MULT_DONE 1
    }
    
}

if { !$::MULT_DONE } {
    delete_output_file
    generate_one_pass 0
}

# Now add on a finish file if required
if { [string length $::FINISH_FN] > 0 } {
    puts "Adding finish code from $::FINISH_FN"
    set f [open $::FINISH_FN]
    set ftxt [read $f]
    close $f
    
    add_to_output_file $ftxt
}

add_to_output_file "\nM1    ;End program"


exit

################################################################################

set w ""

puts $::OBJECTS

menu $w.menu -tearoff 0

menu $w.menu.file -tearoff 0
menu $w.menu.windows -tearoff 0
menu $w.menu.options -tearoff 0
menu $w.menu.options.cascade -tearoff 0

$w.menu add cascade -label "File"  -menu $w.menu.file -underline 0
$w.menu add cascade -label "Windows" -menu $w.menu.windows -underline 0

set m $w.menu.file
$m add command -label "Draw Profile" -command "DrawProfile"
$m add command -label "Create Wrap GCode" -command "CreateWrap"
$m add command -label "Exit" -command exit

set m $w.menu.windows
$m add command -label "Close Source Windows" -command "CloseSourceWindows source"
$m add command -label "Close Error Windows" -command "CloseSourceWindows wrn"

. configure -menu $w.menu
