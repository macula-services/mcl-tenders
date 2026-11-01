# mcl-tenders architecture: C4 model

*This exists so a reader can see what mcl-tenders talks to, and what it is made
of, before any of it is built.*

**Status: the model, ahead of the code.** It follows the Boundary as Raf amended
it on macula-services/mcl-tenders#1: each realm runs its own mcl-tenders, the
realm is the trust boundary, the sensor is filtered by the realm's own profile,
and the profile is set in a LAN-facing admin UI. Dashed boxes are later work
packages. The diagrams are drawn by `architecture/c4_diagrams.py`.

## Level 1: system context

![mcl-tenders system context](../assets/c4-context.svg)

| Element | Kind | Role |
| --- | --- | --- |
| mcl-tenders | In scope | One Erlang umbrella, one release, on a node of the company's realm. It fetches the notices that fit the realm's own profile, guides each tender from spotted to bid, won or lost, and keeps the profile and the work on that node |
| Bid team | Person | The company's own people. They set the profile and work each tender in a browser on the company LAN, signed in with their realm identity |
| Realm operator | Person | Deploys mcl-tenders in the realm and grants the tenders role to the people and agents who may use it |
| Company agent | External system, optional | An agent of the same realm holding the tenders role. It reads notice text as data, never as instructions |
| TED Search API | External system | Anonymous, no key. Its query names the realm's CPV codes and countries and a date, and nothing else |
| macula-realm | Macula infrastructure | The trust anchor: membership, the tenders role, and the org delegation the sealed group's key rests on |
| Macula stations, mesh DHT | Macula infrastructure | Carry the sealed fact between the realm's nodes. They see a topic and a size, never a notice |
| TenderNed | External system, later (#6) | A second source of the same notices, for the Netherlands; needs credentials per realm |
| Company mail server | External system, later (#5) | Gets the morning digest only when an owner switches it on, straight from the node |

**The realm is the trust boundary.** Each realm runs its own mcl-tenders; no
sensor is shared between realms. The profile, the matches and the pursuits stay
on the realm's node.

**What leaves the realm, and to whom:**

- **TED** sees the realm's CPV codes and countries in the query, from the
  realm's address. That is the price of a filtered fetch. Keywords, exclusions
  and the description never leave.
- **The stations** see that the realm uses the service: a topic, and the size
  and timing of sealed facts. Never which notices.
- **Nothing else.** No procedure answers anyone outside the tenders role.

## Level 2: containers

![mcl-tenders containers](../assets/c4-containers.svg)

| Container | Technology | Responsibility |
| --- | --- | --- |
| `sense_tender_notices` | OTP app, the sensor | Reads the realm's profile from `query_tenders` in process. Asks TED for the day's notices in the profile's CPV codes and countries, drops the ones an exclusion term hits, and reports each new one as `tender_notice_reported_v1`, sealed under the realm's tenders group. With no profile it fetches nothing |
| `guide_tender_lifecycle` | OTP app, CMD: the process | Two aggregates. `tender_profile`: CPV codes, countries, keywords, exclusions, description. `tender`, keyed by procedure id, the dossier: spotted, pursued or declined, questions asked, bid submitted, won or lost, with corrections and the published award folded in. Hears the fact in its `on_tender_notice_reported_*` process manager, from the realm's sensors only |
| `project_tenders` | OTP app, PRJ | One projection per event, `{event}_to_{table}`, writing the read models |
| `query_tenders` | OTP app, QRY | `get_tender_profile`, `get_tenders_page` (the morning list), `get_tender_by_id`. Serves the admin UI and the sensor in process, and agents through sealed procedures that admit only the tenders role |
| `mcl_tenders_admin` | OTP app, web UI on cowboy | Bound to the LAN, never to a public address. Sign-in with the realm identity, as on the portal; access follows the tenders role. Real controls: a CPV picker, a country list, keywords, exclusions. Shows the morning list and each tender's dossier, and sends the bid team's decisions to `guide_tender_lifecycle` as commands |
| Event store | ReckonDB, embedded | Every event of the process, on the node's disk. It holds the bid strategy |
| Read models | SQLite | The profile, the tenders page and each dossier, shaped for their reads |
| `mcl_om`, macula | libraries | Realm identity, the pinned dial, `/health`, sealed calls, and the sealed group. The node serves the group's key itself (the SDK's distributor), so the fact needs no other service |

**Why one release.** The sensor now reads the profile. In the same release it reads
it in process, so the profile crosses no network, not even inside the realm.

**Why the fact still goes over the mesh.** The sensor and the process are separate
divisions, and a fact on the mesh is how one division tells another. It also lets
a realm run the sensor on a second node. Because the sensor is filtered, the facts
it sends are the realm's matches: so they travel **sealed under the realm's
tenders group**, and the process subscribes with the realm's sensors as its only
sources.

**Why one topic is still needed.** Inside a realm there is one subscriber, so a
topic per code would buy no filtering. It would only show the stations which codes
the realm follows. One topic, sealed, shows them nothing but traffic.

**Who is trusted.** Procedures are sealed and admit `{callers, role}`: only the
identities the realm granted the tenders role, not every realm member. The
process's subscription names `sources => {org, <<"mcl-tenders">>}`: nodes the
realm delegated to the mcl-tenders org, which runs both the sensor and the process. A sensor that is redeployed with a new node id
keeps working, and no other realm member can feed it a notice.

## Decided (Raf, 2026-11-01, on reading this model)

1. **One release**, not two images: the sensor reads the profile in process.
2. **The admin UI signs in with the realm identity**, the same sign-in as the
   portal. What a person may see and do follows the tenders role the realm
   grants, as it does for agents.
3. **WP1 (#2, PR #7) is revised under this model.** Its parser, fact schema,
   reported window and sweep pacing stay; it gains the profile read, the
   narrowed query, the sealed publish, and reads a release day twice rather
   than once per sweep.
