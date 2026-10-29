#!/bin/bash
# Apply devops/cloudflare-ips.txt to new.imsss.net: allow web traffic (ports 80
# and 443) only from Cloudflare's address ranges in the firewall, and rebuild
# nginx's list of addresses it takes visitors' real addresses from. Run it on
# the server as root, after updating the checkout:
#
#   /home/plone/imsss.net-plone-6.1.3/imsss-2025/devops/scripts/apply-cloudflare-ranges.sh
#
# It adds a firewall rule, commented "cloudflare", for each range in the list,
# and removes "cloudflare" rules for ranges no longer in it. It doesn't touch
# any other rule.
set -euo pipefail

LIST=$(dirname "$0")/../cloudflare-ips.txt
REALIP=/etc/nginx/conf.d/cloudflare-realip.conf

log() { echo "==> $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || fail "run this script as root"
mapfile -t RANGES < <(grep -vE '^\s*(#|$)' "$LIST")
[ "${#RANGES[@]}" -ge 10 ] || fail "$LIST has only ${#RANGES[@]} ranges"
for r in "${RANGES[@]}"; do
    [[ $r =~ ^[0-9a-f.:]+/[0-9]+$ ]] || fail "not an address range: $r"
done

# 1. nginx: rebuild the real-address settings, keeping the old file if the
#    new one doesn't pass nginx -t.
log "updating $REALIP"
old=$(mktemp)
cp "$REALIP" "$old" 2>/dev/null || true
{
    echo "# Cloudflare proxies new.imsss.net. Take the visitor's real address from"
    echo "# CF-Connecting-IP, trusting it only from Cloudflare's address ranges."
    echo "# Written by devops/scripts/apply-cloudflare-ranges.sh from devops/cloudflare-ips.txt."
    printf 'set_real_ip_from %s;\n' "${RANGES[@]}"
    echo "real_ip_header CF-Connecting-IP;"
} > "$REALIP"
if ! nginx -t 2>/dev/null; then
    cp "$old" "$REALIP"
    rm -f "$old"
    fail "nginx rejected the new $REALIP; kept the old one"
fi
rm -f "$old"
systemctl reload nginx

# 2. Firewall: add a rule for each range, then remove rules for old ranges.
log "adding firewall rules"
for r in "${RANGES[@]}"; do
    ufw allow proto tcp from "$r" to any port 80,443 comment cloudflare >/dev/null
done
mapfile -t RULES < <(ufw show added | grep -F "comment 'cloudflare'" || true)
for line in "${RULES[@]}"; do
    r=$(echo "$line" | sed -E 's/.* from ([^ ]+) .*/\1/')
    if ! printf '%s\n' "${RANGES[@]}" | grep -qxF "$r"; then
        log "removing the rule for $r, which Cloudflare no longer lists"
        ufw delete allow proto tcp from "$r" to any port 80,443 >/dev/null
    fi
done

log "done: $(ufw show added | grep -cF "comment 'cloudflare'") Cloudflare rules, for ${#RANGES[@]} ranges"
