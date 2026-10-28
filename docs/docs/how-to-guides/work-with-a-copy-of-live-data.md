---
myst:
  html_meta:
    "description": "How to run a local copy of new.imsss.net with the live site's content"
    "property=og:description": "How to run a local copy of new.imsss.net with the live site's content"
    "property=og:title": "Work with a copy of the live site's content"
    "keywords": "Plone, IMSSS 2025, local development, Data.fs, blobs, copy"
---

# Work with a copy of the live site's content

A local site created with `make backend-create-site` contains only example content.
To try changes against the real pages, copy the live database and blobs to your computer.

```{important}
Edits you make to the local copy stay on your computer.
They don't reach the live site, and copying the live data again overwrites them.
Make content changes on the live site, and use the local copy for trying out code and theme changes.
```

## Before you start

- Install the project locally with `make install`, as in the README's quick start.
- Make sure you can connect to the server with `ssh plone@new.imsss.net`.
- Close any SSH tunnel to the server, because the local backend and frontend use the same ports.

## 1. Stop the local backend

Stop `make backend-start` with {kbd}`Ctrl+C`, or stop whatever runs Plone on port 8080.
Plone must not have `Data.fs` open while you replace it.

## 2. Keep a copy of your current local data

From the repository root:

```shell
cd backend/instance/var
BACKUP=backup-local-$(date +%Y%m%d)
mkdir -p $BACKUP
mv filestorage blobs $BACKUP/
mkdir filestorage
```

## 3. Copy the live data

```shell
REMOTE=plone@new.imsss.net:imsss.net-plone-6.1.3/imsss-2025/backend/instance/var
scp "$REMOTE/filestorage/Data.fs" filestorage/Data.fs
scp -r "$REMOTE/blobs" ./blobs
```

You can copy while the live site is running.
FileStorage only ever appends to `Data.fs`, so a copy taken mid-write ends with a partial transaction, which Plone drops when it opens the file.
Don't copy `Data.fs.index`; Plone rebuilds it on startup.

Check that the copy is complete by comparing sizes with the server:

```shell
ls -l filestorage/Data.fs && find blobs -type f | wc -l
ssh plone@new.imsss.net 'cd imsss.net-plone-6.1.3/imsss-2025/backend/instance/var && ls -l filestorage/Data.fs && find blobs -type f | wc -l'
```

## 4. Start the local site

```shell
make backend-start      # in one terminal, from the repository root
make frontend-start     # in another terminal
```

Open `http://localhost:3000/`.
Log in with an account that exists on the live site.
The local `admin` account created by `make backend-create-site` no longer exists in the copied database.

## Go back to your previous local data

Stop the backend, then swap the folders back:

```shell
cd backend/instance/var
rm -r filestorage blobs
mv backup-local-YYYYMMDD/filestorage backup-local-YYYYMMDD/blobs .
```
