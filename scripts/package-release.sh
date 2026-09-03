#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
version="${1:-v1.0.0}"
release_dir="${project_dir}/release"
archive="${release_dir}/Mail-macOS-${version}.zip"
checksum="${archive}.sha256"

if [[ ! "${version}" =~ '^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' ]]; then
    echo "Version must be a semantic tag such as v1.0.0." >&2
    exit 64
fi

mkdir -p "${release_dir}"
rm -f "${archive}" "${checksum}"

"${project_dir}/scripts/build-app.sh"
codesign --verify --deep --strict "${project_dir}/Mail.app"
ditto -c -k --sequesterRsrc --keepParent "${project_dir}/Mail.app" "${archive}"

(
    cd "${release_dir}"
    shasum -a 256 "${archive:t}" > "${checksum:t}"
)

echo "Packaged ${archive}"
echo "Checksum ${checksum}"
