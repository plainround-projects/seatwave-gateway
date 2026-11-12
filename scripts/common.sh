#!/usr/bin/env bash
# Shared by scripts/stack.sh and scripts/lab.sh: the project's fixed name, the Docker check, the
# audit line and the readiness question. Sourced, never run on its own. Adapted from the Module 10
# project's scripts/common.sh.

readonly PROJECT="seatwave-gateway"
# How long "docker info" may take before Docker counts as not running.
readonly DOCKER_TIMEOUT_SECONDS=10
readonly KEY_FILE="build/keys/issuer-keys.json"
compose=(docker compose -p "$PROJECT")

# Check before: Docker must answer, within a bound, or nothing is done.
docker_must_answer() {
  docker info --format '{{.ServerVersion}}' > /dev/null 2>&1 &
  local checker=$!
  local waited
  for (( waited = 0; waited < DOCKER_TIMEOUT_SECONDS; waited++ )); do
    if ! kill -0 "$checker" 2> /dev/null; then
      if wait "$checker"; then
        return 0
      fi
      break
    fi
    sleep 1
  done
  kill "$checker" 2> /dev/null || true
  echo "Docker is not running (or does not answer within ${DOCKER_TIMEOUT_SECONDS} s)." >&2
  echo "Start Docker Desktop and run this again; nothing was started or stopped." >&2
  exit 1
}

audit() {
  mkdir -p build/stack
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $1" >> build/stack/audit.log
}

# The gateway answers health on its management port, the issuer serves its key set, and a catalog
# read through the gateway reaches the catalog: then every program of the stack is up.
stack_ready() {
  curl -s --max-time 2 http://127.0.0.1:21101/actuator/health 2> /dev/null | grep -q '"status":"UP"' \
    && curl -s --fail --max-time 2 -o /dev/null http://127.0.0.1:21102/.well-known/jwks.json \
    && curl -s --fail --max-time 2 -o /dev/null http://127.0.0.1:21100/v1/events/1
}

# Waits until the stack is ready again, at most the given number of seconds.
wait_until_ready() {
  local limit="$1"
  local waited
  for (( waited = 0; waited < limit; waited++ )); do
    if stack_ready; then
      echo "stack is up after ${waited} s: gateway, issuer and catalog answer"
      return 0
    fi
    sleep 1
  done
  echo "the stack was not ready within ${limit} s" >&2
  "${compose[@]}" logs --tail 20 >&2
  return 1
}
