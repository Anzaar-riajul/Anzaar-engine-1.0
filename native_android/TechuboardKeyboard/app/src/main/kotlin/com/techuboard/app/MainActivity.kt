package com.techuboard.app

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/**
 * MainActivity: Techuboard Mobile Studio & Setup
 * 
 * Provides:
 * - 2-step setup: 1. Enable in Settings, 2. Select Techuboard
 * - Live Interactive Typing Test Box with real Android EditText
 * - Live Theme Picker (All 8 themes instantly selectable and saved)
 */
class MainActivity : AppCompatActivity() {

    private val allThemes = listOf(
        Pair("Dark Titanium", "#121417"),
        Pair("Pure AMOLED", "#000000"),
        Pair("Cyberpunk Cyan", "#041218"),
        Pair("Forest Emerald", "#09140E"),
        Pair("Sunset Rose", "#14090E"),
        Pair("Pacific Blue", "#08101A"),
        Pair("Solar Amber", "#141008"),
        Pair("Midnight Indigo", "#080913")
    )
    private val themeIds = listOf("dark", "amoled", "cyber", "emerald", "rose", "ocean", "solar", "midnight")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val scroll = ScrollView(this).apply {
            setBackgroundColor(Color.parseColor("#121417"))
            isFillViewport = true
        }

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(20), dp(36), dp(20), dp(36))
        }

        // Title Header
        val title = TextView(this).apply {
            text = "Techuboard"
            textSize = 28f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        val subtitle = TextView(this).apply {
            text = "বাংলা ও ইংরেজি ফোনেটিক কীবোর্ড স্টুডিও"
            textSize = 14f
            setTextColor(Color.parseColor("#00E5FF"))
            gravity = Gravity.CENTER
            setPadding(0, dp(4), 0, dp(24))
        }

        // Step 1: Enable
        val btnEnable = createActionButton("১. কীবোর্ড সক্রিয় করুন (Enable in Settings)", Color.parseColor("#238636")) {
            startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
        }

        // Step 2: Select
        val btnSelect = createActionButton("২. Techuboard নির্বাচন করুন (Select Input Method)", Color.parseColor("#1F6FEB")) {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showInputMethodPicker()
        }

        // Step 3: Live Test Box
        val testLabel = TextView(this).apply {
            text = "৩. লাইভ টাইপিং টেস্ট এরিয়া:"
            textSize = 14f
            setTextColor(Color.parseColor("#8B949E"))
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, dp(28), 0, dp(8))
        }

        val testInput = EditText(this).apply {
            hint = "এখানে লিখুন (যেমন: ami bangla bhalobashi)..."
            setHintTextColor(Color.parseColor("#57606A"))
            setTextColor(Color.WHITE)
            textSize = 16f
            setPadding(dp(16), dp(16), dp(16), dp(16))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#181D24"))
                cornerRadius = dp(10).toFloat()
                setStroke(1, Color.parseColor("#30363D"))
            }
        }

        // Step 4: Theme Picker Header
        val themeLabel = TextView(this).apply {
            text = "৪. পছন্দের থিম বেছে নিন (৮টি ইউনিক থিম):"
            textSize = 14f
            setTextColor(Color.parseColor("#8B949E"))
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, dp(24), 0, dp(10))
        }

        val themeScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
        }
        val themeLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
        }

        val prefs = getSharedPreferences("techuboard_prefs", Context.MODE_PRIVATE)
        val savedThemeId = prefs.getString("theme_id", "dark") ?: "dark"

        for (i in allThemes.indices) {
            val (name, bgHex) = allThemes[i]
            val id = themeIds[i]
            val isSelected = (id == savedThemeId)

            val themeCard = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(dp(14), dp(10), dp(14), dp(10))
                background = GradientDrawable().apply {
                    setColor(Color.parseColor(bgHex))
                    cornerRadius = dp(8).toFloat()
                    setStroke(if (isSelected) 2 else 1, if (isSelected) Color.parseColor("#00E5FF") else Color.parseColor("#30363D"))
                }
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { setMargins(0, 0, dp(8), 0) }
                setOnClickListener {
                    prefs.edit().putString("theme_id", id).apply()
                    android.widget.Toast.makeText(this@MainActivity, "$name থিম নির্বাচিত হয়েছে", android.widget.Toast.LENGTH_SHORT).show()
                    recreate()
                }
            }

            val cardTitle = TextView(this).apply {
                text = name
                textSize = 13f
                setTextColor(Color.WHITE)
                typeface = if (isSelected) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            }
            themeCard.addView(cardTitle)

            if (isSelected) {
                val checkTv = TextView(this).apply {
                    text = "✓ সক্রিয়"
                    textSize = 11f
                    setTextColor(Color.parseColor("#00E5FF"))
                }
                themeCard.addView(checkTv)
            }
            themeLayout.addView(themeCard)
        }
        themeScroll.addView(themeLayout)

        layout.addView(title)
        layout.addView(subtitle)
        layout.addView(btnEnable)
        layout.addView(createSpacer(12))
        layout.addView(btnSelect)
        layout.addView(testLabel)
        layout.addView(testInput)
        layout.addView(themeLabel)
        layout.addView(themeScroll)

        scroll.addView(layout)
        setContentView(scroll)
    }

    private fun createActionButton(label: String, bgColor: Int, onClick: () -> Unit): Button {
        return Button(this).apply {
            text = label
            setTextColor(Color.WHITE)
            textSize = 14.5f
            typeface = Typeface.DEFAULT_BOLD
            isAllCaps = false
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = GradientDrawable().apply {
                setColor(bgColor)
                cornerRadius = dp(10).toFloat()
            }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            setOnClickListener { onClick() }
        }
    }

    private fun createSpacer(dp: Int): LinearLayout {
        return LinearLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(dp)
            )
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }
}
