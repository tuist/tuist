defmodule Tuist.ClickHouse.Endpoints do
  @moduledoc """
  Resolves the two ClickHouse servers the migration tasks work across, and
  starts them properly.

  Both are already configured Ecto repositories: `Tuist.IngestRepo` is the
  system of record, and `Tuist.ShadowIngestRepo` is the in-cluster server
  being migrated onto. Going through them rather than opening connections by
  hand fixes two things that a first attempt got wrong.

  A release task runs under `bin/tuist eval`, which loads the application but
  does not start it, so `DBConnection`'s supervisor is not running and
  `Ch.start_link/1` exits with `no process`. `Ecto.Migrator.with_repo/3` is
  the pattern the rest of `Tuist.Release` already uses for exactly this, and
  it starts the repository and its dependencies before handing it over.

  More importantly, no credential passes through this code. The first
  implementation parsed the URLs itself and passed a password to
  `Ch.start_link/1`; when that call exited, the connection options went into
  the crash message, and the ClickHouse Cloud password was written to the pod
  log. Reading configuration from a started repository means there is nothing
  to leak, and every statement these modules issue is emitted with
  `log: false` so a query carrying a credential cannot be logged either.
  """

  alias Tuist.Environment

  require Logger

  @ready_timeout to_timeout(minute: 5)
  @ready_interval to_timeout(second: 5)

  @doc """
  Starts the ledger, source and destination repositories and calls `fun` with a
  descriptor for the two ClickHouse ones, then shuts them all down again.

  Returns `{:error, :no_target_configured}` when the destination is not
  configured, which is every environment that is not mid-migration.
  """
  def with_repos(opts \\ [], fun) do
    source_repo = Keyword.get(opts, :source_repo, Tuist.IngestRepo)
    target_repo = Keyword.get(opts, :target_repo, Tuist.ShadowIngestRepo)

    if is_nil(Environment.clickhouse_bare_metal_url()) do
      {:error, :no_target_configured}
    else
      # The backfill records its progress in Postgres, which `bin/tuist eval`
      # has not started either. A repository that is not started fails at the
      # first query rather than at lookup, so the omission surfaced only once
      # the first chunk had already been copied.
      with_started_repo(Tuist.Repo, fn _ledger -> with_clickhouse_repos(source_repo, target_repo, fun) end)
    end
  end

  @doc """
  Waits until `endpoint` answers a query, for up to `:ready_timeout`.

  The in-cluster server is rolled by the same release that runs these tasks, so
  a `post-upgrade` Job reaches it while its pod may still be coming back. The
  pool reports that as a queue timeout within seconds, and a task that takes
  the first refusal at face value fails its Job, which fails the release and
  rolls it back. Waiting is what keeps a restart window a transient rather than
  a failed deploy.

  Returns `{:error, {:not_ready, database, reason}}` carrying the last refusal
  once the deadline passes.
  """
  def await_ready(endpoint, opts \\ []) do
    interval = Keyword.get(opts, :ready_interval, @ready_interval)
    deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :ready_timeout, @ready_timeout)

    await_ready(endpoint, interval, deadline)
  end

  defp await_ready(endpoint, interval, deadline) do
    case endpoint.repo.query("SELECT 1", [], log: false) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        if System.monotonic_time(:millisecond) + interval < deadline do
          Logger.info("#{endpoint.database} is not answering yet; retrying in #{interval}ms")
          Process.sleep(interval)
          await_ready(endpoint, interval, deadline)
        else
          {:error, {:not_ready, endpoint.database, reason}}
        end
    end
  end

  defp with_clickhouse_repos(source_repo, target_repo, fun) do
    with_started_repo(source_repo, fn source ->
      with_started_repo(target_repo, fn target -> fun.(source, target) end)
    end)
  end

  defp with_started_repo(repo, fun) do
    {:ok, result, _apps} =
      Ecto.Migrator.with_repo(repo, fn started ->
        fun.(%{repo: started, database: database(started)})
      end)

    result
  end

  @doc """
  The database a started repository is pointed at.
  """
  def database(repo) do
    repo.config() |> Keyword.fetch!(:database) |> to_string()
  end

  @doc """
  Quotes an identifier for interpolation into a statement.
  """
  def quote_ident(name), do: "`" <> String.replace(to_string(name), "`", "``") <> "`"
end
