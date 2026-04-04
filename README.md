# Sparks

Fullscreen GPU shader demo — animated fire sparks with layered Voronoi particles and procedural smoke.

Ported from the original [Shadertoy shader](https://www.shadertoy.com/view/4tXXzj) by Jan Mróz (jaszunio15), licensed under CC BY 3.0.

## Platforms

| Platform | GPU API | Language | Min Version |
|----------|---------|----------|-------------|
| Android  | Vulkan  | Kotlin + C++/NDK | API 26 (Android 8.0) |
| iOS      | Metal   | Swift    | iOS 15.0 |

## Project Structure

```
sparks/
├── shared/shaders/     # Canonical shader sources (GLSL + MSL)
│   ├── fullscreen.vert.glsl   # Fullscreen triangle vertex shader
│   ├── sparks.frag.glsl       # Main effect fragment shader (Vulkan)
│   ├── sparks.metal           # Metal vertex + fragment shader
│   └── compile_spirv.sh       # GLSL → SPIR-V compilation script
├── android/            # Android Studio project (Vulkan)
└── ios/                # Xcode project (Metal)
```

## How It Works

The entire effect runs in a single fragment shader pass over a fullscreen triangle. No geometry, no particle buffers — every pixel is computed procedurally each frame.

- **Voronoi-based spark particles**: Layered grids of animated Voronoi cells, each containing a glowing spark with bloom
- **Procedural smoke**: Layered value noise with directional movement, cut by additional noise for organic holes
- **Temperature color palette**: White → yellow → orange → red spark gradient
- **Vignette**: Darkens edges for cinematic framing
- **15 particle layers** composited with size/alpha modulation for pseudo-3D depth

Uniforms: `iResolution` (vec2) and `iTime` (float) — that's all the shader needs.

## Build

### Android

1. Install [Vulkan SDK](https://vulkan.lunarg.com/) (for `glslangValidator`)
2. Compile shaders:
   ```bash
   cd shared/shaders
   bash compile_spirv.sh
   ```
3. Open `android/` in Android Studio
4. Build and deploy to a physical device with Vulkan support

### iOS

1. Open `ios/Sparks.xcodeproj` in Xcode
2. Select a physical device target
3. Build and run (Cmd+R)

## Credits

- Original shader: [Jan Mróz (jaszunio15)](https://www.shadertoy.com/user/jaszunio15) — CC BY 3.0
