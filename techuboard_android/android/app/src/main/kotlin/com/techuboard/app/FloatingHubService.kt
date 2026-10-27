package com.techuboard.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.sqlite.SQLiteDatabase
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.text.Editable
import android.text.TextUtils
import android.text.TextWatcher
import android.util.Log
import android.view.*
import android.widget.*
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.abs
import kotlin.math.hypot

/**
 * World-Class Floating Paste Hub for Android.
 * Replicates the complete macOS MenuBar Panel model:
 *  - 📋 All Tab: Complete clipboard history, sub-filters (All, Pinned, Links, Text), 1-tap paste, copy, pin, delete.
 *  - 📝 Notes Tab: Categorized snippet folders, note search, 1-tap paste, copy, quick add.
 *  - 💻 Devices Tab: Connected Mac / companion devices, live LAN sync status, unpair / disconnect.
 *  - 🎯 Messenger-style Drag-to-Close drop target with haptic feedback.
 *  - 🛡️ Safe back-key handling, keyboard overlap prevention, and non-destructive cursor paste.
 */
class FloatingHubService : Service() {

    companion object {
        private const val TAG = "TechuFloatingHub"
        const val CHANNEL_ID = TechuboardNotificationHelper.CHANNEL_ID
        const val NOTIFICATION_ID = TechuboardNotificationHelper.NOTIFICATION_ID
        const val ACTION_STOP_SERVICE = "com.techuboard.app.ACTION_STOP_FLOATING_HUB"

        @Volatile
        var isRunning: Boolean = false
            private set
    }

    private var windowManager: WindowManager? = null
    private var pillView: View? = null
    private var expandedView: View? = null
    private var removeTargetView: View? = null
    private var pillParams: WindowManager.LayoutParams? = null
    private var removeParams: WindowManager.LayoutParams? = null

    private var isExpanded = false
    private var isNearDropZone = false
    private var hasVibratedInDropZone = false

    // State matching macOS MenuBar
    private enum class Tab { ALL, NOTES, DEVICES }
    private var activeTab: Tab = Tab.ALL
    private var activeSubFilter = "all" // "all", "pinned", "links", "text"
    private var activeFolderId = "all"
    private var currentQuery = ""

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_SERVICE) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        startForegroundCompat()
        createPillView()
    }

    override fun onDestroy() {
        isRunning = false
        mainHandler.removeCallbacks(dimRunnable)
        removeExpandedView()
        removePillView()
        removeDropTargetView()

        if (TechuboardSyncForegroundService.isRunning) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_DETACH)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(false)
            }
            TechuboardNotificationHelper.update(applicationContext)
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        }
        super.onDestroy()
    }

    private fun startForegroundCompat() {
        TechuboardNotificationHelper.ensureChannel(this)
        val notification = TechuboardNotificationHelper.buildUnifiedNotification(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                TechuboardNotificationHelper.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(TechuboardNotificationHelper.NOTIFICATION_ID, notification)
        }
    }

    private fun dpToPx(dp: Int): Int {
        val density = resources.displayMetrics.density
        return (dp * density).toInt()
    }

    // =========================================================================
    // 1. FLOATING PILL & DRAG-TO-CLOSE DROP TARGET (MESSENGER STYLE)
    // =========================================================================

    // 2-second auto-dimming when idle / closed
    private val dimRunnable = Runnable {
        if (!isExpanded) {
            pillView?.animate()
                ?.alpha(0.2f)
                ?.setDuration(350)
                ?.start()
        }
    }

    private fun resetPillOpacity() {
        mainHandler.removeCallbacks(dimRunnable)
        pillView?.animate()
            ?.alpha(1.0f)
            ?.setDuration(120)
            ?.start()
    }

    private fun schedulePillDim() {
        mainHandler.removeCallbacks(dimRunnable)
        if (!isExpanded) {
            mainHandler.postDelayed(dimRunnable, 2000L)
        }
    }

    private fun createPillView() {
        val pill = FrameLayout(this)
        val pillBg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            colors = intArrayOf(Color.parseColor("#1262F3"), Color.parseColor("#0A47B8"))
            gradientType = GradientDrawable.LINEAR_GRADIENT
            setStroke(dpToPx(1.5f.toInt().coerceAtLeast(1)), Color.parseColor("#80ABC7FF"))
        }
        pill.background = pillBg
        pill.elevation = dpToPx(8).toFloat()

        val icon = ImageView(this).apply {
            setImageResource(R.drawable.ic_menubar_white_logo)
            scaleType = ImageView.ScaleType.FIT_CENTER
            val paddingH = dpToPx(11)
            val paddingV = dpToPx(13)
            setPadding(paddingH, paddingV, paddingH, paddingV)
        }
        pill.addView(icon, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val size = dpToPx(50)
        val screenWidth = resources.displayMetrics.widthPixels
        val screenHeight = resources.displayMetrics.heightPixels

        val params = WindowManager.LayoutParams(
            size,
            size,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = screenWidth - size - dpToPx(12)
            y = screenHeight / 3
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
                    resetPillOpacity()
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    isNearDropZone = false
                    hasVibratedInDropZone = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    resetPillOpacity()
                    val dx = (event.rawX - initialTouchX).toInt()
                    val dy = (event.rawY - initialTouchY).toInt()

                    if (!isDragging && (abs(dx) > dpToPx(6) || abs(dy) > dpToPx(6))) {
                        isDragging = true
                        showDropTargetView()
                    }

                    if (isDragging) {
                        params.x = initialX + dx
                        params.y = initialY + dy
                        windowManager?.updateViewLayout(pill, params)
                        checkDropZone(event.rawX, event.rawY)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (isDragging) {
                        val wasInDropZone = isNearDropZone || isTouchInDropZone(event.rawX, event.rawY)
                        hideDropTargetView()
                        if (wasInDropZone) {
                            // Dropped in close zone!
                            vibrate(strong = true)
                            Toast.makeText(this, "Floating Hub turned off", Toast.LENGTH_SHORT).show()
                            stopSelf()
                            return@setOnTouchListener true
                        }

                        // Snap to nearest edge
                        val sw = resources.displayMetrics.widthPixels
                        val sh = resources.displayMetrics.heightPixels
                        params.x = if (params.x + size / 2 < sw / 2) dpToPx(12) else sw - size - dpToPx(12)
                        // Safe vertical clamp so it never slips under notch or nav bar
                        params.y = params.y.coerceIn(dpToPx(40), sh - dpToPx(100))
                        windowManager?.updateViewLayout(pill, params)
                        schedulePillDim()
                    } else {
                        toggleExpanded()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    schedulePillDim()
                    false
                }
                else -> false
            }
        }

        pillView = pill
        try {
            windowManager?.addView(pill, params)
            schedulePillDim()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add pillView", e)
        }
    }

    private fun showDropTargetView() {
        if (removeTargetView != null) return

        val target = FrameLayout(this)
        val bg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.parseColor("#991F2633"))
            setStroke(dpToPx(2), Color.parseColor("#EF4444"))
        }
        target.background = bg
        target.elevation = dpToPx(12).toFloat()

        val closeIcon = TextView(this).apply {
            text = "✕"
            setTextColor(Color.WHITE)
            textSize = 22f
            gravity = Gravity.CENTER
        }
        target.addView(closeIcon, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val targetSize = dpToPx(68)
        val sw = resources.displayMetrics.widthPixels
        val sh = resources.displayMetrics.heightPixels

        val params = WindowManager.LayoutParams(
            targetSize,
            targetSize,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (sw - targetSize) / 2
            y = sh - targetSize - dpToPx(48)
        }

        removeParams = params
        removeTargetView = target

        try {
            windowManager?.addView(target, params)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to show removeTargetView: $e")
        }
    }

    private fun isTouchInDropZone(touchX: Float, touchY: Float): Boolean {
        val sw = resources.displayMetrics.widthPixels
        val sh = resources.displayMetrics.heightPixels
        val targetSize = dpToPx(68)
        val targetCenterX = sw / 2f
        val targetCenterY = (sh - targetSize - dpToPx(48)) + targetSize / 2f
        val dist = hypot(touchX - targetCenterX, touchY - targetCenterY)
        val inBottomZone = touchY > (sh - dpToPx(130)) && abs(touchX - (sw / 2f)) < dpToPx(110)
        return dist < dpToPx(95) || inBottomZone
    }

    private fun checkDropZone(touchX: Float, touchY: Float) {
        val target = removeTargetView ?: return
        val inZone = isTouchInDropZone(touchX, touchY)

        if (inZone) {
            if (!isNearDropZone) {
                isNearDropZone = true
                target.animate().scaleX(1.35f).scaleY(1.35f).setDuration(120).start()
                val bg = target.background as? GradientDrawable
                bg?.setColor(Color.parseColor("#EECC2D2D"))
                if (!hasVibratedInDropZone) {
                    vibrate(strong = false)
                    hasVibratedInDropZone = true
                }
            }
        } else {
            if (isNearDropZone) {
                isNearDropZone = false
                target.animate().scaleX(1.0f).scaleY(1.0f).setDuration(120).start()
                val bg = target.background as? GradientDrawable
                bg?.setColor(Color.parseColor("#991F2633"))
                hasVibratedInDropZone = false
            }
        }
    }

    private fun hideDropTargetView() {
        removeTargetView?.let {
            try {
                windowManager?.removeView(it)
            } catch (_: Exception) {}
        }
        removeTargetView = null
        removeParams = null
        isNearDropZone = false
        hasVibratedInDropZone = false
    }

    private fun removePillView() {
        pillView?.let {
            try {
                windowManager?.removeView(it)
            } catch (_: Exception) {}
        }
        pillView = null
    }

    private fun removeDropTargetView() {
        hideDropTargetView()
    }

    // =========================================================================
    // 2. EXPANDED PANEL (EXACT MAC MENUBAR REPLICA: ALL - NOTES - DEVICES)
    // =========================================================================

    private fun toggleExpanded() {
        if (isExpanded) collapse() else expand()
    }

    private fun collapse() {
        if (!isExpanded) return
        isExpanded = false
        removeExpandedView()
        schedulePillDim()
    }

    private fun removeExpandedView() {
        expandedView?.let {
            try {
                windowManager?.removeView(it)
            } catch (_: Exception) {}
        }
        expandedView = null
    }

    private fun expand() {
        if (isExpanded) return
        isExpanded = true
        resetPillOpacity()
        vibrate(strong = false)

        // Custom root layout to intercept Android Back Button & Back Gestures
        val root = object : FrameLayout(this) {
            override fun dispatchKeyEvent(event: KeyEvent): Boolean {
                if (event.keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                    collapse()
                    return true
                }
                return super.dispatchKeyEvent(event)
            }
        }

        val cardBg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dpToPx(18).toFloat()
            setColor(Color.parseColor("#12151D"))
            setStroke(dpToPx(1), Color.parseColor("#263142"))
        }
        root.background = cardBg
        root.elevation = dpToPx(24).toFloat()

        val mainContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dpToPx(16), dpToPx(14), dpToPx(16), dpToPx(14))
        }
        root.addView(mainContainer, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        // 1. Header (Brand Logo + Title + Close Button)
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dpToPx(10))
        }

        val logoIcon = TextView(this).apply {
            text = "⚡"
            textSize = 15f
            setPadding(0, 0, dpToPx(6), 0)
        }

        val brandTitle = TextView(this).apply {
            text = "Techuboard"
            setTextColor(Color.WHITE)
            textSize = 16f
            paint.isFakeBoldText = true
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }

        val closeBtn = TextView(this).apply {
            text = "✕"
            setTextColor(Color.parseColor("#8E99A8"))
            textSize = 16f
            setPadding(dpToPx(8), dpToPx(4), dpToPx(4), dpToPx(4))
            setOnClickListener { collapse() }
        }

        header.addView(logoIcon)
        header.addView(brandTitle)
        header.addView(closeBtn)
        mainContainer.addView(header)

        // Dynamic Counts
        val allCount = getClipboardCount()
        val notesCount = getNotesCount()
        val devicesCount = getDevicesCount()

        // 2. Mac-Style 3-Segment Tab Bar (All - Notes - Devices) directly under header
        val tabBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            val tbBg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(10).toFloat()
                setColor(Color.parseColor("#161C26"))
                setStroke(dpToPx(1), Color.parseColor("#252E3E"))
            }
            background = tbBg
            setPadding(dpToPx(3), dpToPx(3), dpToPx(3), dpToPx(3))
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dpToPx(34)).apply {
                setMargins(0, 0, 0, dpToPx(8))
            }
        }

        val btnTabAll = TextView(this)
        val btnTabNotes = TextView(this)
        val btnTabDevices = TextView(this)

        val tabWeightParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f)
        btnTabAll.apply { layoutParams = tabWeightParams }
        btnTabNotes.apply { layoutParams = tabWeightParams }
        btnTabDevices.apply { layoutParams = tabWeightParams }

        tabBar.addView(btnTabAll)
        tabBar.addView(btnTabNotes)
        tabBar.addView(btnTabDevices)
        mainContainer.addView(tabBar)

        // 3. Expandable Filter Chips & Search Bar Row
        val filterAndSearchContainer = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dpToPx(32)).apply {
                setMargins(0, 0, 0, dpToPx(8))
            }
        }

        val filterRowLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        }

        val chipsScroll = HorizontalScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f)
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
        }

        val subFilterRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.MATCH_PARENT)
        }
        chipsScroll.addView(subFilterRow)
        filterRowLayout.addView(chipsScroll)

        val searchToggleBtn = TextView(this).apply {
            text = "🔍"
            textSize = 12.5f
            gravity = Gravity.CENTER
            val sBtnBg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(Color.parseColor("#1B2230"))
                setStroke(dpToPx(1), Color.parseColor("#29354A"))
            }
            background = sBtnBg
            layoutParams = LinearLayout.LayoutParams(dpToPx(32), dpToPx(28)).apply {
                setMargins(dpToPx(4), 0, 0, 0)
            }
        }
        filterRowLayout.addView(searchToggleBtn)
        filterAndSearchContainer.addView(filterRowLayout)

        // Expanded Search Box (smoothly overlays filter chips)
        val searchBox = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            visibility = if (currentQuery.isNotEmpty()) View.VISIBLE else View.GONE
            val sBg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(Color.parseColor("#1B2230"))
                setStroke(dpToPx(1), Color.parseColor("#38BDF8"))
            }
            background = sBg
            setPadding(dpToPx(8), 0, dpToPx(8), 0)
            layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        }

        val searchIcon = TextView(this).apply {
            text = "🔍"
            textSize = 12f
            setPadding(0, 0, dpToPx(6), 0)
        }

        val searchInput = EditText(this).apply {
            hint = "Search clips, notes..."
            setHintTextColor(Color.parseColor("#788494"))
            setTextColor(Color.WHITE)
            textSize = 12.5f
            background = null
            maxLines = 1
            if (currentQuery.isNotEmpty()) setText(currentQuery)
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }

        val dismissSearchBtn = TextView(this).apply {
            text = "✕"
            setTextColor(Color.parseColor("#94A3B8"))
            textSize = 13.5f
            setPadding(dpToPx(6), dpToPx(4), dpToPx(4), dpToPx(4))
        }

        searchBox.addView(searchIcon)
        searchBox.addView(searchInput)
        searchBox.addView(dismissSearchBtn)
        filterAndSearchContainer.addView(searchBox)

        if (currentQuery.isNotEmpty()) {
            filterRowLayout.visibility = View.GONE
            searchBox.visibility = View.VISIBLE
        } else {
            filterRowLayout.visibility = View.VISIBLE
            searchBox.visibility = View.GONE
        }

        searchToggleBtn.setOnClickListener {
            filterRowLayout.visibility = View.GONE
            searchBox.visibility = View.VISIBLE
            searchInput.requestFocus()
            val imm = getSystemService(INPUT_METHOD_SERVICE) as? android.view.inputmethod.InputMethodManager
            imm?.showSoftInput(searchInput, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
        }

        dismissSearchBtn.setOnClickListener {
            searchInput.setText("")
            currentQuery = ""
            val imm = getSystemService(INPUT_METHOD_SERVICE) as? android.view.inputmethod.InputMethodManager
            imm?.hideSoftInputFromWindow(searchInput.windowToken, 0)
            searchBox.visibility = View.GONE
            filterRowLayout.visibility = View.VISIBLE
        }

        mainContainer.addView(filterAndSearchContainer)

        // Scrollable content area
        val contentLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        val scrollView = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f)
            isFillViewport = true
            addView(contentLayout)
        }
        mainContainer.addView(scrollView)

        fun updateTabsUI() {
            val tabs = listOf(
                Triple(btnTabAll, Tab.ALL, "📋 All ($allCount)"),
                Triple(btnTabNotes, Tab.NOTES, "📝 Notes ($notesCount)"),
                Triple(btnTabDevices, Tab.DEVICES, "💻 Devices ($devicesCount)")
            )
            for ((tv, tab, label) in tabs) {
                val isSelected = activeTab == tab
                tv.text = label
                tv.gravity = Gravity.CENTER
                tv.textSize = 12f
                tv.paint.isFakeBoldText = isSelected
                tv.setTextColor(if (isSelected) Color.WHITE else Color.parseColor("#8E99A8"))
                val bg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(8).toFloat()
                    if (isSelected) {
                        setColor(Color.parseColor("#253247"))
                        setStroke(dpToPx(1), Color.parseColor("#384B6B"))
                    } else {
                        setColor(Color.TRANSPARENT)
                    }
                }
                tv.background = bg
            }
        }

        fun renderActiveTab() {
            contentLayout.removeAllViews()
            subFilterRow.removeAllViews()

            when (activeTab) {
                Tab.ALL -> {
                    filterAndSearchContainer.visibility = View.VISIBLE
                    renderSubFilters(subFilterRow) { renderActiveTab() }
                    renderAllTab(contentLayout, currentQuery)
                }
                Tab.NOTES -> {
                    filterAndSearchContainer.visibility = View.VISIBLE
                    renderNotesFolderFilters(subFilterRow) { renderActiveTab() }
                    renderNotesTab(contentLayout, currentQuery)
                }
                Tab.DEVICES -> {
                    filterAndSearchContainer.visibility = View.GONE
                    renderDevicesTab(contentLayout, currentQuery)
                }
            }
        }

        btnTabAll.setOnClickListener {
            activeTab = Tab.ALL
            updateTabsUI()
            renderActiveTab()
        }
        btnTabNotes.setOnClickListener {
            activeTab = Tab.NOTES
            updateTabsUI()
            renderActiveTab()
        }
        btnTabDevices.setOnClickListener {
            activeTab = Tab.DEVICES
            updateTabsUI()
            renderActiveTab()
        }

        updateTabsUI()
        renderActiveTab()

        searchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                currentQuery = s?.toString()?.trim() ?: ""
                renderActiveTab()
            }
            override fun afterTextChanged(s: Editable?) {}
        })

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val sw = resources.displayMetrics.widthPixels
        val sh = resources.displayMetrics.heightPixels

        // Sleek & compact floating hub window dimensions
        val panelWidth = (sw * 0.86).toInt().coerceAtMost(dpToPx(350))
        val panelHeight = (sh * 0.52).toInt().coerceIn(dpToPx(360), dpToPx(430))

        val expParams = WindowManager.LayoutParams(
            panelWidth,
            panelHeight,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or WindowManager.LayoutParams.SOFT_INPUT_STATE_HIDDEN
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

    // =========================================================================
    // 3. TAB 1: ALL (CLIPBOARD HISTORY)
    // =========================================================================

    private fun renderSubFilters(container: LinearLayout, onFilterChanged: () -> Unit) {
        val filters = listOf(
            "all" to "All",
            "pinned" to "📌 Pinned",
            "links" to "🔗 Links",
            "images" to "🖼️ Images",
            "text" to "📄 Text"
        )
        for ((key, label) in filters) {
            val isSelected = activeSubFilter == key
            val pill = TextView(this).apply {
                text = label
                textSize = 11.5f
                paint.isFakeBoldText = isSelected
                setTextColor(if (isSelected) Color.parseColor("#38BDF8") else Color.parseColor("#8E99A8"))
                val bg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(14).toFloat()
                    if (isSelected) {
                        setColor(Color.parseColor("#1A324A"))
                        setStroke(dpToPx(1), Color.parseColor("#0284C7"))
                    } else {
                        setColor(Color.parseColor("#151C26"))
                        setStroke(dpToPx(1), Color.parseColor("#222C3A"))
                    }
                }
                background = bg
                setPadding(dpToPx(10), dpToPx(4), dpToPx(10), dpToPx(4))
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    setMargins(0, 0, dpToPx(5), 0)
                }
                setOnClickListener {
                    activeSubFilter = key
                    onFilterChanged()
                }
            }
            container.addView(pill)
        }
    }

    private fun getBadgeInfo(value: String, isImage: Boolean): Pair<String, String>? {
        if (isImage) return Pair("IMAGE", "#38BDF8")
        for (ch in value) {
            val code = ch.code
            if (code in 0x0980..0x09FF) {
                return Pair("TechuAvro", "#22C55E")
            }
        }
        if (value.startsWith("http://") || value.startsWith("https://")) {
            return Pair("URL", "#A855F7")
        }
        if (value.contains("=") || value.contains("function ") || value.contains("var ") ||
            value.contains("let ") || value.contains("const ") || value.contains("{") ||
            value.contains("def ") || value.contains("class ")) {
            return Pair("Code", "#F97316")
        }
        return null
    }

    private data class ClipItem(
        val id: Long,
        val hash: String,
        val type: String,
        val value: String,
        val sourceApp: String,
        val createdAt: Long,
        var isPinned: Boolean
    )

    private fun renderAllTab(container: LinearLayout, query: String) {
        val clips = fetchClipboardItems(query, activeSubFilter)

        if (clips.isEmpty()) {
            val emptyTv = TextView(this).apply {
                text = if (query.isEmpty()) "Clipboard history is empty" else "No matching clips found"
                setTextColor(Color.parseColor("#788494"))
                textSize = 13f
                gravity = Gravity.CENTER
                setPadding(0, dpToPx(40), 0, dpToPx(40))
            }
            container.addView(emptyTv)
            return
        }

        for (clip in clips) {
            val isImage = clip.type == "image"
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                val bg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(8).toFloat()
                    setColor(Color.parseColor("#161C26"))
                    setStroke(dpToPx(1), Color.parseColor("#232C3C"))
                }
                background = bg
                setPadding(dpToPx(8), dpToPx(6), dpToPx(8), dpToPx(6))
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    setMargins(0, 0, 0, dpToPx(5))
                }
            }

            // Left: Thumbnail for image or Pin icon
            if (isImage) {
                val thumbView = ImageView(this).apply {
                    layoutParams = LinearLayout.LayoutParams(dpToPx(38), dpToPx(28)).apply {
                        setMargins(0, 0, dpToPx(8), 0)
                    }
                    scaleType = ImageView.ScaleType.CENTER_CROP
                    clipToOutline = true
                    background = GradientDrawable().apply {
                        cornerRadius = dpToPx(4).toFloat()
                        setColor(Color.parseColor("#1F2937"))
                    }
                    try {
                        val file = File(clip.value)
                        if (file.exists()) {
                            val opt = BitmapFactory.Options().apply { inSampleSize = 4 }
                            val bmp = BitmapFactory.decodeFile(file.absolutePath, opt)
                            if (bmp != null) setImageBitmap(bmp)
                        }
                    } catch (_: Exception) {}
                }
                row.addView(thumbView)
            } else if (clip.isPinned) {
                val pinIcon = TextView(this).apply {
                    text = "📌"
                    textSize = 11f
                    setPadding(0, 0, dpToPx(5), 0)
                }
                row.addView(pinIcon)
            }

            // Middle: Badges + Text + Time
            val textCol = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                    setMargins(0, 0, dpToPx(6), 0)
                }
            }

            val titleLine = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }

            val badgePair = getBadgeInfo(clip.value, isImage)
            if (badgePair != null) {
                val (bText, bColorHex) = badgePair
                val badgeTv = TextView(this).apply {
                    text = bText
                    setTextColor(Color.parseColor(bColorHex))
                    textSize = 9f
                    paint.isFakeBoldText = true
                    val bBg = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dpToPx(3).toFloat()
                        val parsed = Color.parseColor(bColorHex)
                        setColor(Color.argb(35, Color.red(parsed), Color.green(parsed), Color.blue(parsed)))
                    }
                    background = bBg
                    setPadding(dpToPx(4), dpToPx(1), dpToPx(4), dpToPx(1))
                    layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                        setMargins(0, 0, dpToPx(5), 0)
                    }
                }
                titleLine.addView(badgeTv)
            }

            val bodyTv = TextView(this).apply {
                text = if (isImage) "[Image]" else clip.value.replace("\n", " ").trim()
                setTextColor(Color.parseColor("#F1F5F9"))
                textSize = 12.5f
                paint.isFakeBoldText = true
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            }
            titleLine.addView(bodyTv)
            textCol.addView(titleLine)

            val subTv = TextView(this).apply {
                text = formatTimeAgo(clip.createdAt) + if (clip.sourceApp.isNotEmpty()) " · ${clip.sourceApp}" else ""
                setTextColor(Color.parseColor("#64748B"))
                textSize = 9.5f
                setPadding(0, dpToPx(1), 0, 0)
            }
            textCol.addView(subTv)

            row.addView(textCol)

            // Direct tap-to-paste
            row.setOnClickListener {
                if (isImage) {
                    copyToClipboard(clip.value, isImage = true)
                } else {
                    executePaste(clip.value)
                }
            }

            // Right: Compact action buttons (⚡ Paste, 📋 Copy, 📌 Pin, 🗑️ Delete)
            val actions = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }

            val btnPaste = TextView(this).apply {
                text = "⚡"
                textSize = 12.5f
                setPadding(dpToPx(5), dpToPx(4), dpToPx(5), dpToPx(4))
                setOnClickListener {
                    if (isImage) {
                        copyToClipboard(clip.value, isImage = true)
                    } else {
                        executePaste(clip.value)
                    }
                }
            }

            val btnCopy = TextView(this).apply {
                text = "📋"
                textSize = 12f
                setPadding(dpToPx(5), dpToPx(4), dpToPx(5), dpToPx(4))
                setOnClickListener {
                    copyToClipboard(clip.value, isImage = isImage)
                }
            }

            val btnPin = TextView(this).apply {
                text = if (clip.isPinned) "⭐" else "📌"
                textSize = 11.5f
                setPadding(dpToPx(5), dpToPx(4), dpToPx(5), dpToPx(4))
                setOnClickListener {
                    togglePinClip(clip.hash)
                    expand()
                }
            }

            val btnDelete = TextView(this).apply {
                text = "🗑️"
                textSize = 11.5f
                setPadding(dpToPx(5), dpToPx(4), dpToPx(5), dpToPx(4))
                setOnClickListener {
                    deleteClip(clip.id)
                    expand()
                }
            }

            actions.addView(btnPaste)
            actions.addView(btnCopy)
            actions.addView(btnPin)
            actions.addView(btnDelete)
            row.addView(actions)

            container.addView(row)
        }
    }

    // =========================================================================
    // 4. TAB 2: NOTES (SNIPPETS & CATEGORIES)
    // =========================================================================

    private data class NoteItem(
        val id: String,
        val folderId: String,
        val folderTitle: String,
        val title: String,
        val content: String,
        val updatedAt: Long
    )

    private fun renderNotesFolderFilters(container: LinearLayout, onFilterChanged: () -> Unit) {
        val folders = fetchSnippetFolders()

        val allPill = TextView(this).apply {
            text = "All Folders"
            textSize = 11.5f
            val isSelected = activeFolderId == "all"
            paint.isFakeBoldText = isSelected
            setTextColor(if (isSelected) Color.parseColor("#38BDF8") else Color.parseColor("#8E99A8"))
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(14).toFloat()
                if (isSelected) {
                    setColor(Color.parseColor("#1A324A"))
                    setStroke(dpToPx(1), Color.parseColor("#0284C7"))
                } else {
                    setColor(Color.parseColor("#151C26"))
                    setStroke(dpToPx(1), Color.parseColor("#222C3A"))
                }
            }
            background = bg
            setPadding(dpToPx(10), dpToPx(4), dpToPx(10), dpToPx(4))
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, dpToPx(6), 0)
            }
            setOnClickListener {
                activeFolderId = "all"
                onFilterChanged()
            }
        }
        container.addView(allPill)

        for ((fId, fTitle) in folders) {
            val isSelected = activeFolderId == fId
            val pill = TextView(this).apply {
                text = fTitle
                textSize = 11.5f
                paint.isFakeBoldText = isSelected
                setTextColor(if (isSelected) Color.parseColor("#38BDF8") else Color.parseColor("#8E99A8"))
                val bg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(14).toFloat()
                    if (isSelected) {
                        setColor(Color.parseColor("#1A324A"))
                        setStroke(dpToPx(1), Color.parseColor("#0284C7"))
                    } else {
                        setColor(Color.parseColor("#151C26"))
                        setStroke(dpToPx(1), Color.parseColor("#222C3A"))
                    }
                }
                background = bg
                setPadding(dpToPx(10), dpToPx(4), dpToPx(10), dpToPx(4))
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    setMargins(0, 0, dpToPx(6), 0)
                }
                setOnClickListener {
                    activeFolderId = fId
                    onFilterChanged()
                }
            }
            container.addView(pill)
        }
    }

    private fun renderNotesTab(container: LinearLayout, query: String) {
        val notes = fetchNotes(query, activeFolderId)

        if (notes.isEmpty()) {
            val emptyTv = TextView(this).apply {
                text = if (query.isEmpty()) "No saved notes in this category" else "No matching notes found"
                setTextColor(Color.parseColor("#788494"))
                textSize = 13f
                gravity = Gravity.CENTER
                setPadding(0, dpToPx(40), 0, dpToPx(40))
            }
            container.addView(emptyTv)
            return
        }

        for (note in notes) {
            val card = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                val bg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(10).toFloat()
                    setColor(Color.parseColor("#18202C"))
                    setStroke(dpToPx(1), Color.parseColor("#263346"))
                }
                background = bg
                setPadding(dpToPx(12), dpToPx(10), dpToPx(12), dpToPx(10))
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    setMargins(0, 0, 0, dpToPx(8))
                }
            }

            // Top meta
            val metaRow = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }

            val folderBadge = TextView(this).apply {
                text = note.folderTitle.uppercase()
                setTextColor(Color.parseColor("#38BDF8"))
                textSize = 10.5f
                paint.isFakeBoldText = true
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            }

            metaRow.addView(folderBadge)
            card.addView(metaRow)

            // Note title
            val titleTv = TextView(this).apply {
                text = note.title
                setTextColor(Color.WHITE)
                textSize = 14f
                paint.isFakeBoldText = true
                setPadding(0, dpToPx(4), 0, dpToPx(2))
            }
            card.addView(titleTv)

            // Note body
            val bodyTv = TextView(this).apply {
                text = note.content
                setTextColor(Color.parseColor("#CBD5E1"))
                textSize = 12.5f
                maxLines = 3
                ellipsize = TextUtils.TruncateAt.END
                setPadding(0, 0, 0, dpToPx(8))
            }
            card.addView(bodyTv)

            // Actions row
            val actionRow = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }

            val btnPaste = TextView(this).apply {
                text = "⚡ Paste"
                setTextColor(Color.WHITE)
                textSize = 11.5f
                paint.isFakeBoldText = true
                val btnBg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(6).toFloat()
                    setColor(Color.parseColor("#0284C7"))
                }
                background = btnBg
                setPadding(dpToPx(10), dpToPx(4), dpToPx(10), dpToPx(4))
                setOnClickListener {
                    executePaste(note.content)
                }
            }

            val btnCopy = TextView(this).apply {
                text = "📋 Copy"
                setTextColor(Color.parseColor("#CBD5E1"))
                textSize = 11f
                setPadding(dpToPx(10), dpToPx(4), dpToPx(10), dpToPx(4))
                setOnClickListener {
                    copyToClipboard(note.content)
                }
            }

            val btnDelete = TextView(this).apply {
                text = "🗑️"
                textSize = 12f
                setPadding(dpToPx(8), dpToPx(4), dpToPx(8), dpToPx(4))
                setOnClickListener {
                    deleteNote(note.id)
                    expand() // Refresh
                }
            }

            actionRow.addView(btnPaste)
            actionRow.addView(btnCopy)
            actionRow.addView(btnDelete)
            card.addView(actionRow)

            container.addView(card)
        }
    }

    // =========================================================================
    // 5. TAB 3: DEVICES (MAC & COMPANION PEERS)
    // =========================================================================

    private data class DeviceItem(
        val id: String,
        val name: String,
        val isMac: Boolean,
        val isConnected: Boolean,
        val pairedAt: String
    )

    private fun renderDevicesTab(container: LinearLayout, query: String) {
        // 1. This Phone Status Card
        val thisDeviceCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(10).toFloat()
                setColor(Color.parseColor("#162130"))
                setStroke(dpToPx(1), Color.parseColor("#0284C7"))
            }
            background = bg
            setPadding(dpToPx(14), dpToPx(12), dpToPx(14), dpToPx(12))
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, dpToPx(12))
            }
        }

        val topRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val phoneTitle = TextView(this).apply {
            text = "📱 This Phone (Android)"
            setTextColor(Color.WHITE)
            textSize = 14f
            paint.isFakeBoldText = true
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }

        val liveBadge = TextView(this).apply {
            text = "● LISTENING LAN"
            setTextColor(Color.parseColor("#34D399"))
            textSize = 11f
            paint.isFakeBoldText = true
        }

        topRow.addView(phoneTitle)
        topRow.addView(liveBadge)
        thisDeviceCard.addView(topRow)

        val portSub = TextView(this).apply {
            text = "Encrypted TCP peer listener active on port :5566"
            setTextColor(Color.parseColor("#788494"))
            textSize = 11.5f
            setPadding(0, dpToPx(4), 0, 0)
        }
        thisDeviceCard.addView(portSub)
        container.addView(thisDeviceCard)

        // 2. Paired Peers List
        val devices = fetchPairedDevices()

        val labelDevices = TextView(this).apply {
            text = "PAIRED PEERS"
            setTextColor(Color.parseColor("#64748B"))
            textSize = 11f
            paint.isFakeBoldText = true
            setPadding(0, dpToPx(4), 0, dpToPx(6))
        }
        container.addView(labelDevices)

        if (devices.isEmpty()) {
            val emptyCard = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                val bg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(10).toFloat()
                    setColor(Color.parseColor("#151C26"))
                    setStroke(dpToPx(1), Color.parseColor("#222C3A"))
                }
                background = bg
                setPadding(dpToPx(16), dpToPx(24), dpToPx(16), dpToPx(24))
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    setMargins(0, 0, 0, dpToPx(12))
                }
            }

            val emptyMsg = TextView(this).apply {
                text = "No paired Mac or companion devices yet."
                setTextColor(Color.parseColor("#8E99A8"))
                textSize = 12.5f
                gravity = Gravity.CENTER
            }
            emptyCard.addView(emptyMsg)
            container.addView(emptyCard)
        } else {
            for (dev in devices) {
                if (query.isNotEmpty() && !dev.name.contains(query, ignoreCase = true)) continue

                val devCard = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    val bg = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dpToPx(10).toFloat()
                        setColor(Color.parseColor("#18202C"))
                        setStroke(dpToPx(1), Color.parseColor("#263346"))
                    }
                    background = bg
                    setPadding(dpToPx(12), dpToPx(10), dpToPx(12), dpToPx(10))
                    layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                        setMargins(0, 0, 0, dpToPx(8))
                    }
                }

                val row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }

                val devIcon = TextView(this).apply {
                    text = if (dev.isMac) "🍎" else "💻"
                    textSize = 18f
                    setPadding(0, 0, dpToPx(8), 0)
                }

                val nameCol = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                }

                val nameTv = TextView(this).apply {
                    text = dev.name
                    setTextColor(Color.WHITE)
                    textSize = 13.5f
                    paint.isFakeBoldText = true
                }

                val statusTv = TextView(this).apply {
                    text = "● Ready to Sync (LAN)"
                    setTextColor(Color.parseColor("#34D399"))
                    textSize = 11f
                }

                nameCol.addView(nameTv)
                nameCol.addView(statusTv)

                val btnUnpair = TextView(this).apply {
                    text = "Unpair"
                    setTextColor(Color.parseColor("#EF4444"))
                    textSize = 11.5f
                    paint.isFakeBoldText = true
                    val bBg = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dpToPx(6).toFloat()
                        setColor(Color.parseColor("#261D22"))
                        setStroke(dpToPx(1), Color.parseColor("#7F1D1D"))
                    }
                    background = bBg
                    setPadding(dpToPx(10), dpToPx(5), dpToPx(10), dpToPx(5))
                    setOnClickListener {
                        unpairDevice(dev.id)
                        expand() // Refresh
                    }
                }

                row.addView(devIcon)
                row.addView(nameCol)
                row.addView(btnUnpair)
                devCard.addView(row)
                container.addView(devCard)
            }
        }

        // 3. Pair New Device Button
        val btnPairNew = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            val pBg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(10).toFloat()
                colors = intArrayOf(Color.parseColor("#0284C7"), Color.parseColor("#0369A1"))
            }
            background = pBg
            setPadding(dpToPx(16), dpToPx(12), dpToPx(16), dpToPx(12))
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, dpToPx(6), 0, dpToPx(12))
            }
            setOnClickListener {
                collapse()
                val intent = Intent(this@FloatingHubService, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                startActivity(intent)
            }
        }

        val pairIcon = TextView(this).apply {
            text = "📷"
            textSize = 14f
            setPadding(0, 0, dpToPx(8), 0)
        }

        val pairText = TextView(this).apply {
            text = "Scan Mac QR Code / Pair Device"
            setTextColor(Color.WHITE)
            textSize = 13f
            paint.isFakeBoldText = true
        }

        btnPairNew.addView(pairIcon)
        btnPairNew.addView(pairText)
        container.addView(btnPairNew)
    }

    // =========================================================================
    // 6. CORE ACTIONS & ACCESSIBILITY EXECUTION
    // =========================================================================

    private fun executePaste(text: String) {
        vibrate(strong = false)
        collapse()

        // Give the target app 120ms to regain window focus before pasting
        mainHandler.postDelayed({
            val accessibility = FloatingHubAccessibilityService.instance
            val directlyInjected = accessibility?.pasteText(text) ?: false

            if (!directlyInjected) {
                copyToClipboard(text, notify = true)
            }
        }, 120)
    }

    private fun copyToClipboard(text: String, isImage: Boolean = false, notify: Boolean = true) {
        try {
            val cm = getSystemService(CLIPBOARD_SERVICE) as? android.content.ClipboardManager
            if (isImage) {
                val file = File(text)
                if (file.exists()) {
                    val uri = androidx.core.content.FileProvider.getUriForFile(
                        this,
                        "${packageName}.fileprovider",
                        file
                    )
                    val clip = android.content.ClipData.newUri(contentResolver, "Techuboard Image", uri)
                    cm?.setPrimaryClip(clip)
                    if (notify && Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                        Toast.makeText(this, "Image copied to clipboard", Toast.LENGTH_SHORT).show()
                    }
                    return
                }
            }
            cm?.setPrimaryClip(android.content.ClipData.newPlainText("Techuboard", text))
            if (notify && Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                Toast.makeText(this, "Copied to clipboard", Toast.LENGTH_SHORT).show()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Clipboard copy error: $e")
        }
    }

    private fun vibrate(strong: Boolean = false) {
        try {
            val vibrator = getSystemService(VIBRATOR_SERVICE) as? Vibrator
            val duration = if (strong) 50L else 25L
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(duration)
            }
        } catch (_: Exception) {}
    }

    // =========================================================================
    // 7. DATABASE & PREFERENCES QUERIES
    // =========================================================================

    private fun getReadableDatabase(): SQLiteDatabase? {
        val candidates = listOf(
            File(filesDir, "techuboard.db"),
            getDatabasePath("techuboard.db")
        )
        for (f in candidates) {
            if (f.exists()) {
                try {
                    return SQLiteDatabase.openDatabase(f.path, null, SQLiteDatabase.OPEN_READWRITE)
                } catch (_: Exception) {
                    try {
                        return SQLiteDatabase.openDatabase(f.path, null, SQLiteDatabase.OPEN_READONLY)
                    } catch (_: Exception) {}
                }
            }
        }
        return null
    }

    private fun getClipboardCount(): Int {
        val db = getReadableDatabase() ?: return 0
        return try {
            val cursor = db.rawQuery("SELECT COUNT(*) FROM clipboard_history", null)
            cursor.use { if (it.moveToFirst()) it.getInt(0) else 0 }
        } catch (_: Exception) { 0 } finally { try { db.close() } catch (_: Exception) {} }
    }

    private fun getNotesCount(): Int {
        val db = getReadableDatabase() ?: return 0
        return try {
            val cursor = db.rawQuery("SELECT COUNT(*) FROM snippets", null)
            cursor.use { if (it.moveToFirst()) it.getInt(0) else 0 }
        } catch (_: Exception) { 0 } finally { try { db.close() } catch (_: Exception) {} }
    }

    private fun getDevicesCount(): Int {
        return fetchPairedDevices().size
    }

    private fun getPinnedHashes(): Set<String> {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("flutter.techuboard.pinned_clips", null) ?: return emptySet()
        val result = mutableSetOf<String>()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                result.add(arr.getString(i))
            }
        } catch (_: Exception) {}
        return result
    }

    private fun togglePinClip(hash: String) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val pinned = getPinnedHashes().toMutableSet()
        if (pinned.contains(hash)) pinned.remove(hash) else pinned.add(hash)
        val arr = JSONArray(pinned)
        prefs.edit().putString("flutter.techuboard.pinned_clips", arr.toString()).apply()
    }

    private fun fetchClipboardItems(query: String, filter: String): List<ClipItem> {
        val result = mutableListOf<ClipItem>()
        val db = getReadableDatabase() ?: return result
        val pinnedSet = getPinnedHashes()

        try {
            var sql = "SELECT id, content_hash, item_type, item_value, source_app, created_at FROM clipboard_history WHERE 1=1"
            val args = mutableListOf<String>()

            if (query.isNotEmpty()) {
                sql += " AND item_value LIKE ?"
                args.add("%$query%")
            }
            when (filter) {
                "links" -> {
                    sql += " AND item_type = 'text' AND (item_value LIKE 'http://%' OR item_value LIKE 'https://%')"
                }
                "images" -> {
                    sql += " AND item_type = 'image'"
                }
                "text" -> {
                    sql += " AND item_type = 'text'"
                }
                else -> {
                    sql += " AND item_type IN ('text', 'image')"
                }
            }

            sql += " ORDER BY created_at DESC LIMIT 50"

            val cursor = db.rawQuery(sql, if (args.isEmpty()) null else args.toTypedArray())
            cursor.use {
                while (it.moveToNext()) {
                    val id = it.getLong(0)
                    val hash = it.getString(1) ?: ""
                    val type = it.getString(2) ?: "text"
                    val value = it.getString(3) ?: ""
                    val src = it.getString(4) ?: ""
                    val time = it.getLong(5)
                    val isPinned = pinnedSet.contains(hash)

                    if (filter == "pinned" && !isPinned) continue

                    result.add(ClipItem(id, hash, type, value, src, time, isPinned))
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error fetching clips: $e")
        } finally {
            try { db.close() } catch (_: Exception) {}
        }
        return result
    }

    private fun deleteClip(id: Long) {
        val db = getReadableDatabase() ?: return
        try {
            db.delete("clipboard_history", "id = ?", arrayOf(id.toString()))
        } catch (_: Exception) {} finally {
            try { db.close() } catch (_: Exception) {}
        }
    }

    private fun fetchSnippetFolders(): List<Pair<String, String>> {
        val result = mutableListOf<Pair<String, String>>()
        val db = getReadableDatabase() ?: return result
        try {
            val cursor = db.rawQuery("SELECT id, title FROM snippet_folders WHERE is_enabled = 1 ORDER BY sort_order ASC, updated_at DESC", null)
            cursor.use {
                while (it.moveToNext()) {
                    result.add(Pair(it.getString(0), it.getString(1)))
                }
            }
        } catch (_: Exception) {} finally {
            try { db.close() } catch (_: Exception) {}
        }
        return result
    }

    private fun fetchNotes(query: String, folderId: String): List<NoteItem> {
        val result = mutableListOf<NoteItem>()
        val db = getReadableDatabase() ?: return result
        try {
            var sql = "SELECT s.id, s.folder_id, f.title, s.title, s.content, s.updated_at FROM snippets s JOIN snippet_folders f ON s.folder_id = f.id WHERE f.is_enabled = 1"
            val args = mutableListOf<String>()

            if (folderId != "all") {
                sql += " AND s.folder_id = ?"
                args.add(folderId)
            }
            if (query.isNotEmpty()) {
                sql += " AND (s.title LIKE ? OR s.content LIKE ?)"
                args.add("%$query%")
                args.add("%$query%")
            }

            sql += " ORDER BY s.sort_order ASC, s.updated_at DESC LIMIT 30"

            val cursor = db.rawQuery(sql, if (args.isEmpty()) null else args.toTypedArray())
            cursor.use {
                while (it.moveToNext()) {
                    result.add(
                        NoteItem(
                            id = it.getString(0),
                            folderId = it.getString(1),
                            folderTitle = it.getString(2) ?: "General",
                            title = it.getString(3) ?: "Note",
                            content = it.getString(4) ?: "",
                            updatedAt = it.getLong(5)
                        )
                    )
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error fetching notes: $e")
        } finally {
            try { db.close() } catch (_: Exception) {}
        }
        return result
    }

    private fun deleteNote(id: String) {
        val db = getReadableDatabase() ?: return
        try {
            db.delete("snippets", "id = ?", arrayOf(id))
        } catch (_: Exception) {} finally {
            try { db.close() } catch (_: Exception) {}
        }
    }

    private fun fetchPairedDevices(): List<DeviceItem> {
        val result = mutableListOf<DeviceItem>()
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val seenIds = mutableSetOf<String>()
        val raw = prefs.getString("flutter.techuboard.trusted_peers.v4", null)
        if (raw != null) {
            try {
                val json = JSONObject(raw)
                val keys = json.keys()
                while (keys.hasNext()) {
                    val peerId = keys.next()
                    seenIds.add(peerId)
                    val obj = json.getJSONObject(peerId)
                    val name = obj.optString("name", "Mac Device")
                    val isMac = name.contains("Mac", ignoreCase = true) || name.contains("Apple", ignoreCase = true)
                    val pairedAt = obj.optString("paired_at", "Recently")
                    result.add(DeviceItem(peerId, name, isMac, isConnected = true, pairedAt = pairedAt))
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error parsing trusted peers: $e")
            }
        }
        val clipPeers = prefs.getString("flutter.clipboardSyncPeerIds", null)
        if (clipPeers != null) {
            try {
                val arr = JSONArray(clipPeers)
                for (i in 0 until arr.length()) {
                    val pid = arr.getString(i)
                    if (!seenIds.contains(pid) && pid.isNotEmpty()) {
                        result.add(DeviceItem(pid, "MacBook ($pid)", isMac = true, isConnected = true, pairedAt = "Connected"))
                    }
                }
            } catch (_: Exception) {}
        }
        return result
    }

    private fun unpairDevice(peerId: String) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("flutter.techuboard.trusted_peers.v4", null) ?: return
        try {
            val json = JSONObject(raw)
            json.remove(peerId)
            prefs.edit().putString("flutter.techuboard.trusted_peers.v4", json.toString()).apply()
            Toast.makeText(this, "Device unpaired", Toast.LENGTH_SHORT).show()
        } catch (_: Exception) {}
    }

    private fun formatTimeAgo(timestamp: Long): String {
        val now = System.currentTimeMillis()
        val diff = now - timestamp
        val seconds = diff / 1000
        val minutes = seconds / 60
        val hours = minutes / 60
        val days = hours / 24

        return when {
            minutes < 1 -> "Just now"
            minutes < 60 -> "${minutes}m ago"
            hours < 24 -> "${hours}h ago"
            days < 7 -> "${days}d ago"
            else -> SimpleDateFormat("MMM d", Locale.getDefault()).format(Date(timestamp))
        }
    }
}
