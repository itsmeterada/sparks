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
    if (gEngine != nullptr) {
        gEngine->onTouch(x, y, action);
    }
}

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeToggleShader(JNIEnv*, jobject) {
    if (gEngine != nullptr) {
        gEngine->toggleShader();
    }
}

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativePrevShader(JNIEnv*, jobject) {
    if (gEngine != nullptr) {
        gEngine->prevShader();
    }
}

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeToggleMode(JNIEnv*, jobject) {
    if (gEngine != nullptr) {
        gEngine->toggleMode();
    }
}

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeToggleHalfRes(JNIEnv*, jobject) {
    if (gEngine != nullptr) {
        gEngine->toggleHalfRes();
    }
}

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeResize(JNIEnv*, jobject, jint width, jint height) {
    if (gEngine != nullptr) {
        gEngine->onResize(static_cast<uint32_t>(width), static_cast<uint32_t>(height));
    }
}

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeStartBenchmark(JNIEnv*, jobject, jint modeKind, jint shaderIndex) {
    if (gEngine == nullptr) return;
    bench::Mode m;
    m.kind = (modeKind == 0) ? bench::Mode::Single : bench::Mode::All;
    m.singleIndex = shaderIndex;
    gEngine->startBenchmark(m);
}

JNIEXPORT void JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeAbortBenchmark(JNIEnv*, jobject) {
    if (gEngine != nullptr) gEngine->abortBenchmark();
}

JNIEXPORT jboolean JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeIsBenchmarkRunning(JNIEnv*, jobject) {
    return (gEngine != nullptr && gEngine->isBenchmarkRunning()) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeIsBenchmarkDone(JNIEnv*, jobject) {
    return (gEngine != nullptr && gEngine->isBenchmarkDone()) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeGetBenchmarkStatus(JNIEnv* env, jobject) {
    if (gEngine == nullptr) return env->NewStringUTF("");
    std::string s = gEngine->getBenchmarkStatus();
    return env->NewStringUTF(s.c_str());
}

JNIEXPORT jstring JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeTakeBenchmarkReport(JNIEnv* env, jobject,
        jstring osVersion, jstring model, jstring thermalStart, jstring thermalEnd, jstring timestamp) {
    if (gEngine == nullptr) return env->NewStringUTF("{}");
    auto toStd = [env](jstring js) -> std::string {
        if (js == nullptr) return {};
        const char* c = env->GetStringUTFChars(js, nullptr);
        std::string s = c ? c : "";
        if (c) env->ReleaseStringUTFChars(js, c);
        return s;
    };
    std::string json = gEngine->getBenchmarkReportJson(
        toStd(osVersion), toStd(model), toStd(thermalStart), toStd(thermalEnd), toStd(timestamp));
    gEngine->finishBenchmarkAndRestore();
    return env->NewStringUTF(json.c_str());
}

JNIEXPORT jint JNICALL
Java_com_sparks_demo_VulkanSurfaceView_nativeCurrentShader(JNIEnv*, jobject) {
    return (gEngine != nullptr) ? (jint)gEngine->currentShaderIndex() : 0;
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
