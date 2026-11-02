#!/usr/bin/env bash
# mint-tenders-group-ucan.sh -- mints one mcl-tenders node's grant to pull the
# realm's tenders group key (interim, macula-services/mcl-om#48).
#
# This exists so the realm's own mcl-tenders node can seal and open the
# sensor's facts, and the morning list fills.
#
# Run ON THE REALM BOX, in the macula-realm checkout, where the org keys live,
# fed from a checkout of this repository and piped into the node's box (README,
# "Asking for today's tenders", step 5):
#
#   ssh <realm box> 'cd <macula-realm checkout> && bash -s -- <node_id_hex> [realm_name]' \
#       < scripts/mint-tenders-group-ucan.sh | ssh <node box> './set-tenders-group-env.sh'
#
#   node_id_hex  the 64-hex node id of the mcl-tenders node being admitted
#   realm_name   the realm's name, default io.macula
#
# STDOUT carries two lines for set-tenders-group-env.sh on the node's box (mix
# may add its own compile lines, which the writer skips):
#   MCL_GROUP_ORG_KEY_ID=<hex>      the org key's id, public
#   MCL_TENDERS_GROUP_UCAN=<token>  A SECRET: pipe it, never paste it into a
#                                   chat, an issue or git
#
# The grant is the org key's `group_keys' capability on
# mri:proc:<realm_name>/mcl-tenders/group_keys_v1, for that node only, valid
# 30 days. Before it expires, mint again; an expired grant idles the sensor and
# /health keeps answering, it never takes the service down.
set -euo pipefail

NODE_ID="${1:?usage: mint-tenders-group-ucan.sh <node_id_hex> [realm_name]}"
REALM_NAME="${2:-io.macula}"

[[ "$NODE_ID" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "node id must be 64 hex characters" >&2; exit 2; }
[[ "$REALM_NAME" =~ ^[a-z0-9._-]+$ ]] || { echo "realm name must be [a-z0-9._-]" >&2; exit 2; }
[ -f mix.exs ] && grep -q macula_realm mix.exs || { echo "run this in the macula-realm checkout" >&2; exit 2; }

# The same shape as macula-realm's own scripts/mint-group-ucan.sh, for one org.
mix run -e '
[node_hex, realm_name] = System.argv()
org = "mcl-tenders"
org_key = MaculaRealm.Identity.OrgKeys.key(org)
exp = :erlang.system_time(:second) + 86_400 * 30
with = [%{with: "mri:proc:#{realm_name}/#{org}/group_keys_v1", can: "group_keys"}]
token = :macula_ucan.create(org_key, Base.decode16!(node_hex, case: :mixed), with, %{exp: exp})
IO.puts("MCL_GROUP_ORG_KEY_ID=" <> Base.encode16(MaculaRealm.Identity.OrgKeys.key_id(org), case: :lower))
IO.puts("MCL_TENDERS_GROUP_UCAN=#{token}")
' -- "$NODE_ID" "$REALM_NAME"
