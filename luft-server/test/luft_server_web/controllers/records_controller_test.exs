defmodule LuftServerWeb.RecordsControllerTest do
  use LuftServerWeb.ConnCase, async: false

  import Ecto.Query

  alias LuftServer.Agents.Lease
  alias LuftServer.Config
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Threads
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Participant
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.Thread
  alias LuftServer.Workspaces.Definition
  alias LuftServer.Workspaces.Local
  alias LuftServer.Workspaces.Records
  alias LuftServerWeb.Auth

  @customer "00000000-0000-4000-8000-000000000001"
  @ticket "00000000-0000-4000-8000-000000000002"
  @reference %{"model" => "support.ticket", "id" => @ticket}
  @queries ~w(support.get support.list accounts.get)
  @actions ~w(support.update)

  setup do
    previous = Application.get_env(:luft_server, :record_workspaces)
    database = "luft_workspace_records_#{System.unique_integer([:positive])}"
    db = Local.connect!(database, true)
    Process.unlink(db)
    directory = Path.join(System.tmp_dir!(), database)
    File.mkdir_p!(directory)
    path = Path.join(directory, "workspace.json")
    File.write!(path, Jason.encode!(catalog()))
    File.write!(Path.join(directory, "bundle.js"), "void 0;")
    File.write!(Path.join(directory, "fixtures.json"), Jason.encode!(fixtures()))
    assert {:ok, _} = Local.publish(db, path)
    assert {:ok, 2} = Local.seed(db, path)

    {token, session} = session(1)
    {reader_token, reader} = session(2)
    thread = thread(session)

    Repo.insert!(%Participant{thread_id: thread.id, user_id: 2, added_by_id: 1})

    human =
      Repo.insert!(%Message{
        thread_id: thread.id,
        position: 1,
        kind: "human",
        body: "Find my ticket",
        author_id: 2,
        author_session_id: reader.id
      })

    message =
      Repo.insert!(%Message{
        thread_id: thread.id,
        position: 2,
        kind: "record",
        body: "Open record",
        record_reference: @reference
      })

    configure(database)
    stub_scope()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:luft_server, :record_workspaces, previous),
        else: Application.delete_env(:luft_server, :record_workspaces)

      if Process.alive?(db), do: GenServer.stop(db)
      config = Application.fetch_env!(:luft_server, LuftServer.Repo)

      {:ok, admin} =
        Postgrex.start_link(
          Keyword.merge(Keyword.take(config, [:hostname, :username, :password]),
            database: "postgres"
          )
        )

      Postgrex.query!(admin, "DROP DATABASE #{Definition.quote_id(database)} WITH (FORCE)", [])
      GenServer.stop(admin)
      File.rm_rf!(directory)
    end)

    %{
      db: db,
      database: database,
      path: path,
      token: token,
      reader_token: reader_token,
      session: session,
      reader: reader,
      thread: thread,
      human: human,
      message: message,
      url: "/api/accounts/team/threads/#{thread.id}/records/#{message.id}"
    }
  end

  test "authenticated open and fresh getter; filtered catalog remains structurally validated",
       ctx do
    assert %{"module" => "support.detail", "reference" => @reference, "workspace" => workspace} =
             ctx.token |> request(:get, ctx.url) |> json_response(200)

    assert [%{"id" => "support.detail", "source" => "void 0;"}] = workspace["ui_modules"]
    assert Map.has_key?(workspace["models"], "accounts.customer")
    refute Map.has_key?(workspace["queries"], "accounts.list")

    assert Definition.validate!(
             Map.update!(
               workspace,
               "ui_modules",
               &Enum.map(&1, fn ui -> Map.delete(ui, "source") end)
             )
           )

    assert %{"record" => %{"title" => "Private ticket", "revision" => 1}} =
             ctx.token |> request(:post, ctx.url <> "/query", query()) |> json_response(200)

    assert request(ctx.token, :get, ctx.url).resp_headers
           |> Enum.member?({"cache-control", "no-store"})

    assert request(nil, :get, ctx.url).status == 401

    assert %{"messages" => messages} =
             ctx.token
             |> request(:get, "/api/accounts/team/threads/#{ctx.thread.id}")
             |> json_response(200)

    assert %{"content" => "Open record", "record_reference" => @reference} = List.last(messages)
    refute Jason.encode!(List.last(messages)) =~ "Private ticket"
  end

  test "reader uses their own grants, not author's; linked customer needs independent read",
       ctx do
    configure(ctx.database, %{queries: ~w(support.get support.list), actions: []})

    assert %{"workspace" => workspace} =
             ctx.reader_token |> request(:get, ctx.url) |> json_response(200)

    assert [%{"capabilities" => %{"queries" => ~w(support.get support.list), "actions" => []}}] =
             workspace["ui_modules"]

    assert workspace["actions"] == %{}
    refute Map.has_key?(workspace["queries"], "accounts.get")

    linked = %{
      "module" => "support.detail",
      "query" => "accounts.get",
      "input" => %{"id" => @customer}
    }

    assert request(ctx.reader_token, :post, ctx.url <> "/query", linked).status == 403
    assert request(ctx.token, :post, ctx.url <> "/query", linked).status == 200
    assert request(ctx.reader_token, :post, ctx.url <> "/action", action()).status == 403
    configure(ctx.database, %{queries: [], actions: @actions})
    assert request(ctx.reader_token, :get, ctx.url).status == 403
    assert request(ctx.reader_token, :post, ctx.url <> "/query", query()).status == 403
  end

  test "default disabled, missing install, mismatched stable identity and catalog fail closed",
       ctx do
    Application.delete_env(:luft_server, :record_workspaces)
    assert request(ctx.token, :get, ctx.url).status == 403
    configure(ctx.database)
    stub_scope(organization_id: 11)
    assert request(ctx.token, :get, ctx.url).status == 403
    stub_scope()
    bindings = Application.fetch_env!(:luft_server, :record_workspaces)

    Application.put_env(
      :luft_server,
      :record_workspaces,
      put_in(bindings, [{10, 100}, :organization], "wrong")
    )

    assert request(ctx.token, :get, ctx.url).status == 403
    configure(ctx.database)
    Postgrex.query!(ctx.db, "DROP TABLE workspace_catalog", [])
    assert request(ctx.token, :get, ctx.url).status == 403
  end

  test "closed bodies reject forged module, credentials and extra nested input", ctx do
    for extra <- [
          %{"module" => "accounts.detail"},
          %{"database" => ctx.database},
          %{"actor" => 1},
          %{"grants" => @queries},
          %{"url" => "http://localhost"},
          %{"organization" => "demo"},
          %{"token" => "fake"}
        ] do
      status = if Map.has_key?(extra, "module"), do: 403, else: 422

      assert request(ctx.token, :post, ctx.url <> "/query", Map.merge(query(), extra)).status ==
               status

      assert request(ctx.token, :post, ctx.url <> "/action", Map.merge(action(), extra)).status ==
               status
    end

    assert request(ctx.token, :post, ctx.url <> "/query", put_in(query(), ["input", "extra"], 1)).status ==
             422

    assert request(
             ctx.token,
             :post,
             ctx.url <> "/action",
             put_in(action(), ["input", "extra"], 1)
           ).status == 422
  end

  test "reference is thread-bound; no cross-account or cross-thread ID opening", ctx do
    other = thread(ctx.session)

    assert request(ctx.token, :get, String.replace(ctx.url, ctx.thread.id, other.id)).status ==
             404

    assert request(ctx.token, :get, String.replace(ctx.url, "/team/", "/other/")).status == 403

    assert request(ctx.token, :get, String.replace(ctx.url, ctx.message.id, ctx.human.id)).status ==
             404

    assert request(ctx.token, :get, String.replace(ctx.url, ctx.message.id, Ecto.UUID.generate())).status ==
             404

    Repo.update!(
      Ecto.Changeset.change(ctx.message,
        record_reference: %{"model" => "support.ticket", "id" => Ecto.UUID.generate()}
      )
    )

    assert request(ctx.token, :get, ctx.url).status == 404
  end

  test "revoked membership, grants and session stop every open/query/action including retry",
       ctx do
    write = action()
    assert request(ctx.reader_token, :post, ctx.url <> "/action", write).status == 200
    stub_scope(revoked: true)

    for {method, suffix, body} <- [
          {:get, "", nil},
          {:post, "/query", query()},
          {:post, "/action", write}
        ] do
      conn = request(ctx.reader_token, method, ctx.url <> suffix, body)

      assert %{"error" => %{"code" => "FORBIDDEN", "message" => "Record unavailable"}} =
               json_response(conn, 403)
    end

    stub_scope()
    configure(ctx.database, %{queries: [], actions: []})
    assert request(ctx.reader_token, :post, ctx.url <> "/action", write).status == 403
    Repo.delete!(ctx.reader)
    assert request(ctx.reader_token, :get, ctx.url).status == 401
  end

  test "write retry returns one durable result/audit, stale revision conflicts, unauthorized replay denied",
       ctx do
    body = action()
    first = ctx.token |> request(:post, ctx.url <> "/action", body) |> json_response(200)
    assert first["revision"] == 2
    assert ctx.token |> request(:post, ctx.url <> "/action", body) |> json_response(200) == first
    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM workspace_audit", []).rows == [[1]]

    assert %{"error" => %{"code" => "REVISION_CONFLICT"}} =
             ctx.token |> request(:post, ctx.url <> "/action", action()) |> json_response(409)

    # Another principal cannot retrieve the first principal's successful replay.
    assert request(ctx.reader_token, :post, ctx.url <> "/action", body).status == 409
    configure(ctx.database, %{queries: @queries, actions: []}, 1)
    assert request(ctx.token, :post, ctx.url <> "/action", body).status == 403
    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM workspace_audit", []).rows == [[1]]
  end

  test "nested validation and not-found errors never include submitted values or other row data",
       ctx do
    invalid = put_in(action(), ["input", "values", "title"], 123)

    assert %{"error" => %{"code" => "VALIDATION_FAILED", "message" => "Record unavailable"}} =
             ctx.token |> request(:post, ctx.url <> "/action", invalid) |> json_response(422)

    invalid = put_in(action(), ["input", "extra"], "secret")

    assert %{"error" => %{"code" => "INVALID_REQUEST", "message" => "Record unavailable"}} =
             ctx.token |> request(:post, ctx.url <> "/action", invalid) |> json_response(422)

    missing = %{
      "module" => "support.detail",
      "query" => "accounts.get",
      "input" => %{"id" => Ecto.UUID.generate()}
    }

    assert %{"error" => %{"code" => "NOT_FOUND", "message" => "Record unavailable"}} =
             ctx.token |> request(:post, ctx.url <> "/query", missing) |> json_response(404)

    assert request(ctx.token, :get, ctx.url).status == 200
    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM workspace_audit", []).rows == [[0]]
  end

  test "linked write values need an independent read grant, before mutation and replay", ctx do
    write = put_in(action(), ["input", "values"], %{"customer" => @customer})
    configure(ctx.database, %{queries: ~w(support.get), actions: @actions})
    assert request(ctx.reader_token, :post, ctx.url <> "/action", write).status == 403
    configure(ctx.database)
    assert request(ctx.reader_token, :post, ctx.url <> "/action", write).status == 200
    configure(ctx.database, %{queries: ~w(support.get), actions: @actions})
    assert request(ctx.reader_token, :post, ctx.url <> "/action", write).status == 403
    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM workspace_audit", []).rows == [[1]]
  end

  test "a PostgreSQL commit fault is unavailable, not a permission denial; caller can retry same UUID",
       ctx do
    table = Definition.quote_id(Definition.table("support.ticket"))

    Postgrex.query!(
      ctx.db,
      "CREATE FUNCTION fail_commit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'private infrastructure detail' USING ERRCODE = '08006'; END $$",
      []
    )

    Postgrex.query!(
      ctx.db,
      "CREATE CONSTRAINT TRIGGER fail_commit AFTER UPDATE ON #{table} DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION fail_commit()",
      []
    )

    write = action()

    assert %{"error" => %{"code" => "UNAVAILABLE", "message" => "Record unavailable"}} =
             ctx.token |> request(:post, ctx.url <> "/action", write) |> json_response(503)

    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM workspace_audit", []).rows == [[0]]
    Postgrex.query!(ctx.db, "DROP TRIGGER fail_commit ON #{table}", [])
    assert request(ctx.token, :post, ctx.url <> "/action", write).status == 200
    assert request(ctx.token, :post, ctx.url <> "/action", write).status == 200
    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM workspace_audit", []).rows == [[1]]
  end

  test "upstream transport failures are unavailable rather than permission revocation", ctx do
    Req.Test.stub(LuftServer.Tuist, fn conn ->
      conn |> put_status(503) |> Req.Test.json(%{error: "private provider detail"})
    end)

    assert %{"error" => %{"code" => "UNAVAILABLE", "message" => "Record unavailable"}} =
             ctx.token |> request(:post, ctx.url <> "/action", action()) |> json_response(503)

    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM workspace_audit", []).rows == [[0]]
  end

  test "module revocation blocks successful replay and removed participant cannot open", ctx do
    write = action()
    assert request(ctx.token, :post, ctx.url <> "/action", write).status == 200

    catalog =
      Map.update!(
        catalog(),
        "ui_modules",
        &Enum.map(&1, fn ui -> put_in(ui, ["capabilities", "actions"], []) end)
      )

    File.write!(ctx.path, Jason.encode!(catalog))
    assert {:ok, _} = Local.publish(ctx.db, ctx.path)
    assert request(ctx.token, :post, ctx.url <> "/action", write).status == 403
    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM workspace_audit", []).rows == [[1]]

    Repo.delete_all(
      from(p in Participant, where: p.thread_id == ^ctx.thread.id and p.user_id == 2)
    )

    assert request(ctx.reader_token, :get, ctx.url).status == 403
  end

  test "module declaration is required even with user grant; getter removal fails closed", ctx do
    catalog = catalog()
    modules = put_in(hd(catalog["ui_modules"]), ["capabilities", "queries"], ["support.get"])
    catalog = Map.put(catalog, "ui_modules", [modules | tl(catalog["ui_modules"])])
    File.write!(ctx.path, Jason.encode!(catalog))
    assert {:ok, _} = Local.publish(ctx.db, ctx.path)

    assert request(ctx.token, :post, ctx.url <> "/query", %{
             "module" => "support.detail",
             "query" => "accounts.get",
             "input" => %{"id" => @customer}
           }).status == 403

    modules = put_in(modules, ["capabilities", "queries"], [])
    File.write!(ctx.path, Jason.encode!(Map.put(catalog, "ui_modules", [modules])))
    assert {:ok, _} = Local.publish(ctx.db, ctx.path)
    assert request(ctx.token, :get, ctx.url).status == 403
  end

  test "show_record is fenced, deduplicated and uses actual triggering author, with fresh discovery",
       ctx do
    Repo.delete!(ctx.message)
    Repo.update!(Ecto.Changeset.change(ctx.thread, revision: 2))
    run = Repo.insert!(%Run{thread_id: ctx.thread.id, message_id: ctx.human.id})
    Lease.want(ctx.thread.id, "thread")
    [%{epoch: epoch}] = Lease.claim("record-test", 1)
    assert {:ok, {run, _}} = Threads.claim(run.id, epoch)
    assert {:ok, {:ok, queries}} = Records.discover(run, %{})
    assert Enum.any?(queries, &(&1["query"] == "support.list"))

    assert {:ok, {:ok, %{"items" => [_]}}} =
             Records.query(run, %{
               "module" => "support.detail",
               "query" => "support.list",
               "input" => %{}
             })

    assert {:ok, _} = Threads.show_record(run, @reference)
    assert {:ok, _} = Threads.show_record(run, @reference)
    assert Repo.aggregate(from(m in Message, where: m.kind == "record"), :count) == 1
    record = Repo.one!(from(m in Message, where: m.kind == "record"))
    assert record.body == "Open record"
    assert record.record_reference == @reference
    configure(ctx.database, %{queries: [], actions: []})
    assert {:error, :forbidden} = Threads.show_record(run, @reference)
    assert {:ok, {:error, %{code: "FORBIDDEN"}}} = Records.query(run, query())
    Lease.release(ctx.thread.id, epoch)
    assert {:error, :stale_run} = Threads.show_record(run, @reference)
  end

  defp request(token, method, path, body \\ nil) do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("origin", Config.public_url())

    conn = if token, do: put_req_cookie(conn, Auth.cookie_name(), token), else: conn
    dispatch(conn, @endpoint, method, path, if(body, do: Jason.encode!(body)))
  end

  defp session(id) do
    {:ok, token, session} =
      Sessions.create(%{
        claims: %{"sub" => to_string(id)},
        tokens: %{
          "access_token" => "upstream-#{id}",
          "refresh_token" => "refresh",
          "expires_in" => 3600
        }
      })

    {token, session}
  end

  defp thread(session) do
    Repo.insert!(%Thread{
      account_id: 100,
      account_handle: "team",
      owner_id: 1,
      owner_session_id: session.id,
      request_id: Ecto.UUID.generate(),
      request_hash: "test",
      title: "Thread",
      goal: "Find ticket",
      provider: "chatgpt",
      model: "model"
    })
  end

  defp configure(database, grant \\ %{queries: @queries, actions: @actions}, user \\ 2) do
    users = %{
      1 => %{queries: @queries, actions: @actions},
      2 => %{queries: @queries, actions: @actions}
    }

    Application.put_env(:luft_server, :record_workspaces, %{
      {10, 100} => %{database: database, organization: "demo", users: Map.put(users, user, grant)}
    })
  end

  defp stub_scope(opts \\ []) do
    Req.Test.stub(LuftServer.Tuist, fn conn ->
      ["Bearer upstream-" <> subject] = get_req_header(conn, "authorization")

      if opts[:revoked] do
        conn |> put_status(403) |> Req.Test.json(%{error: "forbidden"})
      else
        Req.Test.json(conn, %{
          user_id: String.to_integer(subject),
          account_id: if(conn.request_path =~ "/other/", do: 101, else: 100),
          organization_id: opts[:organization_id] || 10,
          can_create_threads: subject == "1",
          people: Enum.map(1..2, &%{id: &1, handle: "person-#{&1}", active: true})
        })
      end
    end)
  end

  defp query,
    do: %{"module" => "support.detail", "query" => "support.get", "input" => %{"id" => @ticket}}

  defp action do
    %{
      "module" => "support.detail",
      "action" => "support.update",
      "request_id" => Ecto.UUID.generate(),
      "input" => %{"id" => @ticket, "expected_revision" => 1, "values" => %{"title" => "Updated"}}
    }
  end

  defp fixtures do
    %{
      "accounts.customer" => [%{"id" => @customer, "name" => "Secret customer"}],
      "support.ticket" => [
        %{"id" => @ticket, "title" => "Private ticket", "customer" => @customer}
      ]
    }
  end

  defp catalog do
    %{
      "format" => 1,
      "organization" => "demo",
      "title" => "Workspace",
      "fixtures" => "fixtures.json",
      "models" => %{
        "accounts.customer" => %{
          "version" => 1,
          "fields" => %{"name" => %{"type" => "string", "required" => true}}
        },
        "support.ticket" => %{
          "version" => 1,
          "fields" => %{
            "title" => %{"type" => "string", "required" => true},
            "customer" => %{"type" => "reference", "model" => "accounts.customer"}
          }
        }
      },
      "queries" => %{
        "support.get" => %{"model" => "support.ticket", "operation" => "get"},
        "support.list" => %{"model" => "support.ticket", "operation" => "list"},
        "accounts.get" => %{"model" => "accounts.customer", "operation" => "get"},
        "accounts.list" => %{"model" => "accounts.customer", "operation" => "list"}
      },
      "actions" => %{"support.update" => %{"model" => "support.ticket", "operation" => "update"}},
      "ui_modules" => [
        %{
          "id" => "support.detail",
          "model" => "support.ticket",
          "title" => "Support",
          "group" => "Apps",
          "entry" => "bundle.js",
          "capabilities" => %{"queries" => @queries, "actions" => @actions}
        },
        %{
          "id" => "accounts.detail",
          "model" => "accounts.customer",
          "title" => "Customers",
          "group" => "Apps",
          "entry" => "bundle.js",
          "capabilities" => %{"queries" => ["accounts.list"], "actions" => []}
        }
      ]
    }
  end
end
