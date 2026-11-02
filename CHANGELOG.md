# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-11-02

Refs macula-services/mcl-tenders#4 (4b) and #25 (documents and questions; the
fit by similarity, 4c, is not in this release).

**Rolling back to 0.3.x needs the read model moved aside.** This release moves
`tenders.sqlite3` to user_version 4 (migrations 3 and 4), and 0.3.1 refuses a
file newer than it knows (`schema_newer_than_release`). To roll back, pin the
0.3.1 digest and move `tenders.sqlite3` out of `MCL_DATA_DIR`: on boot the
read model is rebuilt from the event store, which keeps every event. 0.3.1
ignores the pursuit's events, so the pursuit, its documents and its questions
stay in the store, unread, until the node rolls forward again. While rolled
back, 0.3.1 does not see that a tender is pursued, so it accepts
`dismiss_tender` on one; after rolling forward, that dossier reads both
pursued and dismissed.

- **A pursuit's documents and questions.** Two sealed procedures for the
  tenders role on a pursued tender: `attach_tender_document` (name, SHA-256,
  and where the file lies on the node; the file never travels) and
  `record_tender_question`. Each records the node that signed the call (T13).
  `get_tender_pursuit`, role-only whatever the open reads switch says, reads
  them back; `get_tender_by_id` is unchanged. The read model moves forward in
  place (user_version 4: `tender_documents`, `tender_questions`). No document
  name, place or question reaches a log (T8).
- **The pursuit: from bid/no-bid to won or lost.** Four sealed procedures for
  the tenders role on a spotted tender's dossier: `pursue_tender`,
  `decline_tender`, `submit_tender_bid` and `record_tender_outcome`
  (`won` or `lost`). Each step happens once, in order, and records the node
  that signed the call (T13). A pursued tender is no longer dismissed
  (`pursued`) and a dismissed one is not pursued (`dismissed`). Corrections
  and the award keep folding into a pursued dossier. The open reads switch
  never opens the pursuit.
- `get_tender_by_id` answers the pursuit (`pursued_by`, `declined_by`,
  `submitted_by`, `outcome`, `outcome_by` and their times), and each line of
  `get_tenders_page`'s `text` ends with where the pursuit stands. The read
  model moves forward in place (user_version 3).

## [0.3.1] - 2026-11-02

Refs macula-services/mcl-tenders#20.

- **Open reads, a switch, off by default.** `MCL_TENDERS_OPEN_READS=1` opens
  `get_tenders_page` and `get_tender_by_id` to every member of the realm
  (`{callers, members}`), so an agent the realm admitted can ask "any tenders
  today?" with no role. Sealing stays required; a node of another realm is
  still refused. The profile, `dismiss_tender` and `archive_tender_profile`
  stay with the tenders role. `/health` info names it: `reads` is `role` or
  `members`.
- **The node can describe the realm's profile from its config, at boot.**
  `MCL_TENDERS_PROFILE_CPV` and `MCL_TENDERS_PROFILE_COUNTRIES`
  (comma-separated; countries alpha-3) describe it through
  `maybe_describe_tender_profile:dispatch`, the same command, rules and event
  as the CALL, by the node's own id, and only when the profile was never
  described: `describe_tender_profile_v1` gains `unless_described`, and the
  aggregate refuses `already_described` on a described profile, so one the
  realm described over the mesh is kept. A bad value is logged by its reason
  and never stops the boot. With open reads, the demo path needs no role and
  no realm admin.

## [0.3.0] - 2026-11-02

Refs macula-services/mcl-tenders#4, #11, #15 and #18.

- **The group grant mints on the real realm box.** The realm runs there as a
  release in a container, with no checkout and no `mix`, so
  `scripts/mint-tenders-group-ucan.sh` now runs its program inside the
  realm's node through the release's rpc (`CONTAINER`, default
  `macula-realm`), as macula-realm's own operator scripts do. It writes
  nothing on the realm: it loads the `mcl-tenders` org key file itself and
  refuses when the file is missing or does not load, leaving it as it is. It
  never calls the realm's `OrgKeys`, which would make and save a new key in
  either case and replace the realm's org key. The grant names the realm the
  box serves, so the realm name argument is gone. Scripts and README only.
- **The morning list** (#4, first step). Each reported contract notice or
  prior information notice that fits the realm's profile gets a dossier
  (`tender_aggregate`, `spot_tender`); corrections (`amend_tender`) and the
  award (`note_tender_award`) fold into it, and the bid team dismisses a tender
  with `dismiss_tender`, which records the caller. The fit is keywords only for
  now: country, CPV hierarchy, exclusions, keywords; similarity to the
  profile's description comes later. Every notice is read again on arrival and
  trusts none of the fact's text. New sealed procedures for the tenders role:
  `get_tenders_page` (best first) and `get_tender_by_id`. At most
  `MCL_TENDERS_DAILY_CAP` (500) tenders are spotted a day, and only a stored
  spot takes a place, so a re-reported notice never eats the cap; `/health` info shows
  `intake`, `sensor` and `quiet`. The process manager is subscribed to the
  sensor's sealed fact through mcl_om 1.7.0's group admission, from the
  realm's `mcl-tenders` org only, once the tenders group is set up.
- **"Any tenders today?" in one read.** `get_tenders_page` also answers
  `text`: the page as lines a person reads (title, buyer, country, deadline,
  TED notice id), for an agent to answer with as it stands. The README walks
  a realm from nothing to that answer, step by step, with
  `scripts/mint-tenders-group-ucan.sh` (on the realm box) piped into
  `scripts/set-tenders-group-env.sh` (on the node's box), so the group grant
  is never shown and never enters git.
- mcl_om `~> 1.7`.
- **The realm can archive its profile** (`archive_tender_profile`, a sealed
  procedure for the tenders role, like the other two). The realm stops looking
  for public tenders: `get_tender_profile` answers `archived`, the sensor idles
  and asks TED nothing, and the profile is not described or archived again
  (`archived`, `already_archived`). The caller is recorded as `archived_by`.
  A boot after the archive starts as before and leaves the profile archived.
- **The read model moves forward in place.** A box that ran 0.1.0 keeps its
  `tenders.sqlite3`: at boot the store applies each schema step above the
  file's `PRAGMA user_version`, in a transaction, and a second boot changes
  nothing. This release adds `archived_at` and `archived_by`.
- **A failed read model step says which, and changes nothing.** The store
  stops with `{migration_failed, Version, SQLite's error}` and the file keeps
  its rows and its version; a step is all or nothing. It closes its
  connection when it stops.
- **An older release refuses a newer read model.** A file whose
  `user_version` is above the last step this release knows (an older image on
  a newer file) stops the store with `{schema_newer_than_release, File, Known}`
  instead of being served.
- README: archive is granted on its own, like every procedure, so a realm can
  keep it in fewer hands than describe.

## [0.1.1] - 2026-11-02

Refs macula-services/mcl-tenders#12.

- **The release assembles.** v0.1.0's image was never built: `rebar3 as prod
  release` refused `sense_ted_notices`, a name both `sense_tender_notices` and
  `mcl_tenders` declared as theirs. It is the sensor app's alone now. 0.1.1 is
  0.1.0 as it was meant to ship.
- CI assembles the prod release on every change, so a release relx refuses
  fails the pull request, not the tag.

## [0.1.0] - 2026-11-02

Refs macula-services/mcl-tenders#2 and #3.

- **The sensor joins the release** (`sense_tender_notices`, under
  `mcl_tenders_sup`; the separate sensor app is gone). Each sweep reads the
  realm's profile in process and asks TED only for its CPV codes and countries,
  never a keyword, an exclusion or the description. It stays idle while the
  realm has no profile with a code and a country, or while the node cannot seal.
  The newest day is read again while a sweep still finds something new of it,
  also when `since` already sat on that day, so a release day costs two TED
  reads in the steady state instead of one per sweep.
- **Sealed inside the realm.** `tender_notice_reported_v1` travels under the
  realm's tenders group (`<realm name>/mcl-tenders/tenders`), and the release
  runs the group's distributor itself (`group_keys_v1`). Admission is interim:
  a hand-minted grant in `MCL_TENDERS_GROUP_UCAN`, checked against
  `MCL_GROUP_ORG_KEY_ID`, until the realm's tenders role replaces it
  (macula-services/mcl-om#48). Without either the node never publishes, and
  the token is never logged.
- **New configuration:** `MCL_REALM_NAME` (checked against `MCL_REALM` at
  boot), `MCL_TENDERS_POLL_MS`, `MCL_TENDERS_MAX_SEEN`,
  `MCL_TENDERS_LOOKBACK_DAYS`, `MCL_GROUP_ORG_KEY_ID`,
  `MCL_TENDERS_GROUP_UCAN`. `/health` info says `sealing: set` or `unset`.
- **The realm's tenders profile.** The first slice of the release:
  `guide_tender_lifecycle` (the `tender_profile` dossier, initiated at boot and
  described through `describe_tender_profile`), `project_tenders` (its
  projections into `tenders.sqlite3`) and `query_tenders`
  (`get_tender_profile`). Both procedures are sealed and admit only the
  realm's tenders role. The profile reaches no log and no crash report, and a
  test runs every profile path with canary terms to hold that.
- **The release and its CI.** `mcl_tenders` boots the slice under `mcl_om`,
  with its own ReckonDB store under `MCL_DATA_DIR` (`/data`, a volume in the
  image). Lint and tests run on hosted runners in the pinned builder image,
  with the shared dependency-advisories scan; an image is built only when both
  are green, and only a signed release moves `:latest`.
- **README and C4.** The service README template with its own Macula Tenders
  logo, and a Level 3 component diagram of the slice in
  `architecture/README.md`.
- **No Erlang distribution.** The node starts no epmd, listens for no node
  connection and has no cookie; the image writes no crash dump. Nothing can
  attach to the process that holds the profile (macula-services/mcl-om#24).
- **Profile text.** Every list is sorted and deduplicated after NFC, and the
  refused characters are whole Unicode categories (Cc, Cf, Zl, Zp, Cn), the tag
  block and the annotation marks among them.
- **Read model in WAL**, with a lock wait on both connections, so a reader
  never answers `store_unavailable` for a lock the writer holds a moment.
