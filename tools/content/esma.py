"""Builds the `esma` pack: Asma ul-Husna in the Tirmidhi order (Allah + 98 names).

Sources (Wikipedia, CC BY-SA 4.0, with attribution):
- EN "Names of God in Islam": order, vocalised Arabic, transliteration, meaning.
- DE "99 Namen Allahs": meanings.
- TR (`okunus_tr`, `anlam_tr`): `esma_tr.json` next to this script. Own wording, following
  the sense of Diyanet, the TDV İslâm Ansiklopedisi and others, independently reviewed; no source
  text is copied. Matched by number and checked against the Arabic of the base list.
- `esma_fix.json`: reviewed corrections of single EN/DE meanings from Wikipedia, each with its
  reason and sources (applied after the import).
The tables use different orders; they are joined on the Arabic consonant skeleton
without harakat and article. If there is no match, the field stays empty instead of
inventing something. `inceleme: ungeprüft` (not yet reviewed).
"""

import html
import json
import re
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script directory from sys.path
from ortak import kaynak, paket_yaz  # noqa: E402

# English Wikipedia gives 59:23 for al-Bari' and al-Musawwir; both occur in 59:24.
AYET_DUZELT = {13: "Q59:24", 14: "Q59:24"}

SEMA = """
CREATE TABLE esma(
    no INTEGER PRIMARY KEY, arapca TEXT NOT NULL, latin TEXT NOT NULL, okunus_tr TEXT,
    anlam_tr TEXT, anlam_de TEXT, anlam_en TEXT, kaynak_ayet TEXT);
"""


def satirlar(dosya: str) -> list[list[str]]:
    h = kaynak(dosya).read_text(encoding="utf-8")
    tablolar = re.findall(r'<table class="wikitable[^"]*".*?</table>', h, flags=re.S)
    tablo = max(tablolar, key=lambda t: t.count("<tr"))
    sonuc = []
    for tr in re.findall(r"<tr.*?</tr>", tablo, flags=re.S):
        hucreler = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", tr, flags=re.S)
        temiz = [html.unescape(re.sub(r"<sup.*?</sup>|<[^>]+>", "", c)).strip() for c in hucreler]
        if temiz and temiz[0].isdigit():
            sonuc.append(temiz)
    return sonuc


def iskelet(ar: str) -> str:
    s = "".join(c for c in unicodedata.normalize("NFKD", ar) if unicodedata.category(c) == "Lo")
    s = s.replace("ٱ", "ا").replace("أ", "ا").replace("إ", "ا").replace("ى", "ي")
    s = re.sub(r"^ال", "", s)
    # Spelling variants across sources: hamza carriers and waw (رءوف/رؤوف/رؤف) and final ya (متعال/متعالي)
    s = s.replace("ؤ", "و").replace("ء", "")
    return {"متعال": "متعالي", "رووف": "روف"}.get(s, s)


def anlam(m: str) -> str:
    m = re.sub(r"\[\d+\]", "", m).strip().strip('"\'„“”').strip()
    return m


def tr_kayitlari(en: list[list[str]]) -> dict[int, tuple[str, str]]:
    """`esma_tr.json` by number; stops if a name does not match the Arabic of the base list."""
    veri = json.loads((Path(__file__).resolve().parent / "esma_tr.json").read_text(encoding="utf-8"))
    if [e["nr"] for e in veri] != list(range(1, 100)):
        sys.exit("esma_tr.json: expected the numbers 1 to 99 in order")
    farkli = [(e["nr"], e["arabisch"], r[1]) for e, r in zip(veri, en)
              if int(r[0]) != e["nr"] or iskelet(e["arabisch"]) != iskelet(r[1])]
    if farkli:
        sys.exit(f"esma_tr.json does not match the base list: {farkli}")
    return {e["nr"]: (e["okunus_tr"], e["anlam_tr"]) for e in veri}


SUTUN = {"anlam_de": 5, "anlam_en": 6}


def duzeltmeler(kayitlar: list[tuple]) -> list[tuple]:
    """Applies `esma_fix.json` (reviewed corrections of single Wikipedia meanings, with reason and
    sources) after the import. Each entry names the old value: if Wikipedia changes, the build stops."""
    veri = json.loads((Path(__file__).resolve().parent / "esma_fix.json").read_text(encoding="utf-8"))
    sonuc = [list(k) for k in kayitlar]
    for f in veri:
        k = sonuc[f["nr"] - 1]
        i = SUTUN[f["feld"]]
        if k[0] != f["nr"] or iskelet(k[1]) != iskelet(f["arabisch"]) or k[i] != f["alt"]:
            sys.exit(f"esma_fix.json: no. {f['nr']} {f['feld']} is {k[i]!r}, expected {f['alt']!r}")
        k[i] = f["neu"]
    return [tuple(k) for k in sonuc]


def main() -> None:
    en = satirlar("esma-en.html")
    de = {iskelet(r[1]): anlam(r[3]) for r in satirlar("esma-de.html") if len(r) >= 4}
    assert len(en) == 99, len(en)
    tr = tr_kayitlari(en)
    kayitlar = []
    eksik_de = []
    for r in en:
        no, ar, ref, latin, ceviri = int(r[0]), r[1], r[2], r[3], anlam(r[4])
        d = de.get(iskelet(ar))
        if no == 1:
            d = d or "Gott"
        if d is None:
            eksik_de.append(latin)
        kayit = AYET_DUZELT.get(no, re.sub(r"\*+", "", ref).strip())
        okunus_tr, anlam_tr = tr.get(no, (None, None))
        kayitlar.append((no, ar, latin, okunus_tr, anlam_tr, d, ceviri, kayit))
    print(f"  without DE: {eksik_de}")
    kayitlar = duzeltmeler(kayitlar)

    def doldur(db) -> None:
        db.executemany("INSERT INTO esma VALUES(?,?,?,?,?,?,?,?)", kayitlar)

    paket_yaz({
        "id": "esma",
        "art": "esma",
        "sprache": "ar",
        "titel": "Esmâü'l-Hüsnâ",
        "quelle": "Wikipedia (EN \"Names of God in Islam\", DE \"99 Namen Allahs\"); TR: own wording, "
                  "following the sense of Diyanet, TDV İslâm Ansiklopedisi and others, independently reviewed; "
                  "single EN/DE corrections with sources in tools/content/esma_fix.json",
        "quelle_url": "https://en.wikipedia.org/wiki/Names_of_God_in_Islam",
        "lizenz": "EN/DE: CC BY-SA 4.0 (Wikipedia contributors); TR: own wording (tools/content/esma_tr.json)",
        "store_tauglich": True,
        "version": "2026-10-18",
        "textstand": None,
        "inceleme": "ungeprüft",
    }, SEMA, doldur)


if __name__ == "__main__":
    main()
