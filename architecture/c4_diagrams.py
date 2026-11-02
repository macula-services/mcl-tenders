"""Generate mcl-tenders' C4 context and container diagrams into assets/.

Run:  python3 architecture/c4_diagrams.py

  c4-context.svg     Level 1: what mcl-tenders talks to, and the realm around it
  c4-containers.svg  Level 2: the apps of the umbrella, its stores, and how they talk
  c4-components.svg  Level 3: the profile, the sensor and the morning list as built

The model comes before the code (macula-services/mcl-tenders#1): it is drawn
from the Boundary and Design on that issue, and once the apps exist, from the
code, in the same commit as any change to what it shows. Dashed boxes are later
work packages.

Colours are plain classes with a prefers-color-scheme: dark block, no CSS custom
properties (rsvg-convert renders those black), so the SVGs render the same on
GitHub, in IDE previews and through rsvg-convert. After a change, render each
(rsvg-convert -w 1400 assets/c4-context.svg -o /tmp/c.png) and look at it; keep
architecture/README.md's tables in step.
"""
import os
from xml.sax.saxutils import escape

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

SANS = '"Atkinson Hyperlegible", "Segoe UI", system-ui, -apple-system, Helvetica, Arial, sans-serif'
MONO = '"JetBrains Mono", ui-monospace, Menlo, Consolas, monospace'

# Element kinds, each (light fill, light stroke, dark fill, dark stroke).
KINDS = {
    "b-sys": ("#F5E9CC", "#A56F0A", "#3A2E13", "#E3AA3C"),   # in scope
    "b-per": ("#E3EBF2", "#3B5B7A", "#1D2A36", "#8EB4D8"),   # person
    "b-mac": ("#E6E4EE", "#5E5A78", "#26243A", "#A9A4C8"),   # Macula infrastructure
    "b-ext": ("#ECEFED", "#8A9791", "#1C2421", "#7D8B85"),   # external system
    "b-cmp": ("#FFFFFF", "#8A9791", "#171F1C", "#7D8B85"),   # component or container
}

STYLE = f"""<style>
.t-name {{ font-family: {SANS}; font-size: 15px; font-weight: 700; }}
.t-desc {{ font-family: {SANS}; font-size: 12.5px; }}
.t-rel {{ font-family: {SANS}; font-size: 11.5px; paint-order: stroke; stroke-width: 4px; stroke-linejoin: round; }}
.t-code {{ font-family: {MONO}; font-size: 13px; font-weight: 600; }}
.t-type {{ font-family: {MONO}; font-size: 11.5px; }}
.t-bound {{ font-family: {MONO}; font-size: 12px; font-weight: 600; }}
.t-leg {{ font-family: {SANS}; font-size: 12px; }}
.edge {{ fill: none; stroke-width: 1.25; }}
.edge-later {{ fill: none; stroke-width: 1.25; stroke-dasharray: 5 4; }}
.bg {{ fill: #FFFFFF; }}
""" + "".join(f".{k} {{ fill: {v[0]}; stroke: {v[1]}; stroke-width: {2 if k == 'b-sys' else 1.25}; }}\n" for k, v in KINDS.items()) + """\
.b-later { fill: none; stroke: #8A9791; stroke-width: 1.25; stroke-dasharray: 5 4; }
.bound { fill: none; stroke: #B3BDB8; stroke-width: 1; }
.head { fill: #3B5B7A; }
.t-name, .t-code { fill: #16201D; }
.t-type, .t-bound, .t-leg { fill: #66736E; }
.t-desc { fill: #34413C; }
.t-rel { fill: #66736E; stroke: #FFFFFF; }
.edge, .edge-later { stroke: #8A9791; }
.arrowhead { fill: #8A9791; }
@media (prefers-color-scheme: dark) {
.bg { fill: #171F1C; }
""" + "".join(f".{k} {{ fill: {v[2]}; stroke: {v[3]}; }}\n" for k, v in KINDS.items()) + """\
.b-later { stroke: #7D8B85; }
.bound { stroke: #4A5752; }
.head { fill: #8EB4D8; }
.t-name, .t-code { fill: #E6ECE9; }
.t-type, .t-bound, .t-leg { fill: #93A09A; }
.t-desc { fill: #C3CDC8; }
.t-rel { fill: #93A09A; stroke: #171F1C; }
.edge, .edge-later { stroke: #7D8B85; }
.arrowhead { fill: #7D8B85; }
}
</style>"""

DEFS = ('<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
        'orient="auto-start-reverse"><path class="arrowhead" d="M0 0L10 5L0 10z"/></marker></defs>')

LEGEND = [("b-sys", "In scope"), ("b-per", "Person"), ("b-mac", "Macula infrastructure"),
          ("b-ext", "External system"), ("b-cmp", "Container or component")]
BOUNDARY = ("bound", "Boundary")


class Diagram:
    def __init__(self, name, title, w, h):
        self.name, self.title, self.w, self.h, self.parts = name, title, w, h, []

    def text(self, cls, x, y, s, anchor=None, rotate=None):
        a = f' text-anchor="{anchor}"' if anchor else ""
        r = f' transform="rotate({rotate} {x} {y})"' if rotate is not None else ""
        self.parts.append(f'<text class="{cls}" x="{x}" y="{y}"{a}{r}>{escape(s)}</text>')

    def box(self, cls, x, y, w, h, name, kind, desc, person=False, code=False):
        # A box that is too small for its own words renders as text on top of the
        # next box, which no test would catch and a reader would read as the
        # diagram saying something it does not. Fail here instead.
        need = 70 + 16 * max(len(desc) - 1, 0) + 18
        if h < need:
            raise ValueError(f"{self.name}: {name} needs height {need}, has {h}")
        for line in desc:
            if 16 + 6.2 * len(line) > w - 16:
                raise ValueError(f"{self.name}: {name}: '{line}' is wider than {w - 32}px")
        self.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="10"/>')
        tx = x + 16
        if person:
            self.parts.append(f'<circle class="head" cx="{x + 26}" cy="{y + 24}" r="9"/>')
            tx = x + 44
        self.text("t-code" if code else "t-name", tx, y + 28, name)
        self.text("t-type", tx, y + 46, kind)
        for i, line in enumerate(desc):
            self.text("t-desc", x + 16, y + 70 + 16 * i, line)

    def bound(self, x, y, w, h, label, bottom=False):
        # bottom=True puts the label on the lower edge, for a boundary that
        # edges enter from above.
        self.parts.append(f'<rect class="bound" x="{x}" y="{y}" width="{w}" height="{h}" rx="12"/>')
        self.text("t-bound", x + 16, y + h - 10 if bottom else y + 22, label)

    def edge(self, d, later=False):
        self.parts.append(f'<path class="{"edge-later" if later else "edge"}" d="{d}" marker-end="url(#a)"/>')

    def legend(self, y, boundary=True):
        x = 24
        for cls, label in LEGEND + ([BOUNDARY] if boundary else []):
            self.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="22" height="14" rx="3"/>')
            self.text("t-leg", x + 30, y + 12, label)
            x += 34 + 6.6 * len(label)

    def write(self):
        svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" role="img" '
               f'aria-label="{escape(self.title)}">', f"<title>{escape(self.title)}</title>", STYLE, DEFS,
               f'<rect class="bg" x="0" y="0" width="{self.w}" height="{self.h}"/>'] + self.parts + ["</svg>", ""]
        with open(os.path.join(OUT, self.name), "w") as f:
            f.write("\n".join(svg))




def context():
    d = Diagram("c4-context.svg", "mcl-tenders system context", 1000, 760)
    d.box("b-per", 40, 30, 270, 120, "Bid team", "[Person]",
          ["The company's own people: they set", "the profile and work each tender,", "in a browser on the company LAN"],
          person=True)
    d.box("b-per", 365, 30, 270, 120, "Realm operator", "[Person]",
          ["Deploys mcl-tenders in the realm", "and grants the tenders role to the", "people and agents who may use it"],
          person=True)
    d.box("b-ext", 690, 30, 270, 120, "Company agent", "[External system, optional]",
          ["An agent of the same realm, holding", "the tenders role; reads notice text", "as data, never as instructions"])
    d.bound(345, 186, 310, 244, "Company realm", bottom=True)
    d.box("b-sys", 365, 214, 270, 170, "mcl-tenders", "[Erlang umbrella, one release]",
          ["Fetches the tender notices that fit", "the realm's own profile, guides each",
           "from spotted to bid, won or lost,", "and keeps the profile and the work", "on the realm's own node"])
    d.box("b-ext", 720, 240, 250, 120, "TED Search API", "[External system]",
          ["Anonymous, no key. Sees the", "realm's CPV codes and countries", "in its query, nothing more"])
    d.box("b-later", 30, 240, 250, 120, "TenderNed", "[External system, later: #6]",
          ["The Dutch platform, as a", "second source of the same", "notices; needs credentials"])
    d.box("b-mac", 365, 470, 270, 120, "macula-realm", "[Macula infrastructure]",
          ["The trust anchor: membership,", "the tenders role, and the org", "delegation the group key rests on"])
    d.box("b-mac", 690, 470, 270, 120, "Macula stations, mesh DHT", "[Macula infrastructure]",
          ["Carry the sealed fact between the", "realm's nodes; they see a topic", "and a size, never a notice"])
    d.box("b-later", 40, 470, 270, 120, "Company mail server", "[External system, later: #5]",
          ["Gets the morning digest only", "when an owner switches it on,", "straight from the node"])
    d.edge("M175 150V170H400V214")
    d.text("t-rel", 183, 166, "sets the profile, works tenders, on the LAN")
    d.edge("M500 150V214"); d.text("t-rel", 508, 196, "deploys, grants")
    d.edge("M825 150V170H600V214"); d.text("t-rel", 817, 166, "sealed calls", anchor="end")
    d.edge("M635 300H720"); d.text("t-rel", 677, 292, "by date,", anchor="middle")
    d.text("t-rel", 677, 318, "CPV, country", anchor="middle")
    d.edge("M365 300H280", later=True); d.text("t-rel", 322, 292, "later", anchor="middle")
    d.edge("M460 384V470"); d.text("t-rel", 468, 456, "role, delegation")
    d.edge("M600 384V445H825V470"); d.text("t-rel", 640, 462, "sealed fact, inside the realm")
    d.edge("M365 365H325V450H175V470", later=True); d.text("t-rel", 183, 444, "digest, opt-in")
    d.text("t-desc", 40, 636, "The realm is the trust boundary: each realm runs its own mcl-tenders, and no sensor is shared between realms. The profile,")
    d.text("t-desc", 40, 654, "the matches and the pursuits stay on the realm's node. TED sees the CPV codes and countries the query names; the stations")
    d.text("t-desc", 40, 672, "see that the realm uses the service, never which notices reached it. Keywords, exclusions and the description never leave.")
    d.legend(700, boundary=True)
    d.write()


def containers():
    d = Diagram("c4-containers.svg", "mcl-tenders containers", 1100, 1180)
    d.box("b-per", 50, 30, 300, 120, "Bid team", "[Person, browser on the LAN]",
          ["Sets the profile and works", "each tender, signed in"], person=True)
    d.box("b-ext", 400, 30, 300, 120, "Company agent", "[External system, optional]",
          ["Holds the tenders role in", "the same realm"])
    d.box("b-ext", 750, 30, 300, 120, "TED Search API", "[External system]",
          ["Anonymous Search API v3"])
    d.bound(30, 190, 1040, 640, "mcl-tenders [one release, on a node of the company's realm]", bottom=True)
    d.box("b-cmp", 50, 230, 300, 150, "mcl_tenders_admin", "[OTP app: web UI, cowboy]",
          ["LAN only; realm sign-in. A CPV", "picker, a country list, keywords,", "exclusions; the morning list and",
           "each tender's dossier."], code=True)
    d.box("b-cmp", 400, 230, 300, 150, "query_tenders", "[OTP app: QRY]",
          ["get_tender_profile, get_tenders_page,", "get_tender_by_id. Serves the UI", "in process, and agents through",
           "sealed procedures, role only."], code=True)
    d.box("b-sys", 750, 230, 300, 150, "sense_tender_notices", "[OTP app: sensor]",
          ["Reads the realm's profile, asks TED", "for the day's notices in its CPV", "codes and countries, drops exclusions,",
           "reports each new one, sealed."], code=True)
    d.box("b-cmp", 50, 430, 300, 150, "guide_tender_lifecycle", "[OTP app: CMD, the process]",
          ["The profile and each tender's dossier:", "spotted, pursued or declined, asked,", "submitted, won or lost. Hears the",
           "fact in on_tender_notice_reported_*."], code=True)
    d.box("b-cmp", 400, 430, 300, 150, "Read models", "[SQLite]",
          ["The profile, the tenders page", "and each dossier, shaped for", "the reads: no joins."])
    d.box("b-mac", 750, 430, 300, 150, "mcl_om and macula", "[libraries]",
          ["Realm identity, the pinned dial,", "sealed calls, and the sealed group:", "this node serves its key."], code=True)
    d.box("b-cmp", 50, 630, 300, 150, "Event store", "[ReckonDB, embedded]",
          ["Every event of the process,", "on this node's disk: it holds", "the bid strategy."])
    d.box("b-cmp", 400, 630, 300, 150, "project_tenders", "[OTP app: PRJ]",
          ["One projection per event,", "event_to_table, writing the", "read models."], code=True)
    d.box("b-mac", 50, 880, 300, 120, "macula-realm", "[Macula infrastructure]",
          ["Membership, the tenders role,", "the org delegation"])
    d.box("b-mac", 750, 880, 300, 120, "Macula stations", "[Macula infrastructure]",
          ["Carry the sealed fact; never", "see a notice"])
    d.edge("M200 150V230"); d.text("t-rel", 208, 176, "HTTPS on the LAN")
    d.edge("M550 150V230"); d.text("t-rel", 558, 176, "sealed calls, tenders role")
    d.edge("M900 230V150"); d.text("t-rel", 908, 176, "by date, CPV, country")
    d.edge("M350 330H400"); d.text("t-rel", 375, 322, "reads", anchor="middle")
    d.edge("M750 330H700"); d.text("t-rel", 725, 322, "profile", anchor="middle")
    d.edge("M200 380V430"); d.text("t-rel", 208, 410, "commands")
    d.edge("M200 580V630"); d.text("t-rel", 208, 610, "appends events")
    d.edge("M350 705H400"); d.text("t-rel", 375, 697, "events", anchor="middle")
    d.edge("M550 630V580"); d.text("t-rel", 558, 624, "writes")
    d.edge("M550 380V430"); d.text("t-rel", 558, 410, "reads")
    d.edge("M900 380V430"); d.text("t-rel", 908, 410, "publishes the sealed fact")
    d.edge("M800 580V605H375V505H350"); d.text("t-rel", 790, 600, "delivers it, from the realm's sensors only", anchor="end")
    d.edge("M1000 580V880"); d.text("t-rel", 1008, 730, "QUIC")
    d.edge("M900 580V855H200V880"); d.text("t-rel", 560, 849, "trust anchor, role, delegation", anchor="middle")
    d.text("t-desc", 50, 1040, "One release, so the profile is read in process and crosses no network. The fact between the sensor and the process goes")
    d.text("t-desc", 50, 1058, "through the mesh, sealed under the realm's group, so the sensor may also run on another node of the realm. Every procedure")
    d.text("t-desc", 50, 1076, "is sealed and admits only the tenders role. The event store and the read models hold the bid strategy: back them up as such.")
    d.legend(1110)
    d.write()


def components():
    d = Diagram("c4-components.svg", "mcl-tenders components: the profile, the sensor and the morning list", 1500, 1260)
    d.box("b-per", 50, 30, 300, 120, "Tenders role holder", "[Person or agent of the realm]",
          ["Describes, reads or archives the profile;", "lists, reads and dismisses tenders,", "through sealed calls"], person=True)
    d.box("b-mac", 400, 30, 300, 120, "macula link", "[library, on this node]",
          ["Refuses a call in the clear, and", "a caller without the tenders role,", "before any handler runs"])
    d.box("b-mac", 750, 30, 300, 120, "macula-realm", "[Macula infrastructure]",
          ["Mints the tenders role and", "anchors the realm's identity"])
    d.bound(30, 190, 1440, 860, "mcl-tenders [one release]: the profile, the sensor and the morning list", bottom=True)
    d.box("b-cmp", 50, 230, 300, 150, "describe_ and archive_ responders", "[guide_tender_lifecycle]",
          ["describe checks every field; archive", "ends the realm's search, for good.", "Each records the caller as who",
           "described or archived it."], code=True)
    d.box("b-sys", 400, 230, 300, 150, "mcl_tenders_service", "[mcl_om service contract]",
          ["Announces its six procedures,", "sealed, for the tenders role only.", "At boot, initiates the realm's",
           "profile once. /health: intake, quiet."], code=True)
    d.box("b-cmp", 750, 230, 300, 150, "get_tender_profile_responder", "[query_tenders]",
          ["Answers the realm's profile,", "or a reason. Never the profile", "of another realm."], code=True)
    d.box("b-cmp", 50, 430, 300, 150, "tender_profile_aggregate", "[guide_tender_lifecycle, CMD]",
          ["maybe_initiate_, maybe_describe_,", "maybe_archive_tender_profile. One", "dossier per realm; its state holds",
           "flags only, never the profile."], code=True)
    d.box("b-cmp", 400, 430, 300, 150, "*_to_tender_profiles", "[project_tenders, PRJ]",
          ["One projection per event, through", "tenders_read_model_store, which", "keeps no argument in a crash",
           "report or a log."], code=True)
    d.box("b-cmp", 750, 430, 300, 150, "get_tender_profile", "[query_tenders, QRY]",
          ["find/1 by realm, through", "tenders_query_store. The sensor", "and the process manager read",
           "it here, in process."], code=True)
    d.box("b-cmp", 50, 630, 300, 150, "mcl_tenders_store", "[ReckonDB, embedded]",
          ["Every event of the profile and", "of each dossier, on this node's", "disk under /data"], code=True)
    d.box("b-cmp", 400, 630, 300, 150, "tenders.sqlite3", "[SQLite read model]",
          ["The profile, one row per realm;", "the tenders, one row per dossier,", "indexed for the morning list"], code=True)
    d.box("b-ext", 1100, 30, 300, 120, "TED Search API", "[External system]",
          ["Anonymous, no key. Sees the", "realm's CPV codes and countries"])
    d.box("b-cmp", 1100, 430, 300, 150, "sense_ted_notices", "[sense_tender_notices, sensor]",
          ["Reads the profile each sweep,", "asks TED for its codes and", "countries, reports each new",
           "notice, sealed in the realm."], code=True)
    d.box("b-cmp", 1100, 630, 300, 150, "mcl_tenders_group_keys", "[macula_group_keys, distributor]",
          ["Hands the tenders group's key", "to nodes with the org's grant.", "Not started without",
           "MCL_GROUP_ORG_KEY_ID."], code=True)
    d.box("b-cmp", 50, 830, 300, 150, "tender_aggregate", "[guide_tender_lifecycle, CMD]",
          ["spot, amend, note the award, dismiss:", "one dossier per tender, its state", "flags only. dismiss_tender_responder",
           "records the caller."], code=True)
    d.box("b-cmp", 400, 830, 300, 150, "*_to_tenders", "[project_tenders, PRJ]",
          ["One upsert per event, in any order:", "a correction that lands before its", "spot is kept; status flags are ORed."],
          code=True)
    d.box("b-cmp", 750, 830, 300, 150, "get_tenders_page, get_tender_by_id", "[query_tenders, QRY, and responders]",
          ["The morning list, best first, and", "the whole dossier. The TED link is", "rebuilt from the publication",
           "number, never taken from a notice."], code=True)
    d.box("b-cmp", 1100, 830, 300, 150, "on_tender_notice_reported_v1_*", "[guide_tender_lifecycle, PM]",
          ["Reads each notice again, fits it", "(tender_fit: keywords only, #4a),", "caps the day's spots (tender_intake),",
           "dispatches in process."], code=True)
    d.edge("M350 90H400"); d.text("t-rel", 375, 82, "call", anchor="middle")
    d.edge("M1100 505H1050"); d.text("t-rel", 1075, 497, "find/1", anchor="middle")
    d.edge("M1250 430V150"); d.text("t-rel", 1258, 290, "days, CPV codes,"); d.text("t-rel", 1258, 306, "countries")
    d.edge("M1250 580V630"); d.text("t-rel", 1258, 610, "pulls the group key")
    d.edge("M750 90H700"); d.text("t-rel", 725, 82, "role", anchor="middle")
    d.edge("M450 150V205H200V230"); d.text("t-rel", 208, 200, "describe_ / archive_tender_profile")
    d.edge("M650 150V205H900V230"); d.text("t-rel", 892, 200, "get_tender_profile", anchor="end")
    d.edge("M200 380V430"); d.text("t-rel", 208, 410, "command")
    d.edge("M550 380V405H300V430"); d.text("t-rel", 558, 400, "initiates at boot")
    d.edge("M900 380V430"); d.text("t-rel", 908, 410, "find/1")
    d.edge("M200 580V630"); d.text("t-rel", 208, 610, "appends events")
    d.edge("M350 705H375V530H400"); d.text("t-rel", 368, 620, "events", anchor="end", rotate=-90)
    d.edge("M550 580V630"); d.text("t-rel", 558, 610, "writes")
    d.edge("M900 580V705H700"); d.text("t-rel", 908, 650, "reads")
    d.edge("M1400 505H1440V905H1400", later=True)
    d.text("t-rel", 1448, 705, "the sealed fact: subscribed with mcl_om 1.7.0", anchor="middle", rotate=90)
    d.edge("M1150 830V805H1000V580"); d.text("t-rel", 1008, 800, "profile")
    d.edge("M1250 980V1015H200V980"); d.text("t-rel", 725, 1009, "spot, amend, note the award, in process", anchor="middle")
    d.edge("M200 830V780"); d.text("t-rel", 208, 810, "appends events")
    d.edge("M350 760H375V905H400"); d.text("t-rel", 368, 870, "events", anchor="end", rotate=-90)
    d.edge("M550 830V780"); d.text("t-rel", 558, 810, "writes")
    d.edge("M750 905H725V760H700"); d.text("t-rel", 733, 800, "reads")
    d.text("t-desc", 50, 1090, "The profile says what the realm bids for, so it lives on the node's disk, in the event store and the read model, and")
    d.text("t-desc", 50, 1108, "nowhere else: not in a log, not in a crash report, not in an aggregate's state. Which notices fit draws the profile's")
    d.text("t-desc", 50, 1126, "outline, so the dossiers keep the same rule. Every procedure is sealed and admits only identities the realm granted the")
    d.text("t-desc", 50, 1144, "tenders role. The sensor asks TED for the profile's codes and countries only, and its facts travel sealed under the")
    d.text("t-desc", 50, 1162, "realm's tenders group. The dashed edge is not wired yet: the node subscribes the process manager once mcl_om 1.7.0 lets a")
    d.text("t-desc", 50, 1180, "declared subscription carry the group and its admission (macula-services/mcl-om#48).")
    d.legend(1220)
    d.write()


if __name__ == "__main__":
    for make in (context, containers, components):
        make()
