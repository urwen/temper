#!/usr/bin/env python3

import argparse
import json

from flask import Flask

from temper import Temper

# parsing config
parser = argparse.ArgumentParser()
parser.add_argument("-H", "--host", default="0.0.0.0", help="host to bind to, default: 0.0.0.0")
parser.add_argument("-p", "--port", default=2600, help="port to listen to, default: 2600")
parser.add_argument("-d", "--debug", default=False, help="debug mode, default: False")

args = parser.parse_args()

host = args.host
port = int(args.port)
debug = args.debug

print(f"host = {host}")
print(f"port = {port}")
print(f"debug = {debug}")

app = Flask("temper")
t = Temper()

@app.route('/list')
def list():
    result = json.dumps(t.usb_devices, indent=2, sort_keys=True)
    return result

@app.route('/metrics')
def metrics():
    result = json.dumps(t.read(), indent=2)
    return result

if __name__ == '__main__':
    app.run(host=host, port=port, debug=debug)
