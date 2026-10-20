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
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.webkit.JavascriptInterface
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient

/**
 * TechuKeyboardService
 * 
 * 100% Exact Direct Implementation of the 10-Hour Designed Techuboard:
 * Directly hosts the custom HTML/CSS/JS keyboard in a hardware-accelerated WebView,
 * connecting every key, theme, emoji, learn guide, numpad, and gesture directly to Android's
 * InputConnection across all apps (WhatsApp, Facebook, Messenger, YouTube, etc.)
 */
class TechuKeyboardService : InputMethodService() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var vibrator: Vibrator? = null
    private var audioManager: AudioManager? = null
    private var webView: WebView? = null

    override fun onCreate() {
        super.onCreate()
        vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreateInputView(): View {
        val density = resources.displayMetrics.density
        val kbdHeightPx = (290 * density).toInt()

        val wv = WebView(this).apply {
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
                useWideViewPort = true
                loadWithOverviewMode = true
                cacheMode = WebSettings.LOAD_DEFAULT
            }

            // CRITICAL: Prevent WebView from stealing window focus from the target app!
            isFocusable = false
            isFocusableInTouchMode = false
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
        fun finishComposingText() {
            service.mainHandler.post {
                service.currentInputConnection?.finishComposingText()
            }
        }

        @JavascriptInterface
        fun deleteSurroundingText(before: Int, after: Int) {
            service.mainHandler.post {
                service.currentInputConnection?.deleteSurroundingText(before, after)
            }
        }

        @JavascriptInterface
        fun sendEnter() {
            service.mainHandler.post {
                val ic = service.currentInputConnection ?: return@post
                ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
                ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
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
