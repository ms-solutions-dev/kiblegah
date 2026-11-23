"""Checks the content packs.

    python3 -I tools/content/denetle.py App/Resources/Paketler          basic check
    python3 -I tools/content/denetle.py App/Resources/Paketler --store  App Store build

Checked: manifest complete, `veri.sqlite` readable and carrying the pack id, packs with
a text revision match the Quran text, basic counts are right. With `--store` the run
fails on every pack with `store_tauglich: false`.
"""

import json
import sqlite3
import sys
from pathlib import Path

FELDER = ("id", "art", "sprache", "titel", "quelle", "quelle_url", "lizenz",
          "store_tauglich", "version", "textstand")
ZAEHLUNG = {
    "kuran-text": [("SELECT count(*) FROM ayet", 6236), ("SELECT count(*) FROM sure", 114),
                   ("SELECT count(*) FROM sayfa WHERE mushaf='medine-604'", 604),
                   ("SELECT count(*) FROM cuz", 30)],
    "meal": [("SELECT count(*) FROM meal", 6236)],
    "okunus": [("SELECT count(*) FROM okunus", 6236)],
    "tefsir": [("SELECT count(*) FROM tefsir", 6236)],
    "esma": [("SELECT count(*) FROM esma", 99)],
    "dua": [("SELECT count(*) >= 50 FROM dua", 1)],
    # 63 verses have no rule (cpfair), so only a lower bound on the spans.
    "tecvid": [("SELECT count(*) > 60000 FROM tecvid", 1)],
    "hadis": [("SELECT count(DISTINCT kimlik) > 2000 FROM hadis", 1), ("SELECT count(*) > 100 FROM bag", 1)],
    "arama-vektor": [("SELECT count(*) % 6236 FROM ayet", 0), ("SELECT count(*) >= 3 FROM merkez", 1),
                     ("SELECT count(*) FROM ayet WHERE length(vektor) <> 260", 0)],
}


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: denetle.py <pack folder> [--store]")
        return 2
    kok = Path(sys.argv[1])
    store = "--store" in sys.argv[2:]
    hatalar: list[str] = []
    manifestler: dict[str, dict] = {}
    for klasor in sorted(p for p in kok.iterdir() if p.is_dir()):
        m_yol, v_yol = klasor / "manifest.json", klasor / "veri.sqlite"
        if not m_yol.exists() or not v_yol.exists():
            hatalar.append(f"{klasor.name}: manifest.json or veri.sqlite missing")
            continue
        m = json.loads(m_yol.read_text(encoding="utf-8"))
        eksik = [f for f in FELDER if f not in m]
        if eksik:
            hatalar.append(f"{klasor.name}: manifest lacks {eksik}")
            continue
        if m["id"] != klasor.name:
            hatalar.append(f"{klasor.name}: folder and id ({m['id']}) differ")
        if store and not m["store_tauglich"]:
            hatalar.append(f"{m['id']}: not suitable for the App Store ({m['lizenz']})")
        db = sqlite3.connect(f"file:{v_yol}?mode=ro", uri=True)
        try:
            paket = db.execute("SELECT deger FROM bilgi WHERE anahtar='paket'").fetchone()
            if not paket or paket[0] != m["id"]:
                hatalar.append(f"{m['id']}: bilgi.paket does not match")
            for sorgu, beklenen in ZAEHLUNG.get(m["art"], []):
                gercek = db.execute(sorgu).fetchone()[0]
                if gercek != beklenen:
                    hatalar.append(f"{m['id']}: {sorgu} -> {gercek}, expected {beklenen}")
        except sqlite3.Error as e:
            hatalar.append(f"{m['id']}: {e}")
        finally:
            db.close()
        manifestler[m["id"]] = m

    kuran = manifestler.get("kuran-text")
    if not kuran:
        hatalar.append("kuran-text missing")
    else:
        for m in manifestler.values():
            if m["textstand"] and m["textstand"] != kuran["textstand"]:
                hatalar.append(f"{m['id']}: text revision {m['textstand']} != {kuran['textstand']}")
    for h in hatalar:
        print(f"  {h}")
    if not hatalar:
        print(f"  {len(manifestler)} packs OK" + (" (store)" if store else ""))
    return 1 if hatalar else 0


if __name__ == "__main__":
    sys.exit(main())
