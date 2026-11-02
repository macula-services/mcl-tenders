#!/usr/bin/env bash
# mint-tenders-group-ucan_test.sh -- holds mint-tenders-group-ucan.sh to what
# the README promises, by running its program for the realm's rpc under Elixir
# against stand-ins for the three realm calls it makes (OrgKeys.key/1 and
# key_id/1, Mesh.realm_name/0 and :macula_ucan.create/4, as in macula-realm
# v0.9.5):
#   - it writes nothing on the realm: with no mcl-tenders org key it refuses,
#     never asks for the key (which would make one), and prints no env line;
#   - with the key it prints exactly the two lines, the grant for that node on
#     the realm's own name, and the token is in no argument list;
#   - a malformed node id never reaches docker;
#   - its output, piped into set-tenders-group-env.sh, lands in the env file.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MINT="$HERE/mint-tenders-group-ucan.sh"
SET="$HERE/set-tenders-group-env.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
NODE="$(printf 'b%.0s' $(seq 64))"
KEY_ID="$(printf 'c%.0s' $(seq 64))"
TOKEN="aGVhZGVy.Y2xhaW1z.c2lnbmF0dXJl"

mkdir -p "$WORK/bin" "$WORK/org-keys"
cat > "$WORK/stand_ins.exs" <<EOF
Application.put_env(:macula_realm, :org_keys_path, "$WORK/org-keys")
defmodule MaculaRealm.Mesh do
  def realm_name, do: "io.example"
end
defmodule MaculaRealm.Identity.OrgKeys do
  def key("mcl-tenders") do
    File.write!("$WORK/key_asked", "1")
    :the_org_key
  end
  def key_id("mcl-tenders"), do: Base.decode16!("$KEY_ID", case: :lower)
end
defmodule :macula_ucan do
  def create(:the_org_key, aud, caps, %{exp: exp}) do
    [%{with: with, can: can}] = caps
    File.write!("$WORK/grant", Enum.join([Base.encode16(aud, case: :lower), with, can, exp - :erlang.system_time(:second)], " "))
    "$TOKEN"
  end
end
EOF
# docker as the realm box has it: exec <container> ./bin/macula_realm rpc <program>.
cat > "$WORK/bin/docker" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$WORK/docker_args"
[ "\$1 \$2 \$3 \$4" = "exec \${CONTAINER_WANTED:-macula-realm} ./bin/macula_realm rpc" ] || { echo "unexpected docker call: \$*" >&2; exit 9; }
printf '%s' "\$5" > "$WORK/program.exs"
elixir -r "$WORK/stand_ins.exs" "$WORK/program.exs"
EOF
chmod +x "$WORK/bin/docker"
export PATH="$WORK/bin:$PATH"

# No org key on the realm: refused, the key never asked for, nothing on stdout.
if "$MINT" "$NODE" > "$WORK/out" 2> "$WORK/err"; then fail "minted without an org key"; fi
[ ! -s "$WORK/out" ] || fail "a refusal printed to stdout"
grep -q '^REFUSED: this realm holds no mcl-tenders org key' "$WORK/err" || fail "the refusal does not say why"
[ ! -e "$WORK/key_asked" ] || fail "the org key was asked for, which makes one"

# With the key: exactly the two lines, the grant is this node's on the realm's name.
touch "$WORK/org-keys/mcl-tenders.pq.bin"
"$MINT" "$NODE" > "$WORK/out" 2> "$WORK/err" || { cat "$WORK/err" >&2; fail "did not mint with the key present"; }
[ "$(cat "$WORK/out")" = "$(printf 'MCL_GROUP_ORG_KEY_ID=%s\nMCL_TENDERS_GROUP_UCAN=%s' "$KEY_ID" "$TOKEN")" ] \
    || fail "stdout is not exactly the two lines: $(grep -v UCAN "$WORK/out")"
grep -qxE "$NODE mri:proc:io.example/mcl-tenders/group_keys_v1 group_keys 259(19[0-9][0-9]|200[0-9])" "$WORK/grant" \
    || fail "the grant is not this node's group_keys on the realm's name for 30 days: $(cat "$WORK/grant")"
grep -q "$TOKEN" "$WORK/docker_args" && fail "the token is in docker's argument list"
grep -q "$TOKEN" "$WORK/err" && fail "the token went to stderr"

# Another container by name.
CONTAINER=realm-two CONTAINER_WANTED=realm-two "$MINT" "$NODE" > /dev/null 2>&1 || fail "CONTAINER is not honoured"

# A malformed node id never reaches docker.
rm -f "$WORK/docker_args"
for BAD in "${NODE:1}" "${NODE:1}g" "${NODE:1}\"" "$NODE$NODE"; do
    if "$MINT" "$BAD" > /dev/null 2>&1; then fail "accepted node id: $BAD"; fi
done
[ ! -e "$WORK/docker_args" ] || fail "a malformed node id reached docker"

# The pipe of README step 5: the env file gets both, the token is not shown.
SHOWN="$("$MINT" "$NODE" | "$SET" "$WORK/secrets/mcl-tenders.env" 2>&1)"
case "$SHOWN" in *"$TOKEN"*) fail "the pipe printed the token" ;; esac
grep -qx "MCL_TENDERS_GROUP_UCAN=$TOKEN" "$WORK/secrets/mcl-tenders.env" || fail "the pipe did not write the token"

echo "mint-tenders-group-ucan: ok"
