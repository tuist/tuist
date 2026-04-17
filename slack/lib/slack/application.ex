defmodule Slack.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if System.get_env("SKIP_MIGRATIONS") != "true" do
      migrate()
    end

    children = [
      Slack.Repo,
      {Phoenix.PubSub, name: Slack.PubSub},
      SlackWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Slack.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SlackWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp migrate do
    path = Application.app_dir(:slack, "priv/repo/migrations")

    if File.dir?(path) do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(Slack.Repo, fn repo ->
          Ecto.Migrator.run(repo, path, :up, all: true)
        end)
    end
  end
end
