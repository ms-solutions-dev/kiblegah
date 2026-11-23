"""Builds the `dualar` pack: supplications from the Quran, stored as keys into verses.

Quranic duas only: Arabic, translation and transliteration come unchanged from the other
packs, the source is the verse itself - nothing is quoted from memory. The selection is
manual: a search for "Rabbana" would also find words of the people of Hell (23:107, 33:67)
or requests the Quran censures (2:200). The basis is the widespread collection of the
"40 Rabbana" duas plus the duas of the prophets. Every passage is checked: it must contain
an address "Rabb". `inceleme: ungeprüft` (not yet reviewed) until a scholar has reviewed
the selection.
"""

import sqlite3
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script directory from sys.path
from ortak import PAKETLER, TEXTSTAND, paket_yaz  # noqa: E402

# (kategori, sure, ilk ayet, son ayet)
DUALAR = [
    # Rabbenâ duaları
    ("rabbena", 2, 127, 127), ("rabbena", 2, 128, 128), ("rabbena", 2, 201, 201), ("rabbena", 2, 250, 250),
    ("rabbena", 2, 286, 286), ("rabbena", 3, 8, 8), ("rabbena", 3, 9, 9), ("rabbena", 3, 16, 16),
    ("rabbena", 3, 53, 53), ("rabbena", 3, 147, 147), ("rabbena", 3, 191, 191), ("rabbena", 3, 192, 192),
    ("rabbena", 3, 193, 193), ("rabbena", 3, 194, 194), ("rabbena", 5, 83, 83), ("rabbena", 7, 23, 23),
    ("rabbena", 7, 47, 47), ("rabbena", 7, 89, 89), ("rabbena", 7, 126, 126), ("rabbena", 10, 85, 86),
    ("rabbena", 14, 38, 38), ("rabbena", 14, 41, 41), ("rabbena", 18, 10, 10), ("rabbena", 23, 109, 109),
    ("rabbena", 25, 65, 66), ("rabbena", 25, 74, 74), ("rabbena", 40, 7, 9), ("rabbena", 59, 10, 10),
    ("rabbena", 60, 4, 5), ("rabbena", 66, 8, 8),
    # Peygamberlerin duaları
    ("peygamber", 2, 126, 126), ("peygamber", 14, 35, 35), ("peygamber", 14, 40, 40), ("peygamber", 26, 83, 85),
    ("peygamber", 37, 100, 100), ("peygamber", 3, 38, 38), ("peygamber", 19, 4, 5), ("peygamber", 21, 89, 89),
    ("peygamber", 21, 83, 83), ("peygamber", 21, 87, 87), ("peygamber", 20, 25, 28), ("peygamber", 28, 16, 16),
    ("peygamber", 28, 24, 24), ("peygamber", 7, 151, 151), ("peygamber", 11, 47, 47), ("peygamber", 71, 28, 28),
    ("peygamber", 27, 19, 19), ("peygamber", 12, 101, 101), ("peygamber", 23, 118, 118),
    # Anne baba ve aile
    ("aile", 17, 24, 24), ("aile", 46, 15, 15),
    # İlim
    ("ilim", 20, 114, 114),
]

ADLAR = {"rabbena": 1, "peygamber": 2, "aile": 3, "ilim": 4}

SEMA = """
CREATE TABLE dua(
    slug TEXT PRIMARY KEY, kategori TEXT NOT NULL, sure INTEGER NOT NULL, ilk INTEGER NOT NULL,
    son INTEGER NOT NULL, ilk_kelime INTEGER NOT NULL, sira INTEGER NOT NULL,
    son_kelime INTEGER NOT NULL DEFAULT 0) WITHOUT ROWID;
CREATE TABLE kategori(id TEXT PRIMARY KEY, sira INTEGER NOT NULL) WITHOUT ROWID;
"""


# Duas that end before the end of the verse: this word (base letters) is no longer part of it.
# 2:126 - followed by Allah's answer "Qala wa man kafara ..."; 28:16 - followed by the narration
# "Fa-ghafara lahu ...". 0 = until the end of the verse.
SONLAR = {(2, 126): "قال", (28, 16): "فغفر"}


def iskelet(kelime: str) -> str:
    """Only the base letters (without marks and alif variants)."""
    s = "".join(c for c in kelime if unicodedata.category(c) == "Lo")
    return s.replace("ٱ", "ا").replace("آ", "ا")


def main() -> None:
    kuran = sqlite3.connect(f"file:{PAKETLER / 'kuran-text' / 'veri.sqlite'}?mode=ro", uri=True)
    satirlar = []
    sira = 0
    gorulen = set()
    for kat, s, ilk, son in DUALAR:
        kelimeler = [r[0] for r in kuran.execute(
            "SELECT metin FROM kelime WHERE sure=? AND ayet=? ORDER BY sira", (s, ilk))]
        assert kelimeler, (s, ilk)
        # First address: "Rabbana" with fatha (رَبَّنَا) or "Rabbi" with kasra (رَبِّ). "Rabbuna"
        # (7:89) and "rabbina" (7:126) are not an address and do not count.
        bas = None
        for i, k in enumerate(kelimeler):
            sk = iskelet(k).removeprefix("و").removeprefix("ف")
            if (sk == "ربنا" and "\u0628\u0651\u064e\u0646" in k) or (sk == "رب" and "\u0628\u0651\u0650" in k):
                bas = i + 1
                break
        if (s, ilk) == (21, 87):  # Yunus: "la ilaha illa anta ..."
            bas = next(i + 1 for i, k in enumerate(kelimeler) if iskelet(k) == "لا")
        if (s, ilk) == (21, 83):  # Ayyub: after "nada rabbahu"
            bas = next(i + 2 for i, k in enumerate(kelimeler) if iskelet(k) == "ربه")
        assert bas is not None, f"no Rabb address in {s}:{ilk}"
        slug = f"{s}-{ilk}" if ilk == son else f"{s}-{ilk}-{son}"
        assert slug not in gorulen, slug
        gorulen.add(slug)
        sira += 1
        bitis = 0
        if (s, son) in SONLAR:
            sonkiler = [r[0] for r in kuran.execute(
                "SELECT metin FROM kelime WHERE sure=? AND ayet=? ORDER BY sira", (s, son))]
            bitis = next(i for i, k in enumerate(sonkiler) if i >= (bas if son == ilk else 0)
                         and iskelet(k) == SONLAR[(s, son)])
        satirlar.append((slug, kat, s, ilk, son, bas, sira, bitis))
        print(f"  {kat:9} {s}:{ilk}{'-' + str(son) if son != ilk else ''}  from word {bas}: {kelimeler[bas - 1]}")

    def doldur(db) -> None:
        db.executemany("INSERT INTO dua VALUES(?,?,?,?,?,?,?,?)", satirlar)
        db.executemany("INSERT INTO kategori VALUES(?,?)", ADLAR.items())

    paket_yaz({
        "id": "dualar",
        "art": "dua",
        "sprache": "ar",
        "titel": "Kur'an'dan dualar",
        "quelle": "The Quran (Tanzil text); selection by Kıblegâh based on the \"40 Rabbana\" collection",
        "quelle_url": "https://tanzil.net",
        "lizenz": "Verses CC BY 3.0 (Tanzil); selection own work",
        "store_tauglich": True,
        "version": "1.0.0",
        "textstand": TEXTSTAND,
        "inceleme": "ungeprüft",
    }, SEMA, doldur)


if __name__ == "__main__":
    main()
