---
myst:
  html_meta:
    "description": "What to do when new.imsss.net doesn't load, or shows a Cloudflare error"
    "property=og:description": "What to do when new.imsss.net doesn't load, or shows a Cloudflare error"
    "property=og:title": "Fix an unresponsive site"
    "keywords": "Plone, IMSSS 2025, outage, Cloudflare, 521, 522, 524, 526, nf_conntrack, bots"
---

# Fix an unresponsive site

Use this guide when `https://new.imsss.net` doesn't load, or shows a Cloudflare error page.
For a `502 Bad Gateway` error, see {doc}`fix-a-502`.

Visitors reach the site through Cloudflare, and the server's firewall accepts web traffic only from Cloudflare.
So a problem can be at Cloudflare, between Cloudflare and the server, or on the server.
See "Cloudflare" in {doc}`../reference/server` for how it's set up.

## 1. Find where it fails

From your own computer:

```shell
curl -s -o /dev/null -w '%{http_code}\n' https://new.imsss.net/
```

Then log in to the server, and check nginx directly, without Cloudflare:

```shell
ssh root@imsss-server
curl -s -o /dev/null -w '%{http_code}\n' --resolve new.imsss.net:443:127.0.0.1 https://new.imsss.net/
systemctl is-active nginx imsss-frontend imsss-backend
```

The server answers `200`, but Cloudflare shows an error
:   The problem is between Cloudflare and the server.
    Look up Cloudflare's error code in the next section.

The server doesn't answer `200` either
:   The problem is on the server.
    For `502`, see {doc}`fix-a-502`.
    If a service isn't `active`, check it with `systemctl status` and `journalctl -u` followed by the service name.

You can't log in over SSH
:   The server may be down, out of memory, or dropping connections.
    See [If you can't log in](#if-you-cant-log-in).

Pages that Cloudflare has cached keep loading for up to 5 minutes after the server stops answering, so check a page you haven't opened recently, or the API, `https://new.imsss.net/++api++/`, which isn't cached.

## 2. Cloudflare's error codes

A Cloudflare error page shows a code, and a diagram of the visitor's browser, Cloudflare, and the server, which Cloudflare calls the host.
The part marked {guilabel}`Error` is where the request failed.

| Code | Meaning | What to check |
| --- | --- | --- |
| 521 | The server refused the connection | nginx is stopped: `systemctl status nginx`. Or the firewall rejects Cloudflare: check `ufw status` for the `cloudflare` rules. |
| 522 | The connection timed out | The firewall is missing some of Cloudflare's address ranges, so check the `cloudflare-ranges.yml` workflow; see "Cloudflare's address ranges" in {doc}`../reference/server`. Or the connection-tracking table is full; see [step 3](#connection-tracking-table-full). Or the server is overloaded or down. |
| 523 | Cloudflare can't reach the server's address | The `A` record for `new` in Cloudflare's DNS points to the wrong address, for example after moving to a new Linode. |
| 524 | The server took more than 100 seconds to answer | Plone or Volto is stuck or overloaded: check `journalctl -u imsss-backend.service -n 100` and the load with `uptime`. |
| 525, 526 | The HTTPS connection to the server failed, or its certificate isn't valid | Check the certificate with `certbot certificates`, and renew it with `certbot renew`; see "HTTPS certificate" in {doc}`../reference/server`. |
| 502, 504 | nginx couldn't get an answer from the frontend or backend | See {doc}`fix-a-502`. |

(connection-tracking-table-full)=
## 3. Connection-tracking table full

The firewall keeps a table of open connections.
When it's full, the kernel drops new connections, so the site and SSH stop responding, or respond only some of the time, while the server itself looks healthy.
This caused the outage of October 29, 2026, after the move to the 1 GB plan.

Check for it:

```shell
journalctl -k -b | grep -c "table full"
sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max
```

A count close to the maximum, or any `table full` messages, means the table filled up.
To make room straight away, raise the limit, for example to double its current value:

```shell
sysctl -w net.netfilter.nf_conntrack_max=131072
```

That lasts until the next reboot.
To keep it, change the value in `/etc/sysctl.d/60-imsss-conntrack.conf`, as described in "Connection tracking" in {doc}`../reference/server`.
Then find out what filled the table, as in the next step.

## 4. A bot or a flood

Since the firewall accepts web traffic only from Cloudflare, a bot can't flood the server directly any more.
Cloudflare's Bot Fight Mode, managed rules, and page cache stop most bots before they reach the server.
Some can still get through, for example a crawler requesting many pages that aren't cached.

Find the busiest clients and user agents in the last 10 minutes:

```shell
L=/var/log/nginx/new.imsss.net.access.log
since=$(date -u -d "-10 min" +%d/%b/%Y:%H:%M)
awk -v s="$since" 'substr($4,2)>=s {print $1}' $L | sort | uniq -c | sort -rn | head
awk -F'"' -v s="$since" '{split($1,a," "); t=substr(a[4],2)} t>=s {print $6}' $L | sort | uniq -c | sort -rn | head
```

The log shows visitors' real addresses, not Cloudflare's.
A single address or user agent with hundreds of requests, far more than the others, is likely a bot.

Block it in the Cloudflare dashboard, not with `ufw`, because the firewall sees only Cloudflare's addresses for web traffic.
Under {guilabel}`Security`, add an IP access rule with the action {guilabel}`Block` for the address, with a note saying why.
During a large attack, turn on {guilabel}`Under Attack Mode` on the zone's {guilabel}`Overview` page, which makes every visitor pass a browser check first, and turn it off again afterward.

For SSH, fail2ban bans addresses that keep failing to log in; see "fail2ban" in {doc}`../reference/server`.

## 5. The server is overloaded

```shell
uptime                       # load averages; the server has 1 vCPU, so above 1 means it's busy
free -m                      # memory and swap use
ps -eo pid,pcpu,rss,etime,comm --sort=-pcpu | head
journalctl -k -b | grep -iE "out of memory|oom" | tail
```

The site normally uses about 650 MB of memory and little swap.
If memory and swap are both close to full, or the kernel log shows processes killed for lack of memory, restart the services, then consider a larger Linode plan; see {doc}`../concepts/hosting-options`.

(if-you-cant-log-in)=
## If you can't log in

If `ssh root@imsss-server` times out, try a few more times: when the connection-tracking table is full, some connections still get through.

Otherwise, use the Linode's console, which doesn't need the network:
in Cloud Manager, open the Linode, and select {guilabel}`Launch LISH Console`.
Log in as `root` with root's password, which SSH doesn't accept but the console does.
If nobody has it, shut the Linode down, set a new one under {guilabel}`Settings` → {guilabel}`Reset Root Password`, and boot it again.
Then follow the steps above.

If the console doesn't respond either, reboot the Linode from Cloud Manager.
The services start by themselves at boot.

## 6. Check the site

When it's fixed, check it through Cloudflare from your own computer, and in a browser:

```shell
curl -s -o /dev/null -w '%{http_code}\n' https://new.imsss.net/
curl -s -o /dev/null -w '%{http_code}\n' https://new.imsss.net/++api++/
```

You should see `200` both times.
