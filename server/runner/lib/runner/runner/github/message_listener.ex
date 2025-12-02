defmodule Runner.Runner.GitHub.MessageListener do
  @moduledoc """
  GenServer that implements long-polling for GitHub Actions job messages.

  The message listener continuously polls the Broker API for new job messages.
  When a job is available, it notifies the parent process and pauses polling
  until the job is complete.

  GitHub's protocol uses HTTP long-polling with a 50-second timeout. If no
  job is available, the server returns 202 Accepted and the listener
  immediately starts a new poll.
  """

  use GenServer

  require Logger

  alias Runner.Runner.GitHub.Auth

  @runner_version "2.320.0"
  @poll_timeout_ms 55_000
  @retry_delays [1000, 2000, 4000, 8000, 16_000]

  defstruct [
    :server_url_v2,
    :credentials,
    :session_id,
    :runner_info,
    :notify_pid,
    :status,
    :retry_count
  ]

  @type message :: %{
          message_type: String.t(),
          body: map(),
          message_id: String.t() | nil
        }

  # Client API

  @doc """
  Starts the message listener.

  Options:
  - `:server_url_v2` - The Broker API URL
  - `:credentials` - Auth credentials with RSA key
  - `:session_id` - The session ID from session creation
  - `:runner_info` - Runner information (id, name, version)
  - `:notify_pid` - PID to notify when jobs are received
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Pauses the message listener (e.g., while executing a job).
  """
  def pause(pid) do
    GenServer.cast(pid, :pause)
  end

  @doc """
  Resumes polling for messages.
  """
  def resume(pid) do
    GenServer.cast(pid, :resume)
  end

  @doc """
  Stops the message listener.
  """
  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  # Server callbacks

  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      server_url_v2: Keyword.fetch!(opts, :server_url_v2),
      credentials: Keyword.fetch!(opts, :credentials),
      session_id: Keyword.fetch!(opts, :session_id),
      runner_info: Keyword.fetch!(opts, :runner_info),
      notify_pid: Keyword.fetch!(opts, :notify_pid),
      status: :polling,
      retry_count: 0
    }

    # Start polling immediately
    send(self(), :poll)

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:poll, %{status: :paused} = state) do
    # Don't poll while paused
    {:noreply, state}
  end

  def handle_info(:poll, state) do
    case poll_for_message(state) do
      {:ok, nil} ->
        # No message, poll again immediately
        send(self(), :poll)
        {:noreply, %{state | retry_count: 0}}

      {:ok, message} ->
        # Got a job message, notify parent and pause
        send(state.notify_pid, {:job_message, message})
        {:noreply, %{state | status: :paused, retry_count: 0}}

      {:error, reason} ->
        Logger.warning("Poll failed: #{inspect(reason)}")
        schedule_retry(state)
    end
  end

  @impl GenServer
  def handle_cast(:pause, state) do
    {:noreply, %{state | status: :paused}}
  end

  def handle_cast(:resume, state) do
    send(self(), :poll)
    {:noreply, %{state | status: :polling}}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    Logger.info("Message listener stopping")
    :ok
  end

  # Private functions

  defp poll_for_message(state) do
    with {:ok, credentials} <- Auth.ensure_valid_token(state.credentials) do
      do_poll(state, credentials)
    end
  end

  defp do_poll(state, credentials) do
    url = build_poll_url(state)

    headers =
      [
        {"User-Agent", "GitHubActionsRunner/#{@runner_version}"},
        {"Accept", "application/json"}
      ] ++ Auth.auth_headers(credentials)

    case Req.get(url, headers: headers, receive_timeout: @poll_timeout_ms) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse_message(body)

      {:ok, %Req.Response{status: 202}} ->
        # No message available
        {:ok, nil}

      {:ok, %Req.Response{status: 204}} ->
        # No message available
        {:ok, nil}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        # Normal timeout, just poll again
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_poll_url(state) do
    query =
      URI.encode_query(%{
        "sessionId" => state.session_id,
        "status" => "Online",
        "runnerVersion" => @runner_version,
        "os" => os_name(),
        "architecture" => architecture()
      })

    "#{state.server_url_v2}/message?#{query}"
  end

  defp parse_message(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_message(decoded)
      {:error, _} -> {:ok, nil}
    end
  end

  defp parse_message(body) when is_map(body) and map_size(body) == 0 do
    {:ok, nil}
  end

  defp parse_message(body) when is_map(body) do
    message_type = body["messageType"]

    if message_type do
      message_body =
        case body["body"] do
          body_str when is_binary(body_str) ->
            case Jason.decode(body_str) do
              {:ok, decoded} -> decoded
              {:error, _} -> %{}
            end

          body_map when is_map(body_map) ->
            body_map

          _ ->
            %{}
        end

      {:ok,
       %{
         message_type: message_type,
         body: message_body,
         message_id: body["messageId"]
       }}
    else
      {:ok, nil}
    end
  end

  defp parse_message(_), do: {:ok, nil}

  defp schedule_retry(state) do
    delay = Enum.at(@retry_delays, state.retry_count, List.last(@retry_delays))
    Process.send_after(self(), :poll, delay)
    {:noreply, %{state | retry_count: state.retry_count + 1}}
  end

  defp os_name do
    case :os.type() do
      {:unix, :darwin} -> "Darwin"
      {:unix, :linux} -> "Linux"
      {:win32, _} -> "Windows"
      _ -> "Unknown"
    end
  end

  defp architecture do
    case :erlang.system_info(:system_architecture) |> to_string() do
      "aarch64" <> _ -> "ARM64"
      "arm64" <> _ -> "ARM64"
      "x86_64" <> _ -> "X64"
      "amd64" <> _ -> "X64"
      _ -> "X64"
    end
  end
end
