#!/usr/bin/env bash
# The Module 11 labs and failure reproductions against the running stack (scripts/stack.sh up).
# The JDK-only LatencyProbe runs on the Mac against the published ports, so every timing crosses
# Docker Desktop's port forwarder into its Linux virtual machine.
#
# Usage: scripts/lab.sh <lab> [--run] [--yes]
#   routes        Lab 1, steps 1 and 2: the status of five requests without a token
#   latency       Lab 1, steps 3 to 6: catalog and booking timed directly and through the gateway,
#                 at RATE requests/s for SECONDS s after a WARMUP s run, with the gateway's CPU read
#                 from its control group around each run through it
#   slow-booking  Lab 3, step 4: booking's reads delayed by 2 s, twenty seat screens through the
#                 gateway; then booking is started again without the delay
#   bottleneck    Section 9, failure mode 1: the gateway limited to 0.5 CPU and probed at RATES
#                 requests/s (default 100, 250 and 500), each after the gateway is quick again; then
#                 the only gateway stopped during a run and started again
#   rotate        Section 9, failure mode 4: the issuer's key rotated and the issuer restarted; a
#                 token signed with the new key and one signed with the old key, through the gateway
#   default a dry run: print the plan, change nothing; --run does it after a question; --yes skips it
#
# Guardrails: the only target is the project seatwave-gateway; Docker must answer and the stack
# must be ready first; each change appends an audit line to build/stack/audit.log; the stack is put
# back as compose.yaml describes it at the end (an EXIT trap), also when a step failed; reports go
# to build/runs/<lab>.txt; any failure exits non-zero. RATE, DURATION and WARMUP may be set in the
# environment (defaults 500, 30 and 10).
set -euo pipefail

usage() {
  echo "usage: $0 <routes|latency|slow-booking|bottleneck|rotate> [--run] [--yes]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
lab="$1"
shift
mode="dry-run"
confirmed="no"
for option in "$@"; do
  case "$option" in
    --run) mode="run" ;;
    --yes) confirmed="yes" ;;
    *) usage ;;
  esac
done

# Lab 1's rate and duration; a warm-up run first, so the JIT has compiled the path being timed.
readonly RATE="${RATE:-500}"
readonly SECONDS_TIMED="${DURATION:-30}"
readonly WARMUP="${WARMUP:-10}"
readonly RATES="${RATES:-100 250 500}"
readonly WAIT_SECONDS=120
readonly GATEWAY="http://127.0.0.1:21100"
readonly SEAT_PAGE="/v1/events/1/seats?section=A&limit=100"
readonly OVERRIDE="build/stack/compose.direct.yaml"

case "$lab" in
  routes) plan="five curl requests through the gateway; nothing is changed" ;;
  latency) plan="catalog and booking published on 127.0.0.1:21110 and 21111 for this lab; four probe runs at ${RATE}/s for ${SECONDS_TIMED} s; then compose.yaml's ports again" ;;
  slow-booking) plan="booking restarted with SEATWAVE_BOOKING_READ_DELAY=2s; twenty screens; booking restarted without it" ;;
  bottleneck) plan="docker update --cpus 0.5 on the gateway; probe runs at ${RATES} requests/s; --cpus 2 again; then the gateway stopped 5 s into a 20 s run and started again" ;;
  rotate) plan="./gradlew :issuer:keys rotate; the issuer restarted; two tokens through the gateway" ;;
  *) usage ;;
esac

cd "$(dirname "$0")/.."
source scripts/common.sh

echo "plan: lab $lab on the Compose project $PROJECT: $plan"
if [[ "$mode" == "dry-run" ]]; then
  echo "dry run: nothing changed. Add --run to do it."
  exit 0
fi
docker_must_answer
if ! stack_ready; then
  echo "the stack is not ready (scripts/stack.sh up --run first); nothing changed" >&2
  exit 1
fi
if [[ "$confirmed" != "yes" ]]; then
  read -r -p "Go ahead with lab '$lab'? [y/N] " answer < /dev/tty
  [[ "$answer" == "y" ]] || { echo "not confirmed; nothing changed" >&2; exit 1; }
fi

mkdir -p build/runs
report="build/runs/$lab.txt"
: > "$report"
say() { echo "$1" | tee -a "$report"; }

# Section 8's command 2: the probe compiled with the JDK alone.
javac -Xlint:all -Werror -d build/labtools labtools/src/main/java/io/plainround/seatwave/gateway/labtools/*.java
probe() { java -cp build/labtools io.plainround.seatwave.gateway.labtools.LatencyProbe "$@"; }

token_for() {
  curl -s --fail --max-time 5 -X POST "http://127.0.0.1:21102/v1/tokens?subject=$1" \
    | sed -n 's/.*"accessToken":"\([^"]*\)".*/\1/p'
}

# Booking is published only through the gateway, so it is ready when it answers through the
# gateway. The question is a hold with a malformed Idempotency-Key: booking refuses it at once
# with its own problem type and holds nothing, and the lab's read delay does not apply to it (the
# delay is longer than the gateway's 2 s read timeout, so a delayed read would never answer).
wait_until_booking_answers() {
  local token waited
  token="$(token_for fan-1)"
  for (( waited = 0; waited < WAIT_SECONDS; waited++ )); do
    if curl -s --max-time 5 -X POST -H "Authorization: Bearer $token" -H 'Idempotency-Key: not valid' \
        -H 'Content-Type: application/json' -d '{"eventId":1,"seatId":"A-1"}' "$GATEWAY/v1/holds" \
        | grep -q 'problems/invalid-request'; then
      return 0
    fi
    sleep 1
  done
  echo "booking did not answer through the gateway within ${WAIT_SECONDS} s" >&2
  return 1
}

# The CPU time the gateway's container has used since it started, in microseconds.
gateway_cpu_usec() {
  docker exec "$PROJECT-gateway-1" cat /sys/fs/cgroup/cpu.stat | awk '$1 == "usage_usec" { print $2 }'
}

# Puts the stack back as compose.yaml describes it, and checks it is ready.
restore() {
  "${compose[@]}" up -d --quiet-pull > /dev/null 2>&1
  docker update --cpus 2 "$PROJECT-gateway-1" > /dev/null
  wait_until_ready "$WAIT_SECONDS" > /dev/null
  wait_until_booking_answers
  audit "$lab: stack put back as compose.yaml describes it"
}

# An overloaded gateway keeps working through its queue after the client has given up, so before
# the next run it must answer one request within half a second again.
wait_until_gateway_is_quick() {
  local waited
  for (( waited = 0; waited < WAIT_SECONDS; waited++ )); do
    if curl -s --fail -o /dev/null --max-time 0.5 "$GATEWAY$SEAT_PAGE"; then
      return 0
    fi
    sleep 1
  done
  echo "the gateway did not answer within 0.5 s for ${WAIT_SECONDS} s" >&2
  return 1
}

# One warm-up run that is thrown away, then the timed run, with the gateway's CPU around it.
timed() {
  local name="$1"
  shift
  probe "$1" "$RATE" "$WARMUP" "${@:2}" > /dev/null
  local before after
  before="$(gateway_cpu_usec)"
  say "== $name: $1 at ${RATE}/s for ${SECONDS_TIMED} s, after a ${WARMUP} s warm-up"
  probe "$1" "$RATE" "$SECONDS_TIMED" "${@:2}" | tee -a "$report"
  after="$(gateway_cpu_usec)"
  say "gateway CPU during the run: $(( (after - before) / 1000 )) ms, $(( (after - before) / (RATE * SECONDS_TIMED) )) us per planned request"
}

case "$lab" in
  routes)
    for request in "GET /v1/events/1" "POST /v1/holds" "GET /mobile/v1/events/1/seat-screen?section=A" \
        "PUT /v1/events/1" "GET /v2/holds"; do
      say "$request -> $(curl -s -o /dev/null -w '%{http_code}' -X "${request%% *}" "$GATEWAY${request#* }")"
    done
    ;;
  latency)
    trap restore EXIT
    mkdir -p build/stack
    # Generated for this lab only, in the ignored build folder: the two services get a port.
    printf 'services:\n  catalog:\n    ports: ["127.0.0.1:21110:8080"]\n  booking:\n    ports: ["127.0.0.1:21111:8080"]\n' > "$OVERRIDE"
    "${compose[@]}" -f compose.yaml -f "$OVERRIDE" up -d catalog booking > /dev/null 2>&1
    audit "latency: catalog and booking published on 21110 and 21111"
    wait_until_ready "$WAIT_SECONDS" > /dev/null
    wait_until_booking_answers
    token="$(token_for fan-42)"
    timed "catalog, direct" "http://127.0.0.1:21110$SEAT_PAGE"
    timed "catalog, through the gateway (public route)" "$GATEWAY$SEAT_PAGE"
    timed "booking, direct (X-SeatWave-Subject as the gateway sends it)" "http://127.0.0.1:21111/v1/holds?eventId=1" "subject=fan-42"
    timed "booking, through the gateway (token checked)" "$GATEWAY/v1/holds?eventId=1" "$token"
    ;;
  slow-booking)
    trap restore EXIT
    SEATWAVE_BOOKING_READ_DELAY=2s "${compose[@]}" up -d booking > /dev/null 2>&1
    audit "slow-booking: booking started with a 2 s read delay"
    wait_until_ready "$WAIT_SECONDS" > /dev/null
    wait_until_booking_answers
    token="$(token_for fan-42)"
    for screen in $(seq 1 20); do
      timing="$(curl -s -o build/runs/screen.json -w '%{http_code} %{time_total}' \
        -H "Authorization: Bearer $token" "$GATEWAY/mobile/v1/events/1/seat-screen?section=A")"
      parts="$(grep -o '"partial":[a-z]*,"missing":\[[^]]*\]' build/runs/screen.json || echo 'no screen in the body')"
      say "screen $screen: status ${timing% *}, ${timing#* } s, $parts"
    done
    ;;
  bottleneck)
    trap restore EXIT
    docker update --cpus 0.5 "$PROJECT-gateway-1" > /dev/null
    audit "bottleneck: gateway limited to 0.5 CPU"
    for rate in $RATES; do
      wait_until_gateway_is_quick
      probe "$GATEWAY$SEAT_PAGE" "$rate" 5 > /dev/null
      say "== the gateway at 0.5 CPU, public route, ${rate}/s for 15 s after a 5 s warm-up"
      probe "$GATEWAY$SEAT_PAGE" "$rate" 15 | tee -a "$report"
    done
    docker update --cpus 2 "$PROJECT-gateway-1" > /dev/null
    wait_until_gateway_is_quick
    say "== the only gateway stopped 5 s into a 20 s run at 500/s"
    probe "$GATEWAY$SEAT_PAGE" 500 20 > build/runs/stopped-probe.txt &
    prober=$!
    sleep 5
    "${compose[@]}" stop gateway > /dev/null 2>&1
    audit "bottleneck: gateway stopped"
    wait "$prober"
    tee -a "$report" < build/runs/stopped-probe.txt
    ;;
  rotate)
    old_token="$(token_for fan-42)"
    ./gradlew -q :issuer:keys --args="rotate $KEY_FILE" | tee -a "$report"
    "${compose[@]}" restart issuer > /dev/null 2>&1
    audit "rotate: issuer key rotated and the issuer restarted"
    wait_until_ready "$WAIT_SECONDS" > /dev/null
    new_token="$(token_for fan-42)"
    say "key ids in the published key set: $(curl -s http://127.0.0.1:21102/.well-known/jwks.json | grep -o '"kid":"[^"]*"' | tr '\n' ' ')"
    say "token signed with the new key -> $(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $new_token" "$GATEWAY/v1/holds?eventId=1")"
    say "token signed before the rotation -> $(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $old_token" "$GATEWAY/v1/holds?eventId=1")"
    ;;
esac
echo "report: $report"
