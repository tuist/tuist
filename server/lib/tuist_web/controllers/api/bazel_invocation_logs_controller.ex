defmodule TuistWeb.API.BazelInvocationLogsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Bazel
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Plugs.LoaderPlug

  @max_chunks 1_280
  @max_chunk_bytes 8 * 1_024
  @max_log_bytes 10 * 1_024 * 1_024
  @project_parameters [
    account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
    project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."]
  ]
  @request_schema %Schema{
    type: :object,
    properties: %{
      invocation_id: %Schema{type: :string, minLength: 1, maxLength: 255},
      logs: %Schema{
        type: :array,
        minItems: 1,
        maxItems: @max_chunks,
        items: %Schema{
          type: :object,
          properties: %{
            sequence_number: %Schema{type: :integer, minimum: 0},
            stream: %Schema{type: :string, enum: ["stdout", "stderr"]},
            message: %Schema{type: :string, minLength: 1, maxLength: @max_chunk_bytes}
          },
          required: [:sequence_number, :stream, :message]
        }
      }
    },
    required: [:invocation_id, :logs]
  }

  plug LoaderPlug
  plug AuthorizationPlug, :build

  tags ["Bazel"]

  operation(:create,
    summary: "Store bounded Bazel command output sent directly by the Tuist client.",
    operation_id: "createBazelInvocationLogs",
    parameters: @project_parameters,
    request_body: {"Bazel command output", "application/json", @request_schema},
    responses: %{
      accepted: {"Bazel invocation logs accepted", "application/json", %Schema{type: :object}},
      bad_request: {"Invalid request", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def create(%{assigns: %{selected_project: project}} = conn, %{"invocation_id" => invocation_id, "logs" => logs})
      when is_binary(invocation_id) and is_list(logs) do
    case logs_from_params(logs, project.id, invocation_id) do
      {:ok, logs} ->
        Bazel.create_invocation_logs(logs)

        conn
        |> put_status(:accepted)
        |> json(%{})

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Invalid Bazel invocation logs."})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{message: "Invalid Bazel invocation logs."})
  end

  defp logs_from_params(logs, project_id, invocation_id)
       when byte_size(invocation_id) in 1..255 and length(logs) <= @max_chunks do
    observed_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    logs
    |> Enum.reduce_while({:ok, [], 0}, fn log, {:ok, entries, total_bytes} ->
      with %{"sequence_number" => sequence_number, "stream" => stream, "message" => message} <- log,
           true <- is_integer(sequence_number) and sequence_number >= 0,
           true <- stream in ["stdout", "stderr"],
           true <- is_binary(message) and byte_size(message) in 1..@max_chunk_bytes,
           next_total_bytes = total_bytes + byte_size(message),
           true <- next_total_bytes <= @max_log_bytes do
        entry = %{
          invocation_id: invocation_id,
          sequence_number: sequence_number,
          stream: stream,
          message: message,
          project_id: project_id,
          observed_at: observed_at
        }

        {:cont, {:ok, [entry | entries], next_total_bytes}}
      else
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, entries, _total_bytes} when entries != [] -> {:ok, Enum.reverse(entries)}
      _ -> :error
    end
  end

  defp logs_from_params(_, _, _), do: :error
end
