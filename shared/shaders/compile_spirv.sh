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
echo "All shaders compiled successfully."
ls -la "$OUTPUT_DIR"/*.spv
