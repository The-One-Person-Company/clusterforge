#!/bin/bash
set -euo pipefail

# Load .env variables
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Output file
OUT=pgsql-init
> "$OUT"

# Find all *_USER and *_PASSWORD pairs
users=()
passwords=()
databases=()

# Collect all *_USER
for var in $(env | grep -E '^[A-Za-z0-9_]+_USER=' | cut -d= -f1); do
  users+=("$var")
  # Try to find a matching password
  pw_var="${var%_USER}_PASSWORD"
  if [ -n "${!pw_var:-}" ]; then
    passwords+=("$pw_var")
  else
    passwords+=("")
  fi
  # Try to find a matching DB
  db_var="${var%_USER}_DB"
  if [ -n "${!db_var:-}" ]; then
    databases+=("$db_var")
  else
    databases+=("")
  fi
  
  # Also check for DB variable with just _DB (for root users)
  if [ -z "${!db_var:-}" ]; then
    db_var2="${var/_USER/}_DB"
    if [ -n "${!db_var2:-}" ]; then
      databases[-1]="$db_var2"
    fi
  fi

done

# Find root user (first *_USER in .env)
ROOT_USER="${!users[0]}"

for i in "${!users[@]}"; do
  USER_VAR="${users[$i]}"
  PW_VAR="${passwords[$i]}"
  DB_VAR="${databases[$i]}"
  USER="${!USER_VAR}"
  PW="${!PW_VAR:-password}"
  DB="${!DB_VAR:-public}"

  cat >> "$OUT" <<EOF
CREATE USER "$USER" WITH PASSWORD '$PW';
GRANT ALL PRIVILEGES ON DATABASE $DB TO "$ROOT_USER";
GRANT ALL PRIVILEGES ON DATABASE $DB TO "$USER";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "$USER";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "$USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "$USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "$USER";

EOF
done

echo "Generated $OUT with users: ${users[*]} and databases: ${databases[*]}" 