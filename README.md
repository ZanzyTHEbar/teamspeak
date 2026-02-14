# TeamSpeak 3 Server — Docker + Caddy L4 Reverse Proxy

Run a [TeamSpeak 3](https://www.teamspeak.com/) voice server inside Docker,
fronted by a [Caddy](https://caddyserver.com/) reverse proxy that handles raw
TCP **and** UDP via the
[caddy-l4](https://github.com/mholt/caddy-l4) module.

A simpler compose file without Caddy is included for setups that don't need a
proxy layer.

---

## Architecture

```
Internet
  │
  ├── UDP 9987  ──► Caddy (layer4) ──► TeamSpeak  (voice)
  ├── TCP 30033 ──► Caddy (layer4) ──► TeamSpeak  (file transfer)
  └── TCP 10011 ──► Caddy (layer4) ──► TeamSpeak  (server query)
```

All traffic enters through Caddy; the TeamSpeak container has **no** ports
published to the host.

### Why Caddy L4?

| Benefit | Detail |
|---|---|
| Single entry point | Every connection passes through one proxy for logging and control. |
| Future TLS termination | Caddy can terminate TLS for the TCP query port if needed. |
| Composability | Add HTTP services (web panel, monitoring) to the same Caddy instance later. |

> **Trade-off:** Proxying UDP adds a small amount of overhead. For most
> TeamSpeak servers (< 500 concurrent users) this is negligible. If you need
> bare-metal latency, use `docker-compose.simple.yml` instead (see
> [Simple mode](#simple-mode-no-caddy) below).

---

## Port Reference

| Port | Protocol | Purpose | Required? |
|-------|----------|-----------------|-----------|
| 9987 | UDP | Voice | Yes |
| 30033 | TCP | File transfer | Yes |
| 10011 | TCP | Server query | Optional |

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Ubuntu 22.04 / 24.04+ (or any Linux with a recent kernel) | 64-bit, `amd64` or `arm64` |
| Docker Engine 24+ | With the Compose V2 plugin (`docker compose`) |
| Root / `sudo` access | Needed for Docker install and port binding |
| Open firewall ports | `9987/udp`, `30033/tcp`, optionally `10011/tcp` |

---

## Step-by-step Setup on Ubuntu

### 1 — Update the system

```bash
sudo apt update && sudo apt upgrade -y
```

### 2 — Remove old Docker packages (if any)

```bash
sudo apt remove -y docker.io docker-compose docker-compose-v2 \
  docker-doc podman-docker containerd runc 2>/dev/null || true
```

### 3 — Install Docker (official APT repo)

```bash
# Dependencies
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings

# GPG key
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Repository
echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update

# Install
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# Verify
sudo docker run --rm hello-world
```

### 4 — (Recommended) Run Docker as a non-root user

```bash
sudo groupadd docker 2>/dev/null || true
sudo usermod -aG docker "$USER"
# Log out and back in, then verify:
docker run --rm hello-world
```

### 5 — Clone this repository

```bash
git clone https://github.com/<your-org>/teamspeak-caddy-docker.git
cd teamspeak-caddy-docker
```

Or just copy the files to your server and `cd` into the directory.

### 6 — Create your `.env` file

```bash
cp .env.example .env
# Review & edit — at minimum, accept the license:
#   TS3SERVER_LICENSE=accept
```

### 7 — Build and start

```bash
# Build the custom Caddy image (first time only, or after Caddyfile changes)
docker compose build

# Start everything
docker compose up -d
```

### 8 — Grab the admin privilege key

On first launch, TeamSpeak generates a one-time **ServerAdmin privilege key**.
You need it to claim admin in your TeamSpeak client.

```bash
docker compose logs teamspeak 2>&1 | grep -i "token"
```

Copy the token. In your TeamSpeak client, connect to your server
(`your-ip:9987`), and when prompted paste the privilege key.

### 9 — Open firewall ports

```bash
sudo ufw allow 9987/udp   comment 'TeamSpeak voice'
sudo ufw allow 30033/tcp  comment 'TeamSpeak file transfer'
sudo ufw allow 10011/tcp  comment 'TeamSpeak server query'  # optional
```

> **Note:** Docker may bypass `ufw` rules for published ports. If you need
> strict firewall control, see the
> [Docker & iptables docs](https://docs.docker.com/network/packet-filtering-firewalls/).

---

## Simple Mode (no Caddy)

If you don't need the Caddy proxy layer, use the standalone compose file:

```bash
docker compose -f docker-compose.simple.yml up -d
```

This publishes TeamSpeak's ports directly to the host with no proxy overhead.

---

## Using MariaDB (optional)

For larger deployments, swap the default SQLite backend for MariaDB:

1. Uncomment the `db` service and `db-data` volume in `docker-compose.yml`.
2. Add the `TS3SERVER_DB_*` environment variables to the `teamspeak` service
   (see the comments in the compose file).
3. Set the corresponding `MYSQL_*` values in `.env`.
4. Add a `depends_on` for `db` on the `teamspeak` service.
5. `docker compose up -d`

---

## Makefile Shortcuts

```
make help          Show all targets
make build         Build the custom Caddy image
make up            Start Caddy + TeamSpeak
make down          Stop all containers
make restart       Restart all containers
make logs          Tail all logs
make token         Print the admin privilege key
make status        Show running containers
make simple-up     Start TeamSpeak without Caddy
make simple-down   Stop TeamSpeak (simple mode)
make clean         Remove volumes (DESTROYS DATA)
```

---

## Customization

### Disabling the server query port

If you don't need remote server query access, remove or comment out the
`:10011` block in `caddy/Caddyfile` and the corresponding port mapping in
`docker-compose.yml`.

### Adding HTTP services

Because Caddy is already running, you can add standard HTTP reverse proxy
blocks to the Caddyfile alongside the `layer4` config. For example, adding a
web panel:

```caddyfile
panel.example.com {
    reverse_proxy ts-panel:8080
}
```

### Connecting via domain name

Point a DNS A record at your server's public IP. TeamSpeak clients can then
connect using `ts.example.com` (port 9987 is the default and can be omitted).

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Container exits immediately | Check `docker compose logs teamspeak` — usually a missing `TS3SERVER_LICENSE=accept`. |
| Can't hear voice / can't connect | Ensure `9987/udp` is open in your firewall **and** on your cloud provider's security group. |
| Caddy fails to start | Run `docker compose logs caddy` — a build error likely means the `xcaddy` build failed. Rebuild with `docker compose build --no-cache`. |
| Port conflict on host | Another process already binds one of the ports. Check with `ss -tulnp \| grep 9987`. |
| High voice latency | The L4 UDP proxy adds minimal overhead, but if latency is critical, switch to `docker-compose.simple.yml`. |

---

## File Structure

```
.
├── caddy/
│   ├── Caddyfile           # Caddy Layer 4 proxy configuration
│   └── Dockerfile          # Builds Caddy with the L4 module
├── docker-compose.yml      # Caddy + TeamSpeak (default)
├── docker-compose.simple.yml  # TeamSpeak only, no proxy
├── .env.example            # Template for environment variables
├── Makefile                # Common shortcuts
├── LICENSE
└── README.md
```

---

## References

- [TeamSpeak Docker Hub (official image)](https://hub.docker.com/_/teamspeak)
- [Caddy L4 module — mholt/caddy-l4](https://github.com/mholt/caddy-l4)
- [Caddy L4 server & proxy docs](https://github.com/mholt/caddy-l4/tree/master/docs)
- [Docker Engine install — Ubuntu](https://docs.docker.com/engine/install/ubuntu/)

## License

[MIT](LICENSE)
