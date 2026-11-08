defmodule TuistLabels.Application do
  use Application

  def start(_type, _args) do
    Supervisor.start_link(
      [
        {Phoenix.PubSub, name: TuistLabels.PubSub},
        {TuistLabels.Store, TuistLabels.Store.config()},
        TuistLabelsWeb.Endpoint
      ],
      strategy: :one_for_one,
      name: TuistLabels.Supervisor
    )
  end
end
