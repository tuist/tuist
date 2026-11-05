defmodule Pulse.MCP.Tools do
  @moduledoc """
  Registry of query and capability-scoped alert-management MCP tools.

  Query tools are read-only against `Pulse.Storage`. Alert management uses
  separately configured principals/capabilities; infrastructure remediation
  remains outside Pulse by design — see `docs/architecture.md`.
  Calls validate the schema vocabulary used by this registry before execution.
  Unknown properties remain allowed unless a schema explicitly closes them;
  optional null properties retain omitted-field defaults.
  Read-only annotations describe tool behavior and do not replace tenant
  authorization, which every tool enforces before querying storage.
  """

  alias Pulse.Alerting.Tools
  alias Pulse.Auth
  alias Pulse.Codec.NIF
  alias Pulse.Errors.Projection
  alias Pulse.LogQL.AST
  alias Pulse.LogQL.Envelope
  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.Parser
  alias Pulse.MCP.Arguments
  alias Pulse.OTLP.Traces
  alias Pulse.PromQL.Discovery
  alias Pulse.QueryRunner
  alias Pulse.Record.Log
  alias Pulse.Record.MetricSample
  alias Pulse.Record.Span
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Traces.Metrics
  alias Pulse.Traces.RegexFilters
  alias Pulse.Traces.Selector
  alias Pulse.Traces.TempoDiscovery
  alias Pulse.Traces.TempoSearch

  @timestamp_schema %{
    "type" => "integer",
    "minimum" => -9_223_372_036_854_775_808,
    "maximum" => 9_223_372_036_854_775_807
  }

  @duration_schema Map.put(@timestamp_schema, "minimum", 0)
  @trace_fields Enum.map(Map.keys(%Span{}) -- [:__struct__], &Atom.to_string/1) ++ ["duration_ns"]

  @read_only_annotations %{
    "readOnlyHint" => true,
    "destructiveHint" => false,
    "idempotentHint" => true,
    "openWorldHint" => false
  }

  @reliability_tools (for name <- ~w(list_reliability_signals list_reliability_changes get_reliability_signal) do
                        properties =
                          if name == "get_reliability_signal" do
                            %{"id" => %{"type" => "string", "minLength" => 1, "maxLength" => 64}}
                          else
                            %{
                              "cursor" => %{"type" => "string", "maxLength" => 4096},
                              "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
                            }
                          end

                        %{
                          "name" => name,
                          "annotations" => @read_only_annotations,
                          "description" =>
                            "Experimental opt-in periodic cross-signal assessments. Measured evidence and model verdicts are separate; missing/deferred/unknown is not health. Inspect window_end_ns, assessments, budgets and investigation statuses. Changes retain 128 events; persist next_cursor and deduplicate change_id, resetting below replay_floor. Signal-list cursors reset on publication. No arbitrary model queries or remediation.",
                          "inputSchema" => %{
                            "type" => "object",
                            "additionalProperties" => false,
                            "properties" => Map.put(properties, "tenant", %{"type" => "string", "minLength" => 1}),
                            "required" => if(name == "get_reliability_signal", do: ["tenant", "id"], else: ["tenant"])
                          }
                        }
                      end)

  @error_schema %{
    "type" => "object",
    "properties" => %{
      "tenant" => %{"type" => "string", "minLength" => 1},
      "project" => %{"type" => "string"},
      "service" => %{"type" => "string"},
      "environment" => %{"type" => "string"},
      "release" => %{"type" => "string"},
      "issue_id" => %{"type" => "string"},
      "event_id" => %{"type" => "string"},
      "start_ts_ns" => Map.put(@timestamp_schema, "minimum", 0),
      "end_ts_ns" => Map.put(@timestamp_schema, "minimum", 0),
      "cursor" => %{"type" => "string", "minLength" => 1, "description" => "Opaque continuation, at most 4096 bytes."},
      "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 5000}
    },
    "required" => ["tenant", "start_ts_ns", "end_ts_ns"]
  }

  @error_index_schema %{
    "type" => "object",
    "properties" => %{
      "tenant" => %{"type" => "string", "minLength" => 1},
      "project" => %{"type" => "string", "minLength" => 1},
      "cursor" => %{"type" => "string", "minLength" => 1},
      "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
    },
    "required" => ["tenant", "project"]
  }

  @tools [
    %{
      "name" => "discover_trace_tags",
      "annotations" => @read_only_annotations,
      "description" =>
        "Experimental default-off complete retained resource/span/instrumentation/event/link attribute names. Requires PULSE_TEMPO_SEARCH_ENABLED. Omit scope or use none for one complete combined five-scope scan plus static intrinsic suggestions; individual attribute namespaces remain distinct. Optional paired positive start_ts_ns/end_ts_ns select retention-visible immutable segment envelopes inclusively, not individual span starts; compaction can broaden dictionaries. Headers for every retained segment still consume row/provider budgets, no indexed-plan improvement. Adapters must implement explicit window-aware execution; flat reference adapters reject rather than silently ignoring windows. No intrinsic predicates. Default names include required service.name for any visible parent even without a filter/original attr, and v2 adds static intrinsic suggestions even when empty. Default names share one 2000000-work and 5000-pair dictionary budget across all five scopes, reserving 25 intrinsic entries; this is stricter than five independent scoped queries. Scope-none values use a distinct three-owner parent-filtered contract, not this five-scope name union. Static suggestions are not stored-data proof; unlike intrinsic-only vocabulary, default names fail whole on storage/legacy/budget errors. Optional query uses the same bounded resource/span original-string equality/anchored-regex AND grammar as value discovery, all on one parent. Filtered names are hints: generic keys come from matching parents, but promoted-column names come from all selected retention-visible context even under impossible filters; required service.name appears if any visible parent exists even without an original attribute. They are NOT proof of matching key presence; values never use this shortcut. Fixed standard promotions only; dynamic dedicated-column mapping is unsupported. Pulse retains matching shared keys that upstream iterators can omit, a conservative complete extension rather than exact omission parity. Instrumentation attributes are not scope name/version, and event/link attributes never become intrinsic fields. Every retained raw header row is charged, and selected payload rows validate under shared admission/provider budgets, 1000000 rows, 2000000 owner-plus-attribute work units per scan attempt before filtering (flat scope capacity shrinks with attribute count), 5000 distinct scope/name pairs (default includes its 25 static reservations) and independent 1MiB retained dictionary/result ceilings; scope strings now count toward name dictionary bytes. Any selected legacy unknown or budget failure rejects the whole result. No truncation or exporter-completeness claim. Explicit intrinsic scope instead returns static Tempo protocol vocabulary with no storage reads, not proof of stored fields or support for all advertised TraceQL syntax; filters remain unsupported.",
      "inputSchema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "tenant" => %{"type" => "string", "minLength" => 1},
          "scope" => %{
            "type" => "string",
            "enum" => ["none", "resource", "span", "instrumentation", "event", "link", "intrinsic"]
          },
          "query" => %{"type" => "string", "maxLength" => 16_384},
          "start_ts_ns" => %{"type" => "integer", "minimum" => 1, "maximum" => 9_223_372_036_854_775_807},
          "end_ts_ns" => %{"type" => "integer", "minimum" => 1, "maximum" => 9_223_372_036_854_775_807}
        },
        "required" => ["tenant"]
      }
    },
    %{
      "name" => "discover_trace_tag_values",
      "annotations" => @read_only_annotations,
      "description" =>
        "Experimental default-off complete retained typed values for an explicit resource/span/instrumentation/event/link attribute. Original string/int64/bool/float values; a matching targeted bytes/array/kvlist/empty value rejects the complete result, never coerces or drops types. Absent tags return an empty list. Explicit scope none discovers resource/span/instrumentation originals, not event/link. Optional resource/span original-string AND filters select one parent, then union all three owners' typed values, which need not individually match the literal/regex. This is a complete filtered extension, NOT Tempo's ignored-filter fast path. Same-key equality across resource/span rejects, regex allowed; no instrumentation/nested predicates. All three owners/attrs charge before selection, selected legacy/corruption fail even on nonmatches, complex target values fail only matching parents. Old unscoped/3 callbacks cannot receive filters: explicit query-aware /4 or bounded reference required. Windowed filtered-none requires NEW explicit /6, never an old /7 window callback. Requires discovery11 matching app/native participants. root.name/root.service.name targets remain unsupported in none scope. Floats use TraceQL shortest-roundtrip Go-style text, preserving signed zero and float identity. Optional query is an AND selector of original resource/span strings using equality or fully anchored regex, all predicates on the same parent span; nested event/link owners contribute only their own attributes, without flattening into span attributes. Same-target equality (Tempo's unproven literal shortcut), malformed/default-fallback queries, structural/intrinsic operators and exporter completeness are unsupported. Optional paired positive start_ts_ns/end_ts_ns select whole retention-visible segment envelopes, not strict span time filters; dictionaries can change with compaction. Raw header rows/provider costs remain charged for every retained source, with explicit window-aware adapter support or rejection, no indexed-planning claim. Scans retained headers and selected rows under shared provider/admission budgets, 1000000 rows, 2000000 owner-plus-attribute work units per scan attempt before filtering (flat scope capacity shrinks with attribute count; trace_discovery_work_limit), 5000 distinct typed values and independent 1MiB dictionary/result ceilings. Requires PULSE_TEMPO_SEARCH_ENABLED; selected legacy unknown fails. Intrinsic scope provides static keyword enums status/span:status and kind/span:kind, plus empty duration/span:duration/traceDuration vocabularies. These do not prove stored values, ignore no filters (nonempty filters reject), and perform no storage I/O. Stored intrinsic strings name/span:name, statusMessage/span:statusMessage, instrumentation:name/instrumentation:version and event:name also accept the same bounded parent-string filters, with normal storage/legacy/scan/work budgets and explicit query-aware adapters; results include all matching strings that upstream distinct iterators may omit, a disclosed complete extension rather than omission parity; these DO read storage and errors fail whole. Missing protobuf string fields use their effective empty default, not original-attribute inference. event:timeSinceStart additionally returns exact signed INTEGER NANOSECONDS, type int not duration strings: source event time minus its own parent's source start. Ingest stores protobuf default0 explicitly, which can yield negative offsets; missing/null/noninteger/out-of-range stored times fail, never guessed0. No event invents no value. Values sort lexically not numerically; equal offsets coalesce in both versions, V1 string-list not provenance. Offsets are high-cardinality: broad retained queries commonly exceed5000 and fail422, never sample/truncate. Use selective parent filters/narrow source windows but whole-source routing/compaction can still overflow, and filters do not reduce work/provider costs. Same-parent string filters return a complete extension, NOT Tempo's empty filtered event-time path. All requested event timestamps validate even on nonmatches; parent+every event+attrs charge before filtering. Requires separate event-time /4 callback or bounded reference and dedicated window /6, never old string /4 or generic window /7. Canonical rootName/trace:rootName and rootServiceName/trace:rootService now return complete retained root strings: any matching parent selects its trace, then recover all retained candidate context, even outside source windows/predicates. Root must be parentless without original-string child_of links. Missing roots or missing original string service.name fail409 whole; differing root IDs/tuples or same-ID contradictory root classification fail409. Do not infer unknown_service/defaults or choose arbitrary roots. Empty proven strings are values. In-flight children-before-root and retention-straddling traces make broad/recent dictionaries commonly fail; filters/older windows help without completeness guarantees, never skip incomplete traces. Whole retained S3 inputs must fit1024 objects/32MiB compressed/1M raw rows regardless of window/matches, no service/ID planner. Replay decodes all sources locally without more GETs; noncandidate JSON is not scrubbed. 65,536 candidates/16MiB root bookkeeping plus 2M resource/span/link owner+attr work and standard dictionary/result bounds; prefilter selected-source work and additional candidate context charge once. Requires separate root /4 or bounded complete reference and dedicated windowed root /6, never old span-local callbacks. Root proof is not full exporter/span-conflict or deployed-client parity. Canonical trace:duration measures max retained span end minus min retained span start across complete candidate context, not matching-span duration. Missing/ambiguous roots do not block this retained envelope, which can grow during ingest or shrink with retention and is NOT exporter duration/completeness. Unfiltered (nil/empty/{}) emits type int exact nanoseconds; any supported parent filter emits type duration Go strings (1.5ms,1µs U+00B5,1h0m0s), both lexical and V1 uses corresponding strings. Separate caches across filter/type changes; no floats/clamping. Same whole-retained1024/32MiB/1M input and local all-source replay limits;65,536 candidate groups/80B per-summary charge within16MiB charged bookkeeping, not total native memory.2M resource/span owners+attrs charge before filters/additional context once; events/links not requested owners but envelopes still validate.5000/1MiB dictionary/result bounds fail whole; broad nanosecond dictionaries commonly fail422, never sample/truncate. Dedicated duration /3 or sentinel reference and windowed /5 fence old root/string/window callbacks. Static duration/span:duration/traceDuration empty vocabulary is unchanged. Other intrinsic targets reject, never invent empty results.",
      "inputSchema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "tenant" => %{"type" => "string", "minLength" => 1},
          "scope" => %{
            "type" => "string",
            "enum" => ["none", "resource", "span", "instrumentation", "event", "link", "intrinsic"]
          },
          "key" => %{"type" => "string", "minLength" => 1, "maxLength" => 256},
          "query" => %{"type" => "string", "maxLength" => 16_384},
          "start_ts_ns" => %{"type" => "integer", "minimum" => 1, "maximum" => 9_223_372_036_854_775_807},
          "end_ts_ns" => %{"type" => "integer", "minimum" => 1, "maximum" => 9_223_372_036_854_775_807}
        },
        "required" => ["tenant", "scope", "key"]
      }
    },
    %{
      "name" => "search_trace_metadata",
      "annotations" => @read_only_annotations,
      "description" =>
        "Search complete retained trace context with bounded TraceQL; results are the most recent traces and with (most_recent=true) is optional. event.<key> predicates match when any event of the span carries a matching original value (exception.type, exception.message, ...). Spansets can be joined by structural operators >> (descendant), > (child), << (ancestor), < (parent) and ~ (sibling), up to four spansets; results and samples are the last spanset's spans. A trailing | select(attr, ...) adds those attributes (resource./span./event./unscoped, name, status, kind) to sampled spans. Positive scoped original-string equality/regex AND selectors retain source planning. Boolean expressions add original-string !=/!~, original-int64 comparisons, status/span:status =/!= unset/ok/error and own-span duration/span:duration comparisons with nonnegative duration literals. Unscoped .key uses the original span value if present, otherwise the resource value; a wrong-typed or nonmatching span value still overrides the resource. Unscoped samples may include independently matching values from both owners, even when another OR branch selects the span. && and || have equal precedence and group left-to-right; use parentheses. All conditions apply to one span, not different spans of a trace. Missing/differently typed attributes never match negative predicates; integer literals do not coerce doubles. New expressions disable service/ID planning and admit all retained sources under existing input limits plus 20M prefilter owner/attribute/instruction work units per scan attempt, both candidate/context passes. Max16 predicates/8 regexes/16 nested groups/16KiB; unsupported grammar fails whole, never drops filters. Window-local search/discovery retain narrower grammar. Inclusive trace-start/end overlap, not span-start filtering; matching spans may be outside the window. Returns Tempo search metadata, root summaries, service stats and sampled spansets, after ordering by full stored trace start. Not exporter completeness or full TraceQL. S3 exact resource.service.name equality can omit publication-proven rich sources from candidate discovery, then recover complete context through conservative trace-ID summaries without service/time restriction. Unknown/legacy sources always read; no inferred original types. Catalog remains metadata-byte/page/heap bounded with hard 8192-reference maximum, not promised capacity. Actual sources cumulatively spend 1024 inputs, 32MiB compressed bytes and 1000000 raw rows. Native index-probe exhaustion falls back to reading; context may exhaust budgets late and all errors fail whole. Captured sources replay without a second GET; candidate IDs stay capped at 65536 including outside-window matches. Unread proven-irrelevant objects are not integrity-scrubbed. All context is recovered before window/order/limit; smaller windows alone do not reduce it. Requires complete-context search capability5 and discovery12 on matching application/native artifacts. Legacy uncertainty on overlapping traces, conflicting root summaries and budgets fail the whole query. Representative posting/index/capacity and deployed Grafana acceptance remain pending.",
      "inputSchema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "tenant" => %{"type" => "string", "minLength" => 1},
          "query" => %{"type" => "string", "minLength" => 1, "maxLength" => 16_384},
          "start_ts_ns" => Map.put(@duration_schema, "minimum", 1),
          "end_ts_ns" => Map.put(@duration_schema, "minimum", 1),
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 1000},
          "spss" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
        },
        "required" => ["tenant", "query", "start_ts_ns", "end_ts_ns"]
      }
    },
    %{
      "name" => "traceql_metrics",
      "annotations" => @read_only_annotations,
      "description" =>
        "TraceQL metrics over stored spans, as Tempo's /api/metrics/query_range and /api/metrics/query: a span selector piped into rate(), count_over_time(), min/max/sum/avg_over_time(attr), quantile_over_time(attr, q...) or histogram_over_time(attr), optionally by(...) and topk/bottomk. Selectors use the bounded search expression grammar, including status/span:status, duration and event.<key> (any event of the span with a matching original value). Structural operators and select are search-only. Omit step_ns for an instant query over the whole window. Returns Tempo's metrics JSON. Requires PULSE_TEMPO_SEARCH_ENABLED.",
      "inputSchema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "tenant" => %{"type" => "string", "minLength" => 1},
          "query" => %{"type" => "string", "minLength" => 1, "maxLength" => 16_384},
          "start_ts_ns" => @timestamp_schema,
          "end_ts_ns" => @timestamp_schema,
          "step_ns" => %{"type" => "integer", "minimum" => 1, "maximum" => 9_223_372_036_854_775_807}
        },
        "required" => ["tenant", "query", "start_ts_ns", "end_ts_ns"]
      }
    },
    %{
      "name" => "search_traces",
      "annotations" => @read_only_annotations,
      "description" =>
        "Search distinct traces using a bounded single-spanset selector: AND-combined resource/span string equality or fully anchored regex, optionally with (most_recent=true). Requires an explicit inclusive span-start time window. Groups ALL stored window spans before ordering earliest window span start descending and trace ID ascending; limit applies to traces, never spans. Counts preserve duplicate rows. Returns window-local aggregates, not Tempo metadata or exporter completeness. Any legacy span in the window fails with trace_metadata_unknown. All window trace IDs, including nonmatches, count toward 65536 groups (trace_group_limit); narrow time windows, not just selectors. Scan/budget exhaustion fails the whole query. No variable expansion, structural operators, root summaries or full TraceQL.",
      "inputSchema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "tenant" => %{"type" => "string", "minLength" => 1},
          "query" => %{"type" => "string", "minLength" => 1, "maxLength" => 16_384},
          "start_ts_ns" => @duration_schema,
          "end_ts_ns" => @duration_schema,
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 1000}
        },
        "required" => ["tenant", "query", "start_ts_ns", "end_ts_ns"]
      }
    },
    %{
      "name" => "get_trace",
      "annotations" => @read_only_annotations,
      "description" =>
        "Assemble all visible stored spans for an exact trace ID without caller time-window or result truncation. Managed snapshots report their retention floor and intentionally exclude expired spans. Includes root, missing-parent, duplicate, proven conflicting and metadata-unknown legacy span IDs. Preserves duplicates. Fails rather than returns partial data when scan, 5000-span or byte budgets are exhausted. Coverage is the storage snapshot, not a guarantee that exporters delivered every span.",
      "inputSchema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "tenant" => %{"type" => "string", "minLength" => 1},
          "trace_id" => %{"type" => "string", "minLength" => 32}
        },
        "required" => ["tenant", "trace_id"]
      }
    },
    %{
      "name" => "query_traces",
      "annotations" => @read_only_annotations,
      "description" =>
        "Return stored spans, newest start time first. Exact trace/span/parent ID lookup or service, name, kind, status, duration, root-only, span/resource attribute search. Optional fields projection. Time bounds apply to span start, not duration overlap. A limited result is not necessarily a complete trace.",
      "inputSchema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "tenant" => %{"type" => "string", "minLength" => 1},
          "trace_id" => %{"type" => "string", "minLength" => 32},
          "span_id" => %{"type" => "string", "minLength" => 16},
          "parent_span_id" => %{"type" => "string", "minLength" => 16},
          "root_only" => %{"type" => "boolean", "description" => "When true, only spans without a parent."},
          "min_duration_ns" => @duration_schema,
          "max_duration_ns" => @duration_schema,
          "fields" => %{"type" => "array", "items" => %{"type" => "string", "enum" => @trace_fields}},
          "service" => %{"type" => "string"},
          "name" => %{"type" => "string"},
          "kind" => %{"type" => "integer", "minimum" => 0, "maximum" => 5},
          "status_code" => %{"type" => "integer", "minimum" => 0, "maximum" => 2},
          "attributes" => %{
            "type" => "object",
            "description" =>
              "Exact query-projection span attribute matches, combined with AND. Bytes project as base64; nonfinite doubles project as NaN/Infinity/-Infinity strings. Consult otlp for original type; this compatibility predicate does not prove string identity."
          },
          "resource" => %{
            "type" => "object",
            "description" =>
              "Exact query-projection resource attribute matches, combined with AND. Bytes project as base64; nonfinite doubles project as NaN/Infinity/-Infinity strings. Consult otlp for original type; this compatibility predicate does not prove string identity."
          },
          "attributes_regex" => %{
            "type" => "object",
            "maxProperties" => 8,
            "additionalProperties" => %{"type" => "string", "maxLength" => 1024},
            "propertyNames" => %{"type" => "string", "minLength" => 1, "maxLength" => 256},
            "description" =>
              "Fully anchored bounded RE2-subset patterns over present string span attribute projections (including base64 bytes and nonfinite-double spellings, not proof of original string type); AND with other filters. At most 8 patterns combined with resource_regex. Patterns max 1024 UTF-8 bytes, keys max 256 bytes."
          },
          "resource_regex" => %{
            "type" => "object",
            "maxProperties" => 8,
            "additionalProperties" => %{"type" => "string", "maxLength" => 1024},
            "propertyNames" => %{"type" => "string", "minLength" => 1, "maxLength" => 256},
            "description" =>
              "Fully anchored bounded RE2-subset patterns over present string resource attribute projections, including base64 bytes and nonfinite-double spellings. Missing/non-string projections never match; consult otlp or original-string search selectors for source type. At most 8 patterns combined with attributes_regex. Patterns max 1024 UTF-8 bytes, keys max 256 bytes."
          },
          "start_ts_ns" => @timestamp_schema,
          "end_ts_ns" => @timestamp_schema,
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 5000}
        },
        "required" => ["tenant"]
      }
    },
    %{
      "name" => "query_errors",
      "annotations" => @read_only_annotations,
      "description" =>
        "Read Sentry error events and scrubbed payloads, newest first. Requires a time window; scans above 5,000 stored occurrences or 32 MiB of decoded S3 columns fail, independently of the page limit. Retries deduplicate by project/event ID. Pages contain at most 2 MiB of JSON; use next_cursor with the same filters/window. Changed results or expired cursors require restarting without the cursor. This is diagnosis, not a monitoring change feed.",
      "inputSchema" => @error_schema
    },
    %{
      "name" => "list_error_issues",
      "annotations" => @read_only_annotations,
      "description" =>
        "Group Sentry errors in a required time window; returns exact retained-window counts and first/last seen, newest issue first. Same filters, pagination and scan limits as query_errors. Not lifetime counts, new-issue detection or resolved/ignored state.",
      "inputSchema" => @error_schema
    },
    %{
      "name" => "list_error_changes",
      "annotations" => @read_only_annotations,
      "description" =>
        "Poll the experimental opt-in S3 error index: baseline_ready, new_in_retained_history, issue_observation, error_rate_increase and explicit reset changes. Rate findings compare the latest two completed five-minute windows per issue/service: at least 5 baseline events and a 3x increase, with exact counts and up to 3 compact examples. Not request-normalized error ratios or statistical anomalies; bootstrap/reset suppresses historical findings. Save next_cursor durably and deduplicate change_id. Newness is scoped to the reported project/history floor, never first-ever. Inspect rate_detector status, indexed_at_ns and backlog; current lag is unknown. Cursors below replay_floor require reset.",
      "inputSchema" => @error_index_schema
    },
    %{
      "name" => "list_indexed_error_issues",
      "annotations" => @read_only_annotations,
      "description" =>
        "Read compact issue summaries from the experimental opt-in S3 error index, with exact deduplicated retained-history counts and latest example references. No payloads or lifetime counts. Inspect indexed_at_ns/history_floor_ns; incomplete reconciliation errors rather than returning partial counts. Fetch payloads separately with query_errors. Changed snapshots require cursor reset.",
      "inputSchema" => @error_index_schema
    },
    %{
      "name" => "query_promql",
      "annotations" => @read_only_annotations,
      "description" =>
        "Evaluate the supported Prometheus Query Language subset: selectors, rate/increase/irate/delta, over-time functions, and sum/avg/min/max/count with by/without grouping. Returns a Prometheus vector or matrix envelope.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "tenant" => %{"type" => "string", "minLength" => 1},
          "query" => %{"type" => "string", "minLength" => 1},
          "start_ts_ns" => @timestamp_schema,
          "end_ts_ns" => @timestamp_schema,
          "step_ms" => %{
            "type" => "integer",
            "minimum" => 1,
            "maximum" => 9_223_372_036_854,
            "description" =>
              "Range-query step in milliseconds. Requires start_ts_ns and end_ts_ns; omit for an instant query."
          }
        },
        "required" => ["tenant", "query"]
      }
    },
    %{
      "name" => "query_logs",
      "annotations" => @read_only_annotations,
      "description" => "Return log records for a tenant, optionally filtered by time range and service.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "tenant" => %{
            "type" => "string",
            "minLength" => 1,
            "description" => "Tenant identifier (matches the X-Scope-OrgID used at ingest)."
          },
          "service" => %{
            "type" => "string",
            "description" => "Optional service.name filter."
          },
          "start_ts_ns" =>
            Map.put(@timestamp_schema, "description", "Inclusive lower bound on log timestamp, Unix nanoseconds."),
          "end_ts_ns" =>
            Map.put(@timestamp_schema, "description", "Inclusive upper bound on log timestamp, Unix nanoseconds."),
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 5000}
        },
        "required" => ["tenant"]
      }
    },
    %{
      "name" => "discover_metrics",
      "annotations" => @read_only_annotations,
      "description" =>
        "Return complete retained sample-backed metric label names, values or series. Values mode requires a nonempty label; other modes omit label. Series requires at least one selector. Selectors are ORed, matchers within one selector ANDed; each selector needs a matcher excluding the empty string. Accepts bare metric/label selectors, not full expressions, ranges or nonzero offsets. Regexes are fully anchored. Empty-valued labels project as absent without rewriting raw records. Optional time bounds are exact inclusive sample timestamps in nanoseconds, not TSDB block metadata. Omitting bounds scans retained history. No limit/truncation parameter: more than 5000 distinct entries or 1 MiB dictionary/encoded output fails whole. S3 scans cap 1024 objects/128 MiB/1M actual footer rows with independent 5M work/16 MiB canonical-probe limits per attempt; the reference caps 100k selected records. These are safety bounds, not guaranteed capacity or total native-memory limits.",
      "inputSchema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "tenant" => %{"type" => "string", "minLength" => 1},
          "mode" => %{"type" => "string", "enum" => ["names", "values", "series"]},
          "label" => %{"type" => "string", "maxLength" => 256},
          "selectors" => %{
            "type" => "array",
            "maxItems" => 16,
            "items" => %{"type" => "string", "minLength" => 1, "maxLength" => 16_384}
          },
          "start_ts_ns" => @timestamp_schema,
          "end_ts_ns" => @timestamp_schema
        },
        "required" => ["tenant", "mode"]
      }
    },
    %{
      "name" => "query_metrics",
      "annotations" => @read_only_annotations,
      "description" =>
        "Return metric samples for a tenant, optionally filtered by time range and PromQL-style label matchers.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "tenant" => %{
            "type" => "string",
            "minLength" => 1,
            "description" => "Tenant identifier (matches the X-Scope-OrgID used at ingest)."
          },
          "matchers" => %{
            "type" => "array",
            "description" =>
              "PromQL-style label matchers. Each element is `{name, op, value}` with op ∈ {=, !=, =~, !~}.",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "name" => %{"type" => "string"},
                "op" => %{"type" => "string", "enum" => ["=", "!=", "=~", "!~"]},
                "value" => %{"type" => "string"}
              },
              "required" => ["name", "op", "value"]
            }
          },
          "start_ts_ns" =>
            Map.put(@timestamp_schema, "description", "Inclusive lower bound on sample timestamp, Unix nanoseconds."),
          "end_ts_ns" =>
            Map.put(@timestamp_schema, "description", "Inclusive upper bound on sample timestamp, Unix nanoseconds."),
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 5000}
        },
        "required" => ["tenant"]
      }
    },
    %{
      "name" => "query_logql",
      "annotations" => @read_only_annotations,
      "description" =>
        "Run a LogQL query and return the Loki-shaped JSON envelope. Supports log queries (streams result) and metric queries (matrix or vector result). The envelope is identical to /loki/api/v1/query_range so agent tooling that already understands Loki works unchanged.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "tenant" => %{"type" => "string", "minLength" => 1},
          "query" => %{"type" => "string", "minLength" => 1, "description" => "LogQL expression."},
          "start_ts_ns" => @timestamp_schema,
          "end_ts_ns" => @timestamp_schema,
          "step_ms" => %{
            "type" => "integer",
            "minimum" => 1,
            "maximum" => 9_223_372_036_854,
            "description" =>
              "Step interval in milliseconds for range metric queries. Required for matrix output; ignored for log queries."
          },
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 5000},
          "direction" => %{"type" => "string", "enum" => ["forward", "backward"]}
        },
        "required" => ["tenant", "query"]
      }
    }
  ]

  @spec list() :: [map()]
  def list, do: @tools ++ @reliability_tools ++ Tools.list()

  @tool_names Enum.map(@tools ++ @reliability_tools, & &1["name"])

  @doc "Whether `name` is a registered tool."
  @spec known?(term()) :: boolean()
  def known?(name), do: name in @tool_names or Tools.known?(name)

  @spec call(String.t(), term(), Pulse.MCP.context()) :: {:ok, [map()]} | {:error, term()}
  def call(name, args, context \\ %{})

  def call(name, args, context) do
    operation =
      cond do
        Tools.known?(name) -> "alert_tool"
        known?(name) -> name
        true -> "unknown_tool"
      end

    Pulse.Metrics.measure(:query, operation, fn ->
      Pulse.SelfMetrics.track(:query, :mcp, fn -> do_call(name, args, context) end)
    end)
  end

  defp do_call(name, args, context) do
    if Tools.known?(name) do
      Tools.call(name, args, context)
    else
      do_query_call(name, args, context)
    end
  end

  defp do_query_call(name, args, context) do
    case Enum.find(@tools ++ @reliability_tools, &(&1["name"] == name)) do
      nil ->
        {:error, {:unknown_tool, name}}

      tool ->
        with :ok <- validate_tenant(args),
             :ok <- verify(context, args["tenant"]),
             args = Arguments.normalize(args, tool["inputSchema"]),
             :ok <- Arguments.validate(args, tool["inputSchema"]),
             :ok <- validate_range(name, args) do
          execute(name, args)
        end
    end
  end

  defp validate_tenant(args) do
    Arguments.validate(args, %{
      "type" => "object",
      "properties" => %{"tenant" => %{"type" => "string", "minLength" => 1}},
      "required" => ["tenant"]
    })
  end

  defp validate_range(name, args) do
    with :ok <- validate_time_order(args), do: validate_range_fields(name, args)
  end

  defp validate_time_order(%{"start_ts_ns" => start, "end_ts_ns" => finish}) when start > finish,
    do: {:error, {:invalid_arguments, "start_ts_ns must not exceed end_ts_ns"}}

  defp validate_time_order(_args), do: :ok

  defp validate_range_fields("query_promql", %{"start_ts_ns" => _, "end_ts_ns" => _, "step_ms" => _}), do: :ok

  defp validate_range_fields("query_promql", args) do
    if Map.has_key?(args, "step_ms") or Map.has_key?(args, "start_ts_ns"),
      do: {:error, {:invalid_arguments, "range queries require start_ts_ns, end_ts_ns, and step_ms"}},
      else: :ok
  end

  defp validate_range_fields("query_traces", %{"min_duration_ns" => start, "max_duration_ns" => finish})
       when start > finish, do: {:error, {:invalid_arguments, "min_duration_ns must not exceed max_duration_ns"}}

  defp validate_range_fields(_name, _args), do: :ok

  defp execute(name, %{"tenant" => tenant} = args) when name in ["discover_trace_tags", "discover_trace_tag_values"] do
    scope = Map.get(args, "scope", "none")

    window =
      if Map.has_key?(args, "start_ts_ns") or Map.has_key?(args, "end_ts_ns"),
        do: {args["start_ts_ns"], args["end_ts_ns"]}

    with {:ok, json} <- TempoDiscovery.query(tenant, scope, args["key"] || "", 2, "json", args["query"], window),
         do: {:ok, [%{"type" => "text", "text" => json}]}
  end

  defp execute("search_trace_metadata", %{"tenant" => tenant} = args) do
    opts = [
      trace_start: args["start_ts_ns"],
      trace_end: args["end_ts_ns"],
      limit: args["limit"] || 100,
      spss: args["spss"] || 3
    ]

    with {:ok, json} <- TempoSearch.query(tenant, args["query"], opts),
         do: {:ok, [%{"type" => "text", "text" => json}]}
  end

  defp execute("traceql_metrics", %{"tenant" => tenant} = args) do
    instant = not Map.has_key?(args, "step_ns")
    window = {args["start_ts_ns"], args["end_ts_ns"], args["step_ns"]}

    with :ok <- TempoSearch.available(),
         {:ok, json} <- Metrics.query(tenant, args["query"], window, instant),
         do: {:ok, [%{"type" => "text", "text" => json}]}
  end

  defp execute("search_traces", %{"tenant" => tenant} = args) do
    with {:ok, predicates} <- Selector.parse(args["query"]) do
      opts = [start_ts: args["start_ts_ns"], end_ts: args["end_ts_ns"], limit: args["limit"] || 100]

      query_trace_search(tenant, predicates, opts)
    end
  end

  defp execute("get_trace", %{"tenant" => tenant} = args) do
    with {:ok, args} <- normalize_trace_ids(args),
         do: query_trace_json(tenant, [trace_id: args["trace_id"]], nil, :assembly)
  end

  defp execute("query_traces", %{"tenant" => tenant} = args) do
    with {:ok, args} <- normalize_trace_ids(args),
         :ok <- trace_filter_budget(args),
         :ok <- RegexFilters.validate(args) do
      # Closed vocabulary: convert known atoms to strings, never user input to atoms.
      opts =
        Enum.reduce(
          [
            :service,
            :name,
            :kind,
            :status_code,
            :attributes,
            :resource,
            :attributes_regex,
            :resource_regex,
            :trace_id,
            :span_id,
            :parent_span_id,
            :root_only,
            :min_duration_ns,
            :max_duration_ns,
            :limit
          ],
          [],
          fn key, opts -> put_opt(opts, key, args[Atom.to_string(key)]) end
        )
        |> put_opt(:start_ts, args["start_ts_ns"])
        |> put_opt(:end_ts, args["end_ts_ns"])

      fields = if is_list(args["fields"]), do: Enum.uniq(args["fields"]), else: args["fields"]
      query_trace_json(tenant, opts, fields)
    end
  end

  defp execute(name, %{"tenant" => tenant} = args) when name in ["query_errors", "list_error_issues"] do
    kind = if name == "query_errors", do: :events, else: :issues

    with {:ok, json} <- Pulse.Errors.query(kind, tenant, args) do
      {:ok, [%{"type" => "text", "text" => json}]}
    end
  end

  defp execute(name, %{"tenant" => tenant} = args)
       when name in ~w(list_reliability_signals list_reliability_changes get_reliability_signal) do
    kind =
      case name do
        "list_reliability_signals" -> :signals
        "list_reliability_changes" -> :changes
        "get_reliability_signal" -> :signal
      end

    with {:ok, result} <- Pulse.Reliability.read(kind, tenant, args) do
      {:ok, [%{"type" => "text", "text" => Pulse.JSON.encode!(result)}]}
    end
  end

  defp execute(name, %{"tenant" => tenant, "project" => project} = args)
       when name in ["list_error_changes", "list_indexed_error_issues"] do
    kind = if name == "list_error_changes", do: :changes, else: :issues

    with {:ok, result} <- Projection.read(kind, tenant, project, args) do
      {:ok, [%{"type" => "text", "text" => Pulse.JSON.encode!(result)}]}
    end
  end

  defp execute("query_logs", %{"tenant" => tenant} = args) when is_binary(tenant) do
    opts =
      []
      |> put_opt(:start_ts, args["start_ts_ns"])
      |> put_opt(:end_ts, args["end_ts_ns"])
      |> put_opt(:limit, args["limit"])
      |> put_opt(:service, args["service"])

    query_raw(:logs, tenant, opts, &encode_records/1)
  end

  defp execute("discover_metrics", %{"tenant" => tenant, "mode" => mode} = args) do
    opts = %{} |> maybe_put(:start_ts_ns, args["start_ts_ns"]) |> maybe_put(:end_ts_ns, args["end_ts_ns"])

    with :ok <- S3.validate_tenant(tenant),
         {:ok, data} <- Discovery.query(tenant, mode, Map.get(args, "label", ""), Map.get(args, "selectors", []), opts) do
      {:ok, [%{"type" => "text", "text" => ~s({"status":"success","data":) <> data <> "}"}]}
    end
  end

  defp execute("query_metrics", %{"tenant" => tenant} = args) when is_binary(tenant) do
    with {:ok, matcher_tuples} <- parse_matchers(args["matchers"]) do
      opts =
        []
        |> put_opt(:start_ts, args["start_ts_ns"])
        |> put_opt(:end_ts, args["end_ts_ns"])
        |> put_opt(:limit, args["limit"])
        |> put_opt(:matchers, matcher_tuples)

      query_raw(:metrics, tenant, opts, &encode_samples/1)
    end
  end

  defp execute("query_logql", %{"tenant" => tenant, "query" => query} = args)
       when is_binary(tenant) and is_binary(query) do
    opts = build_logql_opts(args)

    with {:ok, ast} <- parse_query(query),
         {:ok, envelope} <- run_logql(ast, tenant, opts) do
      {:ok, [%{"type" => "text", "text" => Pulse.JSON.encode!(envelope)}]}
    else
      {:error, {:invalid_arguments, {:logql_parse_error, _}}} = error -> grafana_variable_error(query) || error
      error -> error
    end
  end

  defp execute("query_promql", %{"tenant" => tenant, "query" => query} = args)
       when is_binary(tenant) and is_binary(query) do
    opts =
      %{}
      |> maybe_put(:start_ts_ns, args["start_ts_ns"])
      |> maybe_put(:end_ts_ns, args["end_ts_ns"])

    opts =
      case Map.fetch(args, "step_ms") do
        :error -> opts
        {:ok, ms} -> Map.put(opts, :step_ns, ms * 1_000_000)
      end

    case Pulse.PromQL.Evaluator.query(query, tenant, opts) do
      {:error, :invalid_or_unsupported_query} = error -> grafana_variable_error(query) || promql_result(error)
      result -> promql_result(result)
    end
  end

  # Grafana replaces its interval and range variables before it sends a query,
  # from settings Pulse cannot see (the data source's scrape interval, the
  # panel's width, the alert's interval). A query that fails to parse because
  # of one says how to replace it rather than guessing a value.
  @grafana_variable ~r/\$\{?(__rate_interval|__interval_ms|__interval|__auto|__range_ms|__range_s|__range)\b/
  defp grafana_variable_error(query) do
    case Regex.run(@grafana_variable, query) do
      [_, name] ->
        {:error,
         {:invalid_arguments,
          "the query uses Grafana's $#{name}, which Grafana replaces before it sends a query; " <>
            "replace it with #{grafana_variable_hint(name)}"}}

      nil ->
        nil
    end
  end

  defp grafana_variable_hint("__rate_interval"),
    do:
      "a duration of at least four scrape intervals, such as [1m] for a 15s scrape (Grafana uses max(step + scrape interval, 4 × scrape interval))"

  defp grafana_variable_hint(name) when name in ["__interval", "__interval_ms", "__auto"],
    do: "the step, such as 1m (or 60000 for $__interval_ms)"

  defp grafana_variable_hint(_range), do: "the dashboard's time range, such as 1h (3600 for $__range_s)"

  defp promql_result({:ok, result}), do: {:ok, [%{"type" => "text", "text" => Pulse.JSON.encode!(result)}]}
  defp promql_result({:error, :invalid_stored_sample}), do: {:error, :metric_data_invalid}
  defp promql_result({:error, {:storage_error, _}}), do: {:error, :metric_storage_unavailable}
  defp promql_result({:error, :query_execution_failed}), do: {:error, :metric_query_execution_failed}
  defp promql_result({:error, :query_overloaded}), do: {:error, :query_overloaded}

  defp promql_result({:error, reason})
       when reason in [
              :query_sample_limit,
              :query_scan_limit,
              :query_work_limit,
              :query_result_limit,
              :query_intermediate_limit,
              :query_resource_limit,
              :query_timeout
            ], do: {:error, :query_execution_limit}

  defp promql_result({:error, reason}), do: {:error, {:invalid_arguments, reason}}

  defp normalize_trace_ids(args) do
    Enum.reduce_while([{"trace_id", 32}, {"span_id", 16}, {"parent_span_id", 16}], {:ok, args}, fn {key, length},
                                                                                                   {:ok, args} ->
      normalize_trace_id(args[key], key, length, args)
    end)
  end

  defp normalize_trace_id(nil, _key, _length, args), do: {:cont, {:ok, args}}

  defp normalize_trace_id(value, key, length, args) do
    case Traces.id(value, length) do
      {:ok, id} -> {:cont, {:ok, Map.put(args, key, id)}}
      _ -> {:halt, {:error, {:invalid_arguments, "#{key} must be a nonzero #{length}-digit hex ID"}}}
    end
  end

  defp trace_filter_budget(args) do
    Enum.reduce_while(["attributes", "resource"], :ok, fn key, :ok ->
      payload = %{"streams" => [%{"stream" => args[key] || %{}}]}

      case Pulse.IngestLimits.validate(:loki, payload) do
        :ok ->
          continue_trace_filter(args[key] || %{})

        _ ->
          {:halt, {:error, {:invalid_arguments, "oversized trace filter"}}}
      end
    end)
  end

  defp continue_trace_filter(value) do
    if trace_filter_value?(value),
      do: {:cont, :ok},
      else: {:halt, {:error, {:invalid_arguments, "unsupported trace filter value"}}}
  end

  defp trace_filter_value?(value) when is_integer(value),
    do: value in -9_223_372_036_854_775_808..9_223_372_036_854_775_807

  defp trace_filter_value?(value) when is_binary(value) or is_float(value) or is_boolean(value) or is_nil(value),
    do: true

  defp trace_filter_value?(value) when is_list(value), do: Enum.all?(value, &trace_filter_value?/1)

  defp trace_filter_value?(value) when is_map(value),
    do: Enum.all?(value, fn {key, value} -> is_binary(key) and trace_filter_value?(value) end)

  defp trace_filter_value?(_), do: false

  defp raw_opts(opts, deadline) do
    opts = if Keyword.has_key?(opts, :limit), do: opts, else: Keyword.put(opts, :limit, 5_001)
    budgets = QueryRunner.storage_opts(deadline, 5_001)
    budgets = if Keyword.get(opts, :limit) == 5_001, do: budgets, else: Keyword.delete(budgets, :max_records)
    opts ++ budgets
  end

  defp query_trace_json(tenant, opts, fields, mode \\ :spans) do
    QueryRunner.run(tenant, :raw, fn deadline ->
      result =
        case mode do
          :spans -> Storage.query_traces_json(tenant, raw_opts(opts, deadline), fields)
          :assembly -> Storage.get_trace_json(tenant, opts[:trace_id], raw_opts(opts, deadline))
        end

      with {:ok, json} <- result,
           do: {:ok, [%{"type" => "text", "text" => json}]}
    end)
  end

  defp query_trace_search(tenant, predicates, opts) do
    QueryRunner.run(tenant, :raw, fn deadline ->
      budgets = QueryRunner.storage_opts(deadline) |> Keyword.delete(:max_records)

      with {:ok, json} <- Storage.search_traces_json(tenant, predicates, opts ++ budgets),
           do: {:ok, [%{"type" => "text", "text" => json}]}
    end)
  end

  defp query_raw(signal, tenant, opts, encode) do
    QueryRunner.run(tenant, :raw, fn deadline ->
      with {:ok, records} <- Storage.query(signal, tenant, raw_opts(opts, deadline)),
           :ok <- check_raw_count(records, opts),
           {:ok, json} <- encode.(records) do
        {:ok, [%{"type" => "text", "text" => json}]}
      end
    end)
  end

  defp check_raw_count(records, opts) do
    if not Keyword.has_key?(opts, :limit) and length(records) > 5_000,
      do: {:error, :query_sample_limit},
      else: :ok
  end

  # -- query_metrics helpers -----------------------------------------------

  # Translate the public PromQL-style operators (`=`, `!=`, `=~`, `!~`)
  # into the atom shape the storage layer and the Rust decoder expect.
  defp parse_matchers(nil), do: {:ok, nil}

  defp parse_matchers(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn
      %{"name" => n, "op" => op, "value" => v}, {:ok, acc}
      when is_binary(n) and is_binary(v) ->
        with {:ok, atom_op} <- translate_op(op),
             :ok <- validate_metric_pattern(atom_op, v) do
          {:cont, {:ok, [{n, atom_op, v} | acc]}}
        else
          err -> {:halt, err}
        end

      _, _ ->
        {:halt, {:error, {:invalid_arguments, "matchers must be [{name, op, value}]"}}}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end

  defp parse_matchers(_), do: {:error, {:invalid_arguments, "matchers must be a list"}}

  defp validate_metric_pattern(op, pattern) when op in [:re, :nre] do
    if byte_size(pattern) <= 1024 and NIF.validate_metric_regex(pattern) == :ok,
      do: :ok,
      else: {:error, {:invalid_arguments, "invalid or oversized metric regular expression"}}
  end

  defp validate_metric_pattern(_op, _value), do: :ok

  defp translate_op("="), do: {:ok, :eq}
  defp translate_op("!="), do: {:ok, :neq}
  defp translate_op("=~"), do: {:ok, :re}
  defp translate_op("!~"), do: {:ok, :nre}
  defp translate_op(op), do: {:error, {:invalid_arguments, "unknown matcher op: #{inspect(op)}"}}

  # -- query_logql helpers -------------------------------------------------

  defp parse_query(query) do
    case Parser.parse(query) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, {:invalid_arguments, {:logql_parse_error, reason}}}
    end
  end

  defp build_logql_opts(args) do
    %{}
    |> maybe_put(:start_ts_ns, args["start_ts_ns"])
    |> maybe_put(:end_ts_ns, args["end_ts_ns"])
    |> maybe_put(:limit, args["limit"])
    |> maybe_put(:step_ns, from_ms(args["step_ms"]))
    |> maybe_put(:direction, from_direction(args["direction"]))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp from_ms(nil), do: nil
  defp from_ms(ms) when is_integer(ms) and ms > 0, do: ms * 1_000_000

  defp from_direction("forward"), do: :forward
  defp from_direction("backward"), do: :backward
  defp from_direction(_), do: nil

  defp run_logql(%AST.LogQuery{} = ast, tenant, opts) do
    case Evaluator.evaluate_log(ast, tenant, opts) do
      {:ok, streams} -> {:ok, Envelope.streams(streams)}
      {:error, _} = err -> err
    end
  end

  defp run_logql(metric_expr, tenant, opts) do
    case Evaluator.evaluate_metric(metric_expr, tenant, opts) do
      {:ok, {:matrix, series}} -> {:ok, Envelope.matrix(series)}
      {:ok, {:vector, series}} -> {:ok, Envelope.vector(series)}
      {:ok, {:scalar, series}} -> {:ok, Envelope.scalar(series)}
      {:error, _} = err -> err
    end
  end

  # Every tool that names a tenant runs it through `Pulse.Auth.verify/3` as `:read`.
  # MCP is the same JSON-RPC transport for read and write; without this hop
  # the ingest boundary's auth check would be bypassable via the read path.
  #
  # A missing conn falls through to a fresh `%Plug.Conn{}`. When the active
  # auth module is `Pulse.Auth.Open` (dev/test default) that still returns
  # :ok. When it is `Pulse.Auth.SharedSecret` (prod) it fails, closed —
  # there is no in-process caller that legitimately reaches this path
  # without a conn under real auth.
  defp verify(context, tenant) do
    conn = Map.get(context, :conn) || %Plug.Conn{}

    case Auth.verify(conn, tenant, :read) do
      :ok -> :ok
      {:error, reason} -> {:error, {:unauthorized, reason}}
    end
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  # Rust encodes the record list directly (no intermediate maps); it defers
  # to the Elixir encoding below whenever it cannot produce the same JSON.
  defp encode_records(records) do
    case NIF.encode_log_segment_bounded(records, 16_777_216) do
      {:ok, _json} = result -> result
      {:error, _} = error -> error
      :fallback -> encode_reference(records, &encode_record/1)
    end
  end

  defp encode_reference(records, encode) do
    # Preserve the Elixir reference for custom adapters with JSON protocol
    # values outside the native vocabulary. Public S3 records are JSON terms.
    Enum.reduce_while(records, {:ok, [], 2}, fn record, {:ok, chunks, bytes} ->
      chunk = JSON.encode!(encode.(record))
      size = bytes + byte_size(chunk) + if(chunks == [], do: 0, else: 1)

      if size <= 16_777_216,
        do: {:cont, {:ok, [chunk | chunks], size}},
        else: {:halt, {:error, :query_result_limit}}
    end)
    |> case do
      {:ok, chunks, _} -> {:ok, IO.iodata_to_binary(["[", Enum.intersperse(Enum.reverse(chunks), ","), "]"])}
      error -> error
    end
  end

  defp encode_record(%Log{} = record) do
    %{
      "timestamp_ns" => record.timestamp_ns,
      "observed_timestamp_ns" => record.observed_timestamp_ns,
      "severity_number" => record.severity_number,
      "severity_text" => record.severity_text,
      "service" => record.service,
      "body" => record.body,
      "trace_id" => record.trace_id,
      "span_id" => record.span_id,
      "attributes" => record.attributes,
      "resource" => record.resource,
      "otlp" => record.otlp
    }
  end

  # Rust fast-path JSON encoder; falls back to Elixir on any shape the
  # Rust side cannot guarantee to emit identically. Keeps the hot path
  # (10k-sample MCP responses) off the general-purpose encoder, which
  # has to build one intermediate string-keyed map per sample first.
  defp encode_samples(samples) do
    case NIF.encode_metric_samples(samples) do
      {:ok, _json} = result -> result
      {:error, _} = error -> error
      :fallback -> encode_reference(samples, &encode_sample/1)
    end
  end

  defp encode_sample(%MetricSample{} = s) do
    %{
      "series_id" => s.series_id,
      "timestamp_ns" => s.timestamp_ns,
      "value" => s.value,
      "labels" => s.labels,
      "otlp" => s.otlp
    }
    |> put_present("start_timestamp_ms", s.start_timestamp_ms)
    |> put_present("histogram", s.histogram && encode_histogram(s.histogram))
    |> put_present("exemplars", s.exemplars && Enum.map(s.exemplars, &Map.from_struct/1))
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp encode_histogram(histogram) do
    spans = fn spans -> Enum.map(spans, &Tuple.to_list/1) end

    histogram
    |> Map.from_struct()
    |> Map.update!(:positive_spans, spans)
    |> Map.update!(:negative_spans, spans)
  end
end
