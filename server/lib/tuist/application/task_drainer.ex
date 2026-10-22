defmodule Tuist.Application.TaskDrainer do
  @moduledoc """
  Waits for optional tasks before their supervisor and ingestion buffers stop.
  """

  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    {:ok, {Keyword.fetch!(opts, :supervisor), Keyword.get(opts, :timeout, 10_000)}}
  end

  @impl true
  def terminate(_reason, {supervisor, timeout}) do
    refs = supervisor |> Task.Supervisor.children() |> MapSet.new(&Process.monitor/1)
    await_tasks(refs, System.monotonic_time(:millisecond) + timeout)
  end

  defp await_tasks(refs, deadline) do
    if MapSet.size(refs) > 0 do
      receive do
        {:DOWN, ref, :process, _pid, _reason} -> await_tasks(MapSet.delete(refs, ref), deadline)
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          Enum.each(refs, &Process.demonitor(&1, [:flush]))
          :ok
      end
    else
      :ok
    end
  end
end
