"""Downloads the hadith encyclopedia from HadeethEnc.com into sources/hadis/<dil>/ (once).

First all ids via the top-level categories, then the detail record per id. Polite: four
concurrent requests, retries on errors, files already present are skipped.
"""

import json
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script directory from sys.path
from ortak import KAYNAK  # noqa: E402

API = "https://hadeethenc.com/api/v1"
DILLER = ("tr", "en", "de")


def getir(url: str):
    """Via curl: the python.org installation on macOS ships without CA certificates."""
    for deneme in range(4):
        y = subprocess.run(["curl", "-sS", "--max-time", "30", "-A", "Kiblegah-content-fetch/1.0 (https://github.com/ms-solutions-dev/kiblegah)", url], capture_output=True)
        if y.returncode == 0:
            try:
                return json.loads(y.stdout.decode("utf-8"))
            except ValueError:
                pass
        time.sleep(2 * (deneme + 1))
    return None


def main() -> None:
    for dil in DILLER:
        klasor = KAYNAK / "hadis" / dil
        klasor.mkdir(parents=True, exist_ok=True)
        kategoriler = getir(f"{API}/categories/list/?language={dil}") or []
        (klasor / "kategoriler.json").write_text(json.dumps(kategoriler, ensure_ascii=False), encoding="utf-8")
        kimlikler = set()
        for k in (k for k in kategoriler if k.get("parent_id") is None):
            sayfa = 1
            while True:
                d = getir(f"{API}/hadeeths/list/?language={dil}&category_id={k['id']}&page={sayfa}&per_page=100")
                if not d:
                    break
                kimlikler.update(h["id"] for h in d.get("data", []))
                if int(d["meta"]["current_page"]) >= int(d["meta"]["last_page"]):
                    break
                sayfa += 1
        print(f"{dil}: {len(kimlikler)} hadiths", flush=True)

        def bir(i: str) -> None:
            f = klasor / f"{i}.json"
            if f.exists():
                return
            d = getir(f"{API}/hadeeths/one/?language={dil}&id={i}")
            if d:
                f.write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")

        with ThreadPoolExecutor(4) as h:
            list(h.map(bir, sorted(kimlikler)))
        print(f"{dil}: done", flush=True)


if __name__ == "__main__":
    main()
