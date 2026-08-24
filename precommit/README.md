# mojito pre-commit gate (homebrew-brew tap)

Every commit runs `precommit/gate.sh`:

- **Tier 0 — validators (always block):** staged whitespace errors, build
  artifacts/junk staged, unresolved conflict markers.
- **Tier 1 — formula sanity:** `ruby -c` syntax check for every formula, and
  `brew audit --strict <name>` when the clone's `Formula/` matches the
  registered tap copy byte-for-byte (audit only ever runs against the
  registered tap, so a drifted clone skips audit with a warning instead of
  auditing stale content).

`MOJITO_GATE_FAST=1` skips Tier 1.

## Install

```sh
precommit/install-hooks.sh        # == git config core.hooksPath .githooks
```

## Host rules (same as claude/OX agents on this host)

- The gate never deletes or modifies anything outside the workspace/ tree.
- The gate NEVER runs `brew untap` / `brew uninstall --force`; retirement of
  anything outside workspace/ uses `mv <path> <path>.superseded` and asks
  first.