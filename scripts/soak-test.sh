#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

project_dir="${0:A:h:h}"
duration="${1:-900}"
label="${2:-soak}"
thread_count="${MAIL_PERF_THREAD_COUNT:-10000}"
app_binary="${MAIL_PERF_APP_BINARY:-${project_dir}/Mail.app/Contents/MacOS/KeyboardFirstMail}"
result_root="${MAIL_PERF_RESULT_ROOT:-${project_dir}/performance-results.noindex}"
result_dir="${result_root}/${label}"
fixture_dir="${MAIL_PERF_FIXTURE_DIR:-${result_dir}/fixture-data}"
output="${result_dir}/soak-${duration}s.json"
memory_output="${result_dir}/soak-${duration}s-rss.txt"

if [[ ! -x "${app_binary}" ]]; then
    print -u2 "Build Mail.app before running the soak test."
    exit 1
fi

mkdir -p "${result_dir}"

if [[ ! -f "${fixture_dir}/mail.sqlite3" ]]; then
    "${project_dir}/scripts/seed-performance-mailbox.sh" "${fixture_dir}" "${thread_count}"
fi

/usr/sbin/taskpolicy -a -l 0 /usr/bin/env \
    MAIL_PERF_OUTPUT="${output}" \
    MAIL_PERF_DATA_DIR="${fixture_dir}" \
    MAIL_PERF_EXPECTED_THREAD_COUNT="${thread_count}" \
    MAIL_PERF_STRESS_SECONDS="${duration}" \
    MAIL_PERF_EXIT_AFTER_PROBE=1 \
    "${app_binary}" &
process_id=$!

elapsed=0
start_rss=0
peak_rss=0
last_rss=0
while kill -0 "${process_id}" 2>/dev/null; do
    last_rss="$(ps -o rss= -p "${process_id}" 2>/dev/null | tr -d ' ' || true)"
    if [[ "${last_rss}" == <-> ]] && (( last_rss > 10000 )); then
        (( start_rss == 0 )) && start_rss="${last_rss}"
        (( last_rss > peak_rss )) && peak_rss="${last_rss}"
    fi
    print "Soak ${elapsed}s/${duration}s, RSS ${last_rss:-unavailable} KB"
    sleep 30
    (( elapsed += 30 ))
done
wait "${process_id}" 2>/dev/null || true

[[ -f "${output}" ]] || {
    print -u2 "Soak test did not produce ${output}"
    exit 1
}

{
    print "start_rss_kb=${start_rss}"
    print "peak_rss_kb=${peak_rss}"
    print "end_rss_kb=${last_rss:-0}"
} > "${memory_output}"

for key in \
    actionCount \
    actionP75Milliseconds \
    actionP95Milliseconds \
    actionMaximumMilliseconds \
    mainQueueDelayP75Milliseconds \
    mainQueueDelayP95Milliseconds \
    mainQueueDelayMaximumMilliseconds \
    mainQueueDelaysOverFrameBudget \
    mainRunLoopWorkP75Milliseconds \
    mainRunLoopWorkP95Milliseconds \
    mainRunLoopWorkMaximumMilliseconds \
    mainThreadTasksOver50Milliseconds; do
    value="$(plutil -extract "${key}" raw "${output}" 2>/dev/null || true)"
    print "${key}=${value}"
done
print "Memory samples: ${memory_output}"

metric() {
    plutil -extract "$1" raw "${output}" 2>/dev/null || print 0
}

assert_at_most() {
    local name="$1"
    local value="$2"
    local budget="$3"
    if ! awk -v value="${value}" -v budget="${budget}" 'BEGIN { exit !(value <= budget) }'; then
        print -u2 "FAIL ${name}: ${value} > ${budget}"
        return 1
    fi
}

minimum_actions=$(( duration * 4 ))
recorded_actions="$(metric actionCount)"
if (( recorded_actions < minimum_actions )); then
    print -u2 "FAIL actionCount: ${recorded_actions} < ${minimum_actions}"
    exit 1
fi

assert_at_most actionP95Milliseconds "$(metric actionP95Milliseconds)" 100
assert_at_most mainQueueDelayP95Milliseconds "$(metric mainQueueDelayP95Milliseconds)" 16.667
assert_at_most mainRunLoopWorkMaximumMilliseconds "$(metric mainRunLoopWorkMaximumMilliseconds)" 50
assert_at_most mainThreadTasksOver50Milliseconds "$(metric mainThreadTasksOver50Milliseconds)" 0

if (( start_rss > 0 && last_rss > start_rss + 10240 )); then
    print -u2 "FAIL resident memory grew by more than 10 MB: ${start_rss} KB -> ${last_rss} KB"
    exit 1
fi

print "Soak performance budgets PASS"
