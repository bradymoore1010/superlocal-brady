#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

project_dir="${0:A:h:h}"
baseline_binary="${1:?Pass the historical app executable}"
candidate_binary="${2:?Pass the candidate app executable}"
result_root="${3:-/private/tmp/keyboard-mail-paired-soak}"
pairs="${4:-3}"
duration="${5:-300}"
maximum_regression_percent="${6:-5}"
thread_count="${MAIL_PERF_THREAD_COUNT:-10000}"

[[ -x "${baseline_binary}" ]] || {
    print -u2 "Baseline app is not executable: ${baseline_binary}"
    exit 1
}
[[ -x "${candidate_binary}" ]] || {
    print -u2 "Candidate app is not executable: ${candidate_binary}"
    exit 1
}
[[ "${pairs}" == <-> && "${pairs}" -gt 0 ]] || {
    print -u2 "Pair count must be a positive integer."
    exit 1
}
[[ "${duration}" == <-> && "${duration}" -gt 0 ]] || {
    print -u2 "Duration must be a positive integer."
    exit 1
}

baseline_dir="${result_root}/baseline"
candidate_dir="${result_root}/candidate"
master_fixture="${result_root}/master-fixture"
mkdir -p "${baseline_dir}" "${candidate_dir}"
touch "${result_root}/.metadata_never_index"

if [[ ! -f "${master_fixture}/mail.sqlite3" ]]; then
    "${project_dir}/scripts/seed-performance-mailbox.sh" \
        "${master_fixture}" \
        "${thread_count}"
fi

run_soak() {
    local variant="$1"
    local app_binary="$2"
    local variant_root="$3"
    local pair="$4"
    local fixture_copy="${result_root}/working-${variant}-${pair}"
    local log="${variant_root}/pair-${pair}.log"
    local output="${variant_root}/pair-${pair}/soak-${duration}s.json"
    local soak_status

    if [[ -f "${output}" ]]; then
        print "Reusing completed ${variant} soak pair ${pair}."
        return
    fi

    rm -rf -- "${fixture_copy}"
    cp -R "${master_fixture}" "${fixture_copy}"
    set +e
    MAIL_PERF_APP_BINARY="${app_binary}" \
        MAIL_PERF_RESULT_ROOT="${variant_root}" \
        MAIL_PERF_FIXTURE_DIR="${fixture_copy}" \
        "${project_dir}/scripts/soak-test.sh" \
        "${duration}" \
        "pair-${pair}" 2>&1 | tee "${log}"
    soak_status=$?
    set -e
    rm -rf -- "${fixture_copy}"

    [[ -f "${output}" ]] || {
        print -u2 "${variant} soak pair ${pair} did not produce a result."
        exit 1
    }
    if (( soak_status != 0 )); then
        if [[ "${variant}" == "candidate" ]]; then
            print -u2 "Candidate soak pair ${pair} failed an absolute release ceiling."
            exit "${soak_status}"
        fi
        print "Historical soak pair ${pair} missed a modern absolute ceiling; retaining its latency sample for the relative comparison."
    fi
}

uptime > "${result_root}/host-load-before.txt"
pair=1
while (( pair <= pairs )); do
    if (( pair % 2 == 1 )); then
        run_soak baseline "${baseline_binary}" "${baseline_dir}" "${pair}"
        run_soak candidate "${candidate_binary}" "${candidate_dir}" "${pair}"
    else
        run_soak candidate "${candidate_binary}" "${candidate_dir}" "${pair}"
        run_soak baseline "${baseline_binary}" "${baseline_dir}" "${pair}"
    fi
    print "paired soak ${pair}/${pairs} complete"
    (( pair += 1 ))
done
uptime > "${result_root}/host-load-after.txt"

metrics=(
    actionP75Milliseconds
    actionP95Milliseconds
    mainQueueDelayP75Milliseconds
    mainQueueDelayP95Milliseconds
    mainRunLoopWorkP75Milliseconds
    mainRunLoopWorkP95Milliseconds
)

comparison_failed=0
comparison_output="${result_root}/comparison.tsv"
print "metric\tmedian_paired_delta_percent\tgate" | tee "${comparison_output}"
for metric in "${metrics[@]}"; do
    deltas=()
    pair=1
    while (( pair <= pairs )); do
        baseline_json="${baseline_dir}/pair-${pair}/soak-${duration}s.json"
        candidate_json="${candidate_dir}/pair-${pair}/soak-${duration}s.json"
        baseline_value="$(plutil -extract "${metric}" raw "${baseline_json}")"
        candidate_value="$(plutil -extract "${metric}" raw "${candidate_json}")"
        delta="$(awk -v baseline="${baseline_value}" -v candidate="${candidate_value}" \
            'BEGIN { printf "%.6f", ((candidate / baseline) - 1) * 100 }')"
        deltas+=("${delta}")
        (( pair += 1 ))
    done

    median="$(printf '%s\n' "${deltas[@]}" | sort -n | awk '
        { values[NR] = $1 }
        END {
            if (NR % 2 == 1) {
                printf "%.6f", values[(NR + 1) / 2]
            } else {
                printf "%.6f", (values[NR / 2] + values[(NR / 2) + 1]) / 2
            }
        }
    ')"
    gate="PASS"
    if ! awk -v delta="${median}" -v maximum="${maximum_regression_percent}" \
        'BEGIN { exit !(delta <= maximum) }'; then
        gate="FAIL"
        comparison_failed=1
    fi
    print "${metric}\t${median}\t${gate}" | tee -a "${comparison_output}"
done

(( comparison_failed == 0 )) || exit 1
print "Paired sustained-use regression gate PASS (maximum ${maximum_regression_percent}%)."
