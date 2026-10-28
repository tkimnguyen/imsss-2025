---
myst:
  html_meta:
    "description": "What to do when new.imsss.net returns 502 Bad Gateway"
    "property=og:description": "What to do when new.imsss.net returns 502 Bad Gateway"
    "property=og:title": "Fix a 502 Bad Gateway error"
    "keywords": "Plone, IMSSS 2025, 502, outage, systemd, journalctl, Volto"
---

# Fix a 502 Bad Gateway error

nginx returns `502 Bad Gateway` when the app it forwards a request to isn't answering.
The frontend handles every page and the backend handles `/++api++`, so a 502 on every page almost always means the frontend.

Run the commands in this guide on the server as `plone`.

```shell
ssh plone@new.imsss.net
```

## 1. Find which app isn't listening

```shell
ss -ltn | grep -E ':3000|:8080'
```

`127.0.0.1:3000`
:   The frontend. If this line is missing, go to step 2.

`127.0.0.1:8080`
:   The backend. If this line is missing, check `systemctl status imsss-backend.service` and `journalctl -u imsss-backend.service -n 100 --no-pager`, then restart it as in step 3.

## 2. Find out why the frontend stopped

```{note}
`systemctl status imsss-frontend.service` can report `active (running)` even when the frontend is down.
The frontend currently runs as a development server, in which the process that serves pages can exit while its parent process keeps running.
Check the port and the journal, not only the status.
```

Look for the line that marks the moment the page server exited:

```shell
journalctl -u imsss-frontend.service --no-pager -o short-iso | grep -n "Script exited" | tail -3
```

Then read the error just before it, replacing the times with the ones you found:

```shell
journalctl -u imsss-frontend.service --no-pager -o short-iso \
    --since "2026-10-27 22:20" --until "2026-10-27 22:29" | grep -v '^\S* \S* pnpm\[[0-9]*\]:\s*at '
```

The `grep -v` hides stack trace lines so that the error messages stand out.

## 3. Restart and wait until the site responds

```shell
sudo systemctl restart imsss-frontend.service && \
until curl -fsS -o /dev/null http://127.0.0.1:3000/; do sleep 2; done && \
echo "frontend is serving on :3000"
```

The development server compiles the whole site on startup, which takes a minute or two.

## 4. Check the site from outside

```shell
curl -s -o /dev/null -w '%{http_code}\n' https://new.imsss.net/
```

You should see `200`.
Also open the site in a browser without an SSH tunnel, for example on your phone over mobile data, to see it as visitors do.

## Known causes

`TypeError: Cannot destructure property 'text' of 'undefined'` in `helpers/Robots/Robots.js`
:   A request for `/robots.txt` failed at the network level, and Volto's `robots.txt` handler crashed on the missing response.
    This caused the outage of October 27, 2026, which lasted from 22:28 UTC until the service was restarted the next day.
    It happened again on October 28, 2026, at 09:14 and 13:20 UTC.
    Many `TypeError: Converting circular structure to JSON ... issuerCertificate` lines before it show that HTTPS requests made during page rendering were failing.

    To stop this crash, nginx now fetches `robots.txt` from Plone, so Volto's handler never runs.
    This block was added to the port 443 `server` in `/etc/nginx/sites-enabled/plone.conf`, before `location ~ /`, on October 28, 2026:

    ```nginx
    location = /robots.txt {
        rewrite ^ /VirtualHostBase/https/$server_name:443/Plone/VirtualHostRoot/robots.txt break;
        proxy_pass http://backend;
        proxy_set_header Host $host;
    }
    ```

    The configuration from before the change is saved as `/root/plone.conf.bak-20261028`.
    To undo the change, run these commands as root:

    ```shell
    cp /root/plone.conf.bak-20261028 /etc/nginx/sites-enabled/plone.conf
    nginx -t && systemctl reload nginx
    ```

    The backup is outside `/etc/nginx/`, so nginx doesn't load it.
    Delete it once you no longer need to undo the change.

`Can't resolve '.../packages/volto-imsss-2025/src/theme/...'`
:   A file that the theme's SCSS refers to is missing from the checkout.
    Check `git status` on the server; the file may have been deleted or not yet pulled.

Switching the frontend to a production build stops a crash from leaving the site down, because systemd then restarts the frontend automatically.
See {doc}`switch-frontend-to-production`.
