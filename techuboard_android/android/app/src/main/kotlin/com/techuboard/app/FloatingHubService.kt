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
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
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
            colors = intArrayOf(Color.parseColor("#475569"), Color.parseColor("#334155"))
            gradientType = GradientDrawable.LINEAR_GRADIENT
            setStroke(dpToPx(1.5f.toInt().coerceAtLeast(1)), Color.parseColor("#64748B"))
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

        val view = expandedView
        if (view != null) {
            view.animate()
                .scaleX(0.85f)
                .scaleY(0.85f)
                .alpha(0f)
                .translationY(dpToPx(-16).toFloat())
                .setDuration(180)
                .setInterpolator(AccelerateInterpolator())
                .withEndAction {
                    removeExpandedView()
                }
                .start()
        } else {
            removeExpandedView()
        }

        pillView?.let { pill ->
            pill.visibility = View.VISIBLE
            pill.scaleX = 0.75f
            pill.scaleY = 0.75f
            pill.alpha = 0f
            pill.animate()
                .scaleX(1.0f)
                .scaleY(1.0f)
                .alpha(1.0f)
                .setDuration(240)
                .setInterpolator(OvershootInterpolator(1.2f))
                .start()
        }
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
        captureActiveClipboardIfNew()

        pillView?.let { pill ->
            pill.animate()
                .scaleX(0.82f)
                .scaleY(0.82f)
                .alpha(0f)
                .setDuration(160)
                .setInterpolator(DecelerateInterpolator())
                .withEndAction {
                    pill.visibility = View.GONE
                }
                .start()
        }

        val theme = getHubTheme()

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
            setColor(theme.panelBg)
            setStroke(dpToPx(1), theme.panelBorder)
        }
        root.background = cardBg
        root.elevation = dpToPx(24).toFloat()

        val mainContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dpToPx(14), dpToPx(12), dpToPx(14), dpToPx(10))
        }
        root.addView(mainContainer, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        // Dynamic Counts
        val allCount = getClipboardCount()
        val notesCount = getNotesCount()
        val devicesCount = getDevicesCount()

        // 1. Top Bar: Tabs with narrow gap + compact close button
        val topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dpToPx(6))
        }

        val tabBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            val tbBg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(theme.tabBg)
                setStroke(dpToPx(1), theme.tabBorder)
            }
            background = tbBg
            setPadding(dpToPx(2), dpToPx(2), dpToPx(2), dpToPx(2))
            layoutParams = LinearLayout.LayoutParams(0, dpToPx(32), 1f)
        }

        val btnTabAll = TextView(this)
        val btnTabNotes = TextView(this)
        val btnTabDevices = TextView(this)

        val tabWeightParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply {
            setMargins(dpToPx(1), 0, dpToPx(1), 0)
        }
        btnTabAll.apply { layoutParams = tabWeightParams }
        btnTabNotes.apply { layoutParams = tabWeightParams }
        btnTabDevices.apply { layoutParams = tabWeightParams }

        tabBar.addView(btnTabAll)
        tabBar.addView(btnTabNotes)
        tabBar.addView(btnTabDevices)
        topBar.addView(tabBar)

        val closeBtn = TextView(this).apply {
            text = "✕"
            setTextColor(theme.textMuted)
            textSize = 13f
            gravity = Gravity.CENTER
            val cBg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(6).toFloat()
                setColor(theme.actionBtnBg)
            }
            background = cBg
            layoutParams = LinearLayout.LayoutParams(dpToPx(28), dpToPx(28)).apply {
                setMargins(dpToPx(6), 0, 0, 0)
            }
            setOnClickListener { collapse() }
        }
        topBar.addView(closeBtn)
        mainContainer.addView(topBar)

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
                setColor(theme.actionBtnBg)
                setStroke(dpToPx(1), theme.cardBorder)
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
                setColor(theme.inputBg)
                setStroke(dpToPx(1), theme.accentBlue)
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
            setHintTextColor(theme.textMuted)
            setTextColor(theme.textPrimary)
            textSize = 12.5f
            background = null
            maxLines = 1
            if (currentQuery.isNotEmpty()) setText(currentQuery)
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }

        val dismissSearchBtn = TextView(this).apply {
            text = "✕"
            setTextColor(theme.textMuted)
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

        // Bottom Footer: Techuboard branding (no emojis, minimal sleek styling)
        val footerLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, dpToPx(6), 0, dpToPx(2))
        }
        val footerLabel = TextView(this).apply {
            text = "Techuboard"
            setTextColor(theme.textMuted)
            textSize = 10.5f
            paint.isFakeBoldText = true
            letterSpacing = 0.08f
        }
        footerLayout.addView(footerLabel)
        mainContainer.addView(footerLayout)

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
                tv.setTextColor(if (isSelected) theme.tabActiveText else theme.tabInactiveText)
                val bg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(8).toFloat()
                    if (isSelected) {
                        setColor(theme.tabActiveBg)
                        setStroke(dpToPx(1), theme.tabActiveBorder)
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
                    renderSubFilters(subFilterRow, theme) { renderActiveTab() }
                    renderAllTab(contentLayout, currentQuery, root, theme) { renderActiveTab() }
                }
                Tab.NOTES -> {
                    filterAndSearchContainer.visibility = View.VISIBLE
                    renderNotesFolderFilters(subFilterRow, root, theme) { renderActiveTab() }
                    renderNotesTab(contentLayout, currentQuery, root, theme) { renderActiveTab() }
                }
                Tab.DEVICES -> {
                    filterAndSearchContainer.visibility = View.GONE
                    renderDevicesTab(contentLayout, currentQuery, theme)
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

        // Sleek & compact floating hub window dimensions (reduced width, increased height)
        val panelWidth = (sw * 0.80).toInt().coerceAtMost(dpToPx(320))
        val panelHeight = (sh * 0.58).toInt().coerceIn(dpToPx(430), dpToPx(490))

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
            root.scaleX = 0.86f
            root.scaleY = 0.86f
            root.alpha = 0f
            root.translationY = dpToPx(-14).toFloat()
            windowManager?.addView(root, expParams)
            root.animate()
                .scaleX(1.0f)
                .scaleY(1.0f)
                .alpha(1.0f)
                .translationY(0f)
                .setDuration(240)
                .setInterpolator(OvershootInterpolator(1.08f))
                .start()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add expandedView", e)
        }
    }

    // =========================================================================
    // 2.5 THEME MODEL DYNAMICALLY SYNCED WITH ANDROID APP APPEARANCE
    // =========================================================================

    data class HubTheme(
        val isDark: Boolean,
        val panelBg: Int,
        val panelBorder: Int,
        val cardBg: Int,
        val cardBorder: Int,
        val tabBg: Int,
        val tabBorder: Int,
        val tabActiveBg: Int,
        val tabActiveBorder: Int,
        val tabActiveText: Int,
        val tabInactiveText: Int,
        val chipBg: Int,
        val chipBorder: Int,
        val chipActiveBg: Int,
        val chipActiveBorder: Int,
        val chipActiveText: Int,
        val chipInactiveText: Int,
        val textPrimary: Int,
        val textSecondary: Int,
        val textMuted: Int,
        val accentBlue: Int,
        val deleteBg: Int,
        val deleteBorder: Int,
        val deleteText: Int,
        val inputBg: Int,
        val inputBorder: Int,
        val actionBtnBg: Int
    )

    private fun getHubTheme(): HubTheme {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val appearance = prefs.getString("flutter.appearance", "system")
        val isNightSystem = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES
        val isDark = when (appearance) {
            "dark" -> true
            "light" -> false
            else -> isNightSystem
        }

        return if (isDark) {
            HubTheme(
                isDark = true,
                panelBg = Color.parseColor("#12151D"),
                panelBorder = Color.parseColor("#263142"),
                cardBg = Color.parseColor("#161C26"),
                cardBorder = Color.parseColor("#232C3C"),
                tabBg = Color.parseColor("#161C26"),
                tabBorder = Color.parseColor("#252E3E"),
                tabActiveBg = Color.parseColor("#253247"),
                tabActiveBorder = Color.parseColor("#384B6B"),
                tabActiveText = Color.WHITE,
                tabInactiveText = Color.parseColor("#8E99A8"),
                chipBg = Color.parseColor("#151C26"),
                chipBorder = Color.parseColor("#222C3A"),
                chipActiveBg = Color.parseColor("#1A324A"),
                chipActiveBorder = Color.parseColor("#0284C7"),
                chipActiveText = Color.parseColor("#38BDF8"),
                chipInactiveText = Color.parseColor("#8E99A8"),
                textPrimary = Color.WHITE,
                textSecondary = Color.parseColor("#CBD5E1"),
                textMuted = Color.parseColor("#64748B"),
                accentBlue = Color.parseColor("#38BDF8"),
                deleteBg = Color.parseColor("#2A1C20"),
                deleteBorder = Color.parseColor("#5A2328"),
                deleteText = Color.parseColor("#EF4444"),
                inputBg = Color.parseColor("#1B2230"),
                inputBorder = Color.parseColor("#29354A"),
                actionBtnBg = Color.parseColor("#1C2430")
            )
        } else {
            HubTheme(
                isDark = false,
                panelBg = Color.parseColor("#FFFFFF"),
                panelBorder = Color.parseColor("#CBD5E1"),
                cardBg = Color.parseColor("#F8FAFC"),
                cardBorder = Color.parseColor("#E2E8F0"),
                tabBg = Color.parseColor("#F1F5F9"),
                tabBorder = Color.parseColor("#CBD5E1"),
                tabActiveBg = Color.parseColor("#FFFFFF"),
                tabActiveBorder = Color.parseColor("#94A3B8"),
                tabActiveText = Color.parseColor("#0F172A"),
                tabInactiveText = Color.parseColor("#64748B"),
                chipBg = Color.parseColor("#F1F5F9"),
                chipBorder = Color.parseColor("#E2E8F0"),
                chipActiveBg = Color.parseColor("#E0F2FE"),
                chipActiveBorder = Color.parseColor("#0284C7"),
                chipActiveText = Color.parseColor("#0284C7"),
                chipInactiveText = Color.parseColor("#64748B"),
                textPrimary = Color.parseColor("#0F172A"),
                textSecondary = Color.parseColor("#334155"),
                textMuted = Color.parseColor("#64748B"),
                accentBlue = Color.parseColor("#0284C7"),
                deleteBg = Color.parseColor("#FEE2E2"),
                deleteBorder = Color.parseColor("#FCA5A5"),
                deleteText = Color.parseColor("#DC2626"),
                inputBg = Color.parseColor("#F8FAFC"),
                inputBorder = Color.parseColor("#CBD5E1"),
                actionBtnBg = Color.parseColor("#F1F5F9")
            )
        }
    }

    // =========================================================================
    // 3. TAB 1: ALL (CLIPBOARD HISTORY)
    // =========================================================================

    private fun renderSubFilters(container: LinearLayout, theme: HubTheme, onFilterChanged: () -> Unit) {
        val filters = listOf(
            "all" to "All",
            "pinned" to "📌 Pinned",
            "links" to "🔗 Links",
            "images" to "🖼️ Images",
            "files" to "📁 Files",
            "text" to "📄 Text"
        )
        for ((key, label) in filters) {
            val isSelected = activeSubFilter == key
            val pill = TextView(this).apply {
                text = label
                textSize = 11.5f
                paint.isFakeBoldText = isSelected
                setTextColor(if (isSelected) theme.chipActiveText else theme.chipInactiveText)
                val bg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(14).toFloat()
                    if (isSelected) {
                        setColor(theme.chipActiveBg)
                        setStroke(dpToPx(1), theme.chipActiveBorder)
                    } else {
                        setColor(theme.chipBg)
                        setStroke(dpToPx(1), theme.chipBorder)
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

    private fun getBadgeInfo(value: String, itemType: String): Pair<String, String>? {
        if (itemType == "image") return Pair("IMAGE", "#38BDF8")
        if (itemType == "fileURL" || itemType == "fileURLs") {
            val lower = value.lowercase()
            return when {
                lower.endsWith(".pdf") -> Pair("PDF", "#EF4444")
                lower.endsWith(".doc") || lower.endsWith(".docx") -> Pair("DOC", "#3B82F6")
                lower.endsWith(".xls") || lower.endsWith(".xlsx") || lower.endsWith(".csv") -> Pair("SHEET", "#10B981")
                lower.endsWith(".ppt") || lower.endsWith(".pptx") -> Pair("SLIDE", "#F97316")
                lower.endsWith(".zip") || lower.endsWith(".rar") || lower.endsWith(".7z") || lower.endsWith(".tar") || lower.endsWith(".gz") -> Pair("ZIP", "#8B5CF6")
                lower.endsWith(".apk") -> Pair("APK", "#22C55E")
                lower.endsWith(".mp3") || lower.endsWith(".wav") || lower.endsWith(".m4a") -> Pair("AUDIO", "#EC4899")
                lower.endsWith(".mp4") || lower.endsWith(".mkv") || lower.endsWith(".mov") -> Pair("VIDEO", "#EAB308")
                else -> Pair("FILE", "#F59E0B")
            }
        }
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

    private fun renderAllTab(
        container: LinearLayout,
        query: String,
        root: FrameLayout,
        theme: HubTheme,
        onRefresh: () -> Unit
    ) {
        val clips = fetchClipboardItems(query, activeSubFilter)

        if (clips.isEmpty()) {
            val emptyTv = TextView(this).apply {
                text = if (query.isEmpty()) "Clipboard history is empty" else "No matching clips found"
                setTextColor(theme.textMuted)
                textSize = 13f
                gravity = Gravity.CENTER
                setPadding(0, dpToPx(40), 0, dpToPx(40))
            }
            container.addView(emptyTv)
            return
        }

        for (clip in clips) {
            val isImage = clip.type == "image"
            val isFile = clip.type == "fileURL" || clip.type == "fileURLs"
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                val bg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(8).toFloat()
                    setColor(theme.cardBg)
                    setStroke(dpToPx(1), theme.cardBorder)
                }
                background = bg
                setPadding(dpToPx(8), dpToPx(6), dpToPx(8), dpToPx(6))
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    setMargins(0, 0, 0, dpToPx(5))
                }
            }

            // macOS-Style Left Blue Accent Indicator Line
            val leftIndicator = View(this).apply {
                layoutParams = LinearLayout.LayoutParams(dpToPx(3), dpToPx(24)).apply {
                    setMargins(0, 0, dpToPx(6), 0)
                }
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(2).toFloat()
                    setColor(theme.accentBlue)
                }
            }
            row.addView(leftIndicator)

            // Left: Thumbnail for image, icon for file, or Pin icon
            if (isImage) {
                val thumbView = ImageView(this).apply {
                    layoutParams = LinearLayout.LayoutParams(dpToPx(38), dpToPx(28)).apply {
                        setMargins(0, 0, dpToPx(8), 0)
                    }
                    scaleType = ImageView.ScaleType.CENTER_CROP
                    clipToOutline = true
                    background = GradientDrawable().apply {
                        cornerRadius = dpToPx(4).toFloat()
                        setColor(if (theme.isDark) Color.parseColor("#1F2937") else Color.parseColor("#E2E8F0"))
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
            } else if (isFile) {
                val fileIconView = TextView(this).apply {
                    text = "📄"
                    textSize = 14f
                    gravity = Gravity.CENTER
                    val fBg = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dpToPx(6).toFloat()
                        setColor(theme.inputBg)
                        setStroke(dpToPx(1), theme.cardBorder)
                    }
                    background = fBg
                    layoutParams = LinearLayout.LayoutParams(dpToPx(30), dpToPx(28)).apply {
                        setMargins(0, 0, dpToPx(8), 0)
                    }
                }
                row.addView(fileIconView)
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

            val badgePair = getBadgeInfo(clip.value, clip.type)
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

            val fileName = if (isFile) File(clip.value).name else ""
            val bodyTv = TextView(this).apply {
                text = if (isImage) "[Image]" else if (isFile) (if (fileName.isNotEmpty()) fileName else "[File]") else clip.value.replace("\n", " ").trim()
                setTextColor(theme.textPrimary)
                textSize = 12.5f
                paint.isFakeBoldText = true
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            }
            titleLine.addView(bodyTv)
            textCol.addView(titleLine)

            var fileDetails = ""
            if (isFile) {
                val f = File(clip.value)
                if (f.exists()) {
                    val kb = f.length() / 1024
                    fileDetails = if (kb >= 1024) " · ${(kb / 1024f).toInt()} MB" else " · $kb KB"
                }
            }
            val subTv = TextView(this).apply {
                text = formatTimeAgo(clip.createdAt) + (if (clip.sourceApp.isNotEmpty()) " · ${clip.sourceApp}" else "") + fileDetails
                setTextColor(theme.textMuted)
                textSize = 9.5f
                setPadding(0, dpToPx(1), 0, 0)
            }
            textCol.addView(subTv)

            row.addView(textCol)

            // Direct tap-to-paste
            row.setOnClickListener {
                if (isImage) {
                    copyToClipboard(clip.value, isImage = true)
                } else if (isFile) {
                    copyFileToClipboard(clip.value)
                } else {
                    executePaste(clip.value)
                }
            }

            // Right: macOS-Style Action Buttons (📌 Pin, 📄 Save Note, 🗑️ Delete) - No copy icon
            val actions = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }

            val btnPin = TextView(this).apply {
                text = "📌"
                textSize = 11.5f
                val pBg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(5).toFloat()
                    setColor(if (clip.isPinned) theme.chipActiveBg else theme.actionBtnBg)
                    setStroke(dpToPx(1), if (clip.isPinned) theme.chipActiveBorder else theme.cardBorder)
                }
                background = pBg
                setPadding(dpToPx(6), dpToPx(4), dpToPx(6), dpToPx(4))
                val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    setMargins(0, 0, dpToPx(4), 0)
                }
                layoutParams = lp
                setOnClickListener {
                    togglePinClip(clip.hash)
                    onRefresh()
                }
            }

            val btnNote = TextView(this).apply {
                text = "📄"
                textSize = 11.5f
                val nBg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(5).toFloat()
                    setColor(theme.actionBtnBg)
                    setStroke(dpToPx(1), theme.cardBorder)
                }
                background = nBg
                setPadding(dpToPx(6), dpToPx(4), dpToPx(6), dpToPx(4))
                val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    setMargins(0, 0, dpToPx(4), 0)
                }
                layoutParams = lp
                setOnClickListener {
                    showSaveNoteDialog(clip.value, root, theme, onRefresh)
                }
            }

            val btnDelete = TextView(this).apply {
                text = "🗑️"
                textSize = 11.5f
                val dBg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(5).toFloat()
                    setColor(theme.deleteBg)
                    setStroke(dpToPx(1), theme.deleteBorder)
                }
                background = dBg
                setPadding(dpToPx(6), dpToPx(4), dpToPx(6), dpToPx(4))
                setOnClickListener {
                    deleteClip(clip.id)
                    onRefresh()
                }
            }

            actions.addView(btnPin)
            actions.addView(btnNote)
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

    private fun renderNotesFolderFilters(
        container: LinearLayout,
        root: FrameLayout,
        theme: HubTheme,
        onFilterChanged: () -> Unit
    ) {
        val folders = fetchSnippetFolders()

        val allPill = TextView(this).apply {
            text = "All Folders"
            textSize = 11.5f
            val isSelected = activeFolderId == "all"
            paint.isFakeBoldText = isSelected
            setTextColor(if (isSelected) theme.chipActiveText else theme.chipInactiveText)
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(14).toFloat()
                if (isSelected) {
                    setColor(theme.chipActiveBg)
                    setStroke(dpToPx(1), theme.chipActiveBorder)
                } else {
                    setColor(theme.chipBg)
                    setStroke(dpToPx(1), theme.chipBorder)
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
                setTextColor(if (isSelected) theme.chipActiveText else theme.chipInactiveText)
                val bg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(14).toFloat()
                    if (isSelected) {
                        setColor(theme.chipActiveBg)
                        setStroke(dpToPx(1), theme.chipActiveBorder)
                    } else {
                        setColor(theme.chipBg)
                        setStroke(dpToPx(1), theme.chipBorder)
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

        // [+ New Folder] chip
        val newFolderPill = TextView(this).apply {
            text = "+ New Folder"
            textSize = 11.5f
            paint.isFakeBoldText = true
            setTextColor(theme.accentBlue)
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(14).toFloat()
                setColor(theme.chipBg)
                setStroke(dpToPx(1), theme.accentBlue)
            }
            background = bg
            setPadding(dpToPx(10), dpToPx(4), dpToPx(10), dpToPx(4))
            setOnClickListener {
                showNewFolderInlineDialog(root, theme) { newId, _ ->
                    activeFolderId = newId
                    onFilterChanged()
                }
            }
        }
        container.addView(newFolderPill)
    }

    private fun renderNotesTab(
        container: LinearLayout,
        query: String,
        root: FrameLayout,
        theme: HubTheme,
        onRefresh: () -> Unit
    ) {
        val folders = fetchSnippetFolders()
        val notes = fetchNotes(query, activeFolderId)

        // Top folder header card: 📁 Folder Title, note count, and [+ Add Note] button (macOS Model)
        val activeFolderTitle = if (activeFolderId == "all") "All Notes" else (folders.firstOrNull { it.first == activeFolderId }?.second ?: "Notes")
        val folderHeaderCard = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(theme.cardBg)
                setStroke(dpToPx(1), theme.cardBorder)
            }
            background = bg
            setPadding(dpToPx(10), dpToPx(8), dpToPx(10), dpToPx(8))
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, dpToPx(8))
            }
            layoutParams = lp
        }

        val folderTitleCol = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        val folderTitleTv = TextView(this).apply {
            text = "📁 $activeFolderTitle"
            setTextColor(theme.textPrimary)
            textSize = 12.5f
            paint.isFakeBoldText = true
        }
        val folderCountTv = TextView(this).apply {
            text = "${notes.size} note${if (notes.size == 1) "" else "s"}"
            setTextColor(theme.textMuted)
            textSize = 10f
        }
        folderTitleCol.addView(folderTitleTv)
        folderTitleCol.addView(folderCountTv)
        folderHeaderCard.addView(folderTitleCol)

        val btnAddNote = TextView(this).apply {
            text = "+ Add Note"
            setTextColor(theme.accentBlue)
            textSize = 11.5f
            paint.isFakeBoldText = true
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(6).toFloat()
                setColor(theme.chipActiveBg)
                setStroke(dpToPx(1), theme.chipActiveBorder)
            }
            background = bg
            setPadding(dpToPx(8), dpToPx(4), dpToPx(8), dpToPx(4))
            setOnClickListener {
                showCreateNoteDialog(activeFolderId, root, theme, onRefresh)
            }
        }
        folderHeaderCard.addView(btnAddNote)
        container.addView(folderHeaderCard)

        if (notes.isEmpty()) {
            val emptyTv = TextView(this).apply {
                text = if (query.isEmpty()) "No saved notes in this category" else "No matching notes found"
                setTextColor(theme.textMuted)
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
                    setColor(theme.cardBg)
                    setStroke(dpToPx(1), theme.cardBorder)
                }
                background = bg
                setPadding(dpToPx(12), dpToPx(10), dpToPx(12), dpToPx(10))
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    setMargins(0, 0, 0, dpToPx(8))
                }
            }

            // Top meta with macOS-Style Blue Accent Indicator
            val metaRow = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }

            val leftIndicator = View(this).apply {
                layoutParams = LinearLayout.LayoutParams(dpToPx(3), dpToPx(16)).apply {
                    setMargins(0, 0, dpToPx(6), 0)
                }
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(2).toFloat()
                    setColor(theme.accentBlue)
                }
            }
            metaRow.addView(leftIndicator)

            val folderBadge = TextView(this).apply {
                text = note.folderTitle.uppercase()
                setTextColor(theme.accentBlue)
                textSize = 10.5f
                paint.isFakeBoldText = true
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            }

            metaRow.addView(folderBadge)
            card.addView(metaRow)

            // Note title
            val titleTv = TextView(this).apply {
                text = note.title
                setTextColor(theme.textPrimary)
                textSize = 14f
                paint.isFakeBoldText = true
                setPadding(0, dpToPx(4), 0, dpToPx(2))
            }
            card.addView(titleTv)

            // Note body
            val bodyTv = TextView(this).apply {
                text = note.content
                setTextColor(theme.textSecondary)
                textSize = 12.5f
                maxLines = 3
                ellipsize = TextUtils.TruncateAt.END
                setPadding(0, 0, 0, dpToPx(8))
            }
            card.addView(bodyTv)

            // Actions row: macOS-Style (✏️ Edit, 🗑️ Delete) - No copy icon
            val actionRow = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }

            val btnEdit = TextView(this).apply {
                text = "✏️"
                textSize = 11.5f
                val eBg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(5).toFloat()
                    setColor(theme.actionBtnBg)
                    setStroke(dpToPx(1), theme.cardBorder)
                }
                background = eBg
                setPadding(dpToPx(6), dpToPx(4), dpToPx(6), dpToPx(4))
                val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    setMargins(0, 0, dpToPx(4), 0)
                }
                layoutParams = lp
                setOnClickListener {
                    showEditNoteDialog(note, root, theme, onRefresh)
                }
            }

            val btnDelete = TextView(this).apply {
                text = "🗑️"
                textSize = 11.5f
                val dBg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(5).toFloat()
                    setColor(theme.deleteBg)
                    setStroke(dpToPx(1), theme.deleteBorder)
                }
                background = dBg
                setPadding(dpToPx(6), dpToPx(4), dpToPx(6), dpToPx(4))
                setOnClickListener {
                    deleteNote(note.id)
                    onRefresh()
                }
            }

            actionRow.addView(btnEdit)
            actionRow.addView(btnDelete)
            card.addView(actionRow)

            card.setOnClickListener {
                executePaste(note.content)
            }

            container.addView(card)
        }
    }

    // =========================================================================
    // 4.5 IN-HUB NOTE DIALOGS (SAVE AS NOTE, CREATE NOTE, EDIT NOTE, NEW FOLDER)
    // =========================================================================

    private fun showSaveNoteDialog(
        clipValue: String,
        root: FrameLayout,
        theme: HubTheme,
        onComplete: () -> Unit
    ) {
        val overlay = FrameLayout(this).apply {
            setBackgroundColor(if (theme.isDark) Color.argb(190, 8, 11, 16) else Color.argb(150, 15, 23, 42))
            isClickable = true
            isFocusable = true
        }

        val dialogContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(14).toFloat()
                setColor(theme.panelBg)
                setStroke(dpToPx(1), theme.panelBorder)
            }
            background = bg
            elevation = dpToPx(24).toFloat()
            setPadding(dpToPx(14), dpToPx(12), dpToPx(14), dpToPx(12))
            val lp = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.CENTER
                setMargins(dpToPx(12), dpToPx(12), dpToPx(12), dpToPx(12))
            }
            layoutParams = lp
        }
        overlay.addView(dialogContainer)

        // Header Row
        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dpToPx(10))
        }
        val headerTitle = TextView(this).apply {
            text = "Save to Notes"
            setTextColor(theme.textPrimary)
            textSize = 14.5f
            paint.isFakeBoldText = true
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        val closeBtn = TextView(this).apply {
            text = "✕"
            setTextColor(theme.textMuted)
            textSize = 13.5f
            gravity = Gravity.CENTER
            setPadding(dpToPx(6), dpToPx(4), dpToPx(6), dpToPx(4))
            setOnClickListener { root.removeView(overlay) }
        }
        headerRow.addView(headerTitle)
        headerRow.addView(closeBtn)
        dialogContainer.addView(headerRow)

        // Folders list
        val folders = fetchSnippetFolders().toMutableList()
        if (folders.isEmpty()) {
            val genId = createSnippetFolder("General")
            folders.add(Pair(genId, "General"))
        }
        var selectedFolderId = if (activeFolderId != "all" && folders.any { it.first == activeFolderId }) activeFolderId else folders.first().first

        val folderLabel = TextView(this).apply {
            text = "SELECT FOLDER"
            setTextColor(theme.textMuted)
            textSize = 9.5f
            paint.isFakeBoldText = true
            setPadding(0, 0, 0, dpToPx(4))
        }
        dialogContainer.addView(folderLabel)

        val folderChipsScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            setPadding(0, 0, 0, dpToPx(8))
        }
        val folderChipsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        folderChipsScroll.addView(folderChipsRow)
        dialogContainer.addView(folderChipsScroll)

        fun rebuildFolderChips() {
            folderChipsRow.removeAllViews()
            for ((fId, fTitle) in folders) {
                val isSelected = selectedFolderId == fId
                val chip = TextView(this).apply {
                    text = fTitle
                    textSize = 11.5f
                    paint.isFakeBoldText = isSelected
                    setTextColor(if (isSelected) theme.chipActiveText else theme.chipInactiveText)
                    val bg = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dpToPx(12).toFloat()
                        setColor(if (isSelected) theme.chipActiveBg else theme.chipBg)
                        setStroke(dpToPx(1), if (isSelected) theme.chipActiveBorder else theme.chipBorder)
                    }
                    background = bg
                    setPadding(dpToPx(10), dpToPx(4), dpToPx(10), dpToPx(4))
                    val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                        setMargins(0, 0, dpToPx(5), 0)
                    }
                    layoutParams = lp
                    setOnClickListener {
                        selectedFolderId = fId
                        rebuildFolderChips()
                    }
                }
                folderChipsRow.addView(chip)
            }

            // [+ New Folder] chip
            val newFolderChip = TextView(this).apply {
                text = "+ New Folder"
                textSize = 11.5f
                paint.isFakeBoldText = true
                setTextColor(theme.accentBlue)
                val bg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(12).toFloat()
                    setColor(theme.chipBg)
                    setStroke(dpToPx(1), theme.accentBlue)
                }
                background = bg
                setPadding(dpToPx(8), dpToPx(4), dpToPx(8), dpToPx(4))
                setOnClickListener {
                    showNewFolderInlineDialog(root, theme) { newId, newTitle ->
                        folders.add(Pair(newId, newTitle))
                        selectedFolderId = newId
                        rebuildFolderChips()
                    }
                }
            }
            folderChipsRow.addView(newFolderChip)
        }
        rebuildFolderChips()

        // Title input
        val titleLabel = TextView(this).apply {
            text = "NOTE TITLE"
            setTextColor(theme.textMuted)
            textSize = 9.5f
            paint.isFakeBoldText = true
            setPadding(0, 0, 0, dpToPx(4))
        }
        dialogContainer.addView(titleLabel)

        val defaultTitle = clipValue.lines().firstOrNull { it.isNotBlank() }?.trim() ?: "Note"
        val titleInput = EditText(this).apply {
            setText(if (defaultTitle.length > 40) defaultTitle.take(40) else defaultTitle)
            setTextColor(theme.textPrimary)
            setHintTextColor(theme.textMuted)
            hint = "Note Title..."
            textSize = 13f
            maxLines = 1
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(theme.inputBg)
                setStroke(dpToPx(1), theme.inputBorder)
            }
            background = bg
            setPadding(dpToPx(10), dpToPx(8), dpToPx(10), dpToPx(8))
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, dpToPx(8))
            }
            layoutParams = lp
        }
        dialogContainer.addView(titleInput)

        // Content preview
        val contentLabel = TextView(this).apply {
            text = "CONTENT PREVIEW"
            setTextColor(theme.textMuted)
            textSize = 9.5f
            paint.isFakeBoldText = true
            setPadding(0, 0, 0, dpToPx(4))
        }
        dialogContainer.addView(contentLabel)

        val previewBox = TextView(this).apply {
            text = clipValue
            setTextColor(theme.textSecondary)
            textSize = 11.5f
            maxLines = 4
            ellipsize = TextUtils.TruncateAt.END
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(theme.cardBg)
                setStroke(dpToPx(1), theme.cardBorder)
            }
            background = bg
            setPadding(dpToPx(10), dpToPx(8), dpToPx(10), dpToPx(8))
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, dpToPx(12))
            }
            layoutParams = lp
        }
        dialogContainer.addView(previewBox)

        // Action buttons
        val btnRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }

        val btnCancel = TextView(this).apply {
            text = "Cancel"
            setTextColor(theme.textMuted)
            textSize = 12.5f
            paint.isFakeBoldText = true
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(theme.actionBtnBg)
                setStroke(dpToPx(1), theme.cardBorder)
            }
            background = bg
            setPadding(dpToPx(14), dpToPx(8), dpToPx(14), dpToPx(8))
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, dpToPx(8), 0)
            }
            layoutParams = lp
            setOnClickListener { root.removeView(overlay) }
        }

        val btnSave = TextView(this).apply {
            text = "Save Note"
            setTextColor(Color.WHITE)
            textSize = 12.5f
            paint.isFakeBoldText = true
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(Color.parseColor("#0284C7"))
            }
            background = bg
            setPadding(dpToPx(16), dpToPx(8), dpToPx(16), dpToPx(8))
            setOnClickListener {
                val title = titleInput.text.toString().trim()
                val ok = insertSnippet(selectedFolderId, if (title.isEmpty()) "Note" else title, clipValue)
                if (ok) {
                    val folderName = folders.firstOrNull { it.first == selectedFolderId }?.second ?: "Notes"
                    Toast.makeText(this@FloatingHubService, "Saved to $folderName", Toast.LENGTH_SHORT).show()
                    root.removeView(overlay)
                    onComplete()
                } else {
                    Toast.makeText(this@FloatingHubService, "Failed to save note", Toast.LENGTH_SHORT).show()
                }
            }
        }

        btnRow.addView(btnCancel)
        btnRow.addView(btnSave)
        dialogContainer.addView(btnRow)

        root.addView(overlay, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    }

    private fun showCreateNoteDialog(
        defaultFolderId: String,
        root: FrameLayout,
        theme: HubTheme,
        onComplete: () -> Unit
    ) {
        val overlay = FrameLayout(this).apply {
            setBackgroundColor(if (theme.isDark) Color.argb(190, 8, 11, 16) else Color.argb(150, 15, 23, 42))
            isClickable = true
            isFocusable = true
        }

        val dialogContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(14).toFloat()
                setColor(theme.panelBg)
                setStroke(dpToPx(1), theme.panelBorder)
            }
            background = bg
            elevation = dpToPx(24).toFloat()
            setPadding(dpToPx(14), dpToPx(12), dpToPx(14), dpToPx(12))
            val lp = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.CENTER
                setMargins(dpToPx(12), dpToPx(12), dpToPx(12), dpToPx(12))
            }
            layoutParams = lp
        }
        overlay.addView(dialogContainer)

        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dpToPx(10))
        }
        val headerTitle = TextView(this).apply {
            text = "Create Note"
            setTextColor(theme.textPrimary)
            textSize = 14.5f
            paint.isFakeBoldText = true
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        val closeBtn = TextView(this).apply {
            text = "✕"
            setTextColor(theme.textMuted)
            textSize = 13.5f
            gravity = Gravity.CENTER
            setPadding(dpToPx(6), dpToPx(4), dpToPx(6), dpToPx(4))
            setOnClickListener { root.removeView(overlay) }
        }
        headerRow.addView(headerTitle)
        headerRow.addView(closeBtn)
        dialogContainer.addView(headerRow)

        val folders = fetchSnippetFolders().toMutableList()
        if (folders.isEmpty()) {
            val genId = createSnippetFolder("General")
            folders.add(Pair(genId, "General"))
        }
        var selectedFolderId = if (defaultFolderId != "all" && folders.any { it.first == defaultFolderId }) defaultFolderId else folders.first().first

        val folderLabel = TextView(this).apply {
            text = "FOLDER"
            setTextColor(theme.textMuted)
            textSize = 9.5f
            paint.isFakeBoldText = true
            setPadding(0, 0, 0, dpToPx(4))
        }
        dialogContainer.addView(folderLabel)

        val folderChipsScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            setPadding(0, 0, 0, dpToPx(8))
        }
        val folderChipsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        folderChipsScroll.addView(folderChipsRow)
        dialogContainer.addView(folderChipsScroll)

        fun rebuildFolderChips() {
            folderChipsRow.removeAllViews()
            for ((fId, fTitle) in folders) {
                val isSelected = selectedFolderId == fId
                val chip = TextView(this).apply {
                    text = fTitle
                    textSize = 11.5f
                    paint.isFakeBoldText = isSelected
                    setTextColor(if (isSelected) theme.chipActiveText else theme.chipInactiveText)
                    val bg = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dpToPx(12).toFloat()
                        setColor(if (isSelected) theme.chipActiveBg else theme.chipBg)
                        setStroke(dpToPx(1), if (isSelected) theme.chipActiveBorder else theme.chipBorder)
                    }
                    background = bg
                    setPadding(dpToPx(10), dpToPx(4), dpToPx(10), dpToPx(4))
                    val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                        setMargins(0, 0, dpToPx(5), 0)
                    }
                    layoutParams = lp
                    setOnClickListener {
                        selectedFolderId = fId
                        rebuildFolderChips()
                    }
                }
                folderChipsRow.addView(chip)
            }
        }
        rebuildFolderChips()

        // Title input
        val titleLabel = TextView(this).apply {
            text = "TITLE"
            setTextColor(theme.textMuted)
            textSize = 9.5f
            paint.isFakeBoldText = true
            setPadding(0, 0, 0, dpToPx(4))
        }
        dialogContainer.addView(titleLabel)

        val titleInput = EditText(this).apply {
            setTextColor(theme.textPrimary)
            setHintTextColor(theme.textMuted)
            hint = "Note Title..."
            textSize = 13f
            maxLines = 1
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(theme.inputBg)
                setStroke(dpToPx(1), theme.inputBorder)
            }
            background = bg
            setPadding(dpToPx(10), dpToPx(8), dpToPx(10), dpToPx(8))
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, dpToPx(8))
            }
            layoutParams = lp
        }
        dialogContainer.addView(titleInput)

        // Content input
        val contentLabel = TextView(this).apply {
            text = "CONTENT"
            setTextColor(theme.textMuted)
            textSize = 9.5f
            paint.isFakeBoldText = true
            setPadding(0, 0, 0, dpToPx(4))
        }
        dialogContainer.addView(contentLabel)

        val contentInput = EditText(this).apply {
            setTextColor(theme.textPrimary)
            setHintTextColor(theme.textMuted)
            hint = "Type note body here..."
            textSize = 12.5f
            minLines = 3
            maxLines = 5
            gravity = Gravity.TOP or Gravity.START
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(theme.inputBg)
                setStroke(dpToPx(1), theme.inputBorder)
            }
            background = bg
            setPadding(dpToPx(10), dpToPx(8), dpToPx(10), dpToPx(8))
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, dpToPx(12))
            }
            layoutParams = lp
        }
        dialogContainer.addView(contentInput)

        // Buttons
        val btnRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }
        val btnCancel = TextView(this).apply {
            text = "Cancel"
            setTextColor(theme.textMuted)
            textSize = 12.5f
            paint.isFakeBoldText = true
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(theme.actionBtnBg)
                setStroke(dpToPx(1), theme.cardBorder)
            }
            background = bg
            setPadding(dpToPx(14), dpToPx(8), dpToPx(14), dpToPx(8))
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, dpToPx(8), 0)
            }
            layoutParams = lp
            setOnClickListener { root.removeView(overlay) }
        }
        val btnSave = TextView(this).apply {
            text = "Save Note"
            setTextColor(Color.WHITE)
            textSize = 12.5f
            paint.isFakeBoldText = true
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(Color.parseColor("#0284C7"))
            }
            background = bg
            setPadding(dpToPx(16), dpToPx(8), dpToPx(16), dpToPx(8))
            setOnClickListener {
                val title = titleInput.text.toString().trim()
                val content = contentInput.text.toString().trim()
                if (content.isEmpty()) {
                    Toast.makeText(this@FloatingHubService, "Please enter note content", Toast.LENGTH_SHORT).show()
                    return@setOnClickListener
                }
                val ok = insertSnippet(selectedFolderId, if (title.isEmpty()) "Note" else title, content)
                if (ok) {
                    Toast.makeText(this@FloatingHubService, "Note created", Toast.LENGTH_SHORT).show()
                    root.removeView(overlay)
                    onComplete()
                }
            }
        }
        btnRow.addView(btnCancel)
        btnRow.addView(btnSave)
        dialogContainer.addView(btnRow)

        root.addView(overlay, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    }

    private fun showEditNoteDialog(
        note: NoteItem,
        root: FrameLayout,
        theme: HubTheme,
        onComplete: () -> Unit
    ) {
        val overlay = FrameLayout(this).apply {
            setBackgroundColor(if (theme.isDark) Color.argb(190, 8, 11, 16) else Color.argb(150, 15, 23, 42))
            isClickable = true
            isFocusable = true
        }

        val dialogContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(14).toFloat()
                setColor(theme.panelBg)
                setStroke(dpToPx(1), theme.panelBorder)
            }
            background = bg
            elevation = dpToPx(24).toFloat()
            setPadding(dpToPx(14), dpToPx(12), dpToPx(14), dpToPx(12))
            val lp = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.CENTER
                setMargins(dpToPx(12), dpToPx(12), dpToPx(12), dpToPx(12))
            }
            layoutParams = lp
        }
        overlay.addView(dialogContainer)

        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dpToPx(10))
        }
        val headerTitle = TextView(this).apply {
            text = "Edit Note (${note.folderTitle})"
            setTextColor(theme.textPrimary)
            textSize = 14.5f
            paint.isFakeBoldText = true
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        val closeBtn = TextView(this).apply {
            text = "✕"
            setTextColor(theme.textMuted)
            textSize = 13.5f
            gravity = Gravity.CENTER
            setPadding(dpToPx(6), dpToPx(4), dpToPx(6), dpToPx(4))
            setOnClickListener { root.removeView(overlay) }
        }
        headerRow.addView(headerTitle)
        headerRow.addView(closeBtn)
        dialogContainer.addView(headerRow)

        // Title
        val titleLabel = TextView(this).apply {
            text = "TITLE"
            setTextColor(theme.textMuted)
            textSize = 9.5f
            paint.isFakeBoldText = true
            setPadding(0, 0, 0, dpToPx(4))
        }
        dialogContainer.addView(titleLabel)

        val titleInput = EditText(this).apply {
            setText(note.title)
            setTextColor(theme.textPrimary)
            setHintTextColor(theme.textMuted)
            textSize = 13f
            maxLines = 1
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(theme.inputBg)
                setStroke(dpToPx(1), theme.inputBorder)
            }
            background = bg
            setPadding(dpToPx(10), dpToPx(8), dpToPx(10), dpToPx(8))
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, dpToPx(8))
            }
            layoutParams = lp
        }
        dialogContainer.addView(titleInput)

        // Content
        val contentLabel = TextView(this).apply {
            text = "CONTENT"
            setTextColor(theme.textMuted)
            textSize = 9.5f
            paint.isFakeBoldText = true
            setPadding(0, 0, 0, dpToPx(4))
        }
        dialogContainer.addView(contentLabel)

        val contentInput = EditText(this).apply {
            setText(note.content)
            setTextColor(theme.textPrimary)
            setHintTextColor(theme.textMuted)
            textSize = 12.5f
            minLines = 3
            maxLines = 6
            gravity = Gravity.TOP or Gravity.START
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(theme.inputBg)
                setStroke(dpToPx(1), theme.inputBorder)
            }
            background = bg
            setPadding(dpToPx(10), dpToPx(8), dpToPx(10), dpToPx(8))
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, dpToPx(12))
            }
            layoutParams = lp
        }
        dialogContainer.addView(contentInput)

        // Buttons
        val btnRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }
        val btnCancel = TextView(this).apply {
            text = "Cancel"
            setTextColor(theme.textMuted)
            textSize = 12.5f
            paint.isFakeBoldText = true
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(theme.actionBtnBg)
                setStroke(dpToPx(1), theme.cardBorder)
            }
            background = bg
            setPadding(dpToPx(14), dpToPx(8), dpToPx(14), dpToPx(8))
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, dpToPx(8), 0)
            }
            layoutParams = lp
            setOnClickListener { root.removeView(overlay) }
        }
        val btnSave = TextView(this).apply {
            text = "Save Changes"
            setTextColor(Color.WHITE)
            textSize = 12.5f
            paint.isFakeBoldText = true
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(Color.parseColor("#0284C7"))
            }
            background = bg
            setPadding(dpToPx(16), dpToPx(8), dpToPx(16), dpToPx(8))
            setOnClickListener {
                val title = titleInput.text.toString().trim()
                val content = contentInput.text.toString().trim()
                if (content.isEmpty()) {
                    Toast.makeText(this@FloatingHubService, "Please enter note content", Toast.LENGTH_SHORT).show()
                    return@setOnClickListener
                }
                val ok = updateSnippet(note.id, title, content)
                if (ok) {
                    Toast.makeText(this@FloatingHubService, "Note updated", Toast.LENGTH_SHORT).show()
                    root.removeView(overlay)
                    onComplete()
                }
            }
        }
        btnRow.addView(btnCancel)
        btnRow.addView(btnSave)
        dialogContainer.addView(btnRow)

        root.addView(overlay, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    }

    private fun showNewFolderInlineDialog(
        root: FrameLayout,
        theme: HubTheme,
        onCreated: (String, String) -> Unit
    ) {
        val overlay = FrameLayout(this).apply {
            setBackgroundColor(if (theme.isDark) Color.argb(190, 8, 11, 16) else Color.argb(150, 15, 23, 42))
            isClickable = true
            isFocusable = true
        }

        val dialogContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(14).toFloat()
                setColor(theme.panelBg)
                setStroke(dpToPx(1), theme.panelBorder)
            }
            background = bg
            elevation = dpToPx(24).toFloat()
            setPadding(dpToPx(14), dpToPx(12), dpToPx(14), dpToPx(12))
            val lp = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.CENTER
                setMargins(dpToPx(16), dpToPx(16), dpToPx(16), dpToPx(16))
            }
            layoutParams = lp
        }
        overlay.addView(dialogContainer)

        val headerTitle = TextView(this).apply {
            text = "Create New Folder"
            setTextColor(theme.textPrimary)
            textSize = 14f
            paint.isFakeBoldText = true
            setPadding(0, 0, 0, dpToPx(8))
        }
        dialogContainer.addView(headerTitle)

        val nameInput = EditText(this).apply {
            hint = "Folder name (e.g. Work, Ideas)"
            setTextColor(theme.textPrimary)
            setHintTextColor(theme.textMuted)
            textSize = 13f
            maxLines = 1
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(theme.inputBg)
                setStroke(dpToPx(1), theme.inputBorder)
            }
            background = bg
            setPadding(dpToPx(10), dpToPx(8), dpToPx(10), dpToPx(8))
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, dpToPx(12))
            }
            layoutParams = lp
        }
        dialogContainer.addView(nameInput)

        val btnRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }
        val btnCancel = TextView(this).apply {
            text = "Cancel"
            setTextColor(theme.textMuted)
            textSize = 12.5f
            paint.isFakeBoldText = true
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(theme.actionBtnBg)
                setStroke(dpToPx(1), theme.cardBorder)
            }
            background = bg
            setPadding(dpToPx(14), dpToPx(8), dpToPx(14), dpToPx(8))
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, dpToPx(8), 0)
            }
            layoutParams = lp
            setOnClickListener { root.removeView(overlay) }
        }
        val btnCreate = TextView(this).apply {
            text = "Create"
            setTextColor(Color.WHITE)
            textSize = 12.5f
            paint.isFakeBoldText = true
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(Color.parseColor("#0284C7"))
            }
            background = bg
            setPadding(dpToPx(16), dpToPx(8), dpToPx(16), dpToPx(8))
            setOnClickListener {
                val name = nameInput.text.toString().trim()
                if (name.isEmpty()) {
                    Toast.makeText(this@FloatingHubService, "Please enter folder name", Toast.LENGTH_SHORT).show()
                    return@setOnClickListener
                }
                val newId = createSnippetFolder(name)
                if (newId.isNotEmpty()) {
                    Toast.makeText(this@FloatingHubService, "Folder '$name' created", Toast.LENGTH_SHORT).show()
                    root.removeView(overlay)
                    onCreated(newId, name)
                } else {
                    Toast.makeText(this@FloatingHubService, "Failed to create folder", Toast.LENGTH_SHORT).show()
                }
            }
        }
        btnRow.addView(btnCancel)
        btnRow.addView(btnCreate)
        dialogContainer.addView(btnRow)

        root.addView(overlay, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        nameInput.requestFocus()
        val imm = getSystemService(INPUT_METHOD_SERVICE) as? android.view.inputmethod.InputMethodManager
        imm?.showSoftInput(nameInput, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
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

    private fun renderDevicesTab(container: LinearLayout, query: String, theme: HubTheme) {
        // 1. This Phone Status Card
        val thisDeviceCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(10).toFloat()
                setColor(theme.cardBg)
                setStroke(dpToPx(1), theme.accentBlue)
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
            setTextColor(theme.textPrimary)
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
            setTextColor(theme.textMuted)
            textSize = 11.5f
            setPadding(0, dpToPx(4), 0, 0)
        }
        thisDeviceCard.addView(portSub)
        container.addView(thisDeviceCard)

        // 2. Paired Peers List
        val devices = fetchPairedDevices()

        val labelDevices = TextView(this).apply {
            text = "PAIRED PEERS"
            setTextColor(theme.textMuted)
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
                    setColor(theme.cardBg)
                    setStroke(dpToPx(1), theme.cardBorder)
                }
                background = bg
                setPadding(dpToPx(16), dpToPx(24), dpToPx(16), dpToPx(24))
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    setMargins(0, 0, 0, dpToPx(12))
                }
            }

            val emptyMsg = TextView(this).apply {
                text = "No paired Mac or companion devices yet."
                setTextColor(theme.textMuted)
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
                        setColor(theme.cardBg)
                        setStroke(dpToPx(1), theme.cardBorder)
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
                    setTextColor(theme.textPrimary)
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

                val btnActions = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }

                val btnConnect = TextView(this).apply {
                    text = "⚡ Connect"
                    setTextColor(theme.accentBlue)
                    textSize = 11f
                    paint.isFakeBoldText = true
                    val cBg = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dpToPx(6).toFloat()
                        setColor(theme.chipActiveBg)
                        setStroke(dpToPx(1), theme.chipActiveBorder)
                    }
                    background = cBg
                    setPadding(dpToPx(8), dpToPx(4), dpToPx(8), dpToPx(4))
                    val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                        setMargins(0, 0, dpToPx(6), 0)
                    }
                    layoutParams = lp
                    setOnClickListener {
                        val intent = Intent(this@FloatingHubService, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        }
                        startActivity(intent)
                        collapse()
                    }
                }

                val btnUnpair = TextView(this).apply {
                    text = "Unpair"
                    setTextColor(theme.deleteText)
                    textSize = 11f
                    paint.isFakeBoldText = true
                    val bBg = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dpToPx(6).toFloat()
                        setColor(theme.deleteBg)
                        setStroke(dpToPx(1), theme.deleteBorder)
                    }
                    background = bBg
                    setPadding(dpToPx(8), dpToPx(4), dpToPx(8), dpToPx(4))
                    setOnClickListener {
                        unpairDevice(dev.id)
                        renderDevicesTab(container, query, theme)
                    }
                }

                btnActions.addView(btnConnect)
                btnActions.addView(btnUnpair)

                row.addView(devIcon)
                row.addView(nameCol)
                row.addView(btnActions)
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

    private fun copyFileToClipboard(filePath: String) {
        try {
            val file = File(filePath)
            if (!file.exists()) {
                Toast.makeText(this, "File does not exist", Toast.LENGTH_SHORT).show()
                return
            }
            val uri = androidx.core.content.FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                file
            )
            val cm = getSystemService(CLIPBOARD_SERVICE) as? android.content.ClipboardManager
            val clip = android.content.ClipData.newUri(contentResolver, file.name, uri)
            cm?.setPrimaryClip(clip)
            Toast.makeText(this, "File copied: ${file.name}", Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Log.w(TAG, "File copy error: $e")
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

    private fun captureActiveClipboardIfNew() {
        try {
            val cm = getSystemService(CLIPBOARD_SERVICE) as? android.content.ClipboardManager ?: return
            val clip = cm.primaryClip ?: return
            if (clip.itemCount == 0) return
            val item = clip.getItemAt(0)
            val uri = item.uri
            val isImageMime = clip.description?.let { desc ->
                (0 until desc.mimeTypeCount).any { desc.getMimeType(it).startsWith("image/") }
            } ?: false

            if (uri != null && (isImageMime || uri.toString().contains("image"))) {
                try {
                    val input = contentResolver.openInputStream(uri)
                    val bytes = input?.readBytes()
                    input?.close()
                    if (bytes != null && bytes.isNotEmpty()) {
                        val md = java.security.MessageDigest.getInstance("SHA-256")
                        val hash = md.digest(bytes).joinToString("") { "%02x".format(it) }
                        val file = File(filesDir, "clipboard-images/$hash.png")
                        file.parentFile?.mkdirs()
                        if (!file.exists()) {
                            file.writeBytes(bytes)
                        }
                        insertClipDirectly(hash, "image", file.absolutePath)
                    }
                } catch (_: Exception) {}
            } else if (uri != null) {
                val path = uri.path ?: uri.toString()
                val md = java.security.MessageDigest.getInstance("SHA-256")
                val hash = md.digest(path.toByteArray()).joinToString("") { "%02x".format(it) }
                insertClipDirectly(hash, "fileURL", path)
            } else {
                val text = item.coerceToText(this)?.toString()?.trim() ?: ""
                if (text.isNotEmpty() && text.length <= 100_000) {
                    val md = java.security.MessageDigest.getInstance("SHA-256")
                    val hash = md.digest(text.toByteArray()).joinToString("") { "%02x".format(it) }
                    insertClipDirectly(hash, "text", text)
                }
            }
        } catch (_: Exception) {}
    }

    private fun insertClipDirectly(hash: String, type: String, value: String) {
        val db = getReadableDatabase() ?: return
        try {
            val cursor = db.rawQuery("SELECT content_hash FROM clipboard_history ORDER BY created_at DESC LIMIT 1", null)
            val latestHash = cursor.use { if (it.moveToFirst()) it.getString(0) else null }
            if (latestHash == hash) return

            val cv = android.content.ContentValues().apply {
                put("content_hash", hash)
                put("item_type", type)
                put("item_value", value)
                put("source_app", "Local Copy")
                put("created_at", System.currentTimeMillis())
            }
            db.insertWithOnConflict("clipboard_history", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
        } catch (_: Exception) {} finally {
            try { db.close() } catch (_: Exception) {}
        }
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
                "files" -> {
                    sql += " AND item_type IN ('fileURL', 'fileURLs')"
                }
                "text" -> {
                    sql += " AND item_type = 'text'"
                }
                else -> {
                    sql += " AND item_type IN ('text', 'image', 'fileURL', 'fileURLs')"
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
            notifySnippetChange()
        } catch (_: Exception) {} finally {
            try { db.close() } catch (_: Exception) {}
        }
    }

    private fun createSnippetFolder(title: String): String {
        val db = getReadableDatabase() ?: return ""
        return try {
            val id = UUID.randomUUID().toString()
            val now = System.currentTimeMillis()
            val cv = android.content.ContentValues().apply {
                put("id", id)
                put("title", title)
                put("is_enabled", 1)
                put("updated_at", now)
                put("sort_order", 0)
            }
            db.insertWithOnConflict("snippet_folders", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
            notifySnippetChange()
            id
        } catch (e: Exception) {
            Log.e(TAG, "Error creating folder: $e")
            ""
        } finally {
            try { db.close() } catch (_: Exception) {}
        }
    }

    private fun insertSnippet(folderId: String, title: String, content: String): Boolean {
        val db = getReadableDatabase() ?: return false
        return try {
            val id = UUID.randomUUID().toString()
            val now = System.currentTimeMillis()
            val cv = android.content.ContentValues().apply {
                put("id", id)
                put("folder_id", folderId)
                put("title", if (title.isBlank()) "Note" else title.trim())
                put("content", content.trim())
                put("updated_at", now)
                put("sort_order", 0)
            }
            db.insertWithOnConflict("snippets", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
            notifySnippetChange()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error inserting snippet: $e")
            false
        } finally {
            try { db.close() } catch (_: Exception) {}
        }
    }

    private fun updateSnippet(id: String, title: String, content: String): Boolean {
        val db = getReadableDatabase() ?: return false
        return try {
            val now = System.currentTimeMillis()
            val cv = android.content.ContentValues().apply {
                put("title", if (title.isBlank()) "Note" else title.trim())
                put("content", content.trim())
                put("updated_at", now)
            }
            val affected = db.update("snippets", cv, "id = ?", arrayOf(id))
            notifySnippetChange()
            affected > 0
        } catch (e: Exception) {
            Log.e(TAG, "Error updating snippet: $e")
            false
        } finally {
            try { db.close() } catch (_: Exception) {}
        }
    }

    private fun notifySnippetChange() {
        try {
            val engine = io.flutter.embedding.engine.FlutterEngineCache.getInstance().get(TechuboardApplication.ENGINE_ID)
            if (engine != null) {
                mainHandler.post {
                    try {
                        io.flutter.plugin.common.MethodChannel(
                            engine.dartExecutor.binaryMessenger,
                            TechuboardApplication.CLIPBOARD_CHANNEL
                        ).invokeMethod("reloadSnippets", null)
                    } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}
    }

    private fun fetchPairedDevices(): List<DeviceItem> {
        val result = mutableListOf<DeviceItem>()
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val seenIds = mutableSetOf<String>()

        val savedRaw = prefs.getString("flutter.techuboard.saved_devices.v1", null)
        if (savedRaw != null) {
            try {
                val arr = JSONArray(savedRaw)
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val pid = obj.optString("peerId", "")
                    if (pid.isNotEmpty() && !seenIds.contains(pid)) {
                        seenIds.add(pid)
                        val name = obj.optString("displayName", "Mac Device")
                        val isMac = name.contains("Mac", ignoreCase = true) || name.contains("Apple", ignoreCase = true)
                        val host = obj.optString("host", "")
                        val port = obj.optInt("port", 5566)
                        result.add(DeviceItem(pid, name, isMac, isConnected = true, pairedAt = if (host.isNotEmpty()) "$host:$port" else "Saved"))
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error parsing saved devices: $e")
            }
        }

        val raw = prefs.getString("flutter.techuboard.trusted_peers.v4", null)
        if (raw != null) {
            try {
                val json = JSONObject(raw)
                val keys = json.keys()
                while (keys.hasNext()) {
                    val peerId = keys.next()
                    if (!seenIds.contains(peerId)) {
                        seenIds.add(peerId)
                        val obj = json.getJSONObject(peerId)
                        val name = obj.optString("name", "Mac Device")
                        val isMac = name.contains("Mac", ignoreCase = true) || name.contains("Apple", ignoreCase = true)
                        val pairedAt = obj.optString("paired_at", "Recently")
                        result.add(DeviceItem(peerId, name, isMac, isConnected = true, pairedAt = pairedAt))
                    }
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
        try {
            val savedRaw = prefs.getString("flutter.techuboard.saved_devices.v1", null)
            if (savedRaw != null) {
                val arr = JSONArray(savedRaw)
                val newArr = JSONArray()
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    if (obj.optString("peerId") != peerId) {
                        newArr.put(obj)
                    }
                }
                prefs.edit().putString("flutter.techuboard.saved_devices.v1", newArr.toString()).apply()
            }
            val raw = prefs.getString("flutter.techuboard.trusted_peers.v4", null)
            if (raw != null) {
                val json = JSONObject(raw)
                json.remove(peerId)
                prefs.edit().putString("flutter.techuboard.trusted_peers.v4", json.toString()).apply()
            }
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
