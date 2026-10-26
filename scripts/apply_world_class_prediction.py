# -*- coding: utf-8 -*-
"""
Applies the World-Class Prediction Engine into web_preview/mobile.html
"""
import re

def run():
    with open('web_preview/mobile.html', 'r', encoding='utf-8') as f:
        html = f.read()

    with open('scripts/generated_engine_merged.js', 'r', encoding='utf-8') as f_engine:
        engine_js = f_engine.read()

    # Split engine_js into constants and getSuggestions
    split_idx = engine_js.find('function getSuggestions() {')
    constants_js = engine_js[:split_idx].strip()
    suggestions_js = engine_js[split_idx:].strip()

    # 1. Replace legacy dictionaries (lines 4806 - 5503)
    start_anchor = '// =========================================================================\n    // 3. COMPREHENSIVE BANGLISH LEXICON & NEXT-WORD PREDICTION (RIDMIK GRADE)'
    if start_anchor not in html:
        # Try finding const BANGLISH_LEXICON
        start_idx = html.find('const BANGLISH_LEXICON = {')
        # Backtrack to the comment
        comment_idx = html.rfind('// =========================================================================', 0, start_idx)
        start_idx = comment_idx if comment_idx != -1 else start_idx
    else:
        start_idx = html.find(start_anchor)

    end_anchor = '// User Dictionary\n    let userLearnedWords'
    end_idx = html.find(end_anchor)

    if start_idx == -1 or end_idx == -1:
        print(f"Error finding dictionary anchors: start={start_idx}, end={end_idx}")
        return

    print(f"Replacing legacy dictionaries: [{start_idx} : {end_idx}]")
    html = html[:start_idx] + constants_js + "\n\n    " + html[end_idx:]

    # 2. Replace legacy getSuggestions()
    sug_start_anchor = '// Dynamic Suggestion Generator\n    function getSuggestions() {'
    if sug_start_anchor not in html:
        sug_start_anchor = 'function getSuggestions() {'
    
    sug_start_idx = html.find(sug_start_anchor)
    sug_end_anchor = '// Live View Sync\n    function syncEditorView() {'
    if sug_end_anchor not in html:
        sug_end_anchor = 'function syncEditorView() {'
    sug_end_idx = html.find(sug_end_anchor)

    if sug_start_idx == -1 or sug_end_idx == -1:
        print(f"Error finding getSuggestions anchors: start={sug_start_idx}, end={sug_end_idx}")
        return

    print(f"Replacing getSuggestions: [{sug_start_idx} : {sug_end_idx}]")
    html = html[:sug_start_idx] + suggestions_js + "\n\n    " + html[sug_end_idx:]

    with open('web_preview/mobile.html', 'w', encoding='utf-8') as f_out:
        f_out.write(html)

    print("Successfully updated web_preview/mobile.html with World-Class Prediction Engine!")

if __name__ == '__main__':
    run()
