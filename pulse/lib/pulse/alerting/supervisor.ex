defmodule Pulse.Alerting.Supervisor do
  @moduledoc false
  use Pulse.Runtime.Supervision

  alias Pulse.Alerting.Membership
  alias Pulse.Alerting.Tasks
  alias Pulse.Alerting.Worker
  alias Pulse.Runtime
  alias Pulse.Runtime.Supervision, as: Supervisor
  alias Pulse.Runtime.Task

  def children do
    opts = Runtime.get_env(:pulse, Pulse.Alerting, [])
    enabled = Keyword.get(opts, :evaluation_enabled, false) or Keyword.get(opts, :notifications_enabled, false)
    if enabled, do: [{__MODULE__, opts}], else: []
  end

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    Supervisor.init(
      [
        %{id: Membership, start: {:pg, :start_link, [Membership]}},
        {Task.Supervisor, name: Tasks, max_children: 1},
        {Worker, opts}
      ],
      strategy: :one_for_all
    )
  end
end
