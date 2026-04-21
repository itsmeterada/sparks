package com.sparks.demo

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.Toast
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class MainActivity : Activity() {

    private lateinit var vulkanSurfaceView: VulkanSurfaceView
    private val shaderButtons: MutableList<View> = mutableListOf()
    private lateinit var benchOverlay: TextView
    private lateinit var benchButton: TextView
    private val uiHandler = Handler(Looper.getMainLooper())
    private var benchPollRunnable: Runnable? = null
    private var benchThermalStart: String = "unknown"
    private var benchStartedAtIso: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val root = FrameLayout(this)
        vulkanSurfaceView = VulkanSurfaceView(this)
        root.addView(vulkanSurfaceView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Shader navigation buttons (top-right, vertical column)
        val sizePx = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 36f, resources.displayMetrics).toInt()
        val marginPx = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 16f, resources.displayMetrics).toInt()
        val topOffset = marginPx + getStatusBarHeight()
        val gap = marginPx / 2

        fun makeButton(label: String, onClick: () -> Unit): TextView {
            return TextView(this).apply {
                text = label
                setTextColor(Color.argb(77, 255, 255, 255))
                textSize = 16f
                gravity = Gravity.CENTER
                val bg = GradientDrawable()
                bg.setColor(Color.argb(20, 255, 255, 255))
                bg.cornerRadius = sizePx / 2f
                background = bg
                setOnClickListener { onClick() }
            }
        }

        // Next shader (right arrow, top)
        val nextButton = makeButton("\u25B7") { vulkanSurfaceView.toggleShader() }
        root.addView(nextButton, FrameLayout.LayoutParams(sizePx, sizePx).apply {
            gravity = Gravity.TOP or Gravity.END
            topMargin = topOffset
            rightMargin = marginPx
        })

        // Previous shader (left arrow)
        val prevButton = makeButton("\u25C1") { vulkanSurfaceView.prevShader() }
        root.addView(prevButton, FrameLayout.LayoutParams(sizePx, sizePx).apply {
            gravity = Gravity.TOP or Gravity.END
            topMargin = topOffset + sizePx + gap
            rightMargin = marginPx
        })

        // Mode toggle button (below shader buttons)
        val modeButton = makeButton("\u25CE") { vulkanSurfaceView.toggleMode() }
        root.addView(modeButton, FrameLayout.LayoutParams(sizePx, sizePx).apply {
            gravity = Gravity.TOP or Gravity.END
            topMargin = topOffset + (sizePx + gap) * 2
            rightMargin = marginPx
        })

        // Half-res toggle button (below mode button)
        val halfResButton = TextView(this).apply {
            text = "\u00BD" // ½
            setTextColor(Color.argb(77, 255, 255, 255))
            textSize = 16f
            gravity = Gravity.CENTER
            val bg = GradientDrawable()
            bg.setColor(Color.argb(20, 255, 255, 255))
            bg.cornerRadius = sizePx / 2f
            background = bg
            var halfResOn = false
            setOnClickListener {
                vulkanSurfaceView.toggleHalfRes()
                halfResOn = !halfResOn
                text = if (halfResOn) "\u00BD" else "1"
                setTextColor(if (halfResOn) Color.argb(200, 255, 180, 80) else Color.argb(77, 255, 255, 255))
                (background as GradientDrawable).setColor(if (halfResOn) Color.argb(60, 255, 180, 80) else Color.argb(20, 255, 255, 255))
            }
            text = "1" // initial state: full resolution
        }
        val hlp = FrameLayout.LayoutParams(sizePx, sizePx).apply {
            gravity = Gravity.TOP or Gravity.END
            topMargin = topOffset + (sizePx + gap) * 3
            rightMargin = marginPx
        }
        root.addView(halfResButton, hlp)

        // Benchmark button (below half-res)
        benchButton = TextView(this).apply {
            text = "BM"
            setTextColor(Color.argb(77, 255, 255, 255))
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            val bg = GradientDrawable()
            bg.setColor(Color.argb(20, 255, 255, 255))
            bg.cornerRadius = sizePx / 2f
            background = bg
            setOnClickListener { showBenchmarkMenu() }
        }
        root.addView(benchButton, FrameLayout.LayoutParams(sizePx, sizePx).apply {
            gravity = Gravity.TOP or Gravity.END
            topMargin = topOffset + (sizePx + gap) * 4
            rightMargin = marginPx
        })

        shaderButtons.addAll(listOf(nextButton, prevButton, modeButton, halfResButton))

        // Benchmark progress overlay (top center, hidden until bench runs)
        benchOverlay = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 14f
            typeface = Typeface.MONOSPACE
            setPadding(24, 12, 24, 12)
            gravity = Gravity.CENTER
            val bg = GradientDrawable()
            bg.setColor(Color.argb(140, 0, 0, 0))
            bg.cornerRadius = 20f
            background = bg
            visibility = View.GONE
        }
        root.addView(benchOverlay, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = topOffset
        })

        setContentView(root)
    }

    // MARK: Benchmark

    private fun showBenchmarkMenu() {
        if (vulkanSurfaceView.isBenchmarkRunning()) {
            AlertDialog.Builder(this)
                .setTitle("Benchmark running")
                .setMessage("Stop the current benchmark?")
                .setPositiveButton("Stop") { _, _ -> abortBenchmark() }
                .setNegativeButton("Continue", null)
                .show()
            return
        }
        val items = arrayOf("Current shader", "All shaders")
        AlertDialog.Builder(this)
            .setTitle("Benchmark")
            .setItems(items) { _, which ->
                when (which) {
                    0 -> startBenchmark(modeKind = 0, shaderIndex = vulkanSurfaceView.currentShaderIndex())
                    1 -> startBenchmark(modeKind = 1, shaderIndex = -1)
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun startBenchmark(modeKind: Int, shaderIndex: Int) {
        benchThermalStart = readThermalState()
        benchStartedAtIso = nowIsoUtc()
        vulkanSurfaceView.startBenchmark(modeKind, shaderIndex)
        benchOverlay.visibility = View.VISIBLE
        setShaderButtonsEnabled(false)
        val r = object : Runnable {
            override fun run() {
                benchOverlay.text = vulkanSurfaceView.benchmarkStatus()
                if (vulkanSurfaceView.isBenchmarkDone()) {
                    finishBenchmarkAndShowResults()
                } else if (vulkanSurfaceView.isBenchmarkRunning()) {
                    uiHandler.postDelayed(this, 200)
                }
            }
        }
        benchPollRunnable = r
        uiHandler.post(r)
    }

    private fun abortBenchmark() {
        vulkanSurfaceView.abortBenchmark()
        stopBenchmarkUI()
    }

    private fun stopBenchmarkUI() {
        benchPollRunnable?.let { uiHandler.removeCallbacks(it) }
        benchPollRunnable = null
        benchOverlay.visibility = View.GONE
        setShaderButtonsEnabled(true)
    }

    private fun setShaderButtonsEnabled(enabled: Boolean) {
        for (b in shaderButtons) {
            b.isEnabled = enabled
            b.alpha = if (enabled) 1f else 0.3f
        }
    }

    private fun finishBenchmarkAndShowResults() {
        val thermalEnd = readThermalState()
        val osVersion = "Android ${Build.VERSION.RELEASE}"
        val model = "${Build.MANUFACTURER} ${Build.MODEL}"
        val json = vulkanSurfaceView.takeBenchmarkReport(
            osVersion, model, benchThermalStart, thermalEnd, benchStartedAtIso
        )
        stopBenchmarkUI()
        val savedPath = saveBenchmarkJson(json)
        val summary = formatSummary(json) + if (savedPath != null) "\n\nSaved: $savedPath" else ""
        AlertDialog.Builder(this)
            .setTitle("Benchmark complete")
            .setMessage(summary)
            .setPositiveButton("OK", null)
            .show()
    }

    private fun saveBenchmarkJson(json: String): String? {
        return try {
            val dir = getExternalFilesDir(null) ?: filesDir
            val fmt = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US)
            val file = File(dir, "benchmark-${fmt.format(Date())}.json")
            file.writeText(json)
            file.absolutePath
        } catch (t: Throwable) {
            Log.e("Sparks", "saveBenchmarkJson failed", t)
            Toast.makeText(this, "Save failed: ${t.message}", Toast.LENGTH_LONG).show()
            null
        }
    }

    private fun formatSummary(json: String): String {
        val sb = StringBuilder()
        try {
            val obj = org.json.JSONObject(json)
            val score = obj.optDouble("overallScore", 0.0)
            val thermalStart = obj.optString("thermalStateStart", "?")
            val thermalEnd = obj.optString("thermalStateEnd", "?")
            sb.append(String.format(Locale.US, "Overall score: %.0f\n", score))
            sb.append("Thermal: $thermalStart → $thermalEnd\n\n")
            val shaders = obj.optJSONArray("shaders")
            if (shaders != null) {
                for (i in 0 until shaders.length()) {
                    val s = shaders.getJSONObject(i)
                    val name = s.optString("name", "?")
                    if (s.optBoolean("skipped", false)) {
                        sb.append("• $name: skipped\n")
                    } else {
                        val avg = s.optDouble("avgFps", 0.0)
                        val low = s.optDouble("onePctLowFps", 0.0)
                        val p99 = s.optDouble("p99FrameMs", 0.0)
                        sb.append(String.format(Locale.US, "• %s: %.1f fps (1%% low %.1f, p99 %.1fms)\n",
                            name, avg, low, p99))
                    }
                }
            }
        } catch (t: Throwable) {
            sb.append("(failed to parse report: ${t.message})")
        }
        return sb.toString()
    }

    private fun readThermalState(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "unknown"
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return "unknown"
        return when (pm.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> "nominal"
            PowerManager.THERMAL_STATUS_LIGHT -> "light"
            PowerManager.THERMAL_STATUS_MODERATE -> "moderate"
            PowerManager.THERMAL_STATUS_SEVERE -> "severe"
            PowerManager.THERMAL_STATUS_CRITICAL -> "critical"
            PowerManager.THERMAL_STATUS_EMERGENCY -> "emergency"
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "shutdown"
            else -> "unknown"
        }
    }

    private fun nowIsoUtc(): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(Date())
    }

    private fun getStatusBarHeight(): Int {
        val resId = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (resId > 0) resources.getDimensionPixelSize(resId) else 0
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    override fun onResume() {
        super.onResume()
        vulkanSurfaceView.onResume()
    }

    override fun onPause() {
        super.onPause()
        vulkanSurfaceView.onPause()
    }

    override fun onDestroy() {
        vulkanSurfaceView.onDestroy()
        super.onDestroy()
    }

    private fun hideSystemBars() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let { controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                )
        }
    }
}
