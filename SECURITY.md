# Security Policy

## Supported versions

Security fixes are applied to the latest released version. Users should upgrade to the newest GitHub release and corresponding container images before reporting an issue that may already be fixed.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability.

Use GitHub's private **Report a vulnerability** form on the repository Security tab when it is available. If private reporting is unavailable, contact the maintainer through [neonwatty.com](https://neonwatty.com/about/) and include only enough information to establish a private channel.

Include:

- the affected version or commit;
- deployment details relevant to the finding;
- reproduction steps or a minimal proof of concept;
- the likely impact; and
- any suggested mitigation.

Remove real API keys, private images, database contents, and personal filesystem paths from the report.

## Deployment scope

Meme Search does not currently include authentication. If you intentionally make it available on a network, place it behind an authenticated reverse proxy or VPN and do not expose it directly to the public internet.

The local description provider keeps image processing on the host. When an OpenAI-compatible provider is selected, images chosen for description generation are sent to the configured endpoint.
