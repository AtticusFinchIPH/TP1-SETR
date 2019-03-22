## \file groundstation.tcl
# Author: Emmanuel Grolleau
#\verbatim

#!/bin/sh
# groundstation.tcl \
exec wish "$0" ${1+"$@"}
package require BWidget

#Protocol
# From ground station to robot
# q -> quit
# p 0..100 -> power
# r x y a -> reset (x,y,angle)
# m 0|1 -> for mode manual or auto
# in manual mode:
# S|F|B|L|R -> stop/forward/backward/left/right
# in auto mode
# g x y -> goto (x,y)
# S -> stop
# From robot to ground station
# o dist-90 dist-45 dist0 dist45 dist90 -> scan results in cm
# p x y angle -> position and angle
# s 0|1|2 -> status standby|auto_move|direct_move

## Options of the ground station.
# Variable names are straightforward
# We define a grid of squares (x1,y1) lower left corner to (x2,y2) upper right corner \
of squares of side cm centimeters
namespace eval ::op {
	## Documented var \c ip
	# IP address of the robot
	variable ip 169.254.137.230
	## Documented var \c x1
	# Abscissa of the lower left corner of the grid
	variable x1 -600
	## Documented var \c y1
	# Ordinate of the lower left corner of the grid
	variable y1 -600
	## Documented var \c x2
	# Abscissa of the higher right corner of the grid
	variable x2 600
	## Documented var \c y2
	# Ordinate of the higher right corner of the grid
	variable y2 600
	## Documented var \c cm
	# Size of each grid square in centimeters
	variable cm 10	
	## Documented var \c ppcm
	# Pixels per centimeter
	variable ppcm 2	
	## Documented var \c radius
	# Radius, in cm of the circle representing each cross
	variable radius 5
	## Documented var \c port
	# Port used on the robot
	variable port 2224
}

set M_SQRT2 [expr sqrt(2.0)]

### proc \c XToCanvas returns the canvas coord of x
# param[in] x the coordinate
# return canvas coord of the x coordinate
proc XToCanvas {x} {
	return [expr ($x-$::op::x1+$::op::radius)*$::op::ppcm]
}

### proc \c YToCanvas returns the canvas coord of y
# param[in] y the coordinate
# return canvas coord of the x coordinate
proc YToCanvas {y} {
	return [expr ($::op::y2-$y+$::op::radius)*$::op::ppcm]	
}

### proc \c CreateCanvas creating the grid
# param[in] parent Name of the parent widget of the new canvas
# return Name of the created widget
proc CreateCanvas {parent} {
	global P
	set w [canvas $parent.c -scrollregion [list 0 0 [expr (($::op::x2-$::op::x1)+2*$::op::radius)*$::op::ppcm+1] [expr (($::op::y2-$::op::y1)+2*$::op::radius)*$::op::ppcm+1]] -bg white]
	set P(canvas) $w
	for {set x $::op::x1} {[expr $x<=$::op::x2]} {incr x $::op::cm} {
		for {set y $::op::y1} {[expr $y<=$::op::y2]} {incr y $::op::cm} {
			set o [$w create oval [expr [XToCanvas $x]-$::op::radius*$::op::ppcm] [expr [YToCanvas $y]-$::op::radius*$::op::ppcm] \
				[expr [XToCanvas $x]+$::op::radius*$::op::ppcm] [expr [YToCanvas $y]+$::op::radius*$::op::ppcm] -fill white -width 1 -outline black]
			set P($x,$y,w) $o
			set P($x,$y) 0
			$w bind $o <Button-1> "Click $x $y"
			$w bind $o <Button-3> "SetTarget $x $y"
			$w bind $o <Enter> "set P(status) \"($x,$y)\""
		}
	}
	return $w
}
proc SetTarget {x y} {
	global P
	if {$P(mode)==2} {
		Switch $P(targetX) $P(targetY) $P($P(targetX),$P(targetY))
		set P(targetX) $x
		set P(targetY) $y
		$P(canvas) itemconfigure $P($x,$y,w) -fill green
	}
}
proc HideTarget {} {
	global P
	Switch $P(targetX) $P(targetY) $P($P(targetX),$P(targetY))	
}
proc Click {x y} {
	global P
	set v $P($x,$y)
	switch $v {
		0 {Switch $x $y 2}
		1 {Switch $x $y 0}
		2 {Switch $x $y 0}
	}
}

proc Connect {ip port} {
	global P
	if {[info exists P(sock]} {
		catch {filevent $P(sock) readable ""}
		catch {close $P(sock)}
	}
	if {[catch {set P(sock) [socket $ip $port]}]} {
		tk_messageBox -type ok -title Error -icon error -message "Cannont connect to $ip:$port" \
			-detail "Check the robot IP."
		return 0
	} else {
		fileevent $P(sock) readable onIncomingData
		SetMode $P(mode)
		return 1
	}
}

proc onIncomingData {} {
	global P
	set t [gets $P(sock)]
	set l [split $t]
	switch -exact -- [lindex $l 0] {
		o {
			foreach {x y} [roundPos $P(x) $P(y)] {}
			#s dist_front dist_45� dist_90� dist_135� dist_180� dist_225� dist_270� dist_315�
			set a [expr round($P(angle)/45.0)*45]
			set b -90
			foreach c [lrange $l 1 end] {
				set alpha [expr $a+$b]
				if {$alpha<0} {
					set alpha [expr $alpha+360]
				} elseif {$alpha>=360} {
					set alpha [expr $alpha-360]
				}
				if {[expr $c>0 && $c<2.5*$::op::cm]} {
					set obstacle 1
				} else {
					set obstacle 0
				}
				switch -exact -- $alpha {
					0 {set ox 1;set oy 0}
					45 {set ox 1;set oy 1}
					90 {set ox 0;set oy 1}
					135 {set ox -1;set oy 1}
					180 {set ox -1;set oy 0}
					225 {set ox -1;set oy -1}
					270 {set ox 0;set oy -1}
					315 {set ox 1;set oy -1}
				}
				if {$P([expr $x+$ox*$::op::cm],[expr $y+$oy*$::op::cm])!=2} {
					Switch [expr $x+$ox*$::op::cm] [expr $y+$oy*$::op::cm] $obstacle
				}
				incr b 45
			}
		}
		p {
			foreach {c x y a} $l {}
			set P(x) $x
			set P(y) $y
			set P(angle) $a
			DrawRobot
		}
		s {
			foreach {c s} $l {
				switch -exact -- $s {
					0 {set P(robotstatus) STDBY}
					1 {set P(robotstatus) DIRECT}
					2 {set P(robotstatus) AUTO}
					default {set P(robotstatus) "???"}
				}
			}
		}
		default {puts "Unrecognized command $t"}
	}
}
proc DirectCommand {c} {
	SendRobot $c
}
proc SendRobot {t} {
	global P
	puts "Sending robot: $t"
	if {[catch {puts $P(sock) $t;flush $P(sock)}]} {
		puts "Disconnected"
	}
}
proc DrawRobot {} {
	global P
	if {[info exists P(robot)]} {
		$P(canvas) delete $P(robot)
	}
	set x0 $P(x)
	set y0 $P(y)
	set a [expr $P(angle)*-0.01745329251994444444444444444444]
	set x 5
	set y 0
	set x1 [expr $x0+$x*cos($a)+$y*sin($a)]
	set y1 [expr $y0+$y*cos($a)-$x*sin($a)]
	set x -5
	set y 3
	set x2 [expr $x0+$x*cos($a)+$y*sin($a)]
	set y2 [expr $y0+$y*cos($a)-$x*sin($a)]
	set x -5
	set y -3
	set x3 [expr $x0+$x*cos($a)+$y*sin($a)]
	set y3 [expr $y0+$y*cos($a)-$x*sin($a)]
	set P(robot) [$P(canvas) create polygon [XToCanvas $x1] [YToCanvas $y1] [XToCanvas $x2] [YToCanvas $y2] [XToCanvas $x3] [YToCanvas $y3] -fill gray]
}

proc AngleToXY {a} {
	global P
	switch $a {
		0 {return [list [expr $P(x)+$::op::cm] $P(y)]}
		45 {return [list [expr $P(x)+$::op::cm] [expr $P(y)+$::op::cm]}
		90 {return [list $P(x) [expr $P(y)+$::op::cm]}
		135 {return [list [expr $P(x)-$::op::cm] [expr $P(y)+$::op::cm]}
		180 {return [list [expr $P(x)-$::op::cm] $P(y)}
		225 {return [list [expr $P(x)-$::op::cm] [expr $P(y)-$::op::cm]}
		270 {return [list $P(x) [expr $P(y)-$::op::cm]}
		315 {return [list [expr $P(x)+$::op::cm] [expr $P(y)-$::op::cm]}
	}
}

proc Switch {x y val} {
	global P
	if {[info exists P($x,$y)]==0} {
		puts "($x,$y) is out of range"
		return
	}
	if {$val==0} {
		$P(canvas) itemconfigure $P($x,$y,w) -fill white
	} elseif {$val==1} {
		$P(canvas) itemconfigure $P($x,$y,w) -fill black
	} else {
		$P(canvas) itemconfigure $P($x,$y,w) -fill red
	}
	set P($x,$y) $val
}

### proc \c CreateWindow creating the main window
# param[in] parent Name of the parent widget of the new canvas
# return Name of the created widget
proc CreateWindow {parent} {
	global P
	set f [frame $parent.f]
	pack [frame $f.f] -side bottom -fill x
	pack [button $f.f.calibration -text Calibrate  -command Calibrate] -side left
	pack [button $f.f.connect -text Connect -command OpenConnect] -side left
	pack [frame $f.f.mode] -side left
	pack [radiobutton $f.f.mode.manual -text Manual -command "SetMode 0" -variable P(Mode) -value 0] -side left
	pack [radiobutton $f.f.mode.guide -text Guiding -command "SetMode 1" -variable P(Mode) -value 1] -side left
	pack [radiobutton $f.f.mode.auto -text "D*" -command "SetMode 2" -variable P(Mode) -value 2] -side left
	pack [Label $f.f.status -textvariable P(status)] -side left
	pack [button $f.f.save -text Save -command Save] -side right
	pack [button $f.f.load -text Load -command Load] -side right
	pack [Label $f.f.rstatus -textvariable P(robotstatus)] -side right
	set P(Mode) 0
	set sw [ScrolledWindow $f.s] 
	pack $sw -side top -fill both -expand 1
	set c [CreateCanvas $sw]
	$sw setwidget $c
	return $f
}

proc SetMode {m} {
	global P
	switch $m {
		0 {
			catch {pack forget $P(1,w)}
			catch {pack forget  $P(2,w)}
			pack $P(0,w) -side right
		}
		1 {
			catch {pack forget  $P(0,w)}
			catch {pack forget  $P(2,w)}
			pack $P(1,w) -side right
		}
		2 {
			catch {pack forget  $P(0,w)}
			catch {pack forget  $P(1,w)}
			pack $P(2,w) -side right
		}
	}
	DirectCommand S
	set P(mode) $m
	if {$P(mode)==2} {
		SetTarget $P(targetX) $P(targetY)
	} else {
		HideTarget
	}
	SendRobot "p 0"
	if {$m} {
		SendRobot "m 1"
	} else {
		SendRobot "m 0"
	}
	SendRobot "p $P($m,power)"
}
proc Calibrate {} {
	global P
	namespace eval cal {}
	set ::cal::P(x) $P(x)
	set ::cal::P(y) $P(y)
	set ::cal::P(angle) $P(angle)
	toplevel .calibration
	wm title .calibration Calibration
	pack [frame .calibration.f] -side top
	pack [label .calibration.f.lx -text X] -side left
	pack [SpinBox .calibration.f.x -textvariable ::cal::P(x) -range [list [expr $::op::x1*$::op::cm] [expr $::op::x2*$::op::cm] 1]] -side left
	pack [label .calibration.f.ly -text Y] -side left
	pack [SpinBox .calibration.f.y -textvariable ::cal::P(y) -range [list [expr $::op::y1*$::op::cm] [expr $::op::y2*$::op::cm] 1]] -side left
	pack [label .calibration.f.la -text Angle] -side left
	pack [SpinBox .calibration.f.a -textvariable ::cal::P(angle) -range [list 0 360 1]] -side left
	pack [frame .calibration.b] -side bottom
	pack [button .calibration.b.cancel -text Cancel -command "destroy .calibration"] -side left
	pack [button .calibration.b.ok -text Ok -command CalibrateValidate] -side left
	tkwait visibility .calibration
	grab .calibration
	focus -force .calibration
	tkwait window .calibration
}

proc OpenConnect {} {
	global P
	namespace eval conn {}
	set ::conn::ip $::op::ip
	set ::conn::port $::op::port
	toplevel .ip
	wm title .ip Connection
	pack [frame .ip.f] -side top
	pack [label .ip.f.lx -text "IP address"] -side left
	pack [entry .ip.f.x -textvariable ::conn::ip -width 16] -side left
	pack [label .ip.f.ly -text Port] -side left
	pack [SpinBox .ip.f.y -textvariable ::conn::port -range [list 0 65535 1]] -side left
	pack [frame .ip.b] -side bottom
	pack [button .ip.b.cancel -text Cancel -command "destroy .ip"] -side left
	pack [button .ip.b.ok -text Ok -command ConnectValidate] -side left
	tkwait visibility .ip
	grab .ip
	focus -force .ip
	tkwait window .ip
}

proc ConnectValidate {} {
	global P
	set ::op::ip $::conn::ip
	set ::op::port $::conn::port
	if {[Connect $::conn::ip $::conn::port]} {
		destroy .ip
	}
}

proc CalibrateValidate {} {
	global P
	set P(x) $::cal::P(x)
	set P(y) $::cal::P(y)
	set P(angle) $::cal::P(angle)
	destroy .calibration
	DrawRobot
	SendRobot "r $P(x) $P(y) $P(angle)"
}

proc onPowerchange {mode val} {
	SendRobot "p $val"
}

proc CreateCommandPad {parent} {
	global P
	set f [frame $parent.manual]
	grid [Button $f.up -text Forward -armcommand "DirectCommand F" -disarmcommand "DirectCommand S"] -row 0 -column 1
	grid [Button $f.left -text Left -armcommand "DirectCommand L" -disarmcommand "DirectCommand S"] -row 1 -column 0
	grid [Button $f.down -text Backward -armcommand "DirectCommand B" -disarmcommand "DirectCommand S"] -row 1 -column 1
	grid [Button $f.right -text Right -armcommand "DirectCommand R" -disarmcommand "DirectCommand S"] -row 1 -column 2
	grid [scale $f.power -from 0 -to 100 -label Power -orient horizontal -variable P(0,power) -command "onPowerchange 0"] -row 2 -column 0 -columnspan 3
	set P(0,w) $f
	set f2 [frame $parent.guiding]
	grid [button $f2.nw -text TL -width 2 -command "OffsetCommand -1 1"] -row 0 -column 0
	grid [button $f2.n -text T -width 2 -command "OffsetCommand 0 1"] -row 0 -column 1
	grid [button $f2.ne -text TR -width 2 -command "OffsetCommand 1 1"] -row 0 -column 2
	grid [button $f2.w -text L -width 2 -command "OffsetCommand -1 0"] -row 1 -column 0
	grid [button $f2.h -text "S" -width 2 -command "DirectCommand S"] -row 1 -column 1
	grid [button $f2.e -text R -width 2 -command "OffsetCommand 1 0"] -row 1 -column 2
	grid [button $f2.sw -text BL -width 2 -command "OffsetCommand -1 -1"] -row 2 -column 0
	grid [button $f2.s -text B -width 2 -command "OffsetCommand 0 -1"] -row 2 -column 1
	grid [button $f2.se -text BR -width 2 -command "OffsetCommand 1 -1"] -row 2 -column 2
	grid [scale $f2.power -from 0 -to 100 -label Power -orient horizontal -variable P(1,power) -command "onPowerchange 1"] -row 3 -column 0 -columnspan 3
	set P(1,w) $f2
	set f3 [frame $parent.auto]
	grid [label $f3.l -text Automatic] -row 0 -column 0 -columnspan 3
	grid [scale $f3.power -from 0 -to 100 -label Power -orient horizontal -variable P(2,power) -command "onPowerchange 2"] -row 3 -column 0 -columnspan 3
	set P(2,w) $f3
	return $f
}
proc roundPos {x y} {
	set X [expr round($x/double($::op::cm))*$::op::cm]
	set Y [expr round($y/double($::op::cm))*$::op::cm]
	return [list $X $Y]
}
proc OffsetCommand {ox oy} {
	global P
	foreach {x y} [roundPos $P(x) $P(y)] {}
	set x [expr $x+$ox*$::op::cm]
	set y [expr $y+$oy*$::op::cm]
	SendRobot "g $x $y"
}
proc Save {} {
	global P
	set f [tk_getSaveFile -title "Save obstacle file..." ]
	if {$f!=""} {
		set f [open $f w]
		for {set x $::op::x1} {[expr $x<=$::op::x2]} {incr x $::op::cm} {
			for {set y $::op::y1} {[expr $y<=$::op::y2]} {incr y $::op::cm} {
				puts $f $P($x,$y)
			}
		}
	}
}
proc Load {} {
	global P
	set f [tk_getOpenFile -title "Load obstacle file..." ]
	if {$f!=""} {
		set f [open $f r]
		for {set x $::op::x1} {[expr $x<=$::op::x2]} {incr x $::op::cm} {
			for {set y $::op::y1} {[expr $y<=$::op::y2]} {incr y $::op::cm} {
				set P($x,$y) [gets $f]
				Switch $x $y $P($x,$y)
			}
		}
	}
}
proc Exit {} {
	SendRobot "q"
	after 500 exit
}

namespace eval DL {
	variable U
	variable km
	variable rhs
	variable g
	proc init {} {
		global P
		variable U,km,rhs,g
		set km 0
		if {[array exists U]} {
			array unset U
		}
		if {[array exists g]} {
			array unset g
		}
		if {[array exists rhs]} {
			array unset rhs
		}
		foreach k [array names P -regexp {^[0-9]+,[0-9]+$}] {
			set rhs($k) Inf
			set g(k) Inf
		}
		set rhs($P(targetX),$P(targetX)) 0
		set g($P(targetX),$P(targetX)) 0
		set U($P(targetX),$P(targetX)) [list 0 0]
		set hinitial [heuristic $P(x) $P(y) $P(targetX) $P(targetY)]
		set rhs($P(x),$P(y)) $hinitial
		set g($P(x),$P(y)) $hinitial
		set U($P(targetX),$P(targetX))  [list $initial $initial]
	}
	proc makeNewCell {x y} {
		global P
		variable U,km,rhs,g
		if {[info exists U($x,$y)]==0} {
			set h [heuristic $x $y $P(targetX) $P(targetY)]
			set U($x,$y) [list $h $h]
		}
	}
	proc UpdateVertex {u} {
		variable U,km,rhs,g,Usorted

		set posu [lsearch -index 0 -exact $u $U]
		if {[expr ($g($u)!=$rhs($u)) && ($posu!=-1)} {
			lreplace U $posu [CalculateKey $u]
			set Usorted 0
		} elseif {[expr ($g($u)!=$rhs($u)) && ($posu==-1)} {
			lappend U [CalculateKey $u]
			set Usorted 0
		} elseif {[expr ($g($u)==$rhs($u)) && ($posu!=-1)} {
			set U [lreplace $U $posu $posu]
			set Usorted 0
		}
	}
	proc TopKey {} {
		variable U,Usorted
		if {!$Usorted} {
			set U [lsort -real -index 2 $U]
			set Usorted 1
		}
		if {[llength $U]==0} {
			return [list "" Inf Inf]
		}
		return [lindex $U 0]
	}
	proc CalculateKey {s} {
		variable rhs,g,km
		global P
		set min1 [expr $g($s)<$rhs($s) ? $g($s) : $rhs($s)]
		set min2 [expr $min1+[costP "$P(x),$P(y)" s]+km]
		return [list $s $min2 $min1]
	}
	proc Less {key1 key2} {
		if {[expr [lindex $key1 1]<[lindex $key2 1]]} {return 1}
		if {[expr [lindex $key1 1]>[lindex $key2 1]]} {return 0}
		return [expr [lindex $key1 2]<[lindex $k2 2]]
	}
	proc LessEq {key1 key2} {
		if {[expr [lindex $key1 1]<[lindex $key2 1]]} {return 1}
		if {[expr [lindex $key1 1]>[lindex $key2 1]]} {return 0}
		return [expr [lindex $key1 2]<=[lindex $k2 2]]
	}
	proc ComputeShortestPath {} {
		global P
		variable U,Usorted,g,rhs,km
		set Pstart [XYtoP $P(x) $P(y)]
		while {([Less [TopKey] [CalculateKey $Pstart]]) || ($rhs($Pstart)>$g($Pstart))} {
			set kold [TopKey]
			set u [lindex $kold 0]
			set knew [CalculateKey $u]
			if {[Less $kold $knew]} {
				set U [lreplace $U 0 0] $knew
				set Usorted 0
			} else if {$g($u)>$rhs($u)} {
				set g($u) $rhs($u)
				set U [lreplace $U 0 0]
				set Ptarget [XYtoP $P(targetX) $P(targetY)]
				foreach s [Voisins $u] {
					if {$s!=$Ptarget} {
					#voir h vs c & lexicographic key order
					}
				}
			}
		}
	}
	proc Voisins {u} {
		global P
		PtoXY $u x y
		set res [list]
		if {$x>$::op::x1} {
			lappend res [XYtoP [expr $x-1] $y]
			if {$y>$::op::y1} {
				lappend res [XYtoP [expr $x-1] [expr $y-1]]
			}
			if {$y<$::op::y2} {
				lappend res [XYtoP [expr $x-1] [expr $y+1]]
			}
		}
		if {$y>$::op::y1} {
			lappend res [XYtoP $x [expr $y-1]]
		}
		if {$y<$::op::y2} {
			lappend res [XYtoP $x [expr $y+1]]
		}
		if {$x<$::op::x2} {
			lappend res [XYtoP [expr $x+1] $y]
			if {$y>$::op::y1} {
				lappend res [XYtoP [expr $x+1] [expr $y-1]]
			}
			if {$y<$::op::y2} {
				lappend res [XYtoP [expr $x+1] [expr $y+1]]
			}
		}
		return $res
	}
	proc XYtoP {x y} {
		return "$x,$y"
	}
	proc PtoXY {P x y} {
		upvar $x X
		upvar $y Y
		foreach {X Y} [split $P ,] {}
	}
	proc costP {P1 P2} {
		PtoXY $P1 x1 y1
		PtoXY $P2 x2 y2
		return [cost $x1 $y1 $x2 $y2]
	}
	proc heuristic {x1 y1 x2 y2} {
		global M_SQRT2
		set m [expr abs(x1-x2)]
		set M [expr abs(y1-y2)]
		if {$M<$m} {
			set tmp $M
			set M $m
			set m $tmp
		}
		return [expr $m*(M_SQRT2-1)+$M]
	}
	proc cost {x1 y1 x2 y2 {testobstacle 1}} {
		global P
		if {[expr $testobstacle&&(($P($x1,$y1)>0)||($P($x2,$y2)>0))]} {
			return Inf
		}
		set diffx [expr $x2-$x1]
		set diffy [expr $y2-$y1]
		return [expr sqrt($diffx*$diffx+$diffy*$diffy)]
	}
}

pack [frame .f] -expand true -fill both
pack [CreateCommandPad .f] -side right
pack [CreateWindow .f] -side left -fill both -expand true
wm protocol . WM_DELETE_WINDOW Exit
set P(mode) 0
set P(angle) 0
set P(x) 0
set P(y) 0
set P(targetX) 0
set P(targetY) 0
set P(robotstatus) "???"
DrawRobot
Calibrate
OpenConnect
console show

