defmodule Tuist.Registry.BoundedTask do
  @moduledoc false

  def run(fun, timeout) do
    # Isolate task failures without orphaning work when its caller is killed.
    # The anonymous supervisor is parented by the caller and terminates its
    # temporary child on parent exit, including Oban's hard timeout.
    {:ok, supervisor} = Task.Supervisor.start_link(max_children: 1)

    try do
      task = Task.Supervisor.async_nolink(supervisor, fun, shutdown: :brutal_kill)
      Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill)
    after
      Supervisor.stop(supervisor)
    end
  end
end
