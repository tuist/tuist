defmodule Tuist.MCP.GradleSchemas do
  @moduledoc false

  def execution do
    object(%{
      "build_path" => string(),
      "project_path" => string(),
      "task_type" => string(),
      "cacheability" => string(),
      "caching_disabled_reason" => string(),
      "execution_reasons" => strings(),
      "incremental" => %{"type" => ["boolean", "null"]},
      "remote_cache_lookup_outcome" => string(),
      "remote_cache_lookup_duration_ms" => duration(),
      "remote_cache_download_duration_ms" => duration(),
      "remote_cache_upload_duration_ms" => duration()
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
  defp strings, do: %{"type" => "array", "items" => string()}
  defp duration, do: %{"type" => ["integer", "null"]}
end
