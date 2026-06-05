defmodule TuistJit.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if System.get_env("SKIP_MIGRATIONS") != "true" do
      migrate()
    end

    children = [
      TuistJit.Repo,
      {Phoenix.PubSub, name: TuistJit.PubSub},
      {Oban, Application.fetch_env!(:tuist_jit, Oban)},
      TuistJitWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: TuistJit.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    TuistJitWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp migrate do
    path = Application.app_dir(:tuist_jit, "priv/repo/migrations")

    if File.dir?(path) do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(TuistJit.Repo, fn repo ->
          Ecto.Migrator.run(repo, path, :up, all: true)
        end)
    end
  end
end
