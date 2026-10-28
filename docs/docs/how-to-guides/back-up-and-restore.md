---
myst:
  html_meta:
    "description": "How to back up and restore the new.imsss.net database"
    "property=og:description": "How to back up and restore the new.imsss.net database"
    "property=og:title": "Back up and restore the site"
    "keywords": "Plone, IMSSS 2025, backup, restore, ZODB, repozo, pack"
---

# Back up and restore the site

All of the site's content lives in two places on the server:

`backend/instance/var/filestorage/Data.fs`
:   The ZODB database: pages, settings, users, and everything else except file contents.

`backend/instance/var/blobs/`
:   The contents of uploaded images and files.

Both paths are relative to the checkout at `/home/plone/imsss.net-plone-6.1.3/imsss-2025`.
A backup must include both, taken at about the same time.
A `Data.fs` restored without its matching blobs shows broken images.

The Linode Backup Service backs up the server's whole disk, keeping about two weeks of backups.
See the "Backups" section of {doc}`../reference/server` for what it covers.
The `repozo` backups described later in this guide are optional.
They keep database backups for longer than two weeks, and they can restore only the database instead of the whole disk.
As of October 28, 2026, they aren't set up.

## Restore from a Linode backup

Restore to a new Linode first, rather than over the live server.
You can then check the backup, or copy content from it, without touching the live site.

1.  In Cloud Manager, open the Linode, select the {guilabel}`Backups` tab, and choose the backup to restore.
2.  From its menu, choose {guilabel}`Deploy New Linode`, and pick a plan.
    Linode bills the new Linode until you delete it.
3.  Log in to the new Linode with SSH as `root`, using its IP address.
    It accepts the same keys as the live server.
4.  Check that the backend starts, and that the content is what you expect.

    ```shell
    systemctl status imsss-backend.service --no-pager
    curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/Plone/++api++
    ```

    To browse the site, open an SSH tunnel to the new Linode's IP address, as described in {doc}`../reference/server`.
    Check the content through the backend at `http://localhost:8080/Plone`, not the frontend.
    The restored frontend is set up for `https://new.imsss.net`, so in a browser it loads content from the live site.

5.  If you need only some content, export it from the new Linode, or copy `Data.fs` and `blobs` from it as described below.
6.  Delete the new Linode when you're done.

To replace the live server with the backup instead, choose {guilabel}`Restore to Existing Linode`.
This overwrites the live server's disk, including any content added since the backup.

## Take a one-off database backup

Run these commands on the server as `plone`.
The backend can keep running.
`repozo` reads only committed transactions, and blob files never change once written.

```shell
cd ~/imsss.net-plone-6.1.3/imsss-2025/backend
mkdir -p ~/backups/filestorage ~/backups/blobs

# Database: a full, compressed backup the first time, then incremental backups
.venv/bin/repozo -B -z -r ~/backups/filestorage -f instance/var/filestorage/Data.fs

# Blobs: a dated archive
tar -czf ~/backups/blobs/blobs-$(date +%Y%m%d-%H%M).tar.gz -C instance/var blobs
```

Add `-F` to the `repozo` command to force a full backup instead of an incremental one.

## Schedule a daily database backup

1.  Save this script as `/home/plone/bin/imsss-backup.sh` and make it executable with `chmod +x`.

    ```shell
    #!/bin/sh
    set -eu
    BACKEND=/home/plone/imsss.net-plone-6.1.3/imsss-2025/backend
    DEST=/home/plone/backups
    mkdir -p "$DEST/filestorage" "$DEST/blobs"

    # Full backup on Sundays, incremental on other days
    FULL=""
    [ "$(date +%u)" = 7 ] && FULL="-F"
    "$BACKEND/.venv/bin/repozo" -B -z $FULL -r "$DEST/filestorage" \
        -f "$BACKEND/instance/var/filestorage/Data.fs"

    tar -czf "$DEST/blobs/blobs-$(date +%Y%m%d).tar.gz" -C "$BACKEND/instance/var" blobs

    # Keep 30 days of backups
    find "$DEST/filestorage" "$DEST/blobs" -type f -mtime +30 -delete
    ```

2.  Create `/etc/systemd/system/imsss-backup.service`.

    ```ini
    [Unit]
    Description=Back up the IMSSS Plone database and blobs

    [Service]
    Type=oneshot
    User=plone
    ExecStart=/home/plone/bin/imsss-backup.sh
    ```

3.  Create `/etc/systemd/system/imsss-backup.timer`.

    ```ini
    [Unit]
    Description=Daily IMSSS backup

    [Timer]
    OnCalendar=*-*-* 03:30:00
    Persistent=true

    [Install]
    WantedBy=timers.target
    ```

4.  Enable the timer, run the backup once by hand, and check the result.

    ```shell
    sudo systemctl daemon-reload
    sudo systemctl enable --now imsss-backup.timer
    sudo systemctl start imsss-backup.service
    journalctl -u imsss-backup.service -n 20 --no-pager
    ls -lh ~/backups/filestorage ~/backups/blobs
    ```

```{important}
Backups stored on the same disk don't protect against losing the server.
Copy `~/backups` to another machine regularly, for example from your own computer with `rsync -a plone@new.imsss.net:backups/ ~/imsss-backups/`.
```

## Restore from a database backup

1.  Stop the backend.

    ```shell
    sudo systemctl stop imsss-backend.service
    ```

2.  Move the current data aside rather than deleting it.

    ```shell
    cd ~/imsss.net-plone-6.1.3/imsss-2025/backend/instance/var
    mv filestorage filestorage-before-restore-$(date +%Y%m%d)
    mv blobs blobs-before-restore-$(date +%Y%m%d)
    mkdir filestorage
    ```

3.  Restore the database.
    Without `-D`, `repozo` restores the most recent backup.
    To restore an earlier point in time, add `-D YYYY-MM-DD-HH-MM-SS`.

    ```shell
    ../../.venv/bin/repozo -R -r ~/backups/filestorage -o filestorage/Data.fs
    ```

4.  Restore the blobs archive from the same day.

    ```shell
    tar -xzf ~/backups/blobs/blobs-YYYYMMDD.tar.gz
    ```

5.  Start the backend, then check that pages and images load.

    ```shell
    sudo systemctl start imsss-backend.service
    curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/Plone/++api++
    ```

## Pack the database

`Data.fs` keeps every old version of every object, so it grows over time.
Packing removes old versions.

1.  Take a backup first.
2.  Open an SSH tunnel to the server, as described in {doc}`../reference/server`, then go to `http://localhost:8080/Control_Panel/Database/main/manage_main` and log in as a Zope manager.
3.  Enter the number of days of history to keep, for example `7`, and select {guilabel}`Pack`.

The server's `zope.conf` sets `pack-keep-old true`, so packing leaves the previous file as `Data.fs.old`.
Delete it once you've checked the site, to free the disk space.
