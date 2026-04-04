# Sparks

フルスクリーンGPUシェーダーデモ — レイヤードVoronoiパーティクルとプロシージャルスモークによる炎の火花アニメーション。

Jan Mróz (jaszunio15) 氏の [Shadertoy シェーダー](https://www.shadertoy.com/view/4tXXzj) をネイティブモバイルに移植。ライセンス: CC BY 3.0。

[English version](README_en.md)

## 対応プラットフォーム

| プラットフォーム | GPU API | 言語 | 最小バージョン |
|-----------------|---------|------|---------------|
| Android | Vulkan | Kotlin + C++/NDK | API 26 (Android 8.0) |
| iOS | Metal | Swift | iOS 15.0 |

## プロジェクト構成

```
sparks/
├── shared/shaders/     # シェーダーソース (GLSL + MSL)
│   ├── fullscreen.vert.glsl   # フルスクリーン三角形 頂点シェーダー
│   ├── sparks.frag.glsl       # メインエフェクト フラグメントシェーダー (Vulkan)
│   ├── sparks.metal           # Metal 頂点 + フラグメントシェーダー
│   └── compile_spirv.sh       # GLSL → SPIR-V コンパイルスクリプト
├── android/            # Android Studio プロジェクト (Vulkan)
└── ios/                # Xcode プロジェクト (Metal)
```

## 仕組み

エフェクト全体がフルスクリーン三角形上の単一フラグメントシェーダーパスで動作します。ジオメトリもパーティクルバッファも不要 — 全ピクセルが毎フレームプロシージャルに計算されます。

- **Voronoiベースの火花パーティクル**: アニメーションするVoronoiセルのレイヤードグリッド、各セルにブルーム付きの光る火花
- **プロシージャルスモーク**: 方向性のあるレイヤードバリューノイズ、追加ノイズで有機的な穴を生成
- **温度カラーパレット**: 白 → 黄 → 橙 → 赤 の火花グラデーション
- **ビネット**: エッジを暗くして映画的なフレーミング
- **15パーティクルレイヤー**: サイズ/アルファ変調で擬似3D深度を表現

Uniform は `iResolution` (vec2) と `iTime` (float) のみ。

## ビルド

### Android

1. [Vulkan SDK](https://vulkan.lunarg.com/) をインストール（`glslangValidator` に必要）
2. シェーダーをコンパイル:
   ```bash
   cd shared/shaders
   bash compile_spirv.sh
   ```
3. `android/` を Android Studio で開く
4. Vulkan対応の実機にビルド・デプロイ

### iOS

1. `ios/Sparks.xcodeproj` を Xcode で開く
2. 実機をターゲットに選択
3. ビルド・実行 (Cmd+R)

## クレジット

- 元シェーダー: [Jan Mróz (jaszunio15)](https://www.shadertoy.com/user/jaszunio15) — CC BY 3.0
