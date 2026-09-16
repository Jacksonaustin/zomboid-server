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

# -adminpassword is required for a non-interactive first run. Without it the
# server prompts for an admin password on stdin, and with no TTY attached that
# read throws NoSuchElementException and the process dies immediately.
exec /data/pzserver/start-server.sh \
    -servername "${SERVER_NAME}" \
    -adminpassword "${ADMIN_PASSWORD}"
