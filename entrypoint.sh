#!/bin/bash
set -euo pipefail

# Zomboid writes its config and world saves under $HOME, so HOME points at the
# volume to make that data persist. OpenShift also runs this container as an
# arbitrary UID with no /etc/passwd entry, so HOME would otherwise be unset.
export HOME=/data/home

: "${SERVER_NAME:?SERVER_NAME must be set}"
: "${RCON_PASSWORD:?RCON_PASSWORD must be set}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD must be set}"

mkdir -p "${HOME}/Zomboid/Server"

# Render the real .ini from the template baked into the image, substituting the
# RCON password that arrived as an env var from a Secret.
export SERVER_NAME RCON_PASSWORD
envsubst < /home/steam/templates/servertest.ini.template \
    > "${HOME}/Zomboid/Server/${SERVER_NAME}.ini"

# Zomboid reads its JVM args from ProjectZomboid64.json, and the JVM has no
# awareness of the container's memory limit - left at its default -Xmx8g it
# grows past the limit and gets OOMKilled. Pin the heap below the limit,
# leaving headroom for non-heap memory (metaspace, stacks, native libs).
# -Xms is normalised too, since an initial heap larger than the max stops the
# JVM from starting at all.
: "${JVM_HEAP:=5g}"
sed -i -e "s/\"-Xmx[0-9]*[gGmM]\"/\"-Xmx${JVM_HEAP}\"/" \
       -e "s/\"-Xms[0-9]*[gGmM]\"/\"-Xms2048m\"/" \
       /data/pzserver/ProjectZomboid64.json

# -adminpassword is required for a non-interactive first run. Without it the
# server prompts for an admin password on stdin, and with no TTY attached that
# read throws NoSuchElementException and the process dies immediately.
exec /data/pzserver/start-server.sh \
    -servername "${SERVER_NAME}" \
    -adminpassword "${ADMIN_PASSWORD}"
