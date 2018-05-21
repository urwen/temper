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

## Example Command Output

### Help

  $ ./temper.py --help
  usage: temper.py [-h] [-l] [--json] [--force VENDOR_ID:PRODUCT_ID]

  temper

  optional arguments:
  -h, --help            show this help message and exit
  -l, --list            List all USB devices
  --json                Provide output as JSON
  --force VENDOR_ID:PRODUCT_ID
                        Force the use of the hex id; ignore other ids

### List Devices

In this example, one of the devices doesn't have the HID driver attached
because I was using an libusb-based program to access it.

  $ ./temper.py -l
  Bus 001 Dev 023 413d:2107 * ??? ['hidraw0', 'hidraw1']
  Bus 001 Dev 086 0c45:7401 * TEMPerV1.4 []
  Bus 002 Dev 002 04d8:f5fe   TrueRNG ['ttyACM0']

### Temperature

In this example, one of the devices doesn't have the HID driver attached
because I was using an libusb-based program to access it.

  $ ./temper.py
  Bus 001 Dev 023 413d:2107 TEMPerX_V3.1 26.55C 79.79F 43.41%
  Bus 001 Dev 086 0c45:7401 Error: no hid/tty devices available

  $ ./temper.py --json
  [
      {
          "path": "/sys/bus/usb/devices/1-1.2",
          "busnum": 1,
          "devnum": 23,
          "vendorid": 16701,
          "productid": 8455,
          "vendor_name": "",
          "product_name": "",
          "devices": [
              "hidraw0",
              "hidraw1"
          ],
          "ident": "TEMPerX_V3.1",
          "celsius": 26.55,
          "fahrenheit": 79.78999999999999,
          "humidity": 43.65
      },
      {
          "path": "/sys/bus/usb/devices/1-1.1.1",
          "busnum": 1,
          "devnum": 86,
          "vendorid": 3141,
          "productid": 29697,
          "vendor_name": "RDing",
          "product_name": "TEMPerV1.4",
          "devices": [
          ],
          "error": "no hid/tty devices available"
      }
  ]

Similar JSON output can be generated with the --list option.
