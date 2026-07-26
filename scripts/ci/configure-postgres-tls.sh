#!/usr/bin/env bash
set -euo pipefail

# Never allow a caller's shell tracing to disclose CI credentials.
set +x

container_id="${1:-${POSTGRES_CONTAINER_ID:-}}"
postgres_user="${2:-${POSTGRES_USER:-}}"
postgres_database="${3:-${POSTGRES_DB:-}}"
postgres_password="${POSTGRES_PASSWORD:-}"

fail() {
  printf '%s\n' "PostgreSQL TLS setup failed: $1" >&2
  exit 1
}

[[ "$container_id" =~ ^[a-fA-F0-9]{12,64}$ ]] || fail "invalid service container id"
[[ "$postgres_user" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || fail "invalid CI database user"
[[ "$postgres_database" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || fail "invalid CI database name"
[[ -n "$postgres_password" && "$postgres_password" != *$'\n'* ]] || fail "CI database password is missing or invalid"

temporary_directory="$(mktemp -d)"
trap 'rm -rf -- "$temporary_directory"' EXIT

cat >"$temporary_directory/server.cnf" <<'EOF'
[req]
distinguished_name = subject
prompt = no
req_extensions = server_extensions

[subject]
CN = postgres

[server_extensions]
subjectAltName = @subject_alt_names
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth

[subject_alt_names]
DNS.1 = localhost
DNS.2 = postgres
IP.1 = 127.0.0.1
EOF

openssl req \
  -x509 -newkey rsa:2048 -nodes -sha256 -days 1 \
  -subj '/CN=Calories Tracking CI CA' \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign' \
  -addext 'subjectKeyIdentifier=hash' \
  -keyout "$temporary_directory/ca.key" \
  -out "$temporary_directory/ca.crt" \
  >/dev/null 2>&1

openssl req \
  -newkey rsa:2048 -nodes -sha256 \
  -config "$temporary_directory/server.cnf" \
  -keyout "$temporary_directory/server.key" \
  -out "$temporary_directory/server.csr" \
  >/dev/null 2>&1

openssl x509 \
  -req -sha256 -days 1 \
  -in "$temporary_directory/server.csr" \
  -CA "$temporary_directory/ca.crt" \
  -CAkey "$temporary_directory/ca.key" \
  -CAcreateserial \
  -extfile "$temporary_directory/server.cnf" \
  -extensions server_extensions \
  -out "$temporary_directory/server.crt" \
  >/dev/null 2>&1

docker cp "$temporary_directory/ca.crt" "$container_id:/var/lib/postgresql/data/ci-ca.crt" >/dev/null
docker cp "$temporary_directory/server.crt" "$container_id:/var/lib/postgresql/data/ci-server.crt" >/dev/null
docker cp "$temporary_directory/server.key" "$container_id:/var/lib/postgresql/data/ci-server.key" >/dev/null

docker exec --user root "$container_id" sh -ceu "
  data_directory=\"\${PGDATA:-/var/lib/postgresql/data}\"
  chown postgres:postgres \
    \"\$data_directory/ci-ca.crt\" \
    \"\$data_directory/ci-server.crt\" \
    \"\$data_directory/ci-server.key\"
  chmod 0644 \"\$data_directory/ci-ca.crt\" \"\$data_directory/ci-server.crt\"
  chmod 0600 \"\$data_directory/ci-server.key\"
  printf \"%s\\n\" \
    \"ssl = on\" \
    \"ssl_ca_file = '\$data_directory/ci-ca.crt'\" \
    \"ssl_cert_file = '\$data_directory/ci-server.crt'\" \
    \"ssl_key_file = '\$data_directory/ci-server.key'\" \
    >>\"\$data_directory/postgresql.conf\"
" >/dev/null

docker restart "$container_id" >/dev/null

ready=false
for _ in $(seq 1 60); do
  if docker exec "$container_id" pg_isready \
      --host localhost \
      --port 5432 \
      --username "$postgres_user" \
      --dbname "$postgres_database" \
      >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
[[ "$ready" == true ]] || fail "service did not become ready after TLS restart"

verification_output="$temporary_directory/postgres-verification.txt"
docker exec \
  --env "PGPASSWORD=$postgres_password" \
  "$container_id" \
  psql \
    "host=localhost port=5432 user=$postgres_user dbname=$postgres_database sslmode=verify-full sslrootcert=/var/lib/postgresql/data/ci-ca.crt channel_binding=require" \
    --no-psqlrc \
    --tuples-only \
    --no-align \
    --set ON_ERROR_STOP=1 \
    --command "SELECT CASE WHEN ssl THEN 'tls-ok' ELSE 'tls-missing' END FROM pg_catalog.pg_stat_ssl WHERE pid = pg_backend_pid(); SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_hba_file_rules WHERE type IN ('host', 'hostssl') AND auth_method = 'scram-sha-256' AND error IS NULL) THEN 'scram-ok' ELSE 'scram-missing' END;" \
    >"$verification_output" 2>/dev/null

grep -Fxq 'tls-ok' "$verification_output" || fail "TLS verification did not succeed"
grep -Fxq 'scram-ok' "$verification_output" || fail "SCRAM verification did not succeed"

printf '%s\n' 'PostgreSQL CI TLS, SCRAM, and channel binding verified.'
