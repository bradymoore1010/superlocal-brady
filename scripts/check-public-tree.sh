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

if rg -n -i "${secret_shape}" "${common_args[@]}" "${project_dir}"; then
    echo "Credential-shaped value found in the public tree." >&2
    exit 1
fi

if rg -n "${private_marker}" "${common_args[@]}" "${project_dir}"; then
    echo "Private path or non-fictional Gmail address found in the public tree." >&2
    exit 1
fi

echo "Public-tree privacy scan passed."
