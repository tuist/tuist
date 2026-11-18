defmodule Condukt.Sandbox.KubernetesTest do
  # Smoke tests that hit a real Kubernetes API server (kind locally, kind
  # in CI). Excluded by default; opt in with `mix test --only k8s_sandbox`.
  # They share a single namespace created in `setup_all` and clean up pods
  # in `on_exit`.
  use ExUnit.Case, async: false

  alias Condukt.Sandbox
  alias Condukt.Sandbox.Kubernetes

  @moduletag :k8s_sandbox

  @image "debian:bookworm-slim"
  @ready_timeout 180_000

  setup_all do
    {:ok, conn} = resolve_conn()
    namespace = "condukt-test-#{System.unique_integer([:positive])}"

    :ok = create_namespace(conn, namespace)
    :ok = wait_for_service_account(conn, namespace, "default", 30_000)

    on_exit(fn -> delete_namespace(conn, namespace) end)

    {:ok, conn: conn, namespace: namespace}
  end

  setup %{namespace: namespace} do
    id = "smoke-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Kubernetes.terminate(id, namespace: namespace)
    end)

    {:ok, id: id}
  end

  test "exec returns stdout from the pod", %{namespace: ns, id: id} do
    {:ok, sandbox} = open_sandbox(id, ns)
    assert {:ok, %{output: "hello\n", exit_code: 0}} = Sandbox.exec(sandbox, "echo hello")
  end

  test "exec captures stderr alongside stdout", %{namespace: ns, id: id} do
    {:ok, sandbox} = open_sandbox(id, ns)

    assert {:ok, %{output: output, exit_code: 0}} =
             Sandbox.exec(sandbox, "echo out; echo err 1>&2")

    assert output =~ "out"
    assert output =~ "err"
  end

  test "exec surfaces non-zero exit codes", %{namespace: ns, id: id} do
    {:ok, sandbox} = open_sandbox(id, ns)
    assert {:ok, %{exit_code: code}} = Sandbox.exec(sandbox, "exit 7")
    assert code != 0
  end

  test "exec enforces command timeout", %{namespace: ns, id: id} do
    {:ok, sandbox} = open_sandbox(id, ns)

    started_at = System.monotonic_time(:millisecond)
    assert {:error, :timeout} = Sandbox.exec(sandbox, "sleep 2", timeout: 500)
    elapsed = System.monotonic_time(:millisecond) - started_at

    assert elapsed < 2_000
  end

  test "read_file / write_file round-trip a binary payload", %{namespace: ns, id: id} do
    {:ok, sandbox} = open_sandbox(id, ns)
    payload = "line one\nline two\nbinary: \x00\x01\x02\n"

    assert :ok = Sandbox.write(sandbox, "/workspace/sample.bin", payload)
    assert {:ok, ^payload} = Sandbox.read(sandbox, "/workspace/sample.bin")
  end

  test "write_file streams a large payload through exec stdin", %{namespace: ns, id: id} do
    {:ok, sandbox} = open_sandbox(id, ns)
    payload = String.duplicate("0123456789abcdef", 16_384)

    assert :ok = Sandbox.write(sandbox, "/workspace/large.txt", payload)
    assert {:ok, ^payload} = Sandbox.read(sandbox, "/workspace/large.txt")
  end

  test "write_file creates parent directories", %{namespace: ns, id: id} do
    {:ok, sandbox} = open_sandbox(id, ns)

    assert :ok = Sandbox.write(sandbox, "/workspace/a/b/c.txt", "deep")
    assert {:ok, "deep"} = Sandbox.read(sandbox, "/workspace/a/b/c.txt")
  end

  test "edit_file replaces a unique occurrence", %{namespace: ns, id: id} do
    {:ok, sandbox} = open_sandbox(id, ns)

    :ok = Sandbox.write(sandbox, "/workspace/edit.txt", "Hello, World!")

    assert {:ok, %{occurrences: 1, content: "Hello, Elixir!"}} =
             Sandbox.edit(sandbox, "/workspace/edit.txt", "World", "Elixir")

    assert {:ok, "Hello, Elixir!"} = Sandbox.read(sandbox, "/workspace/edit.txt")
  end

  test "edit_file reports zero occurrences without writing", %{namespace: ns, id: id} do
    {:ok, sandbox} = open_sandbox(id, ns)

    :ok = Sandbox.write(sandbox, "/workspace/edit.txt", "Hello")

    assert {:ok, %{occurrences: 0, content: "Hello"}} =
             Sandbox.edit(sandbox, "/workspace/edit.txt", "World", "Elixir")
  end

  test "glob lists matching paths", %{namespace: ns, id: id} do
    {:ok, sandbox} = open_sandbox(id, ns)

    :ok = Sandbox.write(sandbox, "/workspace/a.txt", "1")
    :ok = Sandbox.write(sandbox, "/workspace/b.txt", "2")
    :ok = Sandbox.write(sandbox, "/workspace/skip.md", "3")

    assert {:ok, files} = Sandbox.glob(sandbox, "*.txt")
    assert "a.txt" in files
    assert "b.txt" in files
    refute "skip.md" in files
  end

  test "grep returns matches with line numbers", %{namespace: ns, id: id} do
    {:ok, sandbox} = open_sandbox(id, ns)

    :ok = Sandbox.write(sandbox, "/workspace/notes.txt", "alpha\nNEEDLE here\nbeta\n")

    assert {:ok, [match]} = Sandbox.grep(sandbox, "NEEDLE", glob: "*.txt")
    assert match.path == "notes.txt"
    assert match.line_number == 2
    assert match.line =~ "NEEDLE"
  end

  test "grep returns an empty list when there are no matches", %{namespace: ns, id: id} do
    {:ok, sandbox} = open_sandbox(id, ns)

    :ok = Sandbox.write(sandbox, "/workspace/notes.txt", "alpha\nbeta\n")

    assert {:ok, []} = Sandbox.grep(sandbox, "NEEDLE", glob: "*.txt")
  end

  test "init is idempotent for the same :id (reattaches to the same pod)", %{
    namespace: ns,
    id: id
  } do
    {:ok, first} = open_sandbox(id, ns)
    :ok = Sandbox.write(first, "/workspace/keep.txt", "persisted")

    # New sandbox handle, same id; should adopt the existing pod.
    {:ok, second} = open_sandbox(id, ns)
    assert second.state.pod_name == first.state.pod_name
    assert {:ok, "persisted"} = Sandbox.read(second, "/workspace/keep.txt")
  end

  test "a process runs in the pod apart from the handle that started it, and a new handle finds it by id",
       %{namespace: ns, id: id} do
    {:ok, first} = open_sandbox(id, ns)
    command = "echo one; while [ ! -e /tmp/gate ]; do sleep 0.1; done; echo two; exit 3"

    assert :ok = Sandbox.start_process(first, "build", command, cwd: "/tmp", env: [{"X", "1"}])
    assert {:ok, %{output: "one\n", status: :running}} = await_process(first, "build", &(&1.output == "one\n"))

    # A new handle on the same pod, as a restarted node opens.
    {:ok, second} = open_sandbox(id, ns)
    assert {:error, :already_started} = Sandbox.start_process(second, "build", command)
    assert {:ok, %{exit_code: 0}} = Sandbox.exec(second, "touch /tmp/gate")

    assert {:ok, %{output: "two\n", offset: 8, size: 8, status: {:exited, 3}}} =
             await_process(second, "build", &(&1.status != :running), 4)

    assert :ok = Sandbox.start_process(second, "slow", "sleep 30", timeout: 500)
    assert {:ok, %{status: :timeout}} = await_process(second, "slow", &(&1.status != :running))

    assert :ok = Sandbox.start_process(second, "long", "sleep 300")
    assert :ok = Sandbox.stop_process(second, "long")
    assert {:error, :not_found} = Sandbox.read_process(second, "long", 0)
    # The image has no pgrep, and the pod's own first process is a sleep.
    assert {:ok, %{output: "", exit_code: 1}} =
             Sandbox.exec(second, ~S"""
             for p in /proc/[0-9]*; do
               case "$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)" in "sleep 300 "*) exit 0 ;; esac
             done
             exit 1
             """)
  end

  test "mount/3 reports :not_supported", %{namespace: ns, id: id} do
    {:ok, sandbox} = open_sandbox(id, ns)
    assert {:error, :not_supported} = Sandbox.mount(sandbox, "/host", "/vfs")
  end

  test "terminate/2 deletes the pod", %{conn: conn, namespace: ns} do
    id = "smoke-terminate-#{System.unique_integer([:positive])}"
    {:ok, _sandbox} = open_sandbox(id, ns)

    pod_name = Kubernetes.pod_name_for(id)
    assert pod_exists?(conn, ns, pod_name)

    :ok = Kubernetes.terminate(id, namespace: ns)

    wait_until(fn -> not pod_exists?(conn, ns, pod_name) end, 60_000)
    refute pod_exists?(conn, ns, pod_name)
  end

  test "shutdown stops the heartbeat worker", %{namespace: ns, id: id} do
    {:ok, sandbox} = open_sandbox(id, ns)
    heartbeat_pid = sandbox.state.heartbeat_pid

    assert is_pid(heartbeat_pid)
    assert Process.alive?(heartbeat_pid)

    assert :ok = Sandbox.shutdown(sandbox)
    wait_until(fn -> not Process.alive?(heartbeat_pid) end, 5_000)
    refute Process.alive?(heartbeat_pid)
  end

  test "reap_stale deletes pods with old heartbeat annotations", %{conn: conn, namespace: ns} do
    id = "smoke-reap-#{System.unique_integer([:positive])}"
    {:ok, _sandbox} = open_sandbox(id, ns, heartbeat_interval: false)

    pod_name = Kubernetes.pod_name_for(id)
    old_heartbeat = DateTime.utc_now() |> DateTime.add(-3_600, :second) |> DateTime.to_iso8601()

    :ok = patch_pod_annotations(conn, ns, pod_name, %{"condukt.tuist.dev/heartbeat-at" => old_heartbeat})

    assert {:ok, [^pod_name]} = Kubernetes.reap_stale(conn: conn, namespace: ns, stale_after: 60_000)
    wait_until(fn -> not pod_exists?(conn, ns, pod_name) end, 60_000)
    refute pod_exists?(conn, ns, pod_name)
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp await_process(sandbox, id, done?, offset \\ 0, attempts \\ 100) do
    result = Sandbox.read_process(sandbox, id, offset)

    case result do
      {:ok, read} when attempts > 0 ->
        if done?.(read), do: result, else: Process.sleep(200) && await_process(sandbox, id, done?, offset, attempts - 1)

      result ->
        result
    end
  end

  defp open_sandbox(id, namespace, opts \\ []) do
    base_opts = [
      id: id,
      namespace: namespace,
      image: @image,
      ready_timeout: @ready_timeout,
      active_deadline_seconds: 3600
    ]

    Sandbox.new(Kubernetes, Keyword.merge(base_opts, opts))
  end

  defp resolve_conn do
    if System.get_env("KUBERNETES_SERVICE_HOST") do
      K8s.Conn.from_service_account()
    else
      K8s.Conn.from_file(default_kubeconfig())
    end
  end

  defp default_kubeconfig do
    case System.get_env("KUBECONFIG") do
      nil -> Path.expand("~/.kube/config")
      path -> path |> String.split(":") |> List.first()
    end
  end

  defp create_namespace(conn, name) do
    manifest = %{
      "apiVersion" => "v1",
      "kind" => "Namespace",
      "metadata" => %{"name" => name}
    }

    case K8s.Client.run(conn, K8s.Client.create(manifest)) do
      {:ok, _} -> :ok
      {:error, %{message: "already exists" <> _}} -> :ok
      {:error, reason} -> flunk("Failed to create namespace #{name}: #{inspect(reason)}")
    end
  end

  defp delete_namespace(conn, name) do
    K8s.Client.run(conn, K8s.Client.delete("v1", "Namespace", name: name))
    :ok
  end

  defp pod_exists?(conn, namespace, name) do
    case K8s.Client.run(conn, K8s.Client.get("v1", "Pod", namespace: namespace, name: name)) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp patch_pod_annotations(conn, namespace, name, annotations) do
    patch = %{"metadata" => %{"annotations" => annotations}}

    case K8s.Client.run(conn, K8s.Client.patch("v1", "Pod", [namespace: namespace, name: name], patch)) do
      {:ok, _} -> :ok
      {:error, reason} -> flunk("Failed to patch pod #{name}: #{inspect(reason)}")
    end
  end

  defp wait_for_service_account(conn, namespace, name, timeout) do
    wait_until(fn -> service_account_exists?(conn, namespace, name) end, timeout)
  end

  defp service_account_exists?(conn, namespace, name) do
    case K8s.Client.run(conn, K8s.Client.get("v1", "ServiceAccount", namespace: namespace, name: name)) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp wait_until(fun, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(fun, deadline)
  end

  defp do_wait_until(fun, deadline) do
    cond do
      fun.() -> :ok
      System.monotonic_time(:millisecond) >= deadline -> :timeout
      true -> Process.sleep(500) && do_wait_until(fun, deadline)
    end
  end
end
