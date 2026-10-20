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
                useWideViewPort = true
                loadWithOverviewMode = true
                cacheMode = WebSettings.LOAD_DEFAULT
            }

            addJavascriptInterface(MainBridge(this@MainActivity), "AndroidKeyboard")
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    view?.evaluateJavascript("""
                        const pill = document.getElementById('pwaInstallPill');
                        if (pill) {
                            pill.style.display = 'inline-flex';
                            pill.innerHTML = '⚙️ কীবোর্ড অন করুন';
                            pill.onclick = function() { window.AndroidKeyboard.openInputMethodSettings(); };
                        }
                    """.trimIndent(), null)
                }
            }
            loadUrl("file:///android_asset/mobile.html")
        }

        webView = wv
        setContentView(wv)
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
                activity.startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
            }
        }

        @JavascriptInterface
        fun showInputMethodPicker() {
            activity.runOnUiThread {
                val imm = activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                imm.showInputMethodPicker()
            }
        }

        @JavascriptInterface
        fun triggerHaptic() {}
    }
}
