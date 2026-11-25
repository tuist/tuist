defmodule Tuist.Sandboxes.ClaudeCodeSnapshots do
  @moduledoc """
  Repo-ready disk snapshots for Claude Code sessions on Linux and macOS.

  A `:claude_code` environment with a `setup_script` boots a new session's
  sandbox from the newest snapshot of the session's repository (`find/2`).
  A new session that finds none starts on the template as before and asks
  for a build (`request_build/2`), so the sessions after it find one. No
  session waits for a build, so the script can take as long as a build
  allows: clone, dependencies, a prebuild.

  A build (`DiskSnapshots.start_build/3`) runs in a builder sandbox of the
  environment's shape that no session uses and that has the build's id.
  One detached command (`Tuist.Sandboxes.Commands`, at most an hour, with
  the build's id too) clones the default branch to where the runner keeps
  its clone and runs the script there as the runner's user in a Bash login
  shell, its output teed to `~/.claude-code-setup.log`. `advance/1`, which
  `Tuist.Sandboxes.Workers.BuildRepositorySnapshotWorker` runs until the
  build ends, follows it. When the command exits 0, it pauses the builder,
  which syncs its disks, saves them (`DiskSnapshots.save_build/2`) and
  deletes the builder. A node without disk for the snapshot keeps the
  paused builder and is asked to make room until the build expires; any
  other end fails the build, which keeps the
  script from building the repository again for an hour.

  Only the clone gets a credential: the token `Router.credentials/3` mints
  for that repository, in the command's environment, unset before the
  script runs. The script gets the Tuist environment
  (`Sandboxes.tuist_env/2`), which holds none, so the snapshot holds none.
  A Mac build's script also gets an identity token with read access to the
  account's cache (`Tuist.Sandboxes.CommandCredentials`), valid only while
  the build's command runs, so its `tuist generate` writes the project a
  signed-in session's does and the session's build reuses the snapshot's;
  the build deletes the session the CLI stored from it before the disks are
  saved.

  A Linux environment's `macos_setup_script` prepares the Macs its sessions
  create with the `create_sandbox` MCP tool (`Tuist.Sandboxes.Query`) for a
  repository connected to one of the account's projects (`mac_source/3`):
  such a Mac boots from the repository's macOS snapshot of its Xcode
  template, else from the template, and asks for a build of it
  (`request_mac_build/1`), so each Xcode has its own snapshot. A Mac build
  clones to `$HOME/work/<name>`, where `tuist sandbox sync` puts the
  session's worktree, so Xcode's DerivedData, keyed by the workspace's path,
  is reused there. After the script it resets the tracked files the script
  changed and records the clone the way `tuist sandbox sync` records what
  it sent (`$HOME/.tuist-sync/`, with the commit), so the session's first
  sync sends only the files that differ from that commit and leaves the
  others, and their modification times, which Xcode compares, alone.
  """
  alias Tuist.Accounts.Account
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Archives
  alias Tuist.Sandboxes.Commands
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.DiskSnapshots
  alias Tuist.Sandboxes.Router
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxCommand

  require Logger

  @user "user"
  @build_timeout_ms to_timeout(hour: 1)
  # `Tuist.Sandboxes.Workers.CommandWatchWorker` records the command's end
  # within 15 seconds.
  @poll_seconds 30
  @retry_seconds 60
  # Refusals that pass: no room yet, or another admission of the account
  # holding its row (two builds starting together).
  @retryable_errors [:no_capacity, :no_node, :sandbox_concurrency_limit, :sandbox_account_busy]

  # Clones beside the final path as the runner's user, so a clone cut short
  # never looks like the runner's repository, then drops the token and runs
  # the script.
  @build_script """
  set -eu
  path=$1 url=$2 script=$3
  parent=$(dirname "$path")
  install -d -o #{@user} -g #{@user} "$(dirname "$parent")" "$parent"
  rm -rf "$path" "$path.sbx-clone"
  runuser -u #{@user} -- git clone --quiet "$url" "$path.sbx-clone"
  mv "$path.sbx-clone" "$path"
  unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
  cd "$path"
  exec runuser -u #{@user} -- /bin/bash -c 'exec > >(tee "$HOME/.claude-code-setup.log") 2>&1; exec /bin/bash -l -c "$1" setup' sh "$script"
  """

  # A macOS guest runs every command as the runner's user already.
  @macos_build_script """
  set -eu
  path=$1 url=$2 script=$3
  mkdir -p "$(dirname "$path")"
  rm -rf "$path" "$path.sbx-clone"
  git clone --quiet "$url" "$path.sbx-clone"
  mv "$path.sbx-clone" "$path"
  unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
  cd "$path"
  exec /bin/bash -c 'exec > >(tee "$HOME/.claude-code-setup.log") 2>&1; exec /bin/bash -l -c "$1" setup' sh "$script"
  """

  # A Mac build ends by recording the clone as `tuist sandbox sync` would
  # (`SandboxSync` in the CLI): the manifest of the commit's files, named by
  # its Git hash, and their paths, under the clone's resolved path. The
  # tracked files the script changed go back to the commit first, so the
  # record describes the copy. Before that it stops the cache proxy and the
  # build service that write the compilation cache, waits for them to exit,
  # and deletes the cache. A kept store, quiesced or not, failed the
  # sessions' compiles with "not a IncludeFileList node kind", and the plugin
  # logged action-cache entries whose values the store lacked (measured
  # 2026-11). The build products in DerivedData stay, and the remote cache
  # serves what reruns. It also drops
  # the session the CLI stored from the build's identity token, and the
  # script's simulators, and stops the simulator services: a Mac booted
  # from the disks mounts the simulator runtimes at new paths, and the
  # devices and services the disks recorded left its runtimes unavailable
  # (measured, 2026-11). The script runs without the clone's
  # `GIT_TERMINAL_PROMPT`, which a session's commands lack: Tuist keys its
  # package-manifest cache on the environment, and the variable left the
  # session's first `tuist install` recompiling the manifests.
  @macos_sync_build_script """
  set -eu
  path=$1 url=$2 script=$3
  mkdir -p "$(dirname "$path")"
  rm -rf "$path" "$path.sbx-clone"
  git clone --quiet "$url" "$path.sbx-clone"
  mv "$path.sbx-clone" "$path"
  unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_TERMINAL_PROMPT
  cd "$path"
  /bin/bash -c 'exec > >(tee "$HOME/.claude-code-setup.log") 2>&1; exec /bin/bash -l -c "$1" setup' sh "$script"
  cache="$HOME/Library/Developer/Xcode/DerivedData/CompilationCache.noindex"
  launchctl bootout "gui/$(id -u)/tuist.cas-proxy" >/dev/null 2>&1 || true
  killall -TERM SWBBuildService XCBBuildService >/dev/null 2>&1 || true
  i=0
  while pgrep -x SWBBuildService >/dev/null || pgrep -x XCBBuildService >/dev/null; do
    i=$((i + 1)); [ "$i" -gt 30 ] && break; sleep 1
  done
  rm -rf "$cache"
  rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/tuist/credentials"
  xcrun simctl shutdown all >/dev/null 2>&1 || true
  xcrun simctl delete all >/dev/null 2>&1 || true
  killall -TERM Simulator com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 || true
  sudo -n killall -TERM simdiskimaged >/dev/null 2>&1 || true
  git update-index -q --refresh || true
  git reset --quiet --hard HEAD
  root=$(pwd -P)
  state="$HOME/.tuist-sync/$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
  rm -rf "$state"
  mkdir -p "$state"
  git ls-files -s -z | perl -e '
    local $/ = "\\0";
    open my $m, ">", $ARGV[0] or die; open my $p, ">", $ARGV[1] or die;
    while (<STDIN>) {
      chomp; my ($meta, $file) = split /\\t/, $_, 2; my ($mode, $object) = split / /, $meta;
      next if $mode eq "160000"; print $m "$mode $object\\t$file\\0"; print $p "$file\\0";
    }
  ' "$state/manifest" "$state/paths"
  printf '%s' "$(git hash-object --no-filters "$state/manifest")" > "$state/id"
  rm "$state/manifest"
  git rev-parse HEAD > "$state/commit"
  sync
  """

  @doc """
  The snapshot a new sandbox of the session's `repository` boots from, or
  nil: for environments with a setup script, the newest one of the
  repository saved with the current script.
  """
  def find(%AgentEnvironment{setup_script: script} = agent_environment, %{owner: owner, name: name})
      when is_binary(script) and script != "" do
    DiskSnapshots.find_ready_for_repository(agent_environment, "#{owner}/#{name}", setup_sha256(script))
  end

  def find(_agent_environment, _repository), do: nil

  @doc """
  Starts building the repository's snapshot with the environment's current
  script, unless a build of it runs or recently failed. Always `:ok`.
  """
  def request_build(%AgentEnvironment{setup_script: script} = agent_environment, %{owner: owner, name: name})
      when is_binary(script) and script != "" do
    repository = "#{owner}/#{name}"

    case DiskSnapshots.start_build(agent_environment, repository, setup_sha256(script)) do
      {:ok, build} ->
        Logger.info("sandboxes: claude code repository snapshot build started",
          disk_snapshot_id: build.id,
          agent_environment_id: agent_environment.id,
          repository: repository
        )

      {:error, :already_building} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: claude code repository snapshot build not started",
          agent_environment_id: agent_environment.id,
          repository: repository,
          reason: inspect(reason)
        )
    end

    :ok
  end

  def request_build(_agent_environment, _repository), do: :ok

  @repository ~r"\A[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}\z"

  @doc """
  What a new macOS sandbox created through the sandbox API for `repository`
  (`owner/name`) boots from: `{:ok, nil}` when it has no repository, is not
  a macOS sandbox, or no Linux Claude Code environment of the account has a
  macOS setup script, or the repository is not connected to one of the
  account's projects; otherwise `{:ok, source}` with the environment, the
  repository's canonical name, the template and the ready snapshot, if any.
  A malformed repository is `{:error, :invalid_parameters}`.
  """
  def mac_source(%Account{} = account, repository, attrs) when is_binary(repository) do
    attrs = Sandboxes.platform_defaults(attrs)

    cond do
      not Regex.match?(@repository, repository) ->
        {:error, :invalid_parameters}

      Map.get(attrs, :platform) not in [:darwin, "darwin"] ->
        {:ok, nil}

      true ->
        with [_ | _] = environments <- mac_environments(account),
             repository when is_binary(repository) <- connected_repository(account, repository) do
          environment_snapshots =
            Enum.map(environments, fn environment ->
              {environment,
               DiskSnapshots.find_ready_for_repository(
                 environment,
                 repository,
                 mac_setup_sha256(environment.macos_setup_script),
                 template: attrs.template,
                 workspace_gb: attrs.workspace_gb
               )}
            end)

          {environment, snapshot} =
            Enum.find(environment_snapshots, hd(environment_snapshots), fn {_environment, snapshot} -> snapshot end)

          {:ok,
           %{
             agent_environment: environment,
             repository: repository,
             template: attrs.template,
             workspace_gb: attrs.workspace_gb,
             snapshot: snapshot
           }}
        else
          _none -> {:ok, nil}
        end
    end
  end

  def mac_source(_account, nil, _attrs), do: {:ok, nil}
  def mac_source(_account, _repository, _attrs), do: {:error, :invalid_parameters}

  @doc """
  Starts building the macOS snapshot of a `mac_source/3` that had none, or
  whose snapshot is older than six hours, unless a build of it runs or
  recently failed. Always `:ok`.

  A snapshot fixes which targets `tuist generate` took from the binary cache
  when it was built. The cache fills in after a push and moves with the
  default branch, so a later generate replaces other targets with binaries,
  which changes the build settings of every target that depends on them, and
  the session's first build compiled those again: 302 files of the Tuist app
  a few hours after its snapshot (measured, 2026-11). The Macs keep booting
  from the old snapshot until the new one is saved and replaces it.
  """
  def request_mac_build(%{snapshot: snapshot, agent_environment: %AgentEnvironment{}} = source) do
    if is_nil(snapshot) or stale?(snapshot), do: start_mac_build(source)
    :ok
  end

  def request_mac_build(_source), do: :ok

  @mac_snapshot_max_age_seconds 6 * 3600

  defp stale?(%DiskSnapshot{inserted_at: inserted_at}),
    do: DateTime.diff(DateTime.utc_now(), inserted_at) > @mac_snapshot_max_age_seconds

  defp start_mac_build(%{agent_environment: environment, repository: repository} = source) do
    case DiskSnapshots.start_build(environment, repository, mac_setup_sha256(environment.macos_setup_script),
           platform: :darwin,
           template: source.template,
           workspace_gb: source.workspace_gb
         ) do
      {:ok, build} ->
        Logger.info("sandboxes: claude code macOS repository snapshot build started",
          disk_snapshot_id: build.id,
          agent_environment_id: environment.id,
          repository: repository,
          template: source.template
        )

      {:error, :already_building} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: claude code macOS repository snapshot build not started",
          agent_environment_id: environment.id,
          repository: repository,
          reason: inspect(reason)
        )
    end
  end

  # The account's enabled Linux Claude Code environments with a macOS setup
  # script, oldest first.
  defp mac_environments(%Account{} = account) do
    :claude_code
    |> Sandboxes.list_enabled_agent_environments()
    |> Enum.filter(fn environment ->
      environment.account_id == account.id and environment.platform == :linux and
        environment.macos_setup_script not in [nil, ""]
    end)
    |> Enum.map(&%{&1 | account: account})
  end

  # Any account member can name the repository, and the build clones it with
  # the account's GitHub installation: only a github.com repository one of
  # the account's projects is connected to is built, under its connected name.
  defp connected_repository(account, repository) do
    repository
    |> Projects.projects_by_vcs_repository_full_handle(preload: [:vcs_connection], client_url: "https://github.com")
    |> Enum.find_value(fn project ->
      if project.account_id == account.id, do: project.vcs_connection.repository_full_handle
    end)
  end

  # A Mac build of a Linux environment runs its macOS setup script for the
  # Macs its sessions create; every other build runs its own platform's.
  defp mac_build?(%DiskSnapshot{platform: :darwin}, %AgentEnvironment{platform: :linux}), do: true
  defp mac_build?(_build, _agent_environment), do: false

  defp script(build, agent_environment) do
    if mac_build?(build, agent_environment),
      do: agent_environment.macos_setup_script,
      else: agent_environment.setup_script
  end

  def setup_sha256(script), do: :sha256 |> :crypto.hash(script) |> Base.encode16(case: :lower)

  # A Mac build's snapshot also depends on what the build does around the
  # script, so a change to that builds the snapshots again.
  defp mac_setup_sha256(script), do: setup_sha256(@macos_sync_build_script <> script)

  defp build_sha256(build, agent_environment, script) do
    if mac_build?(build, agent_environment), do: mac_setup_sha256(script), else: setup_sha256(script)
  end

  @doc """
  Takes a build its next step: creates the builder and starts the command,
  waits for the command, or saves or fails the build once it ended. Answers
  `{:snooze, seconds}` while the build goes on and `:ok` once it ended.
  """
  def advance(%DiskSnapshot{state: :building} = build) do
    build = Repo.preload(build, agent_environment: :account)

    with %AgentEnvironment{} = agent_environment <- build.agent_environment,
         script when is_binary(script) <- script(build, agent_environment),
         true <- build_sha256(build, agent_environment, script) == build.setup_sha256 do
      advance(build, agent_environment, Sandboxes.get_sandbox_by_id(build.id))
    else
      _changed -> abandon(build)
    end
  end

  def advance(%DiskSnapshot{}), do: :ok

  defp advance(build, agent_environment, nil), do: create_builder(build, agent_environment)

  # A create that placement refused leaves its row without a node.
  defp advance(build, agent_environment, %Sandbox{state: :error, node_name: nil} = sandbox) do
    with {:ok, _deleted} <- Sandboxes.delete(sandbox), do: create_builder(build, agent_environment)
  end

  defp advance(_build, _agent_environment, %Sandbox{state: state}) when state in [:creating, :resuming],
    do: {:snooze, @poll_seconds}

  defp advance(build, agent_environment, %Sandbox{state: state} = sandbox) when state in [:running, :paused] do
    case Repo.get(SandboxCommand, build.id) do
      nil -> start_command(build, agent_environment, sandbox)
      %SandboxCommand{status: :running} -> {:snooze, @poll_seconds}
      %SandboxCommand{status: :exited, exit_code: 0} -> save(build, sandbox)
      %SandboxCommand{} = command -> fail(build, sandbox, {command.status, command.exit_code})
    end
  end

  defp advance(build, _agent_environment, sandbox), do: fail(build, sandbox, {:builder, sandbox.state})

  defp create_builder(build, agent_environment) do
    # A Mac build takes the default macOS shape: the snapshot holds only disks.
    attrs =
      if mac_build?(build, agent_environment),
        do: %{
          agent_environment_id: agent_environment.id,
          platform: :darwin,
          template: build.template,
          workspace_gb: build.workspace_gb
        },
        else: %{
          agent_environment_id: agent_environment.id,
          platform: agent_environment.platform,
          template: agent_environment.template,
          vcpus: agent_environment.vcpus,
          memory_mb: agent_environment.memory_mb,
          workspace_gb: agent_environment.workspace_gb
        }

    case Sandboxes.create_sandbox(agent_environment.account, attrs, id: build.id) do
      {:ok, sandbox} -> start_command(build, agent_environment, sandbox)
      {:error, reason} when reason in @retryable_errors -> {:snooze, @retry_seconds}
      {:error, reason} -> fail(build, Sandboxes.get_sandbox_by_id(build.id), reason)
    end
  end

  defp start_command(build, agent_environment, sandbox) do
    url = "https://github.com/" <> build.repository
    {git_env, _secret} = Router.credentials(agent_environment.account, url, :account)
    path = clone_path(build, agent_environment, sandbox)

    env =
      agent_environment.account
      |> Sandboxes.tuist_env(sandbox)
      |> Map.merge(git_env)
      |> Map.put("GIT_TERMINAL_PROMPT", "0")

    # A Mac build's script signs in to Tuist as a session's does
    # (`CommandCredentials`, read access to the account's cache).
    started_by = if mac_build?(build, agent_environment), do: :snapshot_build

    case Commands.start(sandbox, %{
           id: build.id,
           started_by: started_by,
           command: "/bin/sh",
           args: [
             "-c",
             build_script(build, agent_environment, sandbox),
             "sh",
             path,
             url,
             script(build, agent_environment)
           ],
           env: env,
           cwd: "/",
           timeout_ms: @build_timeout_ms
         }) do
      {:ok, _command} ->
        {:snooze, @poll_seconds}

      {:error, reason} when reason in @retryable_errors ->
        {:snooze, @retry_seconds}

      # A Mac's idle pause can beat the first command, and CI can take the
      # slot it freed before the command resumes it. The builder has done
      # nothing yet: drop it, and the next step places a new one on a host
      # with an idle slot.
      {:error, {:host_busy, _why}} ->
        _ = Sandboxes.delete(sandbox)
        {:snooze, @retry_seconds}

      {:error, reason} ->
        fail(build, sandbox, reason)
    end
  end

  defp build_script(build, agent_environment, sandbox) do
    cond do
      mac_build?(build, agent_environment) -> @macos_sync_build_script
      sandbox.platform == :darwin -> @macos_build_script
      true -> @build_script
    end
  end

  # Where the runner keeps its clone, or for a Mac a session creates, where
  # `tuist sandbox sync` puts the session's worktree by default:
  # `$HOME/work/<name>`, the workspace's root.
  defp clone_path(build, agent_environment, sandbox) do
    if mac_build?(build, agent_environment),
      do: Path.join(Sandboxes.workspace(sandbox), build.repository |> String.split("/") |> List.last()),
      else: Path.join([Sandboxes.workspace(sandbox), "claude-code" | String.split(build.repository, "/")])
  end

  defp save(build, sandbox) do
    with {:ok, paused} <- paused(sandbox),
         {:ok, snapshot} <- DiskSnapshots.save_build(build, paused) do
      Logger.info("sandboxes: claude code repository snapshot saved",
        disk_snapshot_id: snapshot.id,
        agent_environment_id: build.agent_environment_id,
        repository: build.repository,
        node: snapshot.node_name
      )

      _ = Sandboxes.delete(paused)
      :ok
    else
      # The builder's node has no disk for the snapshot yet. The paused
      # builder keeps the finished work while the archive tier frees room
      # there, as it does for a new sandbox; `DiskSnapshots.delete_expired/0`
      # bounds the wait.
      {:error, :no_capacity} ->
        Archives.make_node_room([sandbox.node_name])
        {:snooze, @retry_seconds}

      {:error, reason} ->
        fail(build, sandbox, {:save, reason})
    end
  end

  # Every pause syncs the guest's disks. The builder pauses by itself once
  # its command ended and it is idle.
  defp paused(%Sandbox{state: :paused} = sandbox), do: {:ok, sandbox}

  defp paused(sandbox) do
    case Sandboxes.pause(sandbox) do
      {:error, {:invalid_state, :paused}} -> {:ok, Sandboxes.get_sandbox_by_id(sandbox.id)}
      result -> result
    end
  end

  # The output tail is logged so a failing script can be fixed; the setup
  # environment holds no credential, and git never prints the token.
  defp fail(build, sandbox, reason) do
    Logger.warning("sandboxes: claude code repository snapshot build failed",
      disk_snapshot_id: build.id,
      agent_environment_id: build.agent_environment_id,
      repository: build.repository,
      reason: inspect(reason),
      stderr: output_tail(sandbox, build.id, reason)
    )

    _ = if sandbox, do: Sandboxes.delete(sandbox)
    DiskSnapshots.fail_build(build)
  end

  defp output_tail(%Sandbox{} = sandbox, id, {status, _exit_code}) when status in [:exited, :timed_out] do
    case Sandboxes.exec(
           sandbox,
           [
             "/bin/sh",
             "-c",
             ~S|d="$HOME/.cache/tuist/commands/$1"; tail -c 2000 "$d/stderr"; tail -c 2000 "$d/stdout"|,
             "sh",
             id
           ],
           timeout_ms: 10_000
         ) do
      {:ok, %{stdout: output}} -> output
      {:error, _reason} -> nil
    end
  end

  defp output_tail(_sandbox, _id, _reason), do: nil

  defp abandon(build) do
    _ = with %Sandbox{} = sandbox <- Sandboxes.get_sandbox_by_id(build.id), do: Sandboxes.delete(sandbox)
    _ = DiskSnapshots.delete(build)
    :ok
  end
end
