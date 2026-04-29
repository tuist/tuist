defmodule Tuist.Kura.Workers.RolloutWorker do
  @moduledoc """
  Executes a single Kura deployment.

  The worker loads a `Tuist.Kura.KuraDeployment` row, materializes the
  per-instance Helm values from the cluster catalog and the parent
  account, then shells out via `Port` to
  `kura/ops/helm/kura/rollout.sh`. The script performs the partitioned
  warm rollout (and on first install delegates to a plain
  `helm upgrade --install --wait`).

  Stdout and stderr are line-buffered into ClickHouse via
  `Tuist.Kura.append_log_lines/2` so the /ops UI can tail them in real
  time. The deployment row's `status` is updated as the worker
  progresses.

  Concurrency is constrained by the dedicated `:kura_rollout` Oban
  queue with `limit: 1` so two rollouts cannot run in parallel.
  """
  use Oban.Worker, queue: :kura_rollout, max_attempts: 1

  alias Tuist.Kura
  alias Tuist.Kura.Clusters
  alias Tuist.Kura.KuraDeployment
  alias Tuist.Kura.KuraServer
  alias Tuist.Kura.Specs
  alias Tuist.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"deployment_id" => id}}) do
    case Repo.get(KuraDeployment, id) do
      nil ->
        Logger.warning("[Kura.RolloutWorker] deployment #{id} not found")
        :ok

      %KuraDeployment{status: :running} = deployment ->
        # A second worker picked up a deployment we'd already started
        # (Oban retried us, or we crashed mid-run). The cluster-side
        # rollout is idempotent — re-running with the same image tag is
        # a no-op once steady state — but we mark this as failed so the
        # operator sees what happened and can re-trigger explicitly.
        {:ok, _} = Kura.mark_failed(deployment, "deployment was already running; manual re-trigger required")
        :ok

      %KuraDeployment{status: status} when status in [:succeeded, :failed, :cancelled] ->
        Logger.info("[Kura.RolloutWorker] deployment #{id} already in terminal state #{status}")
        :ok

      %KuraDeployment{} = deployment ->
        execute(deployment)
    end
  end

  defp execute(%KuraDeployment{} = deployment) do
    deployment = Repo.preload(deployment, [:account, :kura_server])
    account = deployment.account
    cluster = Clusters.get(deployment.cluster_id)
    server = deployment.kura_server

    case cluster do
      nil ->
        message = "cluster #{deployment.cluster_id} is no longer in the catalog"
        {:ok, _} = Kura.mark_failed(deployment, message)
        if server, do: Kura.fail_server(server)
        {:error, message}

      %Clusters{} = cluster ->
        do_execute(deployment, account, cluster, server)
    end
  end

  defp do_execute(%KuraDeployment{} = deployment, account, %Clusters{} = cluster, server) do
    case prepare(deployment, account, cluster, server) do
      {:ok, %{kubeconfig_path: kubeconfig, instance_values_path: instance_values}} ->
        {:ok, deployment} = Kura.mark_running(deployment)

        case run_rollout(deployment, account, cluster, kubeconfig, instance_values) do
          :ok ->
            if server, do: Kura.activate_server(server, deployment.image_tag)
            :ok

          {:error, _message} = error ->
            if server, do: Kura.fail_server(server)
            error
        end

      {:error, message} ->
        {:ok, _} = Kura.mark_failed(deployment, message)
        if server, do: Kura.fail_server(server)
        {:error, message}
    end
  end

  defp prepare(%KuraDeployment{} = deployment, account, %Clusters{} = cluster, server) do
    with {:ok, _chart_path} <- chart_path(),
         {:ok, kubeconfig} <- kubeconfig_for(cluster),
         {:ok, kubeconfig_path} <- write_temp(kubeconfig, "kubeconfig"),
         instance_yaml <- render_instance_values(deployment, account, cluster, server),
         {:ok, instance_values_path} <- write_temp(instance_yaml, "instance.yaml") do
      {:ok, %{kubeconfig_path: kubeconfig_path, instance_values_path: instance_values_path}}
    end
  end

  defp chart_path do
    case Application.get_env(:tuist, :kura_chart_path) do
      nil ->
        {:error,
         "kura_chart_path is not configured. Set :tuist, :kura_chart_path to the directory containing the Kura Helm chart."}

      path when is_binary(path) ->
        if File.dir?(path), do: {:ok, path}, else: {:error, "kura_chart_path #{path} is not a directory"}
    end
  end

  defp kubeconfig_for(%Clusters{id: cluster_id, provider: provider}) do
    case Tuist.Environment.kura_kubeconfig(cluster_id) do
      nil -> autodiscover_kubeconfig(cluster_id, provider)
      "" -> autodiscover_kubeconfig(cluster_id, provider)
      kubeconfig when is_binary(kubeconfig) -> {:ok, kubeconfig}
    end
  end

  # For local-provider clusters, fall back to kind so developers don't
  # need to set TUIST_KURA_KUBECONFIG_PATH_LOCAL_1. If the kind cluster
  # named by `Clusters.local_kind_cluster_name/0` doesn't exist yet we
  # auto-create it (dev/test only) — the deployment row stays at
  # `:provisioning` while kind boots, which is the right UX.
  defp autodiscover_kubeconfig(cluster_id, "local") do
    name = Clusters.local_kind_cluster_name()

    case System.find_executable("kind") do
      nil ->
        {:error,
         "no kubeconfig configured for cluster #{cluster_id} and `kind` is not on PATH " <>
           "(install via mise: mise install kind, or set TUIST_KURA_KUBECONFIG_PATH_#{String.upcase(cluster_id) |> String.replace("-", "_")} to a kubeconfig file)"}

      _ ->
        case kind_get_kubeconfig(name) do
          {:ok, kubeconfig} ->
            {:ok, kubeconfig}

          {:error, _output} ->
            with :ok <- ensure_kind_cluster(name) do
              kind_get_kubeconfig(name)
            end
        end
    end
  end

  defp autodiscover_kubeconfig(cluster_id, _provider) do
    {:error, "no kubeconfig configured for cluster #{cluster_id}"}
  end

  defp kind_get_kubeconfig(name) do
    case MuonTrap.cmd("kind", ["get", "kubeconfig", "--name", name], stderr_to_stdout: true) do
      {kubeconfig, 0} when is_binary(kubeconfig) and kubeconfig != "" -> {:ok, kubeconfig}
      {output, _status} -> {:error, output}
    end
  end

  defp ensure_kind_cluster(name) do
    if Tuist.Environment.dev?() or Tuist.Environment.test?() do
      Logger.info("[Kura.RolloutWorker] kind cluster `#{name}` missing; creating it (this takes ~60s)")

      case MuonTrap.cmd("kind", ["create", "cluster", "--name", name], stderr_to_stdout: true) do
        {_output, 0} -> :ok
        {output, _status} -> {:error, "kind create cluster failed: #{String.trim(output)}"}
      end
    else
      {:error, "kind cluster `#{name}` not found and auto-create is dev-only"}
    end
  end

  defp render_instance_values(%KuraDeployment{image_tag: image_tag} = _deployment, account, %Clusters{} = cluster, server) do
    release = Clusters.release_name(account.name, cluster)
    host = Clusters.public_url(account.name, cluster) |> URI.parse() |> Map.fetch!(:host)
    {:ok, chart_path} = chart_path()
    hook_script = File.read!(Path.join(chart_path, "hooks/tuist.lua"))
    extension_env = render_extension_env()
    spec_block = render_spec_block(server)
    persistence_block = render_persistence_block(server)

    """
    fullnameOverride: #{release}
    image:
      tag: "#{image_tag}"
    config:
      tenantId: "#{account.name}"
      region: "#{cluster.region}"
    extension:
      enabled: true
      script: |
    #{indent(hook_script, 8)}
    extraEnv:
    #{extension_env}
    #{spec_block}
    #{persistence_block}
    ingress:
      hosts:
        - host: #{host}
          paths:
            - path: /
              pathType: Prefix
      tls:
        - secretName: tuist-tls-cloudflare-origin-kura
          hosts:
            - #{host}
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app.kubernetes.io/name: kura
            app.kubernetes.io/instance: #{release}
    """
  end

  # Resource overlay derived from the server's spec. When the deployment
  # has no parent server (e.g. a standalone test deployment), fall back
  # to the defaults baked into values-managed.yaml by emitting nothing.
  defp render_spec_block(%KuraServer{spec: spec}) do
    case Specs.resource_overlay(spec) do
      %{"resources" => res} ->
        """
        resources:
          requests:
            cpu: "#{res["requests"]["cpu"]}"
            memory: "#{res["requests"]["memory"]}"
          limits:
            memory: "#{res["limits"]["memory"]}"\
        """

      _ ->
        ""
    end
  end

  defp render_spec_block(_), do: ""

  defp render_persistence_block(%KuraServer{volume_size_gi: gi}) when is_integer(gi) and gi > 0 do
    """
    persistence:
      size: #{gi}Gi\
    """
  end

  defp render_persistence_block(_), do: ""

  # Builds the YAML fragment that goes under `extraEnv:` in the per-instance
  # overlay. The chart wires these straight onto the StatefulSet, so they
  # become the env Kura's extension engine reads at startup.
  #
  # We always set the HTTP-callback target (the Tuist server URL) and the
  # shared secret. We only set the signer if the central server has a
  # license signing key; in dev/test the server returns nil and the
  # response_headers hook degrades to no-op (Kura skips unknown signers).
  defp render_extension_env do
    base = [
      env("KURA_EXTENSION_FAIL_CLOSED_AUTHENTICATE", "true"),
      env("KURA_EXTENSION_FAIL_CLOSED_AUTHORIZE", "true"),
      env("KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL", Tuist.Environment.app_url())
    ]

    base =
      case Tuist.Environment.kura_verify_token() do
        nil -> base
        token -> base ++ [env("KURA_EXTENSION_HTTP_CLIENT_TUIST_HEADERS_AUTHORIZATION", "Bearer #{token}")]
      end

    base =
      case license_signing_key() do
        nil ->
          base

        signing_key ->
          base ++
            [
              env("KURA_EXTENSION_SIGNER_TUIST_ALGORITHM", "hmac-sha256"),
              env("KURA_EXTENSION_SIGNER_TUIST_SECRET", signing_key)
            ]
      end

    Enum.join(base, "\n")
  end

  defp env(name, value) do
    # Single-quoted YAML scalar; escape embedded single quotes.
    escaped = String.replace(value || "", "'", "''")
    "  - name: #{name}\n    value: '#{escaped}'"
  end

  defp license_signing_key do
    case Tuist.License.get_license() do
      {:ok, %{signing_key: key}} when is_binary(key) and key != "" -> key
      _ -> nil
    end
  rescue
    # In dev/test there's no license; Tuist.License may raise rather than
    # return an error tuple. Treat absence as "no signing".
    _ -> nil
  end

  defp indent(text, n) do
    pad = String.duplicate(" ", n)
    text |> String.split("\n") |> Enum.map_join("\n", &(pad <> &1))
  end

  defp write_temp(contents, label) do
    case Briefly.create(prefix: "kura-#{label}-", extname: ".yaml") do
      {:ok, path} ->
        case File.write(path, contents) do
          :ok -> {:ok, path}
          {:error, reason} -> {:error, "failed to write #{label}: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "failed to create temp #{label}: #{inspect(reason)}"}
    end
  end

  defp run_rollout(%KuraDeployment{} = deployment, account, %Clusters{} = cluster, kubeconfig_path, instance_values_path) do
    {:ok, chart_path} = chart_path()

    release = Clusters.release_name(account.name, cluster)
    namespace = "kura"
    rollout_script = Path.join(chart_path, "rollout.sh")
    base_values = Path.join(chart_path, "values-managed.yaml")
    provider_values = Path.join(chart_path, "values-managed-provider-#{cluster.provider}.yaml")
    values_args = ["-f", base_values, "-f", provider_values, "-f", instance_values_path]

    env = [
      {~c"KUBECONFIG", String.to_charlist(kubeconfig_path)},
      {~c"PATH", String.to_charlist(System.get_env("PATH") || "/usr/local/bin:/usr/bin:/bin")}
    ]

    args = [rollout_script, release, namespace] ++ values_args

    Process.put(:kura_log_sequence, 0)

    port =
      Port.open(
        {:spawn_executable, ensure_executable!("/usr/bin/env")},
        [:binary, :exit_status, :stderr_to_stdout, {:line, 4_096}, {:env, env}, {:args, args}]
      )

    case stream_logs(port, deployment.id) do
      :ok ->
        {:ok, _} = Kura.mark_succeeded(deployment)
        :ok

      {:error, exit_code} ->
        message = "rollout exited with status #{exit_code}"
        {:ok, _} = Kura.mark_failed(deployment, message)
        {:error, message}
    end
  end

  defp ensure_executable!(path) do
    if File.exists?(path), do: path, else: System.find_executable("env") || raise("env binary not found")
  end

  # Reads from the Port one line at a time, batches every 25 lines or
  # 500ms into ClickHouse, returns `:ok` (or `{:error, exit_status}`)
  # when the Port exits. The sequence counter lives in the process
  # dictionary (`:kura_log_sequence`) so it monotonically increments
  # across the whole worker run regardless of how many subprocesses or
  # batches the rollout produces.
  defp stream_logs(port, deployment_id) do
    stream_loop(port, deployment_id, [], System.monotonic_time(:millisecond))
  end

  defp stream_loop(port, deployment_id, buffer, last_flush) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        buffer = [{next_sequence(), :stdout, line} | buffer]

        if length(buffer) >= 25 or System.monotonic_time(:millisecond) - last_flush >= 500 do
          flush(deployment_id, buffer)
          stream_loop(port, deployment_id, [], System.monotonic_time(:millisecond))
        else
          stream_loop(port, deployment_id, buffer, last_flush)
        end

      {^port, {:data, {:noeol, line}}} ->
        buffer = [{next_sequence(), :stdout, line} | buffer]
        flush(deployment_id, buffer)
        stream_loop(port, deployment_id, [], System.monotonic_time(:millisecond))

      {^port, {:exit_status, 0}} ->
        flush(deployment_id, buffer)
        :ok

      {^port, {:exit_status, status}} ->
        flush(deployment_id, buffer)
        {:error, status}
    end
  end

  defp next_sequence do
    seq = Process.get(:kura_log_sequence, 0) + 1
    Process.put(:kura_log_sequence, seq)
    seq
  end

  defp flush(_deployment_id, []), do: :ok

  defp flush(deployment_id, buffer) do
    {:ok, _} = Kura.append_log_lines(deployment_id, Enum.reverse(buffer))
    :ok
  end

  # Convenience: re-export so test code can poke at the helper without
  # going through Oban.
  @doc false
  def render_instance_values_for_test(deployment, account, cluster, server \\ nil) do
    render_instance_values(deployment, account, cluster, server)
  end
end
