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
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/**
 * Techuboard Onboarding & Setup Activity.
 * Provides a clean 2-step setup to enable and select Techuboard,
 * followed by a live interactive test input field.
 */
class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val scroll = ScrollView(this).apply {
            setBackgroundColor(Color.parseColor("#121417"))
            isFillViewport = true
        }

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(20), dp(40), dp(20), dp(40))
        }

        val title = TextView(this).apply {
            text = "Techuboard"
            textSize = 30f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }

        val subtitle = TextView(this).apply {
            text = "বাংলা ও ইংরেজি ফোনেটিক কীবোর্ড"
            textSize = 15f
            setTextColor(Color.parseColor("#8B949E"))
            gravity = Gravity.CENTER
            setPadding(0, dp(6), 0, dp(32))
        }

        val btnEnable = createActionButton("১. কীবোর্ড সক্রিয় করুন (Enable in Settings)", Color.parseColor("#238636")) {
            startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
        }

        val btnSelect = createActionButton("২. Techuboard নির্বাচন করুন (Select Input Method)", Color.parseColor("#1F6FEB")) {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showInputMethodPicker()
        }

        val testLabel = TextView(this).apply {
            text = "৩. এখানে যেকোনো অ্যাপের মতো টাইপ টেস্ট করুন:"
            textSize = 14f
            setTextColor(Color.parseColor("#8B949E"))
            setPadding(0, dp(36), 0, dp(12))
        }

        val testInput = EditText(this).apply {
            hint = "এখানে লিখুন (যেমন: ami banglay gan gai)..."
            setHintTextColor(Color.parseColor("#484F58"))
            setTextColor(Color.WHITE)
            textSize = 16f
            setPadding(dp(16), dp(16), dp(16), dp(16))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#181D24"))
                cornerRadius = dp(12).toFloat()
                setStroke(1, Color.parseColor("#30363D"))
            }
        }

        layout.addView(title)
        layout.addView(subtitle)
        layout.addView(btnEnable)
        layout.addView(createSpacer(14))
        layout.addView(btnSelect)
        layout.addView(testLabel)
        layout.addView(testInput)

        scroll.addView(layout)
        setContentView(scroll)
    }

    private fun createActionButton(label: String, bgColor: Int, onClick: () -> Unit): Button {
        return Button(this).apply {
            text = label
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            isAllCaps = false
            setPadding(dp(16), dp(16), dp(16), dp(16))
            background = GradientDrawable().apply {
                setColor(bgColor)
                cornerRadius = dp(12).toFloat()
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
