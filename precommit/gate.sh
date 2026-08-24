#!/bin/sh
# mojito pre-commit gate for the homebrew-brew tap.
#
# Tier 0: structural validators (whitespace, junk, conflict markers).
# Tier 1: formula sanity — Ruby syntax check + `brew audit --strict` against
#         the formula name. `brew audit` audits the installed tap copy, so
#         the gate first verifies the clone's Formula/ is byte-identical to
#         the registered tap (/opt/homebrew/Library/Taps/mojito/homebrew-brew);
#         if not (clone drifted or tap missing), the audit step is skipped
#         with a warning instead of auditing stale content.
#
# Env: MOJITO_GATE_FAST=1 skips Tier 1.
#
# Host rules (same as claude/OX agents on this host):
#   - This gate NEVER deletes or modifies anything outside the workspace; it
#     never runs brew untap/uninstall; it only audits and syntax-checks.
set -u

cd "$(git rev-parse --show-toplevel)" || exit 2
FAST="${MOJITO_GATE_FAST:-0}"
failures=0
say() { printf '%s\n' "$*"; }

# ---------------------------------------------------------------- Tier 0 ----
ws_errors=$(git diff --cached --check 2>&1)
if [ -n "$ws_errors" ]; then
    say "Tier 0 FAIL: whitespace errors in staged diff:"
    printf '%s\n' "$ws_errors" | sed 's/^/  | /'
    failures=$((failures + 1))
fi

blocked=$(git diff --cached --name-only \
    | grep -E '(^|/)(build|\.build)/|\.(dylib|o|a|pyc|class|tmp|swp)$|\.DS_Store' || true)
if [ -n "$blocked" ]; then
    say "Tier 0 FAIL: build artifacts / junk must not be committed:"
    printf '%s\n' "$blocked" | sed 's/^/  | /'
    failures=$((failures + 1))
fi

conflicts=$(git grep --cached -n -E '^(<<<<<<< |>>>>>>> )' -- \
    '*.rb' '*.sh' '*.md' 2>/dev/null || true)
if [ -n "$conflicts" ]; then
    say "Tier 0 FAIL: unresolved conflict markers in staged content:"
    printf '%s\n' "$conflicts" | sed 's/^/  | /'
    failures=$((failures + 1))
fi

# ---------------------------------------------------------------- Tier 1 ----
if [ "$FAST" != "1" ]; then
    formulas=$(find Formula -name '*.rb' 2>/dev/null | sort)
    if [ -z "$formulas" ]; then
        say "Tier 1 FAIL: no formulae under Formula/"
        failures=$((failures + 1))
    else
        for f in $formulas; do
            name=$(basename "$f" .rb)
            if command -v ruby >/dev/null 2>&1; then
                if ruby -c "$f" >/dev/null 2>&1; then
                    printf '%-38s PASS\n' "$name ruby -c"
                else
                    printf '%-38s FAIL\n' "$name ruby -c"
                    ruby -c "$f" 2>&1 | tail -n 3 | sed 's/^/    | /'
                    failures=$((failures + 1))
                fi
            else
                say "$name ruby -c                       SKIP (no ruby)"
            fi

            if command -v brew >/dev/null 2>&1; then
                tap_copy="/opt/homebrew/Library/Taps/mojito/homebrew-brew/Formula/$name.rb"
                if [ -f "$tap_copy" ] && cmp -s "$f" "$tap_copy"; then
                    if brew audit --strict "$name" >/tmp/mojito_audit_$$.log 2>&1; then
                        printf '%-38s PASS\n' "$name brew audit"
                    else
                        printf '%-38s FAIL\n' "$name brew audit"
                        tail -n 10 /tmp/mojito_audit_$$.log | sed 's/^/    | /'
                        failures=$((failures + 1))
                    fi
                    rm -f /tmp/mojito_audit_$$.log
                else
                    say "$name brew audit                  SKIP (tap copy differs; push to sync, or brew tap update)"
                fi
            else
                say "$name brew audit                  SKIP (no brew)"
            fi
        done
    fi
fi

# ---------------------------------------------------------------- summary ----
if [ "$failures" -ne 0 ]; then
    say ""
    say "GATE FAILED ($failures issue(s))."
    say "  - Fix the reported issue, or bypass with git commit --no-verify"
    say "    only when the gate itself is broken (file an issue)."
    exit 1
fi
say "gate: all checks passed"
exit 0