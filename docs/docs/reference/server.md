---
myst:
  html_meta:
    "description": "Reference for the new.imsss.net server: services, paths, nginx, TLS, and logs"
    "property=og:description": "Reference for the new.imsss.net server: services, paths, nginx, TLS, and logs"
    "property=og:title": "Server reference"
    "keywords": "Plone, IMSSS 2025, server, systemd, nginx, certbot, logs"
---

# Server reference

This page describes the server that runs [new.imsss.net](https://new.imsss.net) as of October 2026.
For an explanation of how the parts fit together, see {doc}`../concepts/architecture`.

## Host

| Item | Value |
| --- | --- |
| Host name | `new.imsss.net`, proxied by Cloudflare since October 29, 2026; see "Cloudflare" below |
| Operating system | Ubuntu 24.04 LTS |
| Resources | Linode 1 GB plan since October 29, 2026: 1 vCPU, 1 GB RAM (961 MB usable), 2.5 GB swap (512 MB partition and 2 GB `/swapfile`), 25 GB disk. Before that, 2 vCPU and 4 GB RAM |
| SSH user for the site | `plone` |
| Docker | Not installed |
| Firewall | `ufw`, allowing only SSH (22) and HTTP/HTTPS (80, 443) from outside; enabled on October 28, 2026. One address is blocked; see "Connection tracking" below |
| SSH logins | Keys only, for every account; root may log in with a key but never with a password. Set on October 28, 2026 |
| SSH protection | fail2ban bans addresses that keep failing to log in over SSH; set up on October 28, 2026 |

## Paths

All paths below are relative to the checkout at `/home/plone/imsss.net-plone-6.1.3/imsss-2025`, unless they start with `/`.

| Path | Contents |
| --- | --- |
| `backend/.venv/` | Python 3.12 virtual environment with Plone 6.1.3 |
| `backend/instance/etc/zope.conf` | Zope configuration, including the database paths |
| `backend/instance/etc/zope.ini` | WSGI configuration; listens on `localhost:8080` with 4 threads |
| `backend/instance/var/filestorage/Data.fs` | The ZODB database |
| `backend/instance/var/blobs/` | Uploaded image and file contents |
| `backend/instance/var/filestorage-orig/`, `blobs-orig/` | Older copies of the database, kept from setup |
| `frontend/volto.config.js` | Volto add-on and theme configuration |
| `/home/plone/backups/` | Daily database and blob backups, readable only by `plone`; see "Backups" below |
| `/home/plone/bin/imsss-backup.sh` | Script that makes those backups |
| `/swapfile` | 2 GB swap file, listed in `/etc/fstab` |
| `/etc/ssh/sshd_config.d/00-imsss.conf` | Turns off password logins over SSH; see below |
| `/etc/fail2ban/jail.d/imsss.local` | fail2ban settings for the SSH jail; see below |
| `/etc/sysctl.d/60-imsss-conntrack.conf` | Enlarges the firewall's connection-tracking table, and shortens how long it remembers idle connections; see "Connection tracking" below |
| `/etc/modules-load.d/imsss-conntrack.conf` | Loads connection tracking early in boot, so that the settings above apply |
| `/etc/systemd/journald.conf.d/size.conf` | Limits the systemd journal to 200 MB (`SystemMaxUse=200M`) |
| `/etc/systemd/system/imsss-backend.service` | Backend service unit |
| `/etc/systemd/system/imsss-frontend.service` | Frontend service unit |
| `/etc/systemd/system/imsss-frontend.service.d/override.conf` | Drop-in that runs the production build of the frontend |
| `/etc/systemd/system/imsss-backup.service`, `imsss-backup.timer` | Runs the backup script daily at 21:30 UTC |
| `/etc/imsss-frontend.env` | Settings for building and running the production build of the frontend |
| `frontend/core/packages/volto/build/` | The production build of the frontend; `build/BUILD_COMMIT` names the commit it was built from, for builds made in CI |
| `frontend/core/packages/volto/build.prev/` | The previous build, kept by `devops/scripts/deploy.sh` so a deploy can go back to it |
| `frontend/core/packages/volto/build.new/`, `build.failed/` | Left by `deploy.sh` only if a deploy stopped part-way, or a new build failed to start; safe to delete |
| `/etc/imsss-deploy.env` | GitHub token that `deploy.sh` uses to download builds from CI, as `GITHUB_TOKEN=...`; owned by root, mode 600. A fine-grained token with read access to Actions on `tkimnguyen/imsss-2025` only, created on October 28, 2026, and expiring on December 27, 2026. Renew it before then. |
| `/etc/nginx/sites-enabled/plone.conf` | nginx site configuration |
| `/var/log/nginx/new.imsss.net.access.log`, `.error.log` | nginx logs |

The `backend/instance/` folder is generated during installation and isn't in git.

On October 28, 2026, folders left over from earlier work were removed to free disk space: `~/imsss.net` (a checkout of the older `tkimnguyen/imsss.net` site), `~/clean-test-plone-6.1.3`, `~/imsss.net-migration-20251014`, and `/root/imsss.net migration 20251014` (the database and blobs from before the migration to this site).
A copy of the old site's data and uncommitted files, and of the pre-migration database and blobs, was kept off the server first.
Caches, an unused Node.js version, old snap revisions, and failed-login logs were also removed, and the journal was limited to 200 MB.

## Services

Both services run as `plone`, start at boot, and restart 5 seconds after a failure.

### `imsss-backend.service`

```ini
[Unit]
Description=IMSSS Plone Backend
After=network.target

[Service]
Type=simple
User=plone
Group=plone
WorkingDirectory=/home/plone/imsss.net-plone-6.1.3/imsss-2025/backend
ExecStart=/home/plone/imsss.net-plone-6.1.3/imsss-2025/backend/.venv/bin/runwsgi \
    /home/plone/imsss.net-plone-6.1.3/imsss-2025/backend/instance/etc/zope.ini
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### `imsss-frontend.service`

```ini
[Unit]
Description=IMSSS Volto Frontend
After=network.target imsss-backend.service
Wants=imsss-backend.service

[Service]
Type=simple
User=plone
Group=plone
WorkingDirectory=/home/plone/imsss.net-plone-6.1.3/imsss-2025/frontend
Environment="PATH=/home/plone/.nvm/versions/node/v22.21.1/bin:/usr/local/bin:/usr/bin:/bin"
Environment="VOLTOCONFIG=/home/plone/imsss.net-plone-6.1.3/imsss-2025/frontend/volto.config.js"
ExecStart=/home/plone/.nvm/versions/node/v22.21.1/bin/pnpm --filter @plone/volto start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

The unit file above still contains the original development-server command.
Since October 28, 2026, a drop-in replaces it with the production build.
Since October 29, 2026, it starts the build with `node` directly, instead of through `pnpm start:prod`, which saves about 125 MB of memory taken by two waiting `pnpm` processes:

```ini
# /etc/systemd/system/imsss-frontend.service.d/override.conf
[Service]
EnvironmentFile=/etc/imsss-frontend.env
Environment="NODE_ENV=production"
WorkingDirectory=/home/plone/imsss.net-plone-6.1.3/imsss-2025/frontend/core/packages/volto
ExecStart=
ExecStart=/home/plone/.nvm/versions/node/v22.21.1/bin/node build/server.js
ExecStartPost=/bin/sh -c 'until curl -fsS -o /dev/null http://127.0.0.1:3000/; do sleep 2; done'
TimeoutStartSec=120
```

`/etc/imsss-frontend.env` holds:

```ini
RAZZLE_PUBLIC_URL=https://new.imsss.net
RAZZLE_INTERNAL_API_PATH=http://localhost:8080/Plone
RAZZLE_BIND_ADDRESS=127.0.0.1
```

`RAZZLE_BIND_ADDRESS`
:   Makes the frontend listen only on `127.0.0.1:3000`.
    Without it, Volto's production server listens on every network interface.

`systemctl start` and `systemctl restart` wait until the frontend serves a page, which takes about 5 seconds.
`systemctl cat imsss-frontend.service` shows the unit and the drop-in together.
Node.js 22.21.1 is installed with nvm for the `plone` user.

## nginx

`/etc/nginx/sites-enabled/plone.conf` defines two upstreams, `backend` (`127.0.0.1:8080`) and `frontend` (`127.0.0.1:3000`), and two servers.

Port 443
:   Terminates TLS for `new.imsss.net`, allows uploads of up to 10 MB, and routes requests:

    - `/++api++` and everything below it goes to the backend.
      nginx rewrites the path to `/VirtualHostBase/https/new.imsss.net/Plone/++api++/VirtualHostRoot/...`, so Plone generates `https://new.imsss.net` URLs.
    - `/robots.txt` goes to the backend, rewritten to `/VirtualHostBase/https/new.imsss.net:443/Plone/VirtualHostRoot/robots.txt`, so Plone generates it.
      This rule was added on October 28, 2026, to stop a crash in Volto's own `robots.txt` handler.
      See {doc}`../how-to-guides/fix-a-502`.
    - Files ending in `.js`, `.css`, or font extensions, and static images, go to the frontend with a one-year `Cache-Control: public` header.
    - Everything else goes to the frontend.

    Two timeouts, added on October 29, 2026, close unused connections sooner than nginx's defaults:
    `client_header_timeout 10s` closes a connection that sends no request within 10 seconds, instead of 60, and `keepalive_timeout 15s` closes an idle connection after 15 seconds, instead of 75.
    The first stops bots that open connections without sending anything from holding hundreds of them.

Port 80
:   Redirects `new.imsss.net` to HTTPS, and returns `404` for any other host name or for the server's IP address.

`plone.conf` is the only site in `/etc/nginx/sites-enabled/`.
nginx's `default` site, which showed a "Welcome to nginx!" page for other host names, was turned off on October 28, 2026, by removing its link from `sites-enabled`.
Its file is still in `/etc/nginx/sites-available/default`.

nginx listens only on IPv4, and `new.imsss.net` has no IPv6 (`AAAA`) record.

## HTTPS certificate

<!-- vale Microsoft.We = NO -->
The certificate comes from Let's Encrypt and is managed by the certbot snap.
<!-- vale Microsoft.We = YES -->
`snap.certbot.renew.timer` runs twice a day and renews the certificate when it's close to expiring.
The renewal settings are in `/etc/letsencrypt/renewal/new.imsss.net.conf`.

```shell
sudo certbot certificates                 # show the certificate and its expiry date
sudo certbot renew --dry-run              # test that renewal works
```

## Logs and status

```shell
systemctl status imsss-frontend.service imsss-backend.service nginx
journalctl -u imsss-frontend.service -f                 # follow frontend output
journalctl -u imsss-backend.service -n 100 --no-pager
sudo tail -f /var/log/nginx/new.imsss.net.error.log
ss -ltn | grep -E ':3000|:8080'                         # check both apps are listening
sudo fail2ban-client status sshd                        # addresses currently banned from SSH
```

## Logging in to the server

`new.imsss.net` points to Cloudflare, which carries only web traffic, so SSH has to use the server's own IPv4 address.
That address isn't in these docs, because publishing it would let anyone go around Cloudflare.
Find it in Cloud Manager, on the Linode's {guilabel}`Network` tab, and add an alias for it to `~/.ssh/config` on your computer:

```text
Host imsss-server
    HostName SERVER-ADDRESS
```

These docs use `imsss-server` in every SSH, `scp`, and `rsync` command, and `devops/scripts/pull-backups.sh` uses it too.
If the server's address changes, update `HostName`.

SSH accepts only key logins.
`/etc/ssh/sshd_config.d/00-imsss.conf` sets:

```ini
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
```

The SSH server uses the first value it finds for each setting, and it reads the files in `sshd_config.d/` before the rest of `/etc/ssh/sshd_config`.
So this file overrides the main file, which still contains the Ubuntu defaults.

To give someone access, add their public key to `~/.ssh/authorized_keys` for `plone` or `root`.
`plone`'s file also has a key that can only read the backups, used to copy them off the server; see {doc}`../how-to-guides/back-up-and-restore`.
Account passwords still work in the hosting provider's web console, but not over SSH.

`plone` isn't in the `sudo` group.
Commands in these docs that start with `sudo` need root: run them in an SSH session as `root`, where they work with or without `sudo`.

Before changing these settings, keep an SSH session open, then check the configuration and reload:

```shell
sudo sshd -t
sudo systemctl reload ssh.service
```

Test a new login from another terminal before closing the open session.
If the new login fails, use the open session to fix the file.

## fail2ban

fail2ban watches the SSH log and bans, through the firewall, any address that fails to log in 5 times within 10 minutes.
A ban lasts an hour at first, and gets longer each time the same address is banned again, up to a week.
The settings are in `/etc/fail2ban/jail.d/imsss.local`.

`ignoreip` in that file lists addresses that are never banned: the server itself, and the maintainer's address as of October 28, 2026.
Update it if that address changes.

To see or lift bans:

```shell
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd unbanip ADDRESS
```

If you're banned yourself, log in from another address or through the hosting provider's web console, then lift the ban.

## Cloudflare

Since October 29, 2026, Cloudflare's proxy sits in front of the site.
The `imsss.net` domain's DNS was already on Cloudflare, and the `new` record was switched from {guilabel}`DNS only` to {guilabel}`Proxied`.
Visitors connect to Cloudflare, and Cloudflare connects to nginx on port 443.

The zone's SSL mode is {guilabel}`Automatic SSL/TLS`, which runs as {guilabel}`Full` for the whole zone.
A Configuration Rule for the host name `new.imsss.net` sets the SSL mode to {guilabel}`Full (strict)`, so Cloudflare checks the server's Let's Encrypt certificate.
If that check ever fails, visitors see Cloudflare's error 526 instead of the site.

SSH doesn't go through Cloudflare, as "Logging in to the server" explains.
Firewall rules and fail2ban bans apply only to connections made directly to the server, not to visitors who come through Cloudflare.
Block those in the Cloudflare dashboard instead.

## Connection tracking

The firewall keeps a table of open connections, the connection-tracking table.
When the table is full, the kernel drops new connections, so the site, and SSH, stop responding, while the server itself looks healthy.
The kernel logs `nf_conntrack: table full, dropping packet` when this happens.

The table's default size depends on the server's memory: 8,192 connections on the 1 GB plan.
That filled within seconds of booting after the move to the 1 GB plan on October 29, 2026, so `/etc/sysctl.d/60-imsss-conntrack.conf` now sets:

```ini
net.netfilter.nf_conntrack_max = 65536
net.netfilter.nf_conntrack_tcp_timeout_established = 600
```

The first line allows 65,536 connections, using about 20 MB of memory.
The second makes the table forget a connection that has sent nothing for 10 minutes, instead of 5 days.
A connection that wakes up after that is picked up again, so idle SSH sessions keep working.

Boot applies `sysctl.d` files before the firewall loads connection tracking, so `/etc/modules-load.d/imsss-conntrack.conf` loads it earlier, with the line `nf_conntrack`.

To check the table:

```shell
sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max
journalctl -k -b | grep -c "table full"
```

After changing the file, apply it by running `sysctl --system` as root.

After a reboot on October 29, 2026, one address, `15.204.77.139`, opened about 10 connections a second to port 443 while sending almost no requests.
It held up to 770 connections at once, as many as the 768 that nginx's single worker can handle, and filled the connection-tracking table by about 75 entries a second.
A firewall rule blocks it:

```shell
ufw insert 1 deny from 15.204.77.139 comment "connection flood, October 29, 2026"
```

`ufw status numbered` lists it as rule 1.
To remove it, run `ufw delete 1` as root, after checking that it's still rule 1.
Block any other address that does the same, in the same way.

## Reach the apps from your computer

Both apps listen only on the server's loopback interface.
To reach them from your computer, open a tunnel:

```shell
ssh plone@imsss-server -L8080:localhost:8080 -L3000:localhost:3000
```

While it's open, `http://localhost:8080/` reaches the server's Plone backend and Zope management interface, and `http://localhost:3000/` reaches its Volto frontend.
Don't run a local backend or frontend at the same time, because they use the same ports.

## Swap

The server has about 2.5 GB of swap: a 512 MB partition, `/dev/sdb`, and a 2 GB swap file, `/swapfile`, added on October 28, 2026, using the steps below.

On the 1 GB plan, the running site uses about 650 MB of memory, including Ubuntu itself, as measured on October 29, 2026.
The swap file lets occasional peaks, and reinstalling frontend dependencies during a deploy, use more than that without running out of memory.

To add a 2 GB swap file, run these commands as root:

```shell
df -h /                          # check there's at least 2 GB free first
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

The last line keeps the swap file in use after a reboot.
The swap file adds to the existing swap partition rather than replacing it.

Check the result:

```shell
swapon --show      # lists /swapfile with a size of 2G
free -m            # the Swap row includes the new 2 GB
```

## The `admin` account

`admin` is the initial Zope user, with the `Manager` role.
It lives in the user folder at the Zope root, `/acl_users`, not in the Plone site's `/Plone/acl_users`.
The password was last changed on October 28, 2026.

The ZMI logs you in with HTTP Basic authentication.
<!-- vale Microsoft.We = NO -->
VS Code's built-in browser doesn't show the login prompt and displays "We're sorry, but there seems to be an error…" instead, so use a regular browser.
<!-- vale Microsoft.We = YES -->

To change the password:

1.  Open the tunnel above, then open `http://localhost:8080/manage_main` in a regular browser and log in as `admin`.
2.  Select {guilabel}`acl_users` at the Zope root.
3.  Select {guilabel}`admin`, enter the new password in both password fields, keep the {guilabel}`Manager` role, and save.
    If `acl_users` lists plugins instead of users, select {guilabel}`users`, then the {guilabel}`Password` link for `admin`.
4.  Log in again with the new password when the browser asks.

Volto sessions that are already logged in stay valid until their login token expires.

`initial_user_password` in `backend/instance.yaml` sets the password only when the instance is first created.
It doesn't change the live password, and the live password isn't stored in this repository.

## Backups

The server is a Linode, and the Linode Backup Service backs up its whole disk automatically.
The backups are stored by Linode, outside the server.
Linode keeps three: one from the last day, one about a week old, and one about two weeks old.
As of October 28, 2026, the backups listed in Linode's Cloud Manager were from October 18, 25, and 28, each taken at 22:12 server time.

To see them, open the Linode in Cloud Manager and select the {guilabel}`Backups` tab.

Keep these limits in mind:

- Nothing older than about two weeks is kept.
  A mistake noticed later than that is in every backup.
- A restore brings back the whole disk, not single files or pages.
  For recent content mistakes, Plone's {guilabel}`History` and undo are quicker.
- The disk is copied while the site runs.
  The ZODB only appends to `Data.fs`, so a copy is normally usable, but the last transaction or two may be missing.

The server also backs up the site's content itself, every day at 21:30 UTC, before the Linode backup window.
`imsss-backup.timer` runs `/home/plone/bin/imsss-backup.sh` as `plone`, which writes to `/home/plone/backups/`:

- `filestorage/`: `repozo` backups of `Data.fs`, full on Sundays and incremental on other days
- `blobs/`: a dated archive of the blobs folder each day

It keeps 30 days of restore points.
`repozo` copies only complete transactions, so each Linode backup also contains a consistent copy of the database from less than an hour earlier.
These backups are small: about 6 MB for a full database backup and 42 MB for each blob archive in October 2026.
They were set up on October 28, 2026, and a test restore matched the live database.

```shell
systemctl list-timers imsss-backup.timer                # when the next backup runs
journalctl -u imsss-backup.service -n 20 --no-pager     # output of the last backups
sudo ls -lh /home/plone/backups/filestorage /home/plone/backups/blobs
```

The maintainer's Mac copies these backups every day and keeps a longer history.

For how that copy works, and how to restore from any of these backups, see {doc}`../how-to-guides/back-up-and-restore`.
