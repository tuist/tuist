defmodule Cache.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Cache.PubSub},
      Cache.KeyValueStore,
      CacheWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Cache.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CacheWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end