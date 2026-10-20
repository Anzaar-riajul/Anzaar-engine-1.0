package com.techuboard.app

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val scroll = ScrollView(this).apply {
            setBackgroundColor(Color.parseColor("#0d1117"))
            isFillViewport = true
        }

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(48, 80, 48, 80)
        }

        val title = TextView(this).apply {
            text = "Techuboard"
            textSize = 32f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }

        val subtitle = TextView(this).apply {
            text = "বাংলা ও ইংরেজি ফোনেটিক কীবোর্ড"
            textSize = 16f
            setTextColor(Color.parseColor("#8b949e"))
            gravity = Gravity.CENTER
            setPadding(0, 16, 0, 60)
        }

        val btnEnable = createStyledButton("১. কীবোর্ড সক্রিয় করুন (Enable in Settings)") {
            startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
        }

        val btnSelect = createStyledButton("২. Techuboard নির্বাচন করুন (Select Input Method)") {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showInputMethodPicker()
        }

        val testLabel = TextView(this).apply {
            text = "৩. এখানে টাইপ করে টেস্ট করুন:"
            textSize = 14f
            setTextColor(Color.parseColor("#8b949e"))
            setPadding(0, 60, 0, 16)
        }

        val testInput = EditText(this).apply {
            hint = "এখানে লিখুন (যেমন: ami banglay gan gai)..."
            setHintTextColor(Color.parseColor("#484f58"))
            setTextColor(Color.WHITE)
            textSize = 16f
            setPadding(32, 32, 32, 32)
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#161b22"))
                cornerRadius = 20f
                setStroke(2, Color.parseColor("#30363d"))
            }
        }

        layout.addView(title)
        layout.addView(subtitle)
        layout.addView(btnEnable)
        layout.addView(createSpacer(24))
        layout.addView(btnSelect)
        layout.addView(testLabel)
        layout.addView(testInput)

        scroll.addView(layout)
        setContentView(scroll)
    }

    private fun createStyledButton(label: String, onClick: () -> Unit): Button {
        return Button(this).apply {
            text = label
            setTextColor(Color.WHITE)
            textSize = 15f
            isAllCaps = false
            setPadding(32, 32, 32, 32)
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#238636"))
                cornerRadius = 24f
            }
            setOnClickListener { onClick() }
        }
    }

    private fun createSpacer(heightDp: Int): LinearLayout {
        return LinearLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                (heightDp * resources.displayMetrics.density).toInt()
            )
        }
    }
}
