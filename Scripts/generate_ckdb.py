#!/usr/bin/env python3
"""Generate a CloudKit Schema Language (.ckdb) file from the Core Data model,
following NSPersistentCloudKitContainer's CD_ mirroring conventions:

  * entity Foo                -> RECORD TYPE CD_Foo
  * attribute bar            -> CD_bar <type> <indexes>  (+ CD_bar_ckAsset ASSET
                                 for String/UUID/Binary — the overflow companion)
  * to-one relationship rel  -> CD_rel STRING (holds destination recordName; NOT a REFERENCE)
  * to-many relationship     -> no field (foreign key lives on the to-one side)
  * every type gets the 6 ___ system fields + CD_entityName STRING QUERYABLE …
  * no many-to-many in this model -> no CDMR type needed
"""
import xml.etree.ElementTree as ET

MODEL = "ProjectStock/Model/ProjectStock.xcdatamodeld/ProjectStock.xcdatamodel/contents"

# Core Data attributeType -> (CKML type, index keywords, needs _ckAsset companion)
def map_attr(atype):
    if atype in ("String", "URI"):
        return ("STRING", "QUERYABLE SEARCHABLE SORTABLE", True)
    if atype == "UUID":
        return ("STRING", "QUERYABLE SEARCHABLE SORTABLE", True)
    if atype == "Boolean":
        return ("INT64", "QUERYABLE SORTABLE", False)
    if atype.startswith("Integer"):
        return ("INT64", "QUERYABLE SORTABLE", False)
    if atype in ("Double", "Float", "Decimal"):
        return ("DOUBLE", "QUERYABLE SORTABLE", False)
    if atype == "Date":
        return ("TIMESTAMP", "QUERYABLE SORTABLE", False)
    if atype in ("Binary", "Transformable"):
        # CloudKit forbids indexing BYTES/ASSET fields — a QUERYABLE/SORTABLE
        # binary field is rejected (or silently dropped) on import and never
        # matches what Core Data's own mirroring generates. Leave it unindexed.
        return ("BYTES", "", True)
    raise SystemExit(f"Unhandled attributeType: {atype}")

SYSTEM_FIELDS = [
    '"___createTime" TIMESTAMP',
    '"___createdBy"  REFERENCE',
    '"___etag"       STRING',
    '"___modTime"    TIMESTAMP',
    '"___modifiedBy" REFERENCE',
    '"___recordID"   REFERENCE QUERYABLE',
]
GRANTS = [
    'GRANT WRITE TO "_creator"',
    'GRANT CREATE TO "_icloud"',
    'GRANT READ TO "_world"',
]

tree = ET.parse(MODEL)
root = tree.getroot()

out = ["DEFINE SCHEMA", ""]

# Default Users type (already present in the container; included for a complete schema).
out.append("    RECORD TYPE Users (")
for f in SYSTEM_FIELDS[:-1]:
    out.append(f"        {f},")
out.append('        "___recordID"   REFERENCE,')
out.append("        roles           LIST<INT64>,")
out.append('        GRANT WRITE TO "_creator",')
out.append('        GRANT READ TO "_world"')
out.append("    );")
out.append("")

# cloudkit.share — the CKShare system record type. CRITICAL: Production NEVER
# auto-creates record types; it only receives what Development has at deploy
# time. Development only gets cloudkit.share when a share is actually created
# there (or when it's imported explicitly). Our first import omitted it, so the
# deploy carried only the CD_ types — and every CKShare save in Production has
# failed since with CKInternalErrorDomain 2006:
#   "Cannot create new type cloudkit.share in production schema"
# (= the confirmed root cause of 共有リンクを作成できませんでした).
# The name MUST be double-quoted: the Console's Import Schema parser rejects the
# unquoted dot ('Encountered "." ... Was expecting: "("'). Quoted, the import
# validates, Development gains the full system share type (the server expands it
# to its real 9 fields incl. cloudkit.title), and Deploy carries it to
# Production — verified working 2026-07.
out.append('    RECORD TYPE "cloudkit.share" (')
for f in SYSTEM_FIELDS:
    out.append(f"        {f},")
out.append('        GRANT WRITE TO "_creator",')
out.append('        GRANT READ TO "_icloud"')
out.append("    );")
out.append("")

for entity in sorted(root.findall("entity"), key=lambda e: e.get("name")):
    name = entity.get("name")
    lines = []
    lines += [f"        {f}," for f in SYSTEM_FIELDS]
    lines.append("        CD_entityName   STRING QUERYABLE SEARCHABLE SORTABLE,")

    for attr in sorted(entity.findall("attribute"), key=lambda a: a.get("name")):
        an = attr.get("name")
        ck, idx, asset = map_attr(attr.get("attributeType"))
        field = f"CD_{an} {ck} {idx}".rstrip()
        lines.append(f"        {field},")
        if asset:
            lines.append(f"        CD_{an}_ckAsset ASSET,")

    for rel in sorted(entity.findall("relationship"), key=lambda r: r.get("name")):
        if rel.get("toMany") == "YES":
            continue  # to-many side stores no field
        rn = rel.get("name")
        lines.append(f"        CD_{rn} STRING QUERYABLE SEARCHABLE SORTABLE,")

    # CD_moveReceipt — REQUIRED on every entity type for CloudKit sharing.
    # When share(_:to:) moves an object graph into the share zone, Core Data
    # writes an opaque NSKeyedArchiver blob (NSCKRecordZoneMoveReceipt) into
    # this field (overflowing to the ASSET companion). Without it, Production
    # rejects the move with "Cannot create or modify field 'CD_moveReceipt'"
    # and sharing stalls after the CKShare itself is created. Type BYTES is
    # confirmed by real exported schemas (perfect-nap, simpleledger, mySpot),
    # by Apple's serializer key enumeration, and by Apple's own statement that
    # the contents are a private archived blob (WWDC22 Core Data lounge).
    lines.append("        CD_moveReceipt BYTES,")
    lines.append("        CD_moveReceipt_ckAsset ASSET,")

    out.append(f"    RECORD TYPE CD_{name} (")
    out += lines
    for i, g in enumerate(GRANTS):
        out.append(f"        {g}" + ("," if i < len(GRANTS) - 1 else ""))
    out.append("    );")
    out.append("")

# (The old assumption that cloudkit.share must be omitted was WRONG — it is
# auto-created only in Development, never in Production. See the comment where
# the type is emitted above.)

open("docs/cloudkit/tanamiru-schema.ckdb", "w").write("\n".join(out))
print("\n".join(out))
