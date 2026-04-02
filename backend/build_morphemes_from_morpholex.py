# -*- coding: utf-8 -*-
"""
MorphoLex Professional Morpheme Builder v3
===========================================
Uses the 'morphemes' PyPI package (bundles MorphoLex-en data).
Fixed to match actual library output format.
"""

import os
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
os.chdir(SCRIPT_DIR)
sys.path.insert(0, str(SCRIPT_DIR))

JSON_FINAL_PATH = SCRIPT_DIR / "morpholex_data" / "morphemes_final.json"
(SCRIPT_DIR / "morpholex_data").mkdir(exist_ok=True)


def log(msg):
    print(f"  {msg}", flush=True)


# ---------------------------------------------------------------------------
# Actual library format example:
#
# m.parse('ability') returns:
# {
#   'status': 'FOUND_IN_DATABASE',
#   'word': 'ability',
#   'morpheme_count': 2,
#   'tree': [
#     {'children': [{'text': 'able', 'type': 'root'}], 'type': 'free'},
#     {'text': 'ity', 'type': 'bound'}
#   ]
# }
#
# m.parse('unhappy') returns:
# {
#   'tree': [
#     {'text': 'un', 'type': 'prefix'},
#     {'children': [{'text': 'happy', 'type': 'root'}], 'type': 'free'}
#   ]
# }
#
# m.parse('accidental') returns:
# {
#   'tree': [
#     {'children': [{'text': 'accident', 'type': 'root'}], 'type': 'free'},
#     {'text': 'al', 'type': 'bound'}
#   ]
# }
# ---------------------------------------------------------------------------

def flatten_tree(tree_nodes):
    """Flatten the nested tree into a simple morpheme list."""
    parts = []
    for node in tree_nodes:
        node_type = node.get('type', '')

        if 'children' in node:
            for child in node['children']:
                child_type = child.get('type', '')
                text = child.get('text', '')
                if text:
                    if child_type == 'prefix':
                        mtype = 'prefix'
                    elif child_type == 'suffix':
                        mtype = 'suffix'
                    else:
                        mtype = 'root'
                    parts.append({"part": text, "type": mtype})
        else:
            text = node.get('text', '')
            if text:
                if node_type == 'prefix':
                    mtype = 'prefix'
                elif node_type in ('suffix', 'bound'):
                    mtype = 'suffix'
                elif node_type == 'free':
                    mtype = 'root'
                else:
                    mtype = 'root'
                parts.append({"part": text, "type": mtype})

    return parts


def parse_all_words(word_list):
    from morphemes import Morphemes

    data_path = str(SCRIPT_DIR / "morpholex_data")
    m = Morphemes(data_path)

    result = {}
    parsed = 0
    skipped = 0
    total = len(word_list)

    log(f"Processing {total} words...")

    for i, word in enumerate(word_list):
        if (i + 1) % 500 == 0:
            log(f"  ...{i + 1}/{total} ({parsed} parsed)")

        word_lower = word.strip().lower()
        if not word_lower or ' ' in word_lower or word_lower.startswith('-'):
            continue

        try:
            info = m.parse(word_lower)
            if not info or info.get('status') != 'FOUND_IN_DATABASE':
                skipped += 1
                continue

            if info.get('morpheme_count', 0) < 2:
                skipped += 1
                continue

            tree = info.get('tree', [])
            if not tree:
                skipped += 1
                continue

            morphemes = flatten_tree(tree)
            if morphemes and len(morphemes) >= 2:
                result[word_lower] = morphemes
                parsed += 1
            else:
                skipped += 1

        except Exception:
            skipped += 1

    log(f"[OK] Parsed: {parsed}, Skipped: {skipped}")
    return result


# ---------------------------------------------------------------------------
# Chinese meaning lookup
# ---------------------------------------------------------------------------
def load_chinese_dict():
    try:
        from app.morpheme_dict import PREFIXES, ROOTS, SUFFIXES
        log(f"[OK] Chinese dict: {len(PREFIXES)} prefixes, {len(ROOTS)} roots, {len(SUFFIXES)} suffixes")
        return PREFIXES, ROOTS, SUFFIXES
    except ImportError as e:
        log(f"[WARN] Cannot load morpheme_dict: {e}")
        return {}, {}, {}


def lookup_meaning(part, mtype, prefixes, roots, suffixes):
    p = part.lower().strip()
    if mtype == 'prefix':
        if p in prefixes:
            cn, en, origin = prefixes[p]
            return cn, origin
        for key in prefixes:
            if len(key) >= 2 and len(p) >= 2 and (p.startswith(key) or key.startswith(p)):
                cn, en, origin = prefixes[key]
                return cn, origin
    elif mtype == 'root':
        if p in roots:
            cn, en, origin = roots[p]
            return cn, origin
        for key in roots:
            if len(key) >= 3 and len(p) >= 3 and (p.startswith(key) or key.startswith(p)):
                cn, en, origin = roots[key]
                return cn, origin
    elif mtype == 'suffix':
        if p in suffixes:
            cn, pos, en = suffixes[p]
            return cn, ""
        for key in suffixes:
            if len(key) >= 2 and len(p) >= 2 and (p.endswith(key) or key.endswith(p)):
                cn, pos, en = suffixes[key]
                return cn, ""
    return "", ""


def annotate_chinese(word_morphemes, prefixes, roots, suffixes):
    # ★ 从数据库加载所有单词的中文释义，用于填充自由词根的含义
    word_defs = load_word_definitions()
    log(f"  Loaded {len(word_defs)} word definitions from database")

    result = {}
    matched = 0
    total_parts = 0
    for word, morphemes in word_morphemes.items():
        annotated = []
        for m in morphemes:
            total_parts += 1
            meaning, origin = lookup_meaning(m['part'], m['type'], prefixes, roots, suffixes)

            # ★ 自由词根没有中文含义时，从数据库查这个词本身的释义
            if not meaning and m['type'] == 'root':
                part_lower = m['part'].lower()
                if part_lower in word_defs:
                    meaning = word_defs[part_lower]

            if meaning:
                matched += 1
            annotated.append({"part": m['part'], "type": m['type'], "meaning": meaning, "origin": origin})
        result[word] = annotated
    pct = (matched / total_parts * 100) if total_parts > 0 else 0
    log(f"[OK] Chinese meanings matched: {matched}/{total_parts} ({pct:.0f}%)")
    return result


def load_word_definitions():
    """Load brief Chinese definitions for all words from database."""
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("SELECT word, definitions FROM words")
    rows = cur.fetchall()
    cur.close()
    conn.close()

    word_defs = {}
    for word_text, defs_json in rows:
        if not defs_json:
            continue
        word_lower = word_text.strip().lower()
        # defs_json is a list of definition objects
        defs = defs_json if isinstance(defs_json, list) else []
        for d in defs[:2]:
            if not isinstance(d, dict):
                continue
            for key in ['cn', 'meaning', 'definition_cn']:
                val = (d.get(key) or '').strip()
                if val and any('\u4e00' <= c <= '\u9fff' for c in val):
                    # Clean: remove pos tags, parenthetical notes, take first meaning
                    import re
                    clean = re.sub(r'^[a-zA-Z]+\.\s*', '', val)
                    clean = re.sub(r'\([^)]*\)', '', clean)
                    # Take first semicolon segment
                    idx = -1
                    for sep in ['；', ';', '，', ',']:
                        pos = clean.find(sep)
                        if pos > 0 and (idx < 0 or pos < idx):
                            idx = pos
                    if idx > 0:
                        clean = clean[:idx]
                    clean = clean.strip()
                    if clean:
                        word_defs[word_lower] = clean
                        break
            if word_lower in word_defs:
                break

    return word_defs


# ---------------------------------------------------------------------------
# Database (sync - using psycopg2 to avoid asyncio issues)
# ---------------------------------------------------------------------------
def get_db_connection():
    """Get a sync psycopg2 connection."""
    try:
        import psycopg2
    except ImportError:
        import subprocess
        log("[INSTALL] Installing psycopg2-binary...")
        subprocess.run([sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"])
        import psycopg2

    # Read from .env or use defaults
    db_url = "postgresql://postgres:postgres@localhost:5432/wordbook_db"

    env_file = SCRIPT_DIR / ".env"
    if env_file.exists():
        for line in env_file.read_text(encoding='utf-8').splitlines():
            if line.strip().startswith('DATABASE_URL') or line.strip().startswith('database_url'):
                val = line.split('=', 1)[1].strip().strip('"').strip("'")
                # Remove async driver prefix
                val = val.replace('+asyncpg', '').replace('+aiopg', '')
                db_url = val
                break

    return psycopg2.connect(db_url)


def get_all_words_from_db():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("SELECT id, word FROM words")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return rows


def write_to_database(morpheme_data):
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("SELECT id, word FROM words")
    db_words = cur.fetchall()
    log(f"  Database has {len(db_words)} words")

    updated = 0
    for word_id, word_text in db_words:
        word_lower = word_text.strip().lower()
        if ' ' in word_lower:
            continue
        if word_lower in morpheme_data:
            import json as _json
            cur.execute(
                "UPDATE words SET morphemes = %s WHERE id = %s",
                (_json.dumps(morpheme_data[word_lower], ensure_ascii=False), word_id)
            )
            updated += 1

    conn.commit()
    cur.close()
    conn.close()
    log(f"[OK] Updated {updated} words in database")
    return updated


def fill_remaining_with_dict():
    try:
        from app.morpheme_dict import get_morphemes
    except ImportError:
        return 0

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("SELECT id, word FROM words WHERE morphemes IS NULL")
    words = cur.fetchall()
    if not words:
        cur.close()
        conn.close()
        return 0

    count = 0
    for word_id, word_text in words:
        if ' ' in word_text:
            continue
        morphemes = get_morphemes(word_text)
        if morphemes:
            import json as _json
            cur.execute(
                "UPDATE words SET morphemes = %s WHERE id = %s",
                (_json.dumps(morphemes, ensure_ascii=False), word_id)
            )
            count += 1

    conn.commit()
    cur.close()
    conn.close()
    return count


# ---------------------------------------------------------------------------
# Syllable IPA: CMU dict → fix phonetics + per-syllable IPA
# ---------------------------------------------------------------------------

# CMU ARPABET → IPA (with stress-dependent variants)
CMU_VOWEL_IPA = {
    'AA': 'ɑ', 'AE': 'æ', 'AO': 'ɔ', 'AW': 'aʊ', 'AY': 'aɪ',
    'EH': 'ɛ', 'ER': 'ɜr', 'EY': 'eɪ', 'IH': 'ɪ', 'IY': 'i',
    'OW': 'oʊ', 'OY': 'ɔɪ', 'UH': 'ʊ', 'UW': 'u',
}
# AH is special: stressed=ʌ, unstressed=ə
CMU_CONSONANT_IPA = {
    'B': 'b', 'CH': 'tʃ', 'D': 'd', 'DH': 'ð', 'F': 'f', 'G': 'ɡ',
    'HH': 'h', 'JH': 'dʒ', 'K': 'k', 'L': 'l', 'M': 'm', 'N': 'n',
    'NG': 'ŋ', 'P': 'p', 'R': 'r', 'S': 's', 'SH': 'ʃ', 'T': 't',
    'TH': 'θ', 'V': 'v', 'W': 'w', 'Y': 'j', 'Z': 'z', 'ZH': 'ʒ',
}


def cmu_to_ipa(phones):
    """Convert a list of CMU phones to a full IPA string with stress marks."""
    ipa = []
    for p in phones:
        if p[-1:].isdigit():
            # Vowel phone
            stress_digit = p[-1]
            base = p[:-1]
            # Stress mark goes BEFORE the syllable it marks
            if stress_digit == '1':
                ipa.append('ˈ')
            elif stress_digit == '2':
                ipa.append('ˌ')
            # AH: stressed → ʌ, unstressed → ə
            if base == 'AH':
                ipa.append('ʌ' if stress_digit in ('1', '2') else 'ə')
            elif base == 'ER':
                ipa.append('ɜr' if stress_digit in ('1', '2') else 'ər')
            else:
                ipa.append(CMU_VOWEL_IPA.get(base, base.lower()))
        else:
            # Consonant phone
            ipa.append(CMU_CONSONANT_IPA.get(p, p.lower()))
    return ''.join(ipa)


def is_vowel_phone(p):
    return p and p[-1:].isdigit()


def split_phones_by_syllables(phones, syllables):
    """
    Split CMU phone sequence into groups matching orthographic syllables.

    Uses vowel nuclei alignment: each syllable has exactly one vowel phone.
    Consonants between vowels are assigned using the orthographic boundary.
    """
    vowel_indices = [i for i, p in enumerate(phones) if is_vowel_phone(p)]

    if len(vowel_indices) != len(syllables):
        return None

    # Build split points between syllable groups.
    # For consonants between vowel[i] and vowel[i+1], use the
    # orthographic text boundary ratio to decide the split.
    word_text = ''.join(syllables)
    n_phones = len(phones)

    # Cumulative text positions at syllable boundaries
    cum_pos = 0
    text_ratios = []
    for s in syllables[:-1]:
        cum_pos += len(s)
        text_ratios.append(cum_pos / len(word_text))

    split_points = []
    for si in range(len(vowel_indices) - 1):
        vi = vowel_indices[si]      # current vowel position
        vj = vowel_indices[si + 1]  # next vowel position

        # Consonants in the gap: phones[vi+1 ... vj-1]
        gap_start = vi + 1
        gap_end = vj  # exclusive

        if gap_start >= gap_end:
            # No consonants between vowels
            split_points.append(gap_end)
            continue

        # Use the text boundary ratio to decide where to split
        ratio = text_ratios[si]
        ideal_pos = ratio * n_phones
        # Snap to the nearest position within the gap
        best = round(ideal_pos)
        best = max(gap_start, min(best, gap_end))

        split_points.append(best)

    # Extract phone groups
    groups = []
    start = 0
    for sp in split_points:
        groups.append(phones[start:sp])
        start = sp
    groups.append(phones[start:])

    # Convert each group to IPA
    result = []
    for group in groups:
        ipa_str = cmu_to_ipa(group)
        result.append(f'/{ipa_str}/')

    return result


def load_cmu_dict():
    """
    Load CMU Pronouncing Dictionary. Try local cache first, then download.
    Returns dict: word → list of phones (e.g. ['AE2','K','S','AH0','D','EH1','N','T','AH0','L'])
    """
    cache_dir = SCRIPT_DIR / "morpholex_data"
    cache_dir.mkdir(exist_ok=True)
    cache_file = cache_dir / "cmudict.txt"

    # Download if not cached
    if not cache_file.exists():
        log("  Downloading CMU Pronouncing Dictionary (~4MB)...")
        import urllib.request
        url = "https://raw.githubusercontent.com/cmusphinx/cmudict/master/cmudict.dict"
        try:
            urllib.request.urlretrieve(url, str(cache_file))
            log(f"  [OK] Saved to {cache_file}")
        except Exception as e:
            log(f"  [ERROR] Download failed: {e}")
            log(f"  Please download manually from:")
            log(f"    {url}")
            log(f"  Save as: {cache_file}")
            return {}
    else:
        log(f"  Using cached CMU dict: {cache_file}")

    # Parse the dict file
    cmu = {}
    with open(cache_file, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(';;;'):
                continue
            parts = line.split()
            if len(parts) < 2:
                continue
            word = parts[0].lower()
            # Remove variant markers like "ABOUT(2)"
            if '(' in word:
                continue  # skip alternate pronunciations
            phones = parts[1:]
            cmu[word] = phones

    log(f"  [OK] CMU dict loaded: {len(cmu)} words")
    return cmu


def fill_syllable_ipa():
    """
    Use CMU Pronouncing Dictionary to:
    1. Fix incorrect phonetic_us with authoritative CMU data
    2. Compute accurate per-syllable IPA
    No external Python libraries needed - uses raw CMU dict file.
    """
    cmu = load_cmu_dict()
    if not cmu:
        return 0

    conn = get_db_connection()
    cur = conn.cursor()

    # Ensure syllable_ipa column exists
    cur.execute("""
        SELECT column_name FROM information_schema.columns
        WHERE table_name='words' AND column_name='syllable_ipa'
    """)
    if not cur.fetchone():
        cur.execute("ALTER TABLE words ADD COLUMN syllable_ipa JSONB")
        conn.commit()
        log("  Added syllable_ipa column")

    # Get all words with syllables
    cur.execute("SELECT id, word, syllables, phonetic_us FROM words WHERE syllables IS NOT NULL")
    words = cur.fetchall()
    log(f"  Processing {len(words)} words with CMU dict...")

    import json as _json
    ipa_count = 0
    phonetic_fixed = 0

    for i, (word_id, word_text, syllables, old_phonetic) in enumerate(words):
        if (i + 1) % 500 == 0:
            log(f"    ...{i+1}/{len(words)} (IPA:{ipa_count}, phonetic fixed:{phonetic_fixed})")

        if not syllables or not isinstance(syllables, list):
            continue
        if ' ' in word_text:
            continue

        # Look up in CMU dict
        phones = cmu.get(word_text.lower())
        if not phones:
            continue

        # 1. Generate correct full-word IPA from CMU
        full_ipa = cmu_to_ipa(phones)
        new_phonetic = f'/{full_ipa}/'

        # Update phonetic_us if it's different (CMU is authoritative)
        if old_phonetic != new_phonetic:
            cur.execute(
                "UPDATE words SET phonetic_us = %s WHERE id = %s",
                (new_phonetic, word_id)
            )
            phonetic_fixed += 1

        # 2. Compute per-syllable IPA
        if len(syllables) >= 2:
            syl_ipa = split_phones_by_syllables(phones, syllables)
            if syl_ipa and len(syl_ipa) == len(syllables):
                cur.execute(
                    "UPDATE words SET syllable_ipa = %s WHERE id = %s",
                    (_json.dumps(syl_ipa, ensure_ascii=False), word_id)
                )
                ipa_count += 1

    conn.commit()
    log(f"[OK] Phonetics fixed: {phonetic_fixed}, Syllable IPA: {ipa_count}")

    # Show samples
    cur.execute("""
        SELECT word, syllables, syllable_ipa, phonetic_us FROM words
        WHERE syllable_ipa IS NOT NULL
        ORDER BY word LIMIT 10
    """)
    print()
    print("  --- Samples (CMU dict) ---")
    for word, syls, ipas, phonetic in cur.fetchall():
        if syls and ipas and len(syls) == len(ipas):
            parts = '  '.join(f"{s}={p}" for s, p in zip(syls, ipas))
            print(f"    {word:20s}  {phonetic:20s}  {parts}")
    print()

    cur.close()
    conn.close()
    return ipa_count


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print()
    print("=" * 58)
    print("  MorphoLex Professional Morpheme Builder v3")
    print("=" * 58)
    print()

    print("[Step 1/5] Check morphemes library")
    try:
        from morphemes import Morphemes
        log("[OK] morphemes library ready")
    except ImportError:
        log("[ERROR] Run: pip install morphemes")
        return

    print()
    print("[Step 2/5] Get word list from database")
    try:
        db_words = get_all_words_from_db()
        word_list = [w[1] for w in db_words]
        log(f"[OK] {len(word_list)} words in database")
    except Exception as e:
        log(f"[ERROR] Cannot connect to database: {e}")
        return

    print()
    print("[Step 3/5] Parse morphemes (MorphoLex professional data)")
    word_morphemes = parse_all_words(word_list)
    if not word_morphemes:
        log("[ERROR] No morphemes parsed")
        return

    print()
    print("[Step 4/5] Add Chinese meanings")
    prefixes, roots, suffixes = load_chinese_dict()
    final_data = annotate_chinese(word_morphemes, prefixes, roots, suffixes)

    with open(JSON_FINAL_PATH, 'w', encoding='utf-8') as f:
        json.dump(final_data, f, ensure_ascii=False, indent=2)
    log(f"  Saved to {JSON_FINAL_PATH}")

    print()
    print("  --- Sample results ---")
    for w in ['ability', 'accident', 'accidental', 'accept', 'comfortable',
              'international', 'unhappy', 'beautiful', 'education', 'impossible',
              'environment', 'achievement', 'discover', 'encourage', 'wonderful']:
        if w in final_data:
            parts = " + ".join(f"{m['part']}({m['meaning'] or '?'})" for m in final_data[w])
            print(f"    {w:20s} = {parts}")
    print()

    print("[Step 5/5] Write to database")
    try:
        count = write_to_database(final_data)
    except Exception as e:
        log(f"[ERROR] Database write failed: {e}")
        return

    print()
    print("[Bonus] Fill remaining words with morpheme_dict fallback")
    try:
        extra = fill_remaining_with_dict()
        log(f"[OK] Fallback filled {extra} additional words")
    except Exception as e:
        log(f"  Fallback skipped: {e}")

    # ★ v5.3: 音节音标精确计算
    print()
    print("[Step 6] Compute per-syllable IPA (CMU Pronouncing Dictionary)")
    try:
        syl_count = fill_syllable_ipa()
    except Exception as e:
        log(f"  Syllable IPA skipped: {e}")
        syl_count = 0

    print()
    print("=" * 58)
    print(f"  All done!")
    print(f"  MorphoLex: {len(final_data)} words")
    print(f"  Database updated: {count} words")
    if syl_count > 0:
        print(f"  Syllable IPA: {syl_count} words")
    print()
    print(f"  Next steps:")
    print(f"  1. Restart start_app.bat")
    print(f"  2. Browser: Ctrl+Shift+R")
    print("=" * 58)
    print()


if __name__ == "__main__":
    main()
