defmodule Symptoms.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if Application.get_env(:symptoms, :migrate_on_boot, true) do
      migrate()
    end

    # In test the repo and Oban start from test/test_helper.exs, only when DB
    # tests are included.
    repo =
      if Application.get_env(:symptoms, :start_repo, true),
        do: [Symptoms.Repo, {Oban, Application.fetch_env!(:symptoms, Oban)}],
        else: []

    # Metrics have their own listener, which only the scraper may reach
    # (SymptomsWeb.MetricsPlug).
    metrics =
      case Application.get_env(:symptoms, :metrics_port) do
        port when is_integer(port) -> [{Bandit, plug: SymptomsWeb.MetricsPlug, port: port, scheme: :http}]
        _ -> []
      end

    children = repo ++ [SymptomsWeb.Endpoint] ++ metrics

    Supervisor.start_link(children, strategy: :one_for_one, name: Symptoms.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SymptomsWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp migrate do
    path = Application.app_dir(:symptoms, "priv/repo/migrations")

    if File.dir?(path) do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(Symptoms.Repo, fn repo ->
          Ecto.Migrator.run(repo, path, :up, all: true)
        end)
    end
  end
end
