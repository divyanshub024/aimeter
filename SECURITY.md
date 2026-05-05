# Security Policy

## Reporting a vulnerability

Please do not open a public issue for security-sensitive problems.

Instead, report vulnerabilities privately to the maintainer through the repository hosting platform's private reporting feature or a direct private contact channel if one is available.

Include:

- a short description of the issue
- affected version or commit
- reproduction steps
- potential impact

Do not include live credentials, session cookies, or personal account data in reports.

## Scope notes

AIMeter uses an authenticated local Cursor web session to read Cursor usage pages. It only loads HTTPS Cursor URLs from `cursor.com` or `www.cursor.com`, and its response parser ignores non-Cursor hosts. Bugs in parsing logic, local storage, or packaging may have security implications and should be reported privately when in doubt.

Cursor credentials, cookies, billing details, account identifiers, and exact personal usage values should never be posted in public issues, pull requests, or screenshots.
