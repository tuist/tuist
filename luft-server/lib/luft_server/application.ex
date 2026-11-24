defmodule LuftServer.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    if System.get_env("SKIP_MIGRATIONS") != "true" and
         Application.get_env(:luft_server, :migrate_on_boot, true) do
      migrate()
    end

    children =
      [
        LuftServer.Repo,
        {DNSCluster, query: Application.get_env(:luft_server, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: LuftServer.PubSub},
        LuftServer.Lounges.Presence,
        LuftServer.Threads.Clients,
        {Oban, Application.fetch_env!(:luft_server, Oban)},
        LuftServerWeb.Endpoint
      ] ++ thread_runtime()

    Supervisor.start_link(children, strategy: :one_for_one, name: LuftServer.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    LuftServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp thread_runtime do
    if Application.get_env(:luft_server, :start_thread_runtime, true) do
      [
        {Task.Supervisor, name: LuftServer.Threads.Tasks},
        {DynamicSupervisor, name: LuftServer.Agents.Hosts, strategy: :one_for_one},
        LuftServer.Threads.Cards,
        Supervisor.child_spec({LuftServer.Agents.Runner, []}, shutdown: 35_000)
      ]
    else
      []
    end
  end

  defp migrate do
    path = Application.app_dir(:luft_server, "priv/repo/migrations")

    if File.dir?(path) do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(LuftServer.Repo, &Ecto.Migrator.run(&1, path, :up, all: true))
    end
  end
end
