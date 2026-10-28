defmodule Atlas.Signals.Interface do
  @moduledoc "Shared, closed contracts for portable signal API/MCP operations."

  @id %{"type" => "string", "format" => "uuid"}
  @page %{"type" => "integer", "minimum" => 1, "maximum" => 100_000}

  def schema(:create_signal_source) do
    object(
      %{
        "name" => nonblank(120),
        "revision_id" => @id,
        "reader_ids" => array(@id, 30),
        "required_scopes" => array(text(100), 100),
        "routing_roles" => array(text(100), 10),
        "event_receiver" =>
          object(
            %{
              "name" => nonblank(100),
              "title" => nonblank(200),
              "summary" => nonblank(1000),
              "match" => %{
                "type" => "object",
                "minProperties" => 1,
                "maxProperties" => 10,
                "additionalProperties" => %{
                  "anyOf" => [
                    text(200),
                    %{"type" => "boolean"},
                    %{"type" => "integer", "minimum" => -9_007_199_254_740_991, "maximum" => 9_007_199_254_740_991}
                  ]
                }
              },
              "correlation_field" => Map.put(text(100), "pattern", "^[a-zA-Z_][a-zA-Z0-9_]*$"),
              "subjects" => array(text(200), 20),
              "topics" => array(text(100), 20)
            },
            ~w(name title summary match correlation_field subjects topics)
          )
      },
      ~w(name revision_id reader_ids required_scopes)
    )
  end

  def schema(:list_signal_sources), do: object(%{"page" => @page}, [])
  def schema(:list_signals), do: object(%{"page" => @page, "status" => %{"enum" => ~w(pending opened ignored)}}, [])
  def schema(:get_signal), do: object(%{"id" => @id}, ["id"])
  def schema(:signal_candidates), do: schema(:get_signal)
  def schema(:decide_signal), do: decision_schema()

  def schema(:set_signal_source_enabled),
    do: object(%{"id" => @id, "enabled" => %{"type" => "boolean"}}, ~w(id enabled))

  def schema(:ingest_signal), do: object(%{"id" => @id, "envelope" => envelope_schema()}, ~w(id envelope))

  def envelope_schema do
    object(
      %{
        "external_id" => text(200),
        "correlation_key" => text(200),
        "type" => text(100),
        "schema_version" => %{"type" => "integer", "minimum" => 1, "maximum" => 2_147_483_647},
        "occurred_at" => %{"type" => "string", "format" => "date-time"},
        "title" => nonblank(200),
        "summary" => text(1000),
        "subjects" => array(text(200), 20),
        "topics" => array(text(100), 20),
        "data" => %{"type" => "object"}
      },
      ~w(external_id correlation_key type schema_version occurred_at title summary)
    )
  end

  def decision_schema do
    object(
      %{
        "signal_id" => @id,
        "action" => %{"enum" => ~w(opened ignored)},
        "priority" => %{"enum" => ~w(now today later)},
        "reason" => text(500)
      },
      ~w(signal_id action priority reason)
    )
  end

  def receipt_schema do
    object(
      %{
        "id" => @id,
        "source_id" => @id,
        "status" => %{"enum" => ~w(pending opened ignored)},
        "priority" => %{"type" => ["string", "null"]},
        "thread_id" => %{"type" => ["string", "null"]},
        "execution_id" => %{"type" => ["string", "null"]},
        "observed_at" => %{"type" => "string"}
      },
      ~w(id source_id status priority thread_id execution_id observed_at)
    )
  end

  def dispatch(:create_signal_source, actor, args, opts), do: Atlas.Signals.create_source(actor, args, opts)
  def dispatch(:list_signal_sources, actor, args, _opts), do: Atlas.Signals.list_sources(actor, args)
  def dispatch(:list_signals, actor, args, _opts), do: Atlas.Signals.list(actor, args)
  def dispatch(:get_signal, actor, args, _opts), do: Atlas.Signals.get(actor, args["id"])
  def dispatch(:signal_candidates, actor, args, _opts), do: Atlas.Signals.candidates(actor, args["id"])

  def dispatch(:set_signal_source_enabled, actor, args, opts),
    do: Atlas.Signals.set_enabled(actor, args["id"], args["enabled"], opts)

  def dispatch(:ingest_signal, actor, args, opts), do: Atlas.Signals.ingest(actor, args["id"], args["envelope"], opts)
  def dispatch(:decide_signal, actor, args, opts), do: Atlas.Signals.decide(actor, args, opts)

  defp nonblank(max), do: Map.put(text(max), "pattern", "^[^\\x00]*[^\\s\\x00][^\\x00]*$")

  defp text(max), do: %{"type" => "string", "minLength" => 1, "maxLength" => max, "pattern" => "^[^\\x00]+$"}

  defp array(items, max), do: %{"type" => "array", "items" => items, "maxItems" => max, "uniqueItems" => true}

  defp object(properties, required),
    do: %{"type" => "object", "properties" => properties, "required" => required, "additionalProperties" => false}
end
