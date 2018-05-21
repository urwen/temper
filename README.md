# temper.py

The USB temperature and temperature/humidity sensors sold my PCsensor are
widely available from the parent site
(http://pcsensor.com/usb-temperature-humidity.html), from Amazon, and from
EBay.

## Design

There are several open source software projects that support these sensors,
sometimes including complicated monitoring and graphing software. Unlike,
these projects, the goal of this project is to simply read data from the
sensors and do nothing else, given the following constraints:
* must work under Linux,
* must work with Python 3,
* third-party software will be avoided when possible,
* all third-party software must be provided as standard Debian packages.

### libusb is not used

I tried to use libusb (apt-get install python3-usb; "import usb.core") and it
provides a sophisticated interface to USB devices that was very nice.
Unfortunately, I have one thermometer that didn't work with raw usb and that
required access via the hidraw device; and I have another thermometer that has
an undocumented HID protocol, but that is accessible via a serial tty.

### hid and hidapi are not used

I tried using hid (apt-get install python3-hid) and hidapi (apt-get install
python3-hidapi) and these worked ok for two of the thermometers I have, but
not for the one that requires access via a serial tty.

### pySerial is used

Although HID devices are accessed directly, pySerial is used for TTYs. This
module is available as a Debian package:
  sudo apt-get install python3-serial

## Supported Devices

I own three kinds of devices from PCsensors. These are all supported.
Additional notes on how these devices behave can be found in the source code.

* 0c45:7401 TEMPerF1.4 Metal USB stick, temperature only
* 413d:2107 TEMPerX_V3.1 White USB stick, temperature and humidity
* 1a86:5523 TEMPerX232_V2.0 White USB stick, temperature and humidity

Note that 1a86:5523 may identify as 413d:2107 depending on button presses. See
the source code for details.

Note also that if you try other software that uses libusb, the hidraw device
may be disconnected. In this case, remove and re-insert the USB stick.
