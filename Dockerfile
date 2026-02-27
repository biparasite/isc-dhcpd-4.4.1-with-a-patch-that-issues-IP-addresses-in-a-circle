FROM debian:bookworm-slim AS builder

ARG ISC_DHCP_VERSION=4.4.1
ARG BISON_VERSION=2:3.8.2+dfsg-1+b1
ARG BUILD_ESSENTIAL_VERSION=12.9
ARG CA_CERTIFICATES_VERSION=20230311*
ARG FILE_VERSION=1:5.44*
ARG FLEX_VERSION=2.6.4-8.2
ARG LIBSSL_DEV_VERSION=3.0.*
ARG PATCH_VERSION=2.7.6-7
ARG WGET_VERSION=1.21.3-1+deb12u1
ARG IPROUTE2_VERSION=6.1*
ENV DEBIAN_FRONTEND=noninteractive
ENV CFLAGS="-g -O2 -Wall -Wno-error -fno-strict-aliasing -fcommon"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bison=${BISON_VERSION} \
        build-essential=${BUILD_ESSENTIAL_VERSION} \
        ca-certificates=${CA_CERTIFICATES_VERSION} \
        file=${FILE_VERSION} \
        flex=${FLEX_VERSION} \
        libssl-dev=${LIBSSL_DEV_VERSION} \
        patch=${PATCH_VERSION} \
        wget=${WGET_VERSION} \
        iproute2=${IPROUTE2_VERSION} \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN wget --progress=dot:giga -O dhcp.tar.gz "https://ftp.isc.org/isc/dhcp/${ISC_DHCP_VERSION}/dhcp-${ISC_DHCP_VERSION}.tar.gz" \
    && tar -xzf dhcp.tar.gz

WORKDIR /build/dhcp-${ISC_DHCP_VERSION}
COPY dhcp-4.4.1-dd-patch/ /tmp/dhcp-4.4.1-dd-patch/

RUN patch -p0 < /tmp/dhcp-4.4.1-dd-patch/dhcpd.c.diff \
    && patch -p0 < /tmp/dhcp-4.4.1-dd-patch/dhcp.c.diff
RUN ./configure --prefix=/usr --sysconfdir=/etc/dhcp --localstatedir=/var \
    && make \
    && make install DESTDIR=/out

FROM debian:bookworm-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive
ARG RUNTIME_CA_CERTIFICATES_VERSION=20230311*
ARG LIBSSL3_VERSION=3.0.*
ARG RUNTIME_IPROUTE2_VERSION=6.1*
ARG PROCPS_VERSION=2:4.0.*

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates=${RUNTIME_CA_CERTIFICATES_VERSION} \
        libssl3=${LIBSSL3_VERSION} \
        iproute2=${RUNTIME_IPROUTE2_VERSION} \
        procps=${PROCPS_VERSION} \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /out/usr/sbin/dhcpd /usr/sbin/dhcpd
COPY --from=builder /out/etc/dhcp /etc/dhcp

RUN mkdir -p /var/lib/dhcp
RUN printf '%s\n' \
    '#!/bin/sh' \
    'set -eu' \
    'exec /usr/sbin/dhcpd "$@" 2>&1' \
    > /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 67/udp 68/udp

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["-f", "-4", "-d", "-dd", "-cf", "/etc/dhcp/dhcpd.conf", "-lf", "/var/lib/dhcp/dhcpd.leases", "-pf", "/tmp/dhcpd.pid", "eth0"]
