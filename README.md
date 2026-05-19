# usque MASQUE SOCKS5

Local SOCKS5 proxy backed by [`usque`](https://github.com/Diniboy1123/usque) and Cloudflare WARP MASQUE, packaged as a macOS `launchd` workflow.

For an agent-focused operations guide, see `AGENT_GUIDE.md`.

## Capabilities

- Starts a local SOCKS5 proxy at `127.0.0.1:1080`.
- Registers a fresh free WARP account or a fresh WARP+ account with your own key.
- Imports and exports an existing `usque` account config for reuse across machines.
- Runs as a per-user macOS LaunchAgent with automatic self-healing.
- Verifies egress through `https://1.1.1.1/cdn-cgi/trace`.

## Quick Start

Create and start a fresh free WARP account:

```sh
./bin/warp-masque-socks register-start
./bin/warp-masque-socks status
./bin/warp-masque-socks trace
```

Create and start a fresh WARP+ account:

```sh
./bin/warp-masque-socks register-start --license-key YOUR_WARP_PLUS_KEY
```

Reuse an existing exported config:

```sh
./bin/warp-masque-socks import-config /path/to/config.json
./bin/warp-masque-socks start
```

Point clients such as Clash, browsers, or curl at:

```text
127.0.0.1:1080
```

## Commands

| Command | Purpose |
| --- | --- |
| `setup` | Download `usque` if missing and prepare local directories. |
| `register [--license-key KEY]` | Create a fresh WARP account and optionally bind a WARP+ key. |
| `register-start [--license-key KEY]` | Register, render runtime config, start the LaunchAgent, and verify startup. |
| `import-config <config.json>` | Install an existing `usque` config into local state. |
| `export-config <path>` | Export the local config with `0600` permissions. |
| `start` | Render the LaunchAgent and start the background proxy. |
| `stop` | Stop and disable the background proxy. |
| `restart` | Replace the running background proxy process. |
| `status` | Show config, LaunchAgent, and listener state. |
| `trace` | Query Cloudflare trace through the SOCKS5 proxy. |
| `logs` | Tail `usque` stdout and stderr logs. |

## Runtime Layout

Tracked files:

- `bin/warp-masque-socks`: control script.
- `launchd/local.usque-warp-socks.plist.template`: LaunchAgent template.
- `tests/smoke.sh`: smoke test coverage for setup, launchd behavior, and supervisor recovery.

Machine-local files under `local/` are ignored by git:

- `local/usque`: downloaded `usque` binary.
- `local/config.json`: primary `usque` account config. Contains secrets.
- `local/runtime-config.json`: rendered runtime config with endpoint overrides.
- `local/log/stdout.log`: proxy stdout log.
- `local/log/stderr.log`: proxy stderr and supervisor log.
- `local/supervise-recovery-until`: transient supervisor recovery marker.

Treat exported configs as credentials. They can contain `private_key`, `access_token`, and `license`.

## WARP+ Model

This wrapper supports two WARP+ workflows:

1. Fresh account: `register --license-key KEY` or `register-start --license-key KEY`.
2. Existing account: import a config that already has the desired license state.

`register-start --license-key` requires end-to-end verification to report `warp=plus`. If binding fails or trace still reports free WARP, the command exits non-zero and stops the service.

## launchd and Self-Healing

The background service is a per-user LaunchAgent:

- label: `local.usque-warp-socks`
- plist: `~/Library/LaunchAgents/local.usque-warp-socks.plist`
- program: `bin/warp-masque-socks supervise`

`start` and `restart` return when launchd is loaded and the local SOCKS listener is back. End-to-end WARP egress is continuously managed by the supervisor rather than by the start command.

The supervisor restarts the child proxy when runtime conditions indicate that client traffic needs a fresh `usque` process:

- repeated end-to-end proxy health-check failures
- default network route changes
- `usque` tunnel-loss events
- a child process that does not stop cleanly after `TERM`

Health probes use total timeouts so a wedged SOCKS data path cannot block the supervisor loop. A short startup grace window lets a fresh MASQUE session settle before health failures can trigger a restart. After a network-route change, tunnel-loss event, manual restart, or health-check restart, the supervisor carries a temporary recovery marker across the next launchd restart. Recovery starts `usque` on a hidden backend port first, verifies that backend through WARP, and only then exposes `127.0.0.1:1080` through a lightweight TCP relay so Clash traffic cannot hit a half-ready WARP tunnel.

## Configuration Knobs

Most users can keep the defaults. Environment variables are useful for tests or machine-specific tuning.

| Variable | Default | Purpose |
| --- | --- | --- |
| `USQUE_BIND` | `127.0.0.1` | SOCKS listen address. |
| `USQUE_PORT` | `1080` | SOCKS listen port. |
| `USQUE_BACKEND_BIND` | `127.0.0.1` | Hidden recovery backend bind address. |
| `USQUE_BACKEND_PORT` | `1081` | Hidden recovery backend SOCKS port. |
| `USQUE_CONNECT_PORT` | `500` | MASQUE connect port passed to `usque`. |
| `USQUE_ENDPOINT_V4` | `162.159.198.2` | IPv4 MASQUE endpoint rendered into runtime config. |
| `USQUE_ENDPOINT_V6` | `2606:4700:103::2` | IPv6 MASQUE endpoint rendered into runtime config. |
| `USQUE_TRACE_URL` | `https://1.1.1.1/cdn-cgi/trace` | URL used for egress verification. |
| `USQUE_TRACE_CONNECT_TIMEOUT` | `2` | Connect timeout for manual `trace` and startup checks. |
| `USQUE_TRACE_MAX_TIME` | `8` | Total timeout for manual `trace` and startup checks. |
| `USQUE_SUPERVISE_HEALTH_INTERVAL` | `30` | Steady-state health-check interval. |
| `USQUE_SUPERVISE_HEALTH_RETRY_INTERVAL` | `1` | Retry interval after a failed supervisor health check. |
| `USQUE_SUPERVISE_HEALTH_TIMEOUT` | `3` | Total timeout for each supervisor health check. |
| `USQUE_SUPERVISE_HEALTH_FAILURES` | `2` | Consecutive health-check failures before restart. |
| `USQUE_SUPERVISE_HEALTH_GRACE` | `10` | Startup settling window before health failures are counted. |
| `USQUE_SUPERVISE_NETWORK_POLL_INTERVAL` | `2` | Default-route polling interval during supervisor sleeps. |
| `USQUE_SUPERVISE_CHILD_STOP_TIMEOUT` | `5` | Time to wait before force-killing a child that ignored `TERM`. |
| `USQUE_SUPERVISE_RECOVERY_GRACE` | `20` | Deadline for hidden backend health before retrying recovery. |
| `PYTHON_BIN` | `python3` | Python interpreter used for the recovery TCP relay. |

## Daily Operations

Start, stop, and restart:

```sh
./bin/warp-masque-socks start
./bin/warp-masque-socks stop
./bin/warp-masque-socks restart
```

Check service state:

```sh
./bin/warp-masque-socks status
```

Healthy service state includes:

- `launchd: loaded`
- `listener: up (127.0.0.1:1080)`

Check end-to-end WARP egress:

```sh
./bin/warp-masque-socks trace
```

Expected trace output includes `ip=`, `loc=`, and `warp=on` or `warp=plus`.

Tail logs:

```sh
./bin/warp-masque-socks logs
```

## Cross-Machine Reuse

Export on the source machine:

```sh
./bin/warp-masque-socks export-config /tmp/usque-config.json
```

Import on the destination machine:

```sh
./bin/warp-masque-socks import-config /tmp/usque-config.json
./bin/warp-masque-socks start
```

Exported and imported configs are forced to `0600`.

## Troubleshooting

### Missing config

Run one of:

```sh
./bin/warp-masque-socks register-start
./bin/warp-masque-socks register-start --license-key YOUR_WARP_PLUS_KEY
./bin/warp-masque-socks import-config /path/to/config.json
```

### Service not loaded

Run:

```sh
./bin/warp-masque-socks start
```

### Listener down

Check logs, then restart:

```sh
./bin/warp-masque-socks logs
./bin/warp-masque-socks restart
```

### Trace fails

Check:

- `status` shows `listener: up`.
- `local/runtime-config.json` still has the expected endpoint override.
- logs show whether MASQUE connect attempts are failing.
- logs show supervisor recovery events such as health-check restarts, default-route restarts, or tunnel-loss restarts.

`start` and `restart` only require launchd plus the local listener to come back. Use `trace` to verify end-to-end WARP egress.

## Notes

- This workflow is macOS-oriented because service management uses `launchd`.
- The runtime config rewrites MASQUE endpoints to the configured endpoint overrides.
- `license: present` in `status` means the config has a non-empty `license` field; use `trace` to confirm whether the live egress is WARP+.
