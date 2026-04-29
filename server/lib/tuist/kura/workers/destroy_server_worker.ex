defmodule Tuist.Kura.Workers.DestroyServerWorker do
  @moduledoc """
  Tears down a Kura server: `helm uninstall` for the release in its
  cluster, then marks the row `:destroyed`.

  The `account_cache_endpoints` row is removed up-front by
  `Tuist.Kura.destroy_server/1` so the CLI stops resolving the URL
  immediately, even before the cluster-side teardown finishes.

  Failures here are logged but do not block the row's transition to
  `:destroyed` — leaving a stuck `:destroying` row would block re-using
  the (account, cluster, spec) triple. The operator can clean up
  orphaned Helm releases manually if a destroy fails.
  """
  use Oban.Worker, queue: :kura_rollout, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.Clusters
  alias Tuist.Kura.KuraServer
  alias Tuist.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"server_id" => id}}) do
    case Repo.get(KuraServer, id) do
      nil ->
        Logger.warning("[Kura.DestroyServerWorker] server #{id} not found")
        :ok

      %KuraServer{status: :destroyed} ->
        :ok

      %KuraServer{} = server ->
        execute(server)
    end
  end

  defp execute(%KuraServer{} = server) do
    server = Repo.preload(server, :account)
    cluster = Clusters.get(server.cluster_id)

    case cluster do
      nil ->
        Logger.warning("[Kura.DestroyServerWorker] cluster #{server.cluster_id} no longer in catalog; marking destroyed anyway")
        Kura.mark_destroyed(server)

      %Clusters{} = cluster ->
        case helm_uninstall(server, cluster) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("[Kura.DestroyServerWorker] helm uninstall failed: #{inspect(reason)}")
        end

        {:ok, _} = Kura.mark_destroyed(server)
        :ok
    end
  end

  defp helm_uninstall(%KuraServer{} = server, %Clusters{} = cluster) do
    with {:ok, kubeconfig} <- resolve_kubeconfig(cluster),
         {:ok, kubeconfig_path} <- write_temp(kubeconfig) do
      {:ok, account} = Accounts.get_account_by_id(server.account_id)
      release = Clusters.release_name(account.name, cluster)
      run_helm_uninstall(release, kubeconfig_path)
    end
  end

  defp resolve_kubeconfig(%Clusters{id: id, provider: "local"}) do
    case Tuist.Environment.kura_kubeconfig(id) do
      kc when is_binary(kc) and kc != "" ->
        {:ok, kc}

      _ ->
        case System.find_executable("kind") do
          nil ->
            {:error, "no kubeconfig for cluster #{id} and kind is not on PATH"}

          _ ->
            name = Clusters.local_kind_cluster_name()

            case MuonTrap.cmd("kind", ["get", "kubeconfig", "--name", name], stderr_to_stdout: true) do
              {kubeconfig, 0} -> {:ok, kubeconfig}
              {output, _} -> {:error, "kind kubeconfig fetch failed: #{String.trim(output)}"}
            end
        end
    end
  end

  defp resolve_kubeconfig(%Clusters{id: id}) do
    case Tuist.Environment.kura_kubeconfig(id) do
      kc when is_binary(kc) and kc != "" -> {:ok, kc}
      _ -> {:error, "no kubeconfig for cluster #{id}"}
    end
  end

  defp run_helm_uninstall(release, kubeconfig_path) do
    env = [
      {~c"KUBECONFIG", String.to_charlist(kubeconfig_path)},
      {~c"PATH", String.to_charlist(System.get_env("PATH") || "/usr/local/bin:/usr/bin:/bin")}
    ]

    args = ["helm", "uninstall", release, "--namespace", "kura", "--ignore-not-found", "--wait"]

    port =
      Port.open(
        {:spawn_executable, System.find_executable("env") || "/usr/bin/env"},
        [:binary, :exit_status, :stderr_to_stdout, {:line, 4_096}, {:env, env}, {:args, args}]
      )

    drain(port, [])
  end

  defp drain(port, buffer) do
    receive do
      {^port, {:data, _}} -> drain(port, buffer)
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, status}} -> {:error, "helm uninstall exited #{status}"}
    end
  end

  defp write_temp(contents) do
    case Briefly.create(prefix: "kura-destroy-kubeconfig-", extname: ".yaml") do
      {:ok, path} ->
        case File.write(path, contents) do
          :ok -> {:ok, path}
          {:error, reason} -> {:error, "failed to write kubeconfig: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "failed to create temp kubeconfig: #{inspect(reason)}"}
    end
  end
end
