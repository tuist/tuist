# SQL targets only connection-local temporary tables inside a sandbox transaction.
# excellent_migrations:safety-assured-for-this-file operation_query operation_config
Code.require_file(Path.expand("../../../../priv/repo/migrations/20261105190000_create_threads.exs", __DIR__))
Code.require_file(Path.expand("../../../../priv/repo/migrations/20261108170000_rename_threads_to_jams.exs", __DIR__))

defmodule Tuist.Repo.Migrations.RenameThreadsToJamsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Ecto.Migration.Runner
  alias Tuist.Repo.Migrations.CreateThreads
  alias Tuist.Repo.Migrations.RenameThreadsToJams

  test "renames persisted history and execution identities in place and rolls back without losing consent" do
    Repo.query!("CREATE TEMP TABLE accounts (id bigint PRIMARY KEY)")
    Repo.query!("CREATE TEMP TABLE users (id bigint PRIMARY KEY)")
    Repo.query!("CREATE TEMP TABLE sandboxes (id uuid PRIMARY KEY, residency_work_id text)")
    Repo.query!("CREATE TEMP TABLE sandbox_provider_environments (external_key text)")
    Repo.query!("CREATE TEMP TABLE oban_jobs (worker text, queue text, args jsonb)")
    migrate(CreateThreads, :change, :up)

    Repo.query!("INSERT INTO pg_temp.accounts VALUES (1)")
    Repo.query!("INSERT INTO pg_temp.users VALUES (1)")

    Repo.query!("""
    INSERT INTO pg_temp.threads
      (id, account_id, owner_id, request_id, request_hash, title, goal, provider, model, branch, inserted_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000001', 1, 1, '00000000-0000-0000-0000-000000000002',
      '\\x0102', 'Saved work', 'Fix it', 'chatgpt', 'model', 'threads/saved-branch', now(), now())
    """)

    Repo.query!("""
    INSERT INTO pg_temp.thread_messages (id, thread_id, position, kind, body, inserted_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
      1, 'human', 'Keep this request', now(), now())
    """)

    Repo.query!("""
    INSERT INTO pg_temp.thread_ship_approvals
      (id, request_id, thread_id, account_id, repository, head_sha, diff, target_branch, mode, inserted_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000005',
      '00000000-0000-0000-0000-000000000001', 1, 'Tuist/Example', 'head', 'exact diff', 'threads/saved-branch',
      'branch', now(), now())
    """)

    Repo.query!("""
    INSERT INTO pg_temp.thread_runs (id, thread_id, message_id, approval_id, checkpoint, inserted_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004', '\\xdeadbeef', now(), now())
    """)

    Repo.query!("""
    INSERT INTO pg_temp.thread_tool_calls (id, run_id, fingerprint, name, result, inserted_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000006',
      '\\x0102', 'bash', '\\xcafe', now(), now())
    """)

    Repo.query!("INSERT INTO pg_temp.thread_inboxes VALUES (1, 1, 42)")

    Repo.query!("""
    INSERT INTO pg_temp.oban_jobs VALUES
      ('Tuist.Threads.Worker', 'threads', '{"run_id":"saved-run","attempt":2}'),
      ('Tuist.Threads.RecoveryWorker', 'threads', '{}'),
      ('Tuist.Unrelated.Worker', 'default', '{}')
    """)

    Repo.query!("INSERT INTO pg_temp.sandbox_provider_environments VALUES ('threads/saved-jam'), ('amp/keep')")

    Repo.query!("""
    INSERT INTO pg_temp.sandboxes VALUES
      ('00000000-0000-0000-0000-000000000008', 'threads:saved-run:2'),
      ('00000000-0000-0000-0000-000000000009', 'threads-ship:saved-run:2'),
      ('00000000-0000-0000-0000-000000000010', 'amp:keep')
    """)

    migrate(RenameThreadsToJams, :up, :up)

    assert Repo.query!("SELECT branch FROM pg_temp.jams").rows == [["threads/saved-branch"]]
    assert Repo.query!("SELECT body FROM pg_temp.jam_messages").rows == [["Keep this request"]]

    assert Repo.query!("SELECT diff, target_branch FROM pg_temp.jam_ship_approvals").rows ==
             [["exact diff", "threads/saved-branch"]]

    assert Repo.query!("SELECT checkpoint FROM pg_temp.jam_runs").rows == [[<<0xDE, 0xAD, 0xBE, 0xEF>>]]
    assert Repo.query!("SELECT result FROM pg_temp.jam_tool_calls").rows == [[<<0xCA, 0xFE>>]]
    assert Repo.query!("SELECT revision FROM pg_temp.jam_inboxes").rows == [[42]]

    assert Repo.query!("SELECT worker, queue FROM pg_temp.oban_jobs ORDER BY worker").rows ==
             [["Tuist.Jams.RecoveryWorker", "jams"], ["Tuist.Jams.Worker", "jams"], ["Tuist.Unrelated.Worker", "default"]]

    assert Repo.query!("SELECT args FROM pg_temp.oban_jobs WHERE worker = 'Tuist.Jams.Worker'").rows ==
             [[%{"run_id" => "saved-run", "attempt" => 2}]]

    assert Repo.query!("SELECT external_key FROM pg_temp.sandbox_provider_environments ORDER BY external_key").rows ==
             [["amp/keep"], ["jams/saved-jam"]]

    assert Repo.query!("SELECT residency_work_id FROM pg_temp.sandboxes ORDER BY id").rows ==
             [["jams:saved-run:2"], ["jams-ship:saved-run:2"], ["amp:keep"]]

    migrate(RenameThreadsToJams, :down, :down)

    assert Repo.query!("SELECT branch FROM pg_temp.threads").rows == [["threads/saved-branch"]]
    assert Repo.query!("SELECT body FROM pg_temp.thread_messages").rows == [["Keep this request"]]
    assert Repo.query!("SELECT diff FROM pg_temp.thread_ship_approvals").rows == [["exact diff"]]
    assert Repo.query!("SELECT checkpoint FROM pg_temp.thread_runs").rows == [[<<0xDE, 0xAD, 0xBE, 0xEF>>]]
    assert Repo.query!("SELECT result FROM pg_temp.thread_tool_calls").rows == [[<<0xCA, 0xFE>>]]
    assert Repo.query!("SELECT revision FROM pg_temp.thread_inboxes").rows == [[42]]

    assert Repo.query!("SELECT worker, queue FROM pg_temp.oban_jobs ORDER BY worker").rows ==
             [
               ["Tuist.Threads.RecoveryWorker", "threads"],
               ["Tuist.Threads.Worker", "threads"],
               ["Tuist.Unrelated.Worker", "default"]
             ]

    assert Repo.query!("SELECT external_key FROM pg_temp.sandbox_provider_environments ORDER BY external_key").rows ==
             [["amp/keep"], ["threads/saved-jam"]]

    assert Repo.query!("SELECT residency_work_id FROM pg_temp.sandboxes ORDER BY id").rows ==
             [["threads:saved-run:2"], ["threads-ship:saved-run:2"], ["amp:keep"]]

    # The renamed foreign keys still cascade through messages, approvals, runs and tool results.
    Repo.query!("DELETE FROM pg_temp.threads")

    for table <- ~w(thread_messages thread_ship_approvals thread_runs thread_tool_calls) do
      assert Repo.query!("SELECT count(*) FROM pg_temp.#{table}").rows == [[0]]
    end
  end

  defp migrate(module, function, direction) do
    Runner.run(Repo, Repo.config(), 20_261_108_170_000, module, :forward, function, direction,
      prefix: "pg_temp",
      log: false
    )
  end
end
