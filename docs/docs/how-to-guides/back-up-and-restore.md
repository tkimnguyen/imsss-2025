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
If the whole server is lost, see {doc}`recover-the-server` instead.
A backup must include both, taken at about the same time.
A `Data.fs` restored without its matching blobs shows broken images.

The Linode Backup Service backs up the server's whole disk, keeping about two weeks of backups.
See the "Backups" section of {doc}`../reference/server` for what it covers.
The server also makes its own daily `repozo` backups of the database and blobs, set up on October 28, 2026, as described in "Schedule a daily database backup" below.
They keep 30 days of restore points, and they can restore only the content instead of the whole disk.
They're on the server's disk, so a Mac also copies them every day and keeps a longer history, as described in "Copy the backups off the server" below.

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

The server already has this set up.
Use these steps to set it up again, for example on a new server.

1.  Save this script as `/home/plone/bin/imsss-backup.sh`, owned by `plone`, and make it executable with `chmod +x`.

    ```shell
    #!/bin/sh
    # Back up the IMSSS Plone database and blobs to ~/backups.
    # Run daily by imsss-backup.timer, before the Linode backup window.
    set -eu
    umask 077
    BACKEND=/home/plone/imsss.net-plone-6.1.3/imsss-2025/backend
    DEST=/home/plone/backups
    mkdir -p "$DEST/filestorage" "$DEST/blobs"

    # Full backup on Sundays, incremental on other days
    FULL=""
    [ "$(date +%u)" = 7 ] && FULL="-F"
    "$BACKEND/.venv/bin/repozo" -B -z $FULL -r "$DEST/filestorage" \
        -f "$BACKEND/instance/var/filestorage/Data.fs"

    tar -czf "$DEST/blobs/blobs-$(date +%Y%m%d).tar.gz" -C "$BACKEND/instance/var" blobs

    # Keep 30 days of restore points. Database files are kept a week longer,
    # so the oldest incremental backups still have their full backup.
    find "$DEST/filestorage" -type f -mtime +37 -delete
    find "$DEST/blobs" -type f -mtime +30 -delete
    ```

    `umask 077` makes the backups readable only by `plone`, because the database includes password hashes.

2.  Create `/etc/systemd/system/imsss-backup.service`.

    ```ini
    [Unit]
    Description=Back up the IMSSS Plone database and blobs

    [Service]
    Type=oneshot
    User=plone
    Nice=10
    IOSchedulingClass=idle
    ExecStart=/home/plone/bin/imsss-backup.sh
    ```

3.  Create `/etc/systemd/system/imsss-backup.timer`.
    The Linode backup window starts at about 22:12 UTC, so this time puts a fresh backup in each Linode backup.

    ```ini
    [Unit]
    Description=Daily IMSSS backup, before the Linode backup window

    [Timer]
    OnCalendar=*-*-* 21:30:00 UTC
    Persistent=true

    [Install]
    WantedBy=timers.target
    ```

4.  As root, enable the timer, run the backup once by hand, and check the result.

    ```shell
    sudo systemctl daemon-reload
    sudo systemctl enable --now imsss-backup.timer
    sudo systemctl start imsss-backup.service
    journalctl -u imsss-backup.service -n 20 --no-pager
    sudo ls -lh /home/plone/backups/filestorage /home/plone/backups/blobs
    ```

## Copy the backups off the server

Backups on the server's disk don't survive losing the server, and the Linode backups keep only about two weeks.
So since October 28, 2026, the maintainer's Mac copies the backups every day and keeps a longer history.
It uses `devops/scripts/pull-backups.sh`, which launchd runs at 18:00 local time, and again at login.
If the Mac is asleep at 18:00, launchd runs the copy when it wakes up.

The copy in `~/imsss-backups` keeps:

- everything from the last 45 days
- after that, each weekly full database backup, with the blob archive from the same day
- after a year, only the first of those in each month

At October 2026 sizes, that's about 4 GB after the first year, growing by about 600 MB a year after that, and more as the site adds images and files.
The script removes old incremental database backups one whole week at a time, because `repozo` needs every incremental backup between a full backup and the point being restored.
It shows a macOS notification if the copy fails, or if the newest backup is more than 3 days old.

The copy logs in with its own SSH key, `~/.ssh/imsss_backup_pull`, which has no passphrase so that it can run unattended.
On the server, `plone`'s `authorized_keys` limits that key to reading `/home/plone/backups` with `rrsync -ro`.
It can't open a shell, run commands, open tunnels, or write or delete files.
The backups include password hashes, so keep them only on an encrypted disk, such as a Mac with FileVault turned on.

### Set up the copy on a Mac

1.  Install Homebrew's `rsync`.
    The `rsync` that comes with macOS, `openrsync`, sends options that `rrsync` refuses.

    ```shell
    brew install rsync
    ```

2.  Create a key, and add it to `/home/plone/.ssh/authorized_keys` on the server, restricted to the backups folder.

    ```shell
    ssh-keygen -t ed25519 -N "" -C "imsss-backup-pull" -f ~/.ssh/imsss_backup_pull
    echo "command=\"/usr/bin/rrsync -ro /home/plone/backups\",restrict $(cat ~/.ssh/imsss_backup_pull.pub)" |
        ssh plone@new.imsss.net 'cat >> ~/.ssh/authorized_keys'
    ```

3.  Install the script.

    ```shell
    mkdir -p ~/.local/bin ~/imsss-backups
    install -m 755 devops/scripts/pull-backups.sh ~/.local/bin/imsss-pull-backups
    ```

4.  Save this as `~/Library/LaunchAgents/net.imsss.backup-pull.plist`, replacing `USER` with your macOS user name.

    ```xml
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>net.imsss.backup-pull</string>
        <key>ProgramArguments</key>
        <array>
            <string>/bin/zsh</string>
            <string>/Users/USER/.local/bin/imsss-pull-backups</string>
        </array>
        <key>StartCalendarInterval</key>
        <dict>
            <key>Hour</key>
            <integer>18</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <key>RunAtLoad</key>
        <true/>
        <key>StandardOutPath</key>
        <string>/Users/USER/imsss-backups/pull.log</string>
        <key>StandardErrorPath</key>
        <string>/Users/USER/imsss-backups/pull.log</string>
    </dict>
    </plist>
    ```

5.  Load the launchd job, which also runs the first copy, and check the log.

    ```shell
    launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/net.imsss.backup-pull.plist
    cat ~/imsss-backups/pull.log
    ```

After changing the script in the repository, install it again with step 3.
To stop the copies, run `launchctl bootout gui/$(id -u)/net.imsss.backup-pull` and delete the plist file.

To restore from the Mac's copy, copy the files back to `/home/plone/backups` on the server, or point `repozo -R -r` at a folder holding them.

## Restore from a database backup

`plone` can't use `sudo`, so run the `sudo` commands in a second SSH session as root, and the others as `plone`.

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
