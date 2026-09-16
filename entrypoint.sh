#!/bin/bash
set -euo pipefail

: "${SERVER_NAME:?SERVER_NAME must be set}"
: "${RCON_PASSWORD:?RCON_PASSWORD must be set}"

mkdir -p /home/steam/Zomboid/Server

export SERVER_NAME RCON_PASSWORD
envsubst < /home/steam/templates/servertest.ini.template \
    > "/home/steam/Zomboid/Server/${SERVER_NAME}.ini"

exec /home/steam/pzserver/start-server.sh -servername "${SERVER_NAME}"
