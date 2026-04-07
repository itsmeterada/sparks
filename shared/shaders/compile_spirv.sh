#!/bin/bash
# Compile GLSL shaders to SPIR-V for Vulkan
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/../../android/app/src/main/assets/shaders"
mkdir -p "$OUTPUT_DIR"
echo "Compiling GLSL shaders to SPIR-V..."
glslangValidator -V "$SCRIPT_DIR/fullscreen.vert.glsl" -o "$OUTPUT_DIR/fullscreen.vert.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/sparks.frag.glsl" -o "$OUTPUT_DIR/sparks.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/cosmic.frag.glsl" -o "$OUTPUT_DIR/cosmic.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/starship.frag.glsl" -o "$OUTPUT_DIR/starship.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/clouds.frag.glsl" -o "$OUTPUT_DIR/clouds.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/seascape.frag.glsl" -o "$OUTPUT_DIR/seascape.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/rainforest.frag.glsl" -o "$OUTPUT_DIR/rainforest.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/plasma.frag.glsl" -o "$OUTPUT_DIR/plasma.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/grid.frag.glsl" -o "$OUTPUT_DIR/grid.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/interstellar.frag.glsl" -o "$OUTPUT_DIR/interstellar.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/mandelbulb.frag.glsl" -o "$OUTPUT_DIR/mandelbulb.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/fxaa.frag.glsl" -o "$OUTPUT_DIR/fxaa.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/cyberspace.frag.glsl" -o "$OUTPUT_DIR/cyberspace.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/primitives.frag.glsl" -o "$OUTPUT_DIR/primitives.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/fractal.frag.glsl" -o "$OUTPUT_DIR/fractal.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/palette.frag.glsl" -o "$OUTPUT_DIR/palette.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/octgrams.frag.glsl" -o "$OUTPUT_DIR/octgrams.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/voxellines.frag.glsl" -o "$OUTPUT_DIR/voxellines.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/mandelbulb2.frag.glsl" -o "$OUTPUT_DIR/mandelbulb2.frag.spv" || exit 1
glslangValidator -V "$SCRIPT_DIR/tunnel.frag.glsl" -o "$OUTPUT_DIR/tunnel.frag.spv" || exit 1
echo "All shaders compiled successfully."
ls -la "$OUTPUT_DIR"/*.spv
