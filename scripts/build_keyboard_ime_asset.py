import re

def build():
    with open('web_preview/mobile.html', 'r', encoding='utf-8') as f:
        text = f.read()

    # 1. Full 100% Fit CSS for Android IME Container with Inset & Landscape Support
    css_patch = '''
    /* ========================================================================= */
    /* WORLD-CLASS 100% FULL-FIT ANDROID SOFT KEYBOARD IME CONTAINER            */
    /* ========================================================================= */
    html, body {
      width: 100% !important;
      height: 100% !important;
      margin: 0 !important;
      padding: 0 !important;
      overflow: hidden !important;
      background: var(--kbd-bg, #0d1117) !important;
      user-select: none !important;
      -webkit-user-select: none !important;
      touch-action: none !important;
      -webkit-touch-callout: none !important;
      -webkit-tap-highlight-color: transparent !important;
      box-sizing: border-box !important;
    }
    * {
      -webkit-tap-highlight-color: transparent !important;
      -webkit-touch-callout: none !important;
    }
    .k-key {
      touch-action: none !important;
    }
    .k-key.touch-active, .k-key:active {
      transition: none !important;
      transform: scale(0.92) !important;
      background: var(--kbd-key-active, #3b4656) !important;
    }
    .k-key.special.touch-active, .k-key.special:active {
      transition: none !important;
      transform: scale(0.92) !important;
      background: var(--kbd-key-active, #28323d) !important;
    }
    .k-key.enter-action.touch-active, .k-key.enter-action:active {
      transition: none !important;
      transform: scale(0.94) !important;
      background: #005999 !important;
    }
    .suggest-chip.touch-active {
      transition: none !important;
      transform: scale(0.95) !important;
      background: var(--kbd-accent, #00e5ff) !important;
      color: #000 !important;
    }
    .techu-soft-keyboard {
      width: 100% !important;
      height: 100% !important;
      position: absolute !important;
      top: 0 !important;
      bottom: 0 !important;
      left: 0 !important;
      right: 0 !important;
      border-top: none !important;
      box-shadow: none !important;
      display: flex !important;
      flex-direction: column !important;
      justify-content: flex-start !important;
      padding: 0 0 2px 0 !important;
      margin: 0 !important;
      box-sizing: border-box !important;
    }
    .kbd-keys-container {
      flex: 1;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      padding: 2px 3px 3px 3px;
      box-sizing: border-box;
    }
    .kbd-tools-deck {
      display: none;
      flex: 1 !important;
      min-height: 0 !important;
      height: 100% !important;
      background: var(--kbd-surface);
      overflow: hidden;
      flex-direction: column;
      position: relative;
    }
    .kbd-tools-deck.open {
      display: flex !important;
    }
    /* When tools deck is open, completely hide keys container */
    .kbd-tools-deck.open ~ .kbd-keys-container,
    .kbd-keys-container.hidden,
    .techu-soft-keyboard.tools-open .kbd-keys-container {
      display: none !important;
    }
    .kbd-key-row {
      flex: 1 !important;
      display: flex !important;
      justify-content: center !important;
      gap: 3.5px !important;
      margin-bottom: 3px !important;
    }
    .kbd-key-row:last-child {
      margin-bottom: 0 !important;
    }
    .k-key {
      height: 100% !important;
    }
    .k-key.enter-key {
      font-weight: 700 !important;
      font-size: 15px !important;
    }
  </style>
'''
    text = text.replace('</style>', css_patch, 1)

    # 2. Strip Top Header & Live Editor from HTML, Replace with Safe Dummy Elements
    body_start = text.find('<body>')
    footer_start = text.find('<footer class="techu-soft-keyboard" id="techuKeyboard">')

    dummy_elements = '''<body>
  <!-- Hidden dummy elements to satisfy all DOM references in syncEditorView and header badges -->
  <div style="display:none !important;" id="dummyEditorContainer">
    <span id="headerModeBadge"></span>
    <span id="statusLayoutName"></span>
    <span id="wordCountBadge"></span>
    <span id="committedBefore"></span>
    <span id="committedAfter"></span>
    <span id="composingStream"></span>
    <span id="rawTagPreview"></span>
    <span id="cursorPosBadge"></span>
    <div id="editorCanvasBox"></div>
    <div id="editorCard"></div>
    <button id="pwaInstallPill"></button>
    <div id="learnTabChart"></div>
    <div id="learnTabRules"></div>
    <div id="learnTabPractice"></div>
    <div id="learnContentChart"></div>
    <div id="learnContentRules"></div>
    <div id="learnContentPractice"></div>
    <div id="emojiDrawer"></div>
    <div id="clipDrawer"></div>
    <div id="cursorDrawer"></div>
    <div id="learnDrawer"></div>
  </div>
'''
    text = text[:body_start] + dummy_elements + text[footer_start:]

    # 3. Flawless Bengali Unicode Sanitizer & Deep Android IME System Controller
    script_top_patch = '''<script>
    // Flawless Unicode Sanitizer (Eliminates broken ligatures & illegal hasantas)
    function sanitizeBangla(txt) {
      if (!txt) return '';
      return txt
        .replace(/\\u0982\\u09CD/g, '\\u0982') // ং্ -> ং (fixes বাং্লা -> বাংলা)
        .replace(/\\u0981\\u09CD/g, '\\u0981') // ঁ্ -> ঁ
        .replace(/\\u0983\\u09CD/g, '\\u0983') // ঃ্ -> ঃ
        .replace(/\\u09CE\\u09CD/g, '\\u09CE') // ৎ্ -> ৎ
        .replace(/\\u09CD\\u09CD+/g, '\\u09CD') // clean double hasantas
        .replace(/\\u09CD([\\u09BE\\u09BF\\u09C0\\u09C1\\u09C2\\u09C3\\u09C7\\u09C8\\u09CB\\u09CC])/g, '$1'); // clean hasanta before vowel signs
    }

    window.isPasswordField = false;
    window.currentImeAction = 0;
    window.activeInternalSearch = null;

    window.resetComposingState = function() {
      composing = '';
      if (typeof renderSuggestionChips === 'function') renderSuggestionChips();
    };

    window.onExternalSelectionChanged = function(selStart, selEnd) {
      if (composing.length > 0) {
        composing = '';
        if (typeof renderSuggestionChips === 'function') renderSuggestionChips();
      }
    };

    window.onEditorStateChanged = function(state) {
      window.isPasswordField = !!state.isPassword;
      window.currentImeAction = state.imeAction || 0;

      // Auto numpad for numeric or phone fields
      if (state.isNumeric) {
        if (typeof openKbdTool === 'function' && activeKbdToolName !== 'numpad') {
          openKbdTool('numpad');
        }
      } else if (activeKbdToolName === 'numpad') {
        if (typeof closeKbdTools === 'function') closeKbdTools();
      }

      // Dynamic Enter key label/icon matching IME action
      const enterBtns = document.querySelectorAll('.k-key.enter-key, [onclick*="pressEnterNewline"]');
      enterBtns.forEach(btn => {
        if (state.imeAction === 3) { // IME_ACTION_SEARCH
          btn.innerHTML = '<span style="font-size:18px;">🔍</span>';
        } else if (state.imeAction === 4) { // IME_ACTION_SEND
          btn.innerHTML = '<span style="font-size:18px;">➤</span>';
        } else if (state.imeAction === 2) { // IME_ACTION_GO
          btn.innerHTML = '<span style="font-size:18px;">➔</span>';
        } else if (state.imeAction === 6) { // IME_ACTION_DONE
          btn.innerHTML = '<span style="font-size:18px;">✓</span>';
        } else if (state.imeAction === 5) { // IME_ACTION_NEXT
          btn.innerHTML = '<span style="font-size:18px;">➜</span>';
        } else {
          btn.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 10 4 15 9 20"></polyline><path d="M20 4v7a4 4 0 0 1-4 4H4"></path></svg>';
        }
      });
    };

    // Attach in-keyboard search routing
    document.addEventListener('DOMContentLoaded', () => {
      const emSearch = document.getElementById('emojiSearchInput');
      const lnSearch = document.getElementById('learnSearchInput');
      if (emSearch) {
        emSearch.addEventListener('focus', () => { window.activeInternalSearch = emSearch; });
        emSearch.addEventListener('blur', () => { if (window.activeInternalSearch === emSearch) window.activeInternalSearch = null; });
      }
      if (lnSearch) {
        lnSearch.addEventListener('focus', () => { window.activeInternalSearch = lnSearch; });
        lnSearch.addEventListener('blur', () => { if (window.activeInternalSearch === lnSearch) window.activeInternalSearch = null; });
      }
    });
'''
    text = text.replace('<script>', script_top_patch, 1)

    # 4. Hook sanitizeBangla in parseAvro
    text = text.replace('return st.join("");', 'return sanitizeBangla(st.join(""));')

    # 5. Hook AndroidKeyboard in triggerHapticFeedback
    haptic_old = "function triggerHapticFeedback(type = 'click') {"
    haptic_new = '''function triggerHapticFeedback(type) {
      const fxType = type || 'click';
      if (window.AndroidKeyboard) {
        if (window.AndroidKeyboard.triggerHapticType) {
          window.AndroidKeyboard.triggerHapticType(fxType);
        } else if (window.AndroidKeyboard.triggerHaptic) {
          window.AndroidKeyboard.triggerHaptic();
        }
        return;
      }'''
    text = text.replace(haptic_old, haptic_new, 1)

    # 6. Hook AndroidKeyboard in pressKey with In-Keyboard Search & Password Field Protection
    press_key_old = '''      const isUpper = (shiftState > 0);
      const c = isUpper ? char.toUpperCase() : char;
      composing += c;'''
    press_key_new = '''      const isUpper = (shiftState > 0);
      const c = isUpper ? char.toUpperCase() : char;

      if (window.activeInternalSearch) {
        window.activeInternalSearch.value += c;
        window.activeInternalSearch.dispatchEvent(new Event('input', { bubbles: true }));
        return;
      }

      if (window.isPasswordField) {
        if (window.AndroidKeyboard) {
          window.AndroidKeyboard.commitText(c);
        }
        return;
      }

      composing += c;

      if (window.AndroidKeyboard) {
        if (!isAvroMode) {
          window.AndroidKeyboard.setComposingText(composing);
        } else {
          const sugs = getSuggestions();
          const preview = sugs[0] || parseAvro(composing) || composing;
          window.AndroidKeyboard.setComposingText(preview);
        }
      }'''
    text = text.replace(press_key_old, press_key_new, 1)

    # 7. Hook AndroidKeyboard in pressBackspace with Clean Zero-Leak Erase
    backspace_old = '''      // 1. If currently composing a word, delete last character from composing
      if (composing.length > 0) {
        composing = composing.slice(0, -1);
      } 
      // 2. If not composing, delete one character from committed text at cursor position!
      else if (cursorPos > 0) {
        committedText = committedText.slice(0, cursorPos - 1) + committedText.slice(cursorPos);
        cursorPos = Math.max(0, cursorPos - 1);
      }'''
    backspace_new = '''      if (window.activeInternalSearch) {
        window.activeInternalSearch.value = window.activeInternalSearch.value.slice(0, -1);
        window.activeInternalSearch.dispatchEvent(new Event('input', { bubbles: true }));
        return;
      }

      // 1. If currently composing a word, delete last character from composing
      if (composing.length > 0) {
        composing = composing.slice(0, -1);
        if (window.AndroidKeyboard) {
          if (composing.length > 0) {
            const preview = !isAvroMode ? composing : (getSuggestions()[0] || parseAvro(composing) || composing);
            window.AndroidKeyboard.setComposingText(preview);
          } else {
            window.AndroidKeyboard.clearComposingText();
          }
        }
      } 
      // 2. If not composing, delete one character from committed text in target app!
      else {
        if (cursorPos > 0) {
          committedText = committedText.slice(0, cursorPos - 1) + committedText.slice(cursorPos);
          cursorPos = Math.max(0, cursorPos - 1);
        }
        if (window.AndroidKeyboard) {
          window.AndroidKeyboard.deleteSurroundingText(1, 0);
        }
      }'''
    text = text.replace(backspace_old, backspace_new, 1)

    # 8. Hook AndroidKeyboard in selectCandidate with Password Safety
    candidate_old = '''      // Learn word into personal dictionary
      if (!userLearnedWords.includes(clean) && clean.length > 1) {
        userLearnedWords.unshift(clean);
        localStorage.setItem('techu_learned_words', JSON.stringify(userLearnedWords.slice(0, 50)));
      }

      // Clear composing query
      composing = "";'''
    candidate_new = '''      // Learn word into personal dictionary (strictly bypassed in password fields!)
      if (!window.isPasswordField && !userLearnedWords.includes(clean) && clean.length > 1) {
        userLearnedWords.unshift(clean);
        localStorage.setItem('techu_learned_words', JSON.stringify(userLearnedWords.slice(0, 50)));
      }

      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.commitText(clean + " ");
      }
      // Clear composing query
      composing = "";'''
    text = text.replace(candidate_old, candidate_new, 1)

    # 9. Hook AndroidKeyboard in pressSpace with Double-Space Period / Dari Support
    space_old = '''    // Spacebar Action
    function pressSpace() {
      const now = Date.now();
      // Double space -> Period / Dāri
      if (typeof userSettings !== 'undefined' && userSettings.doubleSpacePeriod && (now - lastSpaceTapTime < 450) && composing.length === 0 && cursorPos > 0) {
        if (committedText[cursorPos - 1] === ' ') {
          pushUndoSnapshot(true);
          const punct = isAvroMode ? '। ' : '. ';
          committedText = committedText.slice(0, cursorPos - 1) + punct + committedText.slice(cursorPos);
          cursorPos = cursorPos - 1 + punct.length;
          lastSpaceTapTime = 0;
          triggerHapticFeedback();
          checkAutoCapCondition();
          renderSuggestionChips();
          return;
        }
      }
      lastSpaceTapTime = now;
      triggerHapticFeedback();
      pushUndoSnapshot(true);

      // If currently composing, commit the top candidate (#1) followed by space
      if (composing.length > 0) {
        const candidates = getSuggestions();
        const top = candidates[0] || (isAvroMode ? parseAvro(composing) : composing);
        selectCandidate(top);
      } 
      // Otherwise insert space and predict NEXT words
      else {
        committedText = committedText.slice(0, cursorPos) + " " + committedText.slice(cursorPos);
        cursorPos += 1;
        checkAutoCapCondition();
        renderSuggestionChips();
      }
    }'''

    space_new = '''    // Spacebar Action
    function pressSpace() {
      const now = Date.now();
      // Double space -> Period / Dāri
      if (typeof userSettings !== 'undefined' && userSettings.doubleSpacePeriod && (now - lastSpaceTapTime < 450) && composing.length === 0) {
        pushUndoSnapshot(true);
        const punct = isAvroMode ? '। ' : '. ';
        if (cursorPos > 0 && committedText[cursorPos - 1] === ' ') {
          committedText = committedText.slice(0, cursorPos - 1) + punct + committedText.slice(cursorPos);
          cursorPos = cursorPos - 1 + punct.length;
        }
        lastSpaceTapTime = 0;
        triggerHapticFeedback();
        if (window.AndroidKeyboard) {
          window.AndroidKeyboard.deleteSurroundingText(1, 0);
          window.AndroidKeyboard.commitText(punct);
        }
        checkAutoCapCondition();
        renderSuggestionChips();
        return;
      }
      lastSpaceTapTime = now;
      triggerHapticFeedback();
      pushUndoSnapshot(true);

      // If currently composing, commit the top candidate (#1) followed by space
      if (composing.length > 0) {
        const candidates = getSuggestions();
        const top = candidates[0] || (isAvroMode ? parseAvro(composing) : composing);
        selectCandidate(top);
      } 
      // Otherwise insert space and predict NEXT words
      else {
        committedText = committedText.slice(0, cursorPos) + " " + committedText.slice(cursorPos);
        cursorPos += 1;
        if (window.AndroidKeyboard) {
          window.AndroidKeyboard.commitText(" ");
        }
        checkAutoCapCondition();
        renderSuggestionChips();
      }
    }'''
    text = text.replace(space_old, space_new, 1)

    # 10. Hook AndroidKeyboard in pressEnterNewline with Clean Candidate Commit & IME Action
    enter_old = '''    // Enter Key: INSERTS NEWLINE (\\n) - NEVER SENDS OR CLEARS!
    function pressEnterNewline() {
      triggerHapticFeedback();
      pushUndoSnapshot(true);

      // If composing, commit first
      if (composing.length > 0) {
        const candidates = getSuggestions();
        const top = candidates[0] || (isAvroMode ? parseAvro(composing) : composing);
        committedText = committedText.slice(0, cursorPos) + top + "\\n" + committedText.slice(cursorPos);
        cursorPos += top.length + 1;
        composing = "";
      } else {
        committedText = committedText.slice(0, cursorPos) + "\\n" + committedText.slice(cursorPos);
        cursorPos += 1;
      }

      checkAutoCapCondition();
      renderSuggestionChips();
    }'''

    enter_new = '''    // Enter Key: Intelligent Android Action & Newline Dispatcher
    function pressEnterNewline() {
      triggerHapticFeedback();
      pushUndoSnapshot(true);

      // If composing, commit first then trigger action
      if (composing.length > 0) {
        const candidates = getSuggestions();
        const top = candidates[0] || (isAvroMode ? parseAvro(composing) : composing);
        committedText = committedText.slice(0, cursorPos) + top + "\\n" + committedText.slice(cursorPos);
        cursorPos += top.length + 1;
        composing = "";
        if (window.AndroidKeyboard) {
          window.AndroidKeyboard.commitText(top);
          window.AndroidKeyboard.sendEnter();
        }
      } else {
        committedText = committedText.slice(0, cursorPos) + "\\n" + committedText.slice(cursorPos);
        cursorPos += 1;
        if (window.AndroidKeyboard) {
          window.AndroidKeyboard.sendEnter();
        }
      }

      checkAutoCapCondition();
      renderSuggestionChips();
    }'''
    text = text.replace(enter_old, enter_new, 1)

    # 11. Hook AndroidKeyboard in insertDirect
    insert_old = '''      if (composing.length > 0) {
        const top = getSuggestions()[0] || composing;
        committedText = committedText.slice(0, cursorPos) + top + char + committedText.slice(cursorPos);
        cursorPos += top.length + char.length;
        composing = "";
      } else {
        committedText = committedText.slice(0, cursorPos) + char + committedText.slice(cursorPos);
        cursorPos += char.length;
      }'''
    insert_new = '''      if (composing.length > 0) {
        const top = getSuggestions()[0] || (!isAvroMode ? composing : parseAvro(composing));
        committedText = committedText.slice(0, cursorPos) + top + char + committedText.slice(cursorPos);
        cursorPos += top.length + char.length;
        composing = "";
        if (window.AndroidKeyboard) {
          window.AndroidKeyboard.commitText(top + char);
        }
      } else {
        committedText = committedText.slice(0, cursorPos) + char + committedText.slice(cursorPos);
        cursorPos += char.length;
        if (window.AndroidKeyboard) {
          window.AndroidKeyboard.commitText(char);
        }
      }'''
    text = text.replace(insert_old, insert_new, 1)

    # 12. Hook insertJuktoborno
    jukto_old = '''    function insertJuktoborno(char, avroCode) {
      triggerHapticFeedback();
      pushUndoSnapshot(true, 'word');
      const cleanChar = char.split(' ')[0];
      if (composing) {
        commitWord(parseAvro(composing));
      }
      committedText = committedText.slice(0, cursorPos) + cleanChar + committedText.slice(cursorPos);
      cursorPos += cleanChar.length;
      syncEditorView();
      showToast(`যুক্তবর্ণ '${cleanChar}' যুক্ত হয়েছে (Avro: ${avroCode})`);
    }'''
    jukto_new = '''    function insertJuktoborno(char, avroCode) {
      triggerHapticFeedback();
      pushUndoSnapshot(true, 'word');
      const cleanChar = char.split(' ')[0];
      if (composing) {
        commitWord(parseAvro(composing));
      }
      committedText = committedText.slice(0, cursorPos) + cleanChar + committedText.slice(cursorPos);
      cursorPos += cleanChar.length;
      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.commitText(cleanChar);
      }
      syncEditorView();
      showToast(`যুক্তবর্ণ '${cleanChar}' যুক্ত হয়েছে (Avro: ${avroCode})`);
    }'''
    text = text.replace(jukto_old, jukto_new, 1)

    # 13. Hook tryPracticeWord
    practice_old = '''    function tryPracticeWord(word, keys) {
      triggerHapticFeedback();
      if (composing) {
        commitWord(parseAvro(composing));
      }
      committedText = committedText.slice(0, cursorPos) + word + ' ' + committedText.slice(cursorPos);
      cursorPos += word.length + 1;
      syncEditorView();
      showToast(`'${word}' টেক্সটে যুক্ত হয়েছে (টাইপ: ${keys})`);
    }'''
    practice_new = '''    function tryPracticeWord(word, keys) {
      triggerHapticFeedback();
      if (composing) {
        commitWord(parseAvro(composing));
      }
      committedText = committedText.slice(0, cursorPos) + word + ' ' + committedText.slice(cursorPos);
      cursorPos += word.length + 1;
      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.commitText(word + " ");
      }
      syncEditorView();
      showToast(`'${word}' টেক্সটে যুক্ত হয়েছে (টাইপ: ${keys})`);
    }'''
    text = text.replace(practice_old, practice_new, 1)

    # 14. Hook moveCursorBy, moveCursorLine, moveCursorTo, jumpWordCursor
    cursor_old = '''    function moveCursorBy(step) {
      triggerHapticFeedback();
      cursorPos = Math.max(0, Math.min(committedText.length, cursorPos + step));
      checkAutoCapCondition();
      syncEditorView();
      if (typeof updateCursorPanelLiveInfo === 'function') updateCursorPanelLiveInfo();
    }'''
    cursor_new = '''    function moveCursorBy(step) {
      triggerHapticFeedback();
      cursorPos = Math.max(0, Math.min(committedText.length, cursorPos + step));
      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.moveCursor(step < 0 ? -1 : 1);
      }
      checkAutoCapCondition();
      syncEditorView();
      if (typeof updateCursorPanelLiveInfo === 'function') updateCursorPanelLiveInfo();
    }'''
    text = text.replace(cursor_old, cursor_new, 1)

    cursor_line_old = '''    function moveCursorLine(dir) {
      triggerHapticFeedback();'''
    cursor_line_new = '''    function moveCursorLine(dir) {
      triggerHapticFeedback();
      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.moveCursorLine(dir);
      }'''
    text = text.replace(cursor_line_old, cursor_line_new, 1)

    cursor_to_old = '''    function moveCursorTo(targetPos) {
      triggerHapticFeedback();'''
    cursor_to_new = '''    function moveCursorTo(targetPos) {
      triggerHapticFeedback();
      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.moveCursorToBoundary(targetPos <= 0 ? 0 : 1);
      }'''
    text = text.replace(cursor_to_old, cursor_to_new, 1)

    cursor_jump_old = '''    function jumpWordCursor(dir) {
      triggerHapticFeedback();'''
    cursor_jump_new = '''    function jumpWordCursor(dir) {
      triggerHapticFeedback();
      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.moveCursorWord(dir);
      }'''
    text = text.replace(cursor_jump_old, cursor_jump_new, 1)

    # 15. Hook Cut, Copy, Paste, Undo, Redo, Clear in Cursor Navigation Panel
    cut_old = '''    function executeCursorCut() {
      triggerHapticFeedback();'''
    cut_new = '''    function executeCursorCut() {
      triggerHapticFeedback();
      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.performCut();
        showToast("কাট সম্পন্ন ✂️");
        return;
      }'''
    text = text.replace(cut_old, cut_new, 1)

    copy_old = '''    function executeCursorCopy() {
      triggerHapticFeedback();'''
    copy_new = '''    function executeCursorCopy() {
      triggerHapticFeedback();
      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.performCopy();
        showToast("কপি সম্পন্ন 📋");
        return;
      }'''
    text = text.replace(copy_old, copy_new, 1)

    paste_old = '''    function executeCursorPaste() {
      triggerHapticFeedback();'''
    paste_new = '''    function executeCursorPaste() {
      triggerHapticFeedback();
      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.performPaste();
        showToast("পেস্ট সম্পন্ন 📥");
        return;
      }'''
    text = text.replace(paste_old, paste_new, 1)

    clear_old = '''    function clearAllText() {
      triggerHapticFeedback();'''
    clear_new = '''    function clearAllText() {
      triggerHapticFeedback();
      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.performSelectAll();
        window.AndroidKeyboard.deleteSurroundingText(1, 0);
      }'''
    text = text.replace(clear_old, clear_new, 1)

    undo_old = '''    function executeSmartUndo() {
      triggerHapticFeedback();'''
    undo_new = '''    function executeSmartUndo() {
      triggerHapticFeedback();
      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.performUndo();
      }'''
    text = text.replace(undo_old, undo_new, 1)

    redo_old = '''    function executeSmartRedo() {
      triggerHapticFeedback();'''
    redo_new = '''    function executeSmartRedo() {
      triggerHapticFeedback();
      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.performRedo();
      }'''
    text = text.replace(redo_old, redo_new, 1)

    # 16. Hook Action Key Long-Press (Z, X, C, V)
    action_key_old = '''            if (actionType === 'undo' || actionType === 'all_undo') executeAllUndo();
            else if (actionType === 'redo' || actionType === 'all_redo') executeSmartRedo();
            else if (actionType === 'bold' || actionType === 'all_bold') executeSmartBold();
            else if (actionType === 'cut' || actionType === 'all_cut') executeAllCut();
            else if (actionType === 'copy' || actionType === 'all_copy') executeAllCopy();
            else if (actionType === 'paste' || actionType === 'all_paste') executeAllPaste();'''

    action_key_new = '''            if (window.AndroidKeyboard) {
              if (actionType === 'undo' || actionType === 'all_undo') window.AndroidKeyboard.performUndo();
              else if (actionType === 'redo' || actionType === 'all_redo') window.AndroidKeyboard.performRedo();
              else if (actionType === 'cut' || actionType === 'all_cut') window.AndroidKeyboard.performCut();
              else if (actionType === 'copy' || actionType === 'all_copy') window.AndroidKeyboard.performCopy();
              else if (actionType === 'paste' || actionType === 'all_paste') window.AndroidKeyboard.performPaste();
              return;
            }
            if (actionType === 'undo' || actionType === 'all_undo') executeAllUndo();
            else if (actionType === 'redo' || actionType === 'all_redo') executeSmartRedo();
            else if (actionType === 'bold' || actionType === 'all_bold') executeSmartBold();
            else if (actionType === 'cut' || actionType === 'all_cut') executeAllCut();
            else if (actionType === 'copy' || actionType === 'all_copy') executeAllCopy();
            else if (actionType === 'paste' || actionType === 'all_paste') executeAllPaste();'''
    text = text.replace(action_key_old, action_key_new, 1)

    # 17. Real Android System Clipboard Synchronization in renderClipList
    clip_sync_old = '''    function renderClipList() {
      const listEl = document.getElementById('clipPanelList');
      if (!listEl) return;

      const allClips = getStoredClips();'''

    clip_sync_new = '''    function renderClipList() {
      const listEl = document.getElementById('clipPanelList');
      if (!listEl) return;

      // Real-time synchronization from Android System Clipboard
      if (window.AndroidKeyboard && window.AndroidKeyboard.getClipboard) {
        try {
          const sysClip = window.AndroidKeyboard.getClipboard();
          if (sysClip && sysClip.trim().length > 0) {
            let clips = getStoredClips();
            if (!clips.some(c => c.text === sysClip)) {
              clips.unshift({ text: sysClip, pinned: false, time: Date.now() });
              saveStoredClips(clips.slice(0, 30));
            }
          }
        } catch (_) {}
      }

      const allClips = getStoredClips();'''
    text = text.replace(clip_sync_old, clip_sync_new, 1)

    # 18. Settings Haptics/Audio Synchronization with Android Service
    settings_sync_old = '''    function applyUserSettings() {'''
    settings_sync_new = '''    function applyUserSettings() {
      if (window.AndroidKeyboard && window.AndroidKeyboard.setAudioHapticsEnabled && typeof userSettings !== 'undefined') {
        window.AndroidKeyboard.setAudioHapticsEnabled(!!userSettings.soundEnabled, !!userSettings.hapticsEnabled);
      }'''
    text = text.replace(settings_sync_old, settings_sync_new, 1)

    # 19. Ensure Keys Container Is Guaranteed to Hide When Any Tool Is Opened
    open_tool_old = '''      if (deck) deck.classList.add('open');
      if (keysContainer) keysContainer.style.display = 'none';'''
    open_tool_new = '''      if (deck) deck.classList.add('open');
      if (keysContainer) {
        keysContainer.style.setProperty('display', 'none', 'important');
        keysContainer.classList.add('hidden');
      }
      document.getElementById('techuKeyboard')?.classList.add('tools-open');'''
    text = text.replace(open_tool_old, open_tool_new, 1)

    close_tool_old = '''      if (deck) deck.classList.remove('open');
      if (keysContainer) keysContainer.style.display = 'flex';'''
    close_tool_new = '''      if (deck) deck.classList.remove('open');
      if (keysContainer) {
        keysContainer.style.removeProperty('display');
        keysContainer.classList.remove('hidden');
      }
      document.getElementById('techuKeyboard')?.classList.remove('tools-open');'''
    text = text.replace(close_tool_old, close_tool_new, 1)

    # 20. Make internal panel search inputs readonly to prevent triggering soft-keyboard loops
    text = text.replace('id="emojiSearchInput" placeholder=', 'id="emojiSearchInput" readonly placeholder=', 1)
    text = text.replace('id="learnSearchInput" placeholder=', 'id="learnSearchInput" readonly placeholder=', 1)

    # 21. Real Android System Voice-To-Text Bridge
    voice_toggle_old = '''    function toggleVoiceInput() {
      if (isVoiceActive) {
        stopVoiceInput();
      } else {
        startVoiceInput();
      }
    }'''
    voice_toggle_new = '''    function toggleVoiceInput() {
      triggerHapticFeedback();
      if (window.AndroidKeyboard && window.AndroidKeyboard.toggleVoice) {
        window.AndroidKeyboard.toggleVoice();
        return;
      }
      if (isVoiceActive) {
        stopVoiceInput();
      } else {
        startVoiceInput();
      }
    }'''
    text = text.replace(voice_toggle_old, voice_toggle_new, 1)

    voice_lang_old = '''    function toggleVoiceLang() {
      triggerHapticFeedback();
      voiceLanguage = (voiceLanguage === 'bn-BD') ? 'en-US' : 'bn-BD';'''
    voice_lang_new = '''    function toggleVoiceLang() {
      triggerHapticFeedback();
      voiceLanguage = (voiceLanguage === 'bn-BD') ? 'en-US' : 'bn-BD';
      if (window.AndroidKeyboard && window.AndroidKeyboard.setVoiceLang) {
        window.AndroidKeyboard.setVoiceLang(voiceLanguage);
      }'''
    text = text.replace(voice_lang_old, voice_lang_new, 1)

    voice_stop_old = '''    function stopVoiceInput() {'''
    voice_stop_new = '''    function stopVoiceInput() {
      if (window.AndroidKeyboard && window.AndroidKeyboard.stopVoice) {
        window.AndroidKeyboard.stopVoice();
      }'''
    text = text.replace(voice_stop_old, voice_stop_new, 1)

    # Write output to keyboard_ime.html
    with open('native_android/TechuboardKeyboard/app/src/main/assets/keyboard_ime.html', 'w', encoding='utf-8') as f:
        f.write(text)

    # Untouched copy of mobile.html for studio reference
    with open('web_preview/mobile.html', 'r', encoding='utf-8') as f_orig:
        orig = f_orig.read()
    with open('native_android/TechuboardKeyboard/app/src/main/assets/mobile.html', 'w', encoding='utf-8') as f_mob:
        f_mob.write(orig)

    print("Successfully built world-class keyboard_ime.html with full Android IME hooks!")

if __name__ == '__main__':
    build()
