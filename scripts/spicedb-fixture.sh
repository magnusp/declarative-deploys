#!/usr/bin/env bash
# Loads schema.zed and relationships.txt into SpiceDB.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="${SCRIPT_DIR}/../fixtures/spicedb"

SPICEDB_ENDPOINT="${SPICEDB_ENDPOINT:-http://127.0.0.1:8443}"
AUTH_HEADER="Authorization: Bearer showcase-authz-key"

write_schema() {
  local schema_file="${1:-${FIXTURES_DIR}/schema.zed}"
  if [ ! -f "$schema_file" ]; then
    echo "Error: schema file '${schema_file}' not found." >&2
    exit 1
  fi

  echo "==> Writing schema from ${schema_file}..."
  local payload
  payload=$(jq -n --rawfile schema "$schema_file" '{schema: $schema}')

  curl -s -f -X POST "${SPICEDB_ENDPOINT}/v1/schema/write" \
    -H "Content-Type: application/json" \
    -H "${AUTH_HEADER}" \
    -d "$payload" | jq .
  echo "✔ Schema applied successfully."
}

write_relationships() {
  local rel_file="${1:-${FIXTURES_DIR}/relationships.txt}"
  if [ ! -f "$rel_file" ]; then
    echo "Error: relationships file '${rel_file}' not found." >&2
    exit 1
  fi

  echo "==> Writing relationships from ${rel_file}..."
  local updates="[]"

  while IFS= read -r line || [ -n "$line" ]; do
    # Trim whitespace and strip comments
    line=$(echo "$line" | sed 's/#.*//' | xargs)
    [ -z "$line" ] && continue

    # Parse tuple: resource_type:resource_id#relation@subject_type:subject_id[#sub_relation]
    if [[ "$line" =~ ^([^:]+):([^#]+)#([^@]+)@([^:#]+):([^#]+)(#(.+))?$ ]]; then
      local res_type="${BASH_REMATCH[1]}"
      local res_id="${BASH_REMATCH[2]}"
      local relation="${BASH_REMATCH[3]}"
      local subj_type="${BASH_REMATCH[4]}"
      local subj_id="${BASH_REMATCH[5]}"
      local subj_rel="${BASH_REMATCH[7]:-}"

      local update_json
      if [ -n "$subj_rel" ]; then
        update_json=$(jq -n \
          --arg rt "$res_type" --arg ri "$res_id" --arg rel "$relation" \
          --arg st "$subj_type" --arg si "$subj_id" --arg sr "$subj_rel" \
          '{
            operation: "OPERATION_TOUCH",
            relationship: {
              resource: { objectType: $rt, objectId: $ri },
              relation: $rel,
              subject: { object: { objectType: $st, objectId: $si }, optionalRelation: $sr }
            }
          }')
      else
        update_json=$(jq -n \
          --arg rt "$res_type" --arg ri "$res_id" --arg rel "$relation" \
          --arg st "$subj_type" --arg si "$subj_id" \
          '{
            operation: "OPERATION_TOUCH",
            relationship: {
              resource: { objectType: $rt, objectId: $ri },
              relation: $rel,
              subject: { object: { objectType: $st, objectId: $si } }
            }
          }')
      fi

      updates=$(echo "$updates" | jq --argjson u "$update_json" '. += [$u]')
    else
      echo "Warning: skipping invalid tuple line: $line" >&2
    fi
  done < "$rel_file"

  curl -s -f -X POST "${SPICEDB_ENDPOINT}/v1/relationships/write" \
    -H "Content-Type: application/json" \
    -H "${AUTH_HEADER}" \
    -d "{\"updates\": ${updates}}" | jq .
  echo "✔ Relationships applied successfully."
}

apply_fixtures() {
  write_schema "${1:-${FIXTURES_DIR}/schema.zed}"
  write_relationships "${2:-${FIXTURES_DIR}/relationships.txt}"
}

check_permission() {
  local user="$1"
  local service="${2:-apps-archetype-backend-demo}"
  echo "==> Checking 'deploy' permission for user '${user}' on service '${service}'..."
  curl -s -X POST "${SPICEDB_ENDPOINT}/v1/permissions/check" \
    -H "Content-Type: application/json" \
    -H "${AUTH_HEADER}" \
    -d "{
      \"consistency\": { \"fullyConsistent\": true },
      \"resource\": { \"objectType\": \"service\", \"objectId\": \"${service}\" },
      \"permission\": \"deploy\",
      \"subject\": { \"object\": { \"objectType\": \"user\", \"objectId\": \"${user}\" } }
    }" | jq .
}

usage() {
  echo "Usage: $0 {apply [schema_path] [relationships_path]|schema [schema_path]|relationships [relationships_path]|check <user> [service]}"
  echo ""
  echo "Examples:"
  echo "  $0 apply                                   # Apply default schema.zed and relationships.txt"
  echo "  $0 check magnusp                           # Check if user magnusp can deploy apps-archetype-backend-demo"
  echo "  $0 check unauthorized-dev                  # Check unauthorized user"
  exit 1
}

case "${1:-}" in
  apply)
    apply_fixtures "${2:-}" "${3:-}"
    ;;
  schema)
    write_schema "${2:-}"
    ;;
  relationships)
    write_relationships "${2:-}"
    ;;
  check)
    [ $# -ge 2 ] || usage
    check_permission "$2" "${3:-apps-archetype-backend-demo}"
    ;;
  *)
    usage
    ;;
esac
