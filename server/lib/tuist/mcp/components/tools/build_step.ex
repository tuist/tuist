defmodule Tuist.MCP.Components.Tools.BuildStep do
  @moduledoc "Shared MCP input and output contracts for build steps."
  alias Tuist.MCP.Tool

  @fields ~w(id title project target category status start_ms duration_ms)

  def input(source, detail) do
    {properties, required} =
      if source == :bazel do
        {%{
           "account_handle" => %{"type" => "string"},
           "project_handle" => %{"type" => "string"},
           "invocation_id" => %{
             "type" => "string",
             "description" => "Bazel invocation identifier, scoped to the project."
           }
         }, ~w(account_handle project_handle invocation_id)}
      else
        {%{"build_run_id" => %{"type" => "string", "description" => "Build UUID or Tuist build dashboard URL."}},
         ["build_run_id"]}
      end

    if detail do
      id =
        if source == :xcode,
          do: %{"type" => "string", "pattern" => "^[0-9]{1,20}$"},
          else: %{"type" => "string", "maxLength" => 128}

      %{"type" => "object", "properties" => Map.put(properties, "step_id", id), "required" => required ++ ["step_id"]}
    else
      %{"type" => "object", "properties" => Map.merge(properties, filters(source)), "required" => required}
    end
  end

  defp filters(source) do
    statuses =
      if source == :xcode,
        do: ~w(success failure),
        else: ~w(success failure unknown local_hit remote_hit cache_hit up_to_date skipped no_source)

    %{
      "page" => %{"type" => "integer", "minimum" => 1, "maximum" => 100_000},
      "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100},
      "search" => %{
        "type" => "string",
        "maxLength" => 512,
        "description" => "Case-insensitive title, project, or target search."
      },
      "project" => %{"type" => "string", "maxLength" => 512},
      "target" => %{"type" => "string", "maxLength" => 512},
      "category" => %{
        "type" => "string",
        "maxLength" => 128,
        "description" => "Exact recorded category, as returned by a recorded step."
      },
      "status" => %{
        "type" => "string",
        "enum" => statuses
      },
      "start_ms" => %{"type" => "number", "minimum" => 0},
      "end_ms" => %{"type" => "number", "minimum" => 0},
      "sort_by" => %{
        "type" => "string",
        "enum" => ["duration_ms", "start_ms"],
        "description" => "Duration descending (default) or start ascending, with step-ID tie breaking."
      }
    }
  end

  def step do
    %{
      "type" => "object",
      "properties" =>
        Map.new(@fields, &{&1, %{"type" => if(&1 in ~w(start_ms duration_ms), do: "number", else: "string")}}),
      "required" => @fields,
      "additionalProperties" => false
    }
  end

  def detail(source) do
    step = step()

    %{
      step
      | "properties" =>
          Map.merge(step["properties"], %{
            "log" => %{"type" => if(source == :xcode, do: "string", else: ["string", "null"])},
            "log_truncated" => %{"type" => "boolean"}
          }),
        "required" => @fields ++ ~w(log log_truncated)
    }
  end

  def list(source) do
    properties = %{
      "steps" => %{"type" => "array", "items" => step()},
      "availability" => %{"type" => "string", "enum" => ~w(available processing unavailable)},
      "pagination_metadata" => Tool.pagination_metadata_schema()
    }

    properties =
      if source == :xcode,
        do: properties,
        else: Map.merge(properties, %{"time_origin" => %{"type" => "string"}, "coverage" => %{"type" => "string"}})

    %{"type" => "object", "properties" => properties, "required" => Map.keys(properties), "additionalProperties" => false}
  end
end
