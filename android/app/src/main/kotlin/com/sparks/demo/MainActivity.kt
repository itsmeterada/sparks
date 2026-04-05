package com.sparks.demo

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView

class MainActivity : Activity() {

    private lateinit var vulkanSurfaceView: VulkanSurfaceView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val root = FrameLayout(this)
        vulkanSurfaceView = VulkanSurfaceView(this)
        root.addView(vulkanSurfaceView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Subtle shader switch button (top-right)
        val sizePx = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 36f, resources.displayMetrics).toInt()
        val marginPx = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 16f, resources.displayMetrics).toInt()

        val button = TextView(this).apply {
            text = "\u25C7" // diamond
            setTextColor(Color.argb(77, 255, 255, 255)) // 30% white
            textSize = 16f
            gravity = Gravity.CENTER
            val bg = GradientDrawable()
            bg.setColor(Color.argb(20, 255, 255, 255)) // 8% white
            bg.cornerRadius = sizePx / 2f
            background = bg
            setOnClickListener { vulkanSurfaceView.toggleShader() }
        }
        val lp = FrameLayout.LayoutParams(sizePx, sizePx).apply {
            gravity = Gravity.TOP or Gravity.END
            topMargin = marginPx + getStatusBarHeight()
            rightMargin = marginPx
        }
        root.addView(button, lp)

        setContentView(root)
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
