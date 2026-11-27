defmodule LuftServer.WorkspacesTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Condukt.MCP.Client
  alias LuftServer.Workspaces.Definition
  alias LuftServer.Workspaces.Local
  alias LuftServer.Workspaces.Preview

  setup do
    database = "luft_workspace_test_#{System.unique_integer([:positive])}"
    connection = Local.connect!(database, true)
    Process.unlink(connection)
    directory = Path.join(System.tmp_dir!(), database)
    File.mkdir_p!(directory)
    path = Path.join(directory, "workspace.json")
    File.write!(Path.join(directory, "bundle.js"), "void 0;")

    File.write!(
      Path.join(directory, "fixtures.json"),
      Jason.encode!(%{
        "accounts.customer" => [
          %{
            "id" => "00000000-0000-4000-8000-000000000001",
            "name" => "Northstar Labs",
            "status" => "active"
          },
          %{
            "id" => "00000000-0000-4000-8000-000000000002",
            "name" => "Harbor Studio",
            "status" => "lead"
          }
        ]
      })
    )

    definition = definition()
    File.write!(path, Jason.encode!(definition))
    assert {:ok, _} = Local.publish(connection, path)
    assert {:ok, 2} = Local.seed(connection, path)

    on_exit(fn ->
      if Process.alive?(connection), do: GenServer.stop(connection)
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

    %{connection: connection, database: database, path: path, definition: definition}
  end

  test "published native source and typed SQL rows survive identical republication", %{
    connection: db,
    path: path
  } do
    assert {:ok, %{"organization" => "demo", "ui_modules" => [%{"source" => "void 0;"}]}} =
             Local.workspace(db)

    assert {:ok, %{"items" => rows}} = Local.query(db, query())
    assert Enum.map(rows, & &1["name"]) == ["Northstar Labs", "Harbor Studio"]
    assert Enum.map(rows, & &1["email"]) == [nil, nil]
    assert {:ok, _} = Local.publish(db, path)
    assert {:ok, %{"items" => ^rows}} = Local.query(db, query())
    table = Definition.table("accounts.customer")

    result =
      Postgrex.query!(
        db,
        "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = $1",
        [table]
      )

    assert ["name", "text"] in result.rows
    assert ["revision", "bigint"] in result.rows

    assert_raise ArgumentError, "Refusing to seed a nonempty model", fn ->
      Local.seed(db, path)
    end
  end

  test "create, replay, edit and stale write use durable action results", %{connection: db} do
    create =
      action("create", %{"values" => %{"name" => "O'Reilly Labs", "email" => "team@example.test"}})

    assert {:ok, %{"id" => id, "revision" => 1, "status" => "lead"} = first} =
             Local.action(db, create)

    assert {:ok, ^first} = Local.action(db, create)

    assert {:error, %{code: "REVISION_CONFLICT"}} =
             Local.action(db, put_in(create, ["input", "values", "name"], "Changed"))

    update =
      action("update", %{
        "id" => id,
        "expected_revision" => 1,
        "values" => %{"status" => "active"}
      })

    assert {:ok, %{"revision" => 2, "status" => "active"}} = Local.action(db, update)

    assert {:error, %{code: "REVISION_CONFLICT"}} =
             Local.action(db, Map.put(update, "request_id", Ecto.UUID.generate()))

    assert {:ok, %{"items" => rows}} = Local.query(db, query())
    assert Enum.count(rows, &(&1["id"] == id)) == 1
    assert Enum.find(rows, &(&1["id"] == id))["revision"] == 2
    assert [[2]] = Postgrex.query!(db, "SELECT count(*) FROM workspace_audit", []).rows
  end

  test "invalid values and unknown fields leave data and audit unchanged", %{connection: db} do
    for values <- [
          %{"name" => ""},
          %{"name" => "Valid", "status" => "invented"},
          %{"name" => "Valid", "organization" => "other"}
        ] do
      assert {:error, %{code: "VALIDATION_FAILED"}} =
               Local.action(db, action("create", %{"values" => values}))
    end

    assert {:error, %{code: "INVALID_REQUEST"}} =
             Local.query(db, put_in(query(), ["input", "sql"], "DROP TABLE workspace_audit"))

    assert {:ok, %{"items" => rows}} = Local.query(db, query())
    assert length(rows) == 2
    assert [[0]] = Postgrex.query!(db, "SELECT count(*) FROM workspace_audit", []).rows
  end

  test "two connections replay a concurrent submission without duplicating its record", %{
    connection: db,
    database: database
  } do
    other = Local.connect!(database)
    request = action("create", %{"values" => %{"name" => "Concurrent studio"}})

    try do
      results =
        [db, other]
        |> Task.async_stream(&Local.action(&1, request), timeout: 10_000)
        |> Enum.map(fn {:ok, {:ok, record}} -> record end)

      assert [first, second] = results
      assert first == second
      assert first["name"] == "Concurrent studio"
      assert {:ok, %{"items" => rows}} = Local.query(other, query())
      assert Enum.count(rows, &(&1["name"] == "Concurrent studio")) == 1
      assert [[1]] = Postgrex.query!(db, "SELECT count(*) FROM workspace_audit", []).rows
    after
      GenServer.stop(other)
    end
  end

  test "schema publication upgrades existing rows and rolls back invalid evolution", %{
    connection: db,
    path: path,
    definition: original
  } do
    next =
      original
      |> put_in(["models", "accounts.customer", "version"], 2)
      |> put_in(["models", "accounts.customer", "fields", "tier"], %{
        "type" => "string",
        "required" => true,
        "default" => "standard"
      })

    File.write!(path, Jason.encode!(next))
    assert {:ok, _} = Local.publish(db, path)
    assert {:ok, %{"items" => rows}} = Local.query(db, query())
    assert Enum.map(rows, & &1["tier"]) == ["standard", "standard"]
    assert Enum.map(rows, & &1["name"]) == ["Northstar Labs", "Harbor Studio"]

    invalid =
      next
      |> put_in(["models", "accounts.customer", "version"], 3)
      |> update_in(["models", "accounts.customer", "fields"], &Map.delete(&1, "name"))

    File.write!(path, Jason.encode!(invalid))
    assert_raise ArgumentError, ~r/Only additive/, fn -> Local.publish(db, path) end
    assert {:ok, installed} = Local.workspace(db)
    assert installed["models"] == next["models"]
    assert {:ok, %{"items" => ^rows}} = Local.query(db, query())
  end

  test "preview API requires its own token and never leaks it", %{connection: db} do
    options =
      Preview.init(connection: db, token_hash: :crypto.hash(:sha256, "test-preview-token"))

    denied = conn(:get, "/workspace") |> Preview.call(options)
    assert denied.status == 401
    assert Jason.decode!(denied.resp_body)["error"]["code"] == "UNAUTHORIZED"

    allowed =
      conn(:get, "/workspace")
      |> put_req_header("authorization", "Bearer test-preview-token")
      |> Preview.call(options)

    assert allowed.status == 200
    refute allowed.resp_body =~ "test-preview-token"
    body = Jason.encode!(action("create", %{"values" => %{"name" => "From HTTP"}}))

    created =
      conn(:post, "/action", body)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-preview-token")
      |> Preview.call(options)

    assert created.status == 200
    assert Jason.decode!(created.resp_body)["name"] == "From HTTP"
  end

  test "the selected database cannot be reassigned to another organization", %{
    connection: db,
    path: path,
    definition: original
  } do
    File.write!(path, Jason.encode!(Map.put(original, "organization", "other")))

    assert_raise ArgumentError, "Database already belongs to another organization", fn ->
      Local.publish(db, path)
    end

    assert {:ok, %{"organization" => "demo"}} = Local.workspace(db)
  end

  test "a real MCP client uses cross-domain contracts without installing any UI", %{
    connection: db,
    path: path
  } do
    {accounts, support} = portable_apps(path)

    for app <- [accounts, support] do
      root = Path.join([Path.dirname(path), "apps", app["id"]])
      write_json(Path.join(root, "app.json"), Map.put(app, "ui_modules", []))
      File.rm!(Path.join(root, "bundle.js"))
    end

    assert {:ok, %{models: 2, modules: 0}} = Local.publish(db, path)
    assert {:ok, %{"ui_modules" => []}} = Local.workspace(db)

    client = workspace_mcp(db, ~w(support.conversation.create support.conversation.update))
    tools = Client.tools(client)
    create = Enum.find(tools, &(&1["name"] == "action.support.conversation.create"))
    schema = create["inputSchema"]["properties"]["input"]["properties"]["values"]
    assert schema["required"] == ["subject"]
    assert Enum.any?(schema["properties"]["customer"]["anyOf"], &(&1["format"] == "uuid"))
    refute Enum.any?(tools, &(&1["name"] == "action.accounts.customer.update"))

    assert {:ok, text} = Client.call_tool(client, "query.accounts.customer.list", %{})
    assert %{"items" => [customer | _]} = Jason.decode!(text)
    assert customer["name"] == "Northstar Labs"
    assert [[0]] = Postgrex.query!(db, "SELECT count(*) FROM workspace_audit", []).rows

    args = %{
      "request_id" => mcp_request_id(client),
      "input" => %{
        "values" => %{
          "subject" => "Build cache setup",
          "customer" => customer["id"]
        }
      }
    }

    assert {:ok, created} =
             Client.call_tool(client, "action.support.conversation.create", args)

    assert %{"id" => id, "status" => "open", "revision" => 1} = Jason.decode!(created)

    assert {:ok, text} =
             Client.call_tool(client, "query.support.conversation.list", %{})

    assert %{"items" => [conversation]} = Jason.decode!(text)

    assert {:ok, text} =
             Client.call_tool(client, "query.accounts.customer.get", %{
               "id" => conversation["customer"]
             })

    assert %{"record" => ^customer} = Jason.decode!(text)

    close = %{
      "request_id" => mcp_request_id(client),
      "input" => %{
        "id" => id,
        "expected_revision" => 1,
        "values" => %{"status" => "closed"}
      }
    }

    assert {:ok, saved} =
             Client.call_tool(client, "action.support.conversation.update", close)

    assert %{"status" => "closed", "revision" => 2} = Jason.decode!(saved)

    assert {:ok, ^saved} =
             Client.call_tool(client, "action.support.conversation.update", close)

    stale = Map.put(close, "request_id", mcp_request_id(client))

    assert {:error, _} =
             Client.call_tool(client, "action.support.conversation.update", stale)

    assert [[2]] = Postgrex.query!(db, "SELECT count(*) FROM workspace_audit", []).rows

    other = Local.connect!(Path.basename(Path.dirname(path)))

    try do
      assert {:ok, %{"items" => [%{"id" => ^id, "status" => "closed", "revision" => 2}]}} =
               Local.query(other, %{"query" => "support.conversation.list", "input" => %{}})
    after
      GenServer.stop(other)
    end
  end

  test "MCP is read-only by default and rejects direct calls to unoffered actions", %{
    connection: db
  } do
    client = workspace_mcp(db, [])
    assert Enum.all?(Client.tools(client), & &1["annotations"]["readOnlyHint"])
    request = action("create", %{"values" => %{"name" => "Must not be written"}})

    assert {:error, _} =
             Client.call_tool(
               client,
               "action.accounts.customer.create",
               Map.delete(request, "action")
             )

    assert {:error, _} = Client.call_tool(client, "workspace_request_id", %{})
    assert [[0]] = Postgrex.query!(db, "SELECT count(*) FROM workspace_audit", []).rows

    writer = workspace_mcp(db, ["accounts.customer.create"])

    for input <- [
          request |> Map.delete("action") |> Map.put("organization", "other"),
          request,
          request |> Map.delete("action") |> put_in(["input", "values", "name"], "")
        ] do
      assert {:error, _} =
               Client.call_tool(writer, "action.accounts.customer.create", input)
    end

    assert [[0]] = Postgrex.query!(db, "SELECT count(*) FROM workspace_audit", []).rows
  end

  test "MCP preserves token isolation and fails closed on malformed and browser requests", %{
    connection: db
  } do
    options = Preview.init(connection: db, token_hash: :crypto.hash(:sha256, "preview-only"))
    assert :post |> conn("/mcp", "{}") |> Preview.call(options) |> Map.fetch!(:status) == 401

    request = fn body ->
      :post
      |> conn("/mcp", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer preview-only")
    end

    for body <- [%{}, [], %{"jsonrpc" => "2.0", "id" => nil, "method" => "tools/list"}] do
      response = body |> request.() |> Preview.call(options)
      assert Jason.decode!(response.resp_body)["error"]["code"] == -32_600
      refute response.resp_body =~ "preview-only"
    end

    metadata = %{"progressToken" => "read-1"}

    for params <- [
          %{"name" => "query.accounts.customer.list"},
          %{"name" => "query.accounts.customer.list", "arguments" => %{}, "_meta" => metadata}
        ] do
      response =
        %{"jsonrpc" => "2.0", "id" => 7, "method" => "tools/call", "params" => params}
        |> request.()
        |> Preview.call(options)

      assert %{"result" => %{"isError" => false, "content" => [%{"text" => text}]}} =
               Jason.decode!(response.resp_body)

      assert %{"items" => [%{"name" => "Northstar Labs"}, %{"name" => "Harbor Studio"}]} =
               Jason.decode!(text)
    end

    listed =
      %{
        "jsonrpc" => "2.0",
        "id" => 8,
        "method" => "tools/list",
        "params" => %{"_meta" => metadata}
      }
      |> request.()
      |> Preview.call(options)

    assert is_list(Jason.decode!(listed.resp_body)["result"]["tools"])

    initialized = request.(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"})
    assert Preview.call(initialized, options).status == 202

    assert %{}
           |> request.()
           |> put_req_header("origin", "https://untrusted.test")
           |> Preview.call(options)
           |> Map.fetch!(:status) == 403

    assert %{}
           |> request.()
           |> put_req_header("mcp-protocol-version", "unsupported")
           |> Preview.call(options)
           |> Map.fetch!(:status) == 400

    assert :get
           |> conn("/mcp")
           |> put_req_header("authorization", "Bearer preview-only")
           |> Preview.call(options)
           |> Map.fetch!(:status) == 405
  end

  defp workspace_mcp(db, actions) do
    token = "test-mcp-workspace-token"

    listener =
      start_supervised!(
        Supervisor.child_spec(
          {Bandit,
           plug:
             {Preview,
              connection: db, token_hash: :crypto.hash(:sha256, token), mcp_actions: actions},
           ip: {127, 0, 0, 1},
           port: 0},
          id: make_ref()
        )
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(listener)

    server = %Condukt.MCP.Server{
      name: "workspace",
      transport:
        {:streamable_http,
         url: "http://127.0.0.1:#{port}/mcp", headers: %{"authorization" => "Bearer " <> token}}
    }

    {:ok, client} = Client.start_link(server)
    on_exit(fn -> Client.stop(client) end)
    client
  end

  defp mcp_request_id(client) do
    {:ok, text} = Client.call_tool(client, "workspace_request_id", %{})
    %{"request_id" => id} = Jason.decode!(text)
    assert {:ok, ^id} = Ecto.UUID.cast(id)
    id
  end

  defp query, do: %{"query" => "accounts.customer.list", "input" => %{}}

  test "portable apps relocate without embedding an organization and keep capabilities explicit",
       %{path: path, connection: db} do
    {accounts, support} = portable_apps(path)
    compiled = Definition.load(path)
    assert compiled["apps"]["support"]["dependencies"] == %{"accounts" => 1}

    assert hd(compiled["ui_modules"])["capabilities"]["actions"] == [
             "support.conversation.create",
             "support.conversation.update"
           ]

    refute Map.has_key?(accounts, "organization")
    refute Map.has_key?(support, "organization")
    directory = Path.dirname(path)
    File.rename!(Path.join(directory, "apps"), Path.join(directory, "relocated"))
    workspace = Jason.decode!(File.read!(path))

    write_json(
      path,
      Map.update!(
        workspace,
        "apps",
        &Enum.map(&1, fn entry -> String.replace(entry, "apps/", "relocated/") end)
      )
    )

    assert Definition.load(path) == compiled
    assert {:ok, _} = Local.publish(db, path)
    assert {:ok, ^compiled} = Local.workspace(db)
  end

  test "portable dependency versions, ownership and undeclared reads are rejected", %{path: path} do
    {accounts, support} = portable_apps(path)
    support_path = Path.join(Path.dirname(path), "apps/support/app.json")

    for dependencies <- [
          %{},
          %{"accounts" => 2},
          %{"accounts" => 1.0},
          %{"missing" => 1},
          %{"accounts" => 0}
        ] do
      write_json(support_path, Map.put(support, "dependencies", dependencies))
      assert_raise ArgumentError, fn -> Definition.load(path) end
    end

    write_json(
      support_path,
      put_in(support, ["models", "accounts.stolen"], support["models"]["support.conversation"])
    )

    assert_raise ArgumentError, ~r/belong/, fn -> Definition.load(path) end
    write_json(support_path, Map.put(support, "id", accounts["id"]))
    assert_raise ArgumentError, ~r/Duplicate/, fn -> Definition.load(path) end

    write_json(
      support_path,
      put_in(support, ["ui_modules", Access.at(0), "entry"], "../../bundle.js")
    )

    assert_raise ArgumentError, ~r/escapes/, fn -> Definition.load(path) end
    write_json(support_path, Map.put(support, "organization", "demo"))
    assert_raise ArgumentError, ~r/Unknown definition keys/, fn -> Definition.load(path) end

    read_only =
      support
      |> Map.put("dependencies", %{})
      |> update_in(["models", "support.conversation", "fields"], &Map.delete(&1, "customer"))

    write_json(support_path, read_only)
    assert_raise ArgumentError, ~r/Undeclared/, fn -> Definition.load(path) end

    for target <- ["accounts.missing", "invalid", nil] do
      write_json(
        support_path,
        put_in(support, ["models", "support.conversation", "fields", "customer", "model"], target)
      )

      assert_raise ArgumentError, fn -> Definition.load(path) end
    end

    write_json(
      support_path,
      put_in(support, ["queries", "support.conversation"], %{
        "model" => "support.conversation",
        "operation" => "get"
      })
    )

    assert_raise ArgumentError, ~r/Duplicate definition/, fn -> Definition.load(path) end
  end

  test "get and reference writes expose canonical UUIDs and enforce actual SQL foreign keys", %{
    path: path,
    connection: db
  } do
    portable_apps(path)
    assert {:ok, _} = Local.publish(db, path)
    customer = "00000000-0000-4000-8000-000000000001"
    get = %{"query" => "accounts.customer.get", "input" => %{"id" => customer}}

    assert {:ok, %{"record" => %{"id" => ^customer, "name" => "Northstar Labs"}}} =
             Local.query(db, get)

    assert {:error, %{code: "NOT_FOUND"}} =
             Local.query(db, put_in(get, ["input", "id"], Ecto.UUID.generate()))

    for input <- [%{}, %{"id" => "bad"}, %{"id" => customer, "extra" => true}, %{"id" => nil}] do
      assert {:error, %{code: "INVALID_REQUEST"}} = Local.query(db, Map.put(get, "input", input))
    end

    for value <- [Ecto.UUID.generate(), "bad", "abcdefghijklmnop", 123] do
      assert {:error, %{code: "VALIDATION_FAILED"}} =
               Local.action(
                 db,
                 support_action("create", %{
                   "values" => %{"subject" => "Help", "customer" => value}
                 })
               )
    end

    assert [[0]] = Postgrex.query!(db, "SELECT count(*) FROM workspace_requests", []).rows
    assert [[0]] = Postgrex.query!(db, "SELECT count(*) FROM workspace_audit", []).rows

    assert {:ok, %{"id" => id, "customer" => ^customer, "status" => "open"}} =
             Local.action(
               db,
               support_action("create", %{
                 "values" => %{"subject" => "Help", "customer" => String.upcase(customer)}
               })
             )

    assert {:ok, %{"customer" => nil, "revision" => 2}} =
             Local.action(
               db,
               support_action("update", %{
                 "id" => id,
                 "expected_revision" => 1,
                 "values" => %{"customer" => nil}
               })
             )

    assert {:ok, %{"customer" => ^customer}} =
             Local.action(
               db,
               support_action("update", %{
                 "id" => id,
                 "expected_revision" => 2,
                 "values" => %{"customer" => customer}
               })
             )

    table = Definition.quote_id(Definition.table("support.conversation"))

    assert {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} =
             Postgrex.query(db, "UPDATE #{table} SET customer = $1", [
               Ecto.UUID.dump!(Ecto.UUID.generate())
             ])

    customers = Definition.quote_id(Definition.table("accounts.customer"))

    assert {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} =
             Postgrex.query(db, "DELETE FROM #{customers} WHERE id = $1", [
               Ecto.UUID.dump!(customer)
             ])

    assert [["uuid"]] =
             Postgrex.query!(
               db,
               "SELECT data_type FROM information_schema.columns WHERE table_name = $1 AND column_name = 'customer'",
               [Definition.table("support.conversation")]
             ).rows
  end

  test "publication and merged seeding handle cycles and roll back failed seeds and reference migrations",
       %{path: path, connection: db} do
    {accounts, support} = portable_apps(path)
    root = Path.dirname(path)
    accounts_path = Path.join(root, "apps/accounts/app.json")
    customer = "00000000-0000-4000-8000-000000000001"
    conversation = "00000000-0000-4000-8000-000000000010"

    accounts =
      accounts
      |> Map.put("dependencies", %{"support" => 1})
      |> put_in(["models", "accounts.customer", "version"], 2)
      |> put_in(["models", "accounts.customer", "fields", "conversation"], %{
        "type" => "reference",
        "model" => "support.conversation",
        "nullable" => true
      })

    write_json(accounts_path, accounts)
    assert {:ok, _} = Local.publish(db, path)

    for model <- ~w(accounts.customer support.conversation),
        do:
          Postgrex.query!(
            db,
            "TRUNCATE #{Definition.quote_id(Definition.table(model))} CASCADE",
            []
          )

    write_json(Path.join(root, "apps/accounts/fixtures.json"), %{
      "accounts.customer" => [
        %{"id" => customer, "name" => "Cycle", "conversation" => conversation}
      ]
    })

    support_fixtures = Path.join(root, "apps/support/fixtures.json")

    write_json(support_fixtures, %{
      "support.conversation" => [
        %{"id" => conversation, "subject" => "Cycle", "customer" => Ecto.UUID.generate()}
      ]
    })

    assert_raise Postgrex.Error, fn -> Local.seed(db, path) end
    assert {:ok, %{"items" => []}} = Local.query(db, query())

    write_json(support_fixtures, %{
      "support.conversation" => [
        %{"id" => conversation, "subject" => "Cycle", "customer" => customer}
      ]
    })

    assert {:ok, 2} = Local.seed(db, path)
    assert {:ok, %{"items" => [%{"conversation" => ^conversation}]}} = Local.query(db, query())
    support_path = Path.join(root, "apps/support/app.json")

    invalid =
      support
      |> put_in(["models", "support.conversation", "version"], 2)
      |> put_in(["models", "support.conversation", "fields", "other"], %{
        "type" => "reference",
        "model" => "accounts.customer",
        "default" => Ecto.UUID.generate()
      })

    write_json(support_path, invalid)
    assert_raise Postgrex.Error, fn -> Local.publish(db, path) end
    assert {:ok, installed} = Local.workspace(db)

    assert installed["models"]["support.conversation"] ==
             support["models"]["support.conversation"]

    assert [[0]] =
             Postgrex.query!(
               db,
               "SELECT count(*) FROM information_schema.columns WHERE table_name = $1 AND column_name = 'other'",
               [Definition.table("support.conversation")]
             ).rows
  end

  defp portable_apps(path) do
    root = Path.dirname(path)

    accounts =
      definition()
      |> Map.delete("organization")
      |> Map.merge(%{"id" => "accounts", "version" => 1, "dependencies" => %{}})
      |> put_in(["queries", "accounts.customer.get"], %{
        "model" => "accounts.customer",
        "operation" => "get"
      })

    support = %{
      "format" => 1,
      "id" => "support",
      "version" => 1,
      "title" => "Support",
      "dependencies" => %{"accounts" => 1},
      "fixtures" => "fixtures.json",
      "models" => %{
        "support.conversation" => %{
          "version" => 1,
          "fields" => %{
            "subject" => %{"type" => "string", "required" => true},
            "status" => %{
              "type" => "enum",
              "values" => ["open", "closed"],
              "default" => "open",
              "nullable" => false
            },
            "customer" => %{
              "type" => "reference",
              "model" => "accounts.customer",
              "nullable" => true
            }
          }
        }
      },
      "queries" => %{
        "support.conversation.list" => %{"model" => "support.conversation", "operation" => "list"}
      },
      "actions" =>
        Map.new(
          ~w(create update),
          &{"support.conversation.#{&1}", %{"model" => "support.conversation", "operation" => &1}}
        ),
      "ui_modules" => [
        %{
          "id" => "support.conversations",
          "title" => "Support",
          "group" => "Support",
          "model" => "support.conversation",
          "entry" => "bundle.js",
          "capabilities" => %{
            "queries" => ["support.conversation.list", "accounts.customer.get"],
            "actions" => ["support.conversation.create", "support.conversation.update"]
          }
        }
      ]
    }

    for app <- [accounts, support] do
      directory = Path.join([root, "apps", app["id"]])
      File.mkdir_p!(directory)
      write_json(Path.join(directory, "app.json"), app)
      File.cp!(Path.join(root, "bundle.js"), Path.join(directory, "bundle.js"))
      write_json(Path.join(directory, "fixtures.json"), %{})
    end

    File.cp!(Path.join(root, "fixtures.json"), Path.join(root, "apps/accounts/fixtures.json"))

    write_json(path, %{
      "format" => 1,
      "organization" => "demo",
      "title" => "Company workspace",
      "apps" => ["apps/support/app.json", "apps/accounts/app.json"]
    })

    {accounts, support}
  end

  defp write_json(path, value), do: File.write!(path, Jason.encode!(value))

  defp support_action(operation, input),
    do: Map.put(action(operation, input), "action", "support.conversation.#{operation}")

  defp action(operation, input),
    do: %{
      "action" => "accounts.customer.#{operation}",
      "request_id" => Ecto.UUID.generate(),
      "input" => input
    }

  defp definition do
    %{
      "format" => 1,
      "organization" => "demo",
      "title" => "Customers",
      "fixtures" => "fixtures.json",
      "models" => %{
        "accounts.customer" => %{
          "version" => 1,
          "fields" => %{
            "name" => %{"type" => "string", "required" => true},
            "email" => %{"type" => "string", "nullable" => true},
            "status" => %{
              "type" => "enum",
              "values" => ["lead", "active", "paused"],
              "required" => true,
              "default" => "lead"
            }
          }
        }
      },
      "queries" => %{
        "accounts.customer.list" => %{"model" => "accounts.customer", "operation" => "list"}
      },
      "actions" => %{
        "accounts.customer.create" => %{"model" => "accounts.customer", "operation" => "create"},
        "accounts.customer.update" => %{"model" => "accounts.customer", "operation" => "update"}
      },
      "ui_modules" => [
        %{
          "id" => "accounts.customers",
          "title" => "Customers",
          "group" => "Account Management",
          "model" => "accounts.customer",
          "entry" => "bundle.js",
          "capabilities" => %{
            "queries" => ["accounts.customer.list"],
            "actions" => ["accounts.customer.create", "accounts.customer.update"]
          }
        }
      ]
    }
  end
end
