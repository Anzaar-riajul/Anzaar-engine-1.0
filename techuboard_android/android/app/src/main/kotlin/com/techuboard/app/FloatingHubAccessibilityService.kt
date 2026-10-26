package com.techuboard.app

import android.accessibilityservice.AccessibilityService
import android.content.ClipData
import android.content.ClipboardManager
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class FloatingHubAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "TechuAccessibility"
        @Volatile
        var instance: FloatingHubAccessibilityService? = null
            private set

        fun isRunning(): Boolean = instance != null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "FloatingHubAccessibilityService connected")
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
        Log.i(TAG, "FloatingHubAccessibilityService destroyed")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Passive listener
    }

    override fun onInterrupt() {
        Log.w(TAG, "FloatingHubAccessibilityService interrupted")
    }

    /**
     * Pastes [text] directly into the currently focused editable input field.
     * Returns true if directly injected, false if fallback to clipboard copy is needed.
     */
    fun pasteText(text: String): Boolean {
        // Always place into system clipboard as first step
        try {
            val cm = getSystemService(CLIPBOARD_SERVICE) as? ClipboardManager
            cm?.setPrimaryClip(ClipData.newPlainText("Techuboard", text))
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set clipboard data: ${e.message}")
        }

        val root = rootInActiveWindow ?: return false
        val focusedNode = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)

        if (focusedNode != null && focusedNode.isEditable) {
            // 1. Try ACTION_PASTE first so it pastes at current cursor position without wiping out existing text!
            if (focusedNode.performAction(AccessibilityNodeInfo.ACTION_PASTE)) {
                Log.d(TAG, "Successfully pasted via ACTION_PASTE")
                return true
            }

            // 2. Fallback: If ACTION_PASTE fails, preserve any existing text
            val currentText = focusedNode.text?.toString() ?: ""
            val newText = if (currentText.isEmpty()) text else "$currentText $text"
            val args = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, newText)
            }
            if (focusedNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) {
                Log.d(TAG, "Successfully pasted via ACTION_SET_TEXT (preserved existing text)")
                return true
            }
        }
        return false
    }
}
