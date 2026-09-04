---
layout: default
title: The Docker Image
description: Obtaining and building the IBGA Docker image
parent: Getting Started
nav_order: 0
---

# The IBGA Docker Image

## Obtaining the image

```bash
docker pull ghcr.io/huieric/ibkr:stable
```

Docker Compose pulls it automatically when you use the example configuration.

## Image channels

| Channel | Tag | Use case |
|---------|-----|----------|
| `stable` | `ghcr.io/huieric/ibkr:stable` | Production trading |
| `latest` | `ghcr.io/huieric/ibkr:latest` | Testing / paper trading |

New releases are built and published automatically by GitHub Actions when IBKR ships a new version.

## Building locally

```bash
./build.sh stable <version>    # or: latest <version>
```

## Design

IBGA is a "disposable container": IB Gateway binaries and settings live in bind-mounted host directories, not inside the container. The image itself contains only the automation scripts, an X11/VNC stack, and the automation dependencies (JAuto + xdotool). IB Gateway is downloaded and installed on first start.
