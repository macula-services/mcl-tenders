#!/usr/bin/env bash
# set-tenders-group-env.sh -- writes the tenders group's two settings into the
# node box's secret env file, without ever printing the token.
#
# This exists so the realm's own mcl-tenders node can seal and open the
# sensor's facts, and the morning list fills.
#
# Run ON THE BOX THAT RUNS mcl-tenders, as the user that runs its stacks, with
# mint-tenders-group-ucan.sh's two lines on stdin:
#
#   ... mint-tenders-group-ucan.sh <node id> | scripts/set-tenders-group-env.sh [env_file]
#
#   env_file  default ~/.macula/secrets/mcl-tenders.env, the file the fleet's
#             reconcile passes to compose as --env-file
#
# stdin: MCL_GROUP_ORG_KEY_ID=<64 hex> and MCL_TENDERS_GROUP_UCAN=<token>, in
# either order. Any other line (mix's own output, say) is skipped and never
# printed. At a terminal each line is read without echo.
#
# The file is written 0600, through a temporary file in the same directory, and
# replaces any earlier values of the two variables; every other line is kept.
# What it prints: the file, the org key id, and the token's length. Never the
# token.
set -euo pipefail

ENV_FILE="${1:-$HOME/.macula/secrets/mcl-tenders.env}"
ORG_KEY_ID=""
TOKEN=""

taken() {
    case "$1" in
        MCL_GROUP_ORG_KEY_ID=*) ORG_KEY_ID="${1#MCL_GROUP_ORG_KEY_ID=}" ;;
        MCL_TENDERS_GROUP_UCAN=*) TOKEN="${1#MCL_TENDERS_GROUP_UCAN=}" ;;
        *) ;;
    esac
}

if [ -t 0 ]; then
    for _ in 1 2; do
        echo "Paste one of the two minted lines, then Enter (it is not shown):" >&2
        IFS= read -rs LINE; echo >&2
        taken "$LINE"
    done
else
    while IFS= read -r LINE || [ -n "$LINE" ]; do taken "$LINE"; done
fi

[[ "$ORG_KEY_ID" =~ ^[0-9a-f]{64}$ ]] || { echo "MCL_GROUP_ORG_KEY_ID must be 64 lowercase hex characters" >&2; exit 2; }
# A UCAN is three base64url parts joined by dots: nothing a shell or compose
# would read as anything else.
[[ "$TOKEN" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]] || {
    echo "MCL_TENDERS_GROUP_UCAN is missing, or not three base64url parts joined by dots" >&2; exit 2; }

umask 077
mkdir -p "$(dirname "$ENV_FILE")"
TMP="$(mktemp "$ENV_FILE.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
if [ -f "$ENV_FILE" ]; then
    grep -v -E '^(MCL_TENDERS_GROUP_UCAN|MCL_GROUP_ORG_KEY_ID)=' "$ENV_FILE" > "$TMP" || true
fi
printf 'MCL_GROUP_ORG_KEY_ID=%s\nMCL_TENDERS_GROUP_UCAN=%s\n' "$ORG_KEY_ID" "$TOKEN" >> "$TMP"
chmod 600 "$TMP"
mv "$TMP" "$ENV_FILE"
trap - EXIT

echo "wrote $ENV_FILE (0600): MCL_GROUP_ORG_KEY_ID=$ORG_KEY_ID, MCL_TENDERS_GROUP_UCAN (${#TOKEN} characters)"
