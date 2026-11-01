# mcl-tenders architecture: C4 model

*This exists so a reader can see what the tender sensor talks to, and what it is
made of, without reading it.*

**Status: the sensor is built (macula-services/mcl-tenders#2), nothing is released
yet.** The company node that matches notices against a company's own profile is
macula-services/mcl-tenders#3, and is drawn dashed as later. The design, with its
threat model (T1 to T13 below), is on macula-services/mcl-tenders#1.

## Level 1: system context

![mcl-tenders sensor system context](../assets/c4-context.svg)

| Element | Kind | Role |
| --- | --- | --- |
| mcl-tenders-sensor | In scope | Sweeps every notice TED published since its last sweep and reports each new one as `tender_notice_reported_v1` on `<realm>/mcl-tenders/tenders/wire/`. Serves no procedure, keeps no store. `/health` is a Unix socket |
| Operator | Person | Runs the realm's own sensor (each realm runs one; none is shared between realms) and tunes the sweep. Nothing the operator sets names an interest |
| Company node | External system, later (#3) | In the same realm: subscribes to the one topic, with the realm's own sensors as its sources, and matches each notice against a profile that never leaves the company's own node |
| TED Search API | External system | `api.ted.europa.eu` v3, anonymous, no key. Every EU notice, eForms and the older schema, in one JSON shape |
| macula-realm | Macula infrastructure | The trust anchor and the grant: scope `mcl-tenders-sensor` for 30 days, and the boot claim its operator sees |
| Macula stations, mesh DHT | Macula infrastructure | The pinned dial. The fact goes out through a station, and the DHT holds each advertisement |

What the sensor deliberately does not learn or leak:

- **TED learns nothing about who uses the notices (T3).** The query names a date
  and nothing else; the sensor reads all of TED.
- **No company asks the sensor anything (T3).** Every fact carries what a match
  needs, so a company node never sends "give me notice X", which would tell the
  sensor which notices matched.
- **One topic for every notice (T3).** Country, CPV code and notice type are
  payload fields. A topic per code would show every station on the path which
  codes a company follows.
- **A closed field list (A5, T4).** No contact field is asked for or read, and the
  fact carries no URL: the company node rebuilds the TED link from the publication
  number, so a link in a payload can never be followed.
- **Notice text is data (T6).** Titles, names and descriptions are bounded and
  stripped of control characters and bidirectional overrides, because they reach
  a company's agent. Language keys and country codes pass only as codes.

## Level 2: containers and components

![mcl-tenders sensor components](../assets/c4-components.svg)

| Component | Technology | Responsibility |
| --- | --- | --- |
| `mcl_tenders_sensor_app` | OTP application | `start/2` calls `mcl_om:boot(mcl_tenders_sensor_service)`. The service exports no `store_id/0` or `data_dir/0`, so mcl_om starts no reckon-db and no subscription |
| `mcl_tenders_sensor_service` | the `mcl_om_service` behaviour | The six callbacks. `start/1` refuses a realm whose tag is not the sha256 of `MCL_REALM_NAME`; scope `mcl-tenders-sensor`, 30 days, no actions and no resources. No procedure of its own; `mcl-om` adds `info` and `get_limits`, both open |
| `mcl_tenders_sensor_sup` | supervisor, `one_for_one` | One child, `sense_ted_notices`, which owns the sweep, the reported window and the publishing. A crashed sensor restarts from today |
| `mcl_tenders_facts` | Erlang module | The one topic and its closed field list, every string tagged text and bounded, and `report/1`, which publishes synchronously and answers `ok` only once the mesh took it |
| `sense_ted_notices` | `gen_server`, the sweep | Every `MCL_TENDERS_POLL_MS`: every notice of the week from its `since` day, in TED's scroll mode, 250 a page, half a second apart, cut off at 400 pages. The first failed report ends the sweep; a failed sweep doubles the wait, up to six hours |
| `parse_ted_notice` | Erlang module, pure | One Search API notice into one map. Corrections are notices with a change-notice version; forms that are neither a call, a prior information notice nor an award are skipped and counted. A missing or odd field is empty, never a crash |
| `reported_window` | Erlang module, pure | The publication numbers already reported, bounded (30,000 by default, about eight release days) and rebuilt empty on restart |
| `mcl_om` | library, `~> 1.6` | `boot/1`: loads the identity key, joins the realm, dials the pinned stations, serves `/health` on a Unix socket. Carries `mcl_om_pubsub:publish/3`, which the fact goes through |
| macula SDK | library, `~> 18.0`, wire 1.0 | QUIC transport, pubsub over the stations, and the verified publisher every fact's attribution rests on |
| Host environment | read at boot | `MCL_REALM`, `MCL_REALM_NAME`, `MCL_REALM_KEY`, `MACULA_STATION_SEEDS`, `MACULA_STATION_NODE_IDS`, `MCL_TENDERS_POLL_MS`, `MCL_TENDERS_MAX_SEEN`, `MCL_TENDERS_LOOKBACK_DAYS`, `MCL_SERVICE_NAME`, `MCL_BOX`, `MCL_NODE_NAME`, `MCL_NODE_HOST`, `MCL_COOKIE` |

There is no store. A sweep reads at most a week, so a sensor far behind catches up a
week per sweep and never asks for more than the page ceiling. `since` moves only when
every notice of the sweep was reported: past the week when the week is wholly before
today, otherwise to the newest day read, which the next sweep reads once more. A dark
mesh or a page TED refuses delays a notice and loses none; the notices that did go out
sit in the reported window and are not sent twice.
On a restart the sensor starts from today again, and a day reported twice is harmless,
because company nodes deduplicate by publication number.

**Two orgs, on purpose.** The service's own org is `mcl-tenders-sensor`
(`config/sys.config.src`): its grant and boot claim. The fact topic's org is
`mcl-tenders`, the owner of the schema the sensor and the company node both build
against, fixed in `mcl_tenders_facts`. Who reported a fact is not in the topic or the
payload; macula delivers it as the verified publisher.

## Drawing them

`assets/c4-context.svg` and `assets/c4-components.svg` are generated by
`architecture/c4_diagrams.py` (`python3 architecture/c4_diagrams.py`), from the code
and never from this page. When the code they describe changes, they change in the same
commit.

Two rules for the files themselves, so they render everywhere they are read (GitHub,
an IDE, `rsvg-convert`): self-contained SVG, and literal colours in plain classes
plus a `prefers-color-scheme` dark block, never CSS custom properties, which
`rsvg-convert` renders black.

The check that keeps them here is the `c4-model` job in
`.github/workflows/c4-model.yml`. It is red until both files exist and are shown,
and it stays red if either one goes missing.
