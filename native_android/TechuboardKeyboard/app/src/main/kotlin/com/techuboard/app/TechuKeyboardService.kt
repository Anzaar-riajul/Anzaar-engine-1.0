package com.techuboard.app

import android.annotation.SuppressLint
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Techuboard 100% Pure Native Android System Keyboard (IME).
 * Features:
 * - Exact dark modern styling matching the user's design.
 * - Full Avro phonetic engine (ami -> আমি, bangla -> বাংলা) with sanitizeBangla Unicode filter.
 * - Spacebar Swipe to toggle between বাংলা and English!
 * - Dedicated language toggle key (বাং / ENG) on bottom row.
 * - Secondary superscript characters on all keys (1-0, @#$, hold for symbols/actions).
 * - Top Tools & Suggestions strip with Cyan grid toggle, Numpad, Emoji, Clipboard, Cursor D-Pad, Mic.
 * - Native 60fps performance across WhatsApp, Facebook, Messenger, Chrome, etc.
 */
class TechuKeyboardService : InputMethodService() {

    private val engine = TechuAvroEngine()
    private lateinit var suggestionManager: TechuSuggestionManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private var vibrator: Vibrator? = null

    private var isAvroMode = true
    private var shiftState = 0 // 0 = lower, 1 = shifted, 2 = caps lock
    private val composing = StringBuilder()
    private var currentSuggestions = listOf<String>()

    // UI Containers
    private var rootLayout: LinearLayout? = null
    private var topStripContainer: FrameLayout? = null
    private var toolsBar: LinearLayout? = null
    private var suggestionsBar: LinearLayout? = null
    private var suggestionsScroll: HorizontalScrollView? = null
    private var toolDeckOverlay: FrameLayout? = null
    private var keyboardRowsContainer: LinearLayout? = null
    private var spacebarText: TextView? = null
    private var langToggleTv: TextView? = null

    private var isSymbolsMode = false
    private var isSecondarySymbols = false
    private var activeToolName: String? = null

    override fun onCreate() {
        super.onCreate()
        suggestionManager = TechuSuggestionManager(this)
        vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    fun triggerHapticClick() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createOneShot(12, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(12)
            }
        } catch (_: Exception) {}
    }

    override fun onCreateInputView(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#121417"))
            setPadding(dp(4), dp(4), dp(4), dp(6))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        rootLayout = root

        // 1. TOP STRIP (Height 42dp: Contains Toggle Button, Suggestions Bar / Tools Strip, and Pinned Mic)
        val topStrip = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(42)
            ).apply { setMargins(0, 0, 0, dp(4)) }
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#181d24"))
                cornerRadius = dp(8).toFloat()
            }
        }
        topStripContainer = topStrip

        // 1A. Left Toggle Button (Cyan 4-grid)
        val toggleBtn = FrameLayout(this).apply {
            val lp = FrameLayout.LayoutParams(dp(40), dp(36), Gravity.START or Gravity.CENTER_VERTICAL).apply {
                setMargins(dp(3), 0, 0, 0)
            }
            layoutParams = lp
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#1b2a38"))
                cornerRadius = dp(6).toFloat()
                setStroke(1, Color.parseColor("#00e5ff"))
            }
            val tv = TextView(this@TechuKeyboardService).apply {
                text = "⊞"
                textSize = 18f
                setTextColor(Color.parseColor("#00e5ff"))
                gravity = Gravity.CENTER
            }
            addView(tv)
            setOnClickListener {
                triggerHapticClick()
                toggleToolsVsSuggestions()
            }
        }

        // 1B. Center Tools Strip (Numpad, Emoji, Learn, Clipboard, Themes, Cursor, Settings)
        toolsBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            val lp = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            ).apply { setMargins(dp(46), 0, dp(44), 0) }
            layoutParams = lp
            buildToolsBar(this)
        }

        // 1C. Center Suggestions Bar (Candidate chips while typing)
        suggestionsScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            visibility = View.GONE
            val lp = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            ).apply { setMargins(dp(46), 0, dp(44), 0) }
            layoutParams = lp
            suggestionsBar = LinearLayout(this@TechuKeyboardService).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(4), 0, dp(4), 0)
            }
            addView(suggestionsBar)
        }

        // 1D. Right Pinned Microphone Button
        val micBtn = FrameLayout(this).apply {
            val lp = FrameLayout.LayoutParams(dp(38), dp(36), Gravity.END or Gravity.CENTER_VERTICAL).apply {
                setMargins(0, 0, dp(3), 0)
            }
            layoutParams = lp
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#222832"))
                cornerRadius = dp(6).toFloat()
            }
            val tv = TextView(this@TechuKeyboardService).apply {
                text = "🎙"
                textSize = 15f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
            }
            addView(tv)
            setOnClickListener {
                triggerHapticClick()
                android.widget.Toast.makeText(this@TechuKeyboardService, "ভয়েস টাইপিং চালু হচ্ছে...", android.widget.Toast.LENGTH_SHORT).show()
            }
        }

        topStrip.addView(toggleBtn)
        topStrip.addView(toolsBar)
        topStrip.addView(suggestionsScroll)
        topStrip.addView(micBtn)
        root.addView(topStrip)

        // 2. TOOL DECK OVERLAY (Opens when Numpad, Emoji, Clipboard, Cursor tools are tapped)
        toolDeckOverlay = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(210)
            )
            visibility = View.GONE
            setBackgroundColor(Color.parseColor("#161b22"))
        }
        root.addView(toolDeckOverlay)

        // 3. MAIN KEYBOARD ROWS CONTAINER (QWERTY with superscripts, shift, enter, spacebar)
        keyboardRowsContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        root.addView(keyboardRowsContainer)

        renderKeyboardKeys()
        return root
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        composing.clear()
        closeToolDeck()
        updateCandidateView()
        updateLanguageUI()
    }

    fun toggleLanguageMode() {
        commitComposing()
        isAvroMode = !isAvroMode
        updateLanguageUI()
        triggerHapticClick()
        val msg = if (isAvroMode) "বাংলা (TechuAvro) মোড চালু" else "English Keyboard Mode"
        android.widget.Toast.makeText(this, msg, android.widget.Toast.LENGTH_SHORT).show()
    }

    private fun updateLanguageUI() {
        spacebarText?.text = if (isAvroMode) "‹ বাংলা ›" else "‹ English ›"
        spacebarText?.setTextColor(if (isAvroMode) Color.parseColor("#00E5FF") else Color.parseColor("#B0BEC5"))
        langToggleTv?.text = if (isAvroMode) "বাং" else "ENG"
        langToggleTv?.setTextColor(if (isAvroMode) Color.parseColor("#00E5FF") else Color.parseColor("#80CBC4"))
    }

    private fun toggleToolsVsSuggestions() {
        val sScroll = suggestionsScroll ?: return
        val tBar = toolsBar ?: return
        if (sScroll.visibility == View.VISIBLE) {
            sScroll.visibility = View.GONE
            tBar.visibility = View.VISIBLE
        } else {
            tBar.visibility = View.GONE
            sScroll.visibility = View.VISIBLE
        }
    }

    private fun buildToolsBar(container: LinearLayout) {
        container.removeAllViews()
        val tools = listOf(
            Pair("🔢", "numpad"),
            Pair("😊", "emoji"),
            Pair("🎓", "learn"),
            Pair("📋", "clip"),
            Pair("🎨", "theme"),
            Pair("🎯", "cursor"),
            Pair("⚙️", "settings")
        )

        for ((icon, name) in tools) {
            val btn = FrameLayout(this).apply {
                layoutParams = LinearLayout.LayoutParams(0, dp(34), 1f).apply {
                    setMargins(dp(2), 0, dp(2), 0)
                }
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#222832"))
                    cornerRadius = dp(6).toFloat()
                }
                val tv = TextView(this@TechuKeyboardService).apply {
                    text = icon
                    textSize = 14f
                    gravity = Gravity.CENTER
                }
                addView(tv)
                setOnClickListener {
                    triggerHapticClick()
                    openToolDeck(name)
                }
            }
            container.addView(btn)
        }
    }

    private fun openToolDeck(toolName: String) {
        val deck = toolDeckOverlay ?: return
        val keys = keyboardRowsContainer ?: return

        if (activeToolName == toolName && deck.visibility == View.VISIBLE) {
            closeToolDeck()
            return
        }

        activeToolName = toolName
        deck.removeAllViews()
        deck.visibility = View.VISIBLE
        keys.visibility = View.GONE

        when (toolName) {
            "numpad" -> buildNumpadDeck(deck)
            "emoji" -> buildEmojiDeck(deck)
            "clip" -> buildClipboardDeck(deck)
            "cursor" -> buildCursorDeck(deck)
            "theme" -> buildThemeDeck(deck)
            "settings" -> buildSettingsDeck(deck)
            "learn" -> buildLearnDeck(deck)
        }
    }

    private fun closeToolDeck() {
        activeToolName = null
        toolDeckOverlay?.visibility = View.GONE
        keyboardRowsContainer?.visibility = View.VISIBLE
    }

    private fun buildNumpadDeck(deck: FrameLayout) {
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(8), dp(16), dp(8))
        }

        val rows = listOf(
            listOf("1", "2", "3"),
            listOf("4", "5", "6"),
            listOf("7", "8", "9"),
            listOf("⌫", "0", "✓")
        )

        for (r in rows) {
            val rowLayout = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(46)).apply {
                    setMargins(0, dp(2), 0, dp(2))
                }
            }
            for (key in r) {
                val btn = FrameLayout(this).apply {
                    layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply {
                        setMargins(dp(4), 0, dp(4), 0)
                    }
                    background = GradientDrawable().apply {
                        setColor(if (key == "✓") Color.parseColor("#007ACC") else Color.parseColor("#1E242C"))
                        cornerRadius = dp(8).toFloat()
                    }
                    val tv = TextView(this@TechuKeyboardService).apply {
                        text = key
                        textSize = 20f
                        setTextColor(Color.WHITE)
                        typeface = Typeface.DEFAULT_BOLD
                        gravity = Gravity.CENTER
                    }
                    addView(tv)
                    setOnClickListener {
                        triggerHapticClick()
                        when (key) {
                            "⌫" -> handleBackspace()
                            "✓" -> closeToolDeck()
                            else -> currentInputConnection?.commitText(key, 1)
                        }
                    }
                }
                rowLayout.addView(btn)
            }
            layout.addView(rowLayout)
        }
        deck.addView(layout)
    }

    private fun buildEmojiDeck(deck: FrameLayout) {
        val scroll = HorizontalScrollView(this).apply {
            val emojiLayout = LinearLayout(this@TechuKeyboardService).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(8), dp(8), dp(8), dp(8))
            }
            val row1 = listOf("😀", "😂", "🥰", "😍", "🤣", "😊", "🙏", "👍", "❤️", "🔥", "✨")
            val row2 = listOf("🇧🇩", "🎉", "💯", "😎", "🥺", "😭", "🤲", "👏", "🙌", "💪", "💐")
            val row3 = listOf("👌", "✌️", "🤔", "😴", "🥳", "😇", "🤩", "💖", "🌟", "🌹", "☕")

            for (r in listOf(row1, row2, row3)) {
                val rowLayout = LinearLayout(this@TechuKeyboardService).apply {
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(0, dp(4), 0, dp(4))
                }
                for (em in r) {
                    val tv = TextView(this@TechuKeyboardService).apply {
                        text = em
                        textSize = 24f
                        setPadding(dp(10), dp(4), dp(10), dp(4))
                        setOnClickListener {
                            triggerHapticClick()
                            currentInputConnection?.commitText(em, 1)
                        }
                    }
                    rowLayout.addView(tv)
                }
                emojiLayout.addView(rowLayout)
            }

            val closeBtn = TextView(this@TechuKeyboardService).apply {
                text = "⌨️ কীবোর্ডে ফিরে যান"
                textSize = 13f
                setTextColor(Color.parseColor("#00E5FF"))
                gravity = Gravity.CENTER
                setPadding(0, dp(8), 0, 0)
                setOnClickListener { closeToolDeck() }
            }
            emojiLayout.addView(closeBtn)
            addView(emojiLayout)
        }
        deck.addView(scroll)
    }

    private fun buildClipboardDeck(deck: FrameLayout) {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        val clip = cm?.primaryClip?.getItemAt(0)?.text?.toString() ?: ""

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(16))
        }

        val title = TextView(this).apply {
            text = "📋 সম্প্রতি কপি করা টেক্সট (১-ট্যাপে পেস্ট)"
            textSize = 14f
            setTextColor(Color.parseColor("#8B949E"))
            setPadding(0, 0, 0, dp(12))
        }
        layout.addView(title)

        if (clip.isNotEmpty()) {
            val clipCard = TextView(this).apply {
                text = clip
                textSize = 15f
                setTextColor(Color.WHITE)
                maxLines = 3
                setPadding(dp(16), dp(12), dp(16), dp(12))
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#1E242C"))
                    cornerRadius = dp(8).toFloat()
                    setStroke(1, Color.parseColor("#00E5FF"))
                }
                setOnClickListener {
                    triggerHapticClick()
                    currentInputConnection?.commitText(clip, 1)
                    closeToolDeck()
                }
            }
            layout.addView(clipCard)
        } else {
            val emptyTv = TextView(this).apply {
                text = "ক্লিপবোর্ডে কোনো লেখা নেই।"
                textSize = 14f
                setTextColor(Color.GRAY)
            }
            layout.addView(emptyTv)
        }

        val backBtn = TextView(this).apply {
            text = "✕ কীবোর্ড বন্ধ করুন"
            textSize = 13f
            setTextColor(Color.parseColor("#00E5FF"))
            gravity = Gravity.CENTER
            setPadding(0, dp(20), 0, 0)
            setOnClickListener { closeToolDeck() }
        }
        layout.addView(backBtn)

        deck.addView(layout)
    }

    private fun buildCursorDeck(deck: FrameLayout) {
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(20), dp(12), dp(20), dp(12))
        }

        val title = TextView(this).apply {
            text = "🎯 প্রিসিশন কার্সর নেভিগেশন (D-Pad)"
            textSize = 13f
            setTextColor(Color.parseColor("#8B949E"))
            setPadding(0, 0, 0, dp(14))
        }
        layout.addView(title)

        val row1 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        val actions = listOf(
            Pair("◀ বামে", -1),
            Pair("ডানে ▶", 1),
            Pair("⌫ ডিলিট", 0),
            Pair("✕ সম্পন্ন", 99)
        )

        for ((label, code) in actions) {
            val btn = TextView(this).apply {
                text = label
                textSize = 14f
                setTextColor(Color.WHITE)
                setPadding(dp(16), dp(12), dp(16), dp(12))
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#1E242C"))
                    cornerRadius = dp(8).toFloat()
                    setStroke(1, Color.parseColor("#30363D"))
                }
                setOnClickListener {
                    triggerHapticClick()
                    when (code) {
                        -1 -> currentInputConnection?.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_LEFT))
                        1 -> currentInputConnection?.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_RIGHT))
                        0 -> handleBackspace()
                        99 -> closeToolDeck()
                    }
                }
            }
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(dp(6), 0, dp(6), 0)
            }
            row1.addView(btn, lp)
        }
        layout.addView(row1)
        deck.addView(layout)
    }

    private fun buildThemeDeck(deck: FrameLayout) {
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(16), dp(20), dp(16))
        }
        val title = TextView(this).apply {
            text = "🎨 থিম নির্বাচন"
            textSize = 15f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, 0, dp(12))
        }
        layout.addView(title)

        val themes = listOf(
            Pair("Midnight Dark (ডিফল্ট)", "#121417"),
            Pair("Slate Black", "#0B0E14"),
            Pair("Deep Navy", "#0D1B2A")
        )

        for ((name, colorHex) in themes) {
            val card = TextView(this).apply {
                text = "✓ $name"
                textSize = 14f
                setTextColor(Color.WHITE)
                setPadding(dp(16), dp(10), dp(16), dp(10))
                background = GradientDrawable().apply {
                    setColor(Color.parseColor(colorHex))
                    cornerRadius = dp(8).toFloat()
                    setStroke(1, Color.parseColor("#00E5FF"))
                }
                setOnClickListener {
                    triggerHapticClick()
                    rootLayout?.setBackgroundColor(Color.parseColor(colorHex))
                    closeToolDeck()
                }
            }
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, dp(8))
            }
            layout.addView(card, lp)
        }
        deck.addView(layout)
    }

    private fun buildSettingsDeck(deck: FrameLayout) {
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(16), dp(20), dp(16))
        }
        val title = TextView(this).apply {
            text = "⚙️ কীবোর্ড সেটিংস"
            textSize = 16f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, 0, dp(14))
        }
        layout.addView(title)

        val btnSettings = TextView(this).apply {
            text = "Android ইনপুট মেথড সেটিংস ওপেন করুন"
            textSize = 14f
            setTextColor(Color.WHITE)
            setPadding(dp(16), dp(12), dp(16), dp(12))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#238636"))
                cornerRadius = dp(8).toFloat()
            }
            setOnClickListener {
                triggerHapticClick()
                val intent = Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
            }
        }
        layout.addView(btnSettings)

        val btnClose = TextView(this).apply {
            text = "✕ কীবোর্ডে ফিরে যান"
            textSize = 13f
            setTextColor(Color.parseColor("#00E5FF"))
            gravity = Gravity.CENTER
            setPadding(0, dp(20), 0, 0)
            setOnClickListener { closeToolDeck() }
        }
        layout.addView(btnClose)

        deck.addView(layout)
    }

    private fun buildLearnDeck(deck: FrameLayout) {
        val scroll = HorizontalScrollView(this).apply {
            val layout = LinearLayout(this@TechuKeyboardService).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(16), dp(12), dp(16), dp(12))
            }
            val title = TextView(this@TechuKeyboardService).apply {
                text = "🎓 জনপ্রিয় যুক্তবর্ণ টাইপিং গাইড"
                textSize = 14f
                setTextColor(Color.parseColor("#00E5FF"))
                setPadding(0, 0, 0, dp(8))
            }
            layout.addView(title)

            val guides = listOf(
                "ক্ষ = kkh", "জ্ঞ = jng", "ঞ্চ = nc", "ঞ্জ = nj",
                "ত্র = tr", "শ্র = shr", "ঙ্গ = Ng", "দ্ধ = ddh"
            )
            for (g in guides) {
                val tv = TextView(this@TechuKeyboardService).apply {
                    text = g
                    textSize = 15f
                    setTextColor(Color.WHITE)
                    setPadding(0, dp(4), 0, dp(4))
                }
                layout.addView(tv)
            }

            val closeTv = TextView(this@TechuKeyboardService).apply {
                text = "✕ বন্ধ করুন"
                textSize = 13f
                setTextColor(Color.parseColor("#00E5FF"))
                setPadding(0, dp(12), 0, 0)
                setOnClickListener { closeToolDeck() }
            }
            layout.addView(closeTv)
            addView(layout)
        }
        deck.addView(scroll)
    }

    // 4. RENDERING MAIN KEYBOARD ROWS
    private fun renderKeyboardKeys() {
        val container = keyboardRowsContainer ?: return
        container.removeAllViews()

        if (!isSymbolsMode) {
            // QWERTY ALPHABET LAYOUT
            val isUpper = (shiftState > 0)
            val r1 = listOf(
                Pair("q", "1"), Pair("w", "2"), Pair("e", "3"), Pair("r", "4"), Pair("t", "5"),
                Pair("y", "6"), Pair("u", "7"), Pair("i", "8"), Pair("o", "9"), Pair("p", "0")
            )
            val r2 = listOf(
                Pair("a", "@"), Pair("s", "#"), Pair("d", "$"), Pair("f", "_"), Pair("g", "&"),
                Pair("h", "-"), Pair("j", "+"), Pair("k", "("), Pair("l", ")")
            )
            val r3 = listOf(
                Pair("z", "↶"), Pair("x", "✂"), Pair("c", "📋"), Pair("v", "📥"), Pair("b", "𝐁"),
                Pair("n", "!"), Pair("m", "↷")
            )

            container.addView(buildKeyRow(r1, isUpper))
            container.addView(buildKeyRow(r2, isUpper))
            container.addView(buildSpecialRow3(r3, isUpper))
            container.addView(buildBottomRow())
        } else {
            // SYMBOLS LAYOUT (?123)
            buildSymbolsPage(container)
        }
    }

    private fun buildKeyRow(keys: List<Pair<String, String>>, isUpper: Boolean): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            weightSum = keys.size.toFloat()
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(48)
            ).apply { setMargins(0, dp(2), 0, dp(2)) }
        }

        for ((primary, sub) in keys) {
            val mainChar = if (isUpper) primary.uppercase() else primary
            val keyView = createNativeKeyView(mainChar, sub, isSpecial = false) { tappedChar ->
                handleCharacter(tappedChar)
            }
            val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply {
                setMargins(dp(2), 0, dp(2), 0)
            }
            row.addView(keyView, lp)
        }
        return row
    }

    private fun buildSpecialRow3(keys: List<Pair<String, String>>, isUpper: Boolean): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(48)
            ).apply { setMargins(0, dp(2), 0, dp(2)) }
        }

        // Shift Key
        val shiftKey = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(44), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(dp(2), 0, dp(2), 0)
            }
            val borderColor = if (shiftState > 0) Color.parseColor("#00E5FF") else Color.parseColor("#2D333B")
            val bgColor = if (shiftState > 0) Color.parseColor("#1B2A38") else Color.parseColor("#1E242C")
            background = GradientDrawable().apply {
                setColor(bgColor)
                cornerRadius = dp(6).toFloat()
                setStroke(1, borderColor)
            }
            val tv = TextView(this@TechuKeyboardService).apply {
                text = if (shiftState == 2) "⇪" else "⇧"
                textSize = 18f
                setTextColor(if (shiftState > 0) Color.parseColor("#00E5FF") else Color.WHITE)
                gravity = Gravity.CENTER
            }
            addView(tv)
            setOnClickListener {
                triggerHapticClick()
                shiftState = (shiftState + 1) % 3
                renderKeyboardKeys()
            }
        }
        row.addView(shiftKey)

        // Middle 7 alphabet keys
        val keysLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f)
            weightSum = keys.size.toFloat()
        }
        for ((primary, sub) in keys) {
            val mainChar = if (isUpper) primary.uppercase() else primary
            val keyView = createNativeKeyView(mainChar, sub, isSpecial = false) { tappedChar ->
                handleCharacter(tappedChar)
            }
            val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply {
                setMargins(dp(2), 0, dp(2), 0)
            }
            keysLayout.addView(keyView, lp)
        }
        row.addView(keysLayout)

        // Backspace Key
        val backspaceKey = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(44), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(dp(2), 0, dp(2), 0)
            }
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#1E242C"))
                cornerRadius = dp(6).toFloat()
                setStroke(1, Color.parseColor("#2D333B"))
            }
            val tv = TextView(this@TechuKeyboardService).apply {
                text = "⌫"
                textSize = 18f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
            }
            addView(tv)
            setOnClickListener { handleBackspace() }
        }
        row.addView(backspaceKey)

        return row
    }

    private fun buildBottomRow(): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(48)
            ).apply { setMargins(0, dp(2), 0, dp(2)) }
        }

        // 1. ?123 Button
        val symBtn = createButtonKey("?123", widthDp = 48) {
            isSymbolsMode = true
            isSecondarySymbols = false
            renderKeyboardKeys()
        }
        row.addView(symBtn)

        // 2. Dedicated Language Toggle Button (বাং / ENG)
        val langBtn = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(44), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(dp(2), 0, dp(2), 0)
            }
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#1B2A38"))
                cornerRadius = dp(6).toFloat()
                setStroke(1, Color.parseColor("#00E5FF"))
            }
            val tv = TextView(this@TechuKeyboardService).apply {
                text = if (isAvroMode) "বাং" else "ENG"
                textSize = 14f
                setTextColor(if (isAvroMode) Color.parseColor("#00E5FF") else Color.parseColor("#80CBC4"))
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
            }
            langToggleTv = tv
            addView(tv)
            setOnClickListener {
                toggleLanguageMode()
            }
        }
        row.addView(langBtn)

        // 3. Comma
        val commaBtn = createButtonKey(",", widthDp = 30) {
            if (isAvroMode) handleCharacter(",") else currentInputConnection?.commitText(",", 1)
        }
        row.addView(commaBtn)

        // 4. Spacebar with "‹ বাংলা ›" / "‹ English ›" and Swipe to switch language
        val spaceBtn = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply {
                setMargins(dp(2), 0, dp(2), 0)
            }
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#1E242C"))
                cornerRadius = dp(6).toFloat()
                setStroke(1, Color.parseColor("#2D333B"))
            }
            spacebarText = TextView(this@TechuKeyboardService).apply {
                text = if (isAvroMode) "‹ বাংলা ›" else "‹ English ›"
                textSize = 14f
                setTextColor(if (isAvroMode) Color.parseColor("#00E5FF") else Color.parseColor("#B0BEC5"))
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
            }
            addView(spacebarText)
            setupSpacebarTouch(this)
        }
        row.addView(spaceBtn)

        // 5. Dari / Dot
        val dotBtn = createButtonKey(if (isAvroMode) "।" else ".", widthDp = 32) {
            if (isAvroMode) {
                commitComposing()
                currentInputConnection?.commitText("। ", 1)
            } else {
                currentInputConnection?.commitText(". ", 1)
            }
        }
        row.addView(dotBtn)

        // 6. Return / Enter (Vibrant Blue accent)
        val enterBtn = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(52), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                setMargins(dp(2), 0, dp(2), 0)
            }
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#007ACC"))
                cornerRadius = dp(6).toFloat()
            }
            val tv = TextView(this@TechuKeyboardService).apply {
                text = "↵"
                textSize = 20f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
            }
            addView(tv)
            setOnClickListener { handleEnter() }
        }
        row.addView(enterBtn)

        return row
    }

    private fun buildSymbolsPage(container: LinearLayout) {
        val row1 = listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0")
        val row2 = listOf("@", "#", "$", "_", "&", "-", "+", "(", ")", "/")
        val row3 = listOf("*", "\"", "'", ":", ";", "!", "?", "।", "৳")

        container.addView(buildSymbolKeyRow(row1))
        container.addView(buildSymbolKeyRow(row2))
        container.addView(buildSymbolKeyRow(row3))

        // Symbols bottom row
        val bottom = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48))
        }

        val abcBtn = createButtonKey("ABC", widthDp = 60) {
            isSymbolsMode = false
            renderKeyboardKeys()
        }
        bottom.addView(abcBtn)

        val spaceBtn = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply {
                setMargins(dp(2), 0, dp(2), 0)
            }
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#1E242C"))
                cornerRadius = dp(6).toFloat()
            }
            val tv = TextView(this@TechuKeyboardService).apply {
                text = "Space"
                textSize = 14f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
            }
            addView(tv)
            setOnClickListener {
                triggerHapticClick()
                currentInputConnection?.commitText(" ", 1)
            }
        }
        bottom.addView(spaceBtn)

        val enterBtn = createButtonKey("↵", widthDp = 56) { handleEnter() }
        bottom.addView(enterBtn)

        container.addView(bottom)
    }

    private fun buildSymbolKeyRow(keys: List<String>): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48)).apply {
                setMargins(0, dp(2), 0, dp(2))
            }
        }
        for (k in keys) {
            val keyView = createButtonKey(k, widthDp = 0, weight = 1f) {
                currentInputConnection?.commitText(k, 1)
            }
            row.addView(keyView)
        }
        return row
    }

    // 5. HELPER VIEW BUILDERS
    private fun createNativeKeyView(
        mainChar: String,
        subChar: String,
        isSpecial: Boolean,
        onTap: (String) -> Unit
    ): FrameLayout {
        return FrameLayout(this).apply {
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#1E242C"))
                cornerRadius = dp(6).toFloat()
                setStroke(1, Color.parseColor("#2D333B"))
            }

            // Top-right secondary superscript
            if (subChar.isNotEmpty()) {
                val subTv = TextView(this@TechuKeyboardService).apply {
                    text = subChar
                    textSize = 9.5f
                    setTextColor(Color.parseColor("#8B949E"))
                    gravity = Gravity.END or Gravity.TOP
                    setPadding(0, dp(2), dp(5), 0)
                    layoutParams = FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                }
                addView(subTv)
            }

            // Center primary main character
            val mainTv = TextView(this@TechuKeyboardService).apply {
                text = mainChar
                textSize = 17f
                setTextColor(Color.WHITE)
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            }
            addView(mainTv)

            setOnClickListener {
                triggerHapticClick()
                onTap(mainChar)
            }

            setOnLongClickListener {
                triggerHapticClick()
                if (subChar.isNotEmpty()) {
                    when (subChar) {
                        "↶" -> android.widget.Toast.makeText(this@TechuKeyboardService, "Undo", android.widget.Toast.LENGTH_SHORT).show()
                        "↷" -> android.widget.Toast.makeText(this@TechuKeyboardService, "Redo", android.widget.Toast.LENGTH_SHORT).show()
                        "𝐁" -> android.widget.Toast.makeText(this@TechuKeyboardService, "Bold", android.widget.Toast.LENGTH_SHORT).show()
                        "✂" -> android.widget.Toast.makeText(this@TechuKeyboardService, "Cut", android.widget.Toast.LENGTH_SHORT).show()
                        "📋" -> openToolDeck("clip")
                        else -> currentInputConnection?.commitText(subChar, 1)
                    }
                }
                true
            }
        }
    }

    private fun createButtonKey(label: String, widthDp: Int, weight: Float = 0f, onClick: () -> Unit): FrameLayout {
        return FrameLayout(this).apply {
            layoutParams = if (weight > 0f) {
                LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, weight).apply {
                    setMargins(dp(2), 0, dp(2), 0)
                }
            } else {
                LinearLayout.LayoutParams(dp(widthDp), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                    setMargins(dp(2), 0, dp(2), 0)
                }
            }
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#1E242C"))
                cornerRadius = dp(6).toFloat()
                setStroke(1, Color.parseColor("#2D333B"))
            }
            val tv = TextView(this@TechuKeyboardService).apply {
                text = label
                textSize = 14f
                setTextColor(Color.WHITE)
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
            }
            addView(tv)
            setOnClickListener {
                triggerHapticClick()
                onClick()
            }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun setupSpacebarTouch(spaceView: View) {
        var startX = 0f
        var startY = 0f
        var isSwiping = false
        val swipeThresholdPx = 28f * resources.displayMetrics.density

        spaceView.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.rawX
                    startY = event.rawY
                    isSwiping = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaX = event.rawX - startX
                    val deltaY = event.rawY - startY
                    // SWIPE DETECTED: TOGGLE LANGUAGE!
                    if (!isSwiping && Math.abs(deltaX) > swipeThresholdPx && Math.abs(deltaX) > Math.abs(deltaY) * 1.3) {
                        isSwiping = true
                        toggleLanguageMode()
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!isSwiping) {
                        handleSpace()
                    }
                    isSwiping = false
                    true
                }
                else -> false
            }
        }
    }

    // 6. KEYBOARD ENGINE LOGIC (AVRO, SUGGESTIONS, BACKSPACE)
    private fun handleCharacter(char: String) {
        closeToolDeck()
        triggerHapticClick()

        if (!isAvroMode) {
            // ENGLISH MODE: Direct typing without transliteration!
            currentInputConnection?.commitText(char, 1)
            if (shiftState == 1) {
                shiftState = 0
                renderKeyboardKeys()
            }
            return
        }

        // BANGLA AVRO PHONETIC MODE:
        composing.append(char)
        val converted = engine.toBangla(composing.toString())
        currentInputConnection?.setComposingText(converted, 1)

        // Auto-unshift if shifted
        if (shiftState == 1) {
            shiftState = 0
            renderKeyboardKeys()
        }

        updateCandidateView()
    }

    private fun handleSpace() {
        triggerHapticClick()
        if (isAvroMode && composing.isNotEmpty()) {
            val topWord = currentSuggestions.firstOrNull() ?: engine.toBangla(composing.toString())
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
        if (isAvroMode && composing.isNotEmpty()) {
            composing.deleteCharAt(composing.length - 1)
            if (composing.isNotEmpty()) {
                val converted = engine.toBangla(composing.toString())
                currentInputConnection?.setComposingText(converted, 1)
            } else {
                currentInputConnection?.commitText("", 1)
            }
            updateCandidateView()
        } else {
            currentInputConnection?.deleteSurroundingText(1, 0)
        }
    }

    private fun handleEnter() {
        triggerHapticClick()
        commitComposing()
        currentInputConnection?.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
        currentInputConnection?.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
    }

    private fun commitComposing() {
        if (isAvroMode && composing.isNotEmpty()) {
            val topWord = currentSuggestions.firstOrNull() ?: engine.toBangla(composing.toString())
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
        val bar = suggestionsBar ?: return
        bar.removeAllViews()

        val query = composing.toString()
        if (query.isEmpty() || !isAvroMode) {
            // Revert back to tools strip when not composing
            suggestionsScroll?.visibility = View.GONE
            toolsBar?.visibility = View.VISIBLE
            return
        }

        // Show suggestions strip when typing
        toolsBar?.visibility = View.GONE
        suggestionsScroll?.visibility = View.VISIBLE

        currentSuggestions = suggestionManager.getSuggestions(query, isAvroMode)

        for ((index, word) in currentSuggestions.withIndex()) {
            val isHero = (index == 0)
            val chip = TextView(this).apply {
                text = if (isHero) "$word ★" else word
                textSize = if (isHero) 15f else 14f
                setTypeface(null, if (isHero) Typeface.BOLD else Typeface.NORMAL)
                setTextColor(if (isHero) Color.parseColor("#00E5FF") else Color.WHITE)
                gravity = Gravity.CENTER
                setPadding(dp(12), dp(4), dp(12), dp(4))

                background = GradientDrawable().apply {
                    setColor(if (isHero) Color.parseColor("#1B2A38") else Color.parseColor("#222832"))
                    cornerRadius = dp(6).toFloat()
                    if (isHero) setStroke(1, Color.parseColor("#00E5FF"))
                }

                setOnClickListener { selectSuggestion(word) }
            }
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(32)).apply {
                setMargins(dp(3), 0, dp(3), 0)
            }
            bar.addView(chip, lp)
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }
}
