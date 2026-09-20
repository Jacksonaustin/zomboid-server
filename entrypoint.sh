#!/bin/bash
set -euo pipefail

# Zomboid locates its data directory via Java's user.home property, NOT the HOME
# environment variable - and with OpenShift's arbitrary UID having no passwd
# entry, that resolves to /home/steam no matter what we export. So rather than
# fight it, the StatefulSet mounts the PVC at /home/steam/Zomboid and we write
# config there. ZOMBOID_DIR is that path.
export HOME=/home/steam
ZOMBOID_DIR=/home/steam/Zomboid

: "${SERVER_NAME:?SERVER_NAME must be set}"
: "${RCON_PASSWORD:?RCON_PASSWORD must be set}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD must be set}"
: "${SERVER_PASSWORD:?SERVER_PASSWORD must be set}"

mkdir -p "${ZOMBOID_DIR}/Server"

# Render the real .ini from the template baked into the image, substituting the
# RCON password that arrived as an env var from a Secret.
export SERVER_NAME RCON_PASSWORD SERVER_PASSWORD
envsubst < /home/steam/templates/servertest.ini.template \
    > "${ZOMBOID_DIR}/Server/${SERVER_NAME}.ini"

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
