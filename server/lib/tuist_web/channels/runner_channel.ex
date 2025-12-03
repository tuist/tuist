defmodule TuistWeb.RunnerChannel do
  @moduledoc """
  Channel for runner WebSocket connections.

  Handles runner registration, job assignments, and status updates.
  """
  use TuistWeb, :channel

  require Logger

  def join("runner:jobs", _payload, socket) do
    case socket.assigns[:current_subject] do
      nil ->
        {:error, %{reason: "unauthorized"}}

      :runner ->
        Logger.info("Runner connected with shared token")
        {:ok, socket}

      subject ->
        Logger.info("Runner connected for account: #{inspect(subject)}")
        {:ok, socket}
    end
  end

  def handle_in("runner:ready", payload, socket) do
    Logger.info("Runner ready: #{inspect(payload)}")
    {:reply, :ok, socket}
  end

  def handle_in("runner:heartbeat", payload, socket) do
    Logger.debug("Runner heartbeat: #{inspect(payload)}")
    {:reply, :ok, socket}
  end

  def handle_in("job:started", payload, socket) do
    Logger.info("Job started: #{inspect(payload)}")
    {:reply, :ok, socket}
  end

  def handle_in("job:completed", payload, socket) do
    Logger.info("Job completed: #{inspect(payload)}")
    {:reply, :ok, socket}
  end
end
