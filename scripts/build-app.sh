#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
fallback_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
cache_root="${project_dir}/.build/tool-cache"
app_dir="${project_dir}/Mail.app"
icon_raster_source="${project_dir}/AppResources/KeyboardMailIconChrome.png"
icon_source="${project_dir}/AppResources/KeyboardMailIcon.svg"
icon_png="${project_dir}/.build/KeyboardMailIcon-1024.png"
icon_renderer_source="${project_dir}/scripts/render-icon.swift"
icon_renderer="${project_dir}/.build/render-icon"
icon_embedder_source="${project_dir}/scripts/embed-raster-svg.swift"
icon_embedder="${project_dir}/.build/embed-raster-svg"
icon_packager_source="${project_dir}/scripts/package-icns.swift"
icon_packager="${project_dir}/.build/package-icns"
iconset_dir="${project_dir}/.build/KeyboardMailIcon.iconset"
icon_output="${project_dir}/AppResources/KeyboardMailIcon.icns"
titlebar_output="${project_dir}/AppResources/KeyboardMailTitlebar.png"

if ! swiftc -sdk "${sdk_path}" -typecheck - <<< 'import SwiftUI; struct BuildProbe: View { @State var flag = false; var body: some View { Text("Probe") } }' >/dev/null 2>&1 && [[ -d "${fallback_sdk}" ]]; then
    sdk_path="${fallback_sdk}"
fi

mkdir -p "${cache_root}/clang" "${cache_root}/swift" "${cache_root}/swiftpm" "${app_dir}/Contents/MacOS" "${app_dir}/Contents/Resources"

if [[ ! -x "${icon_embedder}" || "${icon_embedder_source}" -nt "${icon_embedder}" ]]; then
    env \
        SDKROOT="${sdk_path}" \
        CLANG_MODULE_CACHE_PATH="${cache_root}/clang" \
        SWIFT_MODULE_CACHE_PATH="${cache_root}/swift" \
        swiftc -sdk "${sdk_path}" "${icon_embedder_source}" -o "${icon_embedder}"
fi

if [[ ! -f "${icon_source}" || "${icon_raster_source}" -nt "${icon_source}" || "${icon_embedder_source}" -nt "${icon_source}" ]]; then
    "${icon_embedder}" "${icon_raster_source}" "${icon_source}"
fi

if [[ ! -x "${icon_renderer}" || "${icon_renderer_source}" -nt "${icon_renderer}" ]]; then
    env \
        SDKROOT="${sdk_path}" \
        CLANG_MODULE_CACHE_PATH="${cache_root}/clang" \
        SWIFT_MODULE_CACHE_PATH="${cache_root}/swift" \
        swiftc -sdk "${sdk_path}" "${icon_renderer_source}" -o "${icon_renderer}"
fi

if [[ ! -x "${icon_packager}" || "${icon_packager_source}" -nt "${icon_packager}" ]]; then
    env \
        SDKROOT="${sdk_path}" \
        CLANG_MODULE_CACHE_PATH="${cache_root}/clang" \
        SWIFT_MODULE_CACHE_PATH="${cache_root}/swift" \
        swiftc -sdk "${sdk_path}" "${icon_packager_source}" -o "${icon_packager}"
fi

if [[ ! -f "${icon_output}" || ! -f "${titlebar_output}" || "${icon_raster_source}" -nt "${icon_output}" || "${icon_raster_source}" -nt "${titlebar_output}" || "${icon_source}" -nt "${icon_output}" || "${icon_source}" -nt "${titlebar_output}" || "${icon_renderer_source}" -nt "${icon_output}" || "${icon_renderer_source}" -nt "${titlebar_output}" ]]; then
    rm -rf "${iconset_dir}"
    mkdir -p "${iconset_dir}"

    render_icon() {
        local size="$1"
        local name="$2"
        "${icon_renderer}" "${size}" "${icon_raster_source}" "${iconset_dir}/${name}"
    }

    render_icon 16 icon_16x16.png
    render_icon 32 icon_16x16@2x.png
    render_icon 32 icon_32x32.png
    render_icon 64 icon_32x32@2x.png
    render_icon 128 icon_128x128.png
    render_icon 256 icon_128x128@2x.png
    render_icon 256 icon_256x256.png
    render_icon 512 icon_256x256@2x.png
    render_icon 512 icon_512x512.png
    "${icon_renderer}" 1024 "${icon_raster_source}" "${icon_png}"
    cp "${icon_png}" "${iconset_dir}/icon_512x512@2x.png"
    "${icon_packager}" "${iconset_dir}" "${icon_output}"
    "${icon_renderer}" 64 "${icon_raster_source}" "${titlebar_output}"
fi

env \
    SDKROOT="${sdk_path}" \
    CLANG_MODULE_CACHE_PATH="${cache_root}/clang" \
    SWIFT_MODULE_CACHE_PATH="${cache_root}/swift" \
    swift build \
        --disable-sandbox \
        --configuration release \
        -Xswiftc -warnings-as-errors \
        -debug-info-format none \
        --sdk "${sdk_path}" \
        --cache-path "${cache_root}/swiftpm/cache" \
        --config-path "${cache_root}/swiftpm/config" \
        --security-path "${cache_root}/swiftpm/security"

cp "${project_dir}/.build/out/Products/Release/KeyboardFirstMail" "${app_dir}/Contents/MacOS/KeyboardFirstMail"
cp "${project_dir}/AppResources/Info.plist" "${app_dir}/Contents/Info.plist"
cp "${icon_output}" "${app_dir}/Contents/Resources/KeyboardMailIcon.icns"
cp "${titlebar_output}" "${app_dir}/Contents/Resources/KeyboardMailTitlebar.png"
cp "${icon_source}" "${app_dir}/Contents/Resources/KeyboardMailIcon.svg"
chmod +x "${app_dir}/Contents/MacOS/KeyboardFirstMail"
codesign --force --deep --sign - --timestamp=none "${app_dir}"

echo "Built ${app_dir}"
