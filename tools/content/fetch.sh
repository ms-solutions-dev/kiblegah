#!/bin/bash
# Downloads the raw sources (if missing) and rebuilds all content packs into
# App/Resources/Paketler/.
#   tools/content/fetch.sh [--no-vector] [--no-hadith]
#     --no-vector  skip the model2vec semantic index (arama-vektor)
#     --no-hadith  skip the hadith download and the hadis pack (large)
set -euo pipefail
cd "$(dirname "$0")"

VECTOR=1
HADITH=1
for arg in "$@"; do
    case "$arg" in
        --no-vector) VECTOR=0 ;;
        --no-hadith) HADITH=0 ;;
        -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

UA="Kiblegah-content-fetch/1.0 (https://github.com/ms-solutions-dev/kiblegah)"
K=sources
mkdir -p "$K/mokhtasar-en"

fetch() {  # fetch <file> <url>
    if [ ! -s "$K/$1" ]; then
        echo "downloading $1"
        curl -fsSL -A "$UA" -o "$K/$1.part" "$2"
        mv "$K/$1.part" "$K/$1"
    fi
}

echo "== Fetching sources"
fetch quran-uthmani-2017.txt https://github.com/cpfair/quran-tajweed/files/7281388/quran-uthmani.txt
fetch quran-data.xml https://tanzil.net/res/text/metadata/quran-data.xml
fetch liste.json https://quranenc.com/api/v1/translations/list
fetch german_bubenheim.sqlite https://quranenc.com/downloads/sqlite/german_bubenheim.sqlite
fetch english_saheeh.sqlite https://quranenc.com/downloads/sqlite/english_saheeh.sqlite
fetch turkish_shahin.sqlite https://quranenc.com/downloads/sqlite/turkish_shahin.sqlite
fetch turkish_mokhtasar.sqlite https://quranenc.com/downloads/sqlite/turkish_mokhtasar.sqlite
for s in $(seq 1 114); do
    fetch "mokhtasar-en/$s.json" "https://quranenc.com/api/v1/translation/sura/english_mokhtasar/$s"
done
fetch cpfair.zip https://github.com/cpfair/quran-tajweed/archive/refs/heads/master.zip
fetch esma-en.html https://en.wikipedia.org/wiki/Names_of_God_in_Islam
fetch esma-de.html https://de.wikipedia.org/wiki/99_Namen_Allahs
if [ "$HADITH" = 1 ]; then
    echo "== Fetching hadiths (HadeethEnc, skips files already present)"
    python3 -I hadis_indir.py
fi

echo "== Building packs"
python3 -I kuran_text.py        # kuran-text (base for everything below)
python3 -I meal.py              # meal-tr-ozek, meal-de-bubenheim, meal-en-saheeh
python3 -I okunus.py            # okunus-tr, okunus-en (reads kuran-text)
python3 -I tecvid.py            # tecvid
python3 -I tefsir.py            # tefsir-tr-muhtasar, tefsir-en-muhtasar
python3 -I dualar.py            # dualar (reads kuran-text)
python3 -I esma.py              # esma
if [ "$HADITH" = 1 ]; then
    python3 -I hadis.py         # hadis (reads kuran-text)
fi
python3 -I arama.py             # arama (reads meal-*, okunus-*, dualar, esma, hadis)

if [ "$VECTOR" = 1 ]; then
    echo "== Building semantic index (model2vec, no torch)"
    if [ ! -x .venv/bin/python ]; then
        python3 -I -m venv .venv
        .venv/bin/python -I -m pip install -q "model2vec==0.10.0"
    fi
    .venv/bin/python -I arama_vektor.py   # arama-vektor (reads meal-*, tefsir-*, sources/hadis)
fi

echo "== Checking packs"
python3 -I denetle.py ../../App/Resources/Paketler --store
