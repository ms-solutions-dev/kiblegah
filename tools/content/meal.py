"""Builds the translation (meal) packs from QuranEnc.

- DE Bubenheim, EN Saheeh and TR Özek via QuranEnc: unchanged, with source and version.
  QuranEnc prefixes some texts with the verse number as "(n) "; it is dropped because
  the app sets the number itself. Footnotes are kept in a separate column.
"""

import json
import re
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script directory from sys.path
from ortak import kaynak, paket_yaz  # noqa: E402

SEMA = """
CREATE TABLE meal(
    sure INTEGER NOT NULL, ayet INTEGER NOT NULL, metin TEXT NOT NULL, dipnot TEXT,
    PRIMARY KEY(sure, ayet)) WITHOUT ROWID;
"""

VERSNUMMER = re.compile(r"^\(\d+\)\s*")


def quranenc(anahtar: str) -> tuple[list[tuple], dict]:
    liste = json.loads(kaynak("liste.json").read_text(encoding="utf-8"))
    bilgi = next(t for t in liste["translations"] if t["key"] == anahtar)
    db = sqlite3.connect(f"file:{kaynak(anahtar + '.sqlite')}?mode=ro", uri=True)
    satirlar = [(s, a, VERSNUMMER.sub("", m).strip(), (d or "").strip() or None)
                for s, a, m, d in db.execute(
                    "SELECT sura, aya, translation, footnotes FROM translations ORDER BY id")]
    return satirlar, bilgi


def yaz(manifest: dict, satirlar: list[tuple]) -> None:
    assert len(satirlar) == 6236, (manifest["id"], len(satirlar))

    def doldur(db) -> None:
        db.executemany("INSERT INTO meal VALUES(?,?,?,?)", satirlar)
        if manifest.get("telif"):
            db.execute("INSERT INTO bilgi VALUES('telif', ?)", (manifest["telif"],))

    paket_yaz(manifest, SEMA, doldur)


def main() -> None:
    for anahtar, kimlik, dil, titel, yazar in (
        ("german_bubenheim", "meal-de-bubenheim", "de", "Bubenheim & Elyas", "Frank Bubenheim, Nadeem Elyas"),
        ("english_saheeh", "meal-en-saheeh", "en", "Saheeh International", "Saheeh International"),
        # Turkish: Özek et al. (TDV translation team), distributed by QuranEnc.
        ("turkish_shahin", "meal-tr-ozek", "tr", "Ali Özek ve arkadaşları", "Dr. Ali Özek, Hayreddin Karaman ve arkadaşları"),
    ):
        satirlar, bilgi = quranenc(anahtar)
        yaz({
            "id": kimlik,
            "art": "meal",
            "sprache": dil,
            "titel": titel,
            "yazar": yazar,
            "quelle": f"QuranEnc.com – {bilgi['title']}",
            "quelle_url": f"https://quranenc.com/en/browse/{anahtar}",
            "lizenz": "QuranEnc terms: unchanged, cite source and version, not for sale",
            "store_tauglich": True,
            "version": bilgi["version"],
            "textstand": None,
        }, satirlar)


if __name__ == "__main__":
    main()
