# SOCKS Auto Restart Design

## Goal

Make the background SOCKS5 proxy self-heal when the process is still listening on `127.0.0.1:1080` but end-to-end proxy traffic is no longer usable.

## Problem

The current LaunchAgent keeps the process alive only when the top-level process exits. If `usque socks` stays running while the MASQUE session or proxy data path is wedged, `launchd` sees a healthy process and does not restart it. Manual `restart` clears the bad state because it forces a fresh `usque` process and a fresh MASQUE session.

## Chosen Approach

Wrap `usque socks` in a lightweight supervisor inside `bin/warp-masque-socks`. The supervisor starts `usque socks`, runs periodic end-to-end health checks through the local SOCKS endpoint, and exits if the proxy fails several checks in a row. `launchd` already has `KeepAlive`, so an exited supervisor will be relaunched automatically.

## Why This Approach

- Keeps the existing `launchd` ownership model.
- Avoids adding a second daemon or timer.
- Detects the failure mode that `status` misses: listener is up but proxy traffic is dead.
- Reuses the existing `trace`-style IP probe instead of introducing a new protocol check.

## Design Details

### Supervisor entrypoint

The LaunchAgent should invoke a dedicated `supervise` command instead of calling `run` directly. `run` remains the raw one-shot `exec usque socks ...` path for manual use and internal composition.

### Health check

The supervisor should probe `https://1.1.1.1/cdn-cgi/trace` through the local SOCKS endpoint with a short connect timeout. This keeps the check independent from proxy-side DNS because it uses an IP URL.

### Failure policy

The supervisor should:

- wait for an initial grace period so startup is not marked unhealthy too early
- count consecutive health-check failures
- reset the failure counter after one successful probe
- log when health checks fail
- terminate the child process and exit non-zero once the failure threshold is reached

### Configuration

Keep the defaults conservative and allow environment overrides for tests:

- probe interval
- connect timeout
- failure threshold
- initial grace period

## Files

- Modify `bin/warp-masque-socks` to add the supervisor loop and reusable health-check helper.
- Modify `launchd/local.usque-warp-socks.plist.template` so launchd starts `supervise`.
- Modify `tests/smoke.sh` to cover supervisor-triggered exit on repeated probe failure.
- Update `README.md` and `AGENT_GUIDE.md` to document self-healing behavior.
