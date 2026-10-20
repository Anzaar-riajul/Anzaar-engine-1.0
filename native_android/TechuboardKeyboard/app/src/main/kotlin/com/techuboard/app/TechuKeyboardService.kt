package com.techuboard.app

import android.annotation.SuppressLint
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.inputmethodservice.InputMethodService
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
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

/**
 * TechuKeyboardService
 * 
 * Directly hosts the exact 100% same-to-same Techuboard UI (keyboard_ime.html)
 * with all vector SVG tools, inner panels (Numpad, Emoji, Learn, Clipboard,
 * Themes, Cursor D-Pad, Settings), real-time Avro transliteration, and native
 * Android InputConnection integration.
 */
class TechuKeyboardService : InputMethodService() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var vibrator: Vibrator? = null
    private var audioManager: AudioManager? = null
    private var webView: WebView? = null
    private var rootContainer: FrameLayout? = null

    var soundEnabled: Boolean = true
    var hapticEnabled: Boolean = true
    var currentImeAction: Int = EditorInfo.IME_ACTION_NONE

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
            (275 * density).toInt()
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

            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                allowFileAccess = true
                setSupportZoom(false)
                useWideViewPort = false
                loadWithOverviewMode = false
                cacheMode = WebSettings.LOAD_DEFAULT
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
        webView?.destroy()
        webView = null
    }

    fun triggerHapticClick() {
        if (soundEnabled) {
            try {
                audioManager?.playSoundEffect(AudioManager.FX_KEY_CLICK, 0.4f)
            } catch (_: Exception) {}
        }
        if (hapticEnabled) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(VibrationEffect.createOneShot(14L, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(14L)
                }
            } catch (_: Exception) {}
        }
    }

    class AndroidKeyboardBridge(private val service: TechuKeyboardService) {

        @JavascriptInterface
        fun isIme(): Boolean = true

        @JavascriptInterface
        fun triggerHaptic() {
            service.triggerHapticClick()
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
