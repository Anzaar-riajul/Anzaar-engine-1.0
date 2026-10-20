package com.techuboard.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/**
 * MainActivity: Modern Native Keyboard Setup & Settings App
 * 
 * Provides an interactive 3-step setup guide for the user:
 * 1. Enable Techuboard in Android System Settings
 * 2. Select Techuboard as default input method
 * 3. Interactive test typing area directly inside the app!
 */
class MainActivity : AppCompatActivity() {

    private lateinit var btnEnableKeyboard: Button
    private lateinit var txtStep1Status: TextView
    private lateinit var btnSelectKeyboard: Button
    private lateinit var txtStep2Status: TextView
    private lateinit var editTestTyping: EditText

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        btnEnableKeyboard = findViewById(R.id.btnEnableKeyboard)
        txtStep1Status = findViewById(R.id.txtStep1Status)
        btnSelectKeyboard = findViewById(R.id.btnSelectKeyboard)
        txtStep2Status = findViewById(R.id.txtStep2Status)
        editTestTyping = findViewById(R.id.editTestTyping)

        val openSettingsAction = View.OnClickListener {
            val intent = Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
        }

        val selectKeyboardAction = View.OnClickListener {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.showInputMethodPicker()
        }

        btnEnableKeyboard.setOnClickListener(openSettingsAction)
        findViewById<View>(R.id.cardStep1).setOnClickListener {
            if (!isKeyboardEnabled()) {
                openSettingsAction.onClick(it)
            }
        }

        btnSelectKeyboard.setOnClickListener(selectKeyboardAction)
        findViewById<View>(R.id.cardStep2).setOnClickListener {
            selectKeyboardAction.onClick(it)
        }
    }

    override fun onResume() {
        super.onResume()
        updateSetupStatus()
    }

    private fun updateSetupStatus() {
        val isEnabled = isKeyboardEnabled()
        val isSelected = isKeyboardSelected()

        if (isEnabled) {
            btnEnableKeyboard.visibility = View.GONE
            txtStep1Status.visibility = View.VISIBLE
        } else {
            btnEnableKeyboard.visibility = View.VISIBLE
            txtStep1Status.visibility = View.GONE
        }

        if (isSelected) {
            btnSelectKeyboard.visibility = View.GONE
            txtStep2Status.visibility = View.VISIBLE
        } else {
            btnSelectKeyboard.visibility = View.VISIBLE
            txtStep2Status.visibility = View.GONE
        }
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
}
