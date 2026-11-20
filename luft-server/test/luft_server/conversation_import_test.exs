defmodule LuftServer.ConversationImportTest do
  # The importer takes whole-table locks, so it must not overlap runtime tests.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Agents.SessionStore
  alias LuftServer.ConversationImport
  alias LuftServer.Repo
  alias LuftServer.Threads.EncryptedBinary

  @tables ~w(thread_runners threads thread_messages thread_participants thread_ship_approvals thread_runs thread_tool_calls thread_runner_requests thread_inboxes halls hall_members hall_messages agent_sessions)

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  defp snapshot do
    id = Ecto.UUID.bingenerate()
    now = DateTime.utc_now()
    tables = Map.new(@tables, &{&1, []})

    tables =
      Map.put(tables, "threads", [
        %{
          "id" => id,
          "account_id" => 100,
          "owner_id" => 7,
          "request_id" => Ecto.UUID.bingenerate(),
          "request_hash" => <<0, 255>>,
          "title" => "history",
          "goal" => "retain",
          "provider" => "anthropic",
          "model" => "test",
          "inserted_at" => now,
          "updated_at" => now
        }
      ])

    tables =
      Map.put(tables, "thread_runs", [
        %{
          "id" => Ecto.UUID.bingenerate(),
          "thread_id" => id,
          "checkpoint" => <<0, 255, 12>>,
          "status" => "waiting",
          "inserted_at" => now,
          "updated_at" => now
        }
      ])

    tables =
      Map.put(tables, "agent_sessions", [
        %{
          "id" => Ecto.UUID.generate(),
          "kind" => "thread",
          "wanted" => true,
          "epoch" => 9,
          "host" => "old",
          "inserted_at" => now,
          "updated_at" => now
        }
      ])

    %{
      "format" => "tuist-luft-conversations/1",
      "accounts" => [{100, "team"}],
      "tables" => tables,
      "objects" => %{
        "agents/thread/history/wal/00000000000000000001" =>
          :erlang.term_to_binary({:records, ["private journal"]})
      }
    }
  end

  defp transfer(snapshot, extra \\ []) do
    binary = :erlang.term_to_binary(snapshot)

    opts = [
      maintenance: true,
      accounts: %{100 => "team"},
      sha256: Base.encode16(:crypto.hash(:sha256, binary), case: :lower)
    ]

    ConversationImport.import(binary, Keyword.merge(opts, extra))
  end

  test "real PostgreSQL transfer re-encrypts checkpoints and journals and leaves no delegation or wants" do
    assert {:ok, %{objects: 1}} = transfer(snapshot())
    %{rows: [[ciphertext]]} = Repo.query!("SELECT checkpoint FROM thread_runs")
    refute ciphertext == <<0, 255, 12>>
    assert {:ok, <<0, 255, 12>>} = EncryptedBinary.load(ciphertext)
    %{rows: [[nil]]} = Repo.query!("SELECT owner_session_id FROM threads")

    %{rows: [[false, nil, nil, 9]]} =
      Repo.query!("SELECT wanted, host, lease_expires_at, epoch FROM agent_sessions")

    %{rows: [[body]]} = Repo.query!("SELECT body FROM agent_objects")
    {_, config} = SessionStore.store("thread", "history", 0)

    assert Keyword.fetch!(config, :decrypt).(body) ==
             :erlang.term_to_binary({:records, ["private journal"]})

    assert {:error, :destination_not_empty} = transfer(snapshot())
  end

  test "mapping, digest and maintenance acknowledgement are mandatory" do
    assert {:error, _} = transfer(snapshot(), accounts: %{100 => "wrong"})
    assert {:error, _} = transfer(snapshot(), sha256: "wrong")
    assert {:error, _} = transfer(snapshot(), maintenance: false)
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM threads")
  end

  test "late corruption rolls back all previously inserted rows" do
    bad = Map.put(snapshot(), "objects", %{"outside-prefix" => "invalid"})
    assert {:error, _} = transfer(bad)
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM threads")
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM thread_runs")
  end

  test "missing referenced journal segments roll back the complete import" do
    manifest = %{
      epoch: 1,
      wal_from: 1,
      header: %{messages: []},
      segments: [%{key: "agents/thread/history/segments/missing"}],
      digest: nil
    }

    data =
      Map.put(snapshot(), "objects", %{
        "agents/thread/history/manifest/00000000000000000001" => :erlang.term_to_binary(manifest)
      })

    assert {:error, _} = transfer(data)
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM threads")
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM agent_objects")
  end

  test "unique conflicts within a snapshot roll back instead of discarding history" do
    data = snapshot()

    data =
      put_in(data, ["tables", "threads"], data["tables"]["threads"] ++ data["tables"]["threads"])

    assert {:error, _} = transfer(data)
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM threads")
  end

  test "retains hall and DM UUIDs, positions, cursors, participants, approvals and runner history" do
    data = snapshot()
    thread = hd(data["tables"]["threads"])
    run = hd(data["tables"]["thread_runs"])
    times = Map.take(thread, ["inserted_at", "updated_at"])
    runner_id = Ecto.UUID.bingenerate()
    old_hash = :crypto.strong_rand_bytes(32)
    hall_id = Ecto.UUID.bingenerate()
    dm_id = Ecto.UUID.bingenerate()
    approval_id = Ecto.UUID.bingenerate()
    message_id = Ecto.UUID.bingenerate()
    row = fn attrs -> Map.merge(times, attrs) end

    additions = %{
      "thread_runners" => [
        row.(%{
          "id" => runner_id,
          "user_id" => 7,
          "name" => "old runner",
          "platform" => "macOS",
          "token_hash" => old_hash
        })
      ],
      "threads" => [Map.put(thread, "runner_id", runner_id)],
      "thread_messages" => [
        row.(%{
          "id" => message_id,
          "thread_id" => thread["id"],
          "position" => 42,
          "kind" => "user",
          "body" => "retain",
          "author_id" => 7,
          "author_session_id" => Ecto.UUID.bingenerate()
        })
      ],
      "thread_participants" => [
        row.(%{"thread_id" => thread["id"], "user_id" => 8, "added_by_id" => 7})
      ],
      "thread_ship_approvals" => [
        row.(%{
          "id" => approval_id,
          "request_id" => Ecto.UUID.bingenerate(),
          "thread_id" => thread["id"],
          "account_id" => 100,
          "repository" => "org/repo",
          "head_sha" => "head",
          "base_sha" => "base",
          "diff" => "private diff",
          "target_branch" => "main",
          "mode" => "branch",
          "approved_by_id" => 7,
          "approved_at" => times["inserted_at"],
          "status" => "approved"
        })
      ],
      "thread_tool_calls" => [
        row.(%{
          "id" => Ecto.UUID.bingenerate(),
          "run_id" => run["id"],
          "fingerprint" => <<255, 0>>,
          "name" => "tool",
          "result" => "private result",
          "checkpointed" => true
        })
      ],
      "thread_runner_requests" => [
        row.(%{
          "id" => Ecto.UUID.bingenerate(),
          "runner_id" => runner_id,
          "op" => "exec",
          "payload" => %{"command" => "do not run"},
          "status" => "pending",
          "expires_at" => times["inserted_at"]
        })
      ],
      "halls" => [
        row.(%{
          "id" => hall_id,
          "account_id" => 100,
          "kind" => "hall",
          "name" => "general",
          "request_id" => Ecto.UUID.bingenerate(),
          "last_position" => 55
        }),
        row.(%{
          "id" => dm_id,
          "account_id" => 100,
          "kind" => "direct",
          "direct_key" => "7:8",
          "request_id" => Ecto.UUID.bingenerate()
        })
      ],
      "hall_members" => [
        row.(%{"hall_id" => hall_id, "user_id" => 7, "last_read_position" => 54})
      ],
      "hall_messages" => [
        row.(%{
          "id" => Ecto.UUID.bingenerate(),
          "hall_id" => hall_id,
          "author_id" => 8,
          "request_id" => Ecto.UUID.bingenerate(),
          "position" => 55,
          "body" => "history"
        })
      ],
      "thread_inboxes" => [%{"owner_id" => 7, "account_id" => 100, "revision" => 99}]
    }

    data = Map.update!(data, "tables", &Map.merge(&1, additions))
    assert {:ok, _} = transfer(data)

    assert %{rows: [[^hall_id, "lounge", 55]]} =
             Repo.query!("SELECT id, kind, last_position FROM lounges WHERE id = $1", [hall_id])

    assert %{rows: [["direct", "7:8"]]} =
             Repo.query!("SELECT kind, direct_key FROM lounges WHERE id = $1", [dm_id])

    assert %{rows: [[54]]} = Repo.query!("SELECT last_read_position FROM lounge_members")
    assert %{rows: [[55, "history"]]} = Repo.query!("SELECT position, body FROM lounge_messages")

    assert %{rows: [[42, nil]]} =
             Repo.query!("SELECT position, author_session_id FROM thread_messages")

    assert %{rows: [[8, 7]]} = Repo.query!("SELECT user_id, added_by_id FROM thread_participants")

    assert %{rows: [[^approval_id, "approved", 7]]} =
             Repo.query!("SELECT id, status, approved_by_id FROM thread_ship_approvals")

    assert %{rows: [[^runner_id, hash, revoked]]} =
             Repo.query!("SELECT id, token_hash, revoked_at FROM thread_runners")

    refute hash == old_hash
    assert revoked
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM thread_runner_credentials")
    assert %{rows: [["cancelled"]]} = Repo.query!("SELECT status FROM thread_runner_requests")

    assert %{rows: [[<<255, 0>>, ciphertext]]} =
             Repo.query!("SELECT fingerprint, result FROM thread_tool_calls")

    assert {:ok, "private result"} = EncryptedBinary.load(ciphertext)
    assert %{rows: [[99]]} = Repo.query!("SELECT revision FROM thread_inboxes")
  end
end
