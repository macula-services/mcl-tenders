# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

Refs macula-services/mcl-tenders#3.

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
