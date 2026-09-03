#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
destination="${1:?Pass a destination directory}"
thread_count="${2:-10000}"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
fallback_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
cache_root="${project_dir}/.build/tool-cache"
seed_binary="${project_dir}/.build/seed-performance-mailbox"

if ! swiftc -sdk "${sdk_path}" -typecheck - <<< 'import Swift' >/dev/null 2>&1 && [[ -d "${fallback_sdk}" ]]; then
    sdk_path="${fallback_sdk}"
fi

mkdir -p "${cache_root}/clang" "${cache_root}/swift" "${destination}"

source_files=(
    "${project_dir}/Sources/KeyboardFirstMail/MailModels.swift"
    "${project_dir}/Sources/KeyboardFirstMail/MailLineFormatter.swift"
    "${project_dir}/Sources/KeyboardFirstMail/RecipientAutocomplete.swift"
    "${project_dir}/Sources/KeyboardFirstMail/GmailRecipientDirectory.swift"
    "${project_dir}/Sources/KeyboardFirstMail/GmailAccount.swift"
    "${project_dir}/Sources/KeyboardFirstMail/GmailCredentialStore.swift"
    "${project_dir}/Sources/KeyboardFirstMail/GmailAPIClient.swift"
    "${project_dir}/Sources/KeyboardFirstMail/GmailMessageParser.swift"
    "${project_dir}/Sources/KeyboardFirstMail/PerformanceInboxFixture.swift"
    "${project_dir}/Sources/KeyboardFirstMail/SQLiteMailRepository.swift"
)

env \
    SDKROOT="${sdk_path}" \
    CLANG_MODULE_CACHE_PATH="${cache_root}/clang" \
    SWIFT_MODULE_CACHE_PATH="${cache_root}/swift" \
    swiftc \
        -O \
        -whole-module-optimization \
        -D PERFORMANCE_BENCHMARK \
        -sdk "${sdk_path}" \
        "${source_files[@]}" \
        "${project_dir}/Benchmarks/SeedPerformanceMailbox.swift" \
        -o "${seed_binary}"

"${seed_binary}" --directory "${destination}" --threads "${thread_count}"
