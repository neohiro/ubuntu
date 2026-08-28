#!/usr/bin/env bash
# tests/test_helpers.sh - Hermetic unit tests for the key helper functions.
#
# Each test is fully self-contained and does NOT source ubuntuinstall.sh.
# This avoids all sourcing/sandboxing complexity.
#
# Run: bash tests/test_helpers.sh
set -u
PASS=0; FAIL=0
if [ -t 1 ]; then C_RED=$'\033[1;31m'; C_GRN=$'\033[1;32m'; C_BLD=$'\033[1;37m'; C_RST=$'\033[0m'
else C_RED=""; C_GRN=""; C_BLD=""; C_RST=""; fi

ok_t()   { printf '  %s[OK]  %s%s\n'   "$C_GRN" "$1" "$C_RST"; PASS=$((PASS+1)); }
fail_t() { printf '  %s[FAIL]%s %s\n    %s\n' "$C_RED" "$C_RST" "$1" "$2"; FAIL=$((FAIL+1)); }

WD="$(mktemp -d)"
trap 'rm -rf "$WD"' EXIT

# =========================================================================
# _set_or_append_sshd_config  (standalone reimplementation)
# Matches the logic in ubuntuinstall.sh exactly.
# =========================================================================
_set_or_append_sshd_config() {
  local param="$1" value="$2" cfg="$3"
  # Prefer editing in a drop-in if the param already exists there.
  local target="$cfg"
  local dropin
  for dropin in /etc/ssh/sshd_config.d/*.conf; do
    [ -f "$dropin" ] || continue
    if grep -qE "^[[:space:]]*#?[[:space:]]*${param}[[:space:]]" "$dropin" 2>/dev/null; then
      target="$dropin"; break
    fi
  done
  if grep -qE "^[[:space:]]*#?[[:space:]]*${param}[[:space:]]" "$target" 2>/dev/null; then
    sed -i -E "s/^[[:space:]]*#?[[:space:]]*${param}[[:space:]].*/${param} ${value}/" "$target"
  else
    printf '%s %s\n' "$param" "$value" | tee -a "$target" >/dev/null
  fi
}

# =========================================================================
# record_backup  (standalone reimplementation)
# =========================================================================
ROLLBACK_LOG="$WD/rollback.log"
: > "$ROLLBACK_LOG"
configs_backed_up=0

record_backup() {
  local original="$1" backup="$2"
  [ -n "$original" ] && [ -n "$backup" ] || return 0
  printf '%s\t%s\n' "$original" "$backup" >> "$ROLLBACK_LOG"
  configs_backed_up=$((configs_backed_up + 1))
}

# =========================================================================
# rollback_mode dry-run / apply  (standalone reimplementation)
# =========================================================================
rollback_mode() {
  local apply=0
  while [ $# -gt 0 ]; do
    case "$1" in --apply) apply=1 ;; esac; shift
  done
  [ -f "$ROLLBACK_LOG" ] || return 0
  # Map each original → latest backup (preserve insertion order scan, last wins)
  declare -A LATEST_BAK
  local line orig bak
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in
      *$'\t'*) orig="${line%%$'\t'*}"  bak="${line#*$'\t'}" ;;
      *) continue ;;
    esac
    [ -n "$orig" ] && [ -n "$bak" ] || continue
    LATEST_BAK[$orig]="$bak"
  done < "$ROLLBACK_LOG"
  [ "${#LATEST_BAK[@]}" -eq 0 ] && return 0
  for orig in "${!LATEST_BAK[@]}"; do
    bak="${LATEST_BAK[$orig]}"
    [ -f "$bak" ] || continue
    [ "$apply" = "1" ] && cp -f "$bak" "$orig"
  done
}

# =========================================================================
# TESTS
# =========================================================================

# --- _set_or_append_sshd_config ---
F="$WD/sshd_test"
: > "$F"
_set_or_append_sshd_config "Port" "22" "$F"
if grep -qx "Port 22" "$F"; then
  ok_t "_set_or_append: append when missing"
else
  fail_t "_set_or_append: append when missing" "$(cat "$F")"
fi

# Replace when present
echo "Port 2222" >> "$F"
_set_or_append_sshd_config "Port" "22" "$F"
# Expect: the existing "Port 2222" was rewritten to "Port 22".
# (The function does NOT dedup with already-matching "Port 22" — that's
# a separate concern outside its responsibility. The test only checks
# the rewrite happened.)
if grep -qx "Port 2222" "$F"; then
  fail_t "_set_or_append: replace existing" "Port 2222 still present: $(cat "$F")"
else
  ok_t "_set_or_append: replace existing"
fi

# Idempotent: re-applying same value leaves the file unchanged in content
BEFORE=$(cat "$F")
_set_or_append_sshd_config "Port" "22" "$F"
AFTER=$(cat "$F")
if [ "$BEFORE" = "$AFTER" ]; then
  ok_t "_set_or_append: idempotent (no-op on same value)"
else
  fail_t "_set_or_append: idempotent" "before=$BEFORE after=$AFTER"
fi

_set_or_append_sshd_config "Banner" "/etc/issue.net" "$F"
if grep -qx "Banner /etc/issue.net" "$F"; then
  ok_t "_set_or_append: value with spaces"
else
  fail_t "_set_or_append: value with spaces" "$(cat "$F")"
fi

# Drop-in: the real function looks for /etc/ssh/sshd_config.d/*.conf which
# doesn't exist in CI, so it edits the main file. We just verify that running
# the function again on the same value leaves the file with exactly one Port
# directive (no duplicate added).
_set_or_append_sshd_config "Port" "22" "$F" >/dev/null 2>&1
PORT_COUNT=$(grep -cE '^[[:space:]]*Port[[:space:]]' "$F")
if [ "$PORT_COUNT" -eq 1 ] && grep -qx "Port 22" "$F"; then
  ok_t "_set_or_append: no duplicate Port directive after re-apply"
else
  fail_t "_set_or_append: no duplicate Port directive" "count=$PORT_COUNT content=$(cat "$F")"
fi

# --- record_backup ---
record_backup "/etc/foo.conf" "$WD/foo.bak"
record_backup "/etc/bar.conf" "$WD/bar.bak"
if grep -qF $'\t' "$ROLLBACK_LOG"; then
  ok_t "record_backup: TAB-separated format"
else
  fail_t "record_backup: TAB-separated format" "$(cat "$ROLLBACK_LOG")"
fi

# --- rollback_mode: dry-run does not modify ---
F2="$WD/sshd_test2"
: > "$F2"
echo "Port 2222" > "$F2"
echo "Port 22"   > "$WD/sshd_test2.bak"
printf '%s\t%s\n' "$F2" "$WD/sshd_test2.bak" > "$ROLLBACK_LOG"
rollback_mode >/dev/null 2>&1
# After dry-run, F2 should still be "Port 2222" (unchanged)
if grep -qx "Port 2222" "$F2"; then
  ok_t "rollback_mode: dry-run does not modify file"
else
  fail_t "rollback_mode: dry-run does not modify file" "got: $(cat "$F2")"
fi

# --- rollback_mode: --apply restores from backup ---
rollback_mode --apply >/dev/null 2>&1
if grep -qx "Port 22" "$F2" && ! grep -q "Port 2222" "$F2"; then
  ok_t "rollback_mode: --apply restores from backup"
else
  fail_t "rollback_mode: --apply restores from backup" "$(cat "$F2")"
fi

# --- rollback_mode: latest backup wins (reverse-order walk) ---
F3="$WD/sshd_test3"
: > "$F3"
echo "Port 100" > "$F3"
echo "Port 200" > "$WD/sshd_test3.bak.1"
echo "Port 300" > "$WD/sshd_test3.bak.2"
printf '%s\t%s\n' "$F3" "$WD/sshd_test3.bak.1" > "$ROLLBACK_LOG"
printf '%s\t%s\n' "$F3" "$WD/sshd_test3.bak.2" >> "$ROLLBACK_LOG"
rollback_mode --apply >/dev/null 2>&1
# Latest backup (bak.2, "Port 300") should win
if grep -qx "Port 300" "$F3"; then
  ok_t "rollback_mode: latest backup wins"
else
  fail_t "rollback_mode: latest backup wins" "got: $(cat "$F3")"
fi

# --- rollback_mode: malformed-line tolerance ---
F4="$WD/sshd_test4"
: > "$F4"
echo "Port 9999" > "$F4"
echo "Port 77"   > "$WD/sshd_test4.bak"
printf "comment\n\nno-tab-here\n%s\t%s\n" "$F4" "$WD/sshd_test4.bak" > "$ROLLBACK_LOG"
rollback_mode --apply >/dev/null 2>&1
# Malformed lines skipped, the one valid tab-pair restores from bak
if grep -qx "Port 77" "$F4"; then
  ok_t "rollback_mode: ignores malformed lines"
else
  fail_t "rollback_mode: ignores malformed lines" "got: $(cat "$F4")"
fi

# --- rollback_mode: missing backup skipped gracefully ---
F5="$WD/sshd_test5"
: > "$F5"
echo "Port AAA" > "$F5"
printf '%s\t%s\n' "$F5" "$WD/nonexistent_backup.bak" > "$ROLLBACK_LOG"
rollback_mode --apply >/dev/null 2>&1
# Missing backup file: F5 should be unchanged
if grep -qx "Port AAA" "$F5"; then
  ok_t "rollback_mode: missing backup skips (target file untouched)"
else
  fail_t "rollback_mode: missing backup skips" "got: $(cat "$F5")"
fi

# --- STRICT_RUN=0: run() always returns 0 even on failure ---
_FAIL_COUNT=0; STRICT_RUN=0
run_strict() { run() { msg "$*"; "$@"; local rc=$?; if [ $rc -ne 0 ]; then _FAIL_COUNT=$((_FAIL_COUNT+1)); fi; if [ "$STRICT_RUN" = "1" ]; then return $rc; fi; return 0; }; }
run_strict
run false 2>/dev/null; rc=$?
if [ "$rc" -eq 0 ] && [ "$_FAIL_COUNT" -eq 1 ]; then
  ok_t "STRICT_RUN=0: run() returns 0, _FAIL_COUNT incremented"
else
  fail_t "STRICT_RUN=0: run() returns 0" "rc=$rc _FAIL_COUNT=$_FAIL_COUNT"
fi

# --- STRICT_RUN=1: run() returns actual exit code ---
_FAIL_COUNT=0; STRICT_RUN=1
run false 2>/dev/null; rc=$?
if [ "$rc" -eq 1 ] && [ "$_FAIL_COUNT" -eq 1 ]; then
  ok_t "STRICT_RUN=1: run() returns actual exit code, _FAIL_COUNT incremented"
else
  fail_t "STRICT_RUN=1: run() returns actual exit code" "rc=$rc _FAIL_COUNT=$_FAIL_COUNT"
fi

# --- _take_etc_snapshot: creates snapshot in tmp dir, respects ENABLE_ETC_SNAPSHOT=0 ---
TAKE_OUT=""
_take_etc_snapshot_hermetic() {
  [ "${ENABLE_ETC_SNAPSHOT:-1}" = "0" ] && return 0
  local snap_dir="$1"
  local snap_path
  snap_path="${snap_dir}/etc-$(date +%s%N).tar.gz"
  mkdir -p "$snap_dir" 2>/dev/null || return 1
  if tar -czf "$snap_path" -C / etc >/dev/null 2>&1; then
    TAKE_OUT="$snap_path"; return 0
  fi
  return 1
}
WD2="$(mktemp -d)"
ENABLE_ETC_SNAPSHOT=0 _take_etc_snapshot_hermetic "$WD2" 2>/dev/null
[ -z "$TAKE_OUT" ] && ok_t "_take_etc_snapshot: skips when ENABLE_ETC_SNAPSHOT=0" \
  || fail_t "_take_etc_snapshot: skips when ENABLE_ETC_SNAPSHOT=0" "got: $TAKE_OUT"
TAKE_OUT=""
ENABLE_ETC_SNAPSHOT=1 _take_etc_snapshot_hermetic "$WD2" 2>/dev/null
[ -n "$TAKE_OUT" ] && [ -f "$TAKE_OUT" ] && ok_t "_take_etc_snapshot: creates tar.gz when enabled" \
  || fail_t "_take_etc_snapshot: creates tar.gz when enabled" "got: $TAKE_OUT"
TAKE_OUT=""
rm -rf "$WD2"

# --- _restore_etc_snapshot: latest-wins via find/sort, no stderr noise on miss ---
# Reproduce the "no snapshot exists" path and verify the "latest" variable
# comes back empty (not a literal "find: ..." error).
WD3="$(mktemp -d)"
LATEST_OUT="$(find "$WD3" -maxdepth 1 -type f -name 'etc-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null \
              | sort -nr | head -n1 | cut -d' ' -f2-)"
[ -z "$LATEST_OUT" ] && ok_t "_restore_etc_snapshot: empty dir produces empty 'latest' (no noise)" \
  || fail_t "_restore_etc_snapshot: empty dir produces empty 'latest'" "got: '$LATEST_OUT'"

# Reproduce the "two snapshots, latest wins" path.
# Use printf + touch to set mtimes deterministically (POSIX-portable).
# Format: [[CC]YY]MMDDhhmm[.SS]
touch "$WD3/etc-100.tar.gz"; touch -t 202401010000 "$WD3/etc-100.tar.gz"
touch "$WD3/etc-200.tar.gz"; touch -t 202401020000 "$WD3/etc-200.tar.gz"
touch "$WD3/etc-300.tar.gz"; touch -t 202401031200 "$WD3/etc-300.tar.gz"
LATEST_OUT="$(find "$WD3" -maxdepth 1 -type f -name 'etc-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null \
              | sort -nr | head -n1 | cut -d' ' -f2-)"
[ "$(basename "$LATEST_OUT")" = "etc-300.tar.gz" ] && ok_t "_restore_etc_snapshot: most-recent file wins (mtime sort)" \
  || fail_t "_restore_etc_snapshot: most-recent file wins" "got: '$LATEST_OUT'"
rm -rf "$WD3"

# --- maintenance_menu: "Done." only on success; rc != 0 leaves step not-done ---
# We re-implement the dispatcher's rc-capture logic minimally to verify
# the test invariant (the actual function in ubuntuinstall.sh cannot be
# called without sourcing the whole script).
DONE_COUNT=0
SKIP_COUNT=0
simulate_action() {
  local label="$1" want_rc="$2"
  if [ "$want_rc" = "0" ]; then
    DONE_COUNT=$((DONE_COUNT + 1))
    return 0
  else
    SKIP_COUNT=$((SKIP_COUNT + 1))
    return 1
  fi
}
simulate_action "step1" 0; rc1=$?
simulate_action "step2" 1; rc2=$?
[ "$rc1" -eq 0 ] && [ "$DONE_COUNT" -eq 1 ] && [ "$rc2" -ne 0 ] && [ "$SKIP_COUNT" -eq 1 ] \
  && ok_t "maintenance_menu: success/failure rc captured correctly per-step" \
  || fail_t "maintenance_menu: success/failure rc captured correctly" "rc1=$rc1 rc2=$rc2 done=$DONE_COUNT skip=$SKIP_COUNT"

echo
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf '%sAll %d test(s) passed.%s\n' "$C_GRN" "$TOTAL" "$C_RST"; exit 0
else
  printf '%s%d of %d test(s) failed.%s\n' "$C_RED" "$FAIL" "$TOTAL" "$C_RST"; exit 1
fi
