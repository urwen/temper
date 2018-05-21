#!/usr/bin/env python3
# temper.py -*-python-*-
# Copyright 2018 by Pham Urwen (urwen@mail.ru)
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

# Standard python3 modules
import argparse
import os
import re
import select
import struct
import sys

# Non-standard modules
try:
  import serial
except:
  print('Cannot import "serial". Please sudo apt-get install python3-serial')
  sys.exit(1)

class Temper(object):
  SYSPATH = '/sys/bus/usb/devices'

  def __init__(self):
    self.usb_devices = self.get_usb_devices()
    self.forced_vendor_id = None
    self.forced_product_id = None

  def _readfile(self, path):
    try:
      with open(path, 'r') as fp:
        return fp.read().strip()
    except:
      return None

  def _find_devices(self, dirname):
    devices = set()
    with os.scandir(dirname) as it:
      for entry in it:
        if entry.is_dir() and not entry.is_symlink():
          devices |= self._find_devices(os.path.join(dirname, entry.name))
        if re.search('tty.*[0-9]', entry.name):
          devices.add(entry.name)
        if re.search('hidraw[0-9]', entry.name):
          devices.add(entry.name)
    return devices

  def _get_usb_device(self, dirname):
    vendorid = self._readfile(os.path.join(dirname, 'idVendor'))
    if vendorid is None:
      return None
    vendorid = int(vendorid, 16)
    productid = self._readfile(os.path.join(dirname, 'idProduct'))
    productid = int(productid, 16)
    vendor_name = self._readfile(os.path.join(dirname, 'manufacturer'))
    product_name = self._readfile(os.path.join(dirname, 'product'))
    busnum = int(self._readfile(os.path.join(dirname, 'busnum')))
    devnum = int(self._readfile(os.path.join(dirname, 'devnum')))
    devices = sorted(self._find_devices(dirname))
    return dirname, busnum, devnum, vendorid, productid, vendor_name, \
      product_name, devices

  def get_usb_devices(self):
    usb_devices = []
    with os.scandir(Temper.SYSPATH) as it:
      for entry in it:
        if entry.is_dir():
          device = self._get_usb_device(os.path.join(Temper.SYSPATH,
                                                     entry.name))
          if device is not None:
            usb_devices.append(device)
    return usb_devices

  def list(self):
    for path, busnum, devnum, vendorid, productid, vendor_name, product_name, \
        devices in sorted(self.usb_devices,
                          key=lambda x: x[1] * 1000 + x[2]):
      print('Bus %03d Dev %03d %04x:%04x %s %s %s' % (
        busnum,
        devnum,
        vendorid,
        productid,
        '*' if self._is_known_id(vendorid, productid) else ' ',
        product_name if product_name is not None else '???',
        list(devices)))

  def _is_known_id(self, vendorid, productid):
    '''
    Returns True if the vendorid and product id are valid.
    '''
    if self.forced_vendor_id is not None and \
       self.forced_product_id is not None:
      if self.forced_vendor_id == vendorid and \
         self.forced_product_id == productid:
        return True
      return False

    if vendorid == 0x0c45 and productid == 0x7401:
      # firmware identifier: TEMPerF1.4
      #
      # physical description: Metal USB stick marked "TEMPer" with thermometer
      # logo on one side, and "TEMPer" on the other side. The end has a screw
      # hole.
      #
      # This model does not have a humidity device.
      return True
    if vendorid == 0x413d and productid == 0x2107:
      # firmware identifier: TEMPerX_V3.1
      #
      # physical description: White plastic USB stick marked "TEMPerHUM",
      # "-40C - +85C", "0-100%RH"; with blue button marked "TXT". On the
      # reverse, "PCsensor". This model does not have a jack on the end.
      #
      # notes: When the button is pressed the red LED will blink as messages
      # of the following are sent (the temperature line repeats every second).
      #
      # www.pcsensor.com
      # temperx v3.1
      # caps lock:on/off/++
      # num lock:off/on/--
      # type:inner-h2
      # inner-temperinner-humidityinterval
      # 32.73 [c]36.82 [%rh]1s
      #
      # This program uses the mode where the LED is off or solid.
      return True
    if vendorid == 0x1a86 and productid == 0x5523:
      # firmware identifier: TEMPerX232_V2.0
      #
      # physical description: White plastic USB stick marked "TEMPerX232",
      # "0-100%RH", "-40 - +85C"; with a green button marked "press". On the
      # reverse, "PCsensor". On the end, a jack for an external temperature
      # sensor (which I do not have and did not try).
      #
      # notes: When the button is pressed and held down until the red LED is
      # solid, a blue LED will flash every second. In this mode, the USB
      # vendor:product is 413d:2107, but only one HID device is available, and
      # protocol sent to the hidraw device is rejected with an error.
      #
      # When the LED is flashing blue, and the button is pressed momemtarily,
      # the following are sent (the temperature line repeats every second).
      #
      # www.PCsensor.com
      # TEMPerX232-V2.0
      # type:inner-H2
      # inner-temperinner-humidityinterval
      # 30.48 [C]40.19 [%RH]1
      #
      # When the button is pressed and held down until the red LED is solid, a
      # green LED will flash every second. This is the mode that this program
      # uses. In this mode, if "Help" is sent to the serial device, the
      # following will be sent back:
      #
      #    >>PCsensor<<
      # Welcome to use TEMPerX232!
      # Firmware Version:TEMPerX232_V2.0
      # The command is:
      #     ReadTemp                     -->read temperature,temp_value = sensor_value + calibration
      #     ReadCalib                    -->read calibration
      #     SetCalib-type:xx.x,xx.x>     -->set calibration, xx.x(-10.0~+10.0)
      #     EraseFlash                   -->erase calibration
      #     Version                      -->read firmware version
      #     ReadType                     -->read the sensor type
      #     ReadAlert-Temp               -->read temp alert value
      #     SetTempUpperAlert-type:xx.xx>-->set temp upper alert value,xx.xx(-40.00~+85.00)
      #     SetTempLowerAlert-type:xx.xx>-->set temp lower alert value,xx.xx(-40.00~+85.00)
      #     ReadAlert-Hum                -->read hum alert value
      #     SetHumUpperAlert-type:xx.xx> -->set hum upper alert value,xx.xx(00.00~99.99)
      #     SetHumLowerAlert-type:xx.xx> -->set hum lower alert value,xx.xx(00.00~99.99)
      #     SetMode-Temp:x>              -->set tempmode, x(0~1)
      #     ReadMode-Temp                -->read tempmode
      #     Help                         -->command help
      #     ?                            -->command help
      # The COM configuration is:
      #     Mode:       ASCII
      #     Baud Rate:  9600bps
      #     Data Bit:   8
      #     Parity Bit: None
      #     Stop Bit:   1
      # SHENZHEN RDing Tech CO.,LTD
      # www.PCsensor.com
      #
      # If "ReadTemp" is sent, the replay is "Temp-Inner:30.53 [C],39.92 [%RH]<"
      # If "Version" is sent, the reply is "TEMPerX232_V2.0"
      # If "ReadType" is sent, the reply is "Type:Inner-H2"
      # If "ReadMode-Temp" is sent, the reply is "TempMode:0"
      # If "ReadCalib" is sent, the reply is:
      #    Inner-Calib:0.0 [C],0.0 [%RH]
      #    Outer-Calib:0.0 [C],0.0 [%RH]
      return True

    # The id is not known to this program.
    return False

  def _read_hidraw(self, device):
    path = os.path.join('/dev', device)
    ident = b''
    bytes = b''
    fd = os.open(path, os.O_RDWR)

    # Get identifier
    os.write(fd, struct.pack('8B', 0x01, 0x86, 0xff, 0x01, 0, 0, 0, 0))
    while True:
      r, _, _ = select.select([fd], [], [], 0.1)
      if fd not in r:
        break
      data = os.read(fd, 8)
      ident += data

    if ident == '':
      return None

    # Get temperature
    os.write(fd, struct.pack('8B', 0x01, 0x80, 0x33, 0x01, 0, 0, 0, 0))
    while True:
      r, _, _ = select.select([fd], [], [], 0.1)
      if fd not in r:
        break
      data = os.read(fd, 8)
      bytes += data

    os.close(fd)
    if ident[:10] == b'TEMPerF1.4':
      degC = struct.unpack_from('>h', bytes, 2)[0] / 256.0
      return str(ident[:10], 'latin-1'), degC, degC * 1.8 + 32.0, None

    if ident[:12] == b'TEMPerX_V3.1':
      degC = struct.unpack_from('>h', bytes, 2)[0] / 100.0
      humidity = struct.unpack_from('>h', bytes, 4)[0] / 100.0
      return str(ident[:12], 'latin-1'), degC, degC * 1.8 + 32.0, humidity

  def _read_serial(self, device):
    path = os.path.join('/dev', device)
    s = serial.Serial(path, 9600)
    s.bytesize = serial.EIGHTBITS
    s.parity = serial.PARITY_NONE
    s.stopbits = serial.STOPBITS_ONE
    s.timeout = 2
    s.xonoff = False
    s.rtscts = False
    s.dsrdtr = False
    s.writeTimeout = 0
    s.write(b'Version')
    ident = str(s.readline(), 'latin-1').strip()
    s.write(b'ReadTemp')
    reply = str(s.readline(), 'latin-1').strip()
    s.close()

    m = re.search(r'Temp-Inner:([0-9.]*).*, ?([0-9.]*)', reply)
    if m is None:
      raise Exception('Cannot parse temperature/humidity')
    degC = float(m.group(1))
    humidity = float(m.group(2))
    return ident, degC, degC * 1.8 + 32.0, humidity

  def read(self):
    for path, busnum, devnum, vendorid, productid, vendor_name, product_name, \
        devices in sorted(self.usb_devices,
                          key=lambda x: x[1] * 1000 + x[2]):
      if not self._is_known_id(vendorid, productid):
        continue

      if len(devices) == 0:
        print('Bus %03d Dev %03d %04x:%04x Error: no hid/tty devices available'
              % (busnum,
                 devnum,
                 vendorid,
                 productid))
        continue

      device, degC, degF, humidity = None, None, None, None
      try:
        system_device = devices[-1]
        if system_device.startswith('hidraw'):
          device, degC, degF, humidity = self._read_hidraw(system_device)
        elif system_device.startswith('tty'):
          device, degC, degF, humidity = self._read_serial(system_device)
      except Exception as exception:
        # In this case, a program using libusb probably asked the hidraw
        # driver to be unloaded. Or the device is not accessible.
        print('Bus %03d Dev %03d %04x:%04x Error: %s' % (
          busnum,
          devnum,
          vendorid,
          productid,
          str(exception)))
      else:
        print('Bus %03d Dev %03d %04x:%04x %s %.2fC %.2fF %.2f%%' % (
          busnum,
          devnum,
          vendorid,
          productid,
          device if device is not None else 'unknown',
          degC if degC is not None else 0,
          degF if degF is not None else 0,
          humidity if humidity is not None else 0))

  def main(self):
    parser = argparse.ArgumentParser(description='temper')
    parser.add_argument('-l', '--list', action='store_true',
                        help='List all USB devices')
    parser.add_argument('--force', type=str,
                        help='Force the use of the hex id; ignore other ids',
                        metavar=('VENDOR_ID:PRODUCT_ID'))
    args = parser.parse_args()

    if args.list:
      self.list()
      return 0
    if args.force:
      ids = args.force.split(':')
      if len(ids) != 2:
        print('Cannot parse hexadecimal id: %s' % args.force)
        return 1
      try:
        vendor_id = int(ids[0], 16)
        product_id = int(ids[1], 16)
      except:
        print('Cannot parse hexadecimal id: %s' % args.force)
        return 1
      self.forced_vendor_id = vendor_id;
      self.forced_product_id = product_id;

    self.read()
    return 0

if __name__ == "__main__":
  temper = Temper()
  sys.exit(temper.main())
