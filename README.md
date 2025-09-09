# Another Nextcloud AIO — A Single-Host, Home-ISP-Friendly Nextcloud Stack with Rootless Podman

A batteries-included, **one-machine** setup to run Nextcloud in a single host with a clean, minimal, and repeatable setup.

**Highlights**

- **Single host / all-in-one**: reverse proxy, TLS, DB, cache, TURN, Talk signaling—all in one compose.
- **Home ISP compatible**: works behind typical consumer routers with DDNS (No-IP).
- **Rootless Podman**: no root-owned data, no chown surprises, no container UID/GID mismatches.
- **User-owned data**: everything on the host filesystem owned by *your* user account.
- **No domain registration**: a free **No-IP** hostname is enough.

Users only need to fill in `.env`, then:

```bash
podman-compose up -d
```

…and your server is live.

---

## Table of Contents

1. [What You’ll Get](#what-youll-get)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Quick Start (6 Steps)](#quick-start-6-steps)
5. [Ports to Forward (Home Router)](#ports-to-forward-home-router)
6. [Environment Variables](#environment-variables)
7. [Service Overview](#service-overview)
8. [Supported Apps with Extra Configuration](#supported-apps-with-extra-configuration)
   - [Talk (HPB + TURN)](#talk-hpb--turn)
9. [Troubleshooting](#troubleshooting)
10. [Security Notes](#security-notes)
11. [FAQ](#faq)

---

## What You’ll Get

- A working Nextcloud reachable at `https://<your-ddns-hostname>` with admin credentials from `.env`.
- HTTPS automatically issued using Let’s Encrypt (works with No-IP hostnames).
- Nextcloud Talk usable across NAT with HPB + TURN for stable calls.
- A sane default layout and `.env` for easy customization.
- All services run **rootless** under your host user, with data directories mounted from the host (owned by you).

---

## Architecture

`podman-compose` file contains several container entries. Each of them are used as follow:

- **app**: Apache container hosting Nextcloud Server.
- **app-cron**: An auxiliary container runing cron job required by Nextcloud server.
- **db**: Postgre DB for Nextcloud Server backend.
- **redis**: Key-value store for file locking and performance improvement in Nextcloud Server backend.
- **caddy**: Reverse proxy and automatic TLS on port`443`.
- **noip**: Dynamic update client for your DDNS domain.
- **imaginary**: Fast image preview generation.
- **spreed-backend**, **nats**, **janus**, **coturn**: Various Nextcloud Talk backend for enabling chats, calls, and video conferencing everywhere.

---

## Prerequisites

- Linux host with Podman and `podman-compose` **1.5.0**
- A typical home router where you can configure **port forwarding**
- No-IP account (free) for **DDNS** (e.g., `mynas.ddns.net`)
- Ability to run one-time `sudo` on the host to enable non-root binding of port 443 (Alternatively: bind port 1443 instead and forward 443 from WAN to 1443 in LAN)

---

## Quick Start (7 Steps)

1. **Register DDNS on No-IP** 
   - Register a NO-IP account.
   - Create a hostname (e.g., `mynas.ddns.net`) pointing to your WAN IPv4 and IPv6.

2. **Set Port Forwarding on the ISP Router**  
   Forward the ports listed in the table below to your host’s **LAN IP**.
   Your Host's LAN IP needs to be statically allocated.

3. **Allow non-root processes to bind to 443 on the host**  
   Run once (requires sudo) so rootless containers can use low ports:
   ```bash
   echo 'net.ipv4.ip_unprivileged_port_start=443' | sudo tee /etc/sysctl.d/99-unprivileged-ports.conf
   echo 'net.ipv6.ip_unprivileged_port_start=443' | sudo tee -a /etc/sysctl.d/99-unprivileged-ports.conf
   sudo sysctl --system
   ```
   > If you can’t change sysctl, see the FAQ for using an alternate external port.

4. **Disable randomized IPv6 address**
   Run once (requires sudo) so your IPv6 address is fixed:
   ```bash
   echo 'net.ipv6.conf.all.use_tempaddr=0' | sudo tee /etc/sysctl.d/99-ipv6-privacy.conf
   echo 'net.ipv6.conf.default.use_tempaddr=0' | sudo tee -a /etc/sysctl.d/99-ipv6-privacy.conf
   ```

5. **Install podman-compose 1.5.0**
   ```bash
   snap install podman-compose
   podman-compose version
   # should say 1.5.0
   ```

6. **Fill `.env` and launch**
   ```bash
   cp .env.example .env
   # edit .env (see variables below)
   podman-compose up -d
   ```

7. **Open your browser and log in**
   - Visit `https://<your-ddns-hostname>`
   - Log in with the admin user/password you set in `.env`

---

## Ports to Forward (Home Router)


| External Port | Protocol | Forward To (Host:Port) | Purpose | Required? | Notes |
|---:|:--:|:--|:--|:--:|:--|
| **443** | TCP | host **443** → reverse proxy | HTTPS for Nextcloud, WebSocket for Talk signaling | ✅ | Required for TLS-ALPN challenge (no need for 80). |
| **3478** | UDP/TCP | host 3478 → **coturn** | STUN/TURN for WebRTC | ✅ if Talk app is installed | Required for Talk calls through NAT. Also allow **TCP 3478** as fallback. |
| 5349 | TCP | host 5349 → coturn | TURN over TLS (recommended) | ✅ if Talk app is installed | Optional but helps with locked-down networks. |
| 49160–49200 | UDP | same range → coturn | TURN relay media ports | ✅ if Talk app is installed | Set the same range in .env. You may also open TCP for this range. |
| 40000–40100 | UDP | same range → Nextcloud Talk RTP | Nextcloud Talk media ports | ✅ if Talk app is installed | Set the same range in .env. |


**Minimum for web UI**: 443/TCP  
**Minimum for Talk**: 443/TCP + 3478/UDP (plus the TURN relay/RTP port range)

---

## Environment Variables

The stack is driven by `.env`. Variable descriptions as follow:

- FQDN: Your domain name (e.g., `mynas.ddns.net`).
- HOST_UID/HOST_GID: The host user's uid/gid (use `id -a` command).
- LAN_IP/LAN_IPV6: Your IP/IPv6 allocated by the router.
   - For IPv6: If your ISP router does not have NAT loopback feature, you need to configure IPv6 otherwise your devices in the same LAN with your Nextcloud host are inaccessible to your cloud.
- NEXTCLOUD_ADMIN_USER/PASSWORD: Your admin account and strong password for managing server.
- POSTGRES_DB/USER/PASSWORD: The database name of your Nextcloud Server and the user/password for the server to access the database (default: nextcloud/ncuser).
- CADDY_EMAIL: Required for caddy container for letencrypt TLS renewal notice.
- NOIP_USERNAME/PASSWORD: NO-IP account/password for noip container to update WAN IP of your Nextcloud Server.
- TURN/SIGNALING/INTERNAL/JANUS_ADMIN_SECRET: 32-byte hex strings for each secret. suggest generating these with `openssl rand -hex 32` command.
- SESSION_HASH_KEY: a 32-byte hex string (`openssl rand -hex 32`)
- SESSION_BLOCK_KEY: a 16-byte hex string (`openssl rand -hex 16`)

Make sure to change `.env` file's permission to `600` so that other users cannot read this file.

---

## Extra Configuration for Specific Apps

These are the apps that typically need more than one click to work well in a home-ISP scenario. Each section gives you the exact fields to fill in the nextcloud setting page.

### Talk (HPB + TURN)

**In Nextcloud → Admin Settings → Talk → High-Performance Backend:**

- **High-Performance Backend**:  
   - **URL**: `wss://<DOMAIN>/standalone-signaling`
   - **Enable SSL**: ✅ (handled by the reverse proxy)
   - **Shared secret**: `SIGNAL_SECRET` (must match the signaling container)
   - After editing the fields above, you should see the check become `OK: Running version: 2.0.4~docker`
- **TURN server**:  
  - `turn only, <DOMAIN>:3478`
  - TURN secret, paste the secret you set in .env file

---

## Contributing & Backend Integrations

I’m actively working on more backend integrations to keep this stack simple yet powerful for home users. Any help is appreciated—from testing and docs to compose snippets and hardening tips.

### Ways to contribute

- Open an issue for bugs, questions, or ideas.

- Submit a PR for compose/services, configs, docs, or automation.

- Share real-world configs (ISP peculiarities, router quirks, IPv6 tips, etc.).

- Help test new backends on diverse home networks.

### Contribution guidelines (quick)

- Favor rootless patterns and user-owned data.

- Prefer path-based routing behind the reverse proxy (minimize extra public ports).

- Keep env-driven config in .env; document any new variables.

- Any variable changes in `config.php` should be an `./occ config:system set` command in `container-hooks/before-starting`
