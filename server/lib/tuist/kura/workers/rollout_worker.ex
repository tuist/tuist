defmodule Tuist.Kura.Workers.RolloutWorker do
  @moduledoc """
  Executes a single Kura deployment.

  The worker loads a `Tuist.Kura.KuraDeployment` row, materializes the
  per-instance Helm values from the cluster catalog and the parent
  account, then shells out via `Port` to
  `kura/ops/helm/kura/rollout.sh`. The script performs the partitioned
  warm rollout from PR #10446.

  Stdout and stderr are line-buffered into ClickHouse via
  `Tuist.Kura.append_log_lines/2` so the /ops UI can tail them in real
  time. The deployment row's `status` is updated as the worker
  progresses.

  Concurrency is constrained by the cluster ID via Oban's `unique`
  options at enqueue time (set by `Tuist.Kura.create_deployment/1`)
  plus a dedicated `:kura_rollout` Oban queue with `limit: 1`. Two
  rollouts targeting the same cluster cannot run in parallel even if a
  bug bypasses uniqueness.
  """
  use Oban.Worker, queue: :kura_rollout, max_attempts: 1

  alias Tuist.Kura
  alias Tuist.Kura.Clusters
  alias Tuist.Kura.KuraDeployment
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
        # Already finished — nothing to do.
        Logger.info("[Kura.RolloutWorker] deployment #{id} already in terminal state #{status}")
        :ok

      %KuraDeployment{} = deployment ->
        execute(deployment)
    end
  end

  defp execute(%KuraDeployment{} = deployment) do
    deployment = Repo.preload(deployment, :account)
    account = deployment.account
    cluster = Clusters.get(deployment.cluster_id)

    case cluster do
      nil ->
        message = "cluster #{deployment.cluster_id} is no longer in the catalog"
        {:ok, _} = Kura.mark_failed(deployment, message)
        {:error, message}

      %Clusters{} = cluster ->
        do_execute(deployment, account, cluster)
    end
  end

  defp do_execute(%KuraDeployment{} = deployment, account, %Clusters{} = cluster) do
    case prepare(deployment, account, cluster) do
      {:ok, %{kubeconfig_path: kubeconfig, instance_values_path: instance_values}} ->
        {:ok, deployment} = Kura.mark_running(deployment)
        run_rollout(deployment, account, cluster, kubeconfig, instance_values)

      {:error, message} ->
        {:ok, _} = Kura.mark_failed(deployment, message)
        {:error, message}
    end
  end

  defp prepare(%KuraDeployment{} = deployment, account, %Clusters{} = cluster) do
    with {:ok, chart_path} <- chart_path(),
         {:ok, kubeconfig} <- kubeconfig_for(cluster),
         {:ok, kubeconfig_path} <- write_temp(kubeconfig, "kubeconfig"),
         instance_yaml <- render_instance_values(deployment, account, cluster),
         {:ok, instance_values_path} <- write_temp(instance_yaml, "instance.yaml") do
      {:ok,
       %{
         chart_path: chart_path,
         kubeconfig_path: kubeconfig_path,
         instance_values_path: instance_values_path
       }}
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

  defp kubeconfig_for(%Clusters{id: cluster_id}) do
    case Tuist.Environment.kura_kubeconfig(cluster_id) do
      nil -> {:error, "no kubeconfig configured for cluster #{cluster_id}"}
      "" -> {:error, "kubeconfig for cluster #{cluster_id} is empty"}
      kubeconfig when is_binary(kubeconfig) -> {:ok, kubeconfig}
    end
  end

  defp render_instance_values(%KuraDeployment{image_tag: image_tag} = _deployment, account, %Clusters{} = cluster) do
    release = Clusters.release_name(account.name, cluster)
    host = Clusters.public_url(account.name, cluster) |> URI.parse() |> Map.fetch!(:host)

    """
    fullnameOverride: #{release}
    image:
      tag: "#{image_tag}"
    config:
      tenantId: "#{account.name}"
      region: "#{cluster.region}"
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
    base_values = Path.join(chart_path, "values-managed.yaml")
    provider_values = Path.join(chart_path, "values-managed-provider-#{cluster.provider}.yaml")
    values_args = ["-f", base_values, "-f", provider_values, "-f", instance_values_path]

    env = [
      {~c"KUBECONFIG", String.to_charlist(kubeconfig_path)},
      {~c"PATH", String.to_charlist(System.get_env("PATH") || "/usr/local/bin:/usr/bin:/bin")}
    ]

    # The partitioned rollout script (`rollout.sh`) reads the existing
    # StatefulSet's replica count to know how to walk the partition
    # cursor; it cannot bootstrap a fresh install. Detect first install
    # and run a plain `helm upgrade --install` instead. Subsequent
    # upgrades go through the warm rollout script.
    sequence_after_namespace =
      ensure_namespace(deployment.id, namespace, env)

    {script_args, sequence_after_install} =
      if statefulset_exists?(release, namespace, env) do
        rollout_script = Path.join(chart_path, "rollout.sh")
        {[rollout_script, release, namespace] ++ values_args, sequence_after_namespace}
      else
        sequence =
          first_install(deployment.id, release, namespace, chart_path, values_args, env, sequence_after_namespace)

        # Nothing more to do — the install already brought up all
        # replicas. Skip rollout.sh and short-circuit to success.
        {nil, sequence}
      end

    case script_args do
      nil ->
        {:ok, _} = Kura.mark_succeeded(deployment)
        :ok

      args ->
        port =
          Port.open(
            {:spawn_executable, ensure_executable!("/usr/bin/env")},
            [:binary, :exit_status, :stderr_to_stdout, {:line, 4_096}, {:env, env}, {:args, args}]
          )

        case stream_logs(port, deployment.id, sequence_after_install) do
          {:ok, _seq} ->
            {:ok, _} = Kura.mark_succeeded(deployment)
            :ok

          {:error, exit_code, _seq} ->
            message = "rollout exited with status #{exit_code}"
            {:ok, _} = Kura.mark_failed(deployment, message)
            {:error, message}
        end
    end
  end

  defp ensure_namespace(deployment_id, namespace, env) do
    args = [
      "sh",
      "-c",
      "kubectl create namespace #{namespace} --dry-run=client -o yaml | kubectl apply -f -"
    ]

    run_subprocess(deployment_id, args, env, 0)
  end

  defp statefulset_exists?(release, namespace, env) do
    args = ["kubectl", "get", "statefulset", release, "-n", namespace, "-o", "name"]

    case run_subprocess_silent(args, env) do
      {0, _output} -> true
      _ -> false
    end
  end

  defp first_install(deployment_id, release, namespace, chart_path, values_args, env, sequence_in) do
    args =
      [
        "helm",
        "upgrade",
        "--install",
        release,
        chart_path,
        "--namespace",
        namespace,
        "--wait",
        "--timeout",
        "10m"
      ] ++ values_args

    run_subprocess(deployment_id, args, env, sequence_in)
  end

  # Synchronous subprocess that streams its output into ClickHouse and
  # returns the next sequence counter for downstream subprocesses to
  # use. Raises on non-zero exit so the surrounding Oban worker fails
  # the deployment.
  defp run_subprocess(deployment_id, args, env, sequence_in) do
    port =
      Port.open(
        {:spawn_executable, ensure_executable!("/usr/bin/env")},
        [:binary, :exit_status, :stderr_to_stdout, {:line, 4_096}, {:env, env}, {:args, args}]
      )

    case stream_logs(port, deployment_id, sequence_in) do
      {:ok, sequence_out} ->
        sequence_out

      {:error, exit_code, _seq} ->
        raise "subprocess exited with status #{exit_code}: #{inspect(args)}"
    end
  end

  # Same as run_subprocess/4 but discards stdout/stderr — used for the
  # statefulset existence probe so we don't pollute the deployment log
  # with kubectl error messages on first install.
  defp run_subprocess_silent(args, env) do
    port =
      Port.open(
        {:spawn_executable, ensure_executable!("/usr/bin/env")},
        [:binary, :exit_status, :stderr_to_stdout, {:env, env}, {:args, args}]
      )

    drain_silent(port, [])
  end

  defp drain_silent(port, buffer) do
    receive do
      {^port, {:data, data}} -> drain_silent(port, [data | buffer])
      {^port, {:exit_status, status}} -> {status, IO.iodata_to_binary(Enum.reverse(buffer))}
    end
  end

  defp ensure_executable!(path) do
    if File.exists?(path), do: path, else: System.find_executable("env") || raise("env binary not found")
  end

  # Reads from the Port one line at a time, batches every 25 lines or
  # 500ms into ClickHouse, returns `{:ok, last_sequence}` (or
  # `{:error, exit_status, last_sequence}`) when the Port exits.
  defp stream_logs(port, deployment_id, initial_sequence) do
    stream_loop(port, deployment_id, initial_sequence, [], System.monotonic_time(:millisecond))
  end

  defp stream_loop(port, deployment_id, sequence, buffer, last_flush) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        sequence = sequence + 1
        buffer = [{sequence, :stdout, line} | buffer]

        if length(buffer) >= 25 or System.monotonic_time(:millisecond) - last_flush >= 500 do
          flush(deployment_id, buffer)
          stream_loop(port, deployment_id, sequence, [], System.monotonic_time(:millisecond))
        else
          stream_loop(port, deployment_id, sequence, buffer, last_flush)
        end

      {^port, {:data, {:noeol, line}}} ->
        sequence = sequence + 1
        buffer = [{sequence, :stdout, line} | buffer]
        flush(deployment_id, buffer)
        stream_loop(port, deployment_id, sequence, [], System.monotonic_time(:millisecond))

      {^port, {:exit_status, 0}} ->
        flush(deployment_id, buffer)
        {:ok, sequence}

      {^port, {:exit_status, status}} ->
        flush(deployment_id, buffer)
        {:error, status, sequence}
    end
  end

  defp flush(_deployment_id, []), do: :ok

  defp flush(deployment_id, buffer) do
    {:ok, _} = Kura.append_log_lines(deployment_id, Enum.reverse(buffer))
    :ok
  end

  # Convenience: re-export so test code can poke at the helper without
  # going through Oban.
  @doc false
  def render_instance_values_for_test(deployment, account, cluster) do
    render_instance_values(deployment, account, cluster)
  end
end
