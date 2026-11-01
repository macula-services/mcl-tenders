# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

Refs macula-services/mcl-tenders#2, #3 and #4.

- **The morning list** (#4, first step). Each reported contract notice or
  prior information notice that fits the realm's profile gets a dossier
  (`tender_aggregate`, `spot_tender`); corrections (`amend_tender`) and the
  award (`note_tender_award`) fold into it, and the bid team dismisses a tender
  with `dismiss_tender`, which records the caller. The fit is keywords only for
  now: country, CPV hierarchy, exclusions, keywords; similarity to the
  profile's description comes later. Every notice is read again on arrival and
  trusts none of the fact's text. New sealed procedures for the tenders role:
  `get_tenders_page` (best first) and `get_tender_by_id`. At most
  `MCL_TENDERS_DAILY_CAP` (500) tenders are spotted a day; `/health` info shows
  `intake`, `sensor` and `quiet`. The process manager is not yet subscribed to
  the sensor's facts: that waits for mcl_om 1.7.0 (macula-services/mcl-om#48).

- **The sensor joins the release** (`sense_tender_notices`, under
  `mcl_tenders_sup`; the separate sensor app is gone). Each sweep reads the
  realm's profile in process and asks TED only for its CPV codes and countries,
  never a keyword, an exclusion or the description. It stays idle while the
  realm has no profile with a code and a country, or while the node cannot seal.
  The newest day is read once more by the next sweep, so a release day costs
  two TED reads instead of one per sweep.
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
