package com.techuboard.app

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.provider.Settings
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.webkit.JavascriptInterface
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity

/**
 * MainActivity: Techuboard Mobile Studio & Onboarding
 * 
 * Top bar provides 2 quick action buttons:
 * 1. কীবোর্ড সক্রিয় করুন (Enable in Settings)
 * 2. Techuboard নির্বাচন করুন (Select Input Method)
 * 
 * Below the buttons, directly loads the complete 10-hour designed Techuboard Studio (mobile.html)
 * allowing full access to the interactive editor, theme picker, learn guide, and typing preview!
 */
class MainActivity : AppCompatActivity() {

    private var webView: WebView? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#121417"))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        // Top Action Bar with 2 Buttons
        val topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(12), dp(8), dp(12), dp(8))
            setBackgroundColor(Color.parseColor("#161B22"))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        val btnEnable = createActionButton("১. কীবোর্ড সক্রিয় করুন", Color.parseColor("#238636")) {
            startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
        }

        val btnSelect = createActionButton("২. Techuboard নির্বাচন করুন", Color.parseColor("#1F6FEB")) {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showInputMethodPicker()
        }

        topBar.addView(btnEnable)
        topBar.addView(createSpacer(8))
        topBar.addView(btnSelect)
        root.addView(topBar)

        // Direct Full Studio WebView
        val wv = WebView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
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
            webViewClient = WebViewClient()
            loadUrl("file:///android_asset/mobile.html")
        }

        webView = wv
        root.addView(wv)

        setContentView(root)
    }

    override fun onBackPressed() {
        val wv = webView
        if (wv != null && wv.canGoBack()) {
            wv.goBack()
        } else {
            super.onBackPressed()
        }
    }

    private fun createActionButton(label: String, bgColor: Int, onClick: () -> Unit): Button {
        return Button(this).apply {
            text = label
            setTextColor(Color.WHITE)
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            isAllCaps = false
            setPadding(dp(8), dp(8), dp(8), dp(8))
            background = GradientDrawable().apply {
                setColor(bgColor)
                cornerRadius = dp(6).toFloat()
            }
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            setOnClickListener { onClick() }
        }
    }

    private fun createSpacer(dp: Int): LinearLayout {
        return LinearLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                dp(dp),
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    class MainBridge(private val activity: MainActivity) {

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
