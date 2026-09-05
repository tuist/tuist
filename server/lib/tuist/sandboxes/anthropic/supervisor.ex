defmodule Tuist.Sandboxes.Anthropic.Supervisor do
  @moduledoc """
  Supervision tree for the Anthropic work-queue pollers: a registry
  keyed by agent environment id, the task supervisor dispatches run on,
  the dynamic supervisor holding one `Poller` per enabled environment,
  and the manager that reconciles pollers against the database.
  """
  use Supervisor

  alias Tuist.Sandboxes.Anthropic.Manager

  @registry Tuist.Sandboxes.Anthropic.PollerRegistry
  @task_supervisor Tuist.Sandboxes.Anthropic.TaskSupervisor
  @poller_supervisor Tuist.Sandboxes.Anthropic.PollerSupervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def registry, do: @registry
  def task_supervisor, do: @task_supervisor
  def poller_supervisor, do: @poller_supervisor

  @impl Supervisor
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: @registry},
      {Task.Supervisor, name: @task_supervisor},
      {DynamicSupervisor, name: @poller_supervisor, strategy: :one_for_one},
      Manager
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
