#!/bin/zsh
# Copy the new.imsss.net database and blob backups to this Mac, and thin out
# old copies. Run daily by a launchd agent; see "Back up and restore the site"
# in docs/.
#
# The server keeps about 30 days of backups in /home/plone/backups. This copy keeps:
#   - everything from the last 45 days
#   - after that, each weekly full database backup, with the blob archive
#     from the same day
#   - after a year, only the first of those in each month
#
# Usage: pull-backups.sh [--thin-only]
set -eu
setopt null_glob

DEST=${IMSSS_BACKUP_DIR:-$HOME/imsss-backups}
KEY=$HOME/.ssh/imsss_backup_pull
RSYNC=/opt/homebrew/bin/rsync
SOURCE=plone@new.imsss.net:./

notify() { osascript -e "display notification \"$1\" with title \"IMSSS backup copy\"" 2>/dev/null || true; }
fail() { echo "ERROR: $*" >&2; notify "$*"; exit 1; }

echo "== $(date '+%Y-%m-%d %H:%M:%S')"
mkdir -p "$DEST/filestorage" "$DEST/blobs"
chmod 700 "$DEST"

# 1. Copy new backups. The server's key only allows reading /home/plone/backups.
if [[ ${1:-} != --thin-only ]]; then
    $RSYNC -a --itemize-changes \
        -e "ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=30" \
        "$SOURCE" "$DEST/" ||
        fail "couldn't copy the backups from new.imsss.net"
fi

# 2. Thin out copies the server no longer has. 45 days is longer than the
#    server keeps anything, so rsync doesn't copy thinned files again.
keep_after=$(date -v-45d +%Y-%m-%d)
monthly_before=$(date -v-365d +%Y-%m-%d)
fs=$DEST/filestorage

# repozo restores a point in time from the full backup before it plus every
# incremental backup in between, so remove incrementals one whole chain at a
# time, and never from the newest chain.
fulls=($fs/*.fsz(on))
typeset -A kept_days kept_months
for ((i = 1; i <= ${#fulls}; i++)); do
    name=${fulls[i]:t:r}
    day=${name[1,10]}
    [[ $day < $keep_after ]] || continue
    (( i < ${#fulls} )) || continue
    next=${fulls[i+1]:t:r}
    for delta in $fs/*.deltafsz(on); do
        dname=${delta:t:r}
        if [[ $dname > $name && $dname < $next ]]; then
            rm -fv "$delta" "$fs/$dname.index"
        fi
    done
    if [[ $day < $monthly_before ]]; then
        if (( ${+kept_months[${day[1,7]}]} )); then
            rm -fv "${fulls[i]}" "$fs/$name.dat" "$fs/$name.index"
            continue
        fi
        kept_months[${day[1,7]}]=1
    fi
    kept_days[${day//-/}]=1
done

for archive in $DEST/blobs/blobs-*.tar.gz(on); do
    day=${${archive:t}#blobs-}
    day=${day%.tar.gz}
    if [[ ${day[1,4]}-${day[5,6]}-${day[7,8]} < $keep_after ]] && (( ! ${+kept_days[$day]} )); then
        rm -fv "$archive"
    fi
done

# 3. Warn if the server stopped making backups. A blob archive is made every day.
newest=($DEST/blobs/blobs-*.tar.gz(On[1]))
if (( ! ${#newest} )) || [[ ${newest[1]:t} < blobs-$(date -v-3d +%Y%m%d) ]]; then
    fail "the newest backup from new.imsss.net is more than 3 days old"
fi
echo "newest backup: ${newest[1]:t}; $(du -sh "$DEST" | cut -f1) in $DEST"
