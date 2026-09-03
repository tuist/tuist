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

  @doc """
  Starts the source and destination repositories and calls `fun` with a
  descriptor for each, then shuts them down again.

  Returns `{:error, :no_target_configured}` when the destination is not
  configured, which is every environment that is not mid-migration.
  """
  def with_repos(opts \\ [], fun) do
    source_repo = Keyword.get(opts, :source_repo, Tuist.IngestRepo)
    target_repo = Keyword.get(opts, :target_repo, Tuist.ShadowIngestRepo)

    if is_nil(Environment.clickhouse_bare_metal_url()) do
      {:error, :no_target_configured}
    else
      with_started_repo(source_repo, fn source ->
        with_started_repo(target_repo, fn target -> fun.(source, target) end)
      end)
    end
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
