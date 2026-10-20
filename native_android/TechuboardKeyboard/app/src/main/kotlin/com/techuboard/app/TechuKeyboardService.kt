package com.techuboard.app

import android.annotation.SuppressLint
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
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
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import android.webkit.JavascriptInterface
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient

/**
 * Custom WebView declaring InputType.TYPE_NULL so it remains fully focusable
 * and interactive for touch clicks without triggering Android soft-keyboard loops.
 */
class TechuKeyboardWebView(context: Context) : WebView(context) {
    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        outAttrs.inputType = InputType.TYPE_NULL
        return BaseInputConnection(this, false)
    }
}

/**
 * TechuKeyboardService: 100% Faithful System IME
 * Directly hosts the user's 10-hour designed Techuboard (keyboard_ime.html),
 * connecting every single key, theme, phonetic Avro transliteration, emoji,
 * gesture, and clipboard action directly to Android's InputConnection.
 */
class TechuKeyboardService : InputMethodService() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var vibrator: Vibrator? = null
    private var audioManager: AudioManager? = null
    private var webView: TechuKeyboardWebView? = null

    override fun onCreate() {
        super.onCreate()
        vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreateInputView(): View {
        val density = resources.displayMetrics.density
        // 275dp is standard ergonomic keyboard height across modern Android devices
        val kbdHeightPx = (275 * density).toInt()

        val wv = TechuKeyboardWebView(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                kbdHeightPx
            )
            setBackgroundColor(Color.parseColor("#121417"))

            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                allowFileAccess = true
                setSupportZoom(false)
                useWideViewPort = false       // MUST BE FALSE: 1:1 match with real device screen width
                loadWithOverviewMode = false  // MUST BE FALSE: Prevents desktop zooming/scaling
                cacheMode = WebSettings.LOAD_DEFAULT
            }

            // Must be focusable so Chromium processes touch down/up/move events!
            isFocusable = true
            isFocusableInTouchMode = true
            isVerticalScrollBarEnabled = false
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER

            addJavascriptInterface(AndroidKeyboardBridge(this@TechuKeyboardService), "AndroidKeyboard")
            webViewClient = WebViewClient()
            loadUrl("file:///android_asset/keyboard_ime.html")
        }

        webView = wv
        return wv
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        webView?.evaluateJavascript("if (typeof resetComposingState === 'function') resetComposingState();", null)
    }

    override fun onDestroy() {
        super.onDestroy()
        webView?.destroy()
        webView = null
    }

    fun triggerHapticClick() {
        try {
            audioManager?.playSoundEffect(AudioManager.FX_KEY_CLICK, 0.4f)
        } catch (_: Exception) {}

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createOneShot(14L, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(14L)
            }
        } catch (_: Exception) {}
    }

    class AndroidKeyboardBridge(private val service: TechuKeyboardService) {

        @JavascriptInterface
        fun isIme(): Boolean = true

        @JavascriptInterface
        fun commitText(text: String) {
            service.mainHandler.post {
                val ic = service.currentInputConnection ?: return@post
                ic.commitText(text, 1)
            }
        }

        @JavascriptInterface
        fun setComposingText(text: String) {
            service.mainHandler.post {
                val ic = service.currentInputConnection ?: return@post
                ic.setComposingText(text, 1)
            }
        }

        @JavascriptInterface
        fun finishComposingText() {
            service.mainHandler.post {
                val ic = service.currentInputConnection ?: return@post
                ic.finishComposingText()
            }
        }

        @JavascriptInterface
        fun deleteSurroundingText(before: Int, after: Int) {
            service.mainHandler.post {
                val ic = service.currentInputConnection ?: return@post
                if (before > 0 && after == 0) {
                    val ok = ic.deleteSurroundingText(before, after)
                    if (!ok) {
                        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
                        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL))
                    }
                } else {
                    ic.deleteSurroundingText(before, after)
                }
            }
        }

        @JavascriptInterface
        fun sendEnter() {
            service.mainHandler.post {
                val ic = service.currentInputConnection ?: return@post
                val action = service.currentInputEditorInfo?.imeOptions?.and(EditorInfo.IME_MASK_ACTION)
                if (action != null && action != EditorInfo.IME_ACTION_NONE && action != EditorInfo.IME_ACTION_UNSPECIFIED) {
                    ic.performEditorAction(action)
                } else {
                    ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
                    ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
                }
            }
        }

        @JavascriptInterface
        fun moveCursor(direction: Int) {
            service.mainHandler.post {
                val ic = service.currentInputConnection ?: return@post
                val keyCode = if (direction < 0) KeyEvent.KEYCODE_DPAD_LEFT else KeyEvent.KEYCODE_DPAD_RIGHT
                ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
                ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
            }
        }

        @JavascriptInterface
        fun sendKeyEvent(keyCode: Int) {
            service.mainHandler.post {
                val ic = service.currentInputConnection ?: return@post
                ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
                ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
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
        fun triggerHaptic() {
            service.triggerHapticClick()
        }

        @JavascriptInterface
        fun getClipboard(): String {
            val cm = service.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            return cm?.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
        }

        @JavascriptInterface
        fun openInputMethodSettings() {
            service.mainHandler.post {
                val intent = Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                service.startActivity(intent)
            }
        }

        @JavascriptInterface
        fun showInputMethodPicker() {
            service.mainHandler.post {
                val imm = service.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                imm?.showInputMethodPicker()
            }
        }
    }
}
