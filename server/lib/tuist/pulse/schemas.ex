defmodule Tuist.Pulse.Schemas do
  @moduledoc "Shared HTTP and MCP contracts for authorized Pulse reads."

  alias OpenApiSpex.Schema

  def inputs(action) do
    fields = Map.merge(%{account_handle: string()}, options(action))

    fields =
      if action in [:query, :analytics],
        do: Map.put(fields, :signal, %Schema{type: :string, enum: ~w(metrics logs traces errors)}),
        else: fields

    fields = if action in [:issue, :event], do: Map.put(fields, :issue_id, string()), else: fields
    fields = if action == :event, do: Map.put(fields, :event_id, string()), else: fields

    required =
      [:account_handle] ++
        case action do
          action when action in [:query, :analytics] -> [:signal]
          :issue -> [:issue_id]
          :event -> [:issue_id, :event_id]
        end

    %{object("Pulse#{action}Input", fields) | required: required}
  end

  def parameters(action) do
    input = inputs(action)

    for name <- input.required ++ Enum.sort(Map.keys(input.properties) -- input.required) do
      schema = Map.fetch!(input.properties, name)
      path? = name in input.required
      {name, [in: if(path?, do: :path, else: :query), type: schema, required: path?]}
    end
  end

  def options(:analytics), do: %{range: range()}

  def options(action) do
    fields = %{
      range: range(),
      end_at: %Schema{
        type: :string,
        description: "ISO8601 pinned window end from the previous response's meta.end_at."
      },
      service: string(),
      project: string(),
      environment: string(),
      release: string(),
      service_op: operator(),
      project_op: operator(),
      environment_op: operator(),
      release_op: operator()
    }

    fields =
      if action == :event,
        do: fields,
        else:
          Map.merge(fields, %{
            page: %Schema{type: :integer, minimum: 1, maximum: 2_147_483_647, default: 1},
            page_size: %Schema{type: :integer, minimum: 1, maximum: 100, default: 20}
          })

    if action == :query do
      Map.merge(fields, %{
        query: %Schema{
          type: :string,
          maxLength: 4096,
          description: "Native PromQL, LogQL or TraceQL expression; literal title search for grouped errors."
        },
        search: string(),
        level: string(),
        level_op: operator(),
        sort_by: %Schema{
          type: :string,
          enum:
            ~w(name value timestamp service level message trace_id duration_ms last_seen_ns first_seen_ns count title project issue_id),
          description:
            "Signal-specific column: metrics name/value; logs timestamp/service/level/message/trace_id; traces timestamp/service/name/duration_ms/trace_id; errors last_seen_ns/first_seen_ns/count/title/service/project/issue_id."
        },
        sort_order: %Schema{type: :string, enum: ~w(asc desc)}
      })
    else
      fields
    end
  end

  def response(:query),
    do: object("PulseQuery", %{rows: array(row()), series: array(series()), warnings: warnings(), meta: meta()})

  def response(:issue),
    do:
      object("PulseErrorIssueDetail", %{
        issue: issue(),
        latest_event: event(),
        occurrence_series: %{
          occurrence_series()
          | description:
              "60 equal-width [bucket_start_unix_seconds, integer_count] pairs covering the selected period, including zero counts. Buckets include their start and exclude their end, except the last includes the selected period end."
        },
        events: array(event()),
        meta: meta(),
        warnings: warnings()
      })

  def response(:event), do: object("PulseErrorEventDetail", %{event: event(), warnings: warnings()})

  def response(:analytics) do
    object("PulseAnalytics", %{
      widgets:
        array(
          object("PulseWidget", %{
            id: string(),
            unit: string(),
            value: %Schema{type: :number, nullable: true},
            previous_value: %Schema{type: :number, nullable: true},
            points: points()
          })
        ),
      warnings: warnings()
    })
  end

  def issue do
    schema =
      object("PulseErrorIssue", %{
        issue_id: string(),
        project: string(),
        service: string(),
        title: string(),
        level: string(true),
        platform: string(true),
        culprit: culprit(),
        occurrence_series: occurrence_series(),
        count: %Schema{
          type: :integer,
          description: "Occurrence count in the complete filtered selected period, not lifetime or page count."
        },
        first_seen_ns: %Schema{type: :integer},
        last_seen_ns: %Schema{type: :integer},
        latest_event_id: string()
      })

    %{schema | required: schema.required -- [:level, :platform, :culprit, :occurrence_series]}
  end

  def event do
    # Only projected event properties belong here, never raw Sentry payloads.
    frame =
      object("PulseErrorFrame", %{
        filename: string(true),
        module: string(true),
        function: string(true),
        lineno: %Schema{type: :integer, nullable: true},
        in_app: %Schema{type: :boolean}
      })

    exception = object("PulseErrorException", %{type: string(true), value: string(true), frames: array(frame)})

    %{
      object("PulseErrorEvent", %{
        event_id: string(),
        issue_id: string(),
        timestamp_ns: string(),
        timestamp: string(),
        project: string(),
        service: string(),
        environment: string(true),
        release: string(true),
        title: string(),
        level: string(true),
        platform: string(true),
        culprit: culprit(),
        tags: metadata(),
        contexts: metadata(),
        extra: metadata(),
        modules: metadata(),
        trace_id: string(true),
        span_id: string(true),
        exceptions: array(exception),
        exception: %{exception | required: []}
      })
      | required: []
    }
  end

  defp culprit do
    %{
      string(true)
      | description:
          "Recorded grouping location from the latest exception: last in_app frame, otherwise last frame; module (or filename) and function joined with a dot. Null when absent."
    }
  end

  defp occurrence_series do
    %Schema{
      type: :array,
      minItems: 60,
      maxItems: 60,
      items: %Schema{type: :array, minItems: 2, maxItems: 2, items: %Schema{type: :integer, minimum: 0}},
      description:
        "60 zero-filled [bucket_start_unix_seconds, integer_count] pairs from the complete filtered issue cohort before pagination. Buckets are half-open; the final bucket includes the selected period end. Summary level/platform/culprit come from that cohort's newest event."
    }
  end

  defp metadata do
    %Schema{
      type: :object,
      additionalProperties: %Schema{},
      description:
        "Recorded metadata only (tags maps or list-pairs normalize to an object; other sections require maps). Nested JSON scalar types are preserved. Credential/sensitive keys and embedded credentials are redacted. No raw request, user or stack locals. Bounds: depth 5, 50 entries/container, 200 visited nodes/section, 128-byte keys, 1024-byte text plus marker, 4096 serialized bytes/section (16384 across four section values). [REDACTED] and [TRUNCATED] mark removed data; an oversized section becomes a truncation-marker object. Absent/malformed sections are empty objects. Text is untrusted and must be escaped by renderers."
    }
  end

  defp row do
    fields =
      Map.merge(issue().properties, %{
        name: string(true),
        value: %Schema{anyOf: [%Schema{type: :number}, string(), %Schema{type: :string, nullable: true}]},
        labels: %Schema{type: :object, additionalProperties: string()},
        timestamp: string(),
        service: string(true),
        level: string(),
        message: string(),
        trace_id: string(),
        duration_ms: %Schema{type: :number, nullable: true}
      })

    %{object("PulseRow", fields) | required: []}
  end

  defp series do
    object("PulseSeries", %{
      name: string(),
      labels: %Schema{type: :object, additionalProperties: string()},
      points: points()
    })
  end

  defp meta do
    object("PulsePagination", %{
      page: %Schema{type: :integer},
      page_size: %Schema{type: :integer},
      total_count: %Schema{type: :integer},
      total_pages: %Schema{type: :integer},
      end_at: string(),
      has_next_page: %Schema{type: :boolean},
      has_previous_page: %Schema{type: :boolean}
    })
  end

  defp points, do: array(array(%Schema{anyOf: [%Schema{type: :number, nullable: true}, string()]}))
  defp warnings, do: array(string())

  defp operator,
    do: %Schema{
      type: :string,
      enum: ~w(eq contains not_contains),
      description: "Filter operator; defaults to exact equality."
    }

  defp range, do: %Schema{type: :string, enum: ~w(15m 1h 6h 24h), default: "1h"}
  defp string(nullable \\ false), do: %Schema{type: :string, nullable: nullable}
  defp array(items), do: %Schema{type: :array, items: items}

  defp object(title, fields),
    do: %Schema{title: title, type: :object, properties: fields, required: Map.keys(fields), additionalProperties: false}

  def json_schema(%Schema{anyOf: alternatives}) when is_list(alternatives),
    do: %{"anyOf" => Enum.map(alternatives, &json_schema/1)}

  def json_schema(%Schema{type: nil}), do: %{}

  def json_schema(%Schema{} = schema) do
    type = to_string(schema.type)
    json = %{"type" => if(schema.nullable, do: [type, "null"], else: type)}

    json =
      if schema.properties,
        do:
          Map.merge(json, %{
            "properties" => Map.new(schema.properties, fn {key, value} -> {to_string(key), json_schema(value)} end),
            "required" => Enum.map(schema.required || [], &to_string/1),
            "additionalProperties" => false
          }),
        else: json

    json = if schema.items, do: Map.put(json, "items", json_schema(schema.items)), else: json

    json =
      case schema.additionalProperties do
        %Schema{} = value -> Map.put(json, "additionalProperties", json_schema(value))
        _ -> json
      end

    Enum.reduce([:enum, :minimum, :maximum, :maxLength, :minItems, :maxItems, :description, :default], json, fn key,
                                                                                                                acc ->
      if is_nil(Map.get(schema, key)), do: acc, else: Map.put(acc, to_string(key), Map.get(schema, key))
    end)
  end
end
