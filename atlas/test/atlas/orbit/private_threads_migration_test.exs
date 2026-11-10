defmodule Atlas.Orbit.PrivateThreadsMigrationTest do
  use ExUnit.Case, async: true

  alias Atlas.Repo
  alias Atlas.Repo.Migrations.AllowMultiplePrivateOrbitThreads
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  defmodule ProbeRepo do
    use Ecto.Repo, otp_app: :atlas, adapter: Ecto.Adapters.Postgres
  end

  @migration Path.expand(
               "../../../priv/repo/migrations/20261024170000_allow_multiple_private_orbit_threads.exs",
               __DIR__
             )
  @external_resource @migration
  Code.require_file(@migration)
  @version 20_261_024_170_000

  setup do
    schema = "orbit_private_#{System.unique_integer([:positive])}"
    Sandbox.unboxed_run(Repo, fn -> SQL.query!(Repo, "CREATE SCHEMA #{schema}") end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn -> SQL.query!(Repo, "DROP SCHEMA IF EXISTS #{schema} CASCADE") end)
    end)

    config =
      Keyword.merge(Repo.config(),
        name: ProbeRepo,
        pool: DBConnection.ConnectionPool,
        pool_size: 2,
        parameters: [search_path: schema]
      )

    start_supervised!({ProbeRepo, config})

    query(
      "CREATE TABLE orbit_threads (id uuid PRIMARY KEY, owner_id uuid, kind text, title varchar(255), updated_at timestamptz)"
    )

    query(
      "CREATE UNIQUE INDEX orbit_threads_single_private_thread_index ON orbit_threads (owner_id) WHERE kind = 'private'"
    )

    query(
      "CREATE TABLE orbit_messages (id uuid PRIMARY KEY, thread_id uuid REFERENCES orbit_threads(id), kind text, body text, position bigint)"
    )

    owner = Ecto.UUID.generate()
    thread = Ecto.UUID.generate()
    query("INSERT INTO orbit_threads VALUES ('#{thread}', '#{owner}', 'private', 'Private thread', now())")
    query("INSERT INTO orbit_messages VALUES ('#{Ecto.UUID.generate()}', '#{thread}', 'human', '', 1)")

    query(
      "INSERT INTO orbit_messages VALUES ('#{Ecto.UUID.generate()}', '#{thread}', 'human', E'First\n  question', 2)"
    )

    query("INSERT INTO orbit_messages VALUES ('#{Ecto.UUID.generate()}', '#{thread}', 'human', 'Follow-up', 3)")
    %{owner: owner, thread: thread, messages: query("SELECT * FROM orbit_messages ORDER BY position").rows}
  end

  test "replaces only private uniqueness and preserves history through up/down/up", context do
    assert :ok = Ecto.Migrator.up(ProbeRepo, @version, AllowMultiplePrivateOrbitThreads, log: false)
    assert query("SELECT title, request_id FROM orbit_threads").rows == [["First question", nil]]
    assert query("SELECT * FROM orbit_messages ORDER BY position").rows == context.messages

    assert :ok = Ecto.Migrator.down(ProbeRepo, @version, AllowMultiplePrivateOrbitThreads, log: false)
    assert query("SELECT * FROM orbit_messages ORDER BY position").rows == context.messages
    assert :ok = Ecto.Migrator.up(ProbeRepo, @version, AllowMultiplePrivateOrbitThreads, log: false)
    assert query("SELECT title FROM orbit_threads").rows == [["First question"]]
    assert query("SELECT * FROM orbit_messages ORDER BY position").rows == context.messages
  end

  test "allows distinct private histories, rejects duplicate replay IDs, and refuses lossy rollback", context do
    assert :ok = Ecto.Migrator.up(ProbeRepo, @version, AllowMultiplePrivateOrbitThreads, log: false)
    request = Ecto.UUID.generate()

    query(
      "INSERT INTO orbit_threads VALUES ('#{Ecto.UUID.generate()}', '#{context.owner}', 'private', 'New conversation', now(), '#{request}')"
    )

    assert_raise Postgrex.Error, fn ->
      query(
        "INSERT INTO orbit_threads VALUES ('#{Ecto.UUID.generate()}', '#{context.owner}', 'private', 'Duplicate', now(), '#{request}')"
      )
    end

    # The same UUID belongs to another owner, not a globally readable creation key.
    query(
      "INSERT INTO orbit_threads VALUES ('#{Ecto.UUID.generate()}', '#{Ecto.UUID.generate()}', 'private', 'New conversation', now(), '#{request}')"
    )

    query(
      "INSERT INTO orbit_threads VALUES ('#{Ecto.UUID.generate()}', '#{context.owner}', 'shared', 'Shared', now(), '#{request}')"
    )

    assert query("SELECT count(*) FROM orbit_threads").rows == [[4]]

    assert_raise Postgrex.Error, fn ->
      Ecto.Migrator.down(ProbeRepo, @version, AllowMultiplePrivateOrbitThreads, log: false)
    end

    assert query("SELECT count(*) FROM orbit_threads").rows == [[4]]
    assert query("SELECT * FROM orbit_messages ORDER BY position").rows == context.messages
    assert query("SELECT count(*) FROM orbit_threads WHERE request_id IS NOT NULL").rows == [[3]]
  end

  defp query(sql), do: SQL.query!(ProbeRepo, sql)
end
