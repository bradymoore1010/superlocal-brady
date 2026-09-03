#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
label="${1:-baseline}"
batches="${2:-1}"
thread_count="${MAIL_PERF_THREAD_COUNT:-10000}"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
fallback_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
cache_root="${project_dir}/.build/tool-cache"
benchmark_binary="${project_dir}/.build/performance-benchmark"
result_root="${MAIL_PERF_RESULT_ROOT:-${project_dir}/performance-results.noindex}"
result_dir="${result_root}/${label}"

if ! swiftc -sdk "${sdk_path}" -typecheck - <<< 'import Swift' >/dev/null 2>&1 && [[ -d "${fallback_sdk}" ]]; then
    sdk_path="${fallback_sdk}"
fi

mkdir -p "${cache_root}/clang" "${cache_root}/swift" "${result_dir}"

source_files=(
    "${project_dir}/Sources/KeyboardFirstMail/MailModels.swift"
    "${project_dir}/Sources/KeyboardFirstMail/MailNotifications.swift"
    "${project_dir}/Sources/KeyboardFirstMail/MailWindowRegistry.swift"
    "${project_dir}/Sources/KeyboardFirstMail/MailLineFormatter.swift"
    "${project_dir}/Sources/KeyboardFirstMail/MailSearchEngine.swift"
    "${project_dir}/Sources/KeyboardFirstMail/RecipientAutocomplete.swift"
    "${project_dir}/Sources/KeyboardFirstMail/GmailRecipientDirectory.swift"
    "${project_dir}/Sources/KeyboardFirstMail/GmailAccount.swift"
    "${project_dir}/Sources/KeyboardFirstMail/GmailCredentialStore.swift"
    "${project_dir}/Sources/KeyboardFirstMail/GmailCredentialPickerController.swift"
    "${project_dir}/Sources/KeyboardFirstMail/GmailOAuthCoordinator.swift"
    "${project_dir}/Sources/KeyboardFirstMail/GmailAPIClient.swift"
    "${project_dir}/Sources/KeyboardFirstMail/GmailMessageParser.swift"
    "${project_dir}/Sources/KeyboardFirstMail/GmailMIMEBuilder.swift"
    "${project_dir}/Sources/KeyboardFirstMail/SQLiteMailRepository.swift"
    "${project_dir}/Sources/KeyboardFirstMail/GmailIntegration.swift"
    "${project_dir}/Sources/KeyboardFirstMail/PerformanceInboxFixture.swift"
    "${project_dir}/Sources/KeyboardFirstMail/PerformanceProbe.swift"
    "${project_dir}/Sources/KeyboardFirstMail/MailStore.swift"
)

env \
    SDKROOT="${sdk_path}" \
    CLANG_MODULE_CACHE_PATH="${cache_root}/clang" \
    SWIFT_MODULE_CACHE_PATH="${cache_root}/swift" \
    swiftc \
        -warnings-as-errors \
        -O \
        -whole-module-optimization \
        -D PERFORMANCE_BENCHMARK \
        -sdk "${sdk_path}" \
        "${source_files[@]}" \
        "${project_dir}/Benchmarks/PerformanceBenchmark.swift" \
        -o "${benchmark_binary}"

commit="$(git -C "${project_dir}" rev-parse HEAD 2>/dev/null || print unknown)"
batch=1
while (( batch <= batches )); do
    output="${result_dir}/batch-${batch}.json"
    MAIL_PERF_GIT_COMMIT="${commit}" "${benchmark_binary}" \
        --output "${output}" \
        --label "${label}" \
        --batch "${batch}" \
        --threads "${thread_count}"
    (( batch += 1 ))
done
