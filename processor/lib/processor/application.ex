defmodule Processor.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Processor.PubSub},
      {Finch, name: Processor.Finch},
      ProcessorWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Processor.Supervisor]

    start_sentry_logger()

    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ProcessorWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp start_sentry_logger do
    if Application.get_env(:sentry, :dsn) do
      :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
        config: %{metadata: [:file, :line]}
      })
    end
  end
end
