#!/bin/bash
set -euo pipefail

# Keep ALL steamcmd state on the volume, not the container's local disk - that
# includes its own bootstrap files and the depot download cache, which is what
# kept filling the node's ephemeral storage and getting the build evicted.
export HOME=/data/steamhome
mkdir -p "${HOME}" /data/pzserver

# steamcmd's first run in a fresh container commonly fails once with
# "Missing configuration" while bootstrapping itself - warm it up, then retry.
/usr/games/steamcmd +quit || true

for i in 1 2 3; do
  if /usr/games/steamcmd +force_install_dir /data/pzserver \
      +login anonymous \
      +app_update 380870 \
      +quit; then
    echo "server files ready in /data/pzserver"
    exit 0
  fi
  echo "steamcmd attempt $i failed, retrying in 10s..."
  sleep 10
done

echo "steamcmd failed after 3 attempts"
exit 1
