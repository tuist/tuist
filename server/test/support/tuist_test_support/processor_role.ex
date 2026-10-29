defmodule TuistTestSupport.ProcessorRole do
  @moduledoc """
  Runs a function against Postgres with the privileges the deployed
  `tuist_processor` role has.

  Managed deployments connect the build, Bazel and xcresult processors as that
  role, and `Tuist.Release` re-derives its table privileges on every migrate:
  everything revoked, then only the enumerated tables granted back. Tests
  otherwise connect as the schema owner, so a processor path reading a table
  missing from those lists passes here and raises `42501` in production.

  `as_processor/1` creates the role from the same grant statements inside the
  test's sandbox transaction and switches the connection to it. An ungranted
  table then fails with the error production would raise.
  """

  alias Ecto.Adapters.SQL
  alias Tuist.Release
  alias Tuist.Repo

  def as_processor(fun) do
    # A warm feature-flag cache answers from ETS and never reaches the table.
    # A denied read caches nothing, so the processors always read this cold.
    FunWithFlags.Store.Cache.flush()

    role = ensure_role()
    SQL.query!(Repo, ~s(SET LOCAL ROLE #{role}), [])

    try do
      fun.()
    after
      SQL.query!(Repo, "RESET ROLE", [])
    end
  end

  # The role is a cluster-wide object while the database is per test partition,
  # so name it after the database to keep concurrent partitions from fighting
  # over one name. Creation and grants live inside the sandbox transaction and
  # disappear with its rollback.
  defp ensure_role do
    database = Keyword.fetch!(Repo.config(), :database)
    role = ~s("#{database}_processor")

    SQL.query!(Repo, ~s(DROP ROLE IF EXISTS #{role}), [])
    SQL.query!(Repo, ~s(CREATE ROLE #{role} NOLOGIN), [])

    for statement <- Release.processor_role_grant_statements(role, ~s("#{database}"), ~s("public")) do
      SQL.query!(Repo, statement, [])
    end

    SQL.query!(Repo, ~s(GRANT #{role} TO CURRENT_USER), [])

    role
  end
end
