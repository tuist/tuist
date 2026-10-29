defmodule Tuist.MCP.CodebaseSearch do
  @moduledoc """
  Calls the private, bounded codebase search service used by hosted Model Context Protocol tools.
  """

  alias Tuist.Environment

  @receive_timeout 5_500
  @connect_timeout 1_000

  def search(arguments), do: request("/v1/search", arguments)
  def list_files(arguments), do: request("/v1/files", arguments)
  def read_file(arguments), do: request("/v1/file", arguments)

  defp request(path, arguments) do
    case Environment.codebase_search_url() do
      nil ->
        {:error, "Tuist codebase search is not configured."}

      base_url ->
        case Req.post(base_url <> path,
               json: arguments,
               receive_timeout: @receive_timeout,
               connect_options: [timeout: @connect_timeout]
             ) do
          {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
            {:ok, body}

          {:ok, %Req.Response{status: status, body: %{"error" => error}}} when is_binary(error) ->
            {:error, "Tuist codebase search returned status #{status}: #{error}"}

          {:ok, %Req.Response{status: status}} ->
            {:error, "Tuist codebase search returned status #{status}."}

          {:error, error} ->
            {:error, "Tuist codebase search is unavailable: #{Exception.message(error)}"}
        end
    end
  end
end
