"""Builds the `kuran-text` pack: Tanzil Uthmani (April 2017 copy) at word level.

The Tanzil text stays unchanged (license). Word boundaries are stored alongside as Unicode
code point offsets, as is the Basmala prefix that Tanzil writes before verse 1 of every
surah (except 1 and 9). Word numbers count from the verse itself, as on Quran.com.
"""

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script directory from sys.path
from ortak import (TEXT_SHA256, TEXTSTAND, kaynak, paket_yaz, sha256,  # noqa: E402
                   tanzil_satirlari)

SEMA = """
CREATE TABLE sure(
    no INTEGER PRIMARY KEY, ayet_sayisi INTEGER NOT NULL, ilk_sira INTEGER NOT NULL,
    ad_ar TEXT NOT NULL, ad_tr TEXT NOT NULL, ad_latin TEXT NOT NULL, anlam_en TEXT NOT NULL,
    inis TEXT NOT NULL, nuzul_sirasi INTEGER NOT NULL, ruku_sayisi INTEGER NOT NULL,
    besmele INTEGER NOT NULL);
CREATE TABLE ayet(
    sira INTEGER PRIMARY KEY, sure INTEGER NOT NULL, ayet INTEGER NOT NULL,
    metin TEXT NOT NULL, besmele_son INTEGER NOT NULL, kelime_sayisi INTEGER NOT NULL,
    cuz INTEGER NOT NULL, hizb_ceyrek INTEGER NOT NULL, secde TEXT,
    UNIQUE(sure, ayet));
CREATE TABLE kelime(
    sure INTEGER NOT NULL, ayet INTEGER NOT NULL, sira INTEGER NOT NULL,
    metin TEXT NOT NULL, bas INTEGER NOT NULL, son INTEGER NOT NULL,
    PRIMARY KEY(sure, ayet, sira)) WITHOUT ROWID;
CREATE TABLE mushaf(id TEXT PRIMARY KEY, ad TEXT NOT NULL, sayfa_sayisi INTEGER NOT NULL) WITHOUT ROWID;
CREATE TABLE sayfa(
    mushaf TEXT NOT NULL, no INTEGER NOT NULL, ilk_sira INTEGER NOT NULL, son_sira INTEGER NOT NULL,
    PRIMARY KEY(mushaf, no)) WITHOUT ROWID;
CREATE TABLE cuz(no INTEGER PRIMARY KEY, ilk_sira INTEGER NOT NULL, son_sira INTEGER NOT NULL);
CREATE TABLE hizb_ceyrek(no INTEGER PRIMARY KEY, ilk_sira INTEGER NOT NULL, son_sira INTEGER NOT NULL);
CREATE INDEX ayet_sure ON ayet(sure, ayet);
"""

SURE_ADLARI = Path(__file__).resolve().parent / "sure_adlari.txt"


def araliklar(baslangiclar: list[int], toplam: int) -> list[tuple[int, int, int]]:
    """From the 1-based start positions of each section, the ranges (no, ilk, son)."""
    sonuc = []
    for i, ilk in enumerate(baslangiclar):
        son = baslangiclar[i + 1] - 1 if i + 1 < len(baslangiclar) else toplam
        sonuc.append((i + 1, ilk, son))
    return sonuc


def main() -> None:
    metin_dosyasi = kaynak("quran-uthmani-2017.txt")
    if sha256(metin_dosyasi) != TEXT_SHA256:
        raise SystemExit("quran-uthmani-2017.txt is not the expected revision (tajweed spans would not match)")
    veri = ET.parse(kaynak("quran-data.xml")).getroot()
    sureler = veri.find("suras").findall("sura")
    adlar_tr = [s.strip() for s in SURE_ADLARI.read_text(encoding="utf-8").splitlines()
                if s.strip() and not s.startswith("#")]
    assert len(sureler) == 114 and len(adlar_tr) == 114, (len(sureler), len(adlar_tr))

    baslangic = {int(s.get("index")): int(s.get("start")) for s in sureler}

    def sira(s: int, a: int) -> int:
        return baslangic[s] + a

    ayetler = list(tanzil_satirlari(metin_dosyasi))
    assert len(ayetler) == 6236
    besmele = next(m for s, a, m in ayetler if s == 1 and a == 1) + " "

    def bolum(etiket: str, alt: str) -> list[int]:
        return [sira(int(e.get("sura")), int(e.get("aya"))) for e in veri.find(etiket).findall(alt)]

    cuzler = araliklar(bolum("juzs", "juz"), 6236)
    ceyrekler = araliklar(bolum("hizbs", "quarter"), 6236)
    sayfalar = araliklar(bolum("pages", "page"), 6236)
    # Tanzil lists 15 prostration places; per the Hanafi school and Diyanet, Surah al-Hajj has
    # only 22:18, 22:77 is not a prostration of recitation (sajdat al-tilawa).
    secdeler = {sira(int(e.get("sura")), int(e.get("aya"))): e.get("type")
                for e in veri.find("sajdas").findall("sajda")
                if (e.get("sura"), e.get("aya")) != ("22", "77")}
    assert len(secdeler) == 14
    assert len(cuzler) == 30 and len(ceyrekler) == 240 and len(sayfalar) == 604

    def bul(araliklar_: list, n: int) -> int:
        return next(no for no, ilk, son in araliklar_ if ilk <= n <= son)

    def doldur(db) -> None:
        for s, ad_tr in zip(sureler, adlar_tr):
            no = int(s.get("index"))
            db.execute("INSERT INTO sure VALUES(?,?,?,?,?,?,?,?,?,?,?)", (
                no, int(s.get("ayas")), int(s.get("start")) + 1, s.get("name"), ad_tr,
                s.get("tname"), s.get("ename"),
                "mekki" if s.get("type") == "Meccan" else "medeni",
                int(s.get("order")), int(s.get("rukus")), 0 if no in (1, 9) else 1))
        kelime_toplam = 0
        for s, a, metin in ayetler:
            bas = 0
            if a == 1 and s not in (1, 9):
                # 95 and 97 carry a shadda on the ba (Tanzil quirk); otherwise identical.
                vorsatz = " ".join(metin.split(" ")[:4]) + " "
                assert vorsatz.replace("\u0651", "", 1) == besmele or vorsatz == besmele, (s, a)
                bas = len(vorsatz)
            kelimeler = []
            konum = bas
            for parca in metin[bas:].split(" "):
                kelimeler.append((parca, konum, konum + len(parca)))
                konum += len(parca) + 1
            n = sira(s, a)
            db.execute("INSERT INTO ayet VALUES(?,?,?,?,?,?,?,?,?)", (
                n, s, a, metin, bas, len(kelimeler), bul(cuzler, n), bul(ceyrekler, n),
                secdeler.get(n)))
            db.executemany("INSERT INTO kelime VALUES(?,?,?,?,?,?)", [
                (s, a, i + 1, k, b, e) for i, (k, b, e) in enumerate(kelimeler)])
            kelime_toplam += len(kelimeler)
        db.execute("INSERT INTO mushaf VALUES('medine-604', 'Medine Mushafı', 604)")
        db.executemany("INSERT INTO sayfa VALUES('medine-604',?,?,?)", sayfalar)
        db.executemany("INSERT INTO cuz VALUES(?,?,?)", cuzler)
        db.executemany("INSERT INTO hizb_ceyrek VALUES(?,?,?)", ceyrekler)
        db.execute("INSERT INTO bilgi VALUES('besmele', ?)", (besmele.strip(),))
        db.execute("INSERT INTO bilgi VALUES('telif', ?)", (TELIF,))
        print(f"  {kelime_toplam} words")

    paket_yaz({
        "id": "kuran-text",
        "art": "kuran-text",
        "sprache": "ar",
        "titel": "Kur'an-ı Kerim (Uthmani)",
        "quelle": "Tanzil.net, Uthmani 1.0.2 (April 2017 copy); metadata quran-data.xml",
        "quelle_url": "https://tanzil.net",
        "lizenz": "CC BY 3.0 – unchanged, cite Tanzil.net as the source with a link",
        "store_tauglich": True,
        "version": "2017.04.1",
        "textstand": TEXTSTAND,
    }, SEMA, doldur)


TELIF = """Tanzil Quran Text (Uthmani, version 1.0.2)
Copyright (C) 2008-2010 Tanzil.net
License: Creative Commons Attribution 3.0
Permission is granted to copy and distribute verbatim copies of this text, but CHANGING IT IS NOT ALLOWED.
This quran text can be used in any website or application, provided its source (Tanzil.net) is clearly
indicated, and a link is made to http://tanzil.net to enable users to keep track of changes."""

if __name__ == "__main__":
    main()
