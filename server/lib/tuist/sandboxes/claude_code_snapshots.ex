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
  A Mac build's script also gets an identity token with the CI preset on the
  account's cache (`Tuist.Sandboxes.CommandCredentials`), valid only while
  the build's command runs, so its `tuist generate` writes the project a
  signed-in session's does, the session's build reuses the snapshot's, and
  the compilation cache publishes what the build compiled;
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
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.GitHub.Client, as: GitHubClient
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
  alias Tuist.VCS

  require Logger

  @user "user"
  @build_timeout_ms to_timeout(hour: 1)
  # `Tuist.Sandboxes.Workers.CommandWatchWorker` records the command's end
  # within 15 seconds.
  @poll_seconds 30
  @retry_seconds 60
  # Refusals that pass: no room yet, another admission of the account
  # holding its row (two builds starting together), or a host that dropped
  # its connection or answered late. None of them ran the script, so none
  # holds the key for an hour: a busy Mac fleet refuses and disconnects
  # often, and failing on them left the snapshot unbuilt (measured, 2026-11).
  @retryable_errors [
    :no_capacity,
    :no_node,
    :sandbox_concurrency_limit,
    :sandbox_account_busy,
    :node_disconnected,
    :not_connected,
    :timeout
  ]

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
  # record describes the copy. Before that it waits for the compilation
  # cache's publications to reach the remote cache (`tuist-cas-proxy
  # --drain`, as CI runners' `drain_cas_publications` does) and fails the
  # build when any record remains: the store's associations name objects
  # only the remote can restore, and a snapshot saved over a builder that
  # could not publish (read-only, 2026-11) failed every session build with
  # "CAS error: missing object". Then it stops what writes the compilation
  # cache, as CI's teardown does (`stop_tuist_launch_agents`): it boots out
  # every `tuist.*` launch agent and waits for each process to exit, since
  # `launchctl bootout` returns first, stops the build service, and ends any
  # process `lsof` still finds in the store. It flushes each file in
  # DerivedData, the compilation cache and the build products, with
  # `F_FULLFSYNC` (51), for a host that evicts the builder instead of
  # shutting it down; the save shuts the guest down cleanly
  # (`DiskSnapshots.save_build/2`). Disks a running guest only synced were
  # not enough: Macs booted from them read `data.v1` with a zeroed header
  # ("specified header offset (16) does not match existing config (0)"),
  # with missing objects ("not a IncludeFileList node kind"), or, after the
  # flush, with an index whose trie crashed `tuist-cas-proxy` on its first
  # writes (`OnDiskTrieRawHashMap::insertLazy`, measured 2026-11). It also drops
  # the session the CLI stored from the build's identity token, and the
  # simulators the script created, and stops the simulator services: a Mac
  # booted from the disks mounts the simulator runtimes at new paths, and the
  # devices and services the disks recorded left its runtimes unavailable
  # (measured, 2026-11). The image's own devices stay, shut down: a Mac
  # restored with them kept its runtimes and devices, and the session's
  # Mac pre-boots one (`Devices.boot_in_background/1`; measured, 2026-11).
  # The script runs without the clone's
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
  devices() { xcrun simctl list devices 2>/dev/null | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | sort -u || true; }
  image_devices=$(devices)
  /bin/bash -c 'exec > >(tee "$HOME/.claude-code-setup.log") 2>&1; exec /bin/bash -l -c "$1" setup' sh "$script"
  derived_data="$HOME/Library/Developer/Xcode/DerivedData"
  cas_client=$(command -v tuist-cas-proxy 2>/dev/null || echo /opt/tuist/tuist-cas-proxy)
  for spool in $(find "$derived_data/CompilationCache.noindex" -type d -name tuist-spool 2>/dev/null); do
    env -u TUIST_CAS_REMOTE_GRPC_URL "$cas_client" --drain "$(dirname "$spool")" --socket "$HOME/.local/state/tuist/cas-proxy.sock" --timeout-ms 300000 || true
    owed=$(find "$spool" -type f ! -name '*.tags' | wc -l | tr -d ' ')
    if [ "$owed" -gt 0 ]; then
      echo "$owed compilation cache publications in $spool did not reach the remote cache" >&2
      exit 1
    fi
  done
  agents=$(launchctl list 2>/dev/null | awk 'NR > 1 && $3 ~ /^tuist\\./ { print $1, $3 }')
  echo "$agents" | while read -r pid label; do
    [ -n "$label" ] || continue
    launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    i=0
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 50 ]; do i=$((i + 1)); sleep 0.2; done
  done
  killall -TERM SWBBuildService XCBBuildService >/dev/null 2>&1 || true
  i=0
  while pgrep -x SWBBuildService >/dev/null || pgrep -x XCBBuildService >/dev/null; do
    i=$((i + 1)); [ "$i" -gt 30 ] && break; sleep 1
  done
  store="$derived_data/CompilationCache.noindex"
  for signal in TERM KILL; do
    holders=$(lsof -n -w -t +D "$store" 2>/dev/null | sort -u | tr '\\n' ' ')
    [ -n "$holders" ] || break
    echo "ending $holders, which still hold $store (SIG$signal)" >&2
    kill "-$signal" $holders 2>/dev/null || true
    sleep 2
  done
  if [ -d "$derived_data" ]; then
    find "$derived_data" -type f -exec perl -e 'for (@ARGV) { open my $f, "<", $_ or die "$_: $!"; fcntl($f, 51, 0) or die "$_: $!" }' {} +
  fi
  rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/tuist/credentials"
  xcrun simctl shutdown all >/dev/null 2>&1 || true
  for device in $(devices); do
    printf '%s\\n' "$image_devices" | grep -qxF "$device" || xcrun simctl delete "$device" >/dev/null 2>&1 || true
  done
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
  # A snapshot is rebuilt for a push only once it is this old, so a default
  # branch that moves every few minutes keeps one builder busy at most a
  # fraction of the time; a build holds an idle Mac slot for about 7 minutes.
  @mac_refresh_min_age_seconds 30 * 60
  # A snapshot is kept fresh while Macs were created from its repository on
  # its template this recently.
  @mac_refresh_used_hours 24

  @doc """
  Rebuilds each macOS repository snapshot in use whose repository's default
  branch moved past the commit it was built from
  (`Tuist.Sandboxes.Workers.RefreshMacSnapshotsWorker`, every ten minutes),
  so a session's Mac boots from a snapshot of the head instead of waiting
  for `request_mac_build/1`'s six hours. A snapshot is in use while Macs
  were created for its repository on its template in the last day, and is
  rebuilt at most every half hour. The Macs keep booting from it until the
  new one is saved.
  """
  def refresh_mac_snapshots do
    now = DateTime.utc_now()
    built_before = DateTime.add(now, -@mac_refresh_min_age_seconds, :second)

    from(s in DiskSnapshot,
      join: e in assoc(s, :agent_environment),
      where: s.state == :ready and s.platform == :darwin and s.inserted_at < ^built_before,
      where: e.enabled and e.kind == :claude_code and e.platform == :linux,
      preload: [agent_environment: e]
    )
    |> Repo.all()
    |> Enum.filter(&(mac_current?(&1) and mac_in_use?(&1, now)))
    |> Enum.group_by(&{&1.account_id, &1.repository})
    |> Enum.each(fn {{account_id, repository}, snapshots} ->
      case default_branch_head(account_id, repository) do
        {:ok, head} ->
          for %DiskSnapshot{commit_sha: commit} = snapshot <- snapshots, commit != head do
            start_mac_build(%{
              agent_environment: snapshot.agent_environment,
              repository: repository,
              template: snapshot.template,
              workspace_gb: snapshot.workspace_gb
            })
          end

        {:error, _reason} ->
          :ok
      end
    end)

    :ok
  end

  # Built with the environment's current macOS setup script; an older one is
  # rebuilt by the next Mac that asks for the repository.
  defp mac_current?(%DiskSnapshot{agent_environment: %AgentEnvironment{macos_setup_script: script}} = snapshot),
    do: script not in [nil, ""] and mac_setup_sha256(script) == snapshot.setup_sha256

  defp mac_in_use?(%DiskSnapshot{} = snapshot, now) do
    since = DateTime.add(now, -@mac_refresh_used_hours, :hour)

    Repo.exists?(
      from(s in Sandbox,
        where: s.account_id == ^snapshot.account_id and s.repository == ^snapshot.repository,
        where: s.template == ^snapshot.template and s.inserted_at >= ^since and s.state != :error
      )
    )
  end

  defp record_commit(%DiskSnapshot{id: id} = build) do
    case default_branch_head(build.account_id, build.repository) do
      {:ok, head} -> Repo.update_all(from(s in DiskSnapshot, where: s.id == ^id), set: [commit_sha: head])
      {:error, _reason} -> :ok
    end
  end

  # The default branch's head as GitHub reports it through the account's
  # installation, which the build clones.
  defp default_branch_head(account_id, repository) do
    with {:ok, installation} <- VCS.get_github_app_installation_for_account(account_id),
         {:ok, %{"default_branch" => default}} when is_binary(default) <-
           GitHubClient.get_repository(installation, repository),
         {:ok, %{"commit" => %{"sha" => head}}} when is_binary(head) <-
           GitHubClient.get_branch(installation, repository, default) do
      {:ok, head}
    else
      _ -> {:error, :unavailable}
    end
  end

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

  # A create that placement refused, or whose host disconnected while it
  # booted, leaves an errored row that never ran the script: replace it.
  defp advance(build, agent_environment, %Sandbox{state: :error} = sandbox) do
    if Repo.get(SandboxCommand, build.id) do
      fail(build, sandbox, {:builder, :error})
    else
      case Sandboxes.delete(sandbox) do
        {:ok, _deleted} -> create_builder(build, agent_environment)
        {:error, _reason} -> {:snooze, @retry_seconds}
      end
    end
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
      {:error, {:host_busy, _why}} -> {:snooze, @retry_seconds}
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
    # (`CommandCredentials`, the CI preset on the account's cache), and the
    # build records the default branch's head it clones, which
    # `refresh_mac_snapshots/0` compares against.
    started_by = if mac_build?(build, agent_environment), do: :snapshot_build
    if started_by, do: record_commit(build)

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
