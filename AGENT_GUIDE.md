# Agent Guide

This document is a concise operator guide for agents that need to install and use this repository on a macOS machine.

Validated first-run flow from a clean public clone:

```sh
git clone https://github.com/SAMYJ1/usque-warp-socks.git
cd usque-warp-socks
bin/warp-masque-socks register-start --license-key YOUR_WARP_PLUS_KEY
bin/warp-masque-socks status
bin/warp-masque-socks trace
bin/warp-masque-socks stop
```

## Goal

Bring up a local SOCKS5 proxy backed by Cloudflare WARP MASQUE through `usque`.

Default proxy endpoint:

```text
127.0.0.1:1080
```

## Prerequisites

Required commands:

- `git`
- `curl`
- `jq`
- `unzip`
- `launchctl`
- `nc`
- `cc`

Expected platform:

- macOS
- user session with a working `launchd` GUI domain

## Install

Clone the repository:

```sh
git clone https://github.com/SAMYJ1/usque-warp-socks.git
cd usque-warp-socks
```

No package manager install step is required. The script downloads `usque` on first use.

## First-Time Setup

### Path A: fresh free WARP account

Use this when there is no existing `config.json` to reuse.

```sh
bin/warp-masque-socks register-start
```

This will:

1. create `local/` state if missing
2. download the `usque` binary if missing
3. register a new free Consumer WARP account
4. render the runtime config
5. install and enable the user LaunchAgent
6. start the background SOCKS5 proxy

### Path A2: fresh WARP+ account with your own key

Use this when you have a WARP+ key from the official `1.1.1.1` app and want end-to-end verification during bootstrap.

```sh
bin/warp-masque-socks register-start --license-key YOUR_WARP_PLUS_KEY
```

You can also provide the key through `USQUE_WARP_PLUS_KEY`.

This path:

1. registers a fresh account
2. binds the account to your WARP+ key
3. re-enrolls the local `usque` config
4. starts the proxy
5. requires `trace` to return `warp=plus`

If binding fails, or `trace` still shows `warp=on`, the command exits non-zero and stops the service.

### Path B: import an existing config

Use this when reusing an existing account or a config that already contains a WARP+ `license`.

```sh
bin/warp-masque-socks import-config /path/to/config.json
bin/warp-masque-socks start
```

## Daily Operations

Start the proxy:

```sh
bin/warp-masque-socks start
```

Stop the proxy:

```sh
bin/warp-masque-socks stop
```

Restart after a config change:

```sh
bin/warp-masque-socks restart
```

Show runtime state:

```sh
bin/warp-masque-socks status
```

Check egress IP and region through the proxy:

```sh
bin/warp-masque-socks trace
```

Tail logs:

```sh
bin/warp-masque-socks logs
```

## Cross-Machine Reuse

Export on the source machine:

```sh
bin/warp-masque-socks export-config /tmp/usque-config.json
```

Import on the destination machine:

```sh
bin/warp-masque-socks import-config /tmp/usque-config.json
bin/warp-masque-socks start
```

Treat exported config files as credentials. They contain secrets.

## WARP+ Model

This repository can bind a WARP+ key directly during registration.

Supported model:

- `register` and `register-start` create a free WARP account
- `register --license-key ...` and `register-start --license-key ...` bind a fresh account to your WARP+ key
- importing a config that already contains the desired `license` is still supported

## Verification Checklist

After setup, run:

```sh
bin/warp-masque-socks status
bin/warp-masque-socks trace
```

Healthy output should include:

- `launchd: loaded`
- `listener: up (127.0.0.1:1080)`
- `warp=on` for free WARP, or `warp=plus` when bootstrapped with a WARP+ key

`trace` should also return an `ip=` line and a `loc=` line.

## Troubleshooting

### Missing config

Symptom:

- script reports `missing config`

Fix:

- use `register-start`, or
- use `register-start --license-key YOUR_WARP_PLUS_KEY`, or
- import a config and run `start`

### Service not loaded

Symptom:

- `status` shows `launchd: unloaded`

Fix:

```sh
bin/warp-masque-socks start
```

### Listener down

Symptom:

- `status` shows `listener: down`

Fix:

```sh
bin/warp-masque-socks logs
bin/warp-masque-socks restart
```

### Egress check fails

Check:

- whether `listener` is up
- whether logs show MASQUE connection failures
- whether `local/runtime-config.json` still contains the expected endpoint override
- whether logs show repeated `proxy health check failed` messages followed by a fresh `SOCKS proxy listening` line

### WARP+ bootstrap fails

Check:

- whether the key came from the official `1.1.1.1` app
- whether the command was run against a freshly registered account
- whether stderr shows bind failure or post-start `trace` verification failure
