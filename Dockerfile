FROM alpine:3.9 as rootfs-stage
MAINTAINER antonchen

# environment
ENV REL=bionic
ENV ARCH=amd64
# install packages
RUN \
 apk add --no-cache \
        bash \
        curl \
        tzdata \
        xz

# grab base tarball
RUN \
 mkdir /root-out && \
 curl -o \
    /rootfs.tar.gz -L \
    https://partner-images.canonical.com/core/${REL}/current/ubuntu-${REL}-core-cloudimg-${ARCH}-root.tar.gz && \
 tar xf \
        /rootfs.tar.gz -C \
        /root-out

# Runtime stage
FROM scratch
COPY --from=rootfs-stage /root-out/ /
LABEL MAINTAINER="Anton Chen <contact@antonchen.com>"

# set version for s6 overlay
ARG OVERLAY_VERSION="v1.22.0.0"
ARG OVERLAY_ARCH="amd64"

# set environment variables
ARG DEBIAN_FRONTEND="noninteractive"
ENV HOME="/root" \
LANGUAGE="en_US.UTF-8" \
LANG="en_US.UTF-8" \
TERM="xterm" \
TZ="UTC"

# copy sources
COPY sources.list /etc/apt/

RUN \
 echo "**** Ripped from Ubuntu Docker Logic ****" && \
 set -xe && \
 echo '#!/bin/sh' \
    > /usr/sbin/policy-rc.d && \
 echo 'exit 101' \
    >> /usr/sbin/policy-rc.d && \
 chmod +x \
    /usr/sbin/policy-rc.d && \
 dpkg-divert --local --rename --add /sbin/initctl && \
 cp -a \
    /usr/sbin/policy-rc.d \
    /sbin/initctl && \
 sed -i \
    's/^exit.*/exit 0/' \
    /sbin/initctl && \
 echo 'force-unsafe-io' \
    > /etc/dpkg/dpkg.cfg.d/docker-apt-speedup && \
 echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' \
    > /etc/apt/apt.conf.d/docker-clean && \
 echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' \
    >> /etc/apt/apt.conf.d/docker-clean && \
 echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' \
    >> /etc/apt/apt.conf.d/docker-clean && \
 echo 'Acquire::Languages "none";' \
    > /etc/apt/apt.conf.d/docker-no-languages && \
 echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' \
    > /etc/apt/apt.conf.d/docker-gzip-indexes && \
 echo 'Apt::AutoRemove::SuggestsImportant "false";' \
    > /etc/apt/apt.conf.d/docker-autoremove-suggests && \
 mkdir -p /run/systemd && \
 echo 'docker' \
    > /run/systemd/container && \
 echo "**** install apt-utils and locales ****" && \
 apt-get update && \
 apt-get install -y \
    apt-utils \
    locales && \
 echo "**** install packages ****" && \
 apt-get install -y \
    curl \
    tzdata && \
 echo "**** generate locale ****" && \
 dpkg-reconfigure -f noninteractive tzdata && \
 locale-gen en_US.UTF-8 && \
 echo "**** add s6 overlay ****" && \
 curl -o \
 /tmp/s6-overlay.tar.gz -L \
    "https://github.com/just-containers/s6-overlay/releases/download/${OVERLAY_VERSION}/s6-overlay-${OVERLAY_ARCH}.tar.gz" && \
 tar xfz \
    /tmp/s6-overlay.tar.gz -C / && \
 echo "**** create abc user and make our folders ****" && \
 useradd -u 911 -U -M -s /bin/false ubuntu && \
 usermod -G users ubuntu && \
 echo "**** cleanup ****" && \
 apt-get clean && \
 rm -rf \
    /tmp/* \
    /var/lib/apt/lists/* \
    /var/tmp/*

# add local files
COPY root/ /

ENTRYPOINT ["/init"]
