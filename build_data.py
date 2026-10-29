#!/usr/bin/env python3
"""
build_data.py — genera `hsk.json` per l'app HSK.

Sorgente: drkameleon/complete-hsk-vocabulary (licenza MIT).
  https://github.com/drkameleon/complete-hsk-vocabulary

Da `complete.json` estrae, per ogni voce:
  - hanzi semplificato e tradizionale
  - pinyin con diacritici + numerazione dei toni
  - significato in inglese
  - livello HSK 2.0 (1-6) e HSK 3.0 (1-7, dove 7 = fascia 7-9 ufficiale)
  - frequenza (per scegliere i distrattori in modo sensato)

Non vengono incluse frasi d'esempio: la sorgente non ne contiene e le
alternative (Tatoeba CC BY 2.0 FR, Gushi CC BY-SA 4) richiederebbero
attribuzioni aggiuntive o una licenza share-alike che propagherebbe.

Uso:
    python3 build_data.py                 # usa la copia locale di complete.json
    python3 build_data.py --download      # la (ri)scarica da GitHub
    python3 build_data.py -o hsk.json
"""

import argparse
import json
import os
import sys
import urllib.request
from datetime import date

SOURCE_RAW = (
    "https://raw.githubusercontent.com/drkameleon/"
    "complete-hsk-vocabulary/main/complete.json"
)
SOURCE_REPO = "https://github.com/drkameleon/complete-hsk-vocabulary"
SOURCE_LICENSE = "MIT"
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "complete.json")


# ----------------------------------------------------------------- sorgente
def load_source(download: bool) -> list:
    """Scarica (se richiesto) e legge complete.json."""
    if download or not os.path.exists(CACHE):
        print(f"Scarico {SOURCE_RAW} ...", file=sys.stderr)
        req = urllib.request.Request(SOURCE_RAW, headers={"User-Agent": "hsk-build"})
        with urllib.request.urlopen(req, timeout=120) as r:
            data = r.read()
        with open(CACHE, "wb") as f:
            f.write(data)
        print(f"  {len(data) / 1024:.0f} KiB salvati in {CACHE}", file=sys.stderr)
    else:
        print(f"Uso la copia locale {CACHE}", file=sys.stderr)

    with open(CACHE, encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------- normalizza
def own_level(entry: dict, prefix: str):
    """Livello 'proprio' della parola in un set: il minimo tra quelli dichiarati.

    `level` nel sorgente è *inclusivo* (elenca tutti i livelli in cui la
    parola compare), quindi il livello di appartenenza è il minimo.
    Restituisce None se la parola non appartiene a quel set.
    """
    levels = [
        int(item.split("-", 1)[1])
        for item in entry.get("level", [])
        if item.startswith(prefix + "-")
    ]
    return min(levels) if levels else None


def clean_meaning(form: dict, limit: int = 3) -> str:
    """Unisce i significati inglesi in una stringa leggibile e compatta."""
    meanings = [m.strip() for m in form.get("meanings", []) if m.strip()]
    # La prima accezione è la più utile per una flashcard; le altre si
    # accorciano perché servono solo da contesto.
    head = meanings[:limit]
    if not head:
        return ""
    return "; ".join(head)


def build_rows(entries: list) -> list:
    """Trasforma le voci sorgente nelle righe compatte di hsk.json."""
    rows = []
    for e in entries:
        forms = e.get("forms") or []
        if not forms:
            continue  # voce priva di forma: nessuna pronuncia, saltiamo
        form = forms[0]  # le varianti successive sono raramenti utili qui

        tr = form.get("transcriptions") or {}
        simp = e.get("simplified", "").strip()
        if not simp:
            continue

        rows.append(
            [
                simp,                                           # 0 hanzi semplificato
                (form.get("traditional") or simp).strip(),      # 1 hanzi tradizionale
                (tr.get("pinyin") or "").strip(),               # 2 pinyin con diacritici
                (tr.get("numeric") or "").strip(),               # 3 pinyin numerico (toni)
                clean_meaning(form),                            # 4 significato in inglese
                own_level(e, "old"),                            # 5 livello HSK 2.0
                own_level(e, "newest"),                         # 6 livello HSK 3.0
                e.get("frequency") or 0,                        # 7 frequenza
            ]
        )

    # Ordinamento stabile: per livello HSK 3.0 (o 2.0 come fallback), poi per
    # frequenza crescente. Le carte nuove escono così in ordine didattico.
    rows.sort(key=lambda r: (r[6] or 99, r[5] or 99, r[7]))
    return rows


def level_histogram(rows: list, idx: int) -> dict:
    out = {}
    for r in rows:
        lv = r[idx]
        if lv is not None:
            out[lv] = out.get(lv, 0) + 1
    return dict(sorted(out.items()))


# -------------------------------------------------------------------- output
def main() -> int:
    ap = argparse.ArgumentParser(description="Genera hsk.json per l'app HSK.")
    ap.add_argument("-o", "--output", default=os.path.join(HERE, "hsk.json"))
    ap.add_argument("--download", action="store_true", help="ri scarica la sorgente")
    args = ap.parse_args()

    entries = load_source(args.download)
    rows = build_rows(entries)

    doc = {
        "meta": {
            "source": SOURCE_REPO,
            "source_file": "complete.json",
            "license": SOURCE_LICENSE,
            "generated": date.today().isoformat(),
            "count": len(rows),
            "fields": [
                "simp", "trad", "pinyin", "numeric", "meaning",
                "hsk2", "hsk3", "frequency",
            ],
            "notes": {
                "hsk2": "livello HSK 2.0 (1-6), null se assente",
                "hsk3": "livello HSK 3.0 (1-7); la fascia 7 ufficiale copre i livelli 7-9",
                "examples": "nessuna frase d'esempio: la sorgente non ne contiene",
            },
        },
        "words": rows,
    }

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))

    size = os.path.getsize(args.output)
    only2 = sum(1 for r in rows if r[5] and not r[6])
    only3 = sum(1 for r in rows if r[6] and not r[5])
    both = sum(1 for r in rows if r[5] and r[6])

    print(f"\nScritto {args.output} — {size / 1024:.0f} KiB, {len(rows)} parole", file=sys.stderr)
    print(f"  HSK 2.0: {level_histogram(rows, 5)}", file=sys.stderr)
    print(f"  HSK 3.0: {level_histogram(rows, 6)}", file=sys.stderr)
    print(f"  in entrambi i set: {both} · solo 2.0: {only2} · solo 3.0: {only3}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
