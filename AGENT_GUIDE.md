# Agent Guide

Concise operations guide for agents installing, validating, or repairing this repository on macOS.

## Purpose

Bring up a local SOCKS5 proxy backed by Cloudflare WARP MASQUE through `usque`.

Default local endpoint:

```text
127.0.0.1:1080
```

## Prerequisites

Required commands:

- `curl`
- `jq`
- `launchctl`
- `nc`
- `python3`
- `sed`
- `unzip`

Expected platform:

- macOS
- a user session with a working `launchd` GUI domain

## Validated First-Run Flow

From a clean clone:

```sh
git clone https://github.com/SAMYJ1/usque-warp-socks.git
cd usque-warp-socks
bin/warp-masque-socks register-start --license-key YOUR_WARP_PLUS_KEY
bin/warp-masque-socks status
bin/warp-masque-socks trace
```

For free WARP, omit `--license-key`.

## Setup Paths

### Fresh free WARP account

```sh
bin/warp-masque-socks register-start
```

This downloads `usque` if needed, registers an account, renders runtime config, installs the LaunchAgent, and starts the proxy.

### Fresh WARP+ account

```sh
bin/warp-masque-socks register-start --license-key YOUR_WARP_PLUS_KEY
```

The key can also come from `USQUE_WARP_PLUS_KEY`. This path verifies that trace reports `warp=plus`; if not, it stops the service and exits non-zero.

### Existing config

```sh
bin/warp-masque-socks import-config /path/to/config.json
bin/warp-masque-socks start
```

Use this when reusing an existing WARP account or an existing WARP+ config.

## Daily Operations

| Task | Command |
| --- | --- |
| Start proxy | `bin/warp-masque-socks start` |
| Stop proxy | `bin/warp-masque-socks stop` |
| Restart proxy | `bin/warp-masque-socks restart` |
| Show state | `bin/warp-masque-socks status` |
| Verify WARP egress | `bin/warp-masque-socks trace` |
| Tail logs | `bin/warp-masque-socks logs` |
| Export config | `bin/warp-masque-socks export-config /tmp/usque-config.json` |
| Import config | `bin/warp-masque-socks import-config /path/to/config.json` |

## Runtime Model

The service is a per-user LaunchAgent:

- label: `local.usque-warp-socks`
- plist: `~/Library/LaunchAgents/local.usque-warp-socks.plist`
- program: `bin/warp-masque-socks supervise`

Important local files:

- `local/usque`: downloaded proxy binary.
- `local/config.json`: account config; contains secrets.
- `local/runtime-config.json`: rendered runtime config with endpoint override.
- `local/log/stdout.log`: stdout log.
- `local/log/stderr.log`: stderr and supervisor log.

`start` and `restart` return when launchd is loaded and `127.0.0.1:1080` is listening. Run `trace` separately to verify end-to-end WARP egress.

## Self-Healing Behavior

The supervisor owns the `usque socks` child and restarts it when runtime state requires a fresh tunnel:

- repeated proxy egress probe failures
- default route changes after network switches
- `usque` tunnel-loss log events
- child shutdown that hangs after `TERM`

Expected recovery markers in `local/log/stderr.log` include:

- `proxy health check failed`
- `proxy health check failure threshold reached; exiting for launchd restart`
- `default network changed; exiting for launchd restart`
- `usque tunnel connection lost; exiting for launchd restart`
- `recent network recovery detected; starting hidden backend before public SOCKS relay`
- `public SOCKS relay listening on 127.0.0.1:1080 -> 127.0.0.1:1081`

Default supervisor settings favor quick recovery while leaving startup and network-recovery settling windows:

- `USQUE_SUPERVISE_HEALTH_GRACE=10`
- `USQUE_SUPERVISE_HEALTH_TIMEOUT=3`
- `USQUE_SUPERVISE_HEALTH_FAILURES=2`
- `USQUE_SUPERVISE_HEALTH_RETRY_INTERVAL=1`
- `USQUE_SUPERVISE_NETWORK_POLL_INTERVAL=2`
- `USQUE_SUPERVISE_RECOVERY_GRACE=20`
- `USQUE_BACKEND_PORT=1081`

Network-route changes, tunnel-loss events, manual restarts, and health-check restarts write `local/supervise-recovery-until`. The next supervisor process honors that marker by starting `usque` on a hidden backend port, probing that backend through WARP, and only then opening the public SOCKS relay. This keeps Clash from flooding a half-ready WARP tunnel.

## Verification Checklist

After setup or repair:

```sh
bin/warp-masque-socks status
bin/warp-masque-socks trace
```

Healthy status includes:

- `config: present`
- `launchd: loaded`
- `listener: up (127.0.0.1:1080)`

Healthy trace includes:

- `ip=...`
- `loc=...`
- `warp=on` for free WARP or `warp=plus` for WARP+

## Troubleshooting

### Missing config

Run one of:

```sh
bin/warp-masque-socks register-start
bin/warp-masque-socks register-start --license-key YOUR_WARP_PLUS_KEY
bin/warp-masque-socks import-config /path/to/config.json
```

### LaunchAgent not loaded

```sh
bin/warp-masque-socks start
```

### Listener down

```sh
bin/warp-masque-socks logs
bin/warp-masque-socks restart
```

### Egress check fails

Check:

- `status` still shows `listener: up`.
- `local/runtime-config.json` contains the expected endpoint override.
- `local/log/stderr.log` shows MASQUE connection attempts.
- supervisor recovery markers appear when the tunnel or network changes.

If applications such as Clash still use stale SOCKS streams, restart the service and watch for a fresh `SOCKS proxy listening` line:

```sh
bin/warp-masque-socks restart
bin/warp-masque-socks trace
```

### WARP+ bootstrap fails

Check:

- the key came from the official `1.1.1.1` app
- the command was run against a freshly registered account
- stderr indicates whether failure happened during key bind or final trace verification

## Safety Notes

- Treat `local/config.json` and exported configs as credentials.
- Do not commit anything under `local/`.
- `license: present` in `status` only means a non-empty license field exists; use `trace` to verify live WARP+ egress.
