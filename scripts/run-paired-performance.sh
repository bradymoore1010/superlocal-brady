#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

project_dir="${0:A:h:h}"
baseline_binary="${1:?Pass the historical benchmark binary}"
candidate_binary="${2:?Pass the candidate benchmark binary}"
result_root="${3:-/private/tmp/keyboard-mail-simultaneous-pairs}"
batches="${4:-9}"
thread_count="${5:-10000}"
maximum_regression_percent="${6:-5}"
max_pair_attempts="${MAIL_PERF_MAX_PAIR_ATTEMPTS:-12}"
pair_mode="${MAIL_PERF_PAIR_MODE:-simultaneous}"

[[ -x "${baseline_binary}" ]] || {
    print -u2 "Baseline benchmark is not executable: ${baseline_binary}"
    exit 1
}
[[ -x "${candidate_binary}" ]] || {
    print -u2 "Candidate benchmark is not executable: ${candidate_binary}"
    exit 1
}
[[ "${batches}" == <-> && "${batches}" -gt 0 ]] || {
    print -u2 "Batch count must be a positive integer."
    exit 1
}
[[ "${thread_count}" == <-> && "${thread_count}" -gt 0 ]] || {
    print -u2 "Thread count must be a positive integer."
    exit 1
}
[[ "${max_pair_attempts}" == <-> && "${max_pair_attempts}" -gt 0 ]] || {
    print -u2 "MAIL_PERF_MAX_PAIR_ATTEMPTS must be a positive integer."
    exit 1
}
[[ "${pair_mode}" == "simultaneous" || "${pair_mode}" == "serial" ]] || {
    print -u2 "MAIL_PERF_PAIR_MODE must be simultaneous or serial."
    exit 1
}

baseline_dir="${result_root}/baseline"
candidate_dir="${result_root}/candidate"
mkdir -p "${baseline_dir}" "${candidate_dir}"
uptime > "${result_root}/host-load-before.txt"

run_benchmark() {
    local label="$1"
    local binary="$2"
    local output_dir="$3"
    local batch="$4"
    /usr/sbin/taskpolicy -a -l 0 /usr/bin/env \
        MAIL_PERF_GIT_COMMIT="${label}" "${binary}" \
        --output "${output_dir}/batch-${batch}.json" \
        --label "${label}" \
        --batch "${batch}" \
        --threads "${thread_count}" \
        > "${output_dir}/batch-${batch}.log" 2>&1
}

run_pair() {
    local batch="$1"
    local attempt=1
    local baseline_pid candidate_pid baseline_status candidate_status
    local rejected_dir="${result_root}/rejected"

    while (( attempt <= max_pair_attempts )); do
        # Start order alternates, but both processes execute concurrently so
        # host, thermal, filesystem, and background-service pressure is shared.
        if [[ "${pair_mode}" == "serial" ]]; then
            set +e
            if (( (batch + attempt) % 2 == 0 )); then
                run_benchmark baseline "${baseline_binary}" "${baseline_dir}" "${batch}"
                baseline_status=$?
                run_benchmark candidate "${candidate_binary}" "${candidate_dir}" "${batch}"
                candidate_status=$?
            else
                run_benchmark candidate "${candidate_binary}" "${candidate_dir}" "${batch}"
                candidate_status=$?
                run_benchmark baseline "${baseline_binary}" "${baseline_dir}" "${batch}"
                baseline_status=$?
            fi
            set -e
        else
            if (( (batch + attempt) % 2 == 0 )); then
                run_benchmark baseline "${baseline_binary}" "${baseline_dir}" "${batch}" &
                baseline_pid=$!
                run_benchmark candidate "${candidate_binary}" "${candidate_dir}" "${batch}" &
                candidate_pid=$!
            else
                run_benchmark candidate "${candidate_binary}" "${candidate_dir}" "${batch}" &
                candidate_pid=$!
                run_benchmark baseline "${baseline_binary}" "${baseline_dir}" "${batch}" &
                baseline_pid=$!
            fi

            set +e
            wait "${baseline_pid}"
            baseline_status=$?
            wait "${candidate_pid}"
            candidate_status=$?
            set -e
        fi

        # Each deterministic fixture database is roughly 120 MB. JSON and logs
        # are durable evidence, so discard only these generated stores.
        rm -rf -- \
            "${baseline_dir}/database-${batch}" \
            "${candidate_dir}/database-${batch}"

        if (( baseline_status == 0 && candidate_status == 0 )); then
            print "paired batch ${batch} complete (attempt ${attempt})"
            return
        fi

        # An absolute-budget miss invalidates the environment for comparison.
        # Preserve it separately, then retry rather than mixing it into the gate.
        mkdir -p "${rejected_dir}"
        [[ ! -f "${baseline_dir}/batch-${batch}.json" ]] || mv \
            "${baseline_dir}/batch-${batch}.json" \
            "${rejected_dir}/baseline-batch-${batch}-attempt-${attempt}.json"
        [[ ! -f "${candidate_dir}/batch-${batch}.json" ]] || mv \
            "${candidate_dir}/batch-${batch}.json" \
            "${rejected_dir}/candidate-batch-${batch}-attempt-${attempt}.json"
        mv "${baseline_dir}/batch-${batch}.log" \
            "${rejected_dir}/baseline-batch-${batch}-attempt-${attempt}.log"
        mv "${candidate_dir}/batch-${batch}.log" \
            "${rejected_dir}/candidate-batch-${batch}-attempt-${attempt}.log"
        uptime >> "${rejected_dir}/host-load.txt"

        if (( attempt == max_pair_attempts )); then
            print -u2 "Paired batch ${batch} remained invalid after ${attempt} attempts."
            tail -40 "${rejected_dir}/baseline-batch-${batch}-attempt-${attempt}.log" >&2 || true
            tail -40 "${rejected_dir}/candidate-batch-${batch}-attempt-${attempt}.log" >&2 || true
            exit 1
        fi
        print -u2 "paired batch ${batch} rejected (attempt ${attempt}); retrying"
        sleep 5
        (( attempt += 1 ))
    done
}

batch=1
while (( batch <= batches )); do
    run_pair "${batch}"
    (( batch += 1 ))
done

uptime > "${result_root}/host-load-after.txt"
"${project_dir}/scripts/compare-performance.sh" \
    "${baseline_dir}" \
    "${candidate_dir}" \
    "${maximum_regression_percent}"
