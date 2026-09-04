---
layout: default
title: Docker Basics
description: Docker Compose basics for IBGA
parent: References
nav_order: 0
---

# Docker Compose Basics

This section covers the basics of a Docker Compose configuration for IBGA. For the full IBGA-specific environment variables, see [Configuration Arguments](config-args.md).

## The example, explained

```yaml
services:
  my-ibga:
    image: ghcr.io/huieric/ibkr:stable
    restart: unless-stopped
    environment:
      - IB_USERNAME=username
      # ...
    volumes:
      - ./run/program:/home/ibg
      - ./run/settings:/home/ibg_settings
    ports:
      - "8888:8888"
      - "6080:6080"
```

* `services.my-ibga` — the service name (also used as the container name). Use a distinct name per instance if running multiple accounts.
* `image` — the IBGA image, pulled automatically from the GitHub Container Registry.
* `restart: unless-stopped` — Docker restarts the container after a reboot or crash.
* `environment` — IBGA configuration; see [Configuration Arguments](config-args.md).
* `volumes` — bind-mounts mapping host dirs into the container. These two make the container disposable: IB Gateway lives in `/home/ibg`, settings in `/home/ibg_settings`.
* `ports` — `host:container` mapping. `8888` is the IB API socket, `6080` is the noVNC browser view.

## Volumes

```yaml
- ./run/program:/home/ibg
- ./run/settings:/home/ibg_settings
```

Maps host `./run/program` to container `/home/ibg` (IB Gateway install dir) and `./run/settings` to `/home/ibg_settings` (user settings). Delete the container and image freely — data survives in these directories, and copying them to another machine migrates the setup.

## Ports

```yaml
- "8888:8888"   # IB API
- "6080:6080"   # noVNC
```

`host_port:container_port`. Visit `http://<host>:6080` to watch IB Gateway live. Point your API client at `http://<host>:8888`.
