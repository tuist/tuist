defmodule Runner.Runner.GitHub.Session do
  @moduledoc """
  Manages sessions with the GitHub Actions Broker API.

  A session must be created before the runner can poll for jobs.
  The session ID is used in all subsequent message polling requests.
  """

  require Logger

  alias Runner.Runner.GitHub.Auth

  @runner_version "2.320.0"

  @type session_info :: %{
          session_id: String.t(),
          owner_name: String.t()
        }

  @doc """
  Creates a new session with the Broker API.

  The session allows the runner to poll for job messages. The session
  must be created after registration and before starting the message listener.
  """
  @spec create_session(String.t(), Auth.credentials(), map()) ::
          {:ok, session_info()} | {:error, term()}
  def create_session(server_url_v2, credentials, runner_info) do
    with {:ok, credentials} <- Auth.ensure_valid_token(credentials) do
      do_create_session(server_url_v2, credentials, runner_info)
    end
  end

  defp do_create_session(server_url, credentials, runner_info) do
    # Azure Pipelines API uses _apis/distributedtask/pools/{poolId}/sessions
    pool_id = runner_info[:pool_id] || "1"
    agent_id = runner_info[:agent_id] || runner_info.runner_id

    # Ensure server URL ends without trailing slash, then add the API path
    base_url = String.trim_trailing(server_url, "/")
    url = "#{base_url}/_apis/distributedtask/pools/#{pool_id}/sessions?api-version=6.0-preview"

    Logger.info("Creating session at: #{url}")

    session_id = UUID.uuid4()
    owner_name = "#{hostname()}(#{System.pid()})"

    body =
      Jason.encode!(%{
        sessionId: session_id,
        ownerName: owner_name,
        agent: %{
          id: agent_id,
          name: runner_info.runner_name,
          version: @runner_version,
          osDescription: os_description(),
          ephemeral: true
        }
      })

    headers =
      [
        {"Content-Type", "application/json"},
        {"User-Agent", "GitHubActionsRunner/#{@runner_version}"}
      ] ++ Auth.auth_headers(credentials)

    Logger.info("Creating session with Broker API")

    case Req.post(url, headers: headers, body: body, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: status, body: response_body}} when status in [200, 201] ->
        Logger.info("Session created: #{session_id}")

        {:ok,
         %{
           session_id: parse_session_id(response_body, session_id),
           owner_name: owner_name
         }}

      {:ok, %Req.Response{status: 400, body: body}} ->
        parsed_body = parse_response_body(body)
        Logger.error("Session creation failed (400): #{inspect(parsed_body)}")
        {:error, {:session_rejected, parsed_body}}

      {:ok, %Req.Response{status: status, body: body}} ->
        parsed_body = parse_response_body(body)
        Logger.error("Session creation failed: status=#{status}, body=#{inspect(parsed_body)}")
        {:error, {:http_error, status, parsed_body}}

      {:error, reason} ->
        Logger.error("Session creation request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Deletes a session from the Broker API.

  Should be called during graceful shutdown to clean up resources.
  """
  @spec delete_session(String.t(), Auth.credentials(), String.t()) :: :ok | {:error, term()}
  def delete_session(server_url_v2, credentials, session_id) do
    with {:ok, credentials} <- Auth.ensure_valid_token(credentials) do
      do_delete_session(server_url_v2, credentials, session_id)
    end
  end

  defp do_delete_session(server_url_v2, credentials, session_id) do
    url = "#{server_url_v2}/sessions/#{session_id}"

    headers =
      [
        {"User-Agent", "GitHubActionsRunner/#{@runner_version}"}
      ] ++ Auth.auth_headers(credentials)

    Logger.info("Deleting session: #{session_id}")

    case Req.delete(url, headers: headers, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: status}} when status in [200, 204] ->
        Logger.info("Session deleted successfully")
        :ok

      {:ok, %Req.Response{status: 404}} ->
        # Session already gone, that's fine
        Logger.debug("Session not found (already deleted)")
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Session deletion returned unexpected status: #{status}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("Session deletion request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp parse_session_id(body, default) when is_map(body) do
    body["sessionId"] || default
  end

  defp parse_session_id(body, default) when is_binary(body) do
    case Jason.decode(strip_bom(body)) do
      {:ok, decoded} -> parse_session_id(decoded, default)
      {:error, _} -> default
    end
  end

  defp parse_session_id(_, default), do: default

  defp parse_response_body(body) when is_binary(body) do
    case Jason.decode(strip_bom(body)) do
      {:ok, decoded} -> decoded
      {:error, _} -> body
    end
  end

  defp parse_response_body(body) when is_map(body), do: body
  defp parse_response_body(body), do: body

  # Strip UTF-8 BOM if present
  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(body), do: body

  defp hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _ -> "unknown"
    end
  end

  defp os_description do
    {os_family, os_name} = :os.type()
    version = :os.version()

    version_string =
      case version do
        {major, minor, patch} -> "#{major}.#{minor}.#{patch}"
        _ -> "unknown"
      end

    "#{os_family}/#{os_name} #{version_string}"
  end
end
