"""Builds `okunus-tr` and `okunus-en`: rule-based transliteration of the Uthmani text.

First version. The rules cover harakat, shadda, tanwin, long-vowel letters, hamzat al-wasl
including sun-letter assimilation, the word Allah, iqlab, the disjointed letters
(huruf muqatta'at) and the pause rules at the end of a verse. The result still needs a
scholar's review; the manifest says `inceleme: "ungeprüft"` (not yet reviewed) and the
app shows that.

Each word becomes a sound sequence of tokens ("K" consonant, "U" vowel). From these the
verse is assembled: words with a silent hamzat al-wasl attach their first consonant to
the previous word, as it is read ("rabbil 'âlemîn").
"""

import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script directory from sys.path
from ortak import PAKETLER, TEXTSTAND, paket_yaz  # noqa: E402

FETHA, KESRE, ZAMME = "َ", "ِ", "ُ"
FETHATEYN, KESRETEYN, ZAMMETEYN = "ً", "ٍ", "ٌ"
SEDDE, SUKUN, MED = "ّ", "ْ", "ٓ"
HEMZE_UST, ELIF_KUCUK = "ٔ", "ٰ"
SIFIR_YUVARLAK, SIFIR_DIK = "۟", "۠"
IKLAB_UST, IKLAB_ALT = "ۢ", "ۭ"
KUCUK_VAV, KUCUK_YE = "ۥ", "ۦ"
TATWEEL, ELIF, ELIF_VASL, ELIF_MAKSURA = "ـ", "ا", "ٱ", "ى"
VAV, YE, TE_MERBUTA, LAM, HE = "و", "ي", "ة", "ل", "ه"
HEMZELER = "ءأؤإئ"
HAREKELER = {FETHA, KESRE, ZAMME, FETHATEYN, KESRETEYN, ZAMMETEYN}
IZ = HAREKELER | {SUKUN, SEDDE}

KALIN = set("خصضطظغقحعر")  # "a"/"u" instead of "e"/"ü" in Turkish
KALIN_KESRE = set("خصضطظغق")  # "ı" instead of "i"

HARF = {
    "tr": {"ب": "b", "ت": "t", "ث": "s", "ج": "c", "ح": "h", "خ": "h", "د": "d", "ذ": "z",
           "ر": "r", "ز": "z", "س": "s", "ش": "ş", "ص": "s", "ض": "d", "ط": "t", "ظ": "z",
           "ع": "'", "غ": "ğ", "ف": "f", "ق": "k", "ك": "k", "ل": "l", "م": "m", "ن": "n",
           "ه": "h", "و": "v", "ي": "y", "ى": "y", "ة": "t", "ء": "'", "أ": "'", "إ": "'",
           "ؤ": "'", "ئ": "'", "ا": "'"},
    "en": {"ب": "b", "ت": "t", "ث": "th", "ج": "j", "ح": "h", "خ": "kh", "د": "d", "ذ": "dh",
           "ر": "r", "ز": "z", "س": "s", "ش": "sh", "ص": "s", "ض": "d", "ط": "t", "ظ": "z",
           "ع": "'", "غ": "gh", "ف": "f", "ق": "q", "ك": "k", "ل": "l", "م": "m", "ن": "n",
           "ه": "h", "و": "w", "ي": "y", "ى": "y", "ة": "t", "ء": "'", "أ": "'", "إ": "'",
           "ؤ": "'", "ئ": "'", "ا": "'"},
}

HARF_ADI = {
    "tr": {"ا": "elif", "ل": "lâm", "م": "mîm", "ص": "sâd", "ر": "râ", "ك": "kâf", "ه": "hâ",
           "ي": "yâ", "ع": "ayn", "ط": "tâ", "س": "sîn", "ح": "hâ", "ق": "kâf", "ن": "nûn"},
    "en": {"ا": "alif", "ل": "laam", "م": "meem", "ص": "saad", "ر": "raa", "ك": "kaaf", "ه": "haa",
           "ي": "yaa", "ع": "'ayn", "ط": "taa", "س": "seen", "ح": "haa", "ق": "qaaf", "ن": "noon"},
}


@dataclass
class Birim:
    """A base letter with its marks."""
    harf: str
    isaret: set = field(default_factory=set)


@dataclass
class Ses:
    tur: str  # "K" or "U"
    yazi: str
    uzun: bool = False
    kisa: str = ""  # short form of a long vowel (before hamzat al-wasl)


def birimler(kelime: str) -> list[Birim]:
    sonuc: list[Birim] = []
    for h in kelime:
        kat = unicodedata.category(h)
        if h == HEMZE_UST and sonuc:
            sonuc[-1].isaret.add(h)
        elif kat == "Mn":
            if sonuc:
                sonuc[-1].isaret.add(h)
        else:
            sonuc.append(Birim(h))
    return sonuc


def harekesiz(b: Birim) -> bool:
    return not (b.isaret & IZ)


def unlu(dil: str, harf: str, hareke: str, uzun: bool, sonraki: Birim | None = None) -> Ses:
    if dil == "en":
        kisa = {"a": "a", "i": "i", "u": "u"}[hareke]
        return Ses("U", {"a": "aa", "i": "ee", "u": "oo"}[hareke] if uzun else kisa, uzun, kisa)
    if hareke == "a":
        kalin_komsu = sonraki is not None and (
            sonraki.harf in KALIN_KESRE or (sonraki.harf in "عح" and SUKUN in sonraki.isaret))
        kisa = "a" if harf in KALIN or kalin_komsu else "e"
        return Ses("U", "â" if uzun else kisa, uzun, kisa)
    if hareke == "i":
        kisa = "ı" if harf in KALIN_KESRE else "i"
        return Ses("U", "î" if uzun else kisa, uzun, kisa)
    kisa = "u" if harf in KALIN else "ü"
    return Ses("U", "û" if uzun else kisa, uzun, kisa)


def mukattaa(bs: list[Birim]) -> bool:
    """Disjointed letters: a word without any harakat (e.g. الٓمٓ, طه)."""
    return all(harekesiz(b) for b in bs) and any(b.harf in HARF_ADI["tr"] for b in bs)


def kelime_sesleri(kelime: str, dil: str, baslangic: bool) -> tuple[list[Ses], bool]:
    """Sound sequence of a word; second value: starts with a silent hamzat al-wasl."""
    bs = birimler(kelime)
    if mukattaa(bs):
        adlar = [HARF_ADI[dil][b.harf] for b in bs if b.harf in HARF_ADI[dil]]
        return [Ses("K", " ".join(adlar))], False
    sesler: list[Ses] = []
    vasl = False
    i = 0
    while i < len(bs):
        b = bs[i]
        h = b.harf
        sonraki = bs[i + 1] if i + 1 < len(bs) else None
        if h == ELIF_VASL:
            if i == 0 and not baslangic:
                vasl = True
            elif i == 0:
                makale = sonraki is not None and sonraki.harf == LAM
                lafza = makale and len(bs) > 2 and bs[2].harf == LAM and SEDDE in bs[2].isaret
                ucuncu = bs[2] if len(bs) > 2 else None
                if makale:
                    sesler.append(Ses("U", "a" if (dil == "en" or lafza) else "e"))
                elif ucuncu is not None and ZAMME in ucuncu.isaret:
                    sesler.append(Ses("U", "u"))
                else:
                    sesler.append(Ses("U", "i"))
            i += 1
            continue
        if h == TATWEEL and HEMZE_UST in b.isaret:
            # Hamza on the tatweel (مَسْـُٔولًا, شَىْـًٔا): read it as a hamza.
            b.harf = h = "ء"
        elif h == TATWEEL:
            if ELIF_KUCUK in b.isaret and sesler and sesler[-1].tur == "U":
                sesler[-1] = unlu(dil, "", "a", True) if dil == "en" else Ses("U", "â", True, sesler[-1].kisa)
            i += 1
            continue
        if h in (KUCUK_VAV, KUCUK_YE):
            if sesler and sesler[-1].tur == "U" and not sesler[-1].uzun:
                son = sesler[-1]
                sesler[-1] = Ses("U", {"tr": {"u": "û", "ü": "û", "i": "î", "ı": "î"},
                                       "en": {"u": "oo", "i": "ee"}}[dil].get(son.yazi, son.yazi),
                                 True, son.yazi)
            i += 1
            continue
        if b.isaret & {SIFIR_YUVARLAK, SIFIR_DIK}:
            i += 1
            continue
        # Assimilation (sun-letter lam, idgham within a word): unmarked letter before a letter with shadda.
        if harekesiz(b) and h not in (ELIF, ELIF_MAKSURA, YE, VAV) and sonraki is not None \
                and SEDDE in sonraki.isaret and MED not in b.isaret:
            i += 1
            continue
        # Long-vowel letters without their own mark after a matching vowel.
        if harekesiz(b) and h in (ELIF, ELIF_MAKSURA, YE, VAV) and sesler and sesler[-1].tur == "U":
            onceki = sesler[-1]
            if onceki.uzun:
                i += 1
                continue
            if onceki.yazi in ("an", "en"):  # fathatayn + silent alif/ya
                i += 1
                continue
            kisa = onceki.yazi
            tur = {"a": "a", "e": "a", "i": "i", "ı": "i", "u": "u", "ü": "u"}.get(kisa)
            if (h in (ELIF, ELIF_MAKSURA) and tur == "a") or (h in (YE, ELIF_MAKSURA) and tur == "i") \
                    or (h == VAV and tur == "u"):
                sesler[-1] = unlu(dil, onceki_harf(bs, i), tur, True)
                i += 1
                continue
            if h in (ELIF, ELIF_MAKSURA):
                i += 1
                continue
        if h == ELIF and MED in b.isaret and harekesiz(b) and not sesler:
            sesler.append(unlu(dil, h, "a", True))
            i += 1
            continue
        if h == ELIF and harekesiz(b):
            i += 1
            continue
        if h in (ELIF_MAKSURA, VAV, YE) and ELIF_KUCUK in b.isaret and harekesiz(b):
            if sesler and sesler[-1].tur == "U":
                sesler[-1] = unlu(dil, onceki_harf(bs, i), "a", True)
            i += 1
            continue
        if h == ELIF and HEMZE_UST in b.isaret:
            h = "أ"
        ses = HARF[dil].get(h)
        if ses is None:
            i += 1
            continue
        if h in HEMZELER + "ا" and not sesler:
            ses = ""
        if (b.isaret & {IKLAB_UST, IKLAB_ALT}) and h == "ن":
            ses = "m"
        if SEDDE in b.isaret and i > 0:
            sesler.append(Ses("K", ses))
        if ses:
            sesler.append(Ses("K", ses))
        hareke = ("a" if FETHA in b.isaret else "i" if KESRE in b.isaret
                  else "u" if ZAMME in b.isaret else None)
        tenvin = ("a" if FETHATEYN in b.isaret else "i" if KESRETEYN in b.isaret
                  else "u" if ZAMMETEYN in b.isaret else None)
        renk = "" if h in HEMZELER + "ا" else h
        if hareke:
            uzun = ELIF_KUCUK in b.isaret or (MED in b.isaret and h not in HEMZELER)
            if lafzatullah(bs, i):
                uzun = True
                renk = "ح"
            sesler.append(unlu(dil, renk, hareke, uzun, sonraki))
        elif tenvin:
            u = unlu(dil, renk, tenvin, False)
            n = "m" if b.isaret & {IKLAB_UST, IKLAB_ALT} else "n"
            sesler.append(Ses("U", u.yazi + n, False, u.yazi))
        i += 1
    return sesler, vasl


def onceki_harf(bs: list[Birim], i: int) -> str:
    for j in range(i - 1, -1, -1):
        if bs[j].harf not in (TATWEEL,):
            return bs[j].harf
    return ""


def lafzatullah(bs: list[Birim], i: int) -> bool:
    """Lam with shadda+fatha between lam and ha (without sukun): "llâh"."""
    b = bs[i]
    if b.harf != LAM or SEDDE not in b.isaret or FETHA not in b.isaret:
        return False
    if i == 0 or bs[i - 1].harf != LAM or i + 1 >= len(bs) or bs[i + 1].harf != HE:
        return False
    return SUKUN not in bs[i + 1].isaret


def vakf(sesler: list[Ses], dil: str, kelime: str) -> list[Ses]:
    """Pause at the end of a verse: final short vowel drops, fathatayn becomes long, ta marbuta becomes h."""
    if not sesler:
        return sesler
    son = sesler[-1]
    te_merbuta = kelime.rstrip("".join(IZ | {ELIF_KUCUK})).endswith(TE_MERBUTA)
    if son.tur == "U" and not son.uzun:
        govde = sesler[:-1]
        if te_merbuta:
            govde = govde[:-1]  # the t
            return govde + ([Ses("K", "h")] if dil == "en" else [])
        if son.yazi.endswith("n") and son.kisa in ("a", "e") and not kelime.endswith(ELIF_MAKSURA):
            return govde + [unlu(dil, "ح" if son.kisa == "a" else "", "a", True)]
        return govde
    return sesler


def yazi(sesler: list[Ses]) -> str:
    return "".join(s.yazi for s in sesler)


def ayet_okunusu(kelimeler: list[str], dil: str) -> tuple[str, list[str]]:
    """One verse: (assembled line, transliteration per word)."""
    parcalar: list[list[Ses]] = []
    vasllar: list[bool] = []
    for i, k in enumerate(kelimeler):
        sesler, vasl = kelime_sesleri(k, dil, baslangic=(i == 0))
        if i == len(kelimeler) - 1:
            sesler = vakf(sesler, dil, k)
        parcalar.append(sesler)
        vasllar.append(vasl)
    # Hamzat al-wasl: the first consonant moves to the previous word, a long final vowel becomes short.
    ekler = [""] * len(kelimeler)
    for i in range(1, len(kelimeler)):
        if not vasllar[i] or not parcalar[i]:
            continue
        onceki = parcalar[i - 1]
        if onceki and onceki[-1].tur == "U" and onceki[-1].uzun and onceki[-1].kisa:
            onceki[-1] = Ses("U", onceki[-1].kisa, False, onceki[-1].kisa)
        elif onceki and (onceki[-1].tur == "K" or onceki[-1].yazi.endswith(("n", "m"))):
            onceki.append(Ses("U", "i"))
        tasinan = []
        while len(parcalar[i]) > 1 and parcalar[i][0].tur == "K" and parcalar[i][1].tur == "K":
            tasinan.append(parcalar[i].pop(0))
        ekler[i - 1] = yazi(tasinan)
        if dil == "tr" and kelimeler[i].startswith(ELIF_VASL + LAM + LAM) and onceki \
                and onceki[-1].tur == "U" and onceki[-1].yazi == "e":
            onceki[-1] = Ses("U", "a", False, "a")
    kelime_yazilari = [yazi(p) + e for p, e in zip(parcalar, ekler)]
    if dil == "tr":
        satir = ""
        for i, k in enumerate(kelime_yazilari):
            ayir = "" if i > 0 and vasllar[i] else " "
            satir += (ayir if satir else "") + k
    else:
        satir = " ".join(kelime_yazilari)
    return buyuk_bas(satir, dil), kelime_yazilari


def buyuk_bas(metin: str, dil: str) -> str:
    if not metin:
        return metin
    ilk = metin[0]
    if dil == "tr":
        ilk = {"i": "İ", "ı": "I"}.get(ilk, ilk.upper())
    else:
        ilk = ilk.upper()
    return ilk + metin[1:]


SEMA = """
CREATE TABLE okunus(
    sure INTEGER NOT NULL, ayet INTEGER NOT NULL, metin TEXT NOT NULL,
    PRIMARY KEY(sure, ayet)) WITHOUT ROWID;
CREATE TABLE kelime_okunus(
    sure INTEGER NOT NULL, ayet INTEGER NOT NULL, sira INTEGER NOT NULL, metin TEXT NOT NULL,
    PRIMARY KEY(sure, ayet, sira)) WITHOUT ROWID;
"""


def main() -> None:
    import sqlite3
    kuran = sqlite3.connect(f"file:{PAKETLER / 'kuran-text' / 'veri.sqlite'}?mode=ro", uri=True)
    ayetler: dict[tuple[int, int], list[str]] = {}
    for s, a, k in kuran.execute("SELECT sure, ayet, metin FROM kelime ORDER BY sure, ayet, sira"):
        ayetler.setdefault((s, a), []).append(k)
    for dil, titel in (("tr", "Okunuş (Türkçe)"), ("en", "Transliteration (English)")):
        def doldur(db, dil=dil) -> None:
            for (s, a), kelimeler in ayetler.items():
                satir, tek = ayet_okunusu(kelimeler, dil)
                db.execute("INSERT INTO okunus VALUES(?,?,?)", (s, a, satir))
                db.executemany("INSERT INTO kelime_okunus VALUES(?,?,?,?)",
                               [(s, a, i + 1, t) for i, t in enumerate(tek)])

        paket_yaz({
            "id": f"okunus-{dil}",
            "art": "okunus",
            "sprache": dil,
            "titel": titel,
            "quelle": "Kıblegâh, generated by rules from Tanzil Uthmani (tools/content/okunus.py)",
            "quelle_url": "https://tanzil.net",
            "lizenz": "own work (generated)",
            "store_tauglich": True,
            "version": "1.0.0",
            "textstand": TEXTSTAND,
            "inceleme": "ungeprüft",
        }, SEMA, doldur)


if __name__ == "__main__":
    main()
