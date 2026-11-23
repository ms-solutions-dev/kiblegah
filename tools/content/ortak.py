"""Shared helpers for the content-pack tools.

A pack is a folder `App/Resources/Paketler/<id>/` containing `manifest.json` and
`veri.sqlite`. The tools read their raw sources only from `sources/` (git-ignored).
"""

import hashlib
import json
import sqlite3
import sys
from pathlib import Path

KOK = Path(__file__).resolve().parents[2]
KAYNAK = Path(__file__).resolve().parent / "sources"
PAKETLER = KOK / "App" / "Resources" / "Paketler"

# The text revision that tajweed spans, word boundaries and transliteration depend on.
# The cpfair tajweed data only matches exactly this Tanzil copy (April 2017, Uthmani 1.0.2).
TEXTSTAND = "tanzil-uthmani-1.0.2@2017-04"
TEXT_SHA256 = "abe6447a5d29bb126383ba9120628060cf96dc9ef5b402a506fc251f6ed0b9a2"

MANIFEST_FELDER = (
    "id", "art", "sprache", "titel", "quelle", "quelle_url", "lizenz",
    "store_tauglich", "version", "textstand",
)


def sha256(pfad: Path) -> str:
    return hashlib.sha256(pfad.read_bytes()).hexdigest()


def kaynak(ad: str) -> Path:
    pfad = KAYNAK / ad
    if not pfad.exists():
        sys.exit(f"Missing raw source: {pfad} - run tools/content/fetch.sh first")
    return pfad


def tanzil_satirlari(pfad: Path):
    """Yields (surah, ayah, text) from a Tanzil file in `s|a|text` format."""
    for satir in pfad.read_text(encoding="utf-8").splitlines():
        parca = satir.split("|", 2)
        if len(parca) == 3 and parca[0].isdigit():
            yield int(parca[0]), int(parca[1]), parca[2]


def paket_yaz(manifest: dict, sema: str, doldur, hedef: Path | None = None) -> Path:
    """Rewrites a pack: create the schema, fill it via `doldur(db)`, vacuum, write the manifest next to it."""
    eksik = [f for f in MANIFEST_FELDER if f not in manifest]
    if eksik:
        sys.exit(f"Manifest {manifest.get('id')}: missing {eksik}")
    klasor = (hedef or PAKETLER) / manifest["id"]
    klasor.mkdir(parents=True, exist_ok=True)
    veri = klasor / "veri.sqlite"
    veri.unlink(missing_ok=True)
    db = sqlite3.connect(veri)
    db.executescript(sema)
    db.execute("CREATE TABLE bilgi(anahtar TEXT PRIMARY KEY, deger TEXT) WITHOUT ROWID")
    doldur(db)
    db.execute("INSERT INTO bilgi VALUES('paket', ?)", (manifest["id"],))
    db.commit()
    db.execute("PRAGMA journal_mode=DELETE")
    db.execute("VACUUM")
    db.close()
    (klasor / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"  {manifest['id']}: {veri.stat().st_size // 1024} KB")
    return klasor
