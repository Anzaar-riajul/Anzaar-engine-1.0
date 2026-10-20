package com.techuboard.app

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.provider.Settings
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.webkit.JavascriptInterface
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity

/**
 * MainActivity: Direct Full Techuboard Studio
 * 
 * Directly displays the 100% exact, untouched 10-hour designed Techuboard mobile studio (mobile.html)
 * with complete header, live text editor, word counter, status bar, and keyboard.
 * Tapping "Settings" or "Install App" triggers the Android Keyboard activation options!
 */
class MainActivity : AppCompatActivity() {

    private var webView: WebView? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val wv = WebView(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(Color.parseColor("#0d1117"))

            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                allowFileAccess = true
                setSupportZoom(false)
                useWideViewPort = false       // MUST BE FALSE: 1:1 real device width
                loadWithOverviewMode = false  // MUST BE FALSE: 1:1 mobile scaling
                cacheMode = WebSettings.LOAD_DEFAULT
            }

            addJavascriptInterface(MainBridge(this@MainActivity), "AndroidKeyboard")
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    updateSetupPill(view)
                }
            }
            loadUrl("file:///android_asset/mobile.html")
        }

        webView = wv
        setContentView(wv)
    }

    override fun onResume() {
        super.onResume()
        webView?.let { updateSetupPill(it) }
    }

    private fun updateSetupPill(view: WebView?) {
        val isEnabled = isKeyboardEnabled()
        val isSelected = isKeyboardSelected()

        val pillText: String
        val jsAction: String

        if (!isEnabled) {
            pillText = "⚙️ ১. কীবোর্ড সক্রিয় করুন"
            jsAction = "window.AndroidKeyboard.openInputMethodSettings();"
        } else if (!isSelected) {
            pillText = "👆 ২. Techuboard নির্বাচন করুন"
            jsAction = "window.AndroidKeyboard.showInputMethodPicker();"
        } else {
            pillText = "✅ Techuboard সক্রিয় আছে"
            jsAction = "window.AndroidKeyboard.showInputMethodPicker();"
        }

        view?.evaluateJavascript("""
            const pill = document.getElementById('pwaInstallPill');
            if (pill) {
                pill.style.display = 'inline-flex';
                pill.innerHTML = '$pillText';
                pill.onclick = function() { $jsAction };
            }
        """.trimIndent(), null)
    }

    private fun isKeyboardEnabled(): Boolean {
        return try {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager ?: return false
            val enabledMethods = imm.enabledInputMethodList
            enabledMethods.any { it.packageName == packageName }
        } catch (_: Exception) {
            false
        }
    }

    private fun isKeyboardSelected(): Boolean {
        return try {
            val currentIme = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
            currentIme?.contains(packageName) == true
        } catch (_: Exception) {
            false
        }
    }

    override fun onBackPressed() {
        val wv = webView
        if (wv != null && wv.canGoBack()) {
            wv.goBack()
        } else {
            super.onBackPressed()
        }
    }

    class MainBridge(private val activity: MainActivity) {

        @JavascriptInterface
        fun isIme(): Boolean = false

        @JavascriptInterface
        fun openInputMethodSettings() {
            activity.runOnUiThread {
                val intent = Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                activity.startActivity(intent)
            }
        }

        @JavascriptInterface
        fun showInputMethodPicker() {
            activity.runOnUiThread {
                val imm = activity.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                imm?.showInputMethodPicker()
            }
        }

        @JavascriptInterface
        fun triggerHaptic() {}
    }
}
