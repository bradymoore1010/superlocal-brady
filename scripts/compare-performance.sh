#!/bin/zsh
set -euo pipefail

baseline_dir="${1:?Pass the baseline result directory}"
candidate_dir="${2:?Pass the candidate result directory}"
maximum_regression_percent="${3:-5}"

command -v jq >/dev/null || {
    print -u2 "jq is required to compare benchmark JSON."
    exit 1
}

baseline_files=("${baseline_dir}"/batch-*.json(N))
candidate_files=("${candidate_dir}"/batch-*.json(N))
if (( ${#baseline_files} == 0 || ${#candidate_files} == 0 )); then
    print -u2 "Both result directories must contain batch-*.json files."
    exit 1
fi
if (( ${#baseline_files} != ${#candidate_files} )); then
    print -u2 "Baseline and candidate must contain the same number of paired batches."
    exit 1
fi

scratch_dir="$(mktemp -d /private/tmp/keyboard-mail-performance-compare.XXXXXX)"
trap 'rm -rf "${scratch_dir}"' EXIT
ratios_file="${scratch_dir}/ratios.tsv"
: > "${ratios_file}"

for candidate_file in "${candidate_files[@]}"; do
    batch_name="${candidate_file:t}"
    baseline_file="${baseline_dir}/${batch_name}"
    [[ -f "${baseline_file}" ]] || {
        print -u2 "Missing paired baseline file: ${batch_name}"
        exit 1
    }

    baseline_tsv="${scratch_dir}/baseline-${batch_name}.tsv"
    candidate_tsv="${scratch_dir}/candidate-${batch_name}.tsv"
    jq -r '.metrics[] | [.name, .p95] | @tsv' "${baseline_file}" | sort > "${baseline_tsv}"
    jq -r '.metrics[] | [.name, .p95] | @tsv' "${candidate_file}" | sort > "${candidate_tsv}"

    expected_metrics="$(wc -l < "${baseline_tsv}" | tr -d ' ')"
    candidate_metrics="$(wc -l < "${candidate_tsv}" | tr -d ' ')"
    (( expected_metrics == candidate_metrics )) || {
        print -u2 "Metric count differs in ${batch_name}."
        exit 1
    }

    join -t $'\t' "${baseline_tsv}" "${candidate_tsv}" |
        awk -F '\t' '{ print $1 "\t" (($3 / $2) - 1) * 100 }' >> "${ratios_file}"
done

sorted_ratios="${scratch_dir}/ratios-sorted.tsv"
sort -t $'\t' -k1,1 -k2,2n "${ratios_file}" > "${sorted_ratios}"

awk -F '\t' -v limit="${maximum_regression_percent}" '
    {
        count[$1] += 1
        value[$1, count[$1]] = $2
    }
    END {
        failed = 0
        printf "%-34s %12s %s\n", "metric", "median delta", "gate"
        for (name in count) {
            n = count[name]
            if (n % 2 == 1) median = value[name, (n + 1) / 2]
            else median = (value[name, n / 2] + value[name, n / 2 + 1]) / 2
            gate = median <= limit ? "PASS" : "FAIL"
            if (gate == "FAIL") failed = 1
            printf "%-34s %+11.3f%% %s\n", name, median, gate
        }
        exit failed
    }
' "${sorted_ratios}" | sort

print "Paired p95 regression gate PASS (maximum ${maximum_regression_percent}%)."
