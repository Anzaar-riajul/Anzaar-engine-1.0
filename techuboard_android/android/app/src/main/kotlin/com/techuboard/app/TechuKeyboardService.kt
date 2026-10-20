package com.techuboard.app

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * TechuAvro Android Soft Keyboard IME.
 * Features:
 * - Top-row Techuboard Clipboard Bar for 1-tap pasting anywhere.
 * - Live phonetic transliteration using the TechuAvro engine (Avro layout).
 * - Instant toggle between TechuAvro and English modes.
 * - Clean English branding (TechuAvro / Techuboard).
 */
class TechuKeyboardService : InputMethodService() {

    private val engine = TechuAvroEngine()
    private lateinit var suggestionManager: TechuSuggestionManager
    private var isAvroMode = true
    private var isShifted = false
    private var composing = StringBuilder()
    private var currentSuggestions = listOf<String>()

    private var candidateScroll: HorizontalScrollView? = null
    private var candidateChipsLayout: LinearLayout? = null
    private var keyboardRowsContainer: LinearLayout? = null
    private var clipboardBar: LinearLayout? = null
    private var modeButton: Button? = null
    private var spaceButton: Button? = null

    private var isSymbolsMode = false
    private var isSecondarySymbols = false
    private var isBanglaNumerals = true
    private var vibrator: Vibrator? = null

    override fun onCreate() {
        super.onCreate()
        suggestionManager = TechuSuggestionManager(this)
        vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    private fun triggerHapticClick() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createOneShot(10, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(10)
            }
        } catch (_: Exception) {}
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun setupSpacebarCursorSwipe(spaceBtn: Button) {
        var startX = 0f
        var startY = 0f
        var isDragging = false
        val stepThresholdPx = 16f * resources.displayMetrics.density
        var lastDispatchedStep = 0

        spaceBtn.setOnTouchListener { v, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.rawX
                    startY = event.rawY
                    isDragging = false
                    lastDispatchedStep = 0
                    spaceBtn.isPressed = true
                    triggerHapticClick()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaX = event.rawX - startX
                    val deltaY = event.rawY - startY

                    // Smooth horizontal drag detection threshold
                    if (!isDragging && Math.abs(deltaX) > stepThresholdPx && Math.abs(deltaX) > Math.abs(deltaY) * 1.2) {
                        isDragging = true
                        v.parent?.requestDisallowInterceptTouchEvent(true)
                    }

                    if (isDragging) {
                        val currentStep = (deltaX / stepThresholdPx).toInt()
                        if (currentStep != lastDispatchedStep) {
                            val stepDiff = currentStep - lastDispatchedStep
                            lastDispatchedStep = currentStep

                            val ic = currentInputConnection
                            if (ic != null) {
                                val before = ic.getTextBeforeCursor(10000, 0)?.length ?: 0
                                val after = ic.getTextAfterCursor(10000, 0)?.length ?: 0
                                val total = before + after
                                val targetPos = (before + stepDiff).coerceIn(0, total)
                                ic.setSelection(targetPos, targetPos)
                                triggerHapticClick()
                            }
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    v.parent?.requestDisallowInterceptTouchEvent(false)
                    spaceBtn.isPressed = false
                    if (isDragging) {
                        isDragging = false
                    } else {
                        handleSpace()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    v.parent?.requestDisallowInterceptTouchEvent(false)
                    spaceBtn.isPressed = false
                    isDragging = false
                    true
                }
                else -> false
            }
        }
    }

    override fun onCreateInputView(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#121417")) // Modern dark keyboard
            setPadding(8, 8, 8, 12)
        }

        // Top Row: Techuboard Clipboard Bar
        val clipboardScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(4, 2, 4, 6) }
        }

        clipboardBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        clipboardScroll.addView(clipboardBar)
        root.addView(clipboardScroll)

        // Candidate / Suggestion Bar: 3 Primary Chips + Horizontal Scroll for 3+ Slide-to-Reveal Chips
        val candidateContainer = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            isFillViewport = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(42)
            ).apply { setMargins(4, 0, 4, 6) }
            setBackgroundColor(Color.parseColor("#1A1F26"))
        }
        this.candidateScroll = candidateContainer

        candidateChipsLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(6), dp(3), dp(6), dp(3))
        }
        candidateContainer.addView(candidateChipsLayout)
        root.addView(candidateContainer)

        // Dynamic Keyboard Rows Container (Supports QWERTY, ?123 Symbols, and =\< Pages)
        keyboardRowsContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        root.addView(keyboardRowsContainer)
        renderKeyboardKeys()

        refreshClipboardChips()
        return root
    }

    override fun onStartInputView(info: android.view.inputmethod.EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        composing.clear()
        updateCandidateView()
        refreshClipboardChips()
    }

    private fun buildKeyRow(keys: List<String>): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            weightSum = keys.size.toFloat()
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(48)
            ).apply { setMargins(0, 2, 0, 2) }
        }

        for (k in keys) {
            val keyView = createKeyButton(k).apply {
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply {
                    setMargins(3, 2, 3, 2)
                }
                setOnClickListener {
                    handleCharacter(if (isShifted) k.uppercase() else k)
                }
            }
            row.addView(keyView)
        }
        return row
    }

    private fun buildSpecialRow3(keys: List<String>): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(48)
            ).apply { setMargins(0, 2, 0, 2) }
        }

        // Shift key
        val shiftKey = createKeyButton("⇧").apply {
            layoutParams = LinearLayout.LayoutParams(dp(44), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(3, 2, 3, 2)
            }
            setBackgroundDrawable(createKeyBackground(Color.parseColor("#262D38")))
            setOnClickListener {
                isShifted = !isShifted
                setTextColor(if (isShifted) Color.parseColor("#00E5FF") else Color.WHITE)
            }
        }
        row.addView(shiftKey)

        // Middle character keys
        val keysLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f)
            weightSum = keys.size.toFloat()
        }
        for (k in keys) {
            val keyView = createKeyButton(k).apply {
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply {
                    setMargins(3, 2, 3, 2)
                }
                setOnClickListener {
                    handleCharacter(if (isShifted) k.uppercase() else k)
                }
            }
            keysLayout.addView(keyView)
        }
        row.addView(keysLayout)

        // Backspace key
        val backspaceKey = createKeyButton("⌫").apply {
            layoutParams = LinearLayout.LayoutParams(dp(44), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(3, 2, 3, 2)
            }
            setBackgroundDrawable(createKeyBackground(Color.parseColor("#262D38")))
            setOnClickListener {
                handleBackspace()
            }
        }
        row.addView(backspaceKey)

        return row
    }

    private fun renderKeyboardKeys() {
        val container = keyboardRowsContainer ?: return
        container.removeAllViews()

        if (!isSymbolsMode) {
            // QWERTY Alphabet Rows
            val row1 = listOf("q", "w", "e", "r", "t", "y", "u", "i", "o", "p")
            val row2 = listOf("a", "s", "d", "f", "g", "h", "j", "k", "l")
            val row3 = listOf("z", "x", "c", "v", "b", "n", "m")

            container.addView(buildKeyRow(row1))
            container.addView(buildKeyRow(row2))
            container.addView(buildSpecialRow3(row3))
            container.addView(buildBottomRow())
        } else if (!isSecondarySymbols) {
            // Primary Symbols & Numbers Page (?123)
            val digits = if (isBanglaNumerals) {
                listOf("১", "২", "৩", "৪", "৫", "৬", "৭", "৮", "৯", "০")
            } else {
                listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0")
            }
            // Essential Symbols including Bengali Taka (৳)
            val row2 = listOf("৳", "@", "#", "$", "%", "&", "*", "-", "+", "(", ")")
            val row3 = listOf("!", "\"", "'", ":", ";", "/", "?", "।")

            container.addView(buildSymbolRow(digits))
            container.addView(buildSymbolRow(row2))
            container.addView(buildSpecialSymbolRow3(row3, isSecondary = false))
            container.addView(buildSymbolsBottomRow())
        } else {
            // Secondary Math & Rare Symbols Page (=\<)
            val row1 = listOf("~", "`", "|", "•", "√", "π", "÷", "×", "§", "∆")
            val row2 = listOf("£", "€", "¥", "¢", "^", "°", "=", "{", "}", "\\")
            val row3 = listOf("%", "<", ">", "[", "]", "©", "®", "™")

            container.addView(buildSymbolRow(row1))
            container.addView(buildSymbolRow(row2))
            container.addView(buildSpecialSymbolRow3(row3, isSecondary = true))
            container.addView(buildSymbolsBottomRow())
        }
    }

    private fun buildSymbolRow(keys: List<String>): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            weightSum = keys.size.toFloat()
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(48)
            ).apply { setMargins(0, 2, 0, 2) }
        }

        for (k in keys) {
            val keyView = createKeyButton(k).apply {
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply {
                    setMargins(2, 2, 2, 2)
                }
                setOnClickListener {
                    commitComposing()
                    currentInputConnection?.commitText(k, 1)
                }
            }
            row.addView(keyView)
        }
        return row
    }

    private fun buildSpecialSymbolRow3(keys: List<String>, isSecondary: Boolean): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(48)
            ).apply { setMargins(0, 2, 0, 2) }
        }

        // Toggle button between ?123 and =\<
        val toggleKey = createKeyButton(if (isSecondary) "?123" else "=\\<").apply {
            textSize = 12f
            layoutParams = LinearLayout.LayoutParams(dp(48), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(2, 2, 2, 2)
            }
            setBackgroundDrawable(createKeyBackground(Color.parseColor("#262D38")))
            setTextColor(Color.parseColor("#00E5FF"))
            setOnClickListener {
                isSecondarySymbols = !isSecondarySymbols
                renderKeyboardKeys()
            }
        }
        row.addView(toggleKey)

        // Middle character keys
        val keysLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f)
            weightSum = keys.size.toFloat()
        }
        for (k in keys) {
            val keyView = createKeyButton(k).apply {
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply {
                    setMargins(2, 2, 2, 2)
                }
                setOnClickListener {
                    commitComposing()
                    currentInputConnection?.commitText(k, 1)
                }
            }
            keysLayout.addView(keyView)
        }
        row.addView(keysLayout)

        // Backspace key
        val backspaceKey = createKeyButton("⌫").apply {
            layoutParams = LinearLayout.LayoutParams(dp(48), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(2, 2, 2, 2)
            }
            setBackgroundDrawable(createKeyBackground(Color.parseColor("#262D38")))
            setOnClickListener {
                handleBackspace()
            }
        }
        row.addView(backspaceKey)

        return row
    }

    private fun buildSymbolsBottomRow(): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(48)
            ).apply { setMargins(0, 2, 0, 2) }
        }

        // ABC Key: Returns to Alphabet Mode
        val abcButton = createKeyButton("ABC").apply {
            textSize = 13f
            layoutParams = LinearLayout.LayoutParams(dp(62), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(2, 2, 2, 2)
            }
            setBackgroundDrawable(createKeyBackground(Color.parseColor("#1B3A4B")))
            setTextColor(Color.parseColor("#00E5FF"))
            setOnClickListener {
                isSymbolsMode = false
                isSecondarySymbols = false
                renderKeyboardKeys()
            }
        }
        row.addView(abcButton)

        // Numeral Script Toggle (Bengali digits vs English digits)
        val scriptToggle = createKeyButton(if (isBanglaNumerals) "১২৩" else "123").apply {
            textSize = 12f
            layoutParams = LinearLayout.LayoutParams(dp(48), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(2, 2, 2, 2)
            }
            setBackgroundDrawable(createKeyBackground(Color.parseColor("#21262D")))
            setTextColor(Color.parseColor("#80CBC4"))
            setOnClickListener {
                isBanglaNumerals = !isBanglaNumerals
                renderKeyboardKeys()
            }
        }
        row.addView(scriptToggle)

        // Spacebar
        val spaceBtn = createKeyButton("Space").apply {
            textSize = 13f
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply {
                setMargins(2, 2, 2, 2)
            }
            setTextColor(Color.parseColor("#B0BEC5"))
        }
        setupSpacebarCursorSwipe(spaceBtn)
        row.addView(spaceBtn)

        // Period
        val periodKey = createKeyButton(".").apply {
            layoutParams = LinearLayout.LayoutParams(dp(36), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(2, 2, 2, 2)
            }
            setOnClickListener {
                triggerHapticClick()
                currentInputConnection?.commitText(".", 1)
            }
        }
        row.addView(periodKey)

        // Enter key
        val enterKey = createKeyButton("↵").apply {
            textSize = 18f
            layoutParams = LinearLayout.LayoutParams(dp(56), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(2, 2, 2, 2)
            }
            setBackgroundDrawable(createKeyBackground(Color.parseColor("#007ACC")))
            setOnClickListener {
                triggerHapticClick()
                commitComposing()
                currentInputConnection?.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
                currentInputConnection?.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
            }
        }
        row.addView(enterKey)

        return row
    }

    private fun buildBottomRow(): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(48)
            ).apply { setMargins(0, 2, 0, 2) }
        }

        // ?123 Symbols Button
        val symButton = createKeyButton("?123").apply {
            textSize = 12f
            layoutParams = LinearLayout.LayoutParams(dp(52), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(2, 2, 2, 2)
            }
            setBackgroundDrawable(createKeyBackground(Color.parseColor("#262D38")))
            setTextColor(Color.WHITE)
            setOnClickListener {
                triggerHapticClick()
                isSymbolsMode = true
                isSecondarySymbols = false
                renderKeyboardKeys()
            }
        }
        row.addView(symButton)

        // Mode Toggle Button (TechuAvro <-> English)
        modeButton = createKeyButton(if (isAvroMode) "TechuAvro" else "ENG").apply {
            textSize = 11f
            layoutParams = LinearLayout.LayoutParams(dp(76), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(2, 2, 2, 2)
            }
            setBackgroundDrawable(createKeyBackground(Color.parseColor("#1B3A4B")))
            setTextColor(Color.parseColor("#00E5FF"))
            setOnClickListener {
                triggerHapticClick()
                isAvroMode = !isAvroMode
                text = if (isAvroMode) "TechuAvro" else "ENG"
                spaceButton?.text = if (isAvroMode) "TechuAvro" else "Space"
                commitComposing()
                updateCandidateView()
            }
        }
        row.addView(modeButton)

        // Punctuation comma
        val commaKey = createKeyButton(",").apply {
            layoutParams = LinearLayout.LayoutParams(dp(32), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(2, 2, 2, 2)
            }
            setOnClickListener { handleCharacter(",") }
        }
        row.addView(commaKey)

        // Spacebar with English Branding & Smooth Cursor Swipe
        spaceButton = createKeyButton(if (isAvroMode) "TechuAvro" else "Space").apply {
            textSize = 13f
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply {
                setMargins(2, 2, 2, 2)
            }
            setTextColor(Color.parseColor("#B0BEC5"))
        }
        setupSpacebarCursorSwipe(spaceButton!!)
        row.addView(spaceButton)

        // Dari / Period
        val periodKey = createKeyButton(if (isAvroMode) "। " else ". ").apply {
            layoutParams = LinearLayout.LayoutParams(dp(34), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(2, 2, 2, 2)
            }
            setOnClickListener {
                triggerHapticClick()
                if (isAvroMode) {
                    commitComposing()
                    currentInputConnection?.commitText("। ", 1)
                } else {
                    commitComposing()
                    currentInputConnection?.commitText(". ", 1)
                }
            }
        }
        row.addView(periodKey)

        // Return / Enter Key
        val enterKey = createKeyButton("↵").apply {
            textSize = 18f
            layoutParams = LinearLayout.LayoutParams(dp(56), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(2, 2, 2, 2)
            }
            setBackgroundDrawable(createKeyBackground(Color.parseColor("#007ACC")))
            setOnClickListener {
                triggerHapticClick()
                commitComposing()
                currentInputConnection?.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
                currentInputConnection?.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
            }
        }
        row.addView(enterKey)

        return row
    }

    private fun handleCharacter(char: String) {
        triggerHapticClick()
        composing.append(char)
        if (isAvroMode) {
            val converted = engine.toBangla(composing.toString())
            currentInputConnection?.setComposingText(converted, 1)
        } else {
            currentInputConnection?.setComposingText(composing.toString(), 1)
        }
        updateCandidateView()
    }

    private fun handleSpace() {
        triggerHapticClick()
        if (composing.isNotEmpty()) {
            val topWord = currentSuggestions.firstOrNull() ?: if (isAvroMode) engine.toBangla(composing.toString()) else composing.toString()
            currentInputConnection?.commitText("$topWord ", 1)
            suggestionManager.recordWord(topWord)
            composing.clear()
            updateCandidateView()
        } else {
            currentInputConnection?.commitText(" ", 1)
        }
    }

    private fun handleBackspace() {
        triggerHapticClick()
        if (composing.isNotEmpty()) {
            composing.deleteCharAt(composing.length - 1)
            if (composing.isNotEmpty()) {
                val converted = if (isAvroMode) engine.toBangla(composing.toString()) else composing.toString()
                currentInputConnection?.setComposingText(converted, 1)
            } else {
                currentInputConnection?.commitText("", 1)
            }
            updateCandidateView()
        } else {
            currentInputConnection?.deleteSurroundingText(1, 0)
        }
    }

    private fun commitComposing() {
        if (composing.isNotEmpty()) {
            val topWord = currentSuggestions.firstOrNull() ?: if (isAvroMode) engine.toBangla(composing.toString()) else composing.toString()
            currentInputConnection?.commitText(topWord, 1)
            suggestionManager.recordWord(topWord)
            composing.clear()
            updateCandidateView()
        }
    }

    private fun selectSuggestion(word: String) {
        triggerHapticClick()
        currentInputConnection?.commitText("$word ", 1)
        suggestionManager.recordWord(word)
        composing.clear()
        updateCandidateView()
    }

    private fun updateCandidateView() {
        val layout = candidateChipsLayout ?: return
        layout.removeAllViews()

        val query = composing.toString()
        currentSuggestions = suggestionManager.getSuggestions(query, isAvroMode)

        if (currentSuggestions.isEmpty()) {
            val emptyHint = TextView(this).apply {
                text = if (isAvroMode) "TechuAvro: টাইপ করুন..." else "English: type to suggest..."
                textSize = 13f
                setTextColor(Color.parseColor("#8E9AA8"))
                setPadding(dp(12), dp(4), dp(12), dp(4))
            }
            layout.addView(emptyHint)
            return
        }

        // Generate suggestion chips:
        // Chip 0: Hero / Primary suggestion (Emphasized, auto-commits on Space)
        // Chips 1, 2: Directly visible beside Hero
        // Chips 3+: Smoothly accessible by sliding horizontally!
        for ((index, word) in currentSuggestions.withIndex()) {
            val isHero = (index == 0 && composing.isNotEmpty())
            val isUserWord = suggestionManager.isUserWord(word)

            val chip = TextView(this).apply {
                text = word
                textSize = if (isHero) 15f else 14f
                setTypeface(null, if (isHero) Typeface.BOLD else Typeface.NORMAL)
                setTextColor(if (isHero) Color.parseColor("#00E5FF") else Color.parseColor("#EDEDED"))
                gravity = Gravity.CENTER
                setPadding(dp(14), dp(5), dp(14), dp(5))

                val bgColor = when {
                    isHero -> Color.parseColor("#1B3A4B")
                    isUserWord -> Color.parseColor("#263238")
                    else -> Color.parseColor("#222832")
                }
                val bgDrawable = GradientDrawable().apply {
                    setColor(bgColor)
                    cornerRadius = dp(8).toFloat()
                    if (isHero) {
                        setStroke(dp(1), Color.parseColor("#00E5FF"))
                    } else if (isUserWord) {
                        setStroke(dp(1), Color.parseColor("#37474F"))
                    }
                }
                background = bgDrawable

                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    dp(32)
                ).apply {
                    setMargins(dp(3), 0, dp(3), 0)
                }

                setOnClickListener {
                    selectSuggestion(word)
                }

                setOnLongClickListener {
                    if (suggestionManager.isUserWord(word)) {
                        suggestionManager.removeUserWord(word)
                        android.widget.Toast.makeText(this@TechuKeyboardService, "Removed: '$word'", android.widget.Toast.LENGTH_SHORT).show()
                        updateCandidateView()
                        true
                    } else {
                        false
                    }
                }
            }
            layout.addView(chip)
        }

        candidateScroll?.scrollTo(0, 0)
    }

    /**
     * Refreshes the top-row clipboard bar with the latest copied items.
     * Tapping any chip immediately pastes it into the focused field!
     */
    private fun refreshClipboardChips() {
        val bar = clipboardBar ?: return
        bar.removeAllViews()

        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        val currentClip = cm?.primaryClip?.getItemAt(0)?.text?.toString()?.trim()

        val chips = mutableListOf<String>()
        if (!currentClip.isNullOrEmpty()) {
            chips.add(currentClip)
        }

        // Add default handy quick-actions
        chips.add("Techuboard")
        chips.add("TechuAvro")

        for (text in chips) {
            val chip = Button(this).apply {
                this.text = if (text.length > 25) text.substring(0, 22) + "…" else text
                textSize = 12f
                isAllCaps = false
                setTextColor(Color.WHITE)
                setBackgroundDrawable(createKeyBackground(Color.parseColor("#263238")))
                setPadding(dp(12), dp(4), dp(12), dp(4))
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    dp(34)
                ).apply { setMargins(4, 0, 4, 0) }
                setOnClickListener {
                    commitComposing()
                    currentInputConnection?.commitText(text, 1)
                }
            }
            bar.addView(chip)
        }
    }

    private fun createKeyButton(label: String): Button {
        return Button(this).apply {
            text = label
            textSize = 16f
            isAllCaps = false
            setTextColor(Color.WHITE)
            setBackgroundDrawable(createKeyBackground(Color.parseColor("#1E242C")))
            setPadding(0, 0, 0, 0)
        }
    }

    private fun createKeyBackground(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(6).toFloat()
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }
}
