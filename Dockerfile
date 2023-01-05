FROM ubuntu:22.04
LABEL maintainer "tuan t. pham" <tuan@vt.edu>

ENV PKGS="python3 python3-serial python3-pip" \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get -yq update && apt-get dist-upgrade -yq \
    && apt-get -yq install --no-install-recommends  ${PKGS} \
    && pip3 install flask

RUN apt-get autoremove -yq \
    && apt-get autoclean \
    && rm -fr /tmp/* /var/lib/apt/lists/*

RUN mkdir -p /opt/temper/bin

COPY temper.py /opt/temper/bin
COPY temper-service.py /opt/temper/bin

EXPOSE 2610

WORKDIR /opt/temper/bin
# This is used at commandline such as
# docker run --rm -it temper/service:latest -h
ENTRYPOINT  ["/opt/temper/bin/temper-service.py"]
