# SOCKS Auto Restart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the background SOCKS proxy exit and restart automatically when end-to-end traffic through the proxy becomes unhealthy.

**Architecture:** Add an in-process supervisor command that starts `usque socks`, probes the local SOCKS endpoint with the existing trace-style IP check, and exits after repeated probe failures so `launchd KeepAlive` can relaunch it. Keep `run` as the direct raw execution path and point the LaunchAgent at `supervise`.

**Tech Stack:** POSIX shell, macOS launchd, curl, existing smoke test harness

---

### Task 1: Add the failing supervisor smoke test

**Files:**
- Modify: `tests/smoke.sh`
- Test: `tests/smoke.sh`

- [ ] **Step 1: Write the failing test**

Add a smoke test that starts the new supervisor command in the background with a fake `usque socks` child, flips the fake trace probe into failure mode, and asserts that the supervisor exits non-zero after repeated failed health checks.

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/smoke.sh`
Expected: FAIL because the script does not yet implement the `supervise` command or restart policy.

- [ ] **Step 3: Write minimal implementation**

Implement `supervise`, a reusable proxy probe helper, and the LaunchAgent command change needed for the new behavior.

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/smoke.sh`
Expected: PASS

- [ ] **Step 5: Update docs**

Document that launchd now starts a supervisor and that repeated proxy health-check failures cause self-restart.

