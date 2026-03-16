defmodule FlakyFixRunner.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: FlakyFixRunner.PubSub},
      {Finch, name: FlakyFixRunner.Finch},
      {Task.Supervisor, name: FlakyFixRunner.TaskSupervisor},
      FlakyFixRunnerWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: FlakyFixRunner.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    FlakyFixRunnerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
