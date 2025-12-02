defmodule Runner.Runner.Connection do
  @moduledoc """
  WebSocket client for connecting to the Tuist server and receiving job assignments.

  This module maintains a persistent connection to the Tuist server and listens
  for job dispatch events. When a job is assigned, it delegates to the JobExecutor
  for execution and reports results back to the server.
  """

  use Slipstream

  require Logger

  alias Runner.Runner.JobExecutor

  @topic "runner:jobs"
  @heartbeat_interval_ms 30_000

  defstruct [
    :server_url,
    :token,
    :base_work_dir,
    :status,
    :current_job,
    :executor_task,
    :heartbeat_timer
  ]

  # Client API

  @doc """
  Starts the connection to the Tuist server.

  Options:
  - `:server_url` - The Tuist server URL
  - `:token` - The runner authentication token
  - `:base_work_dir` - Base directory for job working directories
  """
  def start_link(opts) do
    config = [
      uri: build_websocket_url(opts[:server_url], opts[:token]),
      reconnect_after_msec: [1000, 2000, 4000, 8000, 16_000]
    ]

    init_args = %{
      server_url: opts[:server_url],
      token: opts[:token],
      base_work_dir: opts[:base_work_dir] || "/tmp/tuist-runner"
    }

    Slipstream.start_link(__MODULE__, {config, init_args})
  end

  # Server callbacks

  @impl Slipstream
  def init({config, init_args}) do
    socket =
      new_socket()
      |> assign(:server_url, init_args.server_url)
      |> assign(:token, init_args.token)
      |> assign(:base_work_dir, init_args.base_work_dir)
      |> assign(:status, :connecting)
      |> assign(:current_job, nil)
      |> assign(:executor_task, nil)

    Logger.info("Connecting to Tuist server at #{init_args.server_url}")

    {:ok, connect!(socket, config)}
  end

  @impl Slipstream
  def handle_connect(socket) do
    Logger.info("Connected to Tuist server, joining #{@topic}")
    {:ok, join(socket, @topic)}
  end

  @impl Slipstream
  def handle_join(@topic, _response, socket) do
    Logger.info("Joined #{@topic} channel")

    # Send ready event
    socket = push_event(socket, "runner:ready", %{
      status: "idle",
      os: os_name(),
      architecture: architecture(),
      capabilities: %{
        github_actions: true
      }
    })

    # Start heartbeat
    timer = Process.send_after(self(), :heartbeat, @heartbeat_interval_ms)

    socket =
      socket
      |> assign(:status, :idle)
      |> assign(:heartbeat_timer, timer)

    {:ok, socket}
  end

  @impl Slipstream
  def handle_message(@topic, "job:assign", payload, socket) do
    if socket.assigns.status == :idle do
      Logger.info("Received job assignment: #{inspect(payload)}")
      handle_job_assignment(socket, payload)
    else
      Logger.warning("Received job while busy, ignoring")
      {:ok, socket}
    end
  end

  def handle_message(@topic, "job:cancel", _payload, socket) do
    Logger.info("Received job cancellation request")

    if socket.assigns.executor_task do
      # The task will handle cleanup
      Task.shutdown(socket.assigns.executor_task, :brutal_kill)
    end

    socket =
      socket
      |> assign(:status, :idle)
      |> assign(:current_job, nil)
      |> assign(:executor_task, nil)

    {:ok, socket}
  end

  def handle_message(@topic, "runner:shutdown", _payload, socket) do
    Logger.info("Received shutdown request")

    socket = assign(socket, :status, :draining)

    if socket.assigns.executor_task do
      # Wait for current job to finish
      Logger.info("Waiting for current job to complete before shutdown")
    else
      # No job running, exit immediately
      send(self(), :shutdown)
    end

    {:ok, socket}
  end

  def handle_message(topic, event, payload, socket) do
    Logger.debug("Received unknown message: #{topic}/#{event}: #{inspect(payload)}")
    {:ok, socket}
  end

  @impl Slipstream
  def handle_info(:heartbeat, socket) do
    socket = push_event(socket, "runner:heartbeat", %{
      status: to_string(socket.assigns.status),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    timer = Process.send_after(self(), :heartbeat, @heartbeat_interval_ms)
    {:noreply, assign(socket, :heartbeat_timer, timer)}
  end

  def handle_info({:job_result, job_id, result}, socket) do
    Logger.info("Job #{job_id} completed with result: #{inspect(result)}")

    # Report result to server
    socket = push_event(socket, "job:completed", %{
      job_id: job_id,
      result: to_string(result.result),
      exit_code: result.exit_code,
      duration_ms: result.duration_ms,
      error: if(result[:error], do: inspect(result.error), else: nil)
    })

    socket =
      socket
      |> assign(:status, if(socket.assigns.status == :draining, do: :draining, else: :idle))
      |> assign(:current_job, nil)
      |> assign(:executor_task, nil)

    if socket.assigns.status == :draining do
      send(self(), :shutdown)
    end

    {:noreply, socket}
  end

  def handle_info({ref, result}, socket) when is_reference(ref) do
    # Task completed
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, job_result} ->
        job_id = socket.assigns.current_job
        send(self(), {:job_result, job_id, job_result})

      {:error, reason} ->
        job_id = socket.assigns.current_job
        send(self(), {:job_result, job_id, %{result: :error, exit_code: 1, error: reason, duration_ms: 0}})
    end

    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, socket) do
    if reason != :normal do
      Logger.error("Job executor crashed: #{inspect(reason)}")
      job_id = socket.assigns.current_job
      send(self(), {:job_result, job_id, %{result: :error, exit_code: 1, error: reason, duration_ms: 0}})
    end

    {:noreply, socket}
  end

  def handle_info(:shutdown, socket) do
    Logger.info("Shutting down connection")
    {:stop, :normal, socket}
  end

  def handle_info(msg, socket) do
    Logger.debug("Received unknown info: #{inspect(msg)}")
    {:noreply, socket}
  end

  @impl Slipstream
  def handle_disconnect(reason, socket) do
    Logger.warning("Disconnected from server: #{inspect(reason)}")

    if socket.assigns[:heartbeat_timer] do
      Process.cancel_timer(socket.assigns.heartbeat_timer)
    end

    case reconnect(socket) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:stop, reason, socket}
    end
  end

  @impl Slipstream
  def handle_topic_close(topic, reason, socket) do
    Logger.warning("Topic #{topic} closed: #{inspect(reason)}")

    case rejoin(socket, topic) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:stop, reason, socket}
    end
  end

  @impl Slipstream
  def terminate(reason, socket) do
    Logger.info("Connection terminating: #{inspect(reason)}")

    if socket.assigns[:heartbeat_timer] do
      Process.cancel_timer(socket.assigns.heartbeat_timer)
    end

    :ok
  end

  # Private functions

  defp handle_job_assignment(socket, payload) do
    job_config = %{
      job_id: payload["job_id"],
      github_org: payload["github_org"],
      github_repo: payload["github_repo"],
      labels: payload["labels"] || ["self-hosted"],
      registration_token: payload["registration_token"],
      timeout_ms: payload["timeout_ms"]
    }

    # Notify server that job started
    socket = push_event(socket, "job:started", %{
      job_id: job_config.job_id,
      started_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    # Execute job in a task
    base_work_dir = socket.assigns.base_work_dir

    task =
      Task.async(fn ->
        JobExecutor.execute(job_config, base_work_dir: base_work_dir)
      end)

    socket =
      socket
      |> assign(:status, :busy)
      |> assign(:current_job, job_config.job_id)
      |> assign(:executor_task, task)

    {:ok, socket}
  end

  defp push_event(socket, event, payload) do
    case push(socket, @topic, event, payload) do
      {:ok, _ref} ->
        socket

      {:error, reason} ->
        Logger.warning("Failed to push event #{event}: #{inspect(reason)}")
        socket
    end
  end

  defp build_websocket_url(server_url, token) do
    ws_protocol = if String.starts_with?(server_url, "https"), do: "wss", else: "ws"

    server_url
    |> String.replace(~r/^https?/, ws_protocol)
    |> Kernel.<>("/socket/websocket?token=#{token}")
  end

  defp os_name do
    case :os.type() do
      {:unix, :darwin} -> "macos"
      {:unix, :linux} -> "linux"
      {:win32, _} -> "windows"
      _ -> "unknown"
    end
  end

  defp architecture do
    case :erlang.system_info(:system_architecture) |> to_string() do
      "aarch64" <> _ -> "arm64"
      "arm64" <> _ -> "arm64"
      "x86_64" <> _ -> "x64"
      "amd64" <> _ -> "x64"
      _ -> "x64"
    end
  end
end
