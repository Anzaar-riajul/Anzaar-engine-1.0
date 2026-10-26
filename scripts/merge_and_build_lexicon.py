# -*- coding: utf-8 -*-
import json
import re

def build():
    # 1. Read existing BANGLISH_LEXICON from mobile.html
    with open('web_preview/mobile.html', 'r', encoding='utf-8') as f:
        html = f.read()

    m = re.search(r'const BANGLISH_LEXICON = \{([\s\S]*?)\};\s*(?://[^\n]*\n\s*)*const BANGLA_NEXT_WORDS', html)
    if not m:
        print("Error: Could not find BANGLISH_LEXICON")
        return

    lexicon_raw = m.group(1)
    legacy_lexicon = {}
    for line in lexicon_raw.split('\n'):
        line = line.strip()
        if line.startswith('//') or not line or ':' not in line:
            continue
        try:
            # parse "key": ["w1", "w2"],
            k_part, v_part = line.split(':', 1)
            k = k_part.strip().strip('"\'')
            v_str = v_part.strip().rstrip(',')
            v = json.loads(v_str)
            legacy_lexicon[k] = v
        except Exception as e:
            pass

    print(f"Parsed {len(legacy_lexicon)} legacy entries.")

    # 2. Load our priority lexicon from build_full_prediction_engine
    import sys, os
    sys.path.insert(0, os.path.dirname(__file__))
    import build_full_prediction_engine as gen
    priority_lexicon = gen.LEXICON_DATA

    priority_lexicon.extend([
        (["chokh", "cokh"], [], [["চোখ", 1000], ["চোখে", 970], ["চোখের", 950]]),
        (["kolom"], [], [["কলম", 1000], ["কলমে", 960]]),
        (["akash", "aakash"], [], [["আকাশ", 1000], ["আকাশে", 960], ["নীল আকাশ", 940]]),
        (["nodi", "nodee"], [], [["নদী", 1000], ["নদীতে", 960]]),
        (["khela"], [], [["খেলা", 1000], ["খেলাধুলা", 960]]),
        (["boi"], [], [["বই", 1000], ["বইমেলা", 960]])
    ])

    # Map: key -> list of [word, score]
    merged_lexicon = {}

    # Insert priority items with high scores (900-1000)
    for keys, abbrevs, cands in priority_lexicon:
        for k in keys:
            norm_k = k.lower()
            if norm_k not in merged_lexicon:
                merged_lexicon[norm_k] = []
            for w, sc in cands:
                if not any(item[0] == w for item in merged_lexicon[norm_k]):
                    merged_lexicon[norm_k].append([w, sc])
        for ab in abbrevs:
            norm_ab = ab.lower()
            if norm_ab not in merged_lexicon:
                merged_lexicon[norm_ab] = []
            for w, sc in cands:
                if not any(item[0] == w for item in merged_lexicon[norm_ab]):
                    merged_lexicon[norm_ab].append([w, sc])

    # Insert legacy items with moderate scores (800-880) so they don't overshadow top chat words
    for k, words in legacy_lexicon.items():
        norm_k = k.lower()
        if norm_k not in merged_lexicon:
            merged_lexicon[norm_k] = []
        for idx, w in enumerate(words):
            score = 850 - (idx * 20)
            if not any(item[0] == w for item in merged_lexicon[norm_k]):
                merged_lexicon[norm_k].append([w, score])

    print(f"Total merged keys: {len(merged_lexicon)}")

    # Convert merged_lexicon into sorted structure for JS
    # Pre-index map: prefix -> sorted [[word, score], ...]
    prefix_map = {}

    for k, cands in merged_lexicon.items():
        # Abbreviations with length <= 3 only index for length >= 2
        min_len = 1
        for length in range(min_len, len(k) + 1):
            p = k[:length]
            if length == 1:
                # Digraph isolation:
                # If key starts with 'dh', do not bleed into 'd'
                if k.startswith('dh') and p == 'd':
                    continue
                # If key is 'tnx'/'thx', do not bleed into 't'
                if k in ['tnx', 'thx'] and p == 't':
                    continue
                # If key starts with 'th', do not bleed into 't' unless word starts with 'থ' or 'ঠ'
                if k.startswith('th') and p == 't' and ('ধ' in cands[0][0] or 'দ' in cands[0][0]):
                    continue

            if p not in prefix_map:
                prefix_map[p] = []
            for w, sc in cands:
                eff_sc = sc
                if length == 1 and sc < 950:
                    eff_sc = sc - 200 # Don't surface obscure words on single-letter taps!
                if not any(item[0] == w for item in prefix_map[p]):
                    prefix_map[p].append([w, eff_sc])

    # Sort each bucket
    for p in prefix_map:
        prefix_map[p].sort(key=lambda x: x[1], reverse=True)
        # Keep top 12 candidates per prefix bucket for fast memory & performance
        prefix_map[p] = prefix_map[p][:12]

    print(f"Generated {len(prefix_map)} prefix buckets.")

    # Convert to compact JSON
    js_prefix_map = json.dumps(prefix_map, ensure_ascii=False)
    js_next_words = json.dumps(gen.NEXT_WORDS_MAP, ensure_ascii=False)
    js_eng_lexicon = json.dumps(gen.ENGLISH_LEXICON_DATA, ensure_ascii=False)
    js_eng_next_words = json.dumps(gen.ENGLISH_NEXT_WORDS_MAP, ensure_ascii=False)

    js_code = f"""    // =========================================================================
    // 🧠 WORLD-CLASS PREDICTIVE & TRANSLITERATION ENGINE (TRI-LAYER HYBRID)
    // =========================================================================
    const TECHU_PREFIX_MAP = {js_prefix_map};
    const TECHU_NEXT_WORDS = {js_next_words};
    const TECHU_ENG_LEXICON = {js_eng_lexicon};
    const TECHU_ENG_NEXT_WORDS = {js_eng_next_words};

    function getSuggestions() {{
      // STATE A: Currently Composing a Word (Phonetic Transliteration & Auto-Complete)
      if (composing) {{
        if (isAvroMode) {{
          const q = composing.toLowerCase();
          const candidates = [];
          const seen = new Set();

          function addCand(word) {{
            if (!word) return;
            const clean = (typeof sanitizeBangla === 'function') ? sanitizeBangla(word.trim()) : word.trim();
            if (clean && !seen.has(clean)) {{
              seen.add(clean);
              candidates.push(clean);
            }}
          }}

          // 1. Personal Learned Words matching prefix (Highest Priority)
          if (typeof userLearnedWords !== 'undefined' && Array.isArray(userLearnedWords)) {{
            userLearnedWords.forEach(uw => {{
              const uLower = uw.toLowerCase();
              if (uLower.startsWith(q) || (parseAvro(q) && uw.startsWith(parseAvro(q)))) {{
                addCand(uw);
              }}
            }});
          }}

          // 2. High-Frequency Pre-Indexed Match (Sub-Millisecond Lookup)
          const bucket = TECHU_PREFIX_MAP[q];
          if (bucket) {{
            bucket.forEach(([w, _score]) => addCand(w));
          }}

          // 3. Authentic Avro Engine Transliteration on Query
          const avroParsed = parseAvro(q);
          if (avroParsed) {{
            addCand(avroParsed);
          }}

          // 4. Intentional Mixed-Case Avro Transliteration (e.g., T, D, R, Sh)
          if (composing !== q && composing !== composing.toUpperCase()) {{
            const avroRaw = parseAvro(composing);
            if (avroRaw) addCand(avroRaw);
          }}

          // 5. Append Raw Latin Text as Last Option
          addCand(composing);

          return candidates.slice(0, 8);

        }} else {{
          // English Composing State
          const q = composing.toLowerCase();
          const candidates = [];
          const seen = new Set();

          function addCand(word) {{
            if (!word) return;
            if (!seen.has(word)) {{
              seen.add(word);
              candidates.push(word);
            }}
          }}

          for (const [keys, cands] of TECHU_ENG_LEXICON) {{
            if (keys.some(k => k.startsWith(q))) {{
              cands.forEach(([w, _score]) => addCand(w));
            }}
            if (candidates.length >= 8) break;
          }}

          addCand(composing);
          addCand(composing + "s");
          addCand(composing + "ed");
          addCand(composing + "ing");

          return candidates.slice(0, 8);
        }}
      }}

      // STATE B: Word Completed & Spaced -> CONTEXTUAL NEXT-WORD PREDICTION (N-Gram)
      if (isAvroMode) {{
        const lastWord = (typeof getLastWord === 'function') ? getLastWord(committedText) : "";
        let list = [];
        if (lastWord && TECHU_NEXT_WORDS[lastWord]) {{
          list = [...TECHU_NEXT_WORDS[lastWord]];
        }} else {{
          list = ["আমি", "আপনি", "কেমন", "ভালো", "ধন্যবাদ", "ঠিক আছে", "ইনশাল্লাহ", "শুভ সকাল", "সবাই", "বাংলাদেশ"];
        }}

        // Discard the completed word itself from next-word suggestions
        list = list.filter(w => w !== lastWord && !w.startsWith(lastWord + ' '));
        return list.slice(0, 8);
      }} else {{
        const lastWord = (typeof getLastWord === 'function') ? getLastWord(committedText).toLowerCase() : "";
        let list = [];
        if (lastWord && TECHU_ENG_NEXT_WORDS[lastWord]) {{
          list = [...TECHU_ENG_NEXT_WORDS[lastWord]];
        }} else {{
          list = ["How", "Are", "Thank", "Good", "I", "What", "Please"];
        }}
        list = list.filter(w => w.toLowerCase() !== lastWord);
        return list.slice(0, 8);
      }}
    }}
"""
    with open('scripts/generated_engine_merged.js', 'w', encoding='utf-8') as f_out:
        f_out.write(js_code)
    print("Successfully built scripts/generated_engine_merged.js!")

if __name__ == '__main__':
    build()
