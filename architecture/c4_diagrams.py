"""Generate mcl-tenders' two C4 diagrams into assets/.

Run:  python3 architecture/c4_diagrams.py

  c4-context.svg     Level 1: what the sensor talks to
  c4-components.svg  Level 2: what it is made of

Drawn from the code, never from a template: the callbacks in
apps/mcl_tenders_sensor/src/mcl_tenders_sensor_service.erl, the one-child
supervisor, the sweep in apps/sense_tender_notices/src/sense_ted_notices/, the
parser and the reported window beside it, the fact in mcl_tenders_facts.erl, the
deps in rebar.config, the org and realm settings in config/sys.config.src, and the
variables deploy/docker-compose.yml passes. When one of those changes, the diagram
changes in the same commit.

The company node (macula-services/mcl-tenders#3) is not built yet and is drawn
dashed, as later.

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

    def bound(self, x, y, w, h, label):
        self.parts.append(f'<rect class="bound" x="{x}" y="{y}" width="{w}" height="{h}" rx="12"/>')
        self.text("t-bound", x + 16, y + 22, label)

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
    d = Diagram("c4-context.svg", "mcl-tenders sensor system context", 1000, 690)
    d.box("b-per", 40, 30, 270, 120, "Operator", "[Person]",
          ["Runs the realm's own sensor;", "no sensor is shared between", "realms. Tunes the sweep only"],
          person=True)
    d.box("b-later", 365, 30, 270, 120, "Company node", "[External system, later: #3]",
          ["Subscribes to the one topic and", "matches each notice against its", "own profile, which never leaves"])
    d.box("b-ext", 690, 30, 270, 120, "TED Search API", "[External system]",
          ["api.ted.europa.eu v3, anonymous,", "no key; every EU notice, eForms", "and the older schema, as JSON"])
    d.box("b-sys", 365, 186, 270, 170, "mcl-tenders-sensor", "[mcl_om mesh service]",
          ["Sweeps every notice TED published", "since its last sweep and reports", "each new one as one fact,",
           "tender_notice_reported_v1. It asks", "TED for all of it, serves no", "procedure and keeps no store"])
    d.box("b-mac", 365, 430, 270, 120, "macula-realm", "[Macula infrastructure]",
          ["The trust anchor and the grant:", "scope mcl-tenders-sensor for 30", "days, and the boot claim"])
    d.box("b-mac", 690, 430, 270, 120, "Macula stations, mesh DHT", "[Macula infrastructure]",
          ["The pinned dial; the fact goes out", "through a station, and the DHT", "holds each advertisement"])
    d.edge("M175 150V168H400V186")
    d.text("t-rel", 183, 184, "deploys it, sets"); d.text("t-rel", 183, 200, "the sweep")
    d.edge("M560 186V150", later=True); d.text("t-rel", 552, 172, "one fact per new notice", anchor="end")
    d.edge("M600 186V168H825V150"); d.text("t-rel", 640, 164, "searches by date only")
    d.edge("M460 356V430"); d.text("t-rel", 468, 384, "trust anchor, grant")
    d.edge("M620 356V370H825V430"); d.text("t-rel", 632, 364, "publishes the fact")
    d.text("t-desc", 40, 596, "The query names a date and nothing else, so TED learns nothing about who uses the notices, and no company")
    d.text("t-desc", 40, 614, "ever asks the sensor for one notice: every fact carries all a match needs. One topic for every notice, so no")
    d.text("t-desc", 40, 632, "station on the path sees which codes a company follows. TED down, or a dark mesh, is not a health failure.")
    d.legend(650, boundary=False)
    d.write()


def components():
    d = Diagram("c4-components.svg", "mcl-tenders sensor components", 1040, 1170)
    d.bound(40, 40, 968, 830, "mcl-tenders-sensor [Container]")
    d.box("b-cmp", 56, 70, 456, 120, "mcl_tenders_sensor_app", "[OTP application]",
          ["start/2 calls mcl_om:boot(mcl_tenders_sensor_service).", "The service exports no store_id/0 or data_dir/0,",
           "so mcl_om starts no reckon-db and no subscription."], code=True)
    d.box("b-sys", 536, 70, 456, 152, "mcl_tenders_sensor_service", "[:mcl_om_service behaviour]",
          ["The six callbacks. start/1 refuses a realm whose", "tag is not the sha256 of MCL_REALM_NAME; scope",
           "mcl-tenders-sensor for 30 days. No procedure of",
           "its own; mcl-om adds info and get_limits, both open.",
           "capabilities/0 is the list."], code=True)
    d.box("b-cmp", 56, 230, 456, 120, "mcl_tenders_sensor_sup", "[supervisor, one_for_one]",
          ["One child, sense_ted_notices, which owns the", "sweep, the reported window and the publishing.",
           "A crashed sensor is restarted from today."], code=True)
    d.box("b-cmp", 536, 230, 456, 120, "mcl_tenders_facts", "[Erlang module]",
          ["The one topic and its closed field list, every", "string tagged text and bounded, and report/1,",
           "which answers ok only once the mesh took it."], code=True)
    d.box("b-cmp", 56, 390, 456, 120, "sense_ted_notices", "[gen_server, the sweep]",
          ["Every MCL_TENDERS_POLL_MS: a week of notices from", "its since day, page by page in scroll mode,",
           "paced; the first failed report ends the sweep."], code=True)
    d.box("b-cmp", 536, 390, 456, 120, "parse_ted_notice", "[Erlang module, pure]",
          ["One Search API notice into one map: type, buyer,", "CPV codes, titles, deadline, value. No contact",
           "field is asked for or read; a bad field is empty."], code=True)
    d.box("b-cmp", 56, 550, 456, 120, "reported_window", "[Erlang module, pure]",
          ["The publication numbers already reported,", "bounded (30,000 by default) and rebuilt empty",
           "on restart; company nodes deduplicate too."], code=True)
    d.box("b-ext", 536, 550, 456, 120, "TED Search API", "[HTTPS, inets and ssl]",
          ["POST /v3/notices/search, anonymous: a date query,", "scroll mode, 250 notices a page, a fixed field",
           "list. A 429 doubles the wait, up to six hours."], code=True)
    d.box("b-mac", 56, 710, 456, 120, "mcl_om", "[library, ~> 1.6]",
          ["boot/1: loads the identity key, joins the realm,", "dials the pinned stations, serves /health on a",
           "Unix socket, and carries mcl_om_pubsub:publish/3."], code=True)
    d.box("b-mac", 536, 710, 456, 120, "macula SDK", "[library, ~> 18.0, wire 1.0]",
          ["QUIC transport, pubsub over the stations, and", "the publisher every link verified, which is",
           "what a fact's attribution rests on."], code=True)
    d.edge("M56 130H16V770H56"); d.text("t-rel", 30, 450, "calls mcl_om:boot/1", anchor="middle", rotate=-90)
    d.edge("M512 130H536"); d.text("t-rel", 524, 122, "boots", anchor="middle")
    d.edge("M536 160H520V210H284V230"); d.text("t-rel", 300, 206, "starts")
    d.edge("M200 350V390"); d.text("t-rel", 208, 374, "one child")
    d.edge("M512 450H536"); d.text("t-rel", 524, 442, "parses", anchor="middle")
    d.edge("M200 510V550"); d.text("t-rel", 208, 534, "skips what it reported")
    d.edge("M350 510V530H700V550"); d.text("t-rel", 420, 526, "searches")
    d.edge("M450 390V378H700V350"); d.text("t-rel", 500, 374, "reports each notice")
    d.edge("M512 770H536"); d.text("t-rel", 524, 762, "dials", anchor="middle")
    d.box("b-ext", 64, 900, 920, 136, "Host environment", "[read at boot; some defaults are baked in]",
          ["MCL_REALM and MCL_REALM_NAME are required and must agree; MCL_REALM_KEY is the trust anchor; MACULA_STATION_SEEDS with",
           "MACULA_STATION_NODE_IDS is the pinned dial. MCL_TENDERS_POLL_MS, MCL_TENDERS_MAX_SEEN and MCL_TENDERS_LOOKBACK_DAYS",
           "tune the sweep, the reported window and the first day a fresh sensor reads.",
           "MCL_SERVICE_NAME and MCL_BOX label the boot claim; /health is a Unix socket, not a port."],
          code=True)
    d.text("t-desc", 64, 1070, "No store: since moves only when every notice of the sweep (at most a week) was reported, so a dark mesh or a page TED")
    d.text("t-desc", 64, 1088, "refuses delays a notice and loses none. On restart the sensor starts from today again; a day reported twice is harmless,")
    d.text("t-desc", 64, 1106, "because company nodes deduplicate by publication number.")
    d.legend(1130)
    d.write()


if __name__ == "__main__":
    for make in (context, components):
        make()
