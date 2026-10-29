---
myst:
  html_meta:
    "description": "How Cloudflare is set up in front of new.imsss.net, and how each setting was tested"
    "property=og:description": "How Cloudflare is set up in front of new.imsss.net, and how each setting was tested"
    "property=og:title": "Cloudflare"
    "keywords": "Plone, IMSSS 2025, Cloudflare, proxy, cache, WAF, rate limiting, DNSSEC, firewall"
---

# Cloudflare

Since October 29, 2026, `new.imsss.net` is behind Cloudflare's free plan.
Visitors connect to Cloudflare, which checks each request, answers from its cache when it can, and otherwise forwards the request to nginx on the server.
The server's firewall accepts web traffic only from Cloudflare.

The site moved behind Cloudflare after a bot flooded the server with connections, following the move to the 1 GB Linode plan that day; see "Connection tracking" in {doc}`server`.
For why Cloudflare suits the site, and what it doesn't change, see {doc}`../concepts/hosting-options`.

All of the settings below are in the `imsss.net` zone in the Cloudflare dashboard.
Some apply to the whole zone, including the old site at `imsss.net`, and are marked as such.
The rest apply only to `new.imsss.net`.
Cloudflare moves its menus around from time to time, so the paths to each setting may differ slightly.

```{mermaid}
flowchart LR
    browser([Visitor's browser]) -- "HTTPS, TLS 1.2+" --> cf["Cloudflare<br/>security rules, page cache"]
    cf -- "HTTPS :443, Full (strict)" --> fw["Server firewall<br/>Cloudflare's ranges only"]
    fw --> nginx
    you([Maintainer]) -- "SSH :22, imsss-server alias" --> fw
```

## DNS and the proxy

The domain is registered with Cloudflare, and its DNS was already on Cloudflare before the switch.
The switch was to change the `A` record for `new` from {guilabel}`DNS only` to {guilabel}`Proxied`.
Since then, `new.imsss.net` resolves to Cloudflare's addresses, for IPv4 and IPv6.
Cloudflare serves visitors over IPv6 too, and connects to the server over IPv4, the only protocol nginx listens on.

Cloudflare carries only web traffic, so SSH can't use `new.imsss.net` any more.
It goes to the server's own address, through an `imsss-server` alias in `~/.ssh/config`; see "Logging in to the server" in {doc}`server`.
The server's address isn't in these docs, because publishing it would let anyone go around Cloudflare.

## SSL and TLS

SSL mode
:   The zone's mode is {guilabel}`Automatic SSL/TLS`, which runs as {guilabel}`Full` for the whole zone.
    A Configuration Rule for the host name `new.imsss.net`, under {guilabel}`Rules`, sets it to {guilabel}`Full (strict)` for the new site only, so Cloudflare checks the server's Let's Encrypt certificate.
    If that check ever fails, visitors see Cloudflare's error 526 instead of the site.

{guilabel}`Always Use HTTPS` (zone-wide)
:   Under {guilabel}`SSL/TLS` → {guilabel}`Edge Certificates`.
    Cloudflare redirects every `http://` address to `https://`, keeping the path and query.
    It doesn't redirect certbot's `/.well-known/acme-challenge/` path, which still reaches nginx on port 80, so certificate renewal keeps working.

{guilabel}`Minimum TLS Version` (zone-wide)
:   Under {guilabel}`SSL/TLS` → {guilabel}`Edge Certificates`, set to TLS 1.2.
    Cloudflare refuses TLS 1.0 and 1.1, and accepts TLS 1.2 and 1.3.

HSTS
:   Not turned on.
    Browsers remember it for months, and with `includeSubDomains` it would apply to every name under `imsss.net`, so it's hard to undo.

## Security

DDoS protection (zone-wide)
:   Network-layer, SSL/TLS, and HTTP DDoS protection are always on, and can't be turned off on the free plan.

Managed rules (zone-wide)
:   Cloudflare's managed ruleset is always on.
    It blocks requests that try to exploit well-known vulnerabilities, such as Log4Shell and Shellshock, before they reach the server.
    The free plan can't change its rules, so the dashboard's {guilabel}`Managed rules` list shows {guilabel}`No Managed rules created`.
    {guilabel}`Response rules` also check the server's answers, with Cloudflare's default protection.

Bot Fight Mode (zone-wide)
:   Turned on October 29, 2026, under {guilabel}`Security` → {guilabel}`Settings`.
    Cloudflare challenges or blocks clients it identifies as bots, except verified ones such as search engines.
    The free plan allows no exceptions, so if a legitimate tool, such as an uptime monitor or a script that uses the API, starts getting challenges, turn it off.

Scanner rule
:   A custom rule, `Block scanners on new.imsss.net`, under {guilabel}`Security` → {guilabel}`WAF` → {guilabel}`Custom rules`, with the action {guilabel}`Block`.
    It blocks requests for paths that only attack tools ask for.
    The site runs no PHP and no WordPress, so nothing real matches:

    ```text
    (http.host eq "new.imsss.net" and (
      ends_with(http.request.uri.path, ".php")
      or http.request.uri.path contains "/.env"
      or http.request.uri.path contains "/.git"
      or http.request.uri.path contains "/wp-admin"
      or http.request.uri.path contains "/wp-content"
      or http.request.uri.path contains "/wp-includes"
      or http.request.uri.path contains "/wp-login"
    ))
    ```

    It applies only to `new.imsss.net`, because the old site at `imsss.net` might use PHP.
    Before it, these requests made up most of the site's `404` responses.

Login rate limit
:   A rate limiting rule, `Limit logins on new.imsss.net`, under {guilabel}`Security` → {guilabel}`WAF` → {guilabel}`Rate limiting rules`.
    When an address sends more than 5 login attempts in 10 seconds, Cloudflare blocks its login attempts for 10 seconds, with `429 Too Many Requests`:

    ```text
    (http.host eq "new.imsss.net" and http.request.method eq "POST" and http.request.uri.path eq "/++api++/@login")
    ```

    Volto's login form sends its requests to `/++api++/@login`.
    Cloudflare counts across its data centers, so the block can start an attempt or two after the limit.
    The free plan allows only this one rate limiting rule, and only a 10-second block, so it stops fast password guessing but not slow, patient guessing.
    The rest of the site keeps working for a blocked address.

IP access rules (account-wide)
:   None.
    Ten {guilabel}`Allow` rules for hosting companies' addresses, left over from earlier setups and without notes, were deleted on October 29, 2026.
    An {guilabel}`Allow` rule exempts an address from every check above, so add one only for a known need, with a note saying what it's for.
    To block an address, add a rule with the action {guilabel}`Block`, also with a note.

AI crawlers (zone-wide)
:   Allowed.
    {guilabel}`AI Labyrinth` is off, and no AI bot policy blocks them.

{guilabel}`Under Attack Mode` (zone-wide)
:   Off.
    It's an emergency switch on the zone's {guilabel}`Overview` page that makes every visitor pass a browser check first.
    See {doc}`../how-to-guides/fix-an-unresponsive-site`.

Blocked and challenged requests are listed under {guilabel}`Security` → {guilabel}`Events`.

## Page cache

A cache rule, `Cache pages on new.imsss.net for visitors`, under {guilabel}`Caching` → {guilabel}`Cache Rules`, keeps copies of pages at Cloudflare for 5 minutes, for visitors who aren't logged in:

```text
(http.host eq "new.imsss.net"
  and not http.cookie contains "auth_token"
  and not starts_with(http.request.uri.path, "/++api++")
  and not starts_with(http.request.uri.path, "/static/"))
```

The rule sets:

- {guilabel}`Cache eligibility` to {guilabel}`Eligible for cache`
- {guilabel}`Edge TTL` to {guilabel}`Ignore cache-control header and use this TTL`, with 5 minutes
- {guilabel}`Browser TTL` to {guilabel}`Respect origin TTL`, so that browsers don't keep pages for the zone's default of 4 hours

Volto keeps a logged-in user's session in the `auth_token` cookie, so editors always get live pages.
The API, under `/++api++`, isn't cached, so navigating within the site and editing work as before.
`/static/` holds the site's JavaScript and CSS, which Cloudflare caches through their own one-year headers.
The site's only language is English, and Volto uses it for every visitor, whatever their browser's language, so one cached copy suits everyone.

After an edit, visitors who aren't logged in see the change within 5 minutes.
To show it at once, go to {guilabel}`Caching` → {guilabel}`Configuration` → {guilabel}`Purge Cache` → {guilabel}`Custom Purge`, and enter the page's address, for example `https://new.imsss.net/congress`.
{guilabel}`Purge Everything` empties the whole zone's cache, including `imsss.net`'s.

The response header `cf-cache-status` shows `HIT` for a page served from the cache, `MISS` for one fetched from the server, and `DYNAMIC` for one that isn't cached.
Each Cloudflare data center keeps its own copy, so the first request through each one is a `MISS`.

## DNSSEC and email

DNSSEC (zone-wide)
:   Turned on October 29, 2026, under {guilabel}`DNS` → {guilabel}`Settings`.
    The domain is registered with Cloudflare, so Cloudflare published the DS record itself.

Email (zone-wide)
:   The domain sends no email, and has no MX record, so nobody receives mail at `@imsss.net` addresses either.
    {guilabel}`Email Security`, with {guilabel}`No email is sent from this domain` chosen, publishes the SPF record `v=spf1 -all` and a DMARC record with `p=reject`, so receiving servers reject mail that claims to come from `imsss.net`.
    An older SPF record, `v=spf1 a mx -all`, was deleted, because a domain may have only one.
    Plone sends no mail either: it has no sender address, and no mail server is installed on the server.
    Before Plone, or anything else, can send mail as `imsss.net`, set up a mail service and change the SPF and DMARC records to allow it.

## On the server

Firewall
:   `ufw` accepts web traffic, on ports 80 and 443, only from Cloudflare's address ranges, so nobody can reach the site without going through Cloudflare.
    A direct connection to the server's address on those ports times out.
    SSH, on port 22, is still open to everyone, with key logins only and fail2ban.
    The firewall and fail2ban see only Cloudflare's addresses for web traffic, so block web visitors in the Cloudflare dashboard instead.

Visitors' real addresses
:   Every web request reaches nginx from one of Cloudflare's addresses.
    `/etc/nginx/conf.d/cloudflare-realip.conf` makes nginx take the visitor's real address from the `CF-Connecting-IP` header that Cloudflare adds, so the access log, and the `X-Real-IP` and `X-Forwarded-For` headers that nginx passes to Plone, show the visitor.
    It trusts that header only from Cloudflare's address ranges, so a client that connects directly can't fake its address.
    The file has one `set_real_ip_from` line for each of Cloudflare's ranges, followed by `real_ip_header CF-Connecting-IP;`.

HTTPS certificate
:   certbot renews the Let's Encrypt certificate as before.
    Let's Encrypt reaches the server through Cloudflare, over port 80.
    Renewal tests passed after each change on October 29, 2026; see "HTTPS certificate" in {doc}`server`.

(cloudflare-address-ranges)=
### Cloudflare's address ranges

The firewall rules and the nginx file both come from `devops/cloudflare-ips.txt`, a copy of Cloudflare's published ranges at <https://www.cloudflare.com/ips-v4> and <https://www.cloudflare.com/ips-v6>.
`devops/scripts/apply-cloudflare-ranges.sh` applies the list.
Run it on the server as root, after deploying:

```shell
/home/plone/imsss.net-plone-6.1.3/imsss-2025/devops/scripts/apply-cloudflare-ranges.sh
```

The script rewrites `/etc/nginx/conf.d/cloudflare-realip.conf` and reloads nginx, keeping the old file if nginx rejects the new one.
It adds a firewall rule, with the comment `cloudflare`, for each range, and removes `cloudflare` rules for ranges that are no longer in the list.
It doesn't change any other firewall rule, and running it again when nothing has changed does nothing.

Every month, the `cloudflare-ranges.yml` workflow checks the list against Cloudflare's published ranges; see {doc}`ci`.
If Cloudflare changes them, the workflow fails and GitHub emails the repository's owner.
A missing range would make some visitors see Cloudflare's error 522, so when that happens:

1.  Update `devops/cloudflare-ips.txt` with the ranges that the failed run lists, and push it.
2.  Deploy, so that the server's checkout has the new list.
3.  Run `apply-cloudflare-ranges.sh` on the server as root.
4.  Run the workflow by hand, from the Actions tab or with `gh workflow run cloudflare-ranges.yml`, and check that it passes.

The web ports were closed to everything else on October 29, 2026, by removing the `Nginx Full` rules with `ufw delete allow 'Nginx Full'`.

## Check the setup

These are the checks used on October 29, 2026.
Run them from your own computer unless they say otherwise.

```shell
# Served by Cloudflare: "server: cloudflare" and a cf-ray header
curl -sI https://new.imsss.net/ | grep -iE '^(server|cf-ray)'

# Page cache: the second request is a HIT (the first through each data center is a MISS)
curl -sI https://new.imsss.net/congress | grep -i cf-cache-status

# Scanner rule: 403 from Cloudflare
curl -s -o /dev/null -w '%{http_code}\n' https://new.imsss.net/.env

# HTTP redirects to HTTPS
curl -sI http://new.imsss.net/ | grep -iE '^(HTTP|location)'

# TLS 1.3 works (macOS's built-in curl can't test TLS 1.3, so use openssl)
echo | openssl s_client -connect new.imsss.net:443 -servername new.imsss.net -tls1_3 2>&1 | grep Protocol

# Direct connections to the server's own address time out
curl -m 8 https://SERVER-ADDRESS/
```

On the server, as root:

```shell
ufw status | grep -c cloudflare           # one rule for each line in devops/cloudflare-ips.txt
tail -3 /var/log/nginx/new.imsss.net.access.log    # visitors' addresses, not Cloudflare's
certbot renew --dry-run --no-random-sleep-on-renew
```

To test the login rate limit, send about 8 login attempts in quick succession with a user name that doesn't exist, and check that the last ones get `429`.
The block ends after 10 seconds.

## Turn Cloudflare off for the site

If Cloudflare ever needs to be taken out of the way, for example during a Cloudflare outage:

1.  In the Cloudflare dashboard, change the `A` record for `new` to {guilabel}`DNS only`.
    `new.imsss.net` then resolves to the server's own address.
2.  On the server, as root, open the web ports to everyone again:

    ```shell
    ufw allow 'Nginx Full'
    ```

3.  Wait a few minutes for the DNS change, then check the site.

Nothing else needs changing.
nginx's real-address settings apply only to requests from Cloudflare's addresses, and SSH keeps working through the `imsss-server` alias.
The cache rule, the scanner rule, the rate limit, and Bot Fight Mode stop applying, because requests no longer pass through Cloudflare.
To go back, set the record to {guilabel}`Proxied` again, and run `ufw delete allow 'Nginx Full'`.

## Not set up

Cloudflare Tunnel
:   A small program on the server, `cloudflared`, would connect out to Cloudflare, so the web ports could be closed entirely, and the monthly check of address ranges would no longer be needed.
    With Cloudflare Access, SSH could go through it too.
    It would use about 30–50 MB of memory, and a problem with the tunnel would leave only the Linode console for getting in.

Caching the API
:   Navigating within the site uses the API, which isn't cached.
    Caching it for visitors who aren't logged in would take more load off the server, but would need the same care as the page cache.

## History

All on October 29, 2026:

1.  After the move to the 1 GB plan, a bot's connections filled the server's connection-tracking table, and the site and SSH stopped responding.
    The table was enlarged, nginx was set to close unused connections sooner, and the bot's address was blocked in the firewall.
2.  The `new` record was switched to {guilabel}`Proxied`, and a Configuration Rule set {guilabel}`Full (strict)` SSL for `new.imsss.net`.
3.  SSH moved to the `imsss-server` alias, and nginx was set up to read visitors' real addresses.
4.  The firewall was limited to Cloudflare's address ranges, with the monthly check, and the block on the bot's address was removed.
5.  {guilabel}`Always Use HTTPS`, TLS 1.2 as the minimum, DNSSEC, the email records, and Bot Fight Mode were turned on, and the old IP {guilabel}`Allow` rules were deleted.
6.  The scanner rule, the login rate limit, and the page cache were added.
