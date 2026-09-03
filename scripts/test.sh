#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
fallback_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
cache_root="${project_dir}/.build/tool-cache"
test_binary="${project_dir}/.build/search-tests"
repository_test_binary="${project_dir}/.build/repository-tests"
store_test_binary="${project_dir}/.build/mail-store-tests"

if ! swiftc -sdk "${sdk_path}" -typecheck - <<< 'import Swift' >/dev/null 2>&1 && [[ -d "${fallback_sdk}" ]]; then
    sdk_path="${fallback_sdk}"
fi

mkdir -p "${cache_root}/clang" "${cache_root}/swift"

env \
    SDKROOT="${sdk_path}" \
    CLANG_MODULE_CACHE_PATH="${cache_root}/clang" \
    SWIFT_MODULE_CACHE_PATH="${cache_root}/swift" \
    swiftc \
        -warnings-as-errors \
        -sdk "${sdk_path}" \
        "${project_dir}/Sources/KeyboardFirstMail/MailModels.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/RecipientAutocomplete.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/GmailRecipientDirectory.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/MailSearchEngine.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/MailLineFormatter.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/GmailAccount.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/GmailCredentialStore.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/GmailOAuthCoordinator.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/GmailAPIClient.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/GmailMessageParser.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/GmailMIMEBuilder.swift" \
        "${project_dir}/Tests/SearchTestRunner.swift" \
        -o "${test_binary}"

"${test_binary}"

env \
    SDKROOT="${sdk_path}" \
    CLANG_MODULE_CACHE_PATH="${cache_root}/clang" \
    SWIFT_MODULE_CACHE_PATH="${cache_root}/swift" \
    swiftc \
        -warnings-as-errors \
        -sdk "${sdk_path}" \
        "${project_dir}/Sources/KeyboardFirstMail/MailModels.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/MailLineFormatter.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/RecipientAutocomplete.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/GmailRecipientDirectory.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/GmailAccount.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/GmailCredentialStore.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/GmailOAuthCoordinator.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/GmailAPIClient.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/GmailMessageParser.swift" \
        "${project_dir}/Sources/KeyboardFirstMail/SQLiteMailRepository.swift" \
        "${project_dir}/Tests/RepositoryTestRunner.swift" \
        -lsqlite3 \
        -o "${repository_test_binary}"

"${repository_test_binary}"

store_sources=("${project_dir}"/Sources/KeyboardFirstMail/*.swift)
store_sources=("${(@)store_sources:#${project_dir}/Sources/KeyboardFirstMail/KeyboardFirstMailApp.swift}")

env \
    SDKROOT="${sdk_path}" \
    CLANG_MODULE_CACHE_PATH="${cache_root}/clang" \
    SWIFT_MODULE_CACHE_PATH="${cache_root}/swift" \
    swiftc \
        -warnings-as-errors \
        -sdk "${sdk_path}" \
        "${store_sources[@]}" \
        "${project_dir}/Tests/MailStoreTestRunner.swift" \
        -lsqlite3 \
        -o "${store_test_binary}"

"${store_test_binary}"
