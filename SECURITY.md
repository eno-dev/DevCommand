# Security Policy

## Reporting a vulnerability

If you find a security issue, please **do not open a public issue**. Instead, email
the maintainer at the address on the GitHub profile, or use GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
on this repository. You'll get an acknowledgement within a few days.

## Scope notes

DevCommand runs entirely on your machine. It shells out to local developer tools
(`lsof`, `xcrun`, `npm`/`npx`, `kill`) and has no analytics, no telemetry, and no
third-party dependencies.

The **only** thing that ever leaves your machine is the optional public-IP lookup, and only
when you explicitly ask for it. It is **off by default**, gated behind **Settings → Privacy →
Show public IP**. Out of the box DevCommand makes **zero** outbound requests; nothing is fetched
until you click the "Show" chip in the menu-bar strip (a one-time, on-demand lookup) or turn the
setting on. It is never fetched on a timer. The lookup itself is a small DNS query to OpenDNS
(via `dig`), falling back to a single plain-text "what's my IP" HTTPS service only if DNS is blocked.
