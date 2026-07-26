#!/usr/bin/env bash
set -euo pipefail

# The script handles generated credentials, so shell tracing is never permitted.
set +x

image="${1:-${CONTAINER_IMAGE:-}}"
database_host="${2:-${POSTGRES_HOST:-host.docker.internal}}"
database_port="${3:-${POSTGRES_PORT:-5432}}"
database_user="${POSTGRES_USER:-}"
database_name="${POSTGRES_DB:-}"
database_password="${POSTGRES_PASSWORD:-}"
database_network="${POSTGRES_DOCKER_NETWORK:-}"
application_port="${APPLICATION_PORT:-18080}"

fail() {
  printf '%s\n' "Container verification failed: $1" >&2
  exit 1
}

[[ -n "$image" && "$image" != *$'\n'* ]] || fail "container image is missing or invalid"
[[ "$database_host" =~ ^[A-Za-z0-9_.-]+$ ]] || fail "database host is invalid"
[[ "$database_port" =~ ^[0-9]{1,5}$ ]] || fail "database port is invalid"
(( database_port >= 1 && database_port <= 65535 )) || fail "database port is outside the valid range"
[[ "$database_user" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || fail "database user is invalid"
[[ "$database_name" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || fail "database name is invalid"
[[ -n "$database_password" && "$database_password" != *$'\n'* && "$database_password" != *';'* ]] || fail "database password is missing or invalid"
[[ "$application_port" =~ ^[0-9]{1,5}$ && "$application_port" != "8080" ]] || fail "application port must be a valid non-default port"
(( application_port >= 1024 && application_port <= 65535 )) || fail "application port is outside the allowed range"

declare -a network_arguments
if [[ -n "$database_network" ]]; then
  [[ "$database_network" =~ ^[A-Za-z0-9_.:-]+$ ]] || fail "database Docker network is invalid"
  docker network inspect "$database_network" >/dev/null 2>&1 || fail "database Docker network does not exist"
  network_arguments=(--network "$database_network")
else
  [[ "$database_host" == "host.docker.internal" ]] || fail "host fallback requires host.docker.internal"
  network_arguments=(--add-host host.docker.internal:host-gateway)
fi

temporary_directory="$(mktemp -d)"
declare -a managed_containers=()

container_exists() {
  docker inspect "$1" >/dev/null 2>&1
}

cleanup() {
  local container
  for container in "${managed_containers[@]}"; do
    if container_exists "$container"; then
      docker logs "$container" >"$temporary_directory/cleanup-${container}.log" 2>&1 || true
      docker rm --force "$container" >/dev/null 2>&1 || true
    fi
  done
  rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

jwt_key="$(openssl rand -hex 32)"
gemini_key="$(openssl rand -hex 24)"
weak_jwt_key="weak-ci-jwt"
database_connection="Host=${database_host};Port=${database_port};Database=${database_name};Username=${database_user};Password=${database_password};SSL Mode=Require;Trust Server Certificate=true;Channel Binding=Require;Include Error Detail=false;Log Parameters=false;Persist Security Info=false"
insecure_tls_connection="Host=${database_host};Port=${database_port};Database=${database_name};Username=${database_user};Password=${database_password};SSL Mode=Disable;Channel Binding=Require;Include Error Detail=false;Log Parameters=false;Persist Security Info=false"
insecure_channel_binding_connection="Host=${database_host};Port=${database_port};Database=${database_name};Username=${database_user};Password=${database_password};SSL Mode=Require;Trust Server Certificate=true;Channel Binding=Disable;Include Error Detail=false;Log Parameters=false;Persist Security Info=false"

assert_no_credential_sentinels() {
  local log_file="$1"
  local sentinel
  for sentinel in "$jwt_key" "$gemini_key" "$weak_jwt_key" "$database_password"; do
    if grep --fixed-strings --quiet -- "$sentinel" "$log_file"; then
      fail "a generated credential sentinel appeared in captured logs"
    fi
  done
}

verify_image_contract() {
  local entrypoint stop_signal exposed_ports
  entrypoint="$(docker image inspect --format '{{json .Config.Entrypoint}}' "$image")"
  stop_signal="$(docker image inspect --format '{{.Config.StopSignal}}' "$image")"
  exposed_ports="$(docker image inspect --format '{{json .Config.ExposedPorts}}' "$image")"

  [[ "$entrypoint" == '["sh","-c","exec dotnet CaloriesTracking.Api.dll --urls http://0.0.0.0:${PORT:-8080}"]' ]] || fail "image entrypoint does not preserve the exec/PORT contract"
  [[ "$stop_signal" == "SIGTERM" ]] || fail "image stop signal is not SIGTERM"
  [[ "$exposed_ports" == *'"8080/tcp"'* ]] || fail "image does not expose the documented default port"

  docker run --rm "${network_arguments[@]}" --entrypoint sh "$image" -ceu \
    'test -s /app/SeedData/usda_calorie_dataset.csv' \
    >/dev/null 2>&1 || fail "published USDA seed CSV is missing or empty"
}

base_environment() {
  local connection_string="$1"
  BASE_ENVIRONMENT=(
    --env 'ASPNETCORE_ENVIRONMENT=Production'
    --env "PORT=${application_port}"
    --env "ConnectionStrings__DefaultConnection=${connection_string}"
    --env "GEMINI__APIKEY=${gemini_key}"
    --env 'HOSTING__BEHINDTLSTERMINATINGPROXY=true'
    --env 'SEEDING__ENABLED=false'
  )
}

expect_startup_failure() {
  local case_name="$1"
  local connection_string="$2"
  local jwt_mode="$3"
  local cors_mode="$4"
  local container="calories-ci-${case_name}-${RANDOM}-$$"
  local log_file="$temporary_directory/${case_name}.log"
  local running exit_code
  local -a environment

  base_environment "$connection_string"
  environment=("${BASE_ENVIRONMENT[@]}")
  if [[ "$jwt_mode" == "valid" ]]; then
    environment+=(--env "JWT__KEY=${jwt_key}")
  elif [[ "$jwt_mode" == "weak" ]]; then
    environment+=(--env "JWT__KEY=${weak_jwt_key}")
  fi
  if [[ "$cors_mode" == "present" ]]; then
    environment+=(--env 'CORS__ALLOWEDORIGINS__0=https://ci.example.invalid')
  fi

  docker run \
    --detach \
    --name "$container" \
    "${network_arguments[@]}" \
    "${environment[@]}" \
    "$image" \
    >/dev/null
  managed_containers+=("$container")

  running=true
  for _ in $(seq 1 30); do
    running="$(docker inspect --format '{{.State.Running}}' "$container")"
    [[ "$running" == "false" ]] && break
    sleep 1
  done

  docker logs "$container" >"$log_file" 2>&1 || true
  assert_no_credential_sentinels "$log_file"
  [[ "$running" == "false" ]] || fail "the ${case_name} expected-failure container kept running"

  exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$container")"
  [[ "$exit_code" != "0" ]] || fail "the ${case_name} expected-failure container exited successfully"
  docker rm "$container" >/dev/null
}

verify_healthy_container() {
  local container="calories-ci-healthy-${RANDOM}-$$"
  local log_file="$temporary_directory/healthy.log"
  local response_body="$temporary_directory/response.json"
  local status_code="" binding exit_code oom_killed
  local -a environment

  base_environment "$database_connection"
  environment=(
    "${BASE_ENVIRONMENT[@]}"
    --env "JWT__KEY=${jwt_key}"
    --env 'CORS__ALLOWEDORIGINS__0=https://ci.example.invalid'
  )

  docker run \
    --detach \
    --name "$container" \
    "${network_arguments[@]}" \
    --publish "127.0.0.1:${application_port}:${application_port}" \
    "${environment[@]}" \
    "$image" \
    >/dev/null
  managed_containers+=("$container")

  for _ in $(seq 1 90); do
    if [[ "$(docker inspect --format '{{.State.Running}}' "$container")" != "true" ]]; then
      break
    fi
    status_code="$(curl --silent --show-error --max-time 3 \
      --output "$response_body" \
      --write-out '%{http_code}' \
      "http://127.0.0.1:${application_port}/health/live" 2>/dev/null || true)"
    if [[ "$status_code" == "200" ]] && [[ "$(<"$response_body")" == '{"status":"ok"}' ]]; then
      break
    fi
    sleep 1
  done

  docker logs "$container" >"$log_file" 2>&1 || true
  assert_no_credential_sentinels "$log_file"
  [[ "$status_code" == "200" ]] || fail "liveness endpoint did not return HTTP 200"
  [[ "$(<"$response_body")" == '{"status":"ok"}' ]] || fail "liveness endpoint returned an unexpected body"

  status_code="$(curl --silent --show-error --max-time 5 \
    --output "$response_body" \
    --write-out '%{http_code}' \
    "http://127.0.0.1:${application_port}/health" 2>/dev/null || true)"
  [[ "$status_code" == "200" ]] || fail "readiness endpoint did not return HTTP 200"
  [[ "$(<"$response_body")" == '{"status":"ok"}' ]] || fail "readiness endpoint returned an unexpected body"

  binding="$(docker port "$container" "${application_port}/tcp")"
  [[ "$binding" == "127.0.0.1:${application_port}" ]] || fail "application port is not bound only to loopback"

  docker stop --time 10 "$container" >/dev/null
  docker logs "$container" >"$log_file" 2>&1 || true
  assert_no_credential_sentinels "$log_file"
  exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$container")"
  oom_killed="$(docker inspect --format '{{.State.OOMKilled}}' "$container")"
  [[ "$exit_code" == "0" && "$oom_killed" == "false" ]] || fail "container did not stop gracefully after SIGTERM"
  docker rm "$container" >/dev/null
}

verify_image_contract
expect_startup_failure 'missing-jwt' "$database_connection" 'missing' 'present'
expect_startup_failure 'weak-jwt' "$database_connection" 'weak' 'present'
expect_startup_failure 'missing-cors' "$database_connection" 'valid' 'missing'
expect_startup_failure 'insecure-postgres-tls' "$insecure_tls_connection" 'valid' 'present'
expect_startup_failure 'insecure-postgres-channel-binding' "$insecure_channel_binding_connection" 'valid' 'present'
verify_healthy_container

printf '%s\n' 'Container image contract, fail-fast cases, health checks, and graceful shutdown verified.'
