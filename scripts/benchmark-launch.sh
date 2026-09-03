#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

project_dir="${0:A:h:h}"
label="${1:-launch}"
warm_runs="${2:-5}"
thread_count="${MAIL_PERF_THREAD_COUNT:-10000}"
app_binary="${MAIL_PERF_APP_BINARY:-${project_dir}/Mail.app/Contents/MacOS/KeyboardFirstMail}"
result_root="${MAIL_PERF_RESULT_ROOT:-${project_dir}/performance-results.noindex}"
result_dir="${result_root}/${label}"
fixture_dir="${MAIL_PERF_FIXTURE_DIR:-${result_dir}/fixture-data}"

if [[ ! -x "${app_binary}" ]]; then
    print -u2 "Build Mail.app before running the launch benchmark."
    exit 1
fi

mkdir -p "${result_dir}"

if [[ ! -f "${fixture_dir}/mail.sqlite3" ]]; then
    "${project_dir}/scripts/seed-performance-mailbox.sh" "${fixture_dir}" "${thread_count}"
fi

run_probe() {
    local kind="$1"
    local run="$2"
    local output="${result_dir}/${kind}-${run}.json"

    MAIL_PERF_OUTPUT="${output}" \
    MAIL_PERF_DATA_DIR="${fixture_dir}" \
    MAIL_PERF_EXPECTED_THREAD_COUNT="${thread_count}" \
    MAIL_PERF_EXIT_AFTER_PROBE=1 \
        "${app_binary}" &
    local process_id=$!
    local checks=0
    while kill -0 "${process_id}" 2>/dev/null && (( checks < 300 )); do
        sleep 0.1
        (( checks += 1 ))
    done
    if kill -0 "${process_id}" 2>/dev/null; then
        kill "${process_id}" 2>/dev/null || true
        wait "${process_id}" 2>/dev/null || true
        print -u2 "Launch probe timed out: ${kind}-${run}"
        exit 1
    fi
    wait "${process_id}" 2>/dev/null || true
    [[ -f "${output}" ]] || {
        print -u2 "Launch probe did not produce ${output}"
        exit 1
    }
    plutil -extract firstFrameMilliseconds raw "${output}"
}

print "Cold launch first frame (ms):"
run_probe cold 1

local_run=1
while (( local_run <= warm_runs )); do
    print "Warm launch ${local_run} first frame (ms):"
    run_probe warm "${local_run}"
    (( local_run += 1 ))
done

print "Launch results: ${result_dir}"
