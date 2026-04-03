#!/bin/bash

# ─────────────────────────────────────────────────────────
# SHFTScreenSaver Memory Leak Test
#
# Tests:
#   1. Cycle test    — 5x start/stop, RSS must not grow > CYCLE_GROWTH_LIMIT
#   2. Steady test   — 30s continuous run, RSS must stay flat
#   3. Threshold test — process must NOT die during normal operation
#
# Usage:
#   ./test_memory.sh              # test already-installed saver
#   ./test_memory.sh --build      # build + install + test
# ─────────────────────────────────────────────────────────

CYCLES=5
STEADY_DURATION=30
STEADY_INTERVAL=5
CYCLE_GROWTH_LIMIT_MB=30   # max allowed RSS growth across all cycles
STEADY_GROWTH_LIMIT_MB=5   # max allowed RSS growth during steady run
WAIT_AFTER_START=4
WAIT_AFTER_STOP=3

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

pass=0
fail=0

log_pass() { echo -e "${GREEN}  PASS${NC} $1"; pass=$((pass + 1)); }
log_fail() { echo -e "${RED}  FAIL${NC} $1"; fail=$((fail + 1)); }
log_info() { echo -e "${YELLOW}  INFO${NC} $1"; }

get_rss_kb() {
    ps -o rss= -p "$1" 2>/dev/null | tr -d ' '
}

kb_to_mb() {
    echo "scale=1; $1 / 1024" | bc
}

wait_for_process() {
    local name=$1 max=$2
    local pid=""
    for i in $(seq 1 "$max"); do
        pid=$(pgrep "$name" 2>/dev/null | head -1)
        [ -n "$pid" ] && echo "$pid" && return 0
        sleep 1
    done
    return 1
}

start_screensaver() {
    open -a ScreenSaverEngine 2>/dev/null || true
    sleep "$WAIT_AFTER_START"
}

stop_screensaver() {
    killall ScreenSaverEngine 2>/dev/null || true
    sleep "$WAIT_AFTER_STOP"
}

# ── Build & Install (optional) ──────────────────────────
if [[ "$1" == "--build" ]]; then
    PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
    echo -e "${BOLD}Building...${NC}"
    bash "$PROJECT_DIR/build.sh"

    SAVER_DIR="$HOME/Library/Screen Savers"
    mkdir -p "$SAVER_DIR"
    rm -rf "$SAVER_DIR/SHFTScreenSaver.saver"
    cp -R "$PROJECT_DIR/build/SHFTScreenSaver.saver" "$SAVER_DIR/"
    echo -e "${BOLD}Installed to $SAVER_DIR${NC}"
    echo ""
fi

# ── Cleanup ──────────────────────────────────────────────
killall ScreenSaverEngine 2>/dev/null || true
killall legacyScreenSaver 2>/dev/null || true
sleep 4

echo -e "${BOLD}══════════════════════════════════════${NC}"
echo -e "${BOLD} SHFTScreenSaver Memory Leak Test${NC}"
echo -e "${BOLD}══════════════════════════════════════${NC}"
echo ""

# ── Test 1: Cycle Test ───────────────────────────────────
echo -e "${BOLD}Test 1: Cycle Test (${CYCLES}x start/stop)${NC}"

cycle_rss=()
cycle_pids=()

for i in $(seq 1 $CYCLES); do
    start_screensaver

    PID=$(wait_for_process legacyScreenSaver 5)
    if [ -z "$PID" ]; then
        log_info "Cycle $i: legacyScreenSaver not found (skipped)"
        stop_screensaver
        continue
    fi

    RSS=$(get_rss_kb "$PID")
    if [ -z "$RSS" ]; then
        log_info "Cycle $i: could not read RSS (skipped)"
        stop_screensaver
        continue
    fi

    RSS_MB=$(kb_to_mb "$RSS")
    cycle_rss+=("$RSS")
    cycle_pids+=("$PID")
    echo "         Cycle $i: PID=$PID RSS=${RSS_MB} MB"

    stop_screensaver
done

if [ "${#cycle_rss[@]}" -ge 2 ]; then
    first_rss=${cycle_rss[0]}
    last_rss=${cycle_rss[${#cycle_rss[@]}-1]}
    growth_kb=$((last_rss - first_rss))
    # Handle negative growth (memory went down)
    if [ "$growth_kb" -lt 0 ]; then growth_kb=0; fi
    growth_mb=$(kb_to_mb "$growth_kb")
    limit_kb=$((CYCLE_GROWTH_LIMIT_MB * 1024))

    if [ "$growth_kb" -le "$limit_kb" ]; then
        log_pass "RSS growth: ${growth_mb} MB (limit: ${CYCLE_GROWTH_LIMIT_MB} MB)"
    else
        log_fail "RSS growth: ${growth_mb} MB exceeds limit (${CYCLE_GROWTH_LIMIT_MB} MB)"
    fi

    # Check PID consistency — did process restart (threshold kill)?
    first_pid=${cycle_pids[0]}
    pid_changed=false
    for p in "${cycle_pids[@]}"; do
        if [ "$p" != "$first_pid" ]; then
            pid_changed=true
            break
        fi
    done
    if $pid_changed; then
        log_fail "Process restarted during cycles (PID changed) — threshold triggered?"
    else
        log_pass "Process stayed alive across all cycles (PID=$first_pid)"
    fi
else
    log_fail "Not enough cycle data collected"
fi
echo ""

# ── Test 2: Steady-State Test ────────────────────────────
echo -e "${BOLD}Test 2: Steady-State (${STEADY_DURATION}s continuous)${NC}"

start_screensaver

PID=$(wait_for_process legacyScreenSaver 5)
if [ -z "$PID" ]; then
    log_fail "legacyScreenSaver not running"
else
    steady_rss=()
    steady_pid="$PID"
    process_died=false

    for t in $(seq 0 $STEADY_INTERVAL $STEADY_DURATION); do
        CURRENT_PID=$(pgrep legacyScreenSaver 2>/dev/null | head -1)

        if [ -z "$CURRENT_PID" ] || [ "$CURRENT_PID" != "$steady_pid" ]; then
            log_fail "Process died/restarted at t=${t}s — would cause visible flicker!"
            process_died=true
            break
        fi

        RSS=$(get_rss_kb "$CURRENT_PID")
        RSS_MB=$(kb_to_mb "$RSS")
        steady_rss+=("$RSS")
        echo "         t=${t}s: RSS=${RSS_MB} MB"

        if [ "$t" -lt "$STEADY_DURATION" ]; then sleep "$STEADY_INTERVAL"; fi
    done

    if [ "${#steady_rss[@]}" -ge 2 ] && ! $process_died; then
        first_rss=${steady_rss[0]}
        last_rss=${steady_rss[${#steady_rss[@]}-1]}
        growth_kb=$((last_rss - first_rss))
        if [ "$growth_kb" -lt 0 ]; then growth_kb=0; fi
        growth_mb=$(kb_to_mb "$growth_kb")
        limit_kb=$((STEADY_GROWTH_LIMIT_MB * 1024))

        # Find peak RSS
        peak_rss=0
        for r in "${steady_rss[@]}"; do
            if [ "$r" -gt "$peak_rss" ]; then peak_rss=$r; fi
        done
        peak_mb=$(kb_to_mb "$peak_rss")

        if [ "$growth_kb" -le "$limit_kb" ]; then
            log_pass "Steady RSS growth: ${growth_mb} MB (limit: ${STEADY_GROWTH_LIMIT_MB} MB)"
        else
            log_fail "Steady RSS growth: ${growth_mb} MB exceeds limit (${STEADY_GROWTH_LIMIT_MB} MB)"
        fi

        peak_limit_kb=$((80 * 1024))  # must stay under _exit threshold
        if [ "$peak_rss" -lt "$peak_limit_kb" ]; then
            log_pass "Peak RSS: ${peak_mb} MB (under 80 MB threshold)"
        else
            log_fail "Peak RSS: ${peak_mb} MB — dangerously close to 80 MB threshold"
        fi
    fi
fi

killall ScreenSaverEngine 2>/dev/null || true
echo ""

# ── Summary ──────────────────────────────────────────────
echo -e "${BOLD}══════════════════════════════════════${NC}"
total=$((pass + fail))
if [ "$fail" -eq 0 ]; then
    echo -e "${GREEN}${BOLD} ALL TESTS PASSED ($pass/$total)${NC}"
else
    echo -e "${RED}${BOLD} $fail FAILED${NC}, $pass passed ($total total)"
fi
echo -e "${BOLD}══════════════════════════════════════${NC}"

exit "$fail"
