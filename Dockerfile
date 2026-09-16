FROM ubuntu:22.04

ENV HOME=/home/steam

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository multiverse && \
    apt-get update && \
    echo steam steam/question select "I AGREE" | debconf-set-selections && \
    echo steam steam/license note '' | debconf-set-selections && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        steamcmd ca-certificates gettext-base \
        lib32gcc-s1 lib32stdc++6 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# OpenShift runs containers as an arbitrary UID that is always a member of
# group 0, so the server user's primary group is 0 and /home/steam is made
# group-writable. Without this the pod cannot write and crashloops.
RUN useradd -u 1001 -g 0 -m -d /home/steam -s /bin/bash steam && \
    mkdir -p /home/steam/templates && \
    chmod -R g=u /home/steam

USER 1001
WORKDIR /home/steam

COPY --chown=1001:0 servertest.ini.template /home/steam/templates/servertest.ini.template
COPY --chown=1001:0 install-server.sh /home/steam/install-server.sh
COPY --chown=1001:0 entrypoint.sh /home/steam/entrypoint.sh
RUN chmod 775 /home/steam/install-server.sh /home/steam/entrypoint.sh && \
    chmod -R g=u /home/steam/templates

EXPOSE 16261/udp
EXPOSE 16262/udp
EXPOSE 27015/tcp

ENTRYPOINT ["/home/steam/entrypoint.sh"]
