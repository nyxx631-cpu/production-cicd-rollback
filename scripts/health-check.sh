
#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://127.0.0.1:18080/}"

echo "Checking application: $URL"

for attempt in $(seq 1 12); do
    if curl --fail --silent --show-error "$URL" >/dev/null; then
        echo "Health check passed."
        exit 0
    fi

    echo "Attempt $attempt failed; retrying..."
    sleep 5
done

echo "Health check failed."
exit 1
