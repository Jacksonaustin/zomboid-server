#!/bin/bash
set -euo pipefail

# OpenShift runs this container as an arbitrary UID with no /etc/passwd entry,
# so $HOME can arrive unset or as "/". Pin it so the game writes its config and
# save data where we expect them - and where the PVC gets mounted.
export HOME=/home/steam

: "${SERVER_NAME:?SERVER_NAME must be set}"
: "${RCON_PASSWORD:?RCON_PASSWORD must be set}"

mkdir -p "${HOME}/Zomboid/Server"

# Render the real .ini from the template, substituting the RCON password that
# arrived as an env var from a Secret - it is never baked into the image or
# committed to git in plaintext.
export SERVER_NAME RCON_PASSWORD
envsubst < "${HOME}/templates/servertest.ini.template" \
    > "${HOME}/Zomboid/Server/${SERVER_NAME}.ini"

exec "${HOME}/pzserver/start-server.sh" -servername "${SERVER_NAME}"
