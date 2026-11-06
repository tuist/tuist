defmodule Tuist.Sandboxes.AmpOrbs do
  @moduledoc """
  Amp's self-hosted Orb dispatch contract on the sandbox substrate.

  The database owns the account-scoped Orb identity. The same cluster lock
  used by sandbox lifecycle operations serializes dispatch, including the
  first create, across web replicas. The unique index is the final identity
  fence. Amp sends pause when a thread goes idle; a running Orb whose
  guest stays quiet for ten minutes is paused as if it had (`pause_idle/2`),
  in case Amp's pause never arrives.

  Project snapshots: a pause carrying Amp's `snapshot_id` syncs the guest's
  disks and saves them as a `Tuist.Sandboxes.DiskSnapshot` on the Orb's
  node; a spawn of a new Orb carrying a `snapshot_id` the account has saved
  is cloned from it, so Amp skips the project's setup. Saving is best
  effort: a failed save never fails the pause, and Amp then reruns setup
  in the next new Orb.

  An Orb paused long enough is archived to object storage by
  `Tuist.Sandboxes.Archives`; a spawn restores it and a pause leaves it
  archived.
  """

  alias Tuist.Environment
  alias Tuist.Guardian
  alias Tuist.Kura
  alias Tuist.Repo
  alias Tuist.Runners.Sites
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.DiskSnapshots
  alias Tuist.Sandboxes.Events
  alias Tuist.Sandboxes.Sandbox

  require Logger

  @cache_scopes ["account:cache:read", "project:cache:read"]
  @cache_token_ttl_hours 6

  # The orb types a managed provider offers. An account administrator adds
  # these names under Orb types in Amp's provider settings; Amp passes the
  # thread's type to every spawn as `ORB_TYPE`, and a thread keeps it for
  # life. Threads created before the provider had types arrive without one
  # and get Linux.
  @orb_types %{
    "linux" => %{platform: :linux, template: "default", vcpus: 2, memory_mb: 4096, workspace_gb: 10},
    "macos" => %{platform: :darwin, template: "macos", vcpus: 8, memory_mb: 8192, workspace_gb: 10}
  }

  def orb_types, do: @orb_types |> Map.keys() |> Enum.sort()

  @doc "The platform and shape of an Orb type; `nil` is a thread without one."
  def orb_type(nil), do: orb_type("linux")

  def orb_type(name) do
    case Map.fetch(@orb_types, name) do
      {:ok, shape} -> {:ok, shape}
      :error -> {:error, :unknown_orb_type}
    end
  end

  def dispatch(account, orb_id, params) do
    Sandboxes.with_sandbox_lock(
      "amp:#{account.id}:#{orb_id}",
      fn ->
        sandbox = Repo.get_by(Sandbox, account_id: account.id, amp_orb_id: orb_id)

        if conflicting_integration?(sandbox, params) do
          {:error, :orb_conflict}
        else
          dispatch_operation(account, orb_id, sandbox, params)
        end
      end,
      wait: false
    )
  end

  defp conflicting_integration?(nil, _params), do: false
  defp conflicting_integration?(sandbox, %{amp_integration_id: id}), do: sandbox.amp_integration_id != id
  defp conflicting_integration?(_sandbox, _params), do: false

  defp dispatch_operation(account, orb_id, sandbox, %{operation: "spawn"} = params) do
    work_id = "amp:" <> orb_id

    created? = match?(nil, sandbox) or match?(%Sandbox{state: :error, node_name: nil}, sandbox)

    with {:ok, sandbox} <- find_or_create(account, orb_id, sandbox, params),
         {:ok, sandbox} <- Sandboxes.prepare_residency(sandbox, work_id, created: created?),
         :ok <- hold(sandbox, work_id) do
      bootstrap(account, sandbox, params)
    end
  end

  # A repeated pause/delete of an absent Orb is successful. Never create a
  # sandbox to satisfy a cleanup job or silently replace an errored disk.
  defp dispatch_operation(_account, _orb_id, nil, _params), do: {:ok, nil}

  defp dispatch_operation(_account, _orb_id, sandbox, %{operation: "delete"}) do
    with {:ok, _deleted} <- Sandboxes.delete(sandbox), do: {:ok, nil}
  end

  # Pausing an archived Orb has nothing left to do: its disks are in object
  # storage and a disk snapshot needs them on a node.
  defp dispatch_operation(_account, _orb_id, %Sandbox{state: :archived} = sandbox, %{operation: "pause"}),
    do: {:ok, sandbox}

  defp dispatch_operation(_account, _orb_id, %Sandbox{state: :paused} = sandbox, %{operation: "pause"} = params) do
    with {:ok, paused} <- Sandboxes.end_residency(sandbox) do
      save_snapshot(paused, params)
    end
  end

  defp dispatch_operation(_account, _orb_id, sandbox, %{operation: "pause"} = params), do: pause_orb(sandbox, params)

  @doc """
  Pauses a running Orb whose guest has been quiet since `last_active_at`,
  as Amp's own pause would, unless a spawn or new activity came since.
  """
  def pause_idle(sandbox_id, %DateTime{} = last_active_at) do
    case Repo.get(Sandbox, sandbox_id) do
      %Sandbox{amp_orb_id: orb_id, account_id: account_id} when is_binary(orb_id) ->
        Sandboxes.with_sandbox_lock(
          "amp:#{account_id}:#{orb_id}",
          fn -> pause_if_still_idle(sandbox_id, last_active_at) end,
          wait: false
        )

      _ ->
        {:ok, :skipped}
    end
  end

  defp pause_if_still_idle(sandbox_id, last_active_at) do
    case Repo.get(Sandbox, sandbox_id) do
      %Sandbox{state: :running, last_active_at: %DateTime{} = active_at} = sandbox ->
        if DateTime.compare(active_at, last_active_at) == :eq do
          Logger.info("sandboxes: pausing an idle Orb", sandbox_id: sandbox_id, node: sandbox.node_name)
          pause_orb(sandbox, %{})
        else
          {:ok, :skipped}
        end

      _ ->
        {:ok, :skipped}
    end
  end

  # Keep the residency until the snapshot succeeds. A failed pause must not
  # make an active Orb eligible for CI reclaim. Every pause syncs the guest's
  # disks, so they alone hold every write once a disk snapshot or the
  # archive tier drops the memory image.
  defp pause_orb(sandbox, params) do
    record_setup(sandbox)

    with {:ok, paused} <- Sandboxes.pause(sandbox),
         {:ok, paused} <- Sandboxes.end_residency(paused) do
      save_snapshot(paused, params)
    end
  end

  # A macOS host cannot see Amp's detached bootstrap, so the turn also holds
  # the VM on the host against idle eviction. A failed hold ends the turn.
  defp hold(sandbox, work_id) do
    case Sandboxes.hold_host_residency(sandbox, work_id) do
      :ok ->
        :ok

      {:error, reason} ->
        _ = Sandboxes.end_residency(sandbox)
        {:error, reason}
    end
  end

  # macOS hosts keep no disk snapshots, so a macOS thread always runs setup.
  defp save_snapshot(%Sandbox{platform: :darwin} = sandbox, _params), do: {:ok, sandbox}

  defp save_snapshot(sandbox, params) do
    with amp_snapshot_id when is_binary(amp_snapshot_id) <- snapshot_id(params),
         {:error, reason} <- DiskSnapshots.save(sandbox, amp_snapshot_id) do
      Logger.warning("sandboxes: saving an Orb project snapshot failed",
        sandbox_id: sandbox.id,
        node: sandbox.node_name,
        reason: inspect(reason)
      )
    end

    {:ok, sandbox}
  end

  defp snapshot_id(params), do: Map.get(params, :snapshot_id)

  # Amp writes `.agents/setup`'s output to this log, replacing it on every
  # run, so its birth and modification times bound the run. A marker with
  # the log's modification time keeps each run from being recorded at every
  # pause; a rerun rewrites the log and is recorded again, which the
  # analytics ignore past the first. Best effort: a slow or failed read only
  # loses the measurement.
  @setup_log "/home/user/.cache/amp/logs/setup.log"
  @setup_marker "/home/user/.cache/amp/logs/.tuist-setup-recorded"
  @setup_read ~s(f=#{@setup_log}; m=#{@setup_marker}; [ -f "$f" ] || exit 0; ) <>
                ~s([ -f "$m" ] && [ ! "$f" -nt "$m" ] && exit 0; stat -c '%W %Y' "$f" && touch -r "$f" "$m")

  defp record_setup(sandbox) do
    with {:ok, %{exit_code: 0, stdout: stdout}} <-
           Sandboxes.exec_running(sandbox, ["sh", "-c", @setup_read], cwd: "/", timeout_ms: 5_000),
         [started, finished] <- String.split(stdout),
         {started_s, ""} <- Integer.parse(started),
         {finished_s, ""} <- Integer.parse(finished) do
      Events.record_setup(sandbox, started_s, finished_s)
    end

    :ok
  end

  defp find_or_create(account, orb_id, nil, params) do
    attrs =
      params
      |> Map.take([:platform, :template, :vcpus, :memory_mb, :workspace_gb, :amp_integration_id])
      |> Map.put(:amp_orb_id, orb_id)

    Sandboxes.create_sandbox(account, attrs, from_disk_snapshot: disk_snapshot(account, attrs, params))
  end

  # Placement refusal leaves an error row with no node. It is safe to retry
  # that allocation; errors on a placed sandbox retain its disks for repair.
  defp find_or_create(account, orb_id, %Sandbox{state: :error, node_name: nil} = sandbox, params) do
    with {:ok, _deleted} <- Sandboxes.delete(sandbox), do: find_or_create(account, orb_id, nil, params)
  end

  # An Orb keeps the platform it was created on. A spawn asking for another
  # one (a type renamed in Amp, or a provider pointed at another catalog)
  # must not boot the wrong guest or migrate its disks.
  defp find_or_create(_account, _orb_id, sandbox, %{platform: platform}) when not is_nil(platform) do
    if to_string(sandbox.platform) == to_string(platform),
      do: {:ok, sandbox},
      else: {:error, :orb_type_mismatch}
  end

  defp find_or_create(_account, _orb_id, sandbox, _params), do: {:ok, sandbox}

  defp disk_snapshot(account, attrs, params) do
    case snapshot_id(params) do
      nil ->
        nil

      amp_snapshot_id ->
        default_shape = Sandboxes.default_shape()

        DiskSnapshots.find_ready(
          account.id,
          amp_snapshot_id,
          Map.get(attrs, :template) || Sandboxes.default_template(),
          Map.get(attrs, :workspace_gb) || default_shape.workspace_gb
        )
    end
  end

  defp bootstrap(account, sandbox, params) do
    env =
      Map.merge(
        %{"ORB_TOKEN" => params.orb_token, "AMP_URL" => Map.get(params, :amp_url, "https://ampcode.com")},
        cache_env(account, sandbox)
      )

    # Credentials travel in the exec environment, never in shell source,
    # argv, the database or returned output. Amp's bootstrap is detached; the
    # residency protects it after this short command exits.
    case Sandboxes.exec(sandbox, bootstrap_command(sandbox), env: env, timeout_ms: bootstrap_timeout(sandbox)) do
      {:ok, %{exit_code: 0}} ->
        {:ok, sandbox}

      _failure ->
        _ = Sandboxes.release_host_residency(sandbox, "amp:" <> sandbox.amp_orb_id)
        _ = Sandboxes.end_residency(sandbox)
        {:error, :orb_bootstrap_failed}
    end
  end

  # The macOS guest bridge, which the host copies onto each guest's disk, starts
  # Amp in its own session so the exec's process-group fence spares it. The
  # first Orb on a guest installs the Amp CLI, which can take a minute.
  defp bootstrap_command(%Sandbox{platform: :darwin}),
    do: ["/usr/local/libexec/tuist-sandbox/sbx-macos", "--orb-bootstrap"]

  defp bootstrap_command(_sandbox), do: ["/usr/local/bin/sbx-orb-bootstrap"]

  defp bootstrap_timeout(%Sandbox{platform: :darwin}), do: 120_000
  defp bootstrap_timeout(_sandbox), do: 15_000

  # Agents run arbitrary code in the guest, so it gets a read-only cache
  # credential for its own account and nothing else the API would accept.
  # The token is stateless and expires on its own; each spawn mints a fresh
  # one. The endpoint is the in-cluster cache a Linux runner on the same Node
  # would use, absent when the account has none.
  defp cache_env(account, sandbox) do
    {:ok, token, _claims} =
      Guardian.encode_and_sign(account, %{"type" => "account", "scopes" => @cache_scopes, "all_projects" => true},
        ttl: {@cache_token_ttl_hours, :hour}
      )

    env = %{"TUIST_TOKEN" => token, "TUIST_URL" => Environment.app_url()}

    platform = if sandbox.platform == :darwin, do: :macos, else: :linux

    case Kura.runner_cache_endpoint_url(account, platform, Sites.node_site(sandbox.node_name)) do
      url when is_binary(url) and url != "" -> Map.put(env, "TUIST_CACHE_ENDPOINT", url)
      _ -> env
    end
  end
end
