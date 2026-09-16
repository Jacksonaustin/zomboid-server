FROM ubuntu:22.04

# OpenShift gives the container an arbitrary UID with no /etc/passwd entry, so
# HOME would otherwise come through unset or as "/". Pin it here.
ENV HOME=/home/steam

# One apt layer: enable i386 (steamcmd is a 32-bit binary) and multiverse
# (where Ubuntu ships steamcmd), pre-accept Valve's license so the build does
# not hang on an interactive prompt, then clean package lists in the SAME
# layer - cleaning them in a later layer would leave the originals behind.
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

# The arbitrary UID OpenShift assigns is always a member of group 0, so the
# server user's PRIMARY group is 0 and everything under /home/steam is made
# group-writable. Without this the pod cannot write its own config or saves
# and crashloops immediately on startup.
RUN useradd -u 1001 -g 0 -m -d /home/steam -s /bin/bash steam && \
    chmod -R g=u /home/steam

USER 1001
WORKDIR /home/steam

RUN mkdir -p /home/steam/.steam

# steamcmd's very first run on a fresh install commonly fails once with
# "Missing configuration" while it is still bootstrapping itself - a known,
# documented quirk. A harmless warm-up call plus retries works around it.
RUN /usr/games/steamcmd +quit || true

# Install the dedicated server, then delete steamcmd's download/staging cache
# and logs IN THE SAME LAYER. Cleaning them in a later RUN would not shrink
# the image at all, since the earlier layer would still carry them.
RUN set -e; \
    for i in 1 2 3; do \
      if /usr/games/steamcmd +force_install_dir /home/steam/pzserver \
          +login anonymous \
          +app_update 380870 \
          +quit; then \
        break; \
      fi; \
      if [ "$i" = 3 ]; then echo "steamcmd failed after 3 attempts"; exit 1; fi; \
      echo "steamcmd attempt $i failed, retrying in 5s..."; \
      sleep 5; \
    done; \
    rm -rf /home/steam/pzserver/steamapps/downloading \
           /home/steam/pzserver/steamapps/temp \
           /home/steam/Steam/logs \
           /home/steam/.local/share/Steam/logs; \
    mkdir -p /home/steam/Zomboid/Server; \
    chmod -R g=u /home/steam

COPY --chown=1001:0 servertest.ini.template /home/steam/templates/servertest.ini.template
COPY --chown=1001:0 entrypoint.sh /home/steam/entrypoint.sh
RUN chmod -R g=u /home/steam/templates && \
    chmod 775 /home/steam/entrypoint.sh

EXPOSE 16261/udp
EXPOSE 16262/udp
EXPOSE 27015/tcp

ENTRYPOINT ["/home/steam/entrypoint.sh"]
