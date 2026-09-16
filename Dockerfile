FROM ubuntu:22.04

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository multiverse && \
    apt-get update

RUN echo steam steam/question select "I AGREE" | debconf-set-selections && \
    echo steam steam/license note '' | debconf-set-selections && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        steamcmd ca-certificates gettext-base \
        lib32gcc-s1 lib32stdc++6 && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m -d /home/steam -s /bin/bash steam
USER steam
WORKDIR /home/steam

RUN mkdir -p /home/steam/.steam

RUN /usr/games/steamcmd +force_install_dir /home/steam/pzserver \
    +login anonymous \
    +app_update 380870 validate \
    +quit

COPY --chown=steam:steam servertest.ini.template /home/steam/templates/servertest.ini.template
COPY --chown=steam:steam entrypoint.sh /home/steam/entrypoint.sh
RUN chmod +x /home/steam/entrypoint.sh

EXPOSE 16261/udp
EXPOSE 16262/udp
EXPOSE 27015/tcp

ENTRYPOINT ["/home/steam/entrypoint.sh"]
