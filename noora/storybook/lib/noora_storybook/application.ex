defmodule NooraStorybook.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: NooraStorybook.PubSub},
      NooraStorybookWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: NooraStorybook.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    NooraStorybookWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
