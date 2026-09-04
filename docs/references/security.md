---
layout: default
title: Security
description: IBGA security considerations
parent: References
nav_order: 2
---

# Security

## Hosting on the internet

IBGA is not hardened for direct exposure on a public server. If you must host it remotely, take these precautions.

### Restrict the API port

The IB API socket is unauthenticated raw TCP. Never expose it to the public internet. In the compose file, bind it to localhost:

```yaml
ports:
  - "127.0.0.1:8888:8888"
```

and connect over SSH tunnel or from a co-located process.

### Protect the host

* Use SSH key-based authentication (disable password login).
* Restrict inbound ports with a firewall (UFW) to your client IP, or use a VPN (e.g. WireGuard) for changing IPs.

### Protect your credentials

IBGA needs your IB username and password to log in. Prefer Docker secrets or a `.env` file over hard-coding them in `docker-compose.yml`, and avoid committing real credentials to version control.

## VNC / noVNC access

The noVNC view (`6080`) is for monitoring. It is not a substitute for the API-port restriction above — securing VNC alone still leaves the API socket open.
