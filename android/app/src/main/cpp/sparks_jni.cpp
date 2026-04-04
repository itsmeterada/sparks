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

extern "C" {

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeInit(JNIEnv* env, jobject /* thiz */, jobject surface) {
    if (gEngine != nullptr) {
        delete gEngine;
        gEngine = nullptr;
    }
    if (gWindow != nullptr) {
        ANativeWindow_release(gWindow);
        gWindow = nullptr;
    }

    gWindow = ANativeWindow_fromSurface(env, surface);
    if (gWindow == nullptr) {
        LOGE("Failed to get ANativeWindow from Surface");
        return;
    }

    // Get AAssetManager from the app context
    jclass surfaceViewClass = env->GetObjectClass(/* thiz */ surface);
    // We need the asset manager from the context. Get it via the activity.
    // Since we receive a Surface object, we need to get the AssetManager differently.
    // We'll pass nullptr and load shaders from a fallback embedded approach,
    // but the proper way is to get it from the Context.
    // Let's get the AssetManager through the Android context.

    // Get the context from the calling class
    jclass contextClass = env->FindClass("android/app/ActivityThread");
    jmethodID currentAppMethod = env->GetStaticMethodID(contextClass, "currentApplication", "()Landroid/app/Application;");
    jobject appContext = env->CallStaticObjectMethod(contextClass, currentAppMethod);

    AAssetManager* assetManager = nullptr;
    if (appContext != nullptr) {
        jclass contextCls = env->FindClass("android/content/Context");
        jmethodID getAssetsMethod = env->GetMethodID(contextCls, "getAssets", "()Landroid/content/res/AssetManager;");
        jobject jAssetManager = env->CallObjectMethod(appContext, getAssetsMethod);
        if (jAssetManager != nullptr) {
            assetManager = AAssetManager_fromJava(env, jAssetManager);
        }
    }

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
Java_com_sparks_demo_VulkanSurfaceView_nativeRender(JNIEnv* /* env */, jobject /* thiz */) {
    if (gEngine != nullptr) {
        gEngine->render();
    }
}

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeDestroy(JNIEnv* /* env */, jobject /* thiz */) {
    if (gEngine != nullptr) {
        delete gEngine;
        gEngine = nullptr;
    }
    if (gWindow != nullptr) {
        ANativeWindow_release(gWindow);
        gWindow = nullptr;
    }
    LOGI("Vulkan engine destroyed");
}

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeTouch(JNIEnv* /* env */, jobject /* thiz */,
                                                    jfloat x, jfloat y, jint action) {
    // Touch input not used in fullscreen shader mode
    (void)x; (void)y; (void)action;
}

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeResize(JNIEnv* /* env */, jobject /* thiz */,
                                                     jint width, jint height) {
    if (gEngine != nullptr) {
        gEngine->onResize(static_cast<uint32_t>(width), static_cast<uint32_t>(height));
    }
}

} // extern "C"
