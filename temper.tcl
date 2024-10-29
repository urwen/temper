#!/usr/bin/env tclsh
# temper.py -*-python-*-
# Copyright 2018 by Pham Urwen (urwen@mail.ru)
# Transformed to Tcl  (avlplus42@gmail.com)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.

#import json

namespace eval USBList {
   variable SYSPATH "/sys/bus/usb/devices"

   # Get a list of all of the USB devices on a system, along with their
   # associated hidraw or serial (tty) devices.

   proc readfile {path} {
      # Read data from 'path' and return it as a string. Return the empty string
      # if the file does not exist, cannot be read, or has an error.
      try {
         set fp [open $path "rb"]; set data [read $fp]; close $fp
         return [string trimright $data "\n"]
      } on error {msg o} {
         return ""
      }
   }

   proc find_devices {dirname} {
      # Scan a directory hierarchy for names that start with "tty" or "hidraw".
      # Return these names in a set.
 
      set devices {}
      foreach entry [glob -directory $dirname -tails -nocomplain "*"] {
         set path [file join $dirname $entry]
         if {[file isdirectory $path] && [file type $path] ne "link"} {
            lappend devices {*}[find_devices $path]
         }
         if {[string match {tty*[0-9]*} $entry] ||
             [string match {hidraw[0-9]*} $entry] } {
            lappend devices $entry
         }
      }
      return $devices
   }

   proc get_usb_device {dirname} {
      # Examine the files in 'dirname', looking for files with well-known
      # names expected to be in the /sys hierarchy under Linux for USB devices.
      # Return a dictionary of the information gathered. If no information is found
      # (i.e., because the directory is not for a USB device) return None.

      set info [dict create "vendorid" ""  "productid" ""  "manufacturer" "" \
                            "product" ""   "busnum" ""  "devnum" ""  "devices" ""   \
                            "firmware" ""  "error" ""   "port" "" ]
      dict set info "vendorid"     [readfile [file join $dirname "idVendor"] ]
      if {[dict get $info "vendorid"] eq ""} { return "" }
      dict set info "productid"    [readfile [file join $dirname "idProduct"] ]
      if {[dict get $info "productid"] eq ""} { return "" }
      dict set info "manufacturer" [readfile [file join $dirname "manufacturer"] ]
      dict set info "product"      [readfile [file join $dirname "product"] ]
      dict set info "busnum"       [readfile [file join $dirname "busnum"] ]
      dict set info "devnum"       [readfile [file join $dirname "devnum"] ]
      dict set info "devices"      [find_devices $dirname]
      return $info
   }

   proc get_usb_devices {} {
      variable SYSPATH
      # Scan a well-known Linux hierarchy in /sys and try to find all of the
      # USB devices on a system. Return these as a dictionary indexed by the path.

      set result {}
      foreach entry [glob -directory $SYSPATH -tails -nocomplain "*"] {
         set path [file join $SYSPATH $entry]
         if {[file isdirectory $path]} {
            set device [get_usb_device $path]
            if {[dict exists $device "vendorid"]} {
               dict set device "port" $entry
               set busdev "[dict get $device busnum]_[dict get $device devnum]"
               lappend result $path $busdev $device
            }
         }
      }
      return [lsort -index 1 -stride 3 $result]
   }
}

namespace eval USBRead {
   # Read temperature and/or humidity information from a specified USB device.

   proc init {dev {verb false}} {
      variable  device $dev  verbose $verb
   }
  
   proc parse_bytes {name offset divisor bytes &info {verb false}} {
      upvar 1 ${&info} info

      # Data is returned from several devices in a similar format. In the first
      # 8 bytes, the internal sensors are returned in bytes 2 and 3 (temperature)
      # and in bytes 4 and 5 (humidity). In the second 8 bytes, external sensor
      # information is returned. If there are only external sensors, then only 8
      # bytes are returned, and the caller is expected to use the correct 'name'.
      # The caller is also expected to detect the firmware version and provide the
      # appropriate divisor, which is usually 100 or 256.
  
      # There is no return value. Instead 'info[name]' is update directly, if a
      # value is found.

      try {
         binary scan $bytes "@${offset}cucu" off0 off1
         if {$off0 == 0x4e && $off1 == 0x20} {
            return
         }

         # Big endian, short (signed) integer (2 Bytes)
         dict set info $name [expr {($off0*256+$off1) / $divisor}]

      } on error {msg o} {
         puts stderr $msg
         return
      }
   }
  
   proc read_hidraw_firmware {fd {verb false}} {
      # Get firmware identifier'''

      set hquery "01 86 ff 01 00 00 00 00"
      set query [binary format "H*" [join $hquery ""]]
      if {$verb} {
         puts [format "Firmware query: %s" [join $hquery ""]]
      }
  
      # Sometimes we don't get all of the expected information from the
      # device.  We'll retry a few times and hope for the best.
      # See: https://github.com/urwen/temper/issues/9
      foreach i [lrepeat 10 ""] {
         puts -nonewline $fd $query; flush $fd
        
         set firmware ""
         while {1} {
            after 100; set data [read $fd 8]
            if {$data eq ""} { break }
            append firmware $data
         }
        
         if {$firmware eq ""} {
            close $fd
            throw "Cannot read device firmware identifier"
         }
        
         if {[string length $firmware] > 8 } { break }
      }
        
      if {$verb} {
         binary scan $firmware H* hfirm
         puts [format "Firmware value: %s %s" \
            $hfirm $firmware]
      }
  
      return $firmware
   }
  
   proc read_hidraw {device} {
      variable verbose

      # Using the Linux hidraw device, send the special commands and receive the
      # raw data. Then call 'parse_bytes' based on the firmware version to provide
      # temperature and humidity information.
      #
      # A dictionary of temperature and humidity info is returned.

      set path [file join "/dev" $device]
      set fd [open $path "r+b"]
      fconfigure $fd -blocking off
  
      set firmware [read_hidraw_firmware $fd $verbose]
  
      # Get temperature/humidity
      set hquery "01 80 33 01 00 00 00 00"
      set query [binary format "H*" [join $hquery ""]]
  
      puts -nonewline $fd $query; flush $fd

      set bytes ""
      while {1} {
         after 100; set data [read $fd 8]
         if {$data eq ""} { break }
         append bytes $data
      }
      close $fd; binary scan $bytes H* hbytes

      if {$verbose} {
         puts [format "Data value: %s" $hbytes]
      }
  
      set sfirm [encoding convertfrom iso8859-1 $firmware]
      binary scan $firmware H* hfirm
      set info [dict create]
      dict set info "firmware" $sfirm
      dict set info "hex_firmware" $hfirm
      dict set info "hex_data" $hbytes
  
      switch -glob -- $sfirm {
         "TEMPerF1.2*" - "TEMPerF1.4*" - "TEMPer1F1.*" {
            dict set info "firmware" [string range $sfirm 0 9]
            parse_bytes "internal temperature"  2 256.0 $bytes info $verbose
            return $info
         }
         "TEMPerGold_V3.1*" - "TEMPerGold_V3.3*" - "TEMPerGold_V3.4*" - "TEMPerGold_V3.5*" {
            dict set info "firmware" [string range $sfirm 0 14]
            parse_bytes "internal temperature"  2 100.0 $bytes info $verbose
            return $info
         }
         "TEMPerX_V3.1*" - "TEMPerX_V3.3*" {
            dict set info "firmware" [string range $sfirm 0 11]
            parse_bytes "internal temperature"  2 100.0 $bytes info $verbose
            parse_bytes "internal humidity"     4 100.0 $bytes info $verbose
            parse_bytes "external temperature" 10 100.0 $bytes info $verbose
            parse_bytes "external humidity"    12 100.0 $bytes info $verbose
            return $info
         }
         "TEMPer2_M12_V1.3*" {
            dict set info "firmware" [string range $sfirm 0 15]
            parse_bytes "internal temperature"  2 256.0 $bytes info $verbose
            parse_bytes "external temperature"  4 256.0 $bytes info $verbose
            return $info
         }
         "TEMPer2_V3.7*" - "TEMPer2_V3.9" {
            dict set info "firmware" [string range $sfirm 0 11]
            #Bytes 3-4 hold the device temp, divide by 100
            parse_bytes "internal temperature"  2 100.0 $bytes info $verbose
            #Bytes 11-12 hold the external temp, divide by 100
            parse_bytes "external temperature" 10 100.0 $bytes info $verbose
            return $info
         }
         "TEMPerHUM_V3.9*" {
            dict set info "firmware" [string range $sfirm 0 13]
            #Bytes 3-4 hold the device temp, divide by 100
            parse_bytes "internal temperature"  2 100.0 $bytes info $verbose
            #Bytes 11-12 hold the external temp, divide by 100
            parse_bytes "external temperature" 10 100.0 $bytes info $verbose
            #Bytes 5-6 hold the device humidity, divide by 100
            parse_bytes "internal humidity"     4 100.0 $bytes info $verbose
            return $info
         }
         "TEMPer1F_H1V1.5F*" {
            dict set info "firmware" [string range $sfirm 0 15]
            parse_bytes "internal temperature"  2   1   $bytes info $verbose
            parse_bytes "internal humidity"     4   1   $bytes info $verbose

            # The values are not aligned to the byte boundary, so shift them. And
            # then apply the equations from the SHT20 data sheet.
            set t [expr {[dict get $info "internal temperature"] << 2}]
            if {$verbose} { puts [format "Raw temperature: %s" $t] }
            set t [expr {-46.85 + 175.72 * $t / 65536}]
            dict set info "internal temperature" $t
            set h [expr {[dict get $info "internal humidity"] << 4}]
            if {$verbose} { puts [format "Raw humidity: %s" $h] }
            set h [expr {-6 + 125.0 * $h / 65536}]
            dict set info "internal humidity" $h
            return $info
         }
         default {
            dict set info "error" [format "Unknown firmware %s: %s" $sfirm $hbytes]
         }
      }

      return $info
   }
  
   proc read_serial {device} {

      # Using the Linux serial device, send the special commands and receive the
      # text data, which is parsed directly in this method.
  
      # A dictionary of device info (like that returned by USBList) combined with
      # temperature and humidity info is returned.

      set path [file join "/dev" $device]
      set fd [open $path "r+b"]
      fconfigure $fd -mode 9600,8,n,1 -blocking off
      #s.xonoff = False
      #s.rtscts = False
      #s.dsrdtr = False
  
      # Send the "Version" command and save the reply.
      puts $fd "Version"; flush $fd
      set firmware [encoding convertfrom iso8859-1 [gets $fd]]
  
      # Send the "ReadTemp" command and save the reply.
      puts $fd "ReadTemp"; flush $fd
      set    reply [encoding convertfrom iso8859-1 [gets $fd]]\n
      append reply [encoding convertfrom iso8859-1 [gets $fd]]\n
      close $fd
  
      set info [dict create "firmware" $firmware ]
      if {[regexp {Temp-Inner:([0-9.]*).*, ?([0-9.]*)} $reply _ g1 g2 ]} {
         dict set info "internal temperature" [expr {double($g1)}]
         dict set info "internal humidity"    [expr {double($g2)}]
      } else {
         dict set info "internal temperature" "-"
         dict set info "internal humidity"    "-"
      }
      if {[regexp {Temp-Outer:([0-9.]*)} $reply _ g1 ]} {
         dict set info "external temperature" [expr {double($g1)}]
      } else {
         dict set info "external temperature" "-"
      }
      return $info
   }
  
   proc readdev {} {
      # Read the firmware version, temperature, and humidity from the device and
      # return a dictionary containing these data.
      variable device

      # Use the last device found
      if {[string match "hidraw*" $device]} {
         return [read_hidraw $device]
      } elseif {[string match "tty*" $device]} {
         return [read_serial $device]
      }
      return [dict create "error" "No usable hid/tty devices available"]
   }
}

namespace eval Temper {
   variable SYSPATH "/sys/bus/usb/devices"
   variable KNOWN {
      "0c45:7401" "0c45:7402" 
      "413d:2107" 
      "1a86:5523" "1a86:e025"
      "3553:a001"
   }

   proc init {} {
      variable usb_devices [USBList::get_usb_devices]
      variable forced_vendor_id ""
      variable forced_product_id ""

      # foreach {x y z} $usb_devices { puts "$x $y $z" }
   }

   proc is_known_id {vendorid productid} {
      variable forced_vendor_id; variable forced_product_id; variable KNOWN

      # Returns True if the vendorid and productid are valid.
      if {$forced_vendor_id ne "" && $forced_product_id ne ""} {
         return [expr {$forced_vendor_id eq $vendorid && $forced_product_id eq $productid}]
      }
      set vidpid "$vendorid:$productid"
      return [expr {$vidpid in $KNOWN}]
   }

   proc listdevs {{use_json false}} {
      variable usb_devices
      # Print out a list all of the USB devices on the system. If 'use_json' is
      # true, then JSON formatting will be used.

      if {$use_json} {
         #print(json.dumps(self.usb_devices, indent=4))
         puts stderr "TODO: json not yet implemented"
         return
      }
  
      # original sorting by:
      # key=lambda x: x[1]['busnum'] * 1000 + x[1]['devnum']):
      foreach {path busdev info} $usb_devices {
         dict with info {
            puts [format "Bus %03d Dev %03d %s:%s %s %s %s" \
               $busnum $devnum $vendorid $productid \
               [expr {[is_known_id $vendorid $productid] ? "*" : " "}] \
               $product [list $devices] \
            ]
         }
      }
   }

   proc readdevs {{verb false}} {
      variable usb_devices
      # Read all of the known devices on the system and return a list of
      # dictionaries which contain the device information, firmware information,
      # and environmental information obtained. If there is an error, then the
      # 'error' field in the dictionary will contain a string explaining the
      # error.

      set results {}
      foreach {path busdev info} $usb_devices {
         dict with info {
            if {![is_known_id $vendorid $productid]} { continue }

            if {[llength $devices] == 0} { continue }
            USBRead::init [lindex $devices end] $verb
            set result [dict merge $info [USBRead::readdev]]
            lappend results $result
         }
      }
      return $results
   }

   proc add_temperature {name info} {
      # Helper method to add the temperature to a string in both Celsius and
      # Fahrenheit. If no sensor data is available, then '- -' will be returned.

      if { ! [dict exists $info $name] } { return "- -" }

      set degC [dict get $info $name]
      set degF [expr {$degC * 1.8 + 32.0}]
      return [format {%.2fC %.2fF} $degC $degF]
   }

   proc add_humidity {name info} {
      # Helper method to add the humidity to a string. If no sensor data is
      # available, then '-' will be returned.
   
      if { ! [dict exists $info $name] } { return "- -" }
      return [format {%d%%} [expr {int([dict get $info $name])}]]
   }
   
   proc print {results {use_json false}} {
      # Print out a list of all of the known USB sensor devices on the system.
      # If 'use_json' is True, then JSON formatting will be used.
      
      if {$use_json} {
         #print(json.dumps(results, indent=4))
         puts stderr "TODO: json not yet implemented"
         return
      }
      
      foreach {info} $results {
         dict with info {
            set res [format "Bus %03d Dev %03d %s:%s %s" \
               $busnum $devnum $vendorid $productid $firmware ]

            if {$error ne ""} {
               append res [format { Error: %s} $error]
            } else {
               append res " " [add_temperature "internal temperature" $info]
               append res " " [add_humidity    "internal humidity"    $info]
               append res " " [add_temperature "external temperature" $info]
               append res " " [add_humidity    "external humidity"    $info]
            }
         }
         puts $res
      }
   }
   
   proc main {argv} {
      # An example 'main' entry point that can be used to make temper.py a
      # standalone program.
      
      set listdevs false; set use_json false; set verbose false
      for {set idx 0} {$idx < [llength $argv]} {incr idx} {
         set arg [lindex $argv $idx]
         switch -exact -- $arg {
            "-l" - "--list" { set listdevs true }
            "--json"        { set use_json true }
            "--verbose"     { set verbose  true }
            "--force"       {
               incr idx; set arg [lindex $argv $idx]
               lassign [split $arg ":"] vendor_id product_id
               variable forced_vendor_id  $vendor_id
               variable forced_product_id $product_id
               set force true
            }
            "--help" {
               puts stderr "usage: $::argv0 \[options ...\]"
               puts stderr "-l or --list    : List all USB devices"
               puts stderr "--json          : Provide output as JSON"
               puts stderr "--force Vid:Pid : Force the use of the hex id; ignore other ids"
               puts stderr "--verbose       : Output binary data from thermometer"
               exit 1
            }
            default { puts stderr "Unknown argument: '$arg'" }
         }
      }

      if {$listdevs} {
         listdevs $use_json
         return 0
      }
      
      # By default, output the temperature and humidity for all known sensors.
      set results [readdevs $verbose]
      print $results $use_json
      return 0
   }
}

Temper::init
set rc [Temper::main $argv]
exit $rc

