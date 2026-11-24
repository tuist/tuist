defmodule Tuist.MCP.Components.Tools.BazelRemoteAction do
  @moduledoc false

  @milliseconds %{
    "type" => ["number", "null"],
    "description" => "Milliseconds between the executor's reported timestamps; null when not reported."
  }
  @summary_properties %{
    "id" => %{"type" => "string", "description" => "The remote execution operation ID."},
    "invocation_id" => %{"type" => "string"},
    "action_digest" => %{
      "type" => "object",
      "properties" => %{"hash" => %{"type" => "string"}, "size_bytes" => %{"type" => "integer"}},
      "required" => ["hash", "size_bytes"],
      "additionalProperties" => false
    },
    "mnemonic" => %{"type" => "string"},
    "target" => %{"type" => "string"},
    "execution_path" => %{
      "type" => "string",
      "description" => "`scheduled` or `lease` (a worker leased for the invocation); empty when unknown."
    },
    "memory_gb" => %{"type" => "integer"},
    "cached_result" => %{"type" => "boolean"},
    "status_code" => %{"type" => "integer", "description" => "The gRPC status of the execution; 0 is OK."},
    "exit_code" => %{"type" => "integer"},
    "queued_at" => %{"type" => ["string", "null"]},
    "duration_ms" => @milliseconds,
    "queue_ms" => @milliseconds,
    "input_fetch_ms" => @milliseconds,
    "execution_ms" => @milliseconds,
    "output_upload_ms" => @milliseconds
  }
  @pairs %{
    "type" => "array",
    "items" => %{
      "type" => "object",
      "properties" => %{"name" => %{"type" => "string"}, "value" => %{"type" => "string"}},
      "required" => ["name", "value"],
      "additionalProperties" => false
    }
  }
  @detail_properties Map.merge(@summary_properties, %{
                       "tool_name" => %{"type" => "string"},
                       "tool_version" => %{"type" => "string"},
                       "configuration_id" => %{"type" => "string"},
                       "worker" => %{"type" => "string"},
                       "sandbox_id" => %{"type" => "string"},
                       "timeout_ms" => %{"type" => "integer"},
                       "do_not_cache" => %{"type" => "boolean"},
                       "arguments" => %{"type" => "array", "items" => %{"type" => "string"}},
                       "arguments_truncated" => %{"type" => "boolean"},
                       "environment" =>
                         Map.put(
                           @pairs,
                           "description",
                           "Values of variables whose names contain TOKEN, SECRET, PASSWORD or KEY are ****."
                         ),
                       "working_directory" => %{
                         "type" => "string",
                         "description" =>
                           "Relative to the action's input root, which is /workspace/action on Tuist's workers. Empty for the input root itself."
                       },
                       "platform" => @pairs,
                       "output_paths" => %{
                         "type" => "array",
                         "items" => %{"type" => "string"},
                         "description" => "The declared outputs, up to 32 KiB of paths."
                       },
                       "output_count" => %{
                         "type" => "integer",
                         "description" =>
                           "How many outputs the command declared; more than output_paths when the list was cut."
                       },
                       "status_message" => %{"type" => "string"},
                       "stdout" => %{"type" => "string", "description" => "Up to the first 16 KiB."},
                       "stdout_size_bytes" => %{"type" => "integer"},
                       "stdout_truncated" => %{"type" => "boolean"},
                       "stderr" => %{"type" => "string", "description" => "Up to the first 16 KiB."},
                       "stderr_size_bytes" => %{"type" => "integer"},
                       "stderr_truncated" => %{"type" => "boolean"},
                       "timestamps" => %{
                         "type" => "object",
                         "additionalProperties" => %{"type" => ["string", "null"]}
                       },
                       "errors" => %{
                         "type" => "array",
                         "description" =>
                           "Compiler errors recognised in the recorded stderr of a failed action, in order; empty when none were recognised.",
                         "items" => %{
                           "type" => "object",
                           "properties" => %{
                             "path" => %{"type" => "string"},
                             "line" => %{"type" => "integer"},
                             "column" => %{"type" => ["integer", "null"]},
                             "message" => %{"type" => "string"}
                           },
                           "required" => ["path", "line", "column", "message"],
                           "additionalProperties" => false
                         }
                       }
                     })

  def summary_schema, do: object(@summary_properties)
  def schema, do: object(@detail_properties)

  def input(properties \\ %{}, required \\ []) do
    %{
      "type" => "object",
      "properties" =>
        Map.merge(
          %{
            "account_handle" => %{"type" => "string", "description" => "The account handle."},
            "project_handle" => %{"type" => "string", "description" => "The project handle."},
            "invocation_id" => %{"type" => "string", "description" => "The Bazel invocation identifier."}
          },
          properties
        ),
      "required" => ["account_handle", "project_handle", "invocation_id" | required]
    }
  end

  defp object(properties),
    do: %{
      "type" => "object",
      "properties" => properties,
      "required" => Map.keys(properties),
      "additionalProperties" => false
    }
end
