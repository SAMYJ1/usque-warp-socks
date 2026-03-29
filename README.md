# usque MASQUE SOCKS5

Background SOCKS5 proxy backed by `usque`, using Cloudflare WARP MASQUE.

For an agent-focused install and operation guide, see `AGENT_GUIDE.md`.

## Overview

This tool wraps `usque` into a reusable local workflow under `.`.

It provides:

- one-command registration and startup for a fresh free WARP account
- one-command registration and startup for a fresh WARP+ account with your own key
- one-command start/stop for a background SOCKS5 proxy
- import/export of an existing `usque` config for cross-machine reuse
- per-user `launchd` management on macOS

Default runtime behavior:

- SOCKS5 bind address: `127.0.0.1:1080`
- background service: `launchd` LaunchAgent
- MASQUE endpoint override: `162.159.198.2:500`

## Layout

- `bin/warp-masque-socks`: control script
- `launchd/local.usque-warp-socks.plist.template`: LaunchAgent template
- `local/`: machine-local state, ignored by git

Important local files:

- `local/config.json`: primary `usque` account config, contains secrets
- `local/runtime-config.json`: rendered runtime config with endpoint override
- `local/log/stdout.log`: proxy stdout log
- `local/log/stderr.log`: proxy stderr log

## Commands

```sh
./bin/warp-masque-socks setup
./bin/warp-masque-socks register
./bin/warp-masque-socks register-start
./bin/warp-masque-socks register --license-key YOUR_WARP_PLUS_KEY
./bin/warp-masque-socks register-start --license-key YOUR_WARP_PLUS_KEY
./bin/warp-masque-socks import-config /path/to/config.json
./bin/warp-masque-socks export-config /path/to/config.json
./bin/warp-masque-socks start
./bin/warp-masque-socks stop
./bin/warp-masque-socks restart
./bin/warp-masque-socks status
./bin/warp-masque-socks trace
./bin/warp-masque-socks logs
```

## First Use

### Option A: create a fresh free WARP account

Use this on a new machine when you do not already have a reusable `config.json`.

```sh
./bin/warp-masque-socks register-start
```

What it does:

1. downloads `usque` if missing
2. registers a new free Consumer WARP account
3. writes `local/config.json`
4. renders `local/runtime-config.json`
5. installs and loads the LaunchAgent
6. starts the background SOCKS5 service

After that, verify:

```sh
./bin/warp-masque-socks status
./bin/warp-masque-socks trace
```

### Option A2: create a fresh WARP+ account with your own key

Use this when you have a WARP+ key from the official `1.1.1.1` app and want a brand-new local account to bind immediately.

```sh
./bin/warp-masque-socks register-start --license-key YOUR_WARP_PLUS_KEY
```

You can also supply the key through `USQUE_WARP_PLUS_KEY`:

```sh
USQUE_WARP_PLUS_KEY=YOUR_WARP_PLUS_KEY ./bin/warp-masque-socks register-start
```

What it does in addition to normal registration:

1. binds the freshly registered account to your WARP+ key
2. re-enrolls the local `usque` config
3. starts the SOCKS5 proxy
4. requires `trace` to report `warp=plus`

If the key bind fails, or startup still reports `warp=on`, the command exits non-zero and stops the service instead of silently downgrading to free WARP.

### Option B: reuse an existing account on a new machine

Use this when you already have a `config.json` exported from another machine.

```sh
./bin/warp-masque-socks import-config /path/to/config.json
./bin/warp-masque-socks start
```

This is still the preferred path if you want the new machine to reuse:

- the same existing WARP account
- a config that already contains a WARP+ `license`

## Daily Use

Start the background proxy:

```sh
./bin/warp-masque-socks start
```

Stop the background proxy:

```sh
./bin/warp-masque-socks stop
```

Restart after changing config:

```sh
./bin/warp-masque-socks restart
```

Show current state:

```sh
./bin/warp-masque-socks status
```

Check current egress IP and region through the SOCKS5 proxy:

```sh
./bin/warp-masque-socks trace
```

Tail logs:

```sh
./bin/warp-masque-socks logs
```

## Cross-Machine Reuse

Export the current config on the old machine:

```sh
./bin/warp-masque-socks export-config /tmp/usque-config.json
```

Import it on the new machine:

```sh
./bin/warp-masque-socks import-config /tmp/usque-config.json
./bin/warp-masque-socks start
```

Notes:

- exported and imported configs are forced to `0600`
- `config.json` contains secrets such as `private_key`, `access_token`, and `license`
- treat exported config files as credentials

## WARP+ Support

This tool can bind a WARP+ key directly during registration.

Current support model:

- `register` and `register-start` create a fresh free WARP account
- `register --license-key ...` and `register-start --license-key ...` bind a fresh account to your WARP+ key
- importing an existing WARP+ `config.json` is still supported

So:

- if you need free WARP, use `register-start`
- if you need WARP+ on a fresh account, use `register-start --license-key ...`
- if you need to reuse an existing WARP+ account, import its config and then `start`

## launchd Behavior

This tool uses a per-user LaunchAgent:

- label: `local.usque-warp-socks`
- plist path: `~/Library/LaunchAgents/local.usque-warp-socks.plist`

Behavior:

- `start` renders the plist, enables the label, and bootstraps it into your user GUI domain
- `stop` boots it out and disables the label
- the LaunchAgent runs a local supervisor that probes proxy egress through the SOCKS endpoint
- repeated probe failures make the supervisor exit so `launchd KeepAlive` can relaunch a fresh process
- because the label is enabled during `start`, the service persists across future logins until you run `stop`

## Status Output

`status` reports:

- config path and runtime config path
- stdout/stderr log paths
- whether `config.json` exists
- whether a non-empty `license` field exists
- whether the LaunchAgent is loaded
- whether `127.0.0.1:1080` is listening

Note:

- `license: present` only means the config has a non-empty `license` field
- it does not prove the current connection is WARP+
- use `trace` and look for `warp=plus` when you need an end-to-end WARP+ check

Typical healthy output includes:

- `config: present`
- `license: present` or `license: absent`
- `launchd: loaded`
- `listener: up (127.0.0.1:1080)`

## Using the SOCKS5 Proxy

Point applications at:

```text
127.0.0.1:1080
```

Example:

```sh
curl --socks5 127.0.0.1:1080 -4 https://1.1.1.1/cdn-cgi/trace
```

## Troubleshooting

### `missing config`

Meaning:

- no local `config.json` exists yet

Fix:

- run `register-start`
- or run `register-start --license-key YOUR_WARP_PLUS_KEY`
- or `import-config /path/to/config.json` and then `start`

### `launchd: unloaded`

Meaning:

- the background service is not running

Fix:

```sh
./bin/warp-masque-socks start
```

### `listener: down`

Meaning:

- the LaunchAgent is not healthy yet, or the proxy process failed

Check:

```sh
./bin/warp-masque-socks logs
./bin/warp-masque-socks restart
```

### `trace` fails

Check:

- whether `status` shows `listener: up`
- whether `logs` show MASQUE connection failures
- whether the local endpoint override is still present in `runtime-config.json`
- whether the logs show repeated `proxy health check failed` messages followed by an automatic restart

### `register-start --license-key` fails

Meaning:

- the WARP+ key bind was rejected, or
- Cloudflare still reported `warp=on` after startup

Check:

- that the key came from the official `1.1.1.1` app
- that the account was freshly registered before binding
- the command stderr for whether failure happened during bind or during final `trace`

## Notes

- Secrets live under `usque/local/` and are not tracked by git
- The runtime config rewrites the MASQUE endpoint to `162.159.198.2:500`
- This workflow is macOS-oriented because service management is built around `launchd`
