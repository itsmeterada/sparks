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
