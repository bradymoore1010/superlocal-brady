#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

project_dir="${0:A:h:h}"
baseline_binary="${1:?Pass the baseline app executable}"
candidate_binary="${2:?Pass the candidate app executable}"
result_root="${3:-/private/tmp/keyboard-mail-paired-launch}"
pairs="${4:-12}"
maximum_regression_percent="${5:-5}"
thread_count="${MAIL_PERF_THREAD_COUNT:-10000}"

[[ -x "${baseline_binary}" ]] || {
    print -u2 "Baseline app is not executable: ${baseline_binary}"
    exit 1
}
[[ -x "${candidate_binary}" ]] || {
    print -u2 "Candidate app is not executable: ${candidate_binary}"
    exit 1
}
[[ "${pairs}" == <-> && "${pairs}" -gt 2 ]] || {
    print -u2 "Pair count must be an integer greater than two."
    exit 1
}

baseline_dir="${result_root}/baseline"
candidate_dir="${result_root}/candidate"
fixture_dir="${result_root}/fixture-data"
mkdir -p "${baseline_dir}" "${candidate_dir}"
touch "${result_root}/.metadata_never_index"

if [[ ! -f "${fixture_dir}/mail.sqlite3" ]]; then
    "${project_dir}/scripts/seed-performance-mailbox.sh" "${fixture_dir}" "${thread_count}"
fi

run_probe() {
    local variant="$1"
    local binary="$2"
    local output="$3"
    local log="${output:r}.log"
    local process_status

    [[ -f "${output}" ]] && return
    /usr/bin/env MAIL_PERF_OUTPUT="${output}" MAIL_PERF_DATA_DIR="${fixture_dir}" MAIL_PERF_EXPECTED_THREAD_COUNT="${thread_count}" MAIL_PERF_EXIT_AFTER_PROBE=1 "${binary}" >"${log}" 2>&1 &
    local process_id=$!
    local checks=0
    while kill -0 "${process_id}" 2>/dev/null && (( checks < 300 )); do
        sleep 0.1
        (( checks += 1 ))
    done
    if kill -0 "${process_id}" 2>/dev/null; then
        kill "${process_id}" 2>/dev/null || true
        wait "${process_id}" 2>/dev/null || true
        print -u2 "${variant} launch probe timed out."
        exit 1
    fi
    set +e
    wait "${process_id}" 2>/dev/null
    process_status=$?
    set -e
    [[ -f "${output}" ]] || {
        print -u2 "${variant} launch probe did not produce ${output} (exit ${process_status})"
        [[ ! -f "${log}" ]] || tail -40 "${log}" >&2
        exit 1
    }
}

# Prime code signing, dynamic libraries, and the deterministic cache once for
# each executable before collecting paired warm-launch samples.
run_probe baseline-warmup "${baseline_binary}" "${baseline_dir}/warmup.json"
run_probe candidate-warmup "${candidate_binary}" "${candidate_dir}/warmup.json"

uptime > "${result_root}/host-load-before.txt"
pair=1
while (( pair <= pairs )); do
    baseline_output="${baseline_dir}/pair-${pair}.json"
    candidate_output="${candidate_dir}/pair-${pair}.json"
    if (( pair % 2 == 1 )); then
        run_probe baseline "${baseline_binary}" "${baseline_output}"
        run_probe candidate "${candidate_binary}" "${candidate_output}"
    else
        run_probe candidate "${candidate_binary}" "${candidate_output}"
        run_probe baseline "${baseline_binary}" "${baseline_output}"
    fi
    print "paired launch ${pair}/${pairs} complete"
    (( pair += 1 ))
done
uptime > "${result_root}/host-load-after.txt"

deltas=()
candidate_values=()
pair=1
while (( pair <= pairs )); do
    baseline_value="$(plutil -extract firstFrameMilliseconds raw "${baseline_dir}/pair-${pair}.json")"
    candidate_value="$(plutil -extract firstFrameMilliseconds raw "${candidate_dir}/pair-${pair}.json")"
    candidate_values+=("${candidate_value}")
    deltas+=("$(awk -v baseline="${baseline_value}" -v candidate="${candidate_value}" 'BEGIN { printf "%.6f", ((candidate / baseline) - 1) * 100 }')")
    (( pair += 1 ))
done

median_delta="$(printf '%s\n' "${deltas[@]}" | sort -n | awk '
    { values[NR] = $1 }
    END {
        if (NR % 2 == 1) printf "%.6f", values[(NR + 1) / 2]
        else printf "%.6f", (values[NR / 2] + values[(NR / 2) + 1]) / 2
    }
')"

percentile() {
    local percentile="$1"
    printf '%s\n' "${candidate_values[@]}" | sort -n | awk -v percentile="${percentile}" '
        { values[NR] = $1 }
        END {
            rank = int((NR * percentile) + 0.999999)
            if (rank < 1) rank = 1
            if (rank > NR) rank = NR
            printf "%.3f", values[rank]
        }
    '
}

candidate_p75="$(percentile 0.75)"
candidate_p95="$(percentile 0.95)"
print "median_paired_delta_percent=${median_delta}"
print "candidate_p75_milliseconds=${candidate_p75}"
print "candidate_p95_milliseconds=${candidate_p95}"

awk -v delta="${median_delta}" -v maximum="${maximum_regression_percent}" 'BEGIN { exit !(delta <= maximum) }' || {
        print -u2 "FAIL launch regression: ${median_delta}% > ${maximum_regression_percent}%"
        exit 1
    }
awk -v value="${candidate_p75}" 'BEGIN { exit !(value < 500) }' || {
    print -u2 "FAIL warm launch p75: ${candidate_p75} ms >= 500 ms"
    exit 1
}
awk -v value="${candidate_p95}" 'BEGIN { exit !(value < 1000) }' || {
    print -u2 "FAIL warm launch p95: ${candidate_p95} ms >= 1000 ms"
    exit 1
}

print "Paired warm-launch regression and absolute budgets PASS."
