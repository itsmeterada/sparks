#include <jni.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <android/log.h>
#include <android/asset_manager.h>
#include <android/asset_manager_jni.h>

#include "vulkan_engine.h"

#define LOG_TAG "SparksJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static VulkanEngine* gEngine = nullptr;
static ANativeWindow* gWindow = nullptr;

static AAssetManager* getAssetManager(JNIEnv* env) {
    jclass contextClass = env->FindClass("android/app/ActivityThread");
    jmethodID currentAppMethod = env->GetStaticMethodID(contextClass, "currentApplication",
                                                         "()Landroid/app/Application;");
    jobject appContext = env->CallStaticObjectMethod(contextClass, currentAppMethod);
    if (appContext == nullptr) return nullptr;

    jclass contextCls = env->FindClass("android/content/Context");
    jmethodID getAssetsMethod = env->GetMethodID(contextCls, "getAssets",
                                                  "()Landroid/content/res/AssetManager;");
    jobject jAssetManager = env->CallObjectMethod(appContext, getAssetsMethod);
    if (jAssetManager == nullptr) return nullptr;

    return AAssetManager_fromJava(env, jAssetManager);
}

extern "C" {

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeInit(JNIEnv* env, jobject, jobject surface) {
    ANativeWindow* newWindow = ANativeWindow_fromSurface(env, surface);
    if (newWindow == nullptr) {
        LOGE("Failed to get ANativeWindow from Surface");
        return;
    }

    if (gWindow != nullptr) {
        ANativeWindow_release(gWindow);
    }
    gWindow = newWindow;

    // If engine already exists, just reinit the surface (fast path for rotation)
    if (gEngine != nullptr && gEngine->isInitialized()) {
        if (gEngine->reinitSurface(gWindow)) {
            LOGI("Surface reinitialized (engine reused)");
            return;
        }
        // reinit failed, fall through to full init
        delete gEngine;
        gEngine = nullptr;
    }

    AAssetManager* assetManager = getAssetManager(env);

    gEngine = new VulkanEngine();
    if (!gEngine->init(gWindow, assetManager)) {
        LOGE("Failed to initialize Vulkan engine");
        delete gEngine;
        gEngine = nullptr;
    } else {
        LOGI("Vulkan engine initialized successfully");
    }
}

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeRender(JNIEnv*, jobject) {
    if (gEngine != nullptr) {
        gEngine->render();
    }
}

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeDestroy(JNIEnv*, jobject) {
    if (gEngine != nullptr) {
        // Just pause rendering — don't release the window or engine.
        // nativeInit will be called again with a new surface shortly.
        gEngine->pause();
        LOGI("Rendering paused (engine kept alive)");
    }
}

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeTouch(JNIEnv*, jobject, jfloat x, jfloat y, jint action) {
    (void)x; (void)y;
    // Toggle shader on tap (ACTION_DOWN = 0)
    if (action == 0 && gEngine != nullptr) {
        gEngine->toggleShader();
    }
}

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeResize(JNIEnv*, jobject, jint width, jint height) {
    if (gEngine != nullptr) {
        gEngine->onResize(static_cast<uint32_t>(width), static_cast<uint32_t>(height));
    }
}

// Called when the activity is truly finishing
JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeShutdown(JNIEnv*, jobject) {
    if (gEngine != nullptr) {
        delete gEngine;
        gEngine = nullptr;
    }
    if (gWindow != nullptr) {
        ANativeWindow_release(gWindow);
        gWindow = nullptr;
    }
    LOGI("Vulkan engine fully destroyed");
}

} // extern "C"
