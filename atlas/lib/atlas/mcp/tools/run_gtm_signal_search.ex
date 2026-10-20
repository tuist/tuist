defmodule Atlas.MCP.Tools.RunGTMSignalSearch do
  @moduledoc """
  Runs the configured GTM signal collectors.
  """

  use Atlas.MCP.Tool,
    name: "run_gtm_signal_search",
    schema: %{
      "type" => "object",
      "properties" => %{
        "force" => %{
          "type" => "boolean",
          "description" => "Bypass the query cooldown and run every enabled query."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "scan" => %{
          "type" => "object",
          "properties" => %{
            "queries" => %{"type" => "integer"},
            "skipped" => %{"type" => "integer"},
            "signals" => %{"type" => "integer"},
            "errors" => %{
              "type" => "array",
              "items" => %{
                "type" => "object",
                "properties" => %{
                  "query" => %{"type" => ["string", "null"]},
                  "source" => %{"type" => "string"},
                  "reason" => %{"type" => "string"}
                },
                "required" => ["query", "reason"],
                "additionalProperties" => false
              }
            }
          },
          "required" => ["queries", "skipped", "signals", "errors"],
          "additionalProperties" => false
        }
      },
      "required" => ["scan"],
      "additionalProperties" => false
    }

  alias Atlas.GTM

  @impl EMCP.Tool
  def description,
    do: "Run due Brave and GitHub GTM signal searches, skipping recently-run queries unless force is true."

  def execute(_conn, args) do
    case GTM.scan_gtm_opportunities(force?: args["force"] == true) do
      {:ok, result} -> {:ok, %{scan: result}}
      {:error, reason} -> {:error, reason}
    end
  end
end
