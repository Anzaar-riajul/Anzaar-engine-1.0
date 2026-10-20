import re

with open('native_android/TechuboardKeyboard/app/src/main/assets/mobile.html', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Insert body.ime-mode CSS right before </style>
css_patch = '''
    /* ========================================================================= */
    /* ANDROID SYSTEM IME MODE (Full 100% Native Keyboard Inside WebView)        */
    /* ========================================================================= */
    body.ime-mode {
      height: 100% !important;
      height: 100vh !important;
      width: 100vw !important;
      margin: 0 !important;
      padding: 0 !important;
      overflow: hidden !important;
      background: var(--kbd-bg, #0d1117) !important;
      display: flex !important;
      flex-direction: column !important;
      justify-content: flex-end !important;
    }
    body.ime-mode .app-header {
      display: none !important;
    }
    body.ime-mode .main-canvas-area {
      display: none !important;
    }
    body.ime-mode .techu-soft-keyboard {
      width: 100% !important;
      height: 100% !important;
      border-top: none !important;
      box-shadow: none !important;
      position: relative !important;
      bottom: 0 !important;
    }
  </style>
'''
if 'body.ime-mode' not in content:
    content = content.replace('</style>', css_patch, 1)

# 2. Insert sanitizeBangla and ime-mode check right after <script>
script_top_patch = '''<script>
    // Environment Detection: Check if loaded as Android System IME
    const urlParams = new URLSearchParams(window.location.search);
    const isImeMode = urlParams.get('env') === 'ime' || (typeof window.AndroidKeyboard !== 'undefined');
    if (isImeMode) {
      document.body.classList.add('ime-mode');
    }

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

    window.resetComposingState = function() {
      composing = '';
      if (typeof renderSuggestionChips === 'function') renderSuggestionChips();
    };
'''
if 'Environment Detection: Check if loaded as Android System IME' not in content:
    content = content.replace('<script>', script_top_patch, 1)

# 3. Hook sanitizeBangla in parseAvro
content = content.replace('return st.join("");', 'return sanitizeBangla(st.join(""));')

# 4. Hook AndroidKeyboard in triggerHapticFeedback
haptic_old = 'function triggerHapticFeedback() {'
haptic_new = '''function triggerHapticFeedback() {
      if (window.AndroidKeyboard && window.AndroidKeyboard.triggerHaptic) {
        window.AndroidKeyboard.triggerHaptic();
      }'''
if 'window.AndroidKeyboard.triggerHaptic' not in content:
    content = content.replace(haptic_old, haptic_new, 1)

# 5. Hook AndroidKeyboard in pressKey
press_key_old = '''      const isUpper = (shiftState > 0);
      const c = isUpper ? char.toUpperCase() : char;
      composing += c;'''
press_key_new = '''      const isUpper = (shiftState > 0);
      const c = isUpper ? char.toUpperCase() : char;
      composing += c;

      if (window.AndroidKeyboard) {
        if (!isAvroMode) {
          window.AndroidKeyboard.commitText(c);
        } else {
          const sugs = getSuggestions();
          const preview = sugs[0] || parseAvro(composing) || composing;
          window.AndroidKeyboard.setComposingText(preview);
        }
      }'''
if 'window.AndroidKeyboard.setComposingText(preview)' not in content:
    content = content.replace(press_key_old, press_key_new, 1)

# 6. Hook AndroidKeyboard in pressBackspace
backspace_old = '''      // 1. If currently composing a word, delete last character from composing
      if (composing.length > 0) {
        composing = composing.slice(0, -1);
      } 
      // 2. If not composing, delete one character from committed text at cursor position!
      else if (cursorPos > 0) {
        committedText = committedText.slice(0, cursorPos - 1) + committedText.slice(cursorPos);
        cursorPos = Math.max(0, cursorPos - 1);
      }'''
backspace_new = '''      // 1. If currently composing a word, delete last character from composing
      if (composing.length > 0) {
        composing = composing.slice(0, -1);
        if (window.AndroidKeyboard) {
          if (composing.length > 0) {
            const sugs = getSuggestions();
            const preview = sugs[0] || parseAvro(composing) || composing;
            window.AndroidKeyboard.setComposingText(preview);
          } else {
            window.AndroidKeyboard.finishComposingText();
            window.AndroidKeyboard.commitText("");
          }
        }
      } 
      // 2. If not composing, delete one character from committed text at cursor position!
      else if (cursorPos > 0) {
        committedText = committedText.slice(0, cursorPos - 1) + committedText.slice(cursorPos);
        cursorPos = Math.max(0, cursorPos - 1);
        if (window.AndroidKeyboard) {
          window.AndroidKeyboard.deleteSurroundingText(1, 0);
        }
      } else {
        if (window.AndroidKeyboard) {
          window.AndroidKeyboard.deleteSurroundingText(1, 0);
        }
      }'''
if 'window.AndroidKeyboard.deleteSurroundingText' not in content:
    content = content.replace(backspace_old, backspace_new, 1)

# 7. Hook AndroidKeyboard in selectCandidate
candidate_old = '''      // Clear composing query
      composing = "";'''
candidate_new = '''      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.commitText(clean + " ");
      }
      // Clear composing query
      composing = "";'''
if 'window.AndroidKeyboard.commitText(clean + " ");' not in content:
    content = content.replace(candidate_old, candidate_new, 1)

# 8. Hook AndroidKeyboard in pressSpace
space_old = '''      // Otherwise insert space and predict NEXT words
      else {
        committedText = committedText.slice(0, cursorPos) + " " + committedText.slice(cursorPos);
        cursorPos += 1;
        checkAutoCapCondition();
        renderSuggestionChips();
      }'''
space_new = '''      // Otherwise insert space and predict NEXT words
      else {
        committedText = committedText.slice(0, cursorPos) + " " + committedText.slice(cursorPos);
        cursorPos += 1;
        if (window.AndroidKeyboard) {
          window.AndroidKeyboard.commitText(" ");
        }
        checkAutoCapCondition();
        renderSuggestionChips();
      }'''
if 'window.AndroidKeyboard.commitText(" ");' not in content:
    content = content.replace(space_old, space_new, 1)

# 9. Hook AndroidKeyboard in pressEnterNewline
enter_old = '''      if (composing.length > 0) {
        const candidates = getSuggestions();
        const top = candidates[0] || (isAvroMode ? parseAvro(composing) : composing);
        committedText = committedText.slice(0, cursorPos) + top + "\\n" + committedText.slice(cursorPos);
        cursorPos += top.length + 1;
        composing = "";
      } else {
        committedText = committedText.slice(0, cursorPos) + "\\n" + committedText.slice(cursorPos);
        cursorPos += 1;
      }'''
enter_new = '''      if (composing.length > 0) {
        const candidates = getSuggestions();
        const top = candidates[0] || (isAvroMode ? parseAvro(composing) : composing);
        committedText = committedText.slice(0, cursorPos) + top + "\\n" + committedText.slice(cursorPos);
        cursorPos += top.length + 1;
        composing = "";
      } else {
        committedText = committedText.slice(0, cursorPos) + "\\n" + committedText.slice(cursorPos);
        cursorPos += 1;
      }
      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.sendEnter();
      }'''
if 'window.AndroidKeyboard.sendEnter();' not in content:
    content = content.replace(enter_old, enter_new, 1)

# 10. Hook AndroidKeyboard in insertDirect
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
        const top = getSuggestions()[0] || composing;
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
if 'window.AndroidKeyboard.commitText(top + char);' not in content:
    content = content.replace(insert_old, insert_new, 1)

# 11. Safe null checks in syncEditorView
sync_old = '''    // Live View Sync
    function syncEditorView() {
      const beforeEl = document.getElementById('committedBefore');
      const afterEl = document.getElementById('committedAfter');
      const composingEl = document.getElementById('composingStream');
      const rawTagEl = document.getElementById('rawTagPreview');
      const posBadgeEl = document.getElementById('cursorPosBadge');
      const wordBadge = document.getElementById('wordCountBadge');
      const modeBadge = document.getElementById('headerModeBadge');
      const statusLayout = document.getElementById('statusLayoutName');

      modeBadge.innerText = isAvroMode ? "TechuAvro" : "English";
      statusLayout.innerText = isAvroMode ? "TechuAvro" : "English";

      const totalWords = committedText.trim() ? committedText.trim().split(/[\\s,\\।\\.\\?\\!\\n]+/).length : 0;
      wordBadge.innerText = `${totalWords} ${totalWords === 1 ? 'word' : 'words'}`;

      if (!committedText && !composing) {
        beforeEl.innerHTML = `<span class="placeholder-text">${isAvroMode ? 'TechuAvro: নিচে কীবোর্ডে টাইপ করুন...' : 'English: Type on keyboard below...'}</span>`;
        afterEl.innerText = "";
        composingEl.innerText = "";
        rawTagEl.innerText = "";
        posBadgeEl.innerText = "Pos: 0";
        return;
      }

      // Render committed text before & after cursor
      const textBefore = committedText.slice(0, cursorPos);
      const textAfter = committedText.slice(cursorPos);
      beforeEl.innerText = textBefore;
      afterEl.innerText = textAfter;

      // Render active composing word with underline highlight
      if (composing) {
        let livePreview = "";
        if (isAvroMode) {
          const sugs = getSuggestions();
          livePreview = sugs[0] || parseAvro(composing) || composing;
        } else {
          livePreview = composing;
        }
        composingEl.innerText = livePreview;
        rawTagEl.innerText = `(${composing})`;
      } else {
        composingEl.innerText = "";
        rawTagEl.innerText = "";
      }

      posBadgeEl.innerText = `Pos: ${cursorPos + (composing ? composing.length : 0)}`;

      // Scroll editor to bottom if cursor is at the end
      const box = document.getElementById('editorCanvasBox');
      box.scrollTop = box.scrollHeight;
    }'''

sync_new = '''    // Live View Sync (Safe Null Checked for IME Mode)
    function syncEditorView() {
      const beforeEl = document.getElementById('committedBefore');
      const afterEl = document.getElementById('committedAfter');
      const composingEl = document.getElementById('composingStream');
      const rawTagEl = document.getElementById('rawTagPreview');
      const posBadgeEl = document.getElementById('cursorPosBadge');
      const wordBadge = document.getElementById('wordCountBadge');
      const modeBadge = document.getElementById('headerModeBadge');
      const statusLayout = document.getElementById('statusLayoutName');

      if (modeBadge) modeBadge.innerText = isAvroMode ? "TechuAvro" : "English";
      if (statusLayout) statusLayout.innerText = isAvroMode ? "TechuAvro" : "English";

      const totalWords = committedText.trim() ? committedText.trim().split(/[\\s,\\।\\.\\?\\!\\n]+/).length : 0;
      if (wordBadge) wordBadge.innerText = `${totalWords} ${totalWords === 1 ? 'word' : 'words'}`;

      if (!committedText && !composing) {
        if (beforeEl) beforeEl.innerHTML = `<span class="placeholder-text">${isAvroMode ? 'TechuAvro: নিচে কীবোর্ডে টাইপ করুন...' : 'English: Type on keyboard below...'}</span>`;
        if (afterEl) afterEl.innerText = "";
        if (composingEl) composingEl.innerText = "";
        if (rawTagEl) rawTagEl.innerText = "";
        if (posBadgeEl) posBadgeEl.innerText = "Pos: 0";
        return;
      }

      // Render committed text before & after cursor
      const textBefore = committedText.slice(0, cursorPos);
      const textAfter = committedText.slice(cursorPos);
      if (beforeEl) beforeEl.innerText = textBefore;
      if (afterEl) afterEl.innerText = textAfter;

      // Render active composing word with underline highlight
      if (composing) {
        let livePreview = "";
        if (isAvroMode) {
          const sugs = getSuggestions();
          livePreview = sugs[0] || parseAvro(composing) || composing;
        } else {
          livePreview = composing;
        }
        if (composingEl) composingEl.innerText = livePreview;
        if (rawTagEl) rawTagEl.innerText = `(${composing})`;
      } else {
        if (composingEl) composingEl.innerText = "";
        if (rawTagEl) rawTagEl.innerText = "";
      }

      if (posBadgeEl) posBadgeEl.innerText = `Pos: ${cursorPos + (composing ? composing.length : 0)}`;

      // Scroll editor to bottom if cursor is at the end
      const box = document.getElementById('editorCanvasBox');
      if (box) box.scrollTop = box.scrollHeight;
    }'''
content = content.replace(sync_old, sync_new, 1)

with open('native_android/TechuboardKeyboard/app/src/main/assets/mobile.html', 'w', encoding='utf-8') as f:
    f.write(content)

print('SUCCESS')
