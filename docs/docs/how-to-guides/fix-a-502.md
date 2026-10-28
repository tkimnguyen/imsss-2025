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

Run the commands in this guide on the server as root.

```shell
ssh root@new.imsss.net
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

The frontend runs a production build.
When it crashes, its main process exits and systemd restarts it 5 seconds later, so a single crash causes only a short outage.
A 502 that lasts longer usually means the frontend fails again each time it starts.

Check whether systemd keeps restarting it:

```shell
systemctl status imsss-frontend.service --no-pager | sed -n 1,8p
systemctl show imsss-frontend.service -p NRestarts
```

`activating (auto-restart)` or a growing `NRestarts` count means it keeps failing.
Look for the moments it exited:

```shell
journalctl -u imsss-frontend.service --no-pager -o short-iso | grep -nE "Main process exited|Failed with result" | tail -5
```

Then read the error just before one of them, replacing the times with the ones you found:

```shell
journalctl -u imsss-frontend.service --no-pager -o short-iso \
    --since "2026-10-28 15:10" --until "2026-10-28 15:12" | grep -v '^\S* \S* \S*\[[0-9]*\]:\s*at '
```

The `grep -v` hides stack trace lines so that the error messages stand out.

## 3. Restart the frontend

```shell
sudo systemctl restart imsss-frontend.service
```

The command waits until the frontend serves a page, which takes about 5 seconds.
If the frontend doesn't respond within 120 seconds, the command fails, and `systemctl status` shows why.
If it started failing after a deploy, go back to the previous build, as in the next section.

## If a deploy caused it

`devops/scripts/deploy.sh` keeps the build it replaced in `frontend/core/packages/volto/build.prev/`.
If a new build doesn't start, the script goes back to that build by itself.
If the new build starts but fails later, go back by hand, as root:

```shell
cd /home/plone/imsss.net-plone-6.1.3/imsss-2025/frontend/core/packages/volto
rm -rf build.failed
mv build build.failed && mv build.prev build
systemctl restart imsss-frontend.service
```

The next run of `deploy.sh` deploys the build of the newest commit that changed the frontend, which is the failed one until a fix is pushed.
So fix the problem in the repository first, wait for CI to pass, and then deploy again.
Delete `build.failed` once the fix is deployed.

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
:   A file that the theme's SCSS refers to is missing.
    The development server shows this error while it runs, which is how it reached the live site before October 28, 2026.
    The production build reads the theme's files only while it's built, so now the error makes the `production-build` job in CI fail instead, and `deploy.sh` has no build to deploy.
    Add the missing file, or remove the reference to it, and push.

`Cannot find module '@kitconcept/volto-light-theme'` at startup
:   Volto can't find the site's add-ons from its own folder.
    `deploy.sh` goes back to the previous build when this happens.
    Check that `frontend/.npmrc` hoists `@kitconcept/*` and `@eeacms/*`.
    If it doesn't, fix it in the repository and deploy again: `deploy.sh` reinstalls the frontend dependencies when `.npmrc` changes.
    See {doc}`switch-frontend-to-production`.
