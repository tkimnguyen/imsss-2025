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
| Host name | `new.imsss.net` |
| Operating system | Ubuntu 24.04 LTS |
| Resources | 2 vCPU, 3.8 GB RAM, 512 MB swap, 25 GB disk |
| SSH user for the site | `plone` |
| Docker | Not installed |

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
| `/etc/systemd/system/imsss-backend.service` | Backend service unit |
| `/etc/systemd/system/imsss-frontend.service` | Frontend service unit |
| `/etc/nginx/sites-enabled/plone.conf` | nginx site configuration |
| `/var/log/nginx/new.imsss.net.access.log`, `.error.log` | nginx logs |

The `backend/instance/` folder is generated during installation and isn't in git.

Other folders in `/home/plone` are left over from earlier work and aren't used by the live site.
`~/imsss.net` is a checkout of the older `tkimnguyen/imsss.net` repository, with uncommitted changes.
`~/imsss.net-migration-20251014` holds migration archives.

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

`pnpm --filter @plone/volto start` runs the Volto **development server**.
It listens on `127.0.0.1:3000` for pages and on `[::1]:3001` for its webpack assets.
Node.js 22.21.1 is installed with nvm for the `plone` user.

## nginx

`/etc/nginx/sites-enabled/plone.conf` defines two upstreams, `backend` (`127.0.0.1:8080`) and `frontend` (`127.0.0.1:3000`), and two servers.

Port 443
:   Terminates TLS for `new.imsss.net`, allows uploads of up to 10 MB, and routes requests:

    - `/++api++` and everything below it goes to the backend.
      nginx rewrites the path to `/VirtualHostBase/https/new.imsss.net/Plone/++api++/VirtualHostRoot/...`, so Plone generates `https://new.imsss.net` URLs.
    - Files ending in `.js`, `.css`, or font extensions, and static images, go to the frontend with a one-year `Cache-Control: public` header.
    - Everything else goes to the frontend.

Port 80
:   Redirects `new.imsss.net` to HTTPS and returns `404` for any other host name.

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
```

## Reach the apps from your computer

Both apps listen only on the server's loopback interface.
To reach them from your computer, open a tunnel:

```shell
ssh plone@new.imsss.net -L8080:localhost:8080 -L3000:localhost:3000 -L3001:localhost:3001
```

While it's open, `http://localhost:8080/` reaches the server's Plone backend and Zope management interface, and `http://localhost:3000/` reaches its Volto frontend.
Don't run a local backend or frontend at the same time, because they use the same ports.

## Backups

None are configured.
See {doc}`../how-to-guides/back-up-and-restore`.
