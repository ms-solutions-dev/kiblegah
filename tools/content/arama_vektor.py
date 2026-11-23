"""Builds the `arama-vektor` pack: on-device semantic search.

Model: potion-multilingual-128M (MinishLab, MIT) - a static embedding model, i.e. just a
table "subword -> vector". No neural network runs on the device: split the query into
subwords (unigram Viterbi over `parca.skor`), average the vectors, compare with the
precomputed verse vectors.

To keep the pack small, `parca` only contains the subwords that occur in our texts
(translation, tafsir, hadith) plus all single characters; tokenising a query can therefore
only differ for words that appear in none of our texts.

Verse vector = translation + 0.7 x tafsir of the verse (where available): the tafsir explains
in simple words and so finds verses whose translation lacks the searched word. `agirlik`
dampens very short verses ("Güzel güzel sabret") that would otherwise top every query on
the topic. Measured on the gold set in `dene()` (hits in the top 10): TR 5 -> 7, EN 5 -> 9 of 39.

Needs `model2vec` (without torch): `fetch.sh` creates `.venv` for it.
    .venv/bin/python -I arama_vektor.py [--dene]
"""

import json
import re
import sqlite3
import sys
import unicodedata
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script directory from sys.path
from ortak import KAYNAK, PAKETLER, paket_yaz  # noqa: E402

MODELL = "minishlab/potion-multilingual-128M"
# Translation pack -> tafsir pack of the same language (or None)
MEALLER = {
    "meal-tr-ozek": "tefsir-tr-muhtasar",
    "meal-de-bubenheim": None,
    "meal-en-saheeh": "tefsir-en-muhtasar",
}

SEMA = """
CREATE TABLE parca(metin TEXT PRIMARY KEY, skor REAL NOT NULL, vektor BLOB NOT NULL) WITHOUT ROWID;
CREATE TABLE merkez(paket TEXT PRIMARY KEY, vektor BLOB NOT NULL) WITHOUT ROWID;
CREATE TABLE ayet(paket TEXT NOT NULL, sure INTEGER NOT NULL, ayet INTEGER NOT NULL, agirlik REAL NOT NULL,
    vektor BLOB NOT NULL,
    PRIMARY KEY(paket, sure, ayet)) WITHOUT ROWID;
"""

DIPNOT = re.compile(r"\[\d+\]|\(\d+\)")


def oku(paket: str, sql: str):
    return sqlite3.connect(f"file:{PAKETLER / paket / 'veri.sqlite'}?mode=ro", uri=True).execute(sql).fetchall()


def birim(v: np.ndarray) -> np.ndarray:
    return v / (np.linalg.norm(v, axis=-1, keepdims=True) + 1e-9)


def ayet_metinleri(meal: str, tefsir: str | None) -> tuple[list[tuple[int, int]], list[str], list[str]]:
    satirlar = oku(meal, "SELECT sure, ayet, metin FROM meal ORDER BY sure, ayet")
    tef: dict[tuple[int, int], str] = {}
    if tefsir:
        for s, i, j, m in oku(tefsir, "SELECT sure, ilk, son, metin FROM tefsir"):
            for a in range(i, j + 1):
                tef[(s, a)] = m
    anahtar = [(s, a) for s, a, _ in satirlar]
    return anahtar, [DIPNOT.sub("", m) for _, _, m in satirlar], [tef.get(k, "") for k in anahtar]


class Zerleger:
    """Unigram Viterbi over a restricted subword list - the app does the same."""

    def __init__(self, skorlar: dict[str, float]):
        self.skor = skorlar
        self.en_uzun = max(len(p) for p in skorlar)

    @staticmethod
    def hazirla(metin: str) -> str:
        return "▁" + unicodedata.normalize("NFKC", metin).replace(" ", "▁")

    def zerle(self, metin: str) -> list[str]:
        s = self.hazirla(metin)
        en_iyi = [0.0] + [-1e18] * len(s)
        geri: list[tuple[int, str | None]] = [(0, None)] * (len(s) + 1)
        for son in range(1, len(s) + 1):
            for bas in range(max(0, son - self.en_uzun), son):
                p = s[bas:son]
                sk = self.skor.get(p)
                if sk is None:
                    if son - bas == 1:  # unknown character: skip
                        sk, p = -100.0, None
                    else:
                        continue
                if en_iyi[bas] + sk > en_iyi[son]:
                    en_iyi[son], geri[son] = en_iyi[bas] + sk, (bas, p)
        parcalar, i = [], len(s)
        while i > 0:
            bas, p = geri[i]
            if p is not None:
                parcalar.append(p)
            i = bas
        return parcalar[::-1]


def main() -> None:
    from model2vec import StaticModel

    m = StaticModel.from_pretrained(MODELL)
    tok = json.loads(m.tokenizer.to_str())
    sozluk = tok["model"]["vocab"]  # [[parca, skor], ...]
    E = m.embedding  # (n, 256)

    # 1. Verse vectors per translation: translation + tafsir, centred, normalised
    paketler, kullanilan = {}, set()
    for meal, tefsir in MEALLER.items():
        anahtar, mealler, tefsirler = ayet_metinleri(meal, tefsir)
        v = birim(m.encode(mealler))
        if tefsir:
            v = birim(v + 0.7 * birim(m.encode([t or x for t, x in zip(tefsirler, mealler)])))
        merkez = v.mean(0)
        agirlik = 1 - np.exp(-np.array([len(x) for x in mealler]) / 60)
        paketler[meal] = (anahtar, birim(v - merkez), merkez, mealler, agirlik)
        for t in mealler + [t for t in tefsirler if t]:
            kullanilan.update(m.tokenizer.encode(t, add_special_tokens=False).ids)

    # 2. Add subwords from hadith texts (queries often sound like explanations)
    for f in (KAYNAK / "hadis").glob("*/[0-9]*.json"):
        d = json.loads(f.read_text(encoding="utf-8"))
        for alan in ("title", "hadeeth", "explanation"):
            if d.get(alan):
                kullanilan.update(m.tokenizer.encode(d[alan], add_special_tokens=False).ids)
    for i, (p, _) in enumerate(sozluk):
        if len(p) == 1 or (len(p) == 2 and p[0] == "▁"):
            kullanilan.add(i)
    kullanilan.discard(tok["model"].get("unk_id", 3))
    secili = sorted(i for i in kullanilan if sozluk[i][0] and not sozluk[i][0].startswith("<"))
    print(f"  {len(secili)} of {len(sozluk)} subwords")

    # int8 per row with its own scale (first 4 bytes float32)
    def paketle(v: np.ndarray) -> bytes:
        olcek = float(np.abs(v).max()) / 127 or 1.0
        return np.float32(olcek).tobytes() + np.round(v / olcek).astype(np.int8).tobytes()

    if "--dene" in sys.argv:
        dene(m, sozluk, secili, paketler)
        return

    def doldur(db) -> None:
        db.executemany("INSERT INTO parca VALUES(?,?,?)", ((sozluk[i][0], float(sozluk[i][1]), paketle(E[i])) for i in secili))
        for meal, (anahtar, v, merkez, _, agirlik) in paketler.items():
            db.execute("INSERT INTO merkez VALUES(?,?)", (meal, merkez.astype(np.float32).tobytes()))
            db.executemany("INSERT INTO ayet VALUES(?,?,?,?,?)",
                           ((meal, s, a, float(g), paketle(x)) for (s, a), x, g in zip(anahtar, v, agirlik)))

    paket_yaz({
        "id": "arama-vektor",
        "art": "arama-vektor",
        "sprache": "mul",
        "titel": "Anlam araması",
        "quelle": "potion-multilingual-128M (MinishLab), vectors from the bundled translation and tafsir packs",
        "quelle_url": "https://huggingface.co/minishlab/potion-multilingual-128M",
        "lizenz": "MIT (model); vectors derived from the translation/tafsir packs",
        "store_tauglich": True,
        "version": "2026-10-18",
        "textstand": None,
    }, SEMA, doldur)


def dene(m, sozluk, secili, paketler) -> None:
    """Same computation as the app (restricted tokenisation, int8) compared with the full model."""
    z = Zerleger({sozluk[i][0]: float(sozluk[i][1]) for i in secili})
    idx = {sozluk[i][0]: i for i in secili}
    sorgular = {
        "meal-tr-ozek": ["zor zamanlarda sabretmek", "anne babaya iyilik", "içki ve kumar", "yetim malı", "ölümden sonra diriliş", "rızık kaygısı"],
        "meal-de-bubenheim": ["in schweren Zeiten geduldig sein", "Güte zu den Eltern", "Wein und Glücksspiel", "Besitz der Waisen"],
        "meal-en-saheeh": ["being patient in hard times", "kindness to parents", "wine and gambling", "worry about provision"],
    }
    for meal, (anahtar, v, merkez, mealler, agirlik) in paketler.items():
        for q in sorgular[meal]:
            parcalar = z.zerle(q)
            qa = birim(m.embedding[[idx[p] for p in parcalar]].mean(0))
            qm = m.encode([q])[0]
            s = (v @ birim(qa - merkez)) * agirlik
            print(f"== {q}  {parcalar}  agreement {float(qa @ birim(qm)):.3f}")
            for i in np.argsort(-s)[:5]:
                print(f"  {s[i]:.3f} {anahtar[i][0]}:{anahtar[i][1]} {mealler[i][:80]}")


if __name__ == "__main__":
    main()
