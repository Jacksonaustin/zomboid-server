# zomboid-server

Hosting a Project Zomboid dedicated server on OpenShift, because apparently that's a normal thing to do now.

My uncle (an actual Red Hat principal architect, no big deal) spun up a cluster for me on top of OpenStack and said "have fun." So this repo is me figuring out Kubernetes/OpenShift for real by building something I actually care about instead of another todo-app tutorial. If you're reading this because you also got handed a cluster and no idea what to do with it — welcome, same.

## what this actually is

A single Project Zomboid server running as a pod on OpenShift, with:

- a container image built **on the cluster itself** (not locally — more on that below, it's a whole saga)
- persistent storage so the world doesn't get wiped every time the pod restarts
- the game ports exposed to the internet, and the admin/RCON port very much **not**
- everything as code in this repo instead of me clicking around in the console and forgetting what I did

## the stack

- **Namespace:** `zomboid` — everything lives in here
- **Image:** built via an OpenShift `BuildConfig` straight from this repo's `Dockerfile`. I originally tried building it locally on my Mac and steamcmd (32-bit x86 binary) just would not run under the ARM-emulating-x86 chain Docker Desktop uses on Apple Silicon — zero error output, just instant death. Building it natively on the cluster's real x86_64 nodes fixed it immediately. Fun couple hours.
- **Storage:** a `PersistentVolumeClaim` (`zomboid-saves`, 20Gi) so the save data survives pod restarts/rescheduling
- **Config:** server settings live in `servertest.ini.template`, rendered into the real `.ini` file at container startup via `envsubst`, so secrets never get baked into the image or committed to git
- **Secrets:** the RCON password is a Kubernetes `Secret`, created manually with `oc create secret` — **never** committed as a file. If you're setting this up yourself, you have to create it yourself too:

  ```
  oc create secret generic zomboid-rcon-secret \
    --from-literal=RCON_PASSWORD='something-actually-strong' \
    -n zomboid
  ```

- **Networking:** two separate Services on purpose —
  - `zomboid-game` — `type: LoadBalancer`, UDP 16261/16262, this is the one that's actually internet-facing
  - `zomboid-rcon` — `type: ClusterIP`, TCP 27015, internal only, reachable via `oc port-forward` when I need to admin the server, never forwarded through anyone's router

That split exists because I got asked once "isn't Zomboid UDP-exclusive?" and the answer is: gameplay traffic, yes. RCON is TCP on purpose, and it stays internal on purpose too.

## repo layout

```
Dockerfile                     # builds the image (SteamCMD + PZ dedicated server)
entrypoint.sh                  # renders config + launches the server at runtime
servertest.ini.template        # server config, with ${SERVER_NAME}/${RCON_PASSWORD} placeholders
manifests/
  namespace.yaml
  imagestream.yaml
  buildconfig.yaml
  pvc.yaml
  service-loadbalancer.yaml    # public, UDP only
  service-rcon.yaml            # internal only, never exposed
```

## setting it up from scratch

```
oc apply -f manifests/namespace.yaml
oc apply -f manifests/imagestream.yaml
oc apply -f manifests/buildconfig.yaml
oc start-build zomboid-server --follow

oc apply -f manifests/pvc.yaml
oc create secret generic zomboid-rcon-secret \
  --from-literal=RCON_PASSWORD='something-actually-strong' \
  -n zomboid

oc apply -f manifests/service-loadbalancer.yaml
oc apply -f manifests/service-rcon.yaml
```

(StatefulSet manifest is coming — that's the piece that actually ties the image + PVC + secret together into a running pod. Check back once it exists here.)

Once `zomboid-game` has a real `EXTERNAL-IP` (`oc get svc -n zomboid`), that's the address that needs UDP 16261 (and optionally 16262) forwarded to it at the router level. Nothing else needs to be forwarded — especially not RCON.

## why this exists

Mostly to actually learn OpenShift instead of just reading about it, and partly because a Project Zomboid server with friends is funnier to justify as a "learning project" than yet another static site. Also yes, an actual principal architect at Red Hat is indirectly responsible for this existing, which feels like it should count for something on a resume.
