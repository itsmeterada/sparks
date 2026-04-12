# Sparks

[Japanese (日本語)](README.md)

Fullscreen GPU shader demo — Shadertoy shaders ported to native mobile (Vulkan / Metal). Tap the top-right button to switch shaders. 24 shaders total.

| Sparks | Cosmic |
|:---:|:---:|
| ![Sparks](./screenshots/screenshot.png) | ![Cosmic](./screenshots/screenshot2.png) |
| **Starship** | **Clouds** |
| ![Starship](./screenshots/screenshot3.png) | ![Clouds](./screenshots/screenshot4.png) |
| **Seascape** | **Rainforest** |
| ![Seascape](./screenshots/screenshot5.png) | ![Rainforest](./screenshots/screenshot6.png) |
| **Plasma Globe** | **Grid** |
| ![Plasma Globe](./screenshots/screenshot7.png) | ![Grid](./screenshots/screenshot8.png) |
| **Interstellar** | **Mandelbulb** |
| ![Interstellar](./screenshots/screenshot9.png) | ![Mandelbulb](./screenshots/screenshot10.png) |
| **Cyberspace** | **Tunnel** |
| ![Cyberspace](./screenshots/screenshot11.png) | ![Tunnel](./screenshots/screenshot12.png) |
| **Primitives** | **Fractal Pyramid** |
| ![Primitives](./screenshots/screenshot13.png) | ![Fractal Pyramid](./screenshots/screenshot14.png) |
| **Palette** | **Octgrams** |
| ![Palette](./screenshots/screenshot15.png) | ![Octgrams](./screenshots/screenshot16.png) |
| **Voxel Lines** | **Mandelbulb 2** |
| ![Voxel Lines](./screenshots/screenshot17.png) | ![Mandelbulb 2](./screenshots/screenshot18.png) |
| **Protean Clouds** | **Rocaille** |
| ![Protean Clouds](./screenshots/screenshot19.png) | ![Rocaille](./screenshots/screenshot20.png) |
| **HUD Rings** | **Flight HUD** |
| ![HUD Rings](./screenshots/screenshot21.png) | ![Flight HUD](./screenshots/screenshot22.png) |
| **Chrome Metaball** | **Shuto Highway** |
| ![Chrome Metaball](./screenshots/screenshot23.png) | ![Shuto Highway](./screenshots/screenshot24.png) |

## Supported Platforms

| Platform | GPU API | Language | Minimum Version |
|----------|---------|----------|-----------------|
| Android | Vulkan | Kotlin + C++/NDK | API 26 (Android 8.0) |
| iOS | Metal | Swift | iOS 15.0 |

## Project Structure

```
sparks/
├── shared/shaders/     # Shader sources (GLSL)
│   ├── fullscreen.vert.glsl   # Fullscreen triangle vertex shader
│   ├── sparks.frag.glsl       # Shader 1 fragment shader
│   ├── cosmic.frag.glsl       # Shader 2
│   ├── starship.frag.glsl     # Shader 3
│   ├── clouds.frag.glsl       # Shader 4
│   ├── seascape.frag.glsl     # Shader 5
│   ├── rainforest.frag.glsl   # Shader 6
│   ├── plasma.frag.glsl       # Shader 7
│   ├── grid.frag.glsl         # Shader 8
│   ├── interstellar.frag.glsl # Shader 9
│   ├── mandelbulb.frag.glsl   # Shader 10
│   ├── cyberspace.frag.glsl   # Shader 11
│   ├── tunnel.frag.glsl       # Shader 12
│   ├── primitives.frag.glsl   # Shader 13
│   ├── fractal.frag.glsl      # Shader 14
│   ├── palette.frag.glsl      # Shader 15
│   ├── octgrams.frag.glsl     # Shader 16
│   ├── voxellines.frag.glsl   # Shader 17
│   ├── mandelbulb2.frag.glsl  # Shader 18
│   ├── protean.frag.glsl      # Shader 19
│   ├── rocaille.frag.glsl     # Shader 20
│   ├── hudrings.frag.glsl     # Shader 21
│   ├── flighthud.frag.glsl    # Shader 22
│   ├── metalball.frag.glsl    # Shader 23
│   ├── shutohwy.frag.glsl    # Shader 24
│   ├── fxaa.frag.glsl         # FXAA post-process shader
│   └── compile_spirv.sh       # GLSL to SPIR-V compilation script
├── android/            # Android Studio project (Vulkan)
└── ios/                # Xcode project (Metal)
    └── Sparks/Shaders/
        ├── ShaderTypes.h          # Shared structs (VertexOut, Uniforms)
        ├── sparks.metal           # Shared vertex shader + Sparks fragment
        ├── cosmic.metal           # Cosmic (per-file -fno-fast-math)
        ├── starship.metal         # Starship
        ├── clouds.metal           # Clouds
        ├── seascape.metal         # Seascape
        ├── rainforest.metal       # Rainforest
        ├── plasma.metal           # Plasma Globe
        ├── grid.metal             # Grid
        ├── interstellar.metal     # Interstellar
        ├── mandelbulb.metal       # Mandelbulb
        ├── cyberspace.metal       # Cyberspace
        ├── tunnel.metal           # Tunnel (per-file -fno-fast-math)
        ├── fractal.metal          # Fractal Pyramid
        ├── mandelbulb2.metal      # Mandelbulb (evilryu)
        ├── octgrams.metal         # Octgrams
        ├── palette.metal          # Palette
        ├── primitives.metal       # Primitives
        ├── voxellines.metal       # Voxel Lines
        ├── protean.metal          # Protean Clouds
        ├── rocaille.metal         # Rocaille
        ├── hudrings.metal         # HUD Rings
        ├── flighthud.metal        # Flight HUD
        └── metalball.metal        # Chrome Metaball
```

## How It Works

Each effect runs as a single fragment shader pass on a fullscreen triangle. No geometry or particle buffers needed — every pixel is computed procedurally each frame. Drag to control camera/viewpoint.

### Controls (top-right)
| Button | Function |
|:---:|---|
| ◇ | Cycle through 24 shaders |
| ◎ | Toggle mode (Sparks: parallax / Rainforest: temporal reprojection / Mandelbulb: FXAA) |
| 1 / ½ | Half-resolution toggle (½ orange = render at half size + linear upscale) |

### Shader 1: Sparks
- **Voronoi-based spark particles**: Layered grid of animated Voronoi cells, each with a glowing bloom spark
- **Procedural smoke**: Directional layered value noise with organic holes
- **Temperature color palette**: White to yellow to orange to red gradient
- **15 particle layers**: Size/alpha modulation for pseudo-3D depth

### Shader 2: Cosmic
- **Iterative transforms**: 19-iteration loop generating complex fractal-like patterns
- **Rotation matrix warping**: UV coordinates rotated per iteration for organic motion
- **Tone mapping**: Nonlinear color compression for cosmic color palette

### Shader 3: Starship
- **50 particle loop**: Each particle with independent trajectory and flash frequency
- **Texture noise**: `stars.jpg` texture sampling for cloudy depth effect
- **Trail effect**: Asymmetric scaling for long-tailed debris particles

### Shader 4: Clouds
- **Volumetric raymarching**: fBM noise density field with volume rendering
- **3D noise texture**: 32x32x32 3D texture with hardware-interpolated smooth noise
- **LOD raymarching**: Reduces noise octaves with distance for performance
- **Touch camera control**: Drag to rotate viewpoint (holds position on release)

### Shader 5: Seascape
- **Heightmap raymarching**: Bisection method for ray-ocean surface intersection
- **fBM octave waves**: Multiple scales of `sea_octave` for realistic wave shapes
- **Fresnel reflection**: View-angle-dependent sky and water color blending
- **Drag time control**: Touch movement controls camera time progression

### Shader 6: Rainforest
- **fBM terrain**: 9-octave 2D noise for terrain height with analytical normals
- **Procedural trees**: Ellipsoids with noise distortion placed on a Voronoi grid
- **Volumetric clouds**: Cloud layer at y=900 raymarched with shadows and lighting
- **Camera animation**: Automatic movement over the terrain surface

### Shader 7: Plasma Globe
- **Volumetric raymarching**: 13 rays march through discharge patterns
- **Flow noise**: fBM-based dynamic noise for inner sphere illumination
- **Fresnel reflection**: Reflection and refraction on the sphere surface
- **Drag camera rotation**: Touch movement rotates the viewpoint

### Shader 8: Warped Extruded Skewed Grid
- **Skewed grid**: Two tile sizes arranged in pinwheel pattern on skewed coordinate system
- **Texture extrusion**: Texture luminance used as height map for block extrusion
- **Space warping**: Camera path + twist generates tunnel-like warped space
- **Glow effects**: Randomly lit blocks for demoscene-style atmosphere

### Shader 9: Interstellar
- **Star field**: Noise texture generates star positions and depth
- **Warp speed variation**: sin/cos-based speed changes for hyperspace feel
- **RGB color shift**: Red/green/blue separation by depth for stereoscopic effect

### Shader 10: Inside the Mandelbulb II
- **8th-power Mandelbulb SDF**: Raymarched power-8 Mandelbulb distance field
- **Refraction + Reflection**: Up to 5 bounces for light transmission inside the fractal
- **ACES tone mapping**: Cinematic color transform + sRGB output
- **FXAA post-process**: Toggle 2-pass FXAA anti-aliasing via mode button

### Shader 11: Cyberspace Data Warehouse
- **Hexagonal grid**: Hex cells converted to isometric 3-face tiles
- **Data spheres**: Animated glowing memory spheres on each tile
- **Blinking pixels**: Noise-based dynamic data display patterns

### Shader 12: Neon Tunnel
- **Winding tunnel**: Raymarched tunnel following a path function
- **Neon lights**: Red and blue spiral neon lines with volumetric glow
- **Fractal texture**: Repeating box patterns for wall decoration
- **Reflection marching**: Specular effects from surface reflections

### Shader 13: SDF Primitives
- **25+ SDF distance functions**: Sphere, box, torus, capsule, cone, octahedron, pyramid, etc.
- **Bounding box optimization**: Efficient raymarching acceleration
- **Soft shadows + AO**: Full lighting with checker floor

### Shader 14: Fractal Pyramid
- **Iterative rotation + abs folding**: 8 iterations generating fractal geometry
- **Volumetric color**: Distance-based palette accumulation for glow effect

### Shader 15: Palette
- **IQ cosine palette**: 4 fract iterations creating nested ring patterns
- **Distance-based glow**: pow(0.01/d, 1.2) for vivid emission

### Shader 16: Octgrams
- **Rotating box SDF**: Multiple box combinations forming octagram shapes
- **Mod-space repetition**: Infinite pattern with volumetric glow
- **Time-varying blue tones**: Dynamic atmosphere

### Shader 17: Voxel Lines
- **DDA voxel raycast**: Noise terrain voxelized and raycast
- **Wireframe + edge glow**: Voxel AO with glowing edge rendering
- **Color/mono toggle**: Periodic color mode switching

### Shader 18: Mandelbulb (evilryu)
- **Power-8 Mandelbulb SDF**: Overstepping-optimized raymarching
- **Soft shadows**: Auto-rotating camera + distance-based color mapping
- **Post-processing**: Gamma, contrast, saturation, vignette

### Shader 19: Protean Clouds
- **Deformed periodic grid**: Texture-free procedural volume noise
- **Dynamic step size**: Density-adaptive marching for performance
- **Saturation-preserving interpolation**: iLerp color blending

### Shader 20: Rocaille
- **Double-loop turbulence**: 9 layers × 9 sin deformations for complex patterns
- **Cosine coloring + tanh tone mapping**: Compact and beautiful effect

### Shader 21: HUD Rings
- **Seven layered ring SDFs**: Concentric rings spinning at different rates, stacked along z and raymarched
- **Seven-segment procedural font**: Digits drawn dynamically via mod-space grid + SDF composition
- **UI overlay suite**: Rectangles, triangles, graphs, arrows and side-lines composed into a mecha HUD
- **30-second looped animation**: `cubicInOut` easing cycles both camera angle and ring thickness

### Shader 22: Flight HUD
- **Radar display**: Rotating sweep line + polar-coordinate grid + numbered tick marks
- **Paper plane overlay**: Origami-style aircraft built from triangle SDF combinations
- **Four graph panels**: Bar graph, histogram, waveform, and dot plot
- **Multiple small UIs**: Rotating ring gauges, crosshair, skewed 7-segment digits

### Shader 23: Chrome Metaball
- **Metaball SDF**: Spherical harmonic deformation + smooth union with ground plane
- **PBR lighting**: GGX NDF + Smith-GGX Visibility + Schlick Fresnel physically-based BRDF
- **5-bounce reflections**: Extinction-based multi-reflection for chrome appearance
- **11-second loop animation**: Bounce, deformation, and camera orbit via smoothstep keyframes

### Shader 24: Shuto Highway 83
- **DDA grid city**: 3D DDA grid traversal with 4-split parametric buildings/traditional houses per cell
- **Highways**: Distance-function curved roads + road markings + LCD billboards + street lamps
- **PBR + shadows + AO**: Hosek sky probe + GGX specular + shadow ray + marched AO
- **7 auto-switching cameras**: Drive, spiral flight, rooftop walk, under-bridge, isometric, etc. (~130 sec)

Uniforms: `iResolution` (vec2), `iTime` (float), `iMouse` (vec4), `mode` (int). Shaders 3/4/7/8/9/17 also use textures.

## Build

### Android

1. Install [Vulkan SDK](https://vulkan.lunarg.com/) (needed for `glslangValidator`)
2. Compile shaders:
   ```bash
   cd shared/shaders
   bash compile_spirv.sh
   ```
3. Open `android/` in Android Studio
4. Build and deploy to a Vulkan-capable device

### iOS

1. Open `ios/Sparks.xcodeproj` in Xcode
2. Select a physical device as target
3. Build and run (Cmd+R)

## Credits

| # | Shader | Author | Description | License |
|---|--------|--------|-------------|---------|
| 1 | [Sparks](https://www.shadertoy.com/view/4tXXzj) | Jan Mróz (jaszunio15) | Voronoi particles + procedural smoke fire sparks | CC BY 3.0 |
| 2 | [Cosmic](https://www.shadertoy.com/view/XXyGzh) | Nguyen2007 | Iterative cosmic abstract effect | CC BY-NC-SA 3.0 |
| 3 | [Starship](https://www.shadertoy.com/view/l3cfW4) | @XorDev | Texture-based spaceship debris particle trails | CC BY-NC-SA 3.0 |
| 4 | [Clouds](https://www.shadertoy.com/view/XslGRr) | Inigo Quilez | Volumetric cloud raymarching with 3D noise | Educational only |
| 5 | [Seascape](https://www.shadertoy.com/view/Ms2SD1) | Alexander Alekseev (TDM) | fBM ocean wave heightmap raymarching | CC BY-NC-SA 3.0 |
| 6 | [Rainforest](https://www.shadertoy.com/view/4ttSWf) | Inigo Quilez | Procedural rainforest with fBM terrain, trees & clouds | Educational only |
| 7 | [Plasma Globe](https://www.shadertoy.com/view/XsjXRm) | nimitz (@stormoid) | Volumetric raymarched plasma globe | CC BY-NC-SA 3.0 |
| 8 | [Grid](https://www.shadertoy.com/view/wtfBDf) | Shane | Demoscene-style skewed grid extrusion tunnel | CC BY-NC-SA 3.0 |
| 9 | [Interstellar](https://www.shadertoy.com/view/Xdl3D2) | Hazel Quantock | Noise-texture star warp effect | CC0 |
| 10 | [Mandelbulb](https://www.shadertoy.com/view/mtScRc) | mrange | 8th-power Mandelbulb fractal interior + FXAA | CC0 |
| 11 | [Cyberspace](https://www.shadertoy.com/view/NlK3Wt) | bitless | Isometric hex-grid cyberspace data warehouse | CC BY-NC-SA 3.0 |
| 12 | [Neon Tunnel](https://www.shadertoy.com/view/scS3Wm) | — | Raymarched neon tunnel with reflections | CC BY-NC-SA 3.0 |
| 13 | [Primitives](https://www.shadertoy.com/view/Xds3zN) | Inigo Quilez | 25+ SDF distance function showcase | MIT |
| 14 | [Fractal Pyramid](https://www.shadertoy.com/view/tsXBzS) | — | Iterative rotation + abs folding fractal | CC BY-NC-SA 3.0 |
| 15 | [Palette](https://www.shadertoy.com/view/mtyGWy) | — | IQ cosine palette fractal rings | CC BY-NC-SA 3.0 |
| 16 | [Octgrams](https://www.shadertoy.com/view/tlVGDt) | — | Rotating box SDF octagram pattern | CC BY-NC-SA 3.0 |
| 17 | [Voxel Lines](https://www.shadertoy.com/view/4dfGzs) | Inigo Quilez | DDA voxel raycast with wireframe glow | Educational only |
| 18 | [Mandelbulb](https://www.shadertoy.com/view/MdXSWn) | evilryu | Power-8 Mandelbulb with overstepping optimization | CC BY-NC-SA 3.0 |
| 19 | [Protean Clouds](https://www.shadertoy.com/view/3l23Rh) | nimitz (@stormoid) | Deformed periodic grid procedural clouds | CC BY-NC-SA 3.0 |
| 20 | [Rocaille](https://www.shadertoy.com/view/WXyczK) | @XorDev | Multi-layer turbulence ornamental pattern | CC BY-NC-SA 3.0 |
| 21 | [HUD Rings](https://www.shadertoy.com/view/Dsf3WH) | kishimisu | Spinning rings + 7-seg digits + HUD overlays mecha UI raymarching | CC BY-NC-SA 3.0 |
| 22 | [Flight HUD](https://www.shadertoy.com/view/Dl2XRz) | kishimisu | Radar + paper plane + graph panels flight-style 2D HUD | CC BY-NC-SA 3.0 |
| 23 | [Chrome Metaball](https://www.shadertoy.com/view/7dtSDf) | — | PBR + multi-reflection chrome metaball | CC BY-NC-SA 3.0 |
| 24 | [Shuto Highway 83](https://www.shadertoy.com/view/XdyyDV) | Jerome Liard | DDA city + highways + PBR + 7-camera full city renderer | CC BY-NC-SA 3.0 |
