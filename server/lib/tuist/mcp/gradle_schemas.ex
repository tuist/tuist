defmodule Tuist.MCP.GradleSchemas do
  @moduledoc false

  def execution do
    object(%{
      "build_path" => string(),
      "task_type" => string(),
      "cacheability" => string(),
      "incremental" => %{"type" => ["boolean", "null"]},
      "remote_cache_lookup_outcome" => string()
    })
  end

  defp object(properties),
    do: %{
      "type" => "object",
      "properties" => properties,
      "required" => Map.keys(properties),
      "additionalProperties" => false
    }

  defp string, do: %{"type" => "string"}
end
