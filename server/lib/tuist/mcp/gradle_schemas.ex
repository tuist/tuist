defmodule Tuist.MCP.GradleSchemas do
  @moduledoc false

  def execution do
    object(%{
      "build_path" => string(),
      "task_type" => string(),
      "cacheability" => string(),
      "incremental" => %{"type" => ["boolean", "null"]},
      "remote_cache_lookup_outcome" => string(),
      "remote_cache_download_duration_ms" => duration(),
      "remote_cache_upload_duration_ms" => duration()
    })
  end

  def failures do
    %{
      "type" => "array",
      "description" =>
        "Why the build failed: the sanitized failure message (exception message and cause chain, at most 16 KiB) of each failed configuration operation and task, in start order, at most 32. Empty for successful builds and for plugin versions that predate failure reporting. Pass step_id to get_gradle_build_step.",
      "items" =>
        object(%{
          "step_id" => string(),
          "kind" => %{"type" => "string", "enum" => ["task", "configuration"]},
          "title" => string(),
          "project" => string(),
          "target" => string(),
          "message" => string(),
          "truncated" => %{"type" => "boolean"}
        })
    }
  end

  defp object(properties),
    do: %{
      "type" => "object",
      "properties" => properties,
      "required" => Map.keys(properties),
      "additionalProperties" => false
    }

  defp string, do: %{"type" => "string"}
  defp duration, do: %{"type" => ["integer", "null"]}
end
