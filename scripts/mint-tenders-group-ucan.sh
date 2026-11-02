#!/usr/bin/env bash
# mint-tenders-group-ucan.sh -- mints one mcl-tenders node's grant to pull the
# realm's tenders group key (interim, macula-services/mcl-om#48).
#
# This exists so the realm's own mcl-tenders node can seal and open the
# sensor's facts, and the morning list fills.
#
# Run ON THE REALM BOX, as a user that may run docker there. The realm runs
# there as a release in a container, so the minting runs inside the realm's own
# node, through the release's rpc (macula-realm's own operator scripts do the
# same). Feed it from a checkout of this repository and pipe it straight into
# the node's box (README, "Asking for today's tenders", step 5):
#
#   ssh <realm box> 'bash -s -- <node_id_hex>' < scripts/mint-tenders-group-ucan.sh \
#       | ssh <node box> './set-tenders-group-env.sh'
#
#   node_id_hex  the 64-hex node id of the mcl-tenders node being admitted.
#                Public: the realm's Members page shows it.
#   CONTAINER    (env) the realm's container, default macula-realm
#
# It WRITES NOTHING ON THE REALM. It reads the realm's mcl-tenders org key file
# itself (the realm makes it when it issues mcl-tenders' provider grant) and
# refuses when that file is missing or does not load. It never asks the
# realm's OrgKeys for the key: that call makes and saves a new key whenever the
# file is missing OR fails to load, which would silently replace the realm's
# org key and leave every grant under it verifying nowhere.
#
# The grant names the realm the box serves, is the org key's `group_keys'
# capability on mri:proc:<realm>/mcl-tenders/group_keys_v1, for that node
# only, and is valid 30 days. Before it expires, mint again; an expired grant
# idles the sensor and /health keeps answering, it never takes the service down.
#
# STDOUT carries exactly two lines, for set-tenders-group-env.sh on the node's
# box, and only when both were minted:
#   MCL_GROUP_ORG_KEY_ID=<hex>      the org key's id, public
#   MCL_TENDERS_GROUP_UCAN=<token>  A SECRET: pipe it, never paste it into a
#                                   chat, an issue or git
# The token exists only inside the realm's node and on this pipe: it is in no
# argument list and no file here. A refusal goes to stderr, without a token.
set -euo pipefail

NODE_ID="${1:?usage: mint-tenders-group-ucan.sh <node_id_hex>}"
CONTAINER="${CONTAINER:-macula-realm}"

# Checked before it goes into the program below: 64 hex characters can carry
# nothing but a node id.
[[ "$NODE_ID" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "node id must be 64 hex characters" >&2; exit 2; }

read -r -d '' PROGRAM <<ELIXIR || true
org = "mcl-tenders"
node_id = Base.decode16!("${NODE_ID}", case: :mixed)
key_file = Path.join(Application.fetch_env!(:macula_realm, :org_keys_path), org <> ".pq.bin")
refuse = fn why -> IO.puts("REFUSED: " <> why) end
mint = fn org_key ->
  realm = MaculaRealm.Mesh.realm_name()
  exp = :erlang.system_time(:second) + 86_400 * 30
  caps = [%{with: "mri:proc:#{realm}/#{org}/group_keys_v1", can: "group_keys"}]
  token = :macula_ucan.create(org_key, node_id, caps, %{exp: exp})
  IO.puts("MCL_GROUP_ORG_KEY_ID=" <> Base.encode16(:macula_node_keys.key_id(org_key), case: :lower))
  IO.puts("MCL_TENDERS_GROUP_UCAN=#{token}")
end
cond do
  not File.exists?(key_file) ->
    refuse.("this realm holds no mcl-tenders org key yet; it makes one when it issues mcl-tenders' provider grant (README, step 1)")
  true ->
    case :macula_node_keys.load(key_file, :org, MaculaRealm.Identity.profile()) do
      {:ok, org_key} -> mint.(org_key)
      {:error, reason} -> refuse.("the realm's mcl-tenders org key does not load (#{inspect(reason)}); left as it is, nothing minted")
    end
end
ELIXIR

OUT="$(docker exec "$CONTAINER" ./bin/macula_realm rpc "$PROGRAM")" || {
    echo "the realm's rpc failed (is $CONTAINER running here?)" >&2; exit 1; }

KEY_LINE="$(printf '%s\n' "$OUT" | grep -E '^MCL_GROUP_ORG_KEY_ID=[0-9a-f]{64}$' || true)"
TOKEN_LINE="$(printf '%s\n' "$OUT" | grep -E '^MCL_TENDERS_GROUP_UCAN=' || true)"
if [ -z "$KEY_LINE" ] || [ -z "$TOKEN_LINE" ]; then
    printf '%s\n' "$OUT" | grep -v -E '^MCL_TENDERS_GROUP_UCAN=' >&2 || true
    echo "nothing minted" >&2
    exit 1
fi
printf '%s\n%s\n' "$KEY_LINE" "$TOKEN_LINE"
