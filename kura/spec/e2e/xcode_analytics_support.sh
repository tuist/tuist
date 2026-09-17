# shellcheck shell=bash

setup_xcode_analytics() {
  xcode_chunking_enabled || return 0
  XCODE_ANALYTICS_PARSER="${KURA_E2E_XCODE_PARSER:-$KURA_PROJECT_ROOT/../server/native/xcactivitylog_nif/.build/release/xcactivitylog-parser}"
  [ -x "$XCODE_ANALYTICS_PARSER" ] || {
    echo 'Build xcactivitylog-parser or set KURA_E2E_XCODE_PARSER to its executable' >&2
    return 1
  }
  setup_xcode_chunking
}

xcode_output_ids() {
  local phase="$1" operation="$2"
  sed -nE "s/.*$operation [Cc][Aa][Ss] output [^ ]+: (0~[A-Za-z0-9+\/_=-]+).*/\1/p" \
    "$XCODE_TEST_ROOT/$phase.build.log" | sort -u
}

check_xcode_analytics() {
  local phase="$1" operation="$2" ids expected matched sizes size compressed
  ids="$XCODE_TEST_ROOT/$phase.output-ids"
  xcode_output_ids "$phase" "$operation" >"$ids" || return 1
  if [ "$operation" = using ]; then
    # Xcode creates the empty diagnostics node locally before restoring outputs.
    # Its REAPI frame is just the 8-byte header, so no download is recorded.
    local empty_node
    empty_node="$(sqlite3 "$XCODE_TEST_ROOT/base-compiled.analytics.db" \
      'SELECT n.key FROM nodes n JOIN cas_outputs c ON c.key = n.checksum WHERE c.size = 8;')" || return 1
    if [ -n "$empty_node" ]; then
      awk -v empty="$empty_node" '$0 != empty' "$ids" >"$ids.filtered" || return 1
      mv "$ids.filtered" "$ids" || return 1
    fi
  fi
  expected="$(wc -l <"$ids" | tr -d ' ')"
  [ "$expected" -gt 0 ] || { echo 'no compiler output remarks'; return 1; }
  # Exercise the same node -> checksum -> output join as CASMetadataReader,
  # using actual compiler identifiers rather than ids made by the writer.
  local query="SELECT count(*), coalesce(sum(c.size), 0), coalesce(sum(c.compressed_size), 0)
    FROM nodes n JOIN cas_outputs c ON c.key = n.checksum WHERE n.key IN ("
  query+="$(sed "s/^/'/; s/$/',/" "$ids")'' );"
  sizes="$(sqlite3 "$XCODE_TEST_ROOT/$phase.analytics.db" "$query")" || return 1
  IFS='|' read -r matched size compressed <<<"$sizes"
  if [ "$matched" != "$expected" ] || [ "$size" -le 0 ] || [ "$compressed" -le 0 ]; then
    echo "matched $matched/$expected compiler outputs; bytes=$size compressed=$compressed"
    return 1
  fi
  echo "matched all $matched compiler outputs; bytes=$size compressed=$compressed"

  if [ "$operation" = using ]; then
    # Swift's cache replay does not print a using remark for every restored file.
    # Verify all nonempty outputs from the original compilation in SQLite too.
    local original_ids
    original_ids="$(xcode_output_ids base-compiled uploaded | sed "s/^/'/; s/$/',/")''"
    sizes="$(sqlite3 "$XCODE_TEST_ROOT/$phase.analytics.db" "
      ATTACH '$XCODE_TEST_ROOT/base-compiled.analytics.db' AS original;
      SELECT count(c.key), count(*) FROM original.nodes source
      JOIN original.cas_outputs uploaded ON uploaded.key = source.checksum
      LEFT JOIN nodes n ON n.key = source.key
      LEFT JOIN cas_outputs c ON c.key = n.checksum
        AND c.size = uploaded.size AND c.compressed_size = uploaded.compressed_size
      WHERE source.key IN ($original_ids) AND uploaded.size > 8;")" || return 1
    IFS='|' read -r matched expected <<<"$sizes"
    [ "$expected" -gt 0 ] && [ "$matched" = "$expected" ] || {
      echo "download metadata matches $matched/$expected originally uploaded outputs"
      return 1
    }
    # The activity log retains Swift replay notes that stdout can omit.
    # Require the parsed report to contain every nonempty restored output.
    ids="$XCODE_TEST_ROOT/$phase.expected-output-ids"
    xcode_output_ids base-compiled uploaded | awk -v empty="$empty_node" '$0 != empty' >"$ids" || return 1
  fi

  local activitylog report report_operation snapshot
  activitylog="$(find "$XCODE_TEST_ROOT/$phase/Logs/Build" -name '*.xcactivitylog' -print -quit)"
  [ -n "$activitylog" ] || return 1
  report="$XCODE_TEST_ROOT/$phase.report.json"
  # Match UploadBuildRunService: checkpoint and ship only the main database,
  # without relying on a WAL file that is absent from uploaded build archives.
  snapshot="$XCODE_TEST_ROOT/$phase.report.db"
  sqlite3 "$XCODE_TEST_ROOT/$phase.analytics.db" 'PRAGMA wal_checkpoint(TRUNCATE);' >/dev/null || return 1
  cp "$XCODE_TEST_ROOT/$phase.analytics.db" "$snapshot" || return 1
  "$XCODE_ANALYTICS_PARSER" "$activitylog" "$snapshot" \
    "$XCODE_TEST_ROOT/no-legacy-metadata" "$report" "$XCODE_TEST_ROOT/$phase.steps.jsonl" || return 1
  report_operation=download
  [ "$operation" != uploaded ] || report_operation=upload
  jq -e --arg operation "$report_operation" --rawfile ids "$ids" '
    [.cas_outputs[] | select(.operation == $operation)] as $outputs |
    ($ids | split("\n") | map(select(length > 0))) as $expected |
    ($outputs | map(.node_id)) as $actual |
    (($expected - $actual) | length) == 0 and
    ($outputs | all(.size > 0 and .compressed_size > 0 and .duration >= 0))
  ' "$report" >/dev/null || { echo 'parsed report is missing transfer metadata'; return 1; }
}
