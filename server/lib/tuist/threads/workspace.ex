defmodule Tuist.Threads.Workspace do
  @moduledoc "Persistent thread checkouts, with one attempt-scoped sandbox residency per run."

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.ProviderEnvironment
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Threads
  alias Tuist.Threads.Repository

  @root "/workspace/repository"

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

  def prepare(thread, run) do
    exclusive(thread.id, fn ->
      with true <- run.thread_id == thread.id and Threads.owns_run?(run.id, run.attempt),
           thread = Repo.reload!(thread),
           true <- thread.status == :active,
           {:ok, account} <- Accounts.get_account_by_id(thread.account_id),
           {:ok, repository} <- Repository.authorize(account, thread.repository),
           {:ok, sandbox} <- sandbox(thread, account),
           {:ok, thread} <- Threads.bind_sandbox(thread.id, run.id, run.attempt, sandbox.id),
           work_id = "threads:#{run.id}:#{run.attempt}",
           {:ok, sandbox} <- Sandboxes.prepare_residency(sandbox, work_id) do
        context = %{thread: thread, sandbox: sandbox, residency: work_id, run_id: run.id, attempt: run.attempt}

        case checkout(context, account, repository) do
          {:ok, thread} ->
            {:ok, %{context | thread: thread}}

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

  @doc false
  def exclusive(thread_id, fun) do
    # A session lock, not a transaction or row lock, spans external boot/git
    # calls. Other replicas fail fast; database disconnect releases the lock.
    Repo.checkout(
      fn ->
        lock = "threads-workspace:#{thread_id}"

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

  # Retention nilifies the binding. A fresh VM cannot recover unpushed work.
  defp sandbox(%{sandbox_id: nil, workspace_ready: true}, _account), do: {:error, :workspace_missing}

  defp sandbox(%{sandbox_id: id, account_id: account_id}, _account) when not is_nil(id) do
    case Sandboxes.get_sandbox_by_id(id) do
      %Sandbox{account_id: ^account_id} = sandbox -> {:ok, sandbox}
      _ -> {:error, :workspace_missing}
    end
  end

  defp sandbox(thread, account) do
    # Persist a creation key BEFORE create_sandbox inserts and boots. Its unique
    # provider_environment_id lets a retry find even a create whose caller died
    # before receiving the result. This is not an Amp/Anthropic session identity.
    binding =
      Repo.get_by(ProviderEnvironment, account_id: account.id, external_key: "threads/#{thread.id}") ||
        Repo.insert!(%ProviderEnvironment{account_id: account.id, external_key: "threads/#{thread.id}"})

    case Repo.get_by(Sandbox, provider_environment_id: binding.id) do
      nil -> Sandboxes.create_sandbox(account, %{provider_environment_id: binding.id})
      %Sandbox{} = sandbox -> {:ok, sandbox}
    end
  end

  defp checkout(%{thread: %{workspace_ready: true} = thread} = context, _account, repository) do
    with {:ok, root} <- git(context.sandbox, ["rev-parse", "--show-toplevel"]),
         true <- root == @root,
         {:ok, remote} <- git(context.sandbox, ["remote", "get-url", "origin"]),
         true <- remote == "https://github.com/#{repository.name}.git",
         {:ok, branch} <- git(context.sandbox, ["symbolic-ref", "--short", "HEAD"]),
         true <- branch == thread.branch,
         {:ok, _} <- git(context.sandbox, ["cat-file", "-e", "#{thread.base_sha}^{commit}"]) do
      {:ok, thread}
    else
      _ -> {:error, :workspace_checkout_missing}
    end
  end

  defp checkout(context, account, repository) do
    thread = context.thread

    with :ok <- initialize(context.sandbox),
         :ok <- origin(context.sandbox, repository.name),
         {:ok, base} <- base(context.sandbox, thread, account, repository),
         :ok <- branch(context.sandbox, thread, base),
         {:ok, updated} <- Threads.bind_workspace(thread.id, context.run_id, context.attempt, context.sandbox.id, base) do
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

  defp base(sandbox, thread, account, repository) do
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
                   "refs/heads/#{thread.base_branch}:refs/remotes/origin/#{thread.base_branch}"
                 ],
                 env
               ),
             {:ok, sha} <- git(sandbox, ["rev-parse", "--verify", "refs/remotes/origin/#{thread.base_branch}^{commit}"]),
             true <- sha?(sha),
             {:ok, _} <- git(sandbox, ["update-ref", "refs/tuist/base", sha, ""]) do
          {:ok, sha}
        else
          _ -> {:error, :workspace_clone_failed}
        end
    end
  end

  defp branch(sandbox, thread, base) do
    name = thread.branch

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
end
