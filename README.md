# mcl-tenders

<!-- Service README template: swap the service name in the badge URLs and the
     package link; everything else is shared. -->

[![CI](https://img.shields.io/github/actions/workflow/status/macula-services/mcl-tenders/lint.yml?branch=main&label=CI)](https://github.com/macula-services/mcl-tenders/actions/workflows/lint.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![ghcr.io](https://img.shields.io/badge/ghcr.io-macula--services%2Fmcl-tenders-blue.svg)](https://github.com/macula-services/mcl-tenders/pkgs/container/mcl-tenders)
[![BEAM](https://img.shields.io/badge/beam-28%2B-A90533?logo=erlang&logoColor=white)](https://www.erlang.org)
[![GitHub Sponsors](https://img.shields.io/badge/GitHub%20Sponsors-support-ea4aaa.svg?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/rgfaber)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-ffdd00.svg?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/rlefever)

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/macula-tenders-full-dark.svg">
    <img src="assets/macula-tenders-full-light.svg" alt="Macula Tenders" width="320">
  </picture>
</p>

<p align="center">
  <strong>Each morning, the new public tenders that fit your company, without handing your profile to anyone outside your realm</strong>
</p>

---

## What is mcl-tenders?

Each realm runs its own mcl-tenders: one release, on a node of the realm. It
fetches the EU's tender notices that fit the realm's own profile, and guides
each one from spotted to bid, won or lost. The company's own people set the
profile, and it never leaves the realm's node.

![mcl-tenders system context](assets/c4-context.svg)

The C4 model (context, containers, components) is in
[architecture/README.md](architecture/README.md). The vision, boundary, design
and threat model are on macula-services/mcl-tenders#1.

## Status

The first slice is built: **the realm's tenders profile**. The release boots,
joins the mesh, opens its own event store and answers `/health` on its Unix
socket, `/run/mcl/health.sock` inside the container. The profile is born the
first time mcl-tenders boots in a realm, and is already there on every boot
after.

| Division | Desks | Dossier or read model |
|----------|-------|-----------------------|
| `guide_tender_lifecycle` (CMD) | `initiate_tender_profile` (at boot), `describe_tender_profile` | the realm's profile, keyed by the realm |
| `project_tenders` (PRJ) | one projection per event | `tenders.sqlite3`: the profile |
| `query_tenders` (QRY) | `get_tender_profile` | reads `tenders.sqlite3` |

Not built yet: the sensor that reads TED (#7), each tender's dossier (#4), and
the admin UI on the LAN where the bid team sets the profile.

## Procedures

Both procedures are CALLs that **require a sealed call**: the node names its KEM
key and macula's link refuses a call in the clear, so the profile crosses a
station only as ciphertext. Both admit **only the tenders role**
(`auth => {callers, role}`): an identity holding a capability the realm minted
for that procedure. A bare realm member, or a node of another realm, is refused
by the link before any handler runs. Each replies with its answer, or
`{"reason": "<text>"}` naming the rule that refused it. Those reason strings are
the wire contract.

| Procedure | Payload | Answer |
|-----------|---------|--------|
| `mcl-tenders/describe_tender_profile` | `{"cpv_codes"?: [...], "countries"?: [...], "keywords"?: [...], "exclusions"?: [...], "description"?}` | `{}`: replaces the whole profile; a field left out is empty |
| `mcl-tenders/get_tender_profile` | `{}` | `{cpv_codes, countries, keywords, exclusions, description, described_by, described_at}` |

`described_by` is the 64-hex node id of the caller that described it last,
`described_at` milliseconds since the epoch. The lists come back sorted, without
duplicates.

The Answer column is a contract a test holds to: `mcl_tenders_wire_replies_tests`
calls each responder against a real store and read model, reads its reply
through macula's own CBOR codec, and fails when a reply's keys or a key named
here change.

| Reason | Meaning |
|--------|---------|
| `invalid_cpv_codes` | up to 100 CPV codes, each eight digits (`72000000`) |
| `invalid_countries` | up to 40 countries, each an ISO 3166 alpha-3 code in capitals (`BEL`), as TED names them |
| `invalid_keywords`, `invalid_exclusions` | up to 50 terms each, 1 to 100 bytes: UTF-8, kept in NFC, with no control or invisible format characters (bidi overrides, zero-width characters and the like) |
| `invalid_description` | the same text rule, up to 4000 bytes, line breaks allowed |
| `not_initiated` | the profile is not there yet; the release initiates it at boot |
| `not_found` | no profile to read yet |
| `no_caller` | the CALL carried no 32-byte node id |
| `no_realm` | the node has no realm, so it serves no profile |
| `store_unavailable`, `internal_error` | the service's own fault; its log names the fault, never the profile |

Plus `mcl-tenders/info` and `mcl-tenders/get_limits`, which `mcl_om` adds to every
service.

**The profile never reaches a log.** It says what the realm bids for, so it
lives on the node's disk, in the event store and the read model, and nowhere
else: not in a log line, not in a crash report, not in the aggregate's state.
One exception stays inside the node: an event a projection cannot apply is
dead-lettered, and evoq keeps that letter, profile and all, in the node's
memory until it restarts; it is never logged.
`mcl_tenders_no_profile_in_logs_tests` runs every profile path with canary terms
under a logger that keeps every event, including a stuck and a crashing store,
and fails if a canary turns up.

Known limits. The realm is the trust boundary: anyone the realm grants the
tenders role reads and replaces the whole profile. Events are permanent: a
description, once given, stays in the event store after it is replaced, even
though no query shows it. Back the store up as you would the bid strategy it
holds.

## Running it

    rebar3 compile
    rebar3 eunit
    rebar3 lint

    scripts/health.sh                      # against a running node

The image builds in one pinned image and runs on another, a pair named by
digest in the two `FROM` lines of the `Containerfile`. The builder carries the
whole toolchain (OTP 28 with ML-DSA, rebar3, Rust for macula's NIFs), so
building needs nothing on the host but podman or docker. CI lints and tests in
that same builder image, and the service's tests fail if the two drift apart.
It also scans every dependency the release resolves for a published advisory,
and no image is built while that scan is red. There is no baseline: an advisory
is fixed, or waived in `.github/advisories-waivers.txt` by a dated, named,
expiring row.

    podman build -t mcl-tenders -f Containerfile .

## Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `MCL_REALM` | required | 64-hex realm tag, the `sha256` of the realm's name. The profile belongs to this realm. |
| `MCL_REALM_KEY` | required | The realm's public signing key, hex encoded: the trust anchor. Public material, not a secret. |
| `MACULA_STATION_SEEDS` | required | Station hosts to dial, `host[:port]`, comma-separated. |
| `MACULA_STATION_NODE_IDS` | required | The matching 64-hex station node ids, index-paired with the seeds. mcl_om refuses to boot a pool with an unpinned seed. |
| `MCL_DATA_DIR` | `/data` in the image | Where the event store and `tenders.sqlite3` live. The image declares `/data` a volume; mount it on a bulk drive. |

The node takes no Erlang node connections: no epmd, no distribution
listener, no cookie (`config/vm.args.src`), so `remote_console` and `eval` do
not work against it, by design. Ask it how it is with `scripts/health.sh`, which
reads `/health` on its Unix socket. It writes no crash dump either.

`deploy/docker-compose.yml` runs it, and carries what the service knows about
itself. If you deploy through something else, let that carry placement: which
host, which station, which realm, which secret store.

## Deployment

The image has two channels, and only a signed release moves `:latest`. A push
to `main` publishes `:main` and `:<sha>`; a `v*` tag publishes its own version,
and once that digest is signed and attested, `:latest` is pointed at the same
digest (`scripts/promote_latest.sh`). A push that changes only documentation
builds no image (`scripts/is_image_push.sh`).

The service's org, the `<org>` its procedure names carry, is this repository's
name, fixed in `config/sys.config.src`. The realm's grant names it; without an
org mcl_om refuses to boot.

## Licence

Apache-2.0.
