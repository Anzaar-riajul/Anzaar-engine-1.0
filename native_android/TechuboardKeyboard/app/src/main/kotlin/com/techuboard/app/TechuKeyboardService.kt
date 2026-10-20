package com.techuboard.app

import android.annotation.SuppressLint
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.inputmethodservice.InputMethodService
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.webkit.JavascriptInterface
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.Toast

/**
 * TechuKeyboardService
 * 
 * Directly hosts the exact 100% same-to-same Techuboard UI (keyboard_ime.html)
 * with all vector SVG tools, inner panels (Numpad, Emoji, Learn, Clipboard,
 * Themes, Cursor D-Pad, Settings), real-time Avro transliteration, native
 * Android SpeechRecognizer voice typing, and Android InputConnection integration.
 */
class TechuKeyboardService : InputMethodService() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var vibrator: Vibrator? = null
    private var audioManager: AudioManager? = null
    private var webView: WebView? = null
    private var rootContainer: FrameLayout? = null
    private var speechRecognizer: SpeechRecognizer? = null

    var soundEnabled: Boolean = true
    var hapticEnabled: Boolean = true
    var currentImeAction: Int = EditorInfo.IME_ACTION_NONE
    var isListeningVoice: Boolean = false
    var voiceLanguage: String = "bn-BD"

    override fun onCreate() {
        super.onCreate()
        vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        try {
            window?.window?.addFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED)
        } catch (_: Exception) {}
    }

    override fun onEvaluateInputViewShown(): Boolean {
        super.onEvaluateInputViewShown()
        return true
    }

    override fun onEvaluateFullscreenMode(): Boolean {
        return false
    }

    override fun onShowInputRequested(flags: Int, configChange: Boolean): Boolean {
        return true
    }

    private fun getErgonomicHeightPx(): Int {
        val dm = resources.displayMetrics
        val density = dm.density
        val isLandscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        return if (isLandscape) {
            val screenHeightDp = dm.heightPixels / density
            ((screenHeightDp * 0.46f).coerceIn(160f, 190f) * density).toInt()
        } else {
            (285 * density).toInt()
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreateInputView(): View {
        val root = FrameLayout(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            setBackgroundColor(Color.parseColor("#0D1117"))
        }
        rootContainer = root

        val kbdHeightPx = getErgonomicHeightPx()

        val wv = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                kbdHeightPx
            )
            setBackgroundColor(Color.parseColor("#0D1117"))

            // World-Class Low-Latency Touch & Hardware Rendering Pipeline
            setLayerType(View.LAYER_TYPE_HARDWARE, null)
            isHapticFeedbackEnabled = false
            isSoundEffectsEnabled = false
            isLongClickable = false
            setOnLongClickListener { true }

            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                allowFileAccess = true
                setSupportZoom(false)
                useWideViewPort = false
                loadWithOverviewMode = false
                cacheMode = WebSettings.LOAD_DEFAULT
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    offscreenPreRaster = true
                }
            }

            isFocusable = true
            isFocusableInTouchMode = true
            isVerticalScrollBarEnabled = false
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER

            addJavascriptInterface(AndroidKeyboardBridge(this@TechuKeyboardService), "AndroidKeyboard")
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    syncEditorStateToWeb()
                }
            }
            loadUrl("file:///android_asset/keyboard_ime.html")
        }

        webView = wv
        root.addView(wv)
        return root
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        val newHeight = getErgonomicHeightPx()
        webView?.let { wv ->
            wv.layoutParams = wv.layoutParams?.apply {
                height = newHeight
            } ?: FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, newHeight)
            wv.requestLayout()
        }
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)

        val inputType = info?.inputType ?: 0
        val classType = inputType and InputType.TYPE_MASK_CLASS
        val variation = inputType and InputType.TYPE_MASK_VARIATION

        val isPassword = variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                (classType == InputType.TYPE_CLASS_NUMBER && variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD)

        val isNumeric = classType == InputType.TYPE_CLASS_NUMBER ||
                classType == InputType.TYPE_CLASS_PHONE ||
                classType == InputType.TYPE_CLASS_DATETIME

        currentImeAction = info?.imeOptions?.and(EditorInfo.IME_MASK_ACTION) ?: EditorInfo.IME_ACTION_NONE
        val isMultiLine = (inputType and InputType.TYPE_TEXT_FLAG_MULTI_LINE) != 0

        syncEditorStateToWeb(isPassword, isNumeric, currentImeAction, isMultiLine)
    }

    private fun syncEditorStateToWeb(
        isPassword: Boolean = false,
        isNumeric: Boolean = false,
        imeAction: Int = EditorInfo.IME_ACTION_NONE,
        isMultiLine: Boolean = false
    ) {
        val js = """
            if (typeof onEditorStateChanged === 'function') {
                onEditorStateChanged({
                    isPassword: $isPassword,
                    isNumeric: $isNumeric,
                    imeAction: $imeAction,
                    isMultiLine: $isMultiLine
                });
            }
            if (typeof resetComposingState === 'function') {
                resetComposingState();
            }
        """.trimIndent()
        webView?.evaluateJavascript(js, null)
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            speechRecognizer?.destroy()
        } catch (_: Exception) {}
        speechRecognizer = null
        webView?.destroy()
        webView = null
    }

    fun triggerHapticClick(type: String = "click") {
        if (soundEnabled) {
            try {
                val fx = when (type) {
                    "space" -> AudioManager.FX_KEYPRESS_SPACEBAR
                    "delete" -> AudioManager.FX_KEYPRESS_DELETE
                    "action" -> AudioManager.FX_KEYPRESS_RETURN
                    else -> AudioManager.FX_KEYPRESS_STANDARD
                }
                audioManager?.playSoundEffect(fx, 0.45f)
            } catch (_: Exception) {}
        }
        if (hapticEnabled) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val effectId = when (type) {
                        "tick" -> VibrationEffect.EFFECT_TICK
                        "action" -> VibrationEffect.EFFECT_HEAVY_CLICK
                        else -> VibrationEffect.EFFECT_CLICK
                    }
                    vibrator?.vibrate(VibrationEffect.createPredefined(effectId))
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val duration = when (type) {
                        "tick" -> 5L
                        "action" -> 16L
                        else -> 10L
                    }
                    vibrator?.vibrate(VibrationEffect.createOneShot(duration, 220))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(10L)
                }
            } catch (_: Exception) {}
        }
    }

    fun toggleVoiceTyping() {
        mainHandler.post {
            if (isListeningVoice) {
                stopVoiceTyping()
            } else {
                startVoiceTyping()
            }
        }
    }

    fun startVoiceTyping() {
        mainHandler.post {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                    Toast.makeText(this, "ভয়েস টাইপিংয়ের জন্য মাইক্রোফোন পারমিশন দিন", Toast.LENGTH_LONG).show()
                    val intent = Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                    return@post
                }
            }

            if (!SpeechRecognizer.isRecognitionAvailable(this)) {
                Toast.makeText(this, "ভয়েস রিকগনিশন ইঞ্জিন ইনস্টল নেই", Toast.LENGTH_SHORT).show()
                return@post
            }

            try {
                speechRecognizer?.destroy()
                speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
                    setRecognitionListener(object : RecognitionListener {
                        override fun onReadyForSpeech(params: Bundle?) {
                            isListeningVoice = true
                            webView?.evaluateJavascript("if (typeof updateVoiceUI === 'function') updateVoiceUI(true);", null)
                            webView?.evaluateJavascript("if (typeof setVoiceStatus === 'function') setVoiceStatus('শুনছি... পরিষ্কারভাবে বলুন');", null)
                        }

                        override fun onBeginningOfSpeech() {}
                        override fun onRmsChanged(rmsdB: Float) {}
                        override fun onBufferReceived(buffer: ByteArray?) {}

                        override fun onEndOfSpeech() {
                            isListeningVoice = false
                            webView?.evaluateJavascript("if (typeof updateVoiceUI === 'function') updateVoiceUI(false);", null)
                        }

                        override fun onError(error: Int) {
                            isListeningVoice = false
                            webView?.evaluateJavascript("if (typeof updateVoiceUI === 'function') updateVoiceUI(false);", null)
                            val msg = when (error) {
                                SpeechRecognizer.ERROR_NO_MATCH -> "কোনো কথা শনাক্ত করা যায়নি"
                                SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "ইন্টারনেট সংযোগ চেক করুন"
                                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "মাইক্রোফোন অনুমতি প্রয়োজন"
                                else -> "ভয়েস টাইপিং সমাপ্ত"
                            }
                            webView?.evaluateJavascript("if (typeof showToast === 'function') showToast('$msg');", null)
                        }

                        override fun onResults(results: Bundle?) {
                            isListeningVoice = false
                            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            if (!matches.isNullOrEmpty()) {
                                val text = matches[0]
                                currentInputConnection?.commitText("$text ", 1)
                                webView?.evaluateJavascript("if (typeof showToast === 'function') showToast('✓ $text');", null)
                            }
                            webView?.evaluateJavascript("if (typeof updateVoiceUI === 'function') updateVoiceUI(false);", null)
                        }

                        override fun onPartialResults(partialResults: Bundle?) {
                            val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            if (!matches.isNullOrEmpty()) {
                                val text = matches[0]
                                webView?.evaluateJavascript("if (typeof setVoiceStatus === 'function') setVoiceStatus('$text', true);", null)
                            }
                        }

                        override fun onEvent(eventType: Int, params: Bundle?) {}
                    })
                }

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, voiceLanguage)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                }
                speechRecognizer?.startListening(intent)
            } catch (e: Exception) {
                isListeningVoice = false
                webView?.evaluateJavascript("if (typeof updateVoiceUI === 'function') updateVoiceUI(false);", null)
            }
        }
    }

    fun stopVoiceTyping() {
        mainHandler.post {
            isListeningVoice = false
            try {
                speechRecognizer?.stopListening()
            } catch (_: Exception) {}
            webView?.evaluateJavascript("if (typeof updateVoiceUI === 'function') updateVoiceUI(false);", null)
        }
    }

    class AndroidKeyboardBridge(private val service: TechuKeyboardService) {

        @JavascriptInterface
        fun isIme(): Boolean = true

        @JavascriptInterface
        fun triggerHaptic() {
            service.triggerHapticClick("click")
        }

        @JavascriptInterface
        fun triggerHapticType(type: String) {
            service.triggerHapticClick(type)
        }

        @JavascriptInterface
        fun toggleVoice() {
            service.toggleVoiceTyping()
        }

        @JavascriptInterface
        fun stopVoice() {
            service.stopVoiceTyping()
        }

        @JavascriptInterface
        fun setVoiceLang(lang: String) {
            service.voiceLanguage = lang
        }

        @JavascriptInterface
        fun commitText(text: String) {
            service.mainHandler.post {
                service.currentInputConnection?.commitText(text, 1)
            }
        }

        @JavascriptInterface
        fun setComposingText(text: String) {
            service.mainHandler.post {
                service.currentInputConnection?.setComposingText(text, 1)
            }
        }

        @JavascriptInterface
        fun clearComposingText() {
            service.mainHandler.post {
                service.currentInputConnection?.finishComposingText()
            }
        }

        @JavascriptInterface
        fun deleteSurroundingText(beforeLength: Int, afterLength: Int) {
            service.mainHandler.post {
                service.currentInputConnection?.deleteSurroundingText(beforeLength, afterLength)
            }
        }

        @JavascriptInterface
        fun sendEnter() {
            service.mainHandler.post {
                val ic = service.currentInputConnection ?: return@post
                if (service.currentImeAction != EditorInfo.IME_ACTION_NONE &&
                    service.currentImeAction != EditorInfo.IME_ACTION_UNSPECIFIED
                ) {
                    ic.performEditorAction(service.currentImeAction)
                } else {
                    ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
                    ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
                }
            }
        }

        @JavascriptInterface
        fun moveCursor(step: Int) {
            service.mainHandler.post {
                val code = if (step < 0) KeyEvent.KEYCODE_DPAD_LEFT else KeyEvent.KEYCODE_DPAD_RIGHT
                val ic = service.currentInputConnection ?: return@post
                ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
                ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
            }
        }

        @JavascriptInterface
        fun moveCursorLine(dir: Int) {
            service.mainHandler.post {
                val code = if (dir < 0) KeyEvent.KEYCODE_DPAD_UP else KeyEvent.KEYCODE_DPAD_DOWN
                val ic = service.currentInputConnection ?: return@post
                ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
                ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
            }
        }

        @JavascriptInterface
        fun moveCursorWord(dir: Int) {
            service.mainHandler.post {
                val code = if (dir < 0) KeyEvent.KEYCODE_DPAD_LEFT else KeyEvent.KEYCODE_DPAD_RIGHT
                val ic = service.currentInputConnection ?: return@post
                ic.sendKeyEvent(KeyEvent(0, 0, KeyEvent.ACTION_DOWN, code, 0, KeyEvent.META_CTRL_ON))
                ic.sendKeyEvent(KeyEvent(0, 0, KeyEvent.ACTION_UP, code, 0, KeyEvent.META_CTRL_ON))
            }
        }

        @JavascriptInterface
        fun performUndo() {
            service.mainHandler.post {
                val ic = service.currentInputConnection ?: return@post
                ic.sendKeyEvent(KeyEvent(0, 0, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_Z, 0, KeyEvent.META_CTRL_ON))
                ic.sendKeyEvent(KeyEvent(0, 0, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_Z, 0, KeyEvent.META_CTRL_ON))
            }
        }

        @JavascriptInterface
        fun performRedo() {
            service.mainHandler.post {
                val ic = service.currentInputConnection ?: return@post
                ic.sendKeyEvent(KeyEvent(0, 0, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_Y, 0, KeyEvent.META_CTRL_ON))
                ic.sendKeyEvent(KeyEvent(0, 0, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_Y, 0, KeyEvent.META_CTRL_ON))
            }
        }

        @JavascriptInterface
        fun performCut() {
            service.mainHandler.post {
                service.currentInputConnection?.performContextMenuAction(android.R.id.cut)
            }
        }

        @JavascriptInterface
        fun performCopy() {
            service.mainHandler.post {
                service.currentInputConnection?.performContextMenuAction(android.R.id.copy)
            }
        }

        @JavascriptInterface
        fun performPaste() {
            service.mainHandler.post {
                service.currentInputConnection?.performContextMenuAction(android.R.id.paste)
            }
        }

        @JavascriptInterface
        fun performSelectAll() {
            service.mainHandler.post {
                service.currentInputConnection?.performContextMenuAction(android.R.id.selectAll)
            }
        }

        @JavascriptInterface
        fun getClipboard(): String {
            return try {
                val cm = service.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                cm?.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
            } catch (_: Exception) {
                ""
            }
        }

        @JavascriptInterface
        fun setAudioHapticsEnabled(sound: Boolean, haptic: Boolean) {
            service.soundEnabled = sound
            service.hapticEnabled = haptic
        }
    }
}
