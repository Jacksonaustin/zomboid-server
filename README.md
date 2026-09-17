# zomboid-server

A Project Zomboid dedicated server running on OpenShift, defined entirely as code.

Started as "I'm tired of one of us having to be online to host," turned into a
much better excuse to actually learn Kubernetes than another todo app. Game
servers are an awkward workload for Kubernetes — stateful, can't scale
horizontally, UDP, big install footprint, needs real persistent storage — which
means you end up dealing with the genuinely hard parts instead of the happy path.

## What it does

One Zomboid server running as a StatefulSet, with:

- the container image built on-cluster from this repo via an OpenShift `BuildConfig`
- game files and world saves on a Cinder-backed `PersistentVolumeClaim`
- gameplay ports exposed to the internet, RCON deliberately not
- config rendered from a template at startup, secrets injected from a `Secret`
- everything in git, applied with `oc apply`, rather than clicked together in the console

## Architecture decisions

**Game files live on the volume, not in the image.** The obvious approach is to
`steamcmd` the server into the image at build time. That produces a ~7.5GB image,
and the build has to write those bytes twice — once into the container filesystem,
again as a committed layer blob — which repeatedly got the build pod evicted for
ephemeral-storage pressure on a node with a 40GB root disk. Even a successful
build wouldn't have helped: a node has to store an image locally to run it, so the
pod would have failed at runtime for the same reason.

Instead, the image contains only SteamCMD and the scripts (a few hundred MB), and
an **init container** downloads the server files onto the PVC on first start. That
moves the bulk from scarce node-local ephemeral storage onto volume storage, where
the capacity actually is. Bonus: builds are fast, updating the game doesn't require
rebuilding an image, and restarts are quick because SteamCMD skips files already
present.

**Two Services, split on purpose.** `zomboid-game` is a `LoadBalancer` exposing
UDP 16261/16262 — the actual gameplay traffic. `zomboid-rcon` is a `ClusterIP`
exposing TCP 27015, which means RCON is unreachable from outside the cluster no
matter what anyone forwards at a router. Admin access goes through
`oc port-forward` instead. RCON is safe by construction rather than by remembering
not to expose it.

**StatefulSet, not Deployment.** One replica with a stable identity, and rollouts
that never run two pods at once — which matters when both would be writing the same
world save.

**Config as code, secrets not.** `servertest.ini.template` lives in the image with
`${...}` placeholders, and the entrypoint renders it with `envsubst` at startup.
The RCON and admin passwords arrive as env vars from a Kubernetes `Secret` that is
created out-of-band and never committed:

```
oc create secret generic zomboid-rcon-secret \
  --from-literal=RCON_PASSWORD='...' \
  --from-literal=ADMIN_PASSWORD='...' \
  -n zomboid
```

**No CPU limit, only a request.** A CPU limit doesn't cap usage, it makes the
kernel throttle the container every scheduling period. With a 2-core limit the
server sat pinned at exactly 1999m, stuttering — and even `oc exec` would hang,
because a new process couldn't get scheduled. Dropping the limit while keeping the
request means the scheduler still reserves capacity and the server can burst into
idle node CPU. Usage fell to ~50m at idle once it wasn't fighting the throttle.

## Repo layout

```
Dockerfile                     # steamcmd + scripts only, no game files
install-server.sh              # init container: downloads the server onto the PVC
entrypoint.sh                  # renders config, pins JVM heap, launches the server
servertest.ini.template        # server config with ${SERVER_NAME}/${RCON_PASSWORD}
manifests/
  namespace.yaml
  imagestream.yaml
  buildconfig.yaml             # builds this repo on-cluster
  pvc.yaml                     # 30Gi: game files + saves
  statefulset.yaml             # init container + server, resources, env from Secret
  service-loadbalancer.yaml    # public, UDP only
  service-rcon.yaml            # cluster-internal only
```

## Deploying from scratch

```
oc apply -f manifests/namespace.yaml
oc apply -f manifests/imagestream.yaml
oc apply -f manifests/buildconfig.yaml
oc start-build zomboid-server --follow

oc create secret generic zomboid-rcon-secret \
  --from-literal=RCON_PASSWORD='...' \
  --from-literal=ADMIN_PASSWORD='...' \
  -n zomboid

oc apply -f manifests/pvc.yaml
oc apply -f manifests/statefulset.yaml
oc apply -f manifests/service-loadbalancer.yaml
oc apply -f manifests/service-rcon.yaml
```

First pod start downloads ~7.2GB, so it sits in `Init:0/1` for a while:

```
oc logs -f zomboid-server-0 -c install-server -n zomboid
```

Once `oc get svc zomboid-game -n zomboid` shows an address, that's what needs
**UDP** 16261 (and optionally 16262) routed to it. Not 27015.

## Things that broke, and why

Most of the real learning happened here, so it's worth writing down.

**SteamCMD is a 32-bit x86 binary.** Building locally on an Apple Silicon Mac
meant emulating x86_64 via QEMU on ARM, and then running a 32-bit binary inside
that — which failed instantly with no output at all. Building on-cluster on native
x86_64 worked first try. Some things aren't worth emulating.

**Debian's `steamcmd` package doesn't create `~/.steam` before symlinking into
it.** `ln -s` into a nonexistent directory fails, so the install dies. One
`mkdir -p` fixes it.

**SteamCMD's first run on a fresh install fails with "Missing configuration."**
Documented quirk, succeeds on retry. Normally you'd hit it once ever on a
long-lived box; in a container every start is a first run, so the install is
wrapped in a retry loop.

**Zomboid prompts for an admin password on stdin on first run.** No TTY in a
container, so `Scanner.nextLine()` throws `NoSuchElementException` and the server
dies before it starts. Fixed by passing `-adminpassword`.

**The JVM has no idea it's in a container.** Zomboid ships `-Xmx8g` in
`ProjectZomboid64.json`. Inside a 6Gi memory limit, that's not a tuning problem,
it's arithmetic: the heap grows past the limit and the kernel kills the process,
every time, forever. The fix is pinning the heap *below* the container limit with
headroom for non-heap memory, not raising the limit until it fits.

Worth knowing the two failure modes look nothing alike and have opposite fixes:

| Symptom | Meaning | Fix |
|---|---|---|
| `Exit Code: 137`, `OOMKilled` | container limit too low | raise the memory limit |
| `java.lang.OutOfMemoryError` in logs | heap too small | raise `-Xmx` |

**OpenShift ignores `USER` in your Dockerfile.** The default `restricted-v2` SCC
runs containers as an arbitrary high UID with no `/etc/passwd` entry, always in
group 0. So a user created with `USER steam` doesn't exist at runtime, `$HOME` is
unset or `/`, and anything owned by that user isn't writable. Handled by giving
the server user primary group 0, making the tree group-writable
(`chmod -R g=u`), and pinning `HOME` explicitly — and doing the `chmod` in the
same layer as the install, since chmod-ing 7GB in a later layer would copy it all
up and double the image.

## Not done yet

- **Liveness/readiness probes.** Right now Kubernetes only knows the process
  exists, not that the server is accepting players — so a hung JVM wouldn't get
  restarted, and the Service routes traffic during the minutes of world loading.
- **Backups.** The PVC's reclaim policy is `Delete`, so deleting it destroys the
  world permanently, and nothing is copied off-volume. A CronJob tarring
  `Saves/` somewhere else is the obvious next step.
- **Mod support.** `WorkshopItems`/`Mods` in the ini template, untested.
