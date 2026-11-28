defmodule LuftServer.Threads.ProviderTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Agents.Lease
  alias LuftServer.FakeOpenAI
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Threads.Attachments
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.ModelFence
  alias LuftServer.Threads.Provider
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.Thread

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    :ok
  end

  test "accepted images cross the buffered provider boundary and inference validation" do
    {thread, run} = running()
    test = self()
    stub_scope()
    FakeOpenAI.connect(11)

    FakeOpenAI.stub(
      respond: fn request ->
        assert length(request["tools"]) == 64
        send(test, :validated)
        "seen"
      end
    )

    for {count, bytes, overhead} <- [{1, 900 * 1024, 10_000}, {4, 1_048_576, 1_048_576}] do
      file = %{
        "name" => "image.png",
        "mime_type" => "image/png",
        "data_base64" => Base.encode64(String.duplicate("x", bytes))
      }

      assert {:ok, files} = Attachments.validate(List.duplicate(file, count))
      images = Attachments.images([%{attachments: files}])

      parts =
        Enum.map(images, fn image ->
          %{type: "image_url", image_url: %{url: "data:#{image.media_type};base64,#{image.data}"}}
        end)

      body =
        Jason.encode!(%{
          # This incoming field is discarded when the stored model is pinned.
          # Also exercises reads above Plug's 8,000,000-byte default without
          # hitting Req.Test's own fixed 8,000,000-byte upstream JSON parser.
          model: String.duplicate("m", if(count == 4, do: 1_572_864, else: 1)),
          tools:
            for(
              n <- 1..64,
              do: %{
                type: "function",
                function: %{
                  name: "tool_#{n}",
                  description: String.duplicate("d", 512),
                  parameters: %{type: "object"}
                }
              }
            ),
          messages: [
            %{role: "system", content: String.duplicate("p", overhead)},
            %{role: "user", content: parts}
          ]
        })

      conn =
        Plug.Test.conn(:post, "/chat/completions", body)
        |> ModelFence.call(
          run_id: run.id,
          attempt: run.attempt,
          worker: self(),
          inner: {Provider, thread: thread}
        )

      assert conn.status == 200
      assert_received :validated
    end

    conn =
      Plug.Test.conn(:post, "/chat/completions", String.duplicate("x", 8_388_609))
      |> ModelFence.call(
        run_id: run.id,
        attempt: run.attempt,
        worker: self(),
        inner: {Provider, thread: thread}
      )

    assert conn.status == 413
    refute_received :validated

    file = %{
      "name" => "big.png",
      "mime_type" => "image/png",
      "data_base64" => Base.encode64(String.duplicate("x", 1_048_577))
    }

    assert {:error, :invalid_arguments} = Attachments.validate([file])

    assert {:error, :invalid_arguments} =
             Attachments.validate(List.duplicate(%{file | "data_base64" => "eA=="}, 5))
  end

  test "attachment compaction retains only the latest user turn's images" do
    image = %{type: :base64, media_type: "image/png", data: "eA=="}
    old = Condukt.Message.user("earlier", [image])
    current = Condukt.Message.user("latest", List.duplicate(image, 4))
    assert {:ok, [compacted, ^current]} = Attachments.compact([old, current], [])
    assert compacted.images == []
    assert compacted.content == old.content
  end

  test "explicit owner and author delegations use their own sessions and fresh scopes" do
    owner = session(11, "owner-token")
    author = session(12, "author-token")

    thread = %Thread{
      owner_id: 11,
      owner_session_id: owner.id,
      account_id: 21,
      account_handle: "team"
    }

    stub_scope()
    assert {:ok, %{id: owner_id}, %{user_id: 11}} = Provider.owner(thread)
    assert owner_id == owner.id

    assert {:ok, %{id: author_id}, %{user_id: 12}} =
             Provider.author(thread, %Message{author_id: 12, author_session_id: author.id})

    assert author_id == author.id
    assert_received {:scope, "Bearer owner-token"}
    assert_received {:scope, "Bearer author-token"}
  end

  test "missing or mismatched delegation never falls back to another live session" do
    owner = session(11, "owner-token")
    _other = session(11, "another-token")

    thread = %Thread{
      owner_id: 11,
      owner_session_id: owner.id,
      account_id: 21,
      account_handle: "team"
    }

    Repo.delete!(owner)

    Req.Test.stub(LuftServer.Tuist, fn _ ->
      flunk("must not contact upstream using another session")
    end)

    assert {:error, :delegation_unavailable} = Provider.owner(thread)
    assert {:error, :delegation_unavailable} = Provider.owner(%{thread | owner_session_id: nil})

    assert {:error, :delegation_unavailable} =
             Provider.author(thread, %Message{author_id: 11, author_session_id: nil})

    wrong = session(12, "author-token")

    assert {:error, :delegation_unavailable} =
             Provider.owner(%{thread | owner_session_id: wrong.id})
  end

  test "fresh scope revocation and tenant mismatch fail closed" do
    owner = session(11, "owner-token")

    thread = %Thread{
      owner_id: 11,
      owner_session_id: owner.id,
      account_id: 21,
      account_handle: "team"
    }

    Req.Test.stub(LuftServer.Tuist, fn conn -> conn |> put_status(403) |> Req.Test.json(%{}) end)
    assert {:error, :delegation_unavailable} = Provider.owner(thread)
    stub_scope(22)
    assert {:error, :delegation_unavailable} = Provider.owner(thread)
    assert {:error, :delegation_unavailable} = Provider.owner(%{thread | account_handle: nil})
  end

  test "the model catalog is the session's own subscription's" do
    owner = session(11, "owner-token")
    other = session(12, "other-token")
    FakeOpenAI.connect(11)
    FakeOpenAI.stub()

    assert :ok = Provider.validate_model(owner, "chatgpt", "test-model")
    assert {:error, :model_unavailable} = Provider.validate_model(other, "chatgpt", "test-model")
    assert {:error, :model_unavailable} = Provider.validate_model(owner, "chatgpt", "not-listed")
  end

  test "buffered transport pins stored provider/model, owner token and lease fence" do
    {thread, run} = running()
    test = self()

    stub_scope()
    FakeOpenAI.connect(11)
    # Another person's subscription is never used for this owner's thread.
    FakeOpenAI.connect(12, "other-person-token")

    FakeOpenAI.stub(
      respond: fn request ->
        # The stored model wins over the one the request named.
        assert request["model"] == "test-model"
        refute Map.has_key?(request, "api_key")
        send(test, :inferred)
        "hello"
      end
    )

    conn = completion_conn(thread, run)
    assert conn.status == 200
    assert_received :inferred
    assert_received {:thread_model_process, _}
    Repo.update!(Ecto.Changeset.change(run, attempt: run.attempt + 1))
    assert completion_conn(thread, run).status == 409
    refute_received :inferred
  end

  test "inference failures log safe categories without upstream content or credentials" do
    {thread, run} = running()
    stub_scope()
    LuftServer.FakeOpenAI.connect(11)

    LuftServer.FakeOpenAI.stub(
      respond: fn _request, conn ->
        conn
        |> put_status(400)
        |> Req.Test.json(%{
          error: %{code: "context_length_exceeded", message: "private upstream content"}
        })
      end
    )

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        conn = completion_conn(thread, run)
        assert conn.status == 400
        refute conn.resp_body =~ "private upstream content"
      end)

    assert log =~ "thread #{thread.id} inference failed: context_length (HTTP 400)"
    refute log =~ "private upstream content"
    refute log =~ LuftServer.FakeOpenAI.token()
  end

  test "model process dies with its worker rather than inferring as an orphan" do
    {_thread, run} = running()
    stub_scope()
    test = self()

    worker =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    model =
      spawn(fn ->
        receive do
          :start ->
            ModelFence.call(Plug.Test.conn(:post, "/"),
              run_id: run.id,
              attempt: run.attempt,
              worker: worker,
              inner: fn conn ->
                send(test, :model_started)

                receive do
                  :finish -> conn
                end
              end
            )
        end
      end)

    Sandbox.allow(Repo, self(), model)
    Req.Test.allow(LuftServer.Tuist, self(), model)
    ref = Process.monitor(model)
    send(model, :start)
    assert_receive :model_started
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^ref, :process, ^model, :killed}
  end

  defp completion_conn(thread, run) do
    :post
    |> Plug.Test.conn(
      "/chat/completions",
      Jason.encode!(%{
        model: "not-the-stored-model",
        api_key: "untrusted",
        messages: [%{role: "user", content: "hello"}]
      })
    )
    |> ModelFence.call(
      run_id: run.id,
      attempt: run.attempt,
      worker: self(),
      inner: {Provider, thread: thread}
    )
  end

  defp stub_scope(account \\ 21) do
    test = self()
    Req.Test.stub(LuftServer.Tuist, &scope(&1, test, account))
  end

  defp scope(conn, test, account) do
    assert conn.request_path == "/api/accounts/team/luft-context"
    [token] = get_req_header(conn, "authorization")
    send(test, {:scope, token})
    id = if token == "Bearer owner-token", do: 11, else: 12

    Req.Test.json(conn, %{
      user_id: id,
      account_id: account,
      organization_id: account,
      can_create_threads: true,
      people: [
        %{id: 11, handle: "owner", active: true},
        %{id: 12, handle: "author", active: true}
      ]
    })
  end

  defp running do
    owner = session(11, "owner-token")

    thread =
      Repo.insert!(%Thread{
        owner_id: 11,
        owner_session_id: owner.id,
        account_id: 21,
        account_handle: "team",
        request_id: Ecto.UUID.generate(),
        request_hash: <<1>>,
        title: "Test",
        goal: "hello",
        provider: "chatgpt",
        model: "test-model"
      })

    message =
      Repo.insert!(%Message{
        thread_id: thread.id,
        position: 1,
        kind: "human",
        author_id: 11,
        author_session_id: owner.id,
        body: "hello"
      })

    Lease.want(thread.id, "thread")
    [%{epoch: epoch}] = Lease.claim(Ecto.UUID.generate(), 1)

    run =
      Repo.insert!(%Run{
        thread_id: thread.id,
        message_id: message.id,
        status: "running",
        attempt: epoch
      })

    {thread, run}
  end

  defp session(id, token) do
    {:ok, _, session} =
      Sessions.create(%{
        claims: %{"sub" => to_string(id)},
        tokens: %{"access_token" => token, "refresh_token" => "refresh", "expires_in" => 3600}
      })

    session
  end
end
