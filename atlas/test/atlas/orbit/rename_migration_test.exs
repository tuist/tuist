defmodule Atlas.Orbit.RenameMigrationTest do
  use ExUnit.Case, async: true

  alias Atlas.Repo
  alias Atlas.Repo.Migrations.CreateConversations
  alias Atlas.Repo.Migrations.RenameConversationsToOrbit
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  defmodule ProbeRepo do
    use Ecto.Repo, otp_app: :atlas, adapter: Ecto.Adapters.Postgres
  end

  @original Path.expand("../../../priv/repo/migrations/20261022120000_create_conversations.exs", __DIR__)
  @rename Path.expand("../../../priv/repo/migrations/20261022191026_rename_conversations_to_orbit.exs", __DIR__)
  @external_resource @original
  @external_resource @rename
  Code.require_file(@original)
  Code.require_file(@rename)

  @user "01922cc0-0000-7000-8000-000000000001"
  @thread "01922cc0-0000-7000-8000-000000000002"
  @profile "01922cc0-0000-7000-8000-000000000003"
  @run "01922cc0-0000-7000-8000-000000000004"
  @message "01922cc0-0000-7000-8000-000000000005"
  @client "01922cc0-0000-7000-8000-000000000006"

  setup do
    schema = "orbit_rename_#{System.unique_integer([:positive])}"
    Sandbox.unboxed_run(Repo, fn -> SQL.query!(Repo, "CREATE SCHEMA #{schema}") end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn -> SQL.query!(Repo, "DROP SCHEMA IF EXISTS #{schema} CASCADE") end)
    end)

    config =
      Repo.config()
      |> Keyword.merge(
        name: ProbeRepo,
        pool: DBConnection.ConnectionPool,
        pool_size: 2,
        parameters: [search_path: schema]
      )

    start_supervised!({ProbeRepo, config})

    for statement <- [
          "CREATE TABLE users (id uuid PRIMARY KEY)",
          "CREATE TABLE inference_model_bindings (id uuid PRIMARY KEY)",
          "CREATE TABLE inference_tokens (atlas_role text, token_hash text)",
          "CREATE TABLE oban_jobs (worker text, queue text, args jsonb)",
          "CREATE TABLE agent_sessions (agent text, prompt text)"
        ] do
      query(statement)
    end

    assert :ok = Ecto.Migrator.up(ProbeRepo, 20_261_022_120_000, CreateConversations, log: false)
    seed_legacy_rows()
    :ok
  end

  test "renames and rolls back without losing history, execution state, credentials or job identity" do
    assert :ok = Ecto.Migrator.up(ProbeRepo, 20_261_022_191_026, RenameConversationsToOrbit, log: false)
    assert_orbit_rows()

    assert query(
             "SELECT indexname FROM pg_indexes WHERE schemaname = current_schema() AND indexname = 'orbit_messages_client_id_index'"
           ).rows ==
             [["orbit_messages_client_id_index"]]

    assert query(
             "SELECT conname FROM pg_constraint WHERE conrelid = 'orbit_participants'::regclass AND conname = 'orbit_participants_thread_id_fkey'"
           ).rows ==
             [["orbit_participants_thread_id_fkey"]]

    assert :ok = Ecto.Migrator.down(ProbeRepo, 20_261_022_191_026, RenameConversationsToOrbit, log: false)

    assert query("SELECT id, conversation_id, body, client_id FROM conversation_messages").rows ==
             [[uuid(@message), uuid(@thread), "Before rename", uuid(@client)]]

    assert query("SELECT checkpoint, session_id FROM conversation_runs").rows == [
             [<<1, 2, 3, 255>>, "existing-session"]
           ]

    assert query("SELECT atlas_conversations FROM inference_model_bindings").rows == [[true]]
    assert query("SELECT atlas_role, token_hash FROM inference_tokens").rows == [["conversations", "existing-hash"]]

    assert query("SELECT worker, queue, args FROM oban_jobs").rows ==
             [["Atlas.Conversations.Workers.RunConversation", "conversations", %{"run_id" => @run, "resume" => 1}]]

    assert query("SELECT agent, prompt FROM agent_sessions").rows ==
             [["Atlas.Conversations.Agent", "conversation_run:#{@run}"]]

    assert :ok = Ecto.Migrator.up(ProbeRepo, 20_261_022_191_026, RenameConversationsToOrbit, log: false)
    assert_orbit_rows()
  end

  defp assert_orbit_rows do
    assert query("SELECT id, thread_id, body, client_id, tool_result FROM orbit_messages").rows ==
             [[uuid(@message), uuid(@thread), "Before rename", uuid(@client), <<4, 5, 255>>]]

    assert query("SELECT id, thread_id, checkpoint, session_id, resume_count FROM orbit_runs").rows ==
             [[uuid(@run), uuid(@thread), <<1, 2, 3, 255>>, "existing-session", 1]]

    assert query("SELECT id, owner_id, required_scopes FROM orbit_threads").rows ==
             [[uuid(@thread), uuid(@user), ["accounts:read"]]]

    assert query("SELECT thread_id, user_id FROM orbit_participants").rows == [[uuid(@thread), uuid(@user)]]
    assert query("SELECT thread_id, user_id FROM orbit_viewers").rows == [[uuid(@thread), uuid(@user)]]
    assert query("SELECT atlas_orbit FROM inference_model_bindings").rows == [[true]]
    assert query("SELECT atlas_role, token_hash FROM inference_tokens").rows == [["orbit", "existing-hash"]]

    assert query("SELECT worker, queue, args FROM oban_jobs").rows ==
             [["Atlas.Orbit.Workers.RunThread", "orbit", %{"run_id" => @run, "resume" => 1}]]

    assert query("SELECT agent, prompt FROM agent_sessions").rows == [["Atlas.Orbit.Agent", "orbit_run:#{@run}"]]
  end

  defp seed_legacy_rows do
    query("INSERT INTO users VALUES ('#{@user}')")
    query("INSERT INTO inference_model_bindings VALUES ('#{@profile}', true)")
    query("INSERT INTO inference_tokens VALUES ('conversations', 'existing-hash')")

    query("""
    INSERT INTO conversations (id, kind, title, owner_id, required_scopes, inserted_at, updated_at)
    VALUES ('#{@thread}', 'private', 'Existing thread', '#{@user}', ARRAY['accounts:read'], now(), now())
    """)

    query("""
    INSERT INTO conversation_participants (conversation_id, user_id, role, inserted_at)
    VALUES ('#{@thread}', '#{@user}', 'owner', now())
    """)

    query("""
    INSERT INTO conversation_runs (id, conversation_id, model_binding_id, trigger_seq, checkpoint, session_id, resume_count, inserted_at, updated_at)
    VALUES ('#{@run}', '#{@thread}', '#{@profile}', 1, decode('010203ff', 'hex'), 'existing-session', 1, now(), now())
    """)

    query("""
    INSERT INTO conversation_messages (id, conversation_id, run_id, kind, body, client_id, tool_result, position, seq, inserted_at, updated_at)
    VALUES ('#{@message}', '#{@thread}', '#{@run}', 'tool', 'Before rename', '#{@client}', decode('0405ff', 'hex'), 1, 1, now(), now())
    """)

    query("""
    INSERT INTO conversation_viewers (connection_id, conversation_id, user_id)
    VALUES ('#{@client}', '#{@thread}', '#{@user}')
    """)

    query("""
    INSERT INTO oban_jobs VALUES ('Atlas.Conversations.Workers.RunConversation', 'conversations', '{"run_id":"#{@run}","resume":1}')
    """)

    query("INSERT INTO agent_sessions VALUES ('Atlas.Conversations.Agent', 'conversation_run:#{@run}')")
  end

  defp query(sql), do: SQL.query!(ProbeRepo, sql)
  defp uuid(value), do: Ecto.UUID.dump!(value)
end
