"""Builds the `arama` pack: full-text index (SQLite FTS5) over translations, transliterations,
duas, Asma ul-Husna and hadiths.

Folded like `TurkceMetin.aramaBicimi` in Swift (İ/ı, accents, apostrophes), so that
"sabır" and "sabir" find the same. In addition a consonant skeleton per word: Turkish
drops vowels ("sabır" -> "sabrı", "sabredin"), the skeleton "sbr" matches all of them.
"""

import json
import sqlite3
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script directory from sys.path
from ortak import PAKETLER, paket_yaz  # noqa: E402

SESLILER = set("aeiou")


def katla(metin: str) -> str:
    """Same as TurkceMetin.aramaBicimi."""
    s = metin.replace("İ", "i").replace("I", "ı").lower().replace("ı", "i")
    s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
    for c in "'’‘`´-":
        s = s.replace(c, " ")
    return " ".join(s.split())


def iskelet(katli: str) -> str:
    """Only the consonants (letters) of each word; words with fewer than 3 consonants are dropped."""
    kelimeler = []
    for k in katli.split():
        sk = "".join(c for c in k if c.isalpha() and c not in SESLILER)
        if len(sk) >= 3:
            kelimeler.append(sk)
    return " ".join(kelimeler)


SEMA = """
CREATE VIRTUAL TABLE belge USING fts5(
    anahtar UNINDEXED, tur UNINDEXED, paket UNINDEXED, katli, iskelet,
    tokenize = 'unicode61 remove_diacritics 2', detail = column);
"""


def oku(paket: str, sql: str):
    db = sqlite3.connect(f"file:{PAKETLER / paket / 'veri.sqlite'}?mode=ro", uri=True)
    yield from db.execute(sql)


def main() -> None:
    satirlar = []

    def ekle(anahtar: str, tur: str, paket: str, metin: str, turkce: bool) -> None:
        # The original text lives in the source packs; only the index is stored here.
        k = katla(metin)
        satirlar.append((anahtar, tur, paket, k, iskelet(k) if turkce else ""))

    mealler = ("meal-tr-ozek", "meal-de-bubenheim", "meal-en-saheeh")
    for klasor in sorted(PAKETLER.iterdir()):
        if not (klasor / "manifest.json").exists():
            continue
        m = json.loads((klasor / "manifest.json").read_text(encoding="utf-8"))
        if not m["store_tauglich"]:
            continue
        if m["art"] == "meal":
            for s, a, metin in oku(m["id"], "SELECT sure, ayet, metin FROM meal"):
                ekle(f"a:{s}:{a}", "meal", m["id"], metin, m["sprache"] == "tr")
        elif m["art"] == "okunus":
            for s, a, metin in oku(m["id"], "SELECT sure, ayet, metin FROM okunus"):
                ekle(f"a:{s}:{a}", "okunus", m["id"], metin, m["sprache"] == "tr")
    # Duas: via the translation text of their verses (all languages) - key d:<slug>.
    meal_metni = {}
    for p in mealler:
        for s, a, metin in oku(p, "SELECT sure, ayet, metin FROM meal"):
            meal_metni[(p, s, a)] = metin
    for slug, s, ilk, son in oku("dualar", "SELECT slug, sure, ilk, son FROM dua"):
        for p in mealler:
            ekle(f"d:{slug}", "dua", p, " ".join(meal_metni[(p, s, a)] for a in range(ilk, son + 1)), p.startswith("meal-tr"))
    for no, latin, ok, tr, de, en in oku("esma", "SELECT no, latin, okunus_tr, anlam_tr, anlam_de, anlam_en FROM esma"):
        ekle(f"e:{no}", "esma", "esma", " · ".join(x for x in (ok, latin, tr, de, en) if x), True)
    # Hadiths: title + text per language; pack "hadis-<dil>" so the app knows the language.
    # Skipped when the hadis pack was not built (fetch.sh --no-hadith).
    if (PAKETLER / "hadis" / "veri.sqlite").exists():
        for kimlik, dil, baslik, metin in oku("hadis", "SELECT kimlik, dil, baslik, metin FROM hadis"):
            ekle(f"h:hadeethenc:{kimlik}", "hadis", f"hadis-{dil}", f"{baslik} {metin}", dil == "tr")
    else:
        print("  hadis pack missing: index built without hadiths")

    def doldur(db) -> None:
        db.executemany("INSERT INTO belge VALUES(?,?,?,?,?)", satirlar)
        db.execute("INSERT INTO belge(belge) VALUES('optimize')")
        print(f"  {len(satirlar)} entries")

    paket_yaz({
        "id": "arama",
        "art": "arama",
        "sprache": "mul",
        "titel": "Arama dizini",
        "quelle": "Kıblegâh, generated from the packs meal-*, okunus-*, dualar, esma, hadis (tools/content/arama.py)",
        "quelle_url": "https://tanzil.net",
        "lizenz": "same as the source packs",
        "store_tauglich": True,
        "version": "1.0.0",
        "textstand": None,
    }, SEMA, doldur)


if __name__ == "__main__":
    main()
