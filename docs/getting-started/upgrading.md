---
layout: default
title: Upgrading
description: Upgrading IBGA and IB Gateway
parent: Getting Started
nav_order: 3
---

# Upgrading

## Upgrading the image

```bash
docker compose pull
docker compose up -d
```

Docker recreates the container with the new image. IB Gateway and settings are persisted in the mounted volumes, so nothing is lost.

## Upgrading IB Gateway

To force a fresh IB Gateway install, remove the program directory while the container is stopped:

```bash
docker compose down
rm -rf ./run/program
docker compose up -d
```

On the next start, IBGA reinstalls IB Gateway into `./run/program`. Settings in `./run/settings` are preserved.
