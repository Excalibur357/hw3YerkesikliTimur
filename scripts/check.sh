#!/bin/bash
set -euo pipefail

BASE=http://localhost:8080

wait_ready() {
    for i in {1..30}; do
        if curl -fsS "$BASE/readyz" > /dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

get_count() {
    curl -fsS "$BASE/" | python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])'
}

cleanup() {
    docker compose start redis > /dev/null 2>&1 || true
}

trap cleanup EXIT

echo "Starting services"
docker compose up -d --build
wait_ready

echo "Checking HTTP"
test "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/healthz")" = "200"
test "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/readyz")" = "200"

before=$(get_count)

echo "Checking increment"
curl -fsS -X POST "$BASE/increment" > /dev/null
after=$(get_count)
test "$after" -eq "$((before + 1))"

echo "Checking persistence"
docker compose down
docker compose up -d
wait_ready
test "$(get_count)" -eq "$after"

echo "Checking Redis failure"
docker compose stop redis
test "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/healthz")" = "200"
test "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/readyz")" = "503"
test "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/")" = "503"

echo "Checking recovery"
docker compose start redis
wait_ready
test "$(get_count)" -eq "$after"

echo "Creating backup"
mkdir -p backups
docker compose exec -T redis redis-cli --rdb /data/backup.rdb
docker compose cp redis:/data/backup.rdb backups/backup.rdb
test -s backups/backup.rdb

echo "All checks passed"