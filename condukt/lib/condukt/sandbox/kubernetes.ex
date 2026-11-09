defmodule Condukt.Sandbox.Kubernetes do
  @moduledoc """
  Sandbox that runs each session inside a dedicated Kubernetes Pod.

  One Pod per session. All filesystem reads and writes and all subprocess
  execution happen inside the Pod via the Kubernetes exec API. The agent
  cannot reach the host running the Condukt BEAM process.

  ## Idempotent init via the session id

  `init/1` is idempotent on a stable id: it derives a deterministic Pod name
  from it and either adopts an existing Pod or creates a fresh one. The
  session's `:id` (passed to `Condukt.Session.start_link/1`, or
  auto-generated) flows into the sandbox by default, so a single id at the
  session level drives both the session and the Pod. This is the
  recommended pattern for Oban-style workers where the job lifecycle and
  the Pod lifecycle are decoupled:

      defmodule MyApp.AgentWorker do
        use Oban.Worker, queue: :agents, max_attempts: 3

        @impl true
        def perform(%Oban.Job{id: job_id, args: %{"prompt" => prompt}}) do
          {:ok, agent} =
            MyApp.CodingAgent.start_link(
              id: job_id,
              api_key: System.get_env("ANTHROPIC_API_KEY"),
              sandbox: {Condukt.Sandbox.Kubernetes, namespace: "agents"}
            )

          Condukt.Session.run(agent, prompt)
        end
      end

  If the job is retried after a crash, the same `job_id` flows through and
  the sandbox reattaches to the existing Pod. Repo clones and in-progress
  file edits persist (they live in an `emptyDir` volume mounted at the
  session cwd, which survives container restarts within the same Pod).

  Pass `:id` explicitly on the sandbox spec only when you want the pod
  identity to diverge from the session identity. An explicit value wins
  over the session-supplied default. When no id is supplied at the session
  level, one is generated and the pod is single-use: `shutdown/1` deletes
  it.

  ## Init options

  * `:id` — stable identifier used to derive the pod name. Defaults to the
    session id when invoked through `Condukt.Session`. Pass it explicitly
    on the sandbox spec only to diverge from the session id.
  * `:namespace` — Kubernetes namespace (default `"default"`).
  * `:image` — container image (default `"debian:bookworm-slim"`).
  * `:cwd` — working directory inside the pod, also where the workspace
    volume is mounted (default `"/workspace"`).
  * `:env` — environment variables to set on the pod container, as a map or
    list of `{key, value}` pairs.
  * `:labels` — additional pod labels (caller-supplied; merged on top of
    Condukt's defaults).
  * `:annotations` — additional pod annotations.
  * `:resources` — Kubernetes resource requests/limits map, e.g.
    `%{requests: %{cpu: "500m", memory: "1Gi"}, limits: %{cpu: "2", memory: "4Gi"}}`.
  * `:service_account` — Kubernetes ServiceAccount the pod runs as.
  * `:active_deadline_seconds` — K8s-side hard ceiling for the pod's lifetime
    (default 8 hours). Insurance against abandoned pods.
  * `:heartbeat_interval` — milliseconds between pod heartbeat annotation
    updates (default `60_000`). Pass `false` to disable. Use
    `reap_stale/1` from a separate process to delete pods whose heartbeat is
    too old.
  * `:workspace_source` — git repository to clone into the workspace at init.
    Accepts a git URL string or a keyword/map with `:git` and optional `:ref`.
    The runtime image must include `git`.
  * `:workspace_source_timeout` — milliseconds to wait for the workspace
    clone or checkout command (default `300_000`).
  * `:ready_timeout` — milliseconds to wait for a created pod to reach
    Running phase (default `120_000`).
  * `:on_stale` — what to do when adopting a pod that is in an unexpected
    phase (Succeeded / Failed). `:error` (default) returns
    `{:error, {:stale_pod, phase}}`; `:recreate` deletes and recreates.
  * `:delete_on_shutdown` — whether `shutdown/1` deletes the pod. Defaults
    to `false` when `:id` is supplied (the pod outlives any single BEAM
    process), `true` when no id is given.
  * `:conn` — already-built `K8s.Conn`. Skips kubeconfig/in-cluster
    resolution.
  * `:kubeconfig` — path to a kubeconfig file (default `~/.kube/config`).
  * `:context` — kubeconfig context name (default: current-context).
  * `:in_cluster` — `true` to use the pod's mounted ServiceAccount token.
    Auto-detected when `KUBERNETES_SERVICE_HOST` is set, so usually not
    needed.

  ## RBAC

  The Kubernetes identity used by the Condukt process needs:

      apiGroups: [""]
      resources: ["pods"]
      verbs: ["get", "list", "create", "patch", "delete"]

      apiGroups: [""]
      resources: ["pods/exec"]
      verbs: ["create"]

  See `docs/guides/sandbox.md` for a full sample `Role` + `RoleBinding`.

  ## Limitations

  * `mount/3` is not supported. Volumes cannot be added to a running pod.
  * Node failure loses the pod's `emptyDir` workspace. Mount a
    PersistentVolumeClaim into the pod manifest if you need cross-node
    durability — currently requires a custom `:image` setup, not exposed
    as an init option in v1.
  * `:workspace_source` shells out to `git` inside the pod. Use an image that
    includes `git` when enabling it.
  """

  @behaviour Condukt.Sandbox

  alias Condukt.Sandbox
  alias Condukt.Sandbox.Kubernetes.Exec
  alias Condukt.Sandbox.Kubernetes.PodSpec
  alias Condukt.Sandbox.Kubernetes.State
  alias Condukt.Sandbox.Kubernetes.WorkspaceSource
  alias Condukt.Sandbox.NetworkPolicy
  alias Condukt.Sandbox.NetworkPolicy.K8s, as: NetK8s
  alias Condukt.Sandbox.NetworkPolicy.K8s.ControlBridge

  @default_image "debian:bookworm-slim"
  @default_cwd "/workspace"
  @default_namespace "default"
  @default_active_deadline 8 * 3600
  @default_ready_timeout 120_000
  @default_heartbeat_interval 60_000
  @default_reap_stale_after 15 * 60_000
  @default_workspace_source_timeout 300_000
  @ready_poll_interval 1_000
  @timeout_exit_code 124
  @timeout_grace_ms 5_000

  @managed_by_label "app.kubernetes.io/managed-by"
  @managed_by_value "condukt"
  @id_label "condukt.tuist.dev/id"
  @created_annotation "condukt.tuist.dev/created-at"
  @heartbeat_annotation "condukt.tuist.dev/heartbeat-at"

  # ============================================================================
  # Sandbox callbacks
  # ============================================================================

  @impl Sandbox
  def init(opts) do
    with {:ok, conn} <- resolve_conn(opts),
         {:ok, config} <- build_config(opts),
         {:ok, state} <- ensure_pod(conn, config) do
      prepare_and_start(state, config)
    end
  end

  @impl Sandbox
  def shutdown(%State{} = state) do
    stop_heartbeat(state)
    stop_net_bridge(state)

    if state.delete_on_shutdown do
      delete_pod(state.conn, state.namespace, state.pod_name)
      teardown_net(state)
    end

    :ok
  end

  defp stop_net_bridge(%State{net_channel_pid: nil}), do: :ok

  defp stop_net_bridge(%State{net_channel_pid: pid}) when is_pid(pid) do
    # Idempotent: the bridge may already be gone (it collapsed when the
    # session owner went away, or it gave up on a dead control port).
    case DynamicSupervisor.terminate_child(Condukt.Application.control_channel_supervisor(), pid) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  end

  defp teardown_net(%State{net_resource_names: nil}), do: :ok

  defp teardown_net(%State{conn: conn, namespace: namespace, net_resource_names: names}) do
    NetK8s.teardown(conn, namespace, names)
  end

  @impl Sandbox
  def cwd(%State{base_cwd: base_cwd}), do: base_cwd

  @impl Sandbox
  def read_file(state, path) do
    case Exec.run(state, ["cat", "--", path]) do
      {:ok, %{output: output, exit_code: 0}} ->
        {:ok, output}

      {:ok, %{exit_code: _, output: output}} ->
        {:error, Exec.format_remote_error(output)}

      {:error, _} = err ->
        err
    end
  end

  @impl Sandbox
  def write_file(state, path, content) do
    script = """
    set -e
    mkdir -p -- "$(dirname -- #{Exec.shell_quote(path)})"
    cat > #{Exec.shell_quote(path)}
    """

    case Exec.run_with_stdin(state, ["bash", "-c", script], content) do
      {:ok, %{exit_code: 0}} -> :ok
      {:ok, %{output: output}} -> {:error, Exec.format_remote_error(output)}
      {:error, _} = err -> err
    end
  end

  @impl Sandbox
  def edit_file(state, path, old_text, new_text) do
    with {:ok, content} <- read_file(state, path) do
      apply_edit(state, path, content, old_text, new_text)
    end
  end

  @impl Sandbox
  def exec(state, command, opts) do
    cwd = Keyword.get(opts, :cwd) || state.base_cwd
    env = Keyword.get(opts, :env, [])
    timeout = Keyword.get(opts, :timeout, 120_000)

    script =
      command
      |> wrap_with_cwd(cwd)
      |> prepend_env_exports(env)
      |> wrap_with_timeout(timeout)

    case Exec.run(state, ["bash", "-c", script], timeout: timeout + @timeout_grace_ms) do
      {:ok, %{exit_code: @timeout_exit_code}} -> {:error, :timeout}
      result -> result
    end
  end

  @impl Sandbox
  def glob(state, pattern, opts) do
    base = Keyword.get(opts, :cwd) || state.base_cwd
    limit = opts[:limit]

    script = """
    cd #{Exec.shell_quote(base)} 2>/dev/null || exit 0
    shopt -s globstar nullglob dotglob
    for p in #{pattern}; do
      [ -e "$p" ] && printf '%s\\n' "$p"
    done
    """

    case Exec.run(state, ["bash", "-c", script]) do
      {:ok, %{output: output, exit_code: 0}} ->
        {:ok, output |> split_lines() |> apply_limit(limit)}

      {:ok, %{output: output}} ->
        {:error, Exec.format_remote_error(output)}

      {:error, _} = err ->
        err
    end
  end

  @impl Sandbox
  def grep(state, pattern, opts) do
    base = Keyword.get(opts, :path) || state.base_cwd
    case_sensitive? = Keyword.get(opts, :case_sensitive, true)
    file_glob = Keyword.get(opts, :glob, "**/*")
    limit = Keyword.get(opts, :limit, 1_000)

    case_flag = if case_sensitive?, do: "", else: "-i"

    script = """
    cd #{Exec.shell_quote(base)} 2>/dev/null || exit 0
    shopt -s globstar nullglob dotglob
    status=1
    for p in #{file_glob}; do
      [ -f "$p" ] || continue
      grep -Hn #{case_flag} -e #{Exec.shell_quote(pattern)} -- "$p" 2>/dev/null
      code=$?
      case "$code" in
        0) status=0 ;;
        1) ;;
        *) exit "$code" ;;
      esac
    done
    exit "$status"
    """

    case Exec.run(state, ["bash", "-c", script]) do
      {:ok, %{exit_code: 0, output: output}} -> {:ok, output |> parse_grep_output() |> apply_limit(limit)}
      {:ok, %{exit_code: 1, output: ""}} -> {:ok, []}
      {:ok, %{output: output}} -> {:error, Exec.format_remote_error(output)}
      {:error, _} = err -> err
    end
  end

  # mount/3 intentionally not implemented; running pods cannot accept volumes.

  # ============================================================================
  # Public helpers
  # ============================================================================

  @doc """
  Explicitly delete the pod backing a session.

  Use this when a session is truly done and you do not want the pod to
  outlive the BEAM process (the default when `:id` is set).

      Condukt.Sandbox.Kubernetes.terminate(id, namespace: "agents")
  """
  def terminate(id, opts \\ []) when is_binary(id) do
    namespace = Keyword.get(opts, :namespace, @default_namespace)
    pod_name = pod_name_for(id)

    with {:ok, conn} <- resolve_conn(opts) do
      delete_pod(conn, namespace, pod_name)
    end
  end

  @doc """
  Updates the heartbeat annotation on a Kubernetes sandbox pod.

  The sandbox starts a worker tied to the owner process by default. This
  helper is exposed for callers that disable the worker and want to drive
  heartbeats from their own supervision tree.
  """
  def heartbeat(%Sandbox{module: __MODULE__, state: %State{} = state}), do: heartbeat(state)

  def heartbeat(%State{} = state), do: patch_heartbeat(state)

  @doc """
  Deletes Condukt-managed pods whose heartbeat annotation is older than
  `:stale_after`.

  Options:

    * `:namespace` - namespace to scan, default `"default"`.
    * `:stale_after` - heartbeat age in milliseconds, default 15 minutes.
    * `:now` - `DateTime` used for tests, default `DateTime.utc_now()`.
    * K8s connection options accepted by `init/1`, such as `:conn`,
      `:kubeconfig`, `:context`, and `:in_cluster`.
  """
  def reap_stale(opts \\ []) do
    namespace = Keyword.get(opts, :namespace, @default_namespace)
    stale_after = Keyword.get(opts, :stale_after, @default_reap_stale_after)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    with {:ok, conn} <- resolve_conn(opts),
         {:ok, pods} <- list_pods(conn, namespace) do
      stale = Enum.filter(pods, &stale_pod?(&1, now, stale_after))
      delete_stale_pods(conn, namespace, stale)
    end
  end

  # ============================================================================
  # Pod lifecycle
  # ============================================================================

  defp ensure_pod(conn, config) do
    case get_pod(conn, config.namespace, config.pod_name) do
      {:ok, pod} -> adopt_or_recreate(conn, config, pod)
      {:error, :not_found} -> create_and_wait(conn, config)
      {:error, _} = err -> err
    end
  end

  defp adopt_or_recreate(conn, config, pod) do
    case pod_phase(pod) do
      "Running" ->
        {:ok, state_from_config(conn, config)}

      "Pending" ->
        wait_until_ready(conn, config)

      phase when phase in ["Succeeded", "Failed"] ->
        handle_stale(conn, config, phase)

      _other ->
        adopt_other_phase(conn, config, pod)
    end
  end

  defp adopt_other_phase(conn, config, pod) do
    if terminating?(pod) do
      recreate_after_deletion(conn, config)
    else
      wait_until_ready(conn, config)
    end
  end

  defp recreate_after_deletion(conn, config) do
    case wait_for_deletion(conn, config) do
      :ok -> create_and_wait(conn, config)
      err -> err
    end
  end

  defp handle_stale(conn, %{on_stale: :recreate} = config, _phase) do
    case delete_pod(conn, config.namespace, config.pod_name) do
      :ok -> recreate_after_deletion(conn, config)
      err -> err
    end
  end

  defp handle_stale(_conn, _config, phase) do
    {:error, {:stale_pod, phase}}
  end

  defp create_and_wait(conn, config) do
    with {:ok, config} <- prepare_net(conn, config) do
      labels = Map.put(config.labels, NetK8s.Manifests.session_label(), config.id)
      manifest = PodSpec.build(%{config | labels: labels})

      case K8s.Client.run(K8s.Client.put_conn(K8s.Client.create(manifest), conn)) do
        {:ok, _pod} -> wait_until_ready(conn, config)
        {:error, %{message: "already exists" <> _}} -> wait_until_ready(conn, config)
        {:error, reason} -> {:error, format_api_error(reason)}
      end
    end
  end

  defp prepare_net(_conn, %{network_policy: nil} = config), do: {:ok, config}

  defp prepare_net(conn, %{network_policy: %NetworkPolicy{} = policy} = config) do
    prepare_opts =
      %{
        session_id: config.id,
        namespace: config.namespace,
        policy: policy
      }
      |> maybe_put(:image, Map.get(config, :network_policy_image))

    with {:ok, prepared} <- NetK8s.prepare(prepare_opts),
         :ok <- NetK8s.apply(conn, prepared) do
      {:ok,
       Map.merge(config, %{
         net: prepared,
         net_policy: prepared.policy,
         net_resource_names: prepared.names
       })}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_network_policy(nil), do: nil
  defp normalize_network_policy(%NetworkPolicy{} = policy), do: policy
  defp normalize_network_policy(opts), do: NetworkPolicy.new(opts)

  defp prepare_and_start(state, config) do
    with {:ok, state} <- WorkspaceSource.prepare(state, config),
         {:ok, state} <- start_heartbeat(state, config),
         {:ok, state} <- start_net_bridge(state, config) do
      {:ok, state}
    else
      {:error, reason} ->
        cleanup_failed_init(state)
        {:error, reason}
    end
  end

  defp start_net_bridge(%State{net_policy: nil} = state, _config), do: {:ok, state}

  defp start_net_bridge(%State{net_policy: policy} = state, _config) do
    if has_decide_rule?(policy) do
      bridge_opts = [
        conn: state.conn,
        namespace: state.namespace,
        pod_name: state.pod_name,
        session_id: state.id,
        policy: policy,
        owner_pid: state.owner_pid
      ]

      spec = {ControlBridge, bridge_opts}

      case DynamicSupervisor.start_child(Condukt.Application.control_channel_supervisor(), spec) do
        {:ok, pid} -> {:ok, %{state | net_channel_pid: pid}}
        {:error, reason} -> {:error, {:net_bridge_failed, reason}}
      end
    else
      {:ok, state}
    end
  end

  defp has_decide_rule?(%NetworkPolicy{rules: rules}) do
    Enum.any?(rules, fn
      {:decide, _callable} -> true
      _ -> false
    end)
  end

  defp cleanup_failed_init(%State{delete_on_shutdown: true} = state) do
    delete_pod(state.conn, state.namespace, state.pod_name)
  end

  defp cleanup_failed_init(%State{}), do: :ok

  defp wait_until_ready(conn, config) do
    deadline = System.monotonic_time(:millisecond) + config.ready_timeout
    do_wait_until_ready(conn, config, deadline)
  end

  defp do_wait_until_ready(conn, config, deadline) do
    case get_pod(conn, config.namespace, config.pod_name) do
      {:ok, pod} -> handle_ready_poll(conn, config, deadline, pod)
      {:error, _} = err -> err
    end
  end

  defp handle_ready_poll(conn, config, deadline, pod) do
    case pod_phase(pod) do
      "Running" ->
        if container_ready?(pod),
          do: {:ok, state_from_config(conn, config)},
          else: sleep_or_timeout(conn, config, deadline)

      "Pending" ->
        sleep_or_timeout(conn, config, deadline)

      phase ->
        {:error, {:unexpected_pod_phase, phase}}
    end
  end

  defp sleep_or_timeout(conn, config, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :ready_timeout}
    else
      Process.sleep(@ready_poll_interval)
      do_wait_until_ready(conn, config, deadline)
    end
  end

  defp wait_for_deletion(conn, config) do
    deadline = System.monotonic_time(:millisecond) + config.ready_timeout
    do_wait_for_deletion(conn, config, deadline)
  end

  defp do_wait_for_deletion(conn, config, deadline) do
    case get_pod(conn, config.namespace, config.pod_name) do
      {:error, :not_found} ->
        :ok

      {:ok, _pod} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :delete_timeout}
        else
          Process.sleep(@ready_poll_interval)
          do_wait_for_deletion(conn, config, deadline)
        end

      {:error, _} = err ->
        err
    end
  end

  # ============================================================================
  # K8s client glue
  # ============================================================================

  defp get_pod(conn, namespace, name) do
    op = K8s.Client.get("v1", "Pod", namespace: namespace, name: name)

    case K8s.Client.run(conn, op) do
      {:ok, pod} -> {:ok, pod}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, %K8s.Client.APIError{reason: "NotFound"}} -> {:error, :not_found}
      {:error, reason} -> {:error, format_api_error(reason)}
    end
  end

  defp list_pods(conn, namespace) do
    op = K8s.Client.list("v1", "Pod", namespace: namespace)

    case K8s.Client.run(conn, op) do
      {:ok, %{"items" => pods}} -> {:ok, pods}
      {:error, reason} -> {:error, format_api_error(reason)}
    end
  end

  defp delete_pod(conn, namespace, name) do
    op = K8s.Client.delete("v1", "Pod", namespace: namespace, name: name)

    case K8s.Client.run(conn, op) do
      {:ok, _} -> :ok
      {:error, %{status: 404}} -> :ok
      {:error, %K8s.Client.APIError{reason: "NotFound"}} -> :ok
      {:error, reason} -> {:error, format_api_error(reason)}
    end
  end

  defp patch_heartbeat(%State{} = state) do
    patch = %{
      "metadata" => %{
        "annotations" => %{
          @heartbeat_annotation => timestamp()
        }
      }
    }

    op = K8s.Client.patch("v1", "Pod", [namespace: state.namespace, name: state.pod_name], patch)

    case K8s.Client.run(state.conn, op) do
      {:ok, _pod} -> :ok
      {:error, reason} -> {:error, format_api_error(reason)}
    end
  end

  defp delete_stale_pods(conn, namespace, pods) do
    Enum.reduce_while(pods, {:ok, []}, fn pod, {:ok, deleted} ->
      name = pod_name(pod)

      case delete_pod(conn, namespace, name) do
        :ok -> {:cont, {:ok, [name | deleted]}}
        {:error, reason} -> {:halt, {:error, {:reap_failed, name, reason}}}
      end
    end)
    |> case do
      {:ok, names} -> {:ok, Enum.reverse(names)}
      {:error, _} = err -> err
    end
  end

  # ============================================================================
  # Config / state assembly
  # ============================================================================

  defp build_config(opts) do
    {id, generated?} =
      case Keyword.get(opts, :id) do
        nil -> {Uniq.UUID.uuid7(), true}
        binary when is_binary(binary) -> {binary, false}
      end

    pod_name = pod_name_for(id)
    namespace = Keyword.get(opts, :namespace, @default_namespace)
    cwd = Keyword.get(opts, :cwd, @default_cwd)
    now = timestamp()

    delete_on_shutdown =
      Keyword.get_lazy(opts, :delete_on_shutdown, fn -> generated? end)

    with {:ok, workspace_source} <- WorkspaceSource.normalize(Keyword.get(opts, :workspace_source)),
         {:ok, heartbeat_interval} <-
           normalize_heartbeat_interval(Keyword.get(opts, :heartbeat_interval, @default_heartbeat_interval)) do
      {:ok,
       %{
         id: id,
         generated_id?: generated?,
         pod_name: pod_name,
         namespace: namespace,
         image: Keyword.get(opts, :image, @default_image),
         cwd: cwd,
         env: normalize_env(Keyword.get(opts, :env, %{})),
         labels: build_labels(id, Keyword.get(opts, :labels, %{})),
         annotations: build_annotations(Keyword.get(opts, :annotations, %{}), now),
         resources: stringify_resources(Keyword.get(opts, :resources, %{})),
         service_account: Keyword.get(opts, :service_account),
         active_deadline_seconds: Keyword.get(opts, :active_deadline_seconds, @default_active_deadline),
         heartbeat_interval: heartbeat_interval,
         workspace_source: workspace_source,
         workspace_source_timeout: Keyword.get(opts, :workspace_source_timeout, @default_workspace_source_timeout),
         ready_timeout: Keyword.get(opts, :ready_timeout, @default_ready_timeout),
         on_stale: Keyword.get(opts, :on_stale, :error),
         delete_on_shutdown: delete_on_shutdown,
         network_policy: normalize_network_policy(Keyword.get(opts, :network_policy)),
         network_policy_image: Keyword.get(opts, :network_policy_image),
         owner_pid: Keyword.get(opts, :owner_pid)
       }}
    end
  end

  defp state_from_config(conn, config) do
    %State{
      conn: conn,
      namespace: config.namespace,
      pod_name: config.pod_name,
      container: PodSpec.container_name(),
      base_cwd: config.cwd,
      id: config.id,
      delete_on_shutdown: config.delete_on_shutdown,
      net_policy: Map.get(config, :net_policy),
      net_resource_names: Map.get(config, :net_resource_names),
      owner_pid: Map.get(config, :owner_pid)
    }
  end

  defp start_heartbeat(state, %{heartbeat_interval: false}), do: {:ok, state}
  defp start_heartbeat(state, %{heartbeat_interval: nil}), do: {:ok, state}

  defp start_heartbeat(state, %{heartbeat_interval: interval}) when is_integer(interval) and interval > 0 do
    owner = self()
    pid = spawn(fn -> heartbeat_loop(Process.monitor(owner), state, interval) end)
    {:ok, %{state | heartbeat_pid: pid}}
  end

  defp start_heartbeat(_state, %{heartbeat_interval: interval}) do
    {:error, {:invalid_heartbeat_interval, interval}}
  end

  defp stop_heartbeat(%State{heartbeat_pid: nil}), do: :ok

  defp stop_heartbeat(%State{heartbeat_pid: pid}) when is_pid(pid) do
    Process.exit(pid, :shutdown)
    :ok
  end

  defp heartbeat_loop(owner_ref, state, interval) do
    _ = patch_heartbeat(state)

    receive do
      {:DOWN, ^owner_ref, :process, _pid, _reason} -> :ok
    after
      interval -> heartbeat_loop(owner_ref, state, interval)
    end
  end

  defp build_labels(id, extra) do
    base = %{
      @managed_by_label => @managed_by_value,
      @id_label => sanitize_label_value(id)
    }

    Map.merge(base, stringify_map(extra))
  end

  defp build_annotations(extra, now) do
    extra
    |> stringify_map()
    |> Map.merge(%{
      @created_annotation => now,
      @heartbeat_annotation => now
    })
  end

  defp sanitize_label_value(id) do
    id
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_.\-]/, "-")
    |> String.slice(0, 63)
    |> String.trim("-")
  end

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp stringify_resources(map) when is_map(map) and map_size(map) == 0, do: %{}

  defp stringify_resources(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_map(v) -> {to_string(k), stringify_map(v)}
      {k, v} -> {to_string(k), to_string(v)}
    end)
  end

  defp normalize_env(env) when is_map(env), do: stringify_map(env)

  defp normalize_env(env) when is_list(env) do
    Map.new(env, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp normalize_env(_), do: %{}

  defp normalize_heartbeat_interval(false), do: {:ok, false}
  defp normalize_heartbeat_interval(nil), do: {:ok, nil}

  defp normalize_heartbeat_interval(interval) when is_integer(interval) and interval > 0 do
    {:ok, interval}
  end

  defp normalize_heartbeat_interval(interval), do: {:error, {:invalid_heartbeat_interval, interval}}

  # ============================================================================
  # Connection resolution
  # ============================================================================

  defp resolve_conn(opts) do
    cond do
      conn = Keyword.get(opts, :conn) -> {:ok, conn}
      Keyword.get(opts, :in_cluster, false) -> from_service_account()
      in_cluster?() -> from_service_account()
      true -> from_kubeconfig(opts)
    end
  end

  defp in_cluster?, do: System.get_env("KUBERNETES_SERVICE_HOST") != nil

  defp from_service_account do
    case K8s.Conn.from_service_account() do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, {:k8s_conn, reason}}
    end
  end

  defp from_kubeconfig(opts) do
    path = Keyword.get(opts, :kubeconfig) || default_kubeconfig()
    conn_opts = if ctx = Keyword.get(opts, :context), do: [context: ctx], else: []

    case K8s.Conn.from_file(path, conn_opts) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, {:k8s_conn, reason}}
    end
  end

  defp default_kubeconfig do
    case System.get_env("KUBECONFIG") do
      nil -> Path.expand("~/.kube/config")
      val -> val |> String.split(":") |> List.first()
    end
  end

  # ============================================================================
  # Pod-name derivation
  # ============================================================================

  @doc false
  def pod_name_for(id) when is_binary(id) do
    sanitized =
      id
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 50)
      |> String.trim("-")

    hash =
      :crypto.hash(:sha256, id)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 6)

    prefix = if sanitized == "", do: "s", else: sanitized
    "condukt-#{prefix}-#{hash}"
  end

  # ============================================================================
  # Misc helpers
  # ============================================================================

  defp pod_phase(pod), do: get_in(pod, ["status", "phase"]) || ""

  defp pod_name(pod), do: get_in(pod, ["metadata", "name"])

  defp stale_pod?(pod, now, stale_after) do
    managed_by_condukt?(pod) and stale_heartbeat?(pod, now, stale_after)
  end

  defp managed_by_condukt?(pod) do
    get_in(pod, ["metadata", "labels", @managed_by_label]) == @managed_by_value
  end

  defp stale_heartbeat?(pod, now, stale_after) do
    pod
    |> heartbeat_timestamp()
    |> stale_timestamp?(now, stale_after)
  end

  defp heartbeat_timestamp(pod) do
    get_in(pod, ["metadata", "annotations", @heartbeat_annotation]) ||
      get_in(pod, ["metadata", "annotations", @created_annotation])
  end

  defp stale_timestamp?(nil, _now, _stale_after), do: false

  defp stale_timestamp?(value, now, stale_after) do
    case DateTime.from_iso8601(value) do
      {:ok, heartbeat_at, _offset} ->
        DateTime.diff(now, heartbeat_at, :millisecond) >= stale_after

      {:error, _reason} ->
        false
    end
  end

  defp container_ready?(pod) do
    pod
    |> get_in(["status", "containerStatuses"])
    |> List.wrap()
    |> Enum.any?(&(&1["ready"] == true))
  end

  defp terminating?(pod), do: not is_nil(get_in(pod, ["metadata", "deletionTimestamp"]))

  defp apply_edit(state, path, content, old_text, new_text) do
    case count_occurrences(content, old_text) do
      0 ->
        {:ok, %{occurrences: 0, content: content}}

      n when n > 1 ->
        {:ok, %{occurrences: n, content: content}}

      1 ->
        {:ok, new_content} = replace_first(content, old_text, new_text)

        case write_file(state, path, new_content) do
          :ok -> {:ok, %{occurrences: 1, content: new_content}}
          err -> err
        end
    end
  end

  defp count_occurrences(content, old_text) do
    content
    |> String.split(old_text)
    |> length()
    |> Kernel.-(1)
  end

  defp replace_first(content, old_text, new_text) do
    case :binary.match(content, old_text) do
      :nomatch ->
        {:ok, content}

      {index, len} ->
        new_content =
          binary_part(content, 0, index) <>
            new_text <>
            binary_part(content, index + len, byte_size(content) - index - len)

        {:ok, new_content}
    end
  end

  defp wrap_with_cwd(command, nil), do: command
  defp wrap_with_cwd(command, cwd), do: "cd #{Exec.shell_quote(cwd)} && #{command}"

  defp wrap_with_timeout(script, timeout) when is_integer(timeout) and timeout > 0 do
    seconds = timeout |> Kernel./(1_000) |> :erlang.float_to_binary(decimals: 3)

    "timeout --kill-after=5s #{seconds}s bash -c #{Exec.shell_quote(script)}"
  end

  defp wrap_with_timeout(script, _timeout), do: script

  defp prepend_env_exports(script, env) do
    normalized = normalize_env(env)

    case Enum.filter(normalized, &valid_env_key?/1) do
      [] ->
        script

      list ->
        exports =
          Enum.map_join(list, "\n", fn {k, v} -> "export #{k}=#{Exec.shell_quote(v)}" end)

        exports <> "\n" <> script
    end
  end

  defp valid_env_key?({key, _value}), do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, key)

  defp split_lines(""), do: []
  defp split_lines(s), do: String.split(s, "\n", trim: true)

  defp apply_limit(list, nil), do: list
  defp apply_limit(list, n) when is_integer(n) and n > 0, do: Enum.take(list, n)
  defp apply_limit(list, _), do: list

  defp parse_grep_output(""), do: []

  defp parse_grep_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&parse_grep_line/1)
  end

  defp parse_grep_line(line) do
    with [path, line_number, content] <- String.split(line, ":", parts: 3),
         {n, ""} <- Integer.parse(line_number) do
      [%{path: path, line_number: n, line: content}]
    else
      _ -> []
    end
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp format_api_error(%{message: message}), do: message
  defp format_api_error(reason) when is_binary(reason), do: reason
  defp format_api_error(reason), do: inspect(reason)
end
