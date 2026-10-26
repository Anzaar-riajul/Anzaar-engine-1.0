package com.techuboard.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import android.view.*
import android.widget.*
import androidx.core.app.NotificationCompat
import java.io.File
import kotlin.math.abs

class FloatingHubService : Service() {

    companion object {
        private const val TAG = "TechuFloatingHub"
        private const val CHANNEL_ID = "techu_floating_hub"
        private const val NOTIFICATION_ID = 5567
        @Volatile
        var isRunning: Boolean = false
            private set
    }

    private var windowManager: WindowManager? = null
    private var pillView: View? = null
    private var expandedView: View? = null
    private var pillParams: WindowManager.LayoutParams? = null
    private var isExpanded = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildForegroundNotification())
        createPillView()
    }

    override fun onDestroy() {
        isRunning = false
        removePillView()
        removeExpandedView()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Techuboard Floating Hub",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Quick clipboard & snippet paste overlay"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Techuboard Floating Paste Hub")
            .setContentText("Tap floating pill to paste clips anywhere")
            .setSmallIcon(android.R.drawable.ic_menu_edit)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun dpToPx(dp: Int): Int {
        val density = resources.displayMetrics.density
        return (dp * density).toInt()
    }

    private fun createPillView() {
        val pill = FrameLayout(this)
        val pillBg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.parseColor("#1262F3"))
            setStroke(dpToPx(2), Color.parseColor("#ABC7FF"))
        }
        pill.background = pillBg
        pill.elevation = dpToPx(8).toFloat()

        val icon = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_edit)
            setColorFilter(Color.WHITE)
            val padding = dpToPx(12)
            setPadding(padding, padding, padding, padding)
        }
        val iconParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        pill.addView(icon, iconParams)

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val size = dpToPx(48)
        val params = WindowManager.LayoutParams(
            size,
            size,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = resources.displayMetrics.widthPixels - size - dpToPx(12)
            y = resources.displayMetrics.heightPixels / 3
        }

        pillParams = params

        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isDragging = false

        pill.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - initialTouchX).toInt()
                    val dy = (event.rawY - initialTouchY).toInt()
                    if (abs(dx) > dpToPx(6) || abs(dy) > dpToPx(6)) {
                        isDragging = true
                    }
                    if (isDragging) {
                        params.x = initialX + dx
                        params.y = initialY + dy
                        windowManager?.updateViewLayout(pill, params)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!isDragging) {
                        toggleExpanded()
                    } else {
                        // Snap to closest edge
                        val screenWidth = resources.displayMetrics.widthPixels
                        params.x = if (params.x + size / 2 < screenWidth / 2) {
                            dpToPx(12)
                        } else {
                            screenWidth - size - dpToPx(12)
                        }
                        windowManager?.updateViewLayout(pill, params)
                    }
                    true
                }
                else -> false
            }
        }

        pillView = pill
        try {
            windowManager?.addView(pill, params)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add pillView", e)
        }
    }

    private fun removePillView() {
        pillView?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                Log.w(TAG, "Error removing pill view: $e")
            }
        }
        pillView = null
    }

    private fun toggleExpanded() {
        if (isExpanded) {
            collapse()
        } else {
            expand()
        }
    }

    private fun expand() {
        if (isExpanded) return
        isExpanded = true
        vibrate()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(20).toFloat()
                setColor(Color.parseColor("#171C26"))
                setStroke(dpToPx(1), Color.parseColor("#293345"))
            }
            background = bg
            elevation = dpToPx(16).toFloat()
            setPadding(dpToPx(16), dpToPx(16), dpToPx(16), dpToPx(16))
        }

        // Top bar
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val title = TextView(this).apply {
            text = "Techuboard Quick Paste"
            setTextColor(Color.WHITE)
            textSize = 16f
            paint.isFakeBoldText = true
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }

        val closeBtn = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            setColorFilter(Color.parseColor("#ABC7FF"))
            setPadding(dpToPx(4), dpToPx(4), dpToPx(4), dpToPx(4))
            setOnClickListener { collapse() }
        }

        header.addView(title)
        header.addView(closeBtn)
        root.addView(header)

        // Search Bar
        val searchInput = EditText(this).apply {
            hint = "Search clipboard & notes..."
            setHintTextColor(Color.parseColor("#8E99A8"))
            setTextColor(Color.WHITE)
            textSize = 14f
            val searchBg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(12).toFloat()
                setColor(Color.parseColor("#1D2533"))
            }
            background = searchBg
            setPadding(dpToPx(12), dpToPx(8), dpToPx(12), dpToPx(8))
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, dpToPx(12), 0, dpToPx(10))
            }
            layoutParams = lp
        }
        root.addView(searchInput)

        // List container
        val listLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        val scrollView = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dpToPx(320)
            )
            addView(listLayout)
        }
        root.addView(scrollView)

        fun populateList(query: String = "") {
            listLayout.removeAllViews()
            val items = fetchItems(query)

            if (items.isEmpty()) {
                val emptyTv = TextView(this).apply {
                    text = if (query.isEmpty()) "Clipboard history is empty" else "No matching items"
                    setTextColor(Color.parseColor("#8E99A8"))
                    textSize = 13f
                    gravity = Gravity.CENTER
                    setPadding(0, dpToPx(32), 0, dpToPx(32))
                }
                listLayout.addView(emptyTv)
                return
            }

            for (item in items) {
                val itemCard = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    val cardBg = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dpToPx(10).toFloat()
                        setColor(Color.parseColor("#243145"))
                    }
                    background = cardBg
                    setPadding(dpToPx(12), dpToPx(10), dpToPx(12), dpToPx(10))
                    val lp = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    ).apply {
                        setMargins(0, dpToPx(4), 0, dpToPx(4))
                    }
                    layoutParams = lp
                    isClickable = true
                    isFocusable = true
                }

                val rowHeader = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                }

                val tagTv = TextView(this).apply {
                    text = if (item.isSnippet) "NOTE: ${item.title}" else "CLIPBOARD"
                    setTextColor(Color.parseColor(if (item.isSnippet) "#ABC7FF" else "#8E99A8"))
                    textSize = 11f
                    paint.isFakeBoldText = true
                    layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                }

                val tapToPaste = TextView(this).apply {
                    text = "Tap to paste"
                    setTextColor(Color.parseColor("#1262F3"))
                    textSize = 11f
                }

                rowHeader.addView(tagTv)
                rowHeader.addView(tapToPaste)
                itemCard.addView(rowHeader)

                val bodyTv = TextView(this).apply {
                    text = item.content
                    setTextColor(Color.WHITE)
                    textSize = 13f
                    maxLines = 3
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    setPadding(0, dpToPx(4), 0, 0)
                }
                itemCard.addView(bodyTv)

                itemCard.setOnClickListener {
                    onItemSelected(item.content)
                }

                listLayout.addView(itemCard)
            }
        }

        searchInput.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                populateList(s?.toString() ?: "")
            }
            override fun afterTextChanged(s: android.text.Editable?) {}
        })

        populateList()

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val width = (resources.displayMetrics.widthPixels * 0.90).toInt()
        val expParams = WindowManager.LayoutParams(
            width,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        root.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_OUTSIDE) {
                collapse()
                true
            } else false
        }

        expandedView = root
        try {
            windowManager?.addView(root, expParams)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add expandedView", e)
        }
    }

    private fun collapse() {
        if (!isExpanded) return
        isExpanded = false
        removeExpandedView()
    }

    private fun removeExpandedView() {
        expandedView?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                Log.w(TAG, "Error removing expanded view: $e")
            }
        }
        expandedView = null
    }

    private fun onItemSelected(text: String) {
        vibrate()
        collapse()

        val accessibility = FloatingHubAccessibilityService.instance
        val directlyInjected = accessibility?.pasteText(text) ?: false

        if (!directlyInjected) {
            // Direct injection not possible (Accessibility not enabled or no focused editable view)
            try {
                val cm = getSystemService(CLIPBOARD_SERVICE) as? android.content.ClipboardManager
                cm?.setPrimaryClip(android.content.ClipData.newPlainText("Techuboard", text))
                Toast.makeText(this, "Copied to clipboard. Long-press to paste.", Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Log.w(TAG, "Clipboard copy error: $e")
            }
        }
    }

    private fun vibrate() {
        try {
            val vibrator = getSystemService(VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createOneShot(30, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(30)
            }
        } catch (_: Exception) {}
    }

    private data class HubItem(val title: String, val content: String, val isSnippet: Boolean)

    private fun fetchItems(query: String): List<HubItem> {
        val result = mutableListOf<HubItem>()
        val dbFile = File(filesDir, "techuboard.db")
        if (!dbFile.exists()) return result

        var db: SQLiteDatabase? = null
        try {
            db = SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READONLY)

            // 1. Fetch enabled snippets first
            val snipQuery = if (query.trim().isEmpty()) {
                """
                SELECT s.title, s.content 
                FROM snippets s 
                JOIN snippet_folders f ON s.folder_id = f.id 
                WHERE f.is_enabled = 1 
                ORDER BY s.sort_order ASC, s.updated_at DESC 
                LIMIT 15
                """.trimIndent()
            } else {
                """
                SELECT s.title, s.content 
                FROM snippets s 
                JOIN snippet_folders f ON s.folder_id = f.id 
                WHERE f.is_enabled = 1 AND (s.title LIKE ? OR s.content LIKE ?)
                ORDER BY s.sort_order ASC, s.updated_at DESC 
                LIMIT 15
                """.trimIndent()
            }

            val snipArgs = if (query.trim().isEmpty()) null else arrayOf("%$query%", "%$query%")
            val snipCursor = db.rawQuery(snipQuery, snipArgs)
            snipCursor.use {
                while (it.moveToNext()) {
                    val title = it.getString(0) ?: ""
                    val content = it.getString(1) ?: ""
                    result.add(HubItem(title, content, isSnippet = true))
                }
            }

            // 2. Fetch recent clipboard text items
            val clipQuery = if (query.trim().isEmpty()) {
                """
                SELECT item_value 
                FROM clipboard_history 
                WHERE item_type = 'text' 
                ORDER BY created_at DESC 
                LIMIT 25
                """.trimIndent()
            } else {
                """
                SELECT item_value 
                FROM clipboard_history 
                WHERE item_type = 'text' AND item_value LIKE ?
                ORDER BY created_at DESC 
                LIMIT 25
                """.trimIndent()
            }

            val clipArgs = if (query.trim().isEmpty()) null else arrayOf("%$query%")
            val clipCursor = db.rawQuery(clipQuery, clipArgs)
            clipCursor.use {
                while (it.moveToNext()) {
                    val content = it.getString(0) ?: ""
                    val title = if (content.length > 40) content.take(40) + "…" else content
                    result.add(HubItem(title, content, isSnippet = false))
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error querying techuboard.db: $e")
        } finally {
            try { db?.close() } catch (_: Exception) {}
        }

        return result
    }
}
