# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The tender sensor (`mcl-tenders-sensor`, macula-services/mcl-tenders#2): sweeps
  TED's Search API v3 for every notice published since its last sweep, in scroll
  mode, and reports each new one as `tender_notice_reported_v1` on
  `<realm>/mcl-tenders/tenders/wire/`. It asks TED for all of it, by date only.
- `parse_ted_notice`: one Search API notice into one map, eForms and the older
  schema alike. Calls, prior information notices, corrections and awards are
  kept; other forms are skipped and counted. No contact field is asked for.
- `mcl_tenders_facts`: the one topic and its closed field list, pinned by a
  test. No URL and no contact data; text bounded and stripped of control
  characters. `report/1` answers `ok` only once the mesh took the fact.
- `reported_window`: the publication numbers already reported, bounded.
- A sweep that could not report every notice keeps its day, so a dark mesh or a
  refused page delays a notice and loses none; a failed sweep backs off, up to
  six hours.
- The `mcl_om` service shell, generated from `rebar3 new mcl_service`: org and
  scope `mcl-tenders-sensor`, no procedure of its own, no store; `start/1`
  refuses a realm name that does not hash to `MCL_REALM`.
- CI: lint, eunit and dialyzer on every push and pull request; dependency
  advisories (`.github/advisories-waivers.txt` waives cowlib's
  EEF-CVE-2026-43966 until 2026-12-01, no fixed release yet); the C4 model
  check. Image: a `v*` tag publishes its version and moves `:latest` only once
  the digest is signed; `main` publishes `:main` and `:<sha>`; a docs-only push
  builds nothing.
- README, `architecture/README.md` and the two C4 diagrams, drawn by
  `architecture/c4_diagrams.py`.
