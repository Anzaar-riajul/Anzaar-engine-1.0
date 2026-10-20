import re

# Read original mobile.html
with open('web_preview/mobile.html', 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Modify CSS in <style>
css_target = '</style>'
css_replacement = '''
    /* Fixed 100% Fill Container for Android Soft Keyboard IME */
    html, body {
      width: 100% !important;
      height: 100% !important;
      margin: 0 !important;
      padding: 0 !important;
      overflow: hidden !important;
      background: var(--kbd-bg, #0d1117) !important;
      user-select: none !important;
      -webkit-user-select: none !important;
      touch-action: manipulation !important;
      display: block !important;
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
      justify-content: space-between !important;
    }
  </style>
'''
text = text.replace(css_target, css_replacement, 1)

# 2. Replace Header and Main Canvas Area with Dummy Elements for Safe DOM Binding
body_start = text.find('<body>')
footer_start = text.find('<footer class="techu-soft-keyboard" id="techuKeyboard">')

dummy_elements = '''<body>
  <!-- Hidden elements to satisfy all DOM references in syncEditorView and header badges -->
  <div style="display:none;" id="dummyEditorContainer">
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
  </div>
'''

text = text[:body_start] + dummy_elements + text[footer_start:]

# 3. Add sanitizeBangla and script initialization
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

    window.resetComposingState = function() {
      composing = '';
      if (typeof renderSuggestionChips === 'function') renderSuggestionChips();
    };
'''
text = text.replace('<script>', script_top_patch, 1)

# 4. Hook sanitizeBangla in parseAvro: replace 'return st.join("");' with 'return sanitizeBangla(st.join(""));'
text = text.replace('return st.join("");', 'return sanitizeBangla(st.join(""));')

# 5. Hook AndroidKeyboard in triggerHapticFeedback
haptic_old = 'function triggerHapticFeedback() {'
haptic_new = '''function triggerHapticFeedback() {
      if (window.AndroidKeyboard && window.AndroidKeyboard.triggerHaptic) {
        window.AndroidKeyboard.triggerHaptic();
      }'''
text = text.replace(haptic_old, haptic_new, 1)

# 6. Hook AndroidKeyboard in pressKey
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
text = text.replace(press_key_old, press_key_new, 1)

# 7. Hook AndroidKeyboard in pressBackspace
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
text = text.replace(backspace_old, backspace_new, 1)

# 8. Hook AndroidKeyboard in selectCandidate
candidate_old = '''      // Clear composing query
      composing = "";'''
candidate_new = '''      if (window.AndroidKeyboard) {
        window.AndroidKeyboard.commitText(clean + " ");
      }
      // Clear composing query
      composing = "";'''
text = text.replace(candidate_old, candidate_new, 1)

# 9. Hook AndroidKeyboard in pressSpace
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
text = text.replace(space_old, space_new, 1)

# 10. Hook AndroidKeyboard in pressEnterNewline
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
text = text.replace(insert_old, insert_new, 1)

# Write keyboard_ime.html
with open('native_android/TechuboardKeyboard/app/src/main/assets/keyboard_ime.html', 'w', encoding='utf-8') as f:
    f.write(text)

# Also ensure mobile.html in assets is 100% UNTOUCHED original copy for MainActivity
with open('web_preview/mobile.html', 'r', encoding='utf-8') as f_orig:
    orig_content = f_orig.read()

# In mobile.html, only hook the PWA/Settings click to open Android IME settings if in Android
with open('native_android/TechuboardKeyboard/app/src/main/assets/mobile.html', 'w', encoding='utf-8') as f_mob:
    f_mob.write(orig_content)

print('SUCCESS: Generated keyboard_ime.html and restored untouched mobile.html!')
