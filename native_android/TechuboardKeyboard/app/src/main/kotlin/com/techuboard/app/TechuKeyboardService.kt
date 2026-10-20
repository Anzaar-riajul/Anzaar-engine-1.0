package com.techuboard.app

import android.annotation.SuppressLint
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.webkit.JavascriptInterface
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient

/**
 * Techuboard Android Soft Keyboard IME.
 * Renders the exact custom designed keyboard UI via hardware-accelerated WebView
 * and connects it directly to Android's InputConnection across all apps.
 */
class TechuKeyboardService : InputMethodService() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var vibrator: Vibrator? = null
    private var webView: WebView? = null

    override fun onCreate() {
        super.onCreate()
        vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
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
                setSupportZoom(false)
                useWideViewPort = true
                loadWithOverviewMode = true
                cacheMode = WebSettings.LOAD_DEFAULT
            }

            // IME window touch handling without stealing window focus from host app
            isFocusable = false
            isFocusableInTouchMode = false

            addJavascriptInterface(AndroidKeyboardBridge(this@TechuKeyboardService), "AndroidKeyboard")
            webViewClient = WebViewClient()
            loadUrl("file:///android_asset/keyboard_ime.html")
        }

        webView = wv
        return wv
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

    class AndroidKeyboardBridge(private val service: TechuKeyboardService) {

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
