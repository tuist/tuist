defmodule TuistWeb.Draining do
  @moduledoc """
  Whether this server is draining before it stops.

  The pod's `preStop` hook creates `file/0`, and this process polls for it. Once
  the file exists, or `start/0` runs from `prep_stop`, the server drains until it
  stops. `TuistWeb.Plugs.DrainingPlug` reads the flag on every response.
  """
  use GenServer

  @file_path "/tmp/tuist-server-draining"
  @interval 500

  def file, do: @file_path

  def draining?, do: :persistent_term.get(__MODULE__, false)

  def start do
    if !draining?(), do: :persistent_term.put(__MODULE__, true)
    :ok
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    state = %{file: Keyword.get(opts, :file, @file_path), interval: Keyword.get(opts, :interval, @interval)}
    {:ok, state, {:continue, :check}}
  end

  @impl true
  def handle_continue(:check, state), do: check(state)

  @impl true
  def handle_info(:check, state), do: check(state)

  defp check(%{file: file, interval: interval} = state) do
    if File.exists?(file) do
      start()
    else
      Process.send_after(self(), :check, interval)
    end

    {:noreply, state}
  end
end
