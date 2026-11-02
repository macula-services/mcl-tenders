#!/usr/bin/env bash
# set-tenders-group-env_test.sh -- holds set-tenders-group-env.sh to what the
# README promises: the token lands in the env file 0600 and is never printed,
# other lines survive, a rerun replaces, and a malformed input writes nothing.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SET="$HERE/set-tenders-group-env.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ENV_FILE="$WORK/secrets/mcl-tenders.env"
KEY="$(printf 'a%.0s' $(seq 64))"
TOKEN="aGVhZGVy.Y2xhaW1zY2FuYXJ5.c2lnbmF0dXJl"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Mix's own output around the two lines is skipped; the token is not printed.
OUT="$(printf 'Compiling 2 files (.ex)\nMCL_TENDERS_GROUP_UCAN=%s\nMCL_GROUP_ORG_KEY_ID=%s\n' "$TOKEN" "$KEY" \
       | "$SET" "$ENV_FILE" 2>&1)"
case "$OUT" in *"$TOKEN"*) fail "the token was printed" ;; esac
[ "$(stat -c %a "$ENV_FILE")" = 600 ] || fail "the env file is not 0600"
grep -qx "MCL_TENDERS_GROUP_UCAN=$TOKEN" "$ENV_FILE" || fail "the token is not in the env file"
grep -qx "MCL_GROUP_ORG_KEY_ID=$KEY" "$ENV_FILE" || fail "the org key id is not in the env file"

# A rerun replaces both and keeps every other line.
echo "OTHER=kept" >> "$ENV_FILE"
NEW="bmV3.bmV3.bmV3"
printf 'MCL_GROUP_ORG_KEY_ID=%s\nMCL_TENDERS_GROUP_UCAN=%s\n' "$KEY" "$NEW" | "$SET" "$ENV_FILE" > /dev/null
[ "$(grep -c '^MCL_TENDERS_GROUP_UCAN=' "$ENV_FILE")" = 1 ] || fail "the token is not replaced"
grep -qx "MCL_TENDERS_GROUP_UCAN=$NEW" "$ENV_FILE" || fail "the new token is not in the env file"
grep -qx "OTHER=kept" "$ENV_FILE" || fail "another line was lost"

# Malformed input: refused, and the file is as it was.
BEFORE="$(cat "$ENV_FILE")"
for INPUT in "MCL_GROUP_ORG_KEY_ID=$KEY" \
             "MCL_TENDERS_GROUP_UCAN=$TOKEN" \
             "$(printf 'MCL_GROUP_ORG_KEY_ID=short\nMCL_TENDERS_GROUP_UCAN=%s' "$TOKEN")" \
             "$(printf 'MCL_GROUP_ORG_KEY_ID=%s\nMCL_TENDERS_GROUP_UCAN=a.b.c;rm -rf x' "$KEY")"; do
    if printf '%s\n' "$INPUT" | "$SET" "$ENV_FILE" > /dev/null 2>&1; then fail "accepted: $INPUT"; fi
    [ "$(cat "$ENV_FILE")" = "$BEFORE" ] || fail "a refused input changed the file"
done
[ -z "$(ls "$WORK/secrets" | grep -v '^mcl-tenders.env$')" ] || fail "a temporary file was left behind"

echo "set-tenders-group-env: ok"
