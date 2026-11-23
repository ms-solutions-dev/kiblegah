"""Builds the tafsir packs: "Al-Mukhtasar fi al-Tafsir" (Tafsir Center) via QuranEnc, TR and EN.

Short and easy to understand, one entry per verse. The schema allows ranges (`ilk`..`son`)
because other tafsirs explain whole passages. QuranEnc has no German edition; the app
then shows the English one and says so.
"""

import json
import re
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script directory from sys.path
from ortak import KAYNAK, kaynak, paket_yaz  # noqa: E402

SEMA = """
CREATE TABLE tefsir(
    sure INTEGER NOT NULL, ilk INTEGER NOT NULL, son INTEGER NOT NULL, metin TEXT NOT NULL,
    PRIMARY KEY(sure, ilk)) WITHOUT ROWID;
"""

NUMARA = re.compile(r"^\(?\d+\)?[.)]?\s*")


def yaz(kimlik: str, dil: str, satirlar: list[tuple], surum: str) -> None:
    assert len(satirlar) == 6236, (kimlik, len(satirlar))

    def doldur(db) -> None:
        db.executemany("INSERT INTO tefsir VALUES(?,?,?,?)", satirlar)

    paket_yaz({
        "id": kimlik,
        "art": "tefsir",
        "sprache": dil,
        "titel": "Muhtasar Tefsir" if dil == "tr" else "Al-Mukhtasar Tafsir",
        "yazar": "Tefsir Araştırmaları Merkezi (Markaz Tafsir)",
        "quelle": "QuranEnc.com – Al-Mukhtasar fi al-Tafsir",
        "quelle_url": f"https://quranenc.com/en/browse/{'turkish' if dil == 'tr' else 'english'}_mokhtasar",
        "lizenz": "QuranEnc terms: unchanged, cite source and version, not for sale",
        "store_tauglich": True,
        "version": surum,
        "textstand": None,
    }, SEMA, doldur)


def main() -> None:
    db = sqlite3.connect(f"file:{kaynak('turkish_mokhtasar.sqlite')}?mode=ro", uri=True)
    tr = [(s, a, a, NUMARA.sub("", m or "").strip()) for s, a, m in
          db.execute("SELECT sura, aya, translation FROM translations ORDER BY id")]
    yaz("tefsir-tr-muhtasar", "tr", tr, "quranenc-2026-10")

    en = []
    for s in range(1, 115):
        veri = json.loads((KAYNAK / "mokhtasar-en" / f"{s}.json").read_text(encoding="utf-8"))["result"]
        en += [(int(v["sura"]), int(v["aya"]), int(v["aya"]), NUMARA.sub("", v["translation"]).strip()) for v in veri]
    yaz("tefsir-en-muhtasar", "en", en, "quranenc-2026-10")


if __name__ == "__main__":
    main()
