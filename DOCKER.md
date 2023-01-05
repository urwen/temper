Running temper as a service in docker container
===============================================
*The container provides the sensor metrics via web API*

* Default port: `2610`
* endpoint `/list`: List available USB devices in JSON format
* endpoint `/metrics`: Send metrics from available temper devices in JSON format

Running the service as a commandline
------------------------------------
```
docker run --rm -it -p 2610:2610 temper/service:latest
```


Snippet of config in `docker-compose.yml`
-----------------------------------------
```
---
version: '3'

services:
  temper:
    container_name: temper
    hostname: temper
    image: temper/service:latest
    restart: always
    ports:
      - 2610:2610
```

Running the docker as a service using docker-compose config.
```
docker-compose up -d
```

Running the script `temper.py` from docker container
----------------------------------------------------
You can run `temper.py` as a docker container by overriding the entrypoint.
```
docker run --rm -it --entrypoint /opt/temper/bin/temper.py temper/service:latest --help
usage: temper.py [-h] [-l] [--json] [--force VENDOR_ID:PRODUCT_ID] [--verbose]

temper

options:
  -h, --help            show this help message and exit
  -l, --list            List all USB devices
  --json                Provide output as JSON
  --force VENDOR_ID:PRODUCT_ID
                        Force the use of the hex id; ignore other ids
  --verbose             Output binary data from thermometer
```

Note: This dockerization effort was sponsored by Greenfly SAU LLC.
