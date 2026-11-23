"""Builds the `tecvid` pack: tajweed rule spans from cpfair/quran-tajweed (CC BY 4.0).

The spans are Unicode code point offsets into the unchanged Tanzil text (April 2017
copy) including the Basmala prefix; the pack is therefore tied to the text revision
of the Quran pack.
"""

import json
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script directory from sys.path
from ortak import TEXTSTAND, kaynak, paket_yaz, tanzil_satirlari  # noqa: E402

SEMA = """
CREATE TABLE tecvid(
    sure INTEGER NOT NULL, ayet INTEGER NOT NULL, kural TEXT NOT NULL,
    bas INTEGER NOT NULL, son INTEGER NOT NULL);
CREATE INDEX tecvid_ayet ON tecvid(sure, ayet);
"""


def main() -> None:
    with zipfile.ZipFile(kaynak("cpfair.zip")) as z:
        veri = json.loads(z.read("quran-tajweed-master/output/tajweed.hafs.uthmani-pause-sajdah.json"))
    metinler = {(s, a): m for s, a, m in tanzil_satirlari(kaynak("quran-uthmani-2017.txt"))}
    satirlar = []
    for v in veri:
        s, a = v["surah"], v["ayah"]
        uzunluk = len(metinler[(s, a)])
        for n in v["annotations"]:
            assert 0 <= n["start"] < n["end"] <= uzunluk, (s, a, n)
            satirlar.append((s, a, n["rule"], n["start"], n["end"]))
    assert len(veri) == 6236

    def doldur(db) -> None:
        db.executemany("INSERT INTO tecvid VALUES(?,?,?,?,?)", satirlar)
        print(f"  {len(satirlar)} spans")

    paket_yaz({
        "id": "tecvid",
        "art": "tecvid",
        "sprache": "ar",
        "titel": "Tecvid renkleri",
        "quelle": "cpfair/quran-tajweed (Collin Fair)",
        "quelle_url": "https://github.com/cpfair/quran-tajweed",
        "lizenz": "CC BY 4.0",
        "store_tauglich": True,
        "version": "2021.10",
        "textstand": TEXTSTAND,
    }, SEMA, doldur)


if __name__ == "__main__":
    main()
