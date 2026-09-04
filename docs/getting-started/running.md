---
layout: default
title: Running
description: Running IBGA with Docker Compose
parent: Getting Started
nav_order: 2
---

# Running IBGA

## Starting the container

```bash
docker compose up -d
```

The `-d` flag runs the container in the background. With `restart: unless-stopped`, the container stays up until you stop it or Docker shuts down.

Two ports are exposed by default:

| Port | Function |
|------|----------|
| `6080` | Browser-based noVNC view of the running IB Gateway |
| `8888` | IB API socket (socat forwards to IBG's internal port, accepts any IP) |

## Daily restarts

IB Gateway restarts daily. IBGA configures the "Auto restart" time from `IB_LOGOFF` and reapplies it after login. A watchdog also checks every few seconds and restarts IBG if it exited.

## Crash handling

Because the restart routine already monitors the IBG process, a crash is handled the same way as a daily restart.

## Health check

The image ships a health check that connects to the API port. Check status with:

```bash
docker ps          # look for the "healthy" status
```
