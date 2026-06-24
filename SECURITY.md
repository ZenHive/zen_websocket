# Security Policy

`zen_websocket` is a WebSocket client substrate that powers live data feeds
(including `onchain`). Bugs in frame parsing, TLS handling, or reconnection can
expose connections to injection or corrupt streamed data, so we take security
reports seriously.

## Supported Versions

This library is pre-1.0; only the current release line receives security fixes.

| Version | Supported          |
| ------- | ------------------ |
| 0.4.x   | :white_check_mark: |
| < 0.4   | :x:                |

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Report privately through GitHub's **Security** tab on this repository:
**Security → Advisories → "Report a vulnerability"**
(<https://github.com/ZenHive/zen_websocket/security/advisories/new>).

This opens a private advisory visible only to you and the maintainers.

### In scope

- Frame/message parsing and reassembly of server-controlled payloads
- TLS and connection establishment
- Reconnection, backoff, and connection state handling

### Out of scope

- Vulnerabilities in the remote WebSocket server you connect to
- Application logic built on top of the client
- Vulnerabilities in upstream dependencies — a heads-up is welcome.

### What to expect

- **Acknowledgement** within a few business days.
- A fix or mitigation plan communicated through the private advisory.
- Coordinated disclosure: we'll agree on a disclosure timeline with you before any public release.

Thank you for helping keep the stack safe.
