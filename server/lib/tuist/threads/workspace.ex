defmodule Tuist.Threads.Workspace do
  @moduledoc """
  Every thread's sandbox, with one attempt-scoped residency per run, and the
  thread's repository checkout in it at `/workspace/repository`.

  The sandbox is created on the thread's first run, whether or not the
  thread has a repository; one that failed to boot is replaced while the
  thread holds no checkout. A thread gets its one repository, which Ship
  publishes to, when its owner names it at creation, and `prepare/2` checks
  it out before any tool runs; or when the agent asks for one its owner can
  read on GitHub (`Tuist.Threads.request_repository/2`), and `attach/1`
  checks it out during that run.

  The guest is untrusted: the agent's shell may have run there as root. A
  checkout's base is the commit GitHub reports for the base branch, read by
  the server (`Repository.branch_head/3`). The server fetches it and stages
  an archive (`Tuist.Threads.Checkout`), so no repository credential ever
  enters the guest; the guest only unpacks it into a fresh directory, which
  replaces `/workspace/repository` (moving whatever was there aside).
  """

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.ProviderEnvironment
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Threads
  alias Tuist.Threads.Checkout
  alias Tuist.Threads.Repository

  require Logger

  @root "/workspace/repository"

  # How long each step of a checkout may take. A run's `prepare/2` is under no
  # other deadline; the unpack stays under `Sandboxes.exec/3`'s 600 s cap,
  # with `curl` leaving the rest of it to unpack. `attach/1` runs in a tool
  # call, which Condukt ends after 300 s: what does not fit is left bound for
  # the next run's `prepare/2`.
  @budgets %{
    prepare: %{fetch_ms: 300_000, archive_ms: 120_000, download_s: 480, unpack_ms: 600_000},
    attach: %{fetch_ms: 120_000, archive_ms: 30_000, download_s: 60, unpack_ms: 90_000}
  }

  # Unpacks the server's checkout archive (`Tuist.Threads.Checkout`) into a
  # fresh directory, checks out the thread's branch at the base, then moves
  # any previous /workspace/repository aside and puts the new one in its
  # place. The archive URL reads one object and carries no other credential.
  @unpack ~S"""
  set -eu
  cd "$WORKSPACE"
  mkdir -- "$STAGING"
  curl -fsS --retry 3 --max-time "$DOWNLOAD_SECONDS" -o "$STAGING.tar" -- "$CHECKOUT_URL"
  mkdir -- "$STAGING/.git"
  tar -xf "$STAGING.tar" -C "$STAGING/.git"
  rm -f -- "$STAGING.tar"
  cd "$STAGING"
  git config core.bare false
  git checkout -q -b "$BRANCH" "$BASE"
  test "$(git rev-parse --verify 'HEAD^{commit}')" = "$BASE"
  cd "$WORKSPACE"
  if [ -e repository ] || [ -L repository ]; then mv -- repository "repository.previous-$(date +%s%N)"; fi
  mv -- "$STAGING" repository
  """

  def prepare(thread, run) do
    exclusive(thread.id, fn ->
      with true <- run.thread_id == thread.id and Threads.owns_run?(run.id, run.attempt),
           thread = Repo.reload!(thread),
           true <- thread.status == :active,
           {:ok, account} <- Accounts.get_account_by_id(thread.account_id),
           {:ok, repository} <- authorize(account, thread),
           {:ok, sandbox} <- sandbox(thread, account),
           {:ok, thread} <- Threads.bind_sandbox(thread.id, run.id, run.attempt, sandbox.id),
           work_id = "threads:#{run.id}:#{run.attempt}",
           {:ok, sandbox} <- Sandboxes.prepare_residency(sandbox, work_id) do
        context = %{thread: thread, sandbox: sandbox, residency: work_id, run_id: run.id, attempt: run.attempt}

        case checkout(context, account, repository, @budgets.prepare) do
          {:ok, thread} ->
            {:ok, %{context | thread: thread}}

          {:error, _} = error ->
            release(context)
            error
        end
      else
        false -> {:error, :stale_run}
        {:error, reason} -> {:error, reason}
        _ -> {:error, :workspace_unavailable}
      end
    end)
  end

  @doc """
  Checks out the repository the agent bound during the run of `context`
  (`prepare/2`'s), in that run's sandbox. A failure leaves the thread's
  repository bound and unchecked out, for the next run's `prepare/2`.
  """
  def attach(context) do
    exclusive(context.thread.id, fn ->
      thread = Repo.reload!(context.thread)

      with true <- Threads.owns_run?(context.run_id, context.attempt) || {:error, :stale_run},
           {:ok, account} <- Accounts.get_account_by_id(thread.account_id),
           {:ok, repository} when not is_nil(repository) <- authorize(account, thread) do
        checkout(%{context | thread: thread}, account, repository, @budgets.attach)
      else
        {:ok, nil} -> {:error, :workspace_unavailable}
        {:error, _} = error -> error
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

  defp sandbox(%{sandbox_id: id, account_id: account_id, workspace_ready: true}, _account) do
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
      nil ->
        Sandboxes.create_sandbox(account, %{provider_environment_id: binding.id})

      # A create that never booted (`last_active_at` is set once one runs)
      # and has no archive holds nothing: replace it rather than refuse every
      # later run until retention deletes it. Any other error keeps what may
      # hold the thread's /workspace files, such as a node that left the
      # cluster and could come back.
      %Sandbox{state: :error, last_active_at: nil, archive_key: nil} = errored ->
        with {:ok, _deleted} <- Sandboxes.delete(errored),
             do: Sandboxes.create_sandbox(account, %{provider_environment_id: binding.id})

      %Sandbox{} = sandbox ->
        {:ok, sandbox}
    end
  end

  # Every run rechecks the owner's GitHub access, so one who lost it stops
  # getting the repository's newer commits and tool access to its checkout.
  defp authorize(_account, %{repository: nil}), do: {:ok, nil}

  defp authorize(account, thread) do
    case Accounts.get_user_by_id(thread.owner_id) do
      nil -> {:error, :forbidden}
      owner -> Repository.authorize(account, owner, thread.repository)
    end
  end

  defp checkout(context, _account, nil, _budget), do: {:ok, context.thread}

  defp checkout(%{thread: %{workspace_ready: true} = thread} = context, _account, repository, _budget) do
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

  defp checkout(context, account, repository, budget) do
    thread = context.thread
    staging = ".tuist-checkout-#{Ecto.UUID.generate()}"
    stage_opts = [fetch_ms: budget.fetch_ms, archive_ms: budget.archive_ms]

    result =
      with {:ok, base} <- Repository.branch_head(account, repository.name, thread.base_branch),
           true <- sha?(base) || {:error, :invalid_base},
           {:ok, url} <- Checkout.stage(account, context.sandbox, repository.name, base, stage_opts),
           :ok <- unpack(context.sandbox, staging, url, base, thread.branch, budget) do
        Threads.bind_workspace(thread, context.run_id, context.attempt, context.sandbox.id, base)
      end

    case result do
      {:ok, updated} ->
        {:ok, updated}

      {:error, reason} = error ->
        Logger.warning("threads: checking out #{repository.name} for thread #{thread.id} failed: #{inspect(reason)}")
        remove(context.sandbox, staging)
        failed(context, error)
    end
  end

  defp failed(_context, {:error, reason}) when reason in [:repository_attached, :stale_run], do: {:error, reason}

  # A checkout that can never succeed would fail every later run of the
  # thread; nothing is checked out, so the thread gives the repository up.
  defp failed(context, {:error, :checkout_too_large}) do
    _ = Threads.unbind_repository(context.thread, context.run_id, context.attempt)
    {:error, :repository_too_large}
  end

  defp failed(_context, _error), do: {:error, :workspace_clone_failed}

  defp unpack(sandbox, staging, url, base, branch, budget) do
    env = %{
      "WORKSPACE" => "/workspace",
      "STAGING" => staging,
      "CHECKOUT_URL" => url,
      "BASE" => base,
      "BRANCH" => branch,
      "DOWNLOAD_SECONDS" => to_string(budget.download_s)
    }

    case Sandboxes.exec(sandbox, ["/bin/bash", "-c", @unpack], cwd: "/workspace", env: env, timeout_ms: budget.unpack_ms) do
      {:ok, %{exit_code: 0}} ->
        :ok

      result ->
        Logger.warning("threads: unpacking a checkout failed: #{inspect(exit_status(result))}", sandbox_id: sandbox.id)
        {:error, :workspace_clone_failed}
    end
  end

  defp exit_status({:ok, %{exit_code: code}}), do: code
  defp exit_status({:error, reason}), do: reason

  defp remove(sandbox, staging) do
    _ =
      Sandboxes.exec(sandbox, ["rm", "-rf", "--", "/workspace/" <> staging, "/workspace/#{staging}.tar"],
        cwd: "/workspace",
        env: %{},
        timeout_ms: 30_000
      )

    :ok
  end
end
