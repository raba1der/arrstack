# Docker Media Stack (Sonarr, Radarr, Bazarr, Prowlarr, qBittorrent)

This repository provides:

-   A `docker-compose.yml` for:
    -   qBittorrent
    -   Prowlarr
    -   Sonarr
    -   Radarr
    -   Bazarr
-   A `.env` configuration file
-   A `create-arr-users.sh` script that:
    -   Creates dedicated system users for each service
    -   Creates a shared `media` group
    -   Configures directory structure and permissions
    -   Prevents common Docker permission issues

------------------------------------------------------------------------

## Architecture Overview

All containers:

-   Run using LinuxServer.io images
-   Use explicit `PUID` and `PGID`
-   Share a common `/data` mount
-   Use `UMASK=002` to ensure group-writable files

### Shared Data Layout

Inside containers:

/data ├── downloads ├── media │ ├── movies │ └── tv

On host (example):

CONFIG_ROOT=/opt/arr/config DATA_ROOT=/srv/data

------------------------------------------------------------------------

## Service Ports

  Service       Port       Purpose
  ------------- ---------- -----------------
  qBittorrent   8080       Web UI
  qBittorrent   6881       BitTorrent TCP
  qBittorrent   6881/udp   DHT / PeX / UDP
  Prowlarr      9696       Web UI
  Sonarr        8989       Web UI
  Radarr        7878       Web UI
  Bazarr        6767       Web UI

Access via:

http://SERVER_IP:PORT

------------------------------------------------------------------------

## User & Permission Model

Each service runs as its own Linux system user:

  Service       Example UID
  ------------- -------------
  qbittorrent   2100
  prowlarr      2101
  sonarr        2102
  radarr        2103
  bazarr        2104

All services share a common group:

media (GID 2000)

### Why This Matters

-   Prevents root-owned download files
-   Allows Sonarr/Radarr to import from qBittorrent
-   Prevents permission conflicts
-   Uses `chmod 2775` to enforce group inheritance (setgid bit)

------------------------------------------------------------------------

## Setup Instructions

### 1. Create Users and Directories

Run as root:

``` bash
chmod +x create-arr-users.sh
sudo ./create-arr-users.sh
```

This will:

-   Create service users
-   Create `/opt/arr/config/*`
-   Create `/srv/data`
-   Apply correct ownership and permissions

------------------------------------------------------------------------

### 2. Configure .env

Example:

``` bash
TZ=Europe/Oslo
UMASK=002

CONFIG_ROOT=/opt/arr/config
DATA_ROOT=/srv/data

MEDIA_GID=2000

QBITTORRENT_UID=2100
PROWLARR_UID=2101
SONARR_UID=2102
RADARR_UID=2103
BAZARR_UID=2104
```

------------------------------------------------------------------------

### 3. Start the Stack

``` bash
docker compose up -d
```

------------------------------------------------------------------------

## qBittorrent Configuration (Important)

Inside qBittorrent:

-   Default Save Path: `/data/downloads`
-   Optional categories:
    -   Movies → `/data/downloads/movies`
    -   TV → `/data/downloads/tv`

In Sonarr/Radarr:

-   Add qBittorrent as Download Client
-   Use host: `qbittorrent`
-   Port: `8080`
-   Path: `/data/downloads`

------------------------------------------------------------------------

## Networking Notes

All containers run on the default Docker bridge network.

Internal container hostname resolution works automatically: - Sonarr →
`http://qbittorrent:8080` - Radarr → `http://qbittorrent:8080` - Apps →
`http://prowlarr:9696`

No hardcoding of IP addresses required.

------------------------------------------------------------------------

## Common Issues & Fixes

### Permission Denied Errors

Ensure:

-   UMASK=002
-   All services use the same PGID
-   `/data` has 2775 permissions

Fix manually if needed:

``` bash
sudo chown -R root:media /srv/data
sudo chmod -R 2775 /srv/data
```

------------------------------------------------------------------------

### Files Owned by root

This usually means:

-   PUID/PGID mismatch
-   Container was started before users were created

Fix:

``` bash
docker compose down
sudo chown -R sonarr:media /opt/arr/config/sonarr
docker compose up -d
```

------------------------------------------------------------------------

## Security Considerations

-   None of these services include authentication by default.
-   Consider:
    -   Reverse proxy (Nginx / Traefik)
    -   VPN for qBittorrent (e.g., gluetun)
    -   Firewall restricting external access

------------------------------------------------------------------------

## Recommended Enhancements

-   Add healthchecks
-   Add automatic container updates (Watchtower)
-   Add reverse proxy with HTTPS
-   Add Gluetun for torrent VPN routing

------------------------------------------------------------------------

## Summary

This setup:

-   Uses strict UID/GID separation
-   Eliminates permission headaches
-   Keeps clean host directory structure
-   Follows Docker best practices
-   Is production-safe for home server environments
