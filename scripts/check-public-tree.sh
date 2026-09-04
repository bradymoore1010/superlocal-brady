#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"

secret_shape='(AIza[0-9A-Za-z_-]{30,}|GOCSPX-[0-9A-Za-z_-]{20,}|ghp_[0-9A-Za-z]{30,}|github_pat_[0-9A-Za-z_]{50,}|ya29\.[0-9A-Za-z_-]+|-----BEGIN [A-Z ]*PRIVATE KEY-----)'
private_marker='(/Users/[A-Za-z0-9._-]+/|@[Gg][Mm][Aa][Ii][Ll]\.[Cc][Oo][Mm])'

common_args=(
    --hidden
    --glob '!.git/**'
    --glob '!.build/**'
    --glob '!Mail.app/**'
    --glob '!OpenDesign/**'
    --glob '!design-qa.md'
    --glob '!launch-video/node_modules/**'
    --glob '!launch-video/out/**'
    --glob '!performance-results/**'
    --glob '!performance-results.noindex/**'
    --glob '!qa/**'
    --glob '!release/**'
    --glob '!v.2/design-qa.md'
    --glob '!v.2/qa-comparison.html'
    --glob '!v.2/qa/**'
)

scan_with_grep() {
    local pattern="$1"
    local case_mode="$2"
    local -a grep_args=(-E -n -H -I)
    local candidate
    local grep_status
    local found=1

    if [[ "${case_mode}" == "insensitive" ]]; then
        grep_args+=(-i)
    fi

    while IFS= read -r -d '' candidate; do
        if grep "${grep_args[@]}" -- "${pattern}" "${candidate}"; then
            found=0
        else
            grep_status=$?
            if (( grep_status > 1 )); then
                echo "Privacy scan could not read ${candidate}." >&2
                return 2
            fi
        fi
    done < <(
        find "${project_dir}" \
            \( -path "${project_dir}/.git" \
            -o -path "${project_dir}/.build" \
            -o -path "${project_dir}/Mail.app" \
            -o -path "${project_dir}/OpenDesign" \
            -o -path "${project_dir}/design-qa.md" \
            -o -path "${project_dir}/launch-video/node_modules" \
            -o -path "${project_dir}/launch-video/out" \
            -o -path "${project_dir}/performance-results" \
            -o -path "${project_dir}/performance-results.noindex" \
            -o -path "${project_dir}/qa" \
            -o -path "${project_dir}/release" \
            -o -path "${project_dir}/v.2/design-qa.md" \
            -o -path "${project_dir}/v.2/qa-comparison.html" \
            -o -path "${project_dir}/v.2/qa" \) -prune \
            -o -type f -print0
    )

    return ${found}
}

if command -v rg >/dev/null 2>&1; then
    if rg -n -i "${secret_shape}" "${common_args[@]}" "${project_dir}"; then
        echo "Credential-shaped value found in the public tree." >&2
        exit 1
    fi

    if rg -n "${private_marker}" "${common_args[@]}" "${project_dir}"; then
        echo "Private path or non-fictional Gmail address found in the public tree." >&2
        exit 1
    fi
elif command -v grep >/dev/null 2>&1 && command -v find >/dev/null 2>&1; then
    if scan_with_grep "${secret_shape}" insensitive; then
        echo "Credential-shaped value found in the public tree." >&2
        exit 1
    elif (( $? > 1 )); then
        exit 2
    fi

    if scan_with_grep "${private_marker}" sensitive; then
        echo "Private path or non-fictional Gmail address found in the public tree." >&2
        exit 1
    elif (( $? > 1 )); then
        exit 2
    fi
else
    echo "Public-tree privacy scan requires rg or both grep and find." >&2
    exit 2
fi

echo "Public-tree privacy scan passed."
