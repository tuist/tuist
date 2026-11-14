defmodule Tuist.Pulse.Schemas do
  @moduledoc "Shared HTTP and MCP contracts for authorized Pulse reads."

  alias OpenApiSpex.Schema

  def inputs(action) do
    fields =
      action
      |> options()
      |> Map.merge(%{account_handle: string(), signal: %Schema{type: :string, enum: ~w(metrics logs traces)}})

    %{object("Pulse#{action}Input", fields) | required: [:account_handle, :signal]}
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

  def options(:query) do
    %{
      range: range(),
      end_at: %Schema{
        type: :string,
        description: "ISO8601 pinned window end from the previous response's meta.end_at."
      },
      service: string(),
      service_op: operator(),
      page: %Schema{type: :integer, minimum: 1, maximum: 2_147_483_647, default: 1},
      page_size: %Schema{type: :integer, minimum: 1, maximum: 100, default: 20},
      query: %Schema{
        type: :string,
        maxLength: 4096,
        description:
          "PromQL expression for metrics; literal, case-insensitive log body or span name text for logs and traces (* selects all)."
      },
      search: string(),
      level: string(),
      level_op: operator(),
      sort_by: %Schema{
        type: :string,
        enum: ~w(name value timestamp service level message trace_id duration_ms),
        description:
          "Signal-specific column: metrics name/value; logs timestamp/service/level/message/trace_id; traces timestamp/service/name/duration_ms/trace_id."
      },
      sort_order: %Schema{type: :string, enum: ~w(asc desc)}
    }
  end

  def response(:query),
    do: object("PulseQuery", %{rows: array(row()), series: array(series()), warnings: warnings(), meta: meta()})

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

  defp row do
    fields = %{
      name: string(true),
      value: %Schema{anyOf: [%Schema{type: :number}, string(), %Schema{type: :string, nullable: true}]},
      labels: %Schema{type: :object, additionalProperties: string()},
      timestamp: string(),
      service: string(true),
      level: string(),
      message: string(),
      trace_id: string(),
      duration_ms: %Schema{type: :number, nullable: true}
    }

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
