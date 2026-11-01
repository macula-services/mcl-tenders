# mcl-tenders

Each morning, the new public tenders that fit your company, without handing your
profile to anyone outside your realm.

Each realm runs its own mcl-tenders: it fetches the EU's tender notices that fit
the realm's own profile, and guides each one from spotted to bid, won or lost. The
profile is set by the company's own people in a web UI on their LAN, and it never
leaves the realm's node.

![mcl-tenders system context](assets/c4-context.svg)

The C4 model, context and containers, is in
[architecture/README.md](architecture/README.md). The vision, boundary, design and
threat model are on macula-services/mcl-tenders#1.

## Licence

Apache-2.0.
