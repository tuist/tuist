defmodule Tuist.Sandboxes.ClaudeCodeSnapshots do
  @moduledoc """
  Repo-ready disk snapshots for Claude Code sessions on Linux.

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
  deletes the builder; any other end fails the build, which keeps the
  script from building the repository again for an hour.

  Only the clone gets a credential: the token `Router.credentials/3` mints
  for that repository, in the command's environment, unset before the
  script runs. The script gets the Tuist environment
  (`Sandboxes.tuist_env/2`), which holds none, so the snapshot holds none.
  """
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
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
  @capacity_retry_seconds 60
  @capacity_errors [:no_capacity, :no_node, :sandbox_concurrency_limit]

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

  @doc """
  The snapshot a new sandbox of the session's `repository` boots from, or
  nil: for Linux environments with a setup script, the newest one of the
  repository saved with the current script.
  """
  def find(%AgentEnvironment{platform: :linux, setup_script: script} = agent_environment, %{owner: owner, name: name})
      when is_binary(script) and script != "" do
    DiskSnapshots.find_ready_for_repository(agent_environment, "#{owner}/#{name}", setup_sha256(script))
  end

  def find(_agent_environment, _repository), do: nil

  @doc """
  Starts building the repository's snapshot with the environment's current
  script, unless a build of it runs or recently failed. Always `:ok`.
  """
  def request_build(%AgentEnvironment{platform: :linux, setup_script: script} = agent_environment, %{
        owner: owner,
        name: name
      })
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

  def setup_sha256(script), do: :sha256 |> :crypto.hash(script) |> Base.encode16(case: :lower)

  @doc """
  Takes a build its next step: creates the builder and starts the command,
  waits for the command, or saves or fails the build once it ended. Answers
  `{:snooze, seconds}` while the build goes on and `:ok` once it ended.
  """
  def advance(%DiskSnapshot{state: :building} = build) do
    build = Repo.preload(build, agent_environment: :account)

    case build.agent_environment do
      %AgentEnvironment{platform: :linux, setup_script: script} = agent_environment when is_binary(script) ->
        if setup_sha256(script) == build.setup_sha256,
          do: advance(build, agent_environment, Sandboxes.get_sandbox_by_id(build.id)),
          else: abandon(build)

      _changed ->
        abandon(build)
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
    attrs = %{
      agent_environment_id: agent_environment.id,
      platform: :linux,
      template: agent_environment.template,
      vcpus: agent_environment.vcpus,
      memory_mb: agent_environment.memory_mb,
      workspace_gb: agent_environment.workspace_gb
    }

    case Sandboxes.create_sandbox(agent_environment.account, attrs, id: build.id) do
      {:ok, sandbox} -> start_command(build, agent_environment, sandbox)
      {:error, reason} when reason in @capacity_errors -> {:snooze, @capacity_retry_seconds}
      {:error, reason} -> fail(build, Sandboxes.get_sandbox_by_id(build.id), reason)
    end
  end

  defp start_command(build, agent_environment, sandbox) do
    url = "https://github.com/" <> build.repository
    {git_env, _secret} = Router.credentials(agent_environment.account, url, :account)
    path = Path.join([Sandboxes.workspace(sandbox), "claude-code" | String.split(build.repository, "/")])

    env =
      agent_environment.account
      |> Sandboxes.tuist_env(sandbox)
      |> Map.merge(git_env)
      |> Map.put("GIT_TERMINAL_PROMPT", "0")

    case Commands.start(sandbox, %{
           id: build.id,
           command: "/bin/sh",
           args: ["-c", @build_script, "sh", path, url, agent_environment.setup_script],
           env: env,
           cwd: "/",
           timeout_ms: @build_timeout_ms
         }) do
      {:ok, _command} -> {:snooze, @poll_seconds}
      {:error, reason} when reason in @capacity_errors -> {:snooze, @capacity_retry_seconds}
      {:error, reason} -> fail(build, sandbox, reason)
    end
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
      {:error, reason} -> fail(build, sandbox, {:save, reason})
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
