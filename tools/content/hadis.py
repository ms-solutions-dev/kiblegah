"""Builds the `hadis` pack: hadith encyclopedia from HadeethEnc.com (TR, EN, DE).

Per hadith: title, text, attribution (e.g. "Muttafaqun 'alayh"), grade (e.g. "Sahih"),
explanation, lessons and Arabic text - unchanged from the source. Links to verses (`bag`):
the Arabic fields cite Quran passages as "[البقرة: 255]"; the surah name is matched
against the surah table of the kuran-text pack, only unambiguous matches count.
"""

import json
import re
import sqlite3
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script directory from sys.path
from ortak import KAYNAK, PAKETLER, paket_yaz  # noqa: E402

SEMA = """
CREATE TABLE hadis(
    kimlik INTEGER NOT NULL, dil TEXT NOT NULL, baslik TEXT NOT NULL, metin TEXT NOT NULL,
    kaynak TEXT NOT NULL, derece TEXT NOT NULL, aciklama TEXT NOT NULL, faydalar TEXT NOT NULL,
    arapca TEXT NOT NULL, kategoriler TEXT NOT NULL, PRIMARY KEY(kimlik, dil)) WITHOUT ROWID;
CREATE TABLE kategori(
    id INTEGER NOT NULL, dil TEXT NOT NULL, ad TEXT NOT NULL, ust INTEGER, adet INTEGER NOT NULL,
    PRIMARY KEY(id, dil)) WITHOUT ROWID;
CREATE TABLE bag(hadis INTEGER NOT NULL, sure INTEGER NOT NULL, ilk INTEGER NOT NULL, son INTEGER NOT NULL);
CREATE INDEX bag_ayet ON bag(sure, ilk);
CREATE INDEX bag_hadis ON bag(hadis);
"""

ATIF = re.compile(r"[\[(]\s*(?:سورة\s+)?([ء-ي\s]{2,30}?)\s*[:،,]?\s*(\d{1,3})(?:\s*[-–،,و]\s*(\d{1,3}))?\s*[\])]")


def sade(ad: str) -> str:
    s = "".join(c for c in unicodedata.normalize("NFKD", ad) if unicodedata.category(c) == "Lo")
    for a, b in (("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ٱ", "ا"), ("ى", "ي"), ("ة", "ه")):
        s = s.replace(a, b)
    return s.removeprefix("سوره").removeprefix("ال")


def liste(deger) -> list:
    if isinstance(deger, list):
        return deger
    try:
        return json.loads(deger.replace("'", '"')) if deger else []
    except ValueError:
        return [deger] if deger else []


def main() -> None:
    kuran = sqlite3.connect(f"file:{PAKETLER / 'kuran-text' / 'veri.sqlite'}?mode=ro", uri=True)
    sureler = {sade(ad): (no, n) for no, ad, n in kuran.execute("SELECT no, ad_ar, ayet_sayisi FROM sure")}
    hadisler, kategoriler, baglar = [], [], set()
    for dil in ("tr", "en", "de"):
        klasor = KAYNAK / "hadis" / dil
        kats = json.loads((klasor / "kategoriler.json").read_text(encoding="utf-8"))
        for k in kats:
            kategoriler.append((int(k["id"]), dil, k["title"], int(k["parent_id"]) if k.get("parent_id") else None,
                                int(k.get("hadeeths_count") or 0)))
        for f in sorted(klasor.glob("[0-9]*.json")):
            d = json.loads(f.read_text(encoding="utf-8"))
            if not d.get("hadeeth"):
                continue
            kimlik = int(d["id"])
            hadisler.append((
                kimlik, dil, d.get("title", ""), d["hadeeth"], d.get("attribution", ""), d.get("grade", ""),
                d.get("explanation", ""), json.dumps([h.strip() for h in liste(d.get("hints")) if h.strip()], ensure_ascii=False),
                d.get("hadeeth_ar", ""), ",".join(str(c) for c in liste(d.get("categories")))))
            metin = " ".join(str(d.get(a, "")) for a in ("hadeeth_ar", "explanation_ar", "hints_ar"))
            for ad, ilk, son in ATIF.findall(metin):
                s = sureler.get(sade(ad))
                ilk_i = int(ilk)
                son_i = int(son) if son and int(son) >= ilk_i else ilk_i
                if s and 1 <= ilk_i <= son_i <= s[1]:
                    baglar.add((kimlik, s[0], ilk_i, son_i))
    # In some translations HadeethEnc gives the attribution line only in Arabic ("رواه مسلم");
    # in that case take the English or Turkish line of the same hadith.
    quelle = {(h[0], h[1]): h[4] for h in hadisler}
    arapca = re.compile(r"[\u0600-\u06FF]")
    ersetzt = 0
    for i, h in enumerate(hadisler):
        if h[1] != "ar" and arapca.search(h[4]):
            yedek = next((quelle.get((h[0], d)) for d in ("en", "tr")
                          if quelle.get((h[0], d)) and not arapca.search(quelle[(h[0], d)])), None)
            if yedek:
                hadisler[i] = h[:4] + (yedek,) + h[5:]
                ersetzt += 1
    print(f"  {len(hadisler)} hadith texts, {len(kategoriler)} categories, {len(baglar)} verse links,"
          f" {ersetzt} Arabic attribution lines replaced")

    def doldur(db) -> None:
        db.executemany("INSERT OR REPLACE INTO hadis VALUES(?,?,?,?,?,?,?,?,?,?)", hadisler)
        db.executemany("INSERT OR REPLACE INTO kategori VALUES(?,?,?,?,?)", kategoriler)
        db.executemany("INSERT INTO bag VALUES(?,?,?,?)", sorted(baglar))

    paket_yaz({
        "id": "hadis",
        "art": "hadis",
        "sprache": "mul",
        "titel": "Hadis Ansiklopedisi",
        "quelle": "HadeethEnc.com – Encyclopedia of Translated Prophetic Hadiths",
        "quelle_url": "https://hadeethenc.com",
        "lizenz": "HadeethEnc terms: unchanged, with source; not for sale",
        "store_tauglich": True,
        "version": "2026-10-18",
        "textstand": None,
    }, SEMA, doldur)


if __name__ == "__main__":
    main()
