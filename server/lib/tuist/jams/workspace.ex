defmodule Tuist.Jams.Workspace do
  @moduledoc "Persistent jam checkouts, with one attempt-scoped sandbox residency per run."

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Jams
  alias Tuist.Jams.Repository
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.ProviderEnvironment
  alias Tuist.Sandboxes.Sandbox

  @root "/workspace/repository"
  @limit 65_536

  # This is the descriptor-relative O_NOFOLLOW approach used by
  # ProviderEnvironments. Its helper is private and read-only; writes and edits
  # additionally open the final component without truncating before validation.
  @files ~S"""
  import os, sys, stat
  op, path = sys.argv[1:3]
  parts = path.split('/')
  if path.startswith('/') or any(p in ('', '.', '..', '.git') for p in parts):
      sys.exit(2)
  fd = os.open('/workspace', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
  for part in ['repository'] + parts[:-1]:
      nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
      os.close(fd)
      fd = nxt
  flags = os.O_NOFOLLOW | os.O_NONBLOCK
  flags |= os.O_RDONLY if op == 'read' else os.O_RDWR
  if op == 'write': flags |= os.O_CREAT
  file = os.open(parts[-1], flags, 0o644, dir_fd=fd)
  if not stat.S_ISREG(os.fstat(file).st_mode) or os.fstat(file).st_nlink != 1: sys.exit(2)
  if op == 'read':
      print(os.read(file, 65536).decode('utf-8', errors='replace'))
  else:
      content = sys.argv[3]
      if op == 'edit':
          old = os.read(file, 1048577)
          if len(old) > 1048576: sys.exit(2)
          old = old.decode('utf-8')
          if old.count(content) != 1: sys.exit(2)
          content = old.replace(content, sys.argv[4], 1)
      os.lseek(file, 0, os.SEEK_SET)
      data = content.encode('utf-8')
      while data:
          data = data[os.write(file, data):]
      os.ftruncate(file, os.lseek(file, 0, os.SEEK_CUR))
      print('File updated.')
  os.close(file)
  os.close(fd)
  """

  @initialize ~S"""
  import os, sys
  fd = os.open('/workspace', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
  try: os.mkdir('repository', dir_fd=fd)
  except FileExistsError: pass
  root = os.open('repository', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
  try:
      metadata = os.open('.git', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=root)
      os.close(metadata)
      print('initialized')
  except FileNotFoundError:
      if os.listdir(root): sys.exit(2)
      print('empty')
  """

  def prepare(jam, run) do
    exclusive(jam.id, fn ->
      with true <- run.jam_id == jam.id and Jams.owns_run?(run.id, run.attempt),
           jam = Repo.reload!(jam),
           true <- jam.status == :active,
           {:ok, account} <- Accounts.get_account_by_id(jam.account_id),
           {:ok, repository} <- Repository.authorize(account, jam.repository),
           {:ok, sandbox} <- sandbox(jam, account),
           {:ok, jam} <- Jams.bind_sandbox(jam.id, run.id, run.attempt, sandbox.id),
           work_id = "jams:#{run.id}:#{run.attempt}",
           {:ok, sandbox} <- Sandboxes.prepare_residency(sandbox, work_id) do
        context = %{jam: jam, sandbox: sandbox, residency: work_id, run_id: run.id, attempt: run.attempt}

        case checkout(context, account, repository) do
          {:ok, jam} ->
            {:ok, %{context | jam: jam}}

          {:error, _} = error ->
            release(context)
            error
        end
      else
        false -> {:error, :stale_run}
        _ -> {:error, :workspace_unavailable}
      end
    end)
  end

  # A short row lock fences the non-fenced Sandboxes.end_residency/1 API.
  # An old attempt can never clear a replacement attempt's residency.
  def release(%{sandbox: sandbox, residency: work_id}) do
    {:ok, _} =
      Repo.transaction(fn ->
        case Repo.one(from s in Sandbox, where: s.id == ^sandbox.id, lock: "FOR UPDATE") do
          %Sandbox{residency_work_id: ^work_id} = fresh -> Sandboxes.end_residency(fresh)
          _ -> :ok
        end
      end)

    :ok
  end

  def call(context, name, args) do
    exclusive(context.jam.id, fn ->
      with true <- Jams.owns_run?(context.run_id, context.attempt),
           {:ok, argv, timeout} <- command(name, args),
           {:ok, sandbox} <- resident(context),
           {:ok, result} <- Sandboxes.exec(sandbox, argv, cwd: @root, env: %{}, timeout_ms: timeout) do
        {:ok, bounded("exit_code=#{result.exit_code}\n" <> result.stdout <> result.stderr)}
      else
        false -> {:error, :stale_run}
        {:error, :invalid_arguments} = error -> error
        _ -> {:error, :workspace_command_failed}
      end
    end)
  end

  @doc false
  def exclusive(jam_id, fun) do
    # A session lock, not a transaction or row lock, spans external boot/git
    # calls. Other replicas fail fast; database disconnect releases the lock.
    Repo.checkout(
      fn ->
        lock = "jams-workspace:#{jam_id}"

        case Repo.query!("SELECT pg_try_advisory_lock(hashtextextended($1, 0))", [lock]).rows do
          [[true]] ->
            try do
              fun.()
            after
              Repo.query!("SELECT pg_advisory_unlock(hashtextextended($1, 0))", [lock])
            end

          _ ->
            {:error, :workspace_busy}
        end
      end,
      timeout: :infinity
    )
  end

  @doc false
  def git(sandbox, argv, env \\ %{}, cwd \\ @root) do
    defaults = %{"GIT_CONFIG_NOSYSTEM" => "1", "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_TERMINAL_PROMPT" => "0"}
    command = ["git", "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false", "-c", "credential.helper="] ++ argv

    case Sandboxes.exec(sandbox, command, cwd: cwd, env: Map.merge(defaults, env), timeout_ms: 90_000) do
      {:ok, %{exit_code: 0, stdout: output}} -> {:ok, String.trim(output)}
      _ -> {:error, :git_failed}
    end
  end

  @doc false
  def sha?(sha), do: is_binary(sha) and Regex.match?(~r/\A[0-9a-f]{40}\z/, sha)

  defp resident(context) do
    case Sandboxes.get_sandbox_by_id(context.sandbox.id) do
      %Sandbox{account_id: account_id, residency_work_id: work_id} = sandbox
      when account_id == context.jam.account_id and work_id == context.residency ->
        {:ok, sandbox}

      _ ->
        {:error, :workspace_unavailable}
    end
  end

  # Retention nilifies the binding. A fresh VM cannot recover unpushed work.
  defp sandbox(%{sandbox_id: nil, workspace_ready: true}, _account), do: {:error, :workspace_missing}

  defp sandbox(%{sandbox_id: id, account_id: account_id}, _account) when not is_nil(id) do
    case Sandboxes.get_sandbox_by_id(id) do
      %Sandbox{account_id: ^account_id} = sandbox -> {:ok, sandbox}
      _ -> {:error, :workspace_missing}
    end
  end

  defp sandbox(jam, account) do
    # Persist a creation key BEFORE create_sandbox inserts and boots. Its unique
    # provider_environment_id lets a retry find even a create whose caller died
    # before receiving the result. This is not an Amp/Anthropic session identity.
    binding =
      Repo.get_by(ProviderEnvironment, account_id: account.id, external_key: "jams/#{jam.id}") ||
        Repo.insert!(%ProviderEnvironment{account_id: account.id, external_key: "jams/#{jam.id}"})

    case Repo.get_by(Sandbox, provider_environment_id: binding.id) do
      nil -> Sandboxes.create_sandbox(account, %{provider_environment_id: binding.id})
      %Sandbox{} = sandbox -> {:ok, sandbox}
    end
  end

  defp checkout(%{jam: %{workspace_ready: true} = jam} = context, _account, repository) do
    with {:ok, root} <- git(context.sandbox, ["rev-parse", "--show-toplevel"]),
         true <- root == @root,
         {:ok, remote} <- git(context.sandbox, ["remote", "get-url", "origin"]),
         true <- remote == "https://github.com/#{repository.name}.git",
         {:ok, branch} <- git(context.sandbox, ["symbolic-ref", "--short", "HEAD"]),
         true <- branch == jam.branch,
         {:ok, _} <- git(context.sandbox, ["cat-file", "-e", "#{jam.base_sha}^{commit}"]) do
      {:ok, jam}
    else
      _ -> {:error, :workspace_checkout_missing}
    end
  end

  defp checkout(context, account, repository) do
    jam = context.jam

    with :ok <- initialize(context.sandbox),
         :ok <- origin(context.sandbox, repository.name),
         {:ok, base} <- base(context.sandbox, jam, account, repository),
         :ok <- branch(context.sandbox, jam, base),
         {:ok, updated} <- Jams.bind_workspace(jam.id, context.run_id, context.attempt, context.sandbox.id, base) do
      {:ok, updated}
    else
      _ -> {:error, :workspace_clone_failed}
    end
  end

  defp initialize(sandbox) do
    case Sandboxes.exec(sandbox, ["python3", "-c", @initialize], cwd: "/workspace", env: %{}, timeout_ms: 10_000) do
      {:ok, %{exit_code: 0, stdout: "initialized\n"}} ->
        :ok

      {:ok, %{exit_code: 0, stdout: "empty\n"}} ->
        with {:ok, _} <- git(sandbox, ["init", "--", @root], %{}, "/workspace"), do: :ok

      _ ->
        {:error, :workspace_clone_failed}
    end
  end

  defp origin(sandbox, name) do
    url = "https://github.com/#{name}.git"

    case git(sandbox, ["remote", "get-url", "origin"]) do
      {:ok, ^url} -> :ok
      {:error, _} -> with {:ok, _} <- git(sandbox, ["remote", "add", "origin", url]), do: :ok
      _ -> {:error, :workspace_clone_failed}
    end
  end

  defp base(sandbox, jam, account, repository) do
    case git(sandbox, ["rev-parse", "--verify", "refs/tuist/base^{commit}"]) do
      {:ok, sha} ->
        if sha?(sha), do: {:ok, sha}, else: {:error, :workspace_clone_failed}

      {:error, _} ->
        # Init precedes fetch, so an interrupted network operation can be
        # repeated without cloning over or deleting any existing working tree.
        with {:ok, env} <- Repository.environment(account, repository.name, :read),
             {:ok, _} <-
               git(
                 sandbox,
                 [
                   "fetch",
                   "--no-tags",
                   "--",
                   "origin",
                   "refs/heads/#{jam.base_branch}:refs/remotes/origin/#{jam.base_branch}"
                 ],
                 env
               ),
             {:ok, sha} <- git(sandbox, ["rev-parse", "--verify", "refs/remotes/origin/#{jam.base_branch}^{commit}"]),
             true <- sha?(sha),
             {:ok, _} <- git(sandbox, ["update-ref", "refs/tuist/base", sha, ""]) do
          {:ok, sha}
        else
          _ -> {:error, :workspace_clone_failed}
        end
    end
  end

  defp branch(sandbox, jam, base) do
    name = jam.branch

    case git(sandbox, ["show-ref", "--verify", "--hash", "refs/heads/#{name}"]) do
      {:ok, ^base} ->
        case git(sandbox, ["symbolic-ref", "--short", "HEAD"]) do
          {:ok, ^name} -> :ok
          _ -> {:error, :workspace_clone_failed}
        end

      {:error, _} ->
        with {:ok, _} <- git(sandbox, ["checkout", "-b", name, base]), do: :ok

      _ ->
        {:error, :workspace_clone_failed}
    end
  end

  defp command("bash", %{"command" => command} = args) do
    if map_size(args) == 1 and text?(command, 8000),
      do: {:ok, ["/bin/bash", "--noprofile", "--norc", "-c", command], 60_000},
      else: {:error, :invalid_arguments}
  end

  defp command("read", %{"path" => path} = args) do
    if map_size(args) == 1 and path?(path),
      do: {:ok, ["python3", "-c", @files, "read", path], 10_000},
      else: {:error, :invalid_arguments}
  end

  defp command("write", %{"path" => path, "content" => content} = args) do
    if map_size(args) == 2 and path?(path) and text?(content, @limit, true),
      do: {:ok, ["python3", "-c", @files, "write", path, content], 10_000},
      else: {:error, :invalid_arguments}
  end

  defp command("edit", %{"path" => path, "old_text" => old, "new_text" => new} = args) do
    if map_size(args) == 3 and path?(path) and text?(old, @limit) and text?(new, @limit, true),
      do: {:ok, ["python3", "-c", @files, "edit", path, old, new], 10_000},
      else: {:error, :invalid_arguments}
  end

  defp command(_, _), do: {:error, :invalid_arguments}

  defp path?(path) do
    text?(path, 4096) and not String.starts_with?(path, "/") and
      Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", "..", ".git"]))
  end

  defp text?(value, limit, empty \\ false),
    do:
      is_binary(value) and String.valid?(value) and byte_size(value) <= limit and (empty or value != "") and
        not String.contains?(value, <<0>>)

  defp bounded(output) when byte_size(output) <= @limit, do: output
  defp bounded(output), do: String.replace_invalid(binary_part(output, 0, @limit - 32)) <> "\n[Output truncated]"
end
