package com.sparks.demo

import android.content.Context
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView

class VulkanSurfaceView(context: Context) : SurfaceView(context), SurfaceHolder.Callback {

    private var renderThread: RenderThread? = null
    private var surfaceReady = false
    private var paused = false

    init {
        holder.addCallback(this)
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        surfaceReady = true
        nativeInit(holder.surface)
        startRenderThread()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        nativeResize(width, height)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        surfaceReady = false
        stopRenderThread()
        nativeDestroy()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!surfaceReady) return false

        // Pass pixel coordinates (Y flipped for Shadertoy convention)
        val pixelX = event.x
        val pixelY = height.toFloat() - event.y

        val action = when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> 0
            MotionEvent.ACTION_MOVE -> 1
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> 2
            else -> return false
        }

        nativeTouch(pixelX, pixelY, action)
        return true
    }

    fun toggleShader() {
        nativeToggleShader()
    }

    fun toggleMode() {
        nativeToggleMode()
    }

    fun onResume() {
        paused = false
        if (surfaceReady) {
            startRenderThread()
        }
    }

    fun onPause() {
        paused = true
        stopRenderThread()
    }

    fun onDestroy() {
        stopRenderThread()
        nativeShutdown()
    }

    private fun startRenderThread() {
        if (renderThread?.isRunning == true) return
        if (paused) return
        val thread = RenderThread()
        renderThread = thread
        thread.start()
    }

    private fun stopRenderThread() {
        renderThread?.let {
            it.isRunning = false
            try {
                it.join(2000)
            } catch (_: InterruptedException) {
            }
        }
        renderThread = null
    }

    private inner class RenderThread : Thread("SparksRenderThread") {
        @Volatile
        var isRunning = true

        override fun run() {
            while (isRunning && surfaceReady && !paused) {
                nativeRender()
            }
        }
    }

    private external fun nativeInit(surface: Surface)
    private external fun nativeRender()
    private external fun nativeDestroy()
    private external fun nativeTouch(x: Float, y: Float, action: Int)
    private external fun nativeToggleShader()
    private external fun nativeToggleMode()
    private external fun nativeResize(width: Int, height: Int)
    private external fun nativeShutdown()

    companion object {
        init {
            System.loadLibrary("sparks_native")
        }
    }
}
