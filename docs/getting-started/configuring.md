---
layout: default
title: Configuring
description: Configuring IBGA with Docker Compose
parent: Getting Started
nav_order: 1
---

# Configuring IBGA

IBGA is configured entirely through a `docker-compose.yml` file. The example below covers the essentials.

```yaml
services:
  my-ibga:
    image: ghcr.io/huieric/ibkr:stable
    restart: unless-stopped
    environment:
      - IB_USERNAME=username
      - IB_PASSWORD=password
      - IB_REGION=America
      - IB_TIMEZONE=America/New_York
      - IB_LOGINTAB=IB API
      - IB_LOGINTYPE=Live Trading
      - IB_LOGOFF=11:55 PM
      - AUTH_METHOD=passkey
    volumes:
      - ./run/program:/home/ibg
      - ./run/settings:/home/ibg_settings
    ports:
      - "8888:8888"
      - "6080:6080"
```

For the full list of IBGA-specific environment variables, see [Configuration Arguments](../references/config-args.md). For `volumes` / `ports` / `restart` basics, see [Docker Basics](../references/docker-basics.md).
