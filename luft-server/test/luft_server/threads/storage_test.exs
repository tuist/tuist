defmodule LuftServer.Threads.StorageTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Repo
  alias LuftServer.Sessions.Session
  alias LuftServer.Threads.Approval
  alias LuftServer.Threads.EncryptedBinary
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Participant
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.Runner
  alias LuftServer.Threads.RunnerRequest
  alias LuftServer.Threads.Thread
  alias LuftServer.Threads.ToolCall

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    :ok
  end

  test "thread request keys are scoped to both upstream tenant and owner" do
    request = Ecto.UUID.generate()
    thread = thread(%{request_id: request})
    constraint(%{thread | id: nil}, "threads_owner_id_account_id_request_id_index")
    assert thread(%{request_id: request, account_id: thread.account_id + 1})
    assert thread(%{request_id: request, owner_id: thread.owner_id + 1})
  end

  test "message and approval replay keys and positions are local to a thread" do
    first = thread()
    second = thread()
    request = Ecto.UUID.generate()
    message = message(first, %{request_id: request})
    constraint(%{message | id: nil, position: 2}, "thread_messages_thread_id_request_id_index")
    constraint(%{message | id: nil, request_id: nil}, "thread_messages_thread_id_position_index")
    assert message(second, %{request_id: request})
    assert message(first, %{position: 2})
    assert message(first, %{position: 3})

    approval = approval(first, %{request_id: request})
    constraint(%{approval | id: nil}, "thread_ship_approvals_thread_id_request_id_index")
    assert approval(second, %{request_id: request})
  end

  test "participant and inbox compound keys keep users isolated by conversation and tenant" do
    first = thread()
    second = thread()
    participant = Repo.insert!(%Participant{thread_id: first.id, user_id: first.owner_id})
    constraint(participant, "thread_participants_pkey")
    assert Repo.insert!(%Participant{thread_id: second.id, user_id: first.owner_id})

    row = %{owner_id: first.owner_id, account_id: first.account_id}
    assert {1, nil} = Repo.insert_all("thread_inboxes", [row])
    assert {0, nil} = Repo.insert_all("thread_inboxes", [row], on_conflict: :nothing)
    assert {1, nil} = Repo.insert_all("thread_inboxes", [%{row | account_id: row.account_id + 1}])
    assert {1, nil} = Repo.insert_all("thread_inboxes", [%{row | owner_id: row.owner_id + 1}])
  end

  test "every pair of unfinished states is mutually exclusive; terminal runs do not block" do
    for current <- ["queued", "running", "waiting"], next <- ["queued", "running", "waiting"] do
      thread = thread()
      run = Repo.insert!(%Run{thread_id: thread.id, status: current})
      constraint(%Run{thread_id: thread.id, status: next}, "thread_runs_one_unfinished")
      Repo.update!(Ecto.Changeset.change(run, status: "succeeded"))
      assert Repo.insert!(%Run{thread_id: thread.id, status: next})
    end
  end

  test "session IDs and tool fingerprints retain their execution uniqueness" do
    first = thread()
    second = thread()
    session_id = Ecto.UUID.generate()
    run = Repo.insert!(%Run{thread_id: first.id, session_id: session_id})
    constraint(%Run{thread_id: second.id, session_id: session_id}, "thread_runs_session_id_index")
    other = Repo.insert!(%Run{thread_id: second.id})
    call = Repo.insert!(%ToolCall{run_id: run.id, fingerprint: "effect", name: "Bash"})
    constraint(%{call | id: nil}, "thread_tool_calls_run_id_fingerprint_index")
    assert Repo.insert!(%ToolCall{run_id: other.id, fingerprint: "effect", name: "Bash"})
  end

  test "all later message and run fields survive a schema roundtrip" do
    thread = thread(%{snoozed_until: now(), snoozed_until_needed: true, account_handle: nil})

    message =
      message(thread, %{
        author_id: 9_000_000_001,
        attachments: [%{"name" => "image.png", "data" => "inline"}],
        suggestions: ["Continue"],
        suggestion_icons: %{"Continue" => "arrow"},
        card_size: "medium",
        card_source: "bundle",
        decision: %{"question" => "Proceed?"},
        progress: %{"steps" => [%{"title" => "Build", "status" => "running"}]}
      })

    assert Repo.reload!(message) == message
    assert Repo.reload!(thread).snoozed_until_needed
    assert Repo.reload!(thread).account_handle == nil
    run = Repo.insert!(%Run{thread_id: thread.id, waited_seconds: 5_000_000_000})
    assert Repo.reload!(run).waited_seconds == 5_000_000_000
  end

  test "thread deletion cascades through local conversation relationships" do
    thread = thread()
    message = message(thread)
    approval = approval(thread)
    Repo.insert!(%Participant{thread_id: thread.id, user_id: 77, added_by_id: 88})

    run =
      Repo.insert!(%Run{thread_id: thread.id, message_id: message.id, approval_id: approval.id})

    call =
      Repo.insert!(%ToolCall{
        run_id: run.id,
        message_id: message.id,
        fingerprint: "one",
        name: "Bash"
      })

    Repo.delete!(thread)
    assert Repo.get(Message, message.id) == nil
    assert Repo.get(Approval, approval.id) == nil
    assert Repo.get(Run, run.id) == nil
    assert Repo.get(ToolCall, call.id) == nil
    assert Repo.get_by(Participant, thread_id: thread.id) == nil

    assert %{rows: [[false, true]]} =
             Repo.query!(
               "SELECT wanted, deleted_at IS NOT NULL FROM agent_sessions WHERE id = $1",
               [thread.id]
             )
  end

  test "deleting optional local parents nilifies references without deleting the run" do
    thread = thread()
    message = message(thread)
    approval = approval(thread)

    run =
      Repo.insert!(%Run{thread_id: thread.id, message_id: message.id, approval_id: approval.id})

    call =
      Repo.insert!(%ToolCall{
        run_id: run.id,
        message_id: message.id,
        fingerprint: "one",
        name: "Bash"
      })

    Repo.delete!(message)
    Repo.delete!(approval)
    assert %{message_id: nil, approval_id: nil} = Repo.reload!(run)
    assert %{message_id: nil} = Repo.reload!(call)
    Repo.delete!(run)
    assert Repo.get(ToolCall, call.id) == nil
  end

  test "runner queue survives roundtrip and cascades while its thread binding is nilified" do
    runner =
      Repo.insert!(%Runner{
        user_id: 9_000_000_001,
        name: "Laptop",
        platform: "macos",
        token_hash: "hash"
      })

    constraint(%{runner | id: nil}, "thread_runners_token_hash_index")
    thread = thread(%{runner_id: runner.id})

    request =
      Repo.insert!(%RunnerRequest{
        runner_id: runner.id,
        op: "read",
        payload: %{"path" => "/workspace"},
        response: %{"ok" => true},
        status: "done",
        claimed_at: now(),
        expires_at: now()
      })

    assert Repo.reload!(request) == request
    Repo.delete!(runner)
    assert Repo.get(RunnerRequest, request.id) == nil
    assert Repo.reload!(thread).runner_id == nil
  end

  test "deleting a delegation session keeps history and never rebinds to another session" do
    delegated = session()
    other = session()
    thread = thread(%{owner_session_id: delegated.id})
    message = message(thread, %{author_id: thread.owner_id, author_session_id: delegated.id})
    independent = message(thread, %{position: 2, author_session_id: other.id})

    Repo.delete!(delegated)
    assert %{owner_session_id: nil, owner_id: 9_000_000_001} = Repo.reload!(thread)
    assert %{author_session_id: nil, author_id: 9_000_000_001} = Repo.reload!(message)
    assert Repo.reload!(independent).author_session_id == other.id
  end

  test "delegation and conversation foreign keys reject nonexistent local parents" do
    missing = Ecto.UUID.generate()
    existing = thread()

    constraint(
      %{existing | id: nil, request_id: Ecto.UUID.generate(), owner_session_id: missing},
      "threads_owner_session_id_fkey"
    )

    constraint(
      %Message{thread_id: existing.id, position: 1, kind: "human", author_session_id: missing},
      "thread_messages_author_session_id_fkey"
    )

    constraint(
      %Message{thread_id: missing, position: 1, kind: "human"},
      "thread_messages_thread_id_fkey"
    )

    constraint(%Run{thread_id: existing.id, message_id: missing}, "thread_runs_message_id_fkey")
  end

  test "checkpoints and tool results are authenticated encrypted bytes at rest" do
    thread = thread()
    plaintext = <<0, 255, "private checkpoint">>
    run = Repo.insert!(%Run{thread_id: thread.id, checkpoint: plaintext})

    call =
      Repo.insert!(%ToolCall{run_id: run.id, fingerprint: "one", name: "Bash", result: plaintext})

    assert Repo.reload!(run).checkpoint == plaintext
    assert Repo.reload!(call).result == plaintext

    %{rows: [[checkpoint, result]]} =
      Repo.query!(
        """
        SELECT r.checkpoint, c.result FROM thread_runs r
        JOIN thread_tool_calls c ON c.run_id = r.id WHERE r.id = $1
        """,
        [Ecto.UUID.dump!(run.id)]
      )

    assert checkpoint != plaintext
    assert result != plaintext
    assert checkpoint != result
    refute String.contains?(checkpoint, "private checkpoint")
    assert EncryptedBinary.load(checkpoint) == {:ok, plaintext}
    assert EncryptedBinary.load(result <> "tampered") == :error
    assert EncryptedBinary.load("legacy Tuist ciphertext") == :error
    assert EncryptedBinary.load(plaintext) == :error
    assert EncryptedBinary.cast(%{}) == :error
    assert EncryptedBinary.dump(%{}) == :error

    secret = Application.fetch_env!(:luft_server, LuftServerWeb.Endpoint)[:secret_key_base]
    wrong_salt = Plug.Crypto.encrypt(secret, "not the thread salt", plaintext)
    assert EncryptedBinary.load(wrong_salt) == :error
    old = Plug.Crypto.encrypt(secret, "luft thread encrypted binary v1", plaintext, signed_at: 1)
    assert EncryptedBinary.load(old) == {:ok, plaintext}

    nil_run = Repo.insert!(%Run{thread_id: thread().id})
    assert Repo.reload!(nil_run).checkpoint == nil
  end

  test "migration retains scalar upstream IDs, local foreign keys and queue indexes" do
    %{rows: foreign_keys} =
      Repo.query!("""
      SELECT c.conrelid::regclass::text, a.attname, c.confrelid::regclass::text, c.confdeltype::text
      FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
      WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace
        AND (c.conrelid::regclass::text = 'threads' OR c.conrelid::regclass::text LIKE 'thread_%')
      """)

    assert Enum.sort(foreign_keys) ==
             Enum.sort([
               ["threads", "owner_session_id", "sessions", "n"],
               ["threads", "runner_id", "thread_runners", "n"],
               ["thread_messages", "thread_id", "threads", "c"],
               ["thread_messages", "author_session_id", "sessions", "n"],
               ["thread_participants", "thread_id", "threads", "c"],
               ["thread_ship_approvals", "thread_id", "threads", "c"],
               ["thread_runs", "thread_id", "threads", "c"],
               ["thread_runs", "message_id", "thread_messages", "n"],
               ["thread_runs", "approval_id", "thread_ship_approvals", "n"],
               ["thread_tool_calls", "run_id", "thread_runs", "c"],
               ["thread_tool_calls", "message_id", "thread_messages", "n"],
               ["thread_runner_credentials", "runner_id", "thread_runners", "c"],
               ["thread_runner_credentials", "session_id", "sessions", "c"],
               ["thread_runner_requests", "run_id", "thread_runs", "c"],
               ["thread_runner_requests", "runner_id", "thread_runners", "c"]
             ])

    %{rows: columns} =
      Repo.query!("""
      SELECT table_name, column_name, data_type FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name IN ('threads', 'thread_messages', 'thread_inboxes')
      """)

    assert ["threads", "account_id", "bigint"] in columns
    assert ["threads", "owner_id", "bigint"] in columns
    assert ["threads", "sandbox_id", "uuid"] in columns
    assert ["thread_messages", "author_id", "bigint"] in columns
    assert ["thread_inboxes", "revision", "bigint"] in columns

    %{rows: indexes} = Repo.query!("SELECT indexname FROM pg_indexes WHERE schemaname = 'public'")
    assert ["thread_runner_requests_runner_id_status_inserted_at_index"] in indexes
    assert ["thread_runner_requests_expires_at_index"] in indexes
    assert ["thread_runner_requests_run_id_index"] in indexes
    assert ["thread_runs_one_unfinished"] in indexes

    assert %{rows: [["luft_thread_session_deleted"]]} =
             Repo.query!("""
             SELECT tgname FROM pg_trigger WHERE tgrelid = 'threads'::regclass AND NOT tgisinternal
             """)
  end

  defp thread(attrs \\ %{}) do
    %Thread{
      account_id: 8_000_000_001,
      account_handle: "organization",
      owner_id: 9_000_000_001,
      request_id: Ecto.UUID.generate(),
      request_hash: "hash",
      title: "A thread",
      goal: "A goal",
      provider: "chatgpt",
      model: "test-model"
    }
    |> struct!(attrs)
    |> Repo.insert!()
  end

  defp message(thread, attrs \\ %{}) do
    %Message{thread_id: thread.id, position: 1, kind: "human", body: "Hello"}
    |> struct!(attrs)
    |> Repo.insert!()
  end

  defp approval(thread, attrs \\ %{}) do
    %Approval{
      thread_id: thread.id,
      account_id: thread.account_id,
      request_id: Ecto.UUID.generate(),
      repository: "owner/repository",
      head_sha: String.duplicate("a", 40),
      diff: "reviewed diff",
      target_branch: "main",
      mode: :branch
    }
    |> struct!(attrs)
    |> Repo.insert!()
  end

  defp session do
    Repo.insert!(%Session{
      token_hash: :crypto.strong_rand_bytes(32),
      user_sub: "9000000001",
      access_token: "encrypted upstream token",
      refresh_token: "encrypted upstream refresh",
      access_token_expires_at: now(),
      expires_at: now()
    })
  end

  defp constraint(row, index) do
    error = assert_raise Ecto.ConstraintError, fn -> Repo.insert!(row, mode: :savepoint) end
    assert error.message =~ index
  end

  defp now, do: DateTime.utc_now(:second)
end
