# Sparks

[English](README_en.md)

フルスクリーンGPUシェーダーデモ — Shadertoy シェーダーをネイティブモバイル (Vulkan / Metal) に移植。画面タップでシェーダーを切り替え。

| シェーダー1: Sparks | シェーダー2: Cosmic |
|:---:|:---:|
| ![Sparks](./screenshot.png) | ![Cosmic](./screenshot2.png) |
| **シェーダー3: Starship** | **シェーダー4: Clouds** |
| ![Starship](./screenshot3.png) | ![Clouds](./screenshot4.png) |
| **シェーダー5: Seascape** | |
| ![Seascape](./screenshot5.png) | |

- **シェーダー1**: Jan Mróz (jaszunio15) 氏の [Sparks](https://www.shadertoy.com/view/4tXXzj) — レイヤードVoronoiパーティクルとプロシージャルスモークによる炎の火花。ライセンス: CC BY 3.0。
- **シェーダー2**: Nguyen2007 氏の [Cosmic](https://www.shadertoy.com/view/XXyGzh) — プロシージャルな宇宙的アブストラクトエフェクト。ライセンス: CC BY-NC-SA 3.0。
- **シェーダー3**: @XorDev 氏の [Starship](https://www.shadertoy.com/view/l3cfW4) — テクスチャベースのパーティクルトレイルによる宇宙船デブリエフェクト。ライセンス: CC BY-NC-SA 3.0。
- **シェーダー4**: Inigo Quilez 氏の [Clouds](https://www.shadertoy.com/view/XslGRr) — 3Dノイズによるボリュメトリック雲のレイマーチング。ライセンス: 教育目的のみ。
- **シェーダー5**: Alexander Alekseev (TDM) 氏の [Seascape](https://www.shadertoy.com/view/Ms2SD1) — プロシージャル海面のハイトマップレイマーチング。ライセンス: CC BY-NC-SA 3.0。

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
│   ├── sparks.frag.glsl       # シェーダー1 フラグメントシェーダー (Vulkan)
│   ├── cosmic.frag.glsl       # シェーダー2 フラグメントシェーダー (Vulkan)
│   ├── starship.frag.glsl     # シェーダー3 フラグメントシェーダー (Vulkan)
│   ├── clouds.frag.glsl       # シェーダー4 フラグメントシェーダー (Vulkan)
│   ├── seascape.frag.glsl     # シェーダー5 フラグメントシェーダー (Vulkan)
│   ├── sparks.metal           # Metal 頂点 + フラグメントシェーダー (全シェーダー)
│   └── compile_spirv.sh       # GLSL → SPIR-V コンパイルスクリプト
├── android/            # Android Studio プロジェクト (Vulkan)
└── ios/                # Xcode プロジェクト (Metal)
```

## 仕組み

各エフェクトはフルスクリーン三角形上の単一フラグメントシェーダーパスで動作します。ジオメトリもパーティクルバッファも不要 — 全ピクセルが毎フレームプロシージャルに計算されます。右上のボタンで5つのシェーダーを切り替えられます。ドラッグでカメラ/視点操作。

### シェーダー1: Sparks
- **Voronoiベースの火花パーティクル**: アニメーションするVoronoiセルのレイヤードグリッド、各セルにブルーム付きの光る火花
- **プロシージャルスモーク**: 方向性のあるレイヤードバリューノイズ、追加ノイズで有機的な穴を生成
- **温度カラーパレット**: 白 → 黄 → 橙 → 赤 の火花グラデーション
- **15パーティクルレイヤー**: サイズ/アルファ変調で擬似3D深度を表現

### シェーダー2: Cosmic
- **反復変換**: 19回の反復ループで複雑なフラクタル的パターンを生成
- **回転行列変形**: 各反復でUV座標を回転行列で変換し、有機的な動きを実現
- **トーンマッピング**: 非線形のカラー圧縮で宇宙的な色彩を表現

### シェーダー3: Starship
- **50パーティクルループ**: 各パーティクルが独立した軌跡とフラッシュ周波数を持つ
- **テクスチャノイズ**: `stars.jpg` テクスチャをサンプリングして雲状の奥行き感を生成
- **トレイルエフェクト**: 非対称スケーリングで長い尾を持つデブリパーティクルを表現

### シェーダー4: Clouds
- **ボリュメトリックレイマーチング**: fBMノイズで密度場を定義し、レイマーチングでボリュームレンダリング
- **3Dノイズテクスチャ**: 32x32x32の3Dテクスチャでハードウェア補間による滑らかなノイズ
- **LODレイマーチ**: 距離に応じてノイズのオクターブ数を減らし、パフォーマンスを最適化
- **タッチカメラ操作**: ドラッグで視点を回転（離すと位置を保持）

### シェーダー5: Seascape
- **ハイトマップレイマーチング**: 海面の高さ関数とレイの交差を二分法で求解
- **fBMオクターブ海波**: `sea_octave` を複数スケールで重ね合わせたリアルな波形
- **フレネル反射**: 視線角度に応じた空と水面色のブレンド
- **ドラッグで時間操作**: タッチ移動でカメラの進行時間を制御

Uniform は `iResolution` (vec2)、`iTime` (float)、`iMouse` (vec4)、`mode` (int)。シェーダー3/4はテクスチャも使用。

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

- シェーダー1: [Jan Mróz (jaszunio15)](https://www.shadertoy.com/user/jaszunio15) — CC BY 3.0
- シェーダー2: [Nguyen2007](https://www.shadertoy.com/view/XXyGzh) — CC BY-NC-SA 3.0
- シェーダー3: [@XorDev](https://www.shadertoy.com/view/l3cfW4) — CC BY-NC-SA 3.0
- シェーダー4: [Inigo Quilez](https://www.shadertoy.com/view/XslGRr) — 教育目的のみ（再配布不可）
- シェーダー5: [Alexander Alekseev (TDM)](https://www.shadertoy.com/view/Ms2SD1) — CC BY-NC-SA 3.0
