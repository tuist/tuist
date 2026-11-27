defmodule LuftServerWeb.CollectionsControllerTest do
  use LuftServerWeb.ConnCase, async: false

  alias LuftServer.Agents.Lease
  alias LuftServer.Config
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Threads
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Participant
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.Thread
  alias LuftServer.Workspaces.Behaviors
  alias LuftServer.Workspaces.Authoring
  alias LuftServer.Workspaces.Definition
  alias LuftServer.Workspaces.Local
  alias LuftServer.Workspaces.Records
  alias LuftServerWeb.Auth

  @base "/api/accounts/team"

  setup do
    previous = Application.get_env(:luft_server, :behavior_workspaces)
    previous_git = Application.get_env(:luft_server, :git_endpoint)
    start_supervised!(LuftServer.FakeGit)

    start_supervised!(
      {GRPC.Server.Supervisor,
       endpoint: LuftServer.FakeGit.Endpoint,
       port: 0,
       start_server: true,
       adapter_opts: [ip: {127, 0, 0, 1}]}
    )

    port = :ranch.get_port(inspect(LuftServer.FakeGit.Endpoint))
    Application.put_env(:luft_server, :git_endpoint, "127.0.0.1:#{port}")
    database = "luft_workspace_behaviors_#{System.unique_integer([:positive])}"
    db = Local.connect!(database, true)
    Process.unlink(db)
    definition = "priv/behaviors/support.json" |> File.read!() |> Jason.decode!()
    collections = Map.keys(definition["resources"])
    methods = Map.keys(definition["methods"])

    grants = %{
      "roles" => ~w(author approve merge activate),
      "owners" => ~w(accounts support),
      "collections" => collections,
      "methods" => methods
    }

    assert {:ok, :ok} = Behaviors.initialize(db, 10, 100, %{1 => grants, 2 => grants})
    Application.put_env(:luft_server, :behavior_workspaces, %{{10, 100} => database})
    {token, session} = session(1)
    {reviewer, reviewer_session} = session(2)
    stub_scope()

    on_exit(fn ->
      if previous_git,
        do: Application.put_env(:luft_server, :git_endpoint, previous_git),
        else: Application.delete_env(:luft_server, :git_endpoint)

      if previous,
        do: Application.put_env(:luft_server, :behavior_workspaces, previous),
        else: Application.delete_env(:luft_server, :behavior_workspaces)

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
    end)

    %{
      db: db,
      token: token,
      reviewer: reviewer,
      session: session,
      reviewer_session: reviewer_session,
      definition: definition
    }
  end

  test "reviews pin commits, not mutable branches, and rejected scopes cannot allocate repositories",
       ctx do
    stub_scope(organization: 11)

    assert call(ctx.token, :post, "/releases", %{
             "definition" => ctx.definition,
             "baseline" => nil
           }).status == 403

    assert Repo.aggregate(LuftServer.Git.OpsRepository, :count) == 0
    # A configured binding alone cannot authorize a different organization.
    bindings = Application.fetch_env!(:luft_server, :behavior_workspaces)

    Application.put_env(
      :luft_server,
      :behavior_workspaces,
      Map.put(bindings, {11, 100}, Map.fetch!(bindings, {10, 100}))
    )

    assert call(ctx.token, :get, "/releases").status == 403
    assert Repo.aggregate(LuftServer.Git.OpsRepository, :count) == 0
    stub_scope()

    proposal =
      call(ctx.token, :post, "/releases", %{"definition" => ctx.definition, "baseline" => nil})
      |> json_response(200)

    %{"hash" => hash, "repository_key" => key, "commit_id" => commit} = proposal
    assert {:ok, ^key} = Ecto.UUID.cast(key)
    assert String.length(commit) == 40
    assert Repo.get_by!(LuftServer.Git.OpsRepository, organization_id: 10).id == key
    assert call(ctx.token, :post, "/releases/#{hash}/approve", %{}).status == 403
    assert call(ctx.reviewer, :post, "/releases/#{hash}/approve", %{}).status == 200

    # The release branch can move, but approval and repeat proposals still use
    # the exact stored commit, never whatever the branch points to now.
    Agent.update(LuftServer.FakeGit, fn state ->
      update_in(state, [key, :refs], fn refs ->
        Map.new(refs, fn {name, _} -> {name, String.duplicate("a", 40)} end)
      end)
    end)

    assert call(ctx.token, :post, "/releases", %{
             "definition" => ctx.definition,
             "baseline" => nil
           })
           |> json_response(200) == proposal

    detail = call(ctx.reviewer, :get, "/releases/#{hash}") |> json_response(200)
    assert detail["commit_id"] == commit and detail["reviewed_commit_id"] == commit
    assert call(ctx.token, :post, "/releases/#{hash}/merge", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{hash}/activate", %{}).status == 200
    assert Repo.aggregate(LuftServer.Git.OpsRepository, :count) == 1
  end

  test "different organizations get different repositories and cannot review each other's commits",
       ctx do
    first =
      call(ctx.token, :post, "/releases", %{"definition" => ctx.definition, "baseline" => nil})
      |> json_response(200)

    database = "luft_workspace_git_#{System.unique_integer([:positive])}"
    db = Local.connect!(database, true)
    Process.unlink(db)

    [[grants]] =
      Postgrex.query!(ctx.db, "SELECT grants FROM behavior_principals WHERE user_id=1", []).rows

    try do
      assert {:ok, :ok} = Behaviors.initialize(db, 11, 100, %{1 => grants, 2 => grants})
      bindings = Application.fetch_env!(:luft_server, :behavior_workspaces)

      Application.put_env(
        :luft_server,
        :behavior_workspaces,
        Map.put(bindings, {11, 100}, database)
      )

      stub_scope(organization: 11)

      other =
        call(ctx.token, :post, "/releases", %{"definition" => ctx.definition, "baseline" => nil})
        |> json_response(200)

      refute other["repository_key"] == first["repository_key"]
      refute other["hash"] == first["hash"]
      assert Repo.aggregate(LuftServer.Git.OpsRepository, :count) == 2
      assert call(ctx.reviewer, :get, "/releases/#{first["hash"]}").status == 404
      assert call(ctx.reviewer, :post, "/releases/#{first["hash"]}/approve", %{}).status == 404
      # Even a misbound pin in the workspace cannot cross the organization's mapping.
      Postgrex.query!(db, "UPDATE behavior_releases SET repository_key=$1,commit_id=$2", [
        first["repository_key"],
        first["commit_id"]
      ])

      assert call(ctx.reviewer, :post, "/releases/#{other["hash"]}/approve", %{}).status == 409
    after
      GenServer.stop(db)
      Postgrex.query!(ctx.db, "DROP DATABASE #{Definition.quote_id(database)} WITH (FORCE)", [])
    end
  end

  test "accounts share an organization's ops repository, not its release authority", ctx do
    first =
      call(ctx.token, :post, "/releases", %{"definition" => ctx.definition, "baseline" => nil})
      |> json_response(200)

    assert call(ctx.reviewer, :post, "/releases/#{first["hash"]}/approve", %{}).status == 200
    Agent.update(LuftServer.FakeGit, &Map.put(&1, :lose_merge_response, true))
    assert call(ctx.token, :post, "/releases/#{first["hash"]}/merge", %{}).status == 503
    database = "luft_workspace_git_#{System.unique_integer([:positive])}"
    db = Local.connect!(database, true)
    Process.unlink(db)

    [[grants]] =
      Postgrex.query!(ctx.db, "SELECT grants FROM behavior_principals WHERE user_id=1", []).rows

    try do
      assert {:ok, :ok} = Behaviors.initialize(db, 10, 101, %{1 => grants, 2 => grants})
      bindings = Application.fetch_env!(:luft_server, :behavior_workspaces)

      Application.put_env(
        :luft_server,
        :behavior_workspaces,
        Map.put(bindings, {10, 101}, database)
      )

      stub_scope(account: 101)

      second =
        call(ctx.token, :post, "/releases", %{"definition" => ctx.definition, "baseline" => nil})
        |> json_response(200)

      assert second["repository_key"] == first["repository_key"]
      refute second["commit_id"] == first["commit_id"]
      assert Repo.aggregate(LuftServer.Git.OpsRepository, :count) == 1
      assert call(ctx.reviewer, :post, "/releases/#{first["hash"]}/approve", %{}).status == 404
      assert call(ctx.reviewer, :post, "/releases/#{second["hash"]}/approve", %{}).status == 200
      assert call(ctx.token, :post, "/releases/#{second["hash"]}/merge", %{}).status == 200
      assert call(ctx.token, :post, "/releases/#{second["hash"]}/activate", %{}).status == 200

      tree =
        Agent.get(LuftServer.FakeGit, fn state ->
          state[second["repository_key"]].commits[second["commit_id"]].tree
        end)

      assert Enum.sort(Map.keys(tree)) == [
               "accounts/100/release.json",
               "accounts/101/release.json"
             ]

      stub_scope()
      assert call(ctx.token, :post, "/releases/#{first["hash"]}/merge", %{}).status == 200
      assert call(ctx.token, :post, "/releases/#{first["hash"]}/activate", %{}).status == 200
    after
      GenServer.stop(db)
      Postgrex.query!(ctx.db, "DROP DATABASE #{Definition.quote_id(database)} WITH (FORCE)", [])
    end
  end

  test "merge is separately authorized, leaves runtime unchanged, and activation is explicit",
       ctx do
    hash = propose(ctx, ctx.definition, nil)
    assert call(ctx.token, :post, "/releases/#{hash}/merge", %{}).status == 403
    assert call(ctx.reviewer, :post, "/releases/#{hash}/approve", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{hash}/activate", %{}).status == 409

    Postgrex.query!(
      ctx.db,
      "UPDATE behavior_principals SET grants=jsonb_set(grants,'{roles}','[\"author\",\"activate\"]') WHERE user_id=1",
      []
    )

    assert call(ctx.token, :post, "/releases/#{hash}/merge", %{}).status == 403

    Postgrex.query!(
      ctx.db,
      "UPDATE behavior_principals SET grants=jsonb_set(grants,'{roles}','[\"author\",\"merge\",\"activate\"]') WHERE user_id=1",
      []
    )

    Postgrex.query!(
      ctx.db,
      "UPDATE behavior_principals SET grants=jsonb_set(grants,'{roles}','[]') WHERE user_id=2",
      []
    )

    assert call(ctx.token, :post, "/releases/#{hash}/merge", %{}).status == 403

    Postgrex.query!(
      ctx.db,
      "UPDATE behavior_principals SET grants=jsonb_set(grants,'{roles}','[\"approve\"]') WHERE user_id=2",
      []
    )

    assert call(ctx.token, :post, "/releases/#{hash}/merge", %{}) |> json_response(200) == %{
             "hash" => hash,
             "state" => "merged"
           }

    detail = call(ctx.token, :get, "/releases/#{hash}") |> json_response(200)
    assert detail["state"] == "merged" and detail["can_activate"]
    refute detail["can_merge"]

    assert call(ctx.token, :get, "/collections") |> json_response(200) |> Map.fetch!("release") ==
             nil

    assert Agent.get(LuftServer.FakeGit, & &1[detail["repository_key"]].refs["refs/heads/main"]) ==
             detail["commit_id"]

    assert call(ctx.token, :post, "/releases/#{hash}/merge", %{}).status == 200

    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM behavior_events WHERE kind='merged'", []).rows ==
             [[1]]

    assert call(ctx.token, :post, "/releases", %{
             "definition" => ctx.definition,
             "baseline" => nil
           }).status == 409

    assert call(ctx.token, :post, "/releases/#{hash}/activate", %{}).status == 200

    assert call(ctx.token, :get, "/collections") |> json_response(200) |> Map.fetch!("release") ==
             hash
  end

  test "a moved main rejects the CAS and requires a new proposal and review", ctx do
    hash = propose(ctx, ctx.definition, nil)
    other = propose(ctx, Map.put(ctx.definition, "title", "Another proposal"), nil)
    assert call(ctx.reviewer, :post, "/releases/#{hash}/approve", %{}).status == 200
    detail = call(ctx.token, :get, "/releases/#{other}") |> json_response(200)

    Agent.update(
      LuftServer.FakeGit,
      &Map.put(&1, :on_fork, fn ->
        Agent.update(LuftServer.FakeGit, fn state ->
          put_in(state, [detail["repository_key"], :refs, "refs/heads/main"], detail["commit_id"])
        end)
      end)
    )

    assert call(ctx.token, :post, "/releases/#{hash}/merge", %{}).status == 409

    assert call(ctx.token, :get, "/releases/#{hash}") |> json_response(200) |> Map.fetch!("state") ==
             "merge_conflict"

    assert Agent.get(LuftServer.FakeGit, & &1[detail["repository_key"]].refs["refs/heads/main"]) ==
             detail["commit_id"]

    fresh = propose(ctx, ctx.definition, nil)
    refute fresh == hash
    assert call(ctx.token, :post, "/releases/#{fresh}/merge", %{}).status == 403
    assert call(ctx.reviewer, :post, "/releases/#{fresh}/approve", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{fresh}/merge", %{}).status == 200
  end

  test "a lost merge response stays pending until exact-commit reconciliation", ctx do
    hash = propose(ctx, ctx.definition, nil)
    assert call(ctx.reviewer, :post, "/releases/#{hash}/approve", %{}).status == 200
    Agent.update(LuftServer.FakeGit, &Map.put(&1, :lose_merge_response, true))
    assert call(ctx.token, :post, "/releases/#{hash}/merge", %{}).status == 503
    detail = call(ctx.token, :get, "/releases/#{hash}") |> json_response(200)
    assert detail["state"] == "merging" and detail["can_merge"]
    refute detail["can_activate"]

    assert Agent.get(LuftServer.FakeGit, & &1[detail["repository_key"]].refs["refs/heads/main"]) ==
             detail["commit_id"]

    assert call(ctx.reviewer, :post, "/releases/#{hash}/approve", %{}).status == 409
    assert call(ctx.token, :post, "/releases/#{hash}/activate", %{}).status == 409

    assert call(ctx.token, :post, "/releases", %{
             "definition" => ctx.definition,
             "baseline" => nil
           }).status == 409

    assert call(ctx.token, :post, "/releases/#{hash}/merge", %{}).status == 200

    assert Postgrex.query!(
             ctx.db,
             "SELECT kind FROM behavior_events WHERE kind IN ('merge_requested','merged') ORDER BY id",
             []
           ).rows == [["merge_requested"], ["merged"]]

    assert call(ctx.token, :post, "/releases/#{hash}/activate", %{}).status == 200
  end

  test "legacy hash-only approvals never transfer to a Git-backed proposal", ctx do
    runtime = LuftServer.Workspaces.BehaviorJavaScript.identity()

    legacy =
      LuftServer.Workspaces.BehaviorDefinition.hash(%{
        "definition" => ctx.definition,
        "baseline" => nil,
        "runtime" => runtime,
        "organization" => 10,
        "account" => 100
      })

    Postgrex.query!(
      ctx.db,
      "INSERT INTO behavior_releases(hash,definition,runtime,baseline,author,reviewer) VALUES($1,$2,$3,NULL,1,2)",
      [legacy, ctx.definition, runtime]
    )

    assert call(ctx.reviewer, :post, "/releases/#{legacy}/approve", %{}).status == 409
    assert call(ctx.token, :post, "/releases/#{legacy}/activate", %{}).status == 409
    fresh = propose(ctx, ctx.definition, nil)
    refute fresh == legacy
    detail = call(ctx.reviewer, :get, "/releases/#{fresh}") |> json_response(200)
    assert is_binary(detail["commit_id"])
    assert detail["reviewer"] == nil and detail["reviewed_commit_id"] == nil
    assert call(ctx.token, :post, "/releases/#{fresh}/activate", %{}).status == 403
    assert call(ctx.reviewer, :post, "/releases/#{fresh}/approve", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{fresh}/merge", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{fresh}/activate", %{}).status == 200
  end

  test "reviewer permission revoked during the Git read prevents approval", ctx do
    hash = propose(ctx, ctx.definition, nil)
    db = ctx.db

    Agent.update(
      LuftServer.FakeGit,
      &Map.put(&1, :on_object, fn ->
        Postgrex.query!(db, "DELETE FROM behavior_principals WHERE user_id=2", [])
      end)
    )

    assert call(ctx.reviewer, :post, "/releases/#{hash}/approve", %{}).status == 403

    [[nil, nil]] =
      Postgrex.query!(
        ctx.db,
        "SELECT reviewer,reviewed_commit_id FROM behavior_releases WHERE hash=$1",
        [hash]
      ).rows
  end

  test "activation rejects a substituted commit and unavailable Git never grants approval", ctx do
    hash = propose(ctx, ctx.definition, nil)
    detail = call(ctx.reviewer, :get, "/releases/#{hash}") |> json_response(200)
    Application.delete_env(:luft_server, :git_endpoint)
    assert call(ctx.reviewer, :post, "/releases/#{hash}/approve", %{}).status == 503

    assert call(ctx.reviewer, :get, "/releases/#{hash}")
           |> json_response(200)
           |> Map.fetch!("reviewed_commit_id") == nil

    port = :ranch.get_port(inspect(LuftServer.FakeGit.Endpoint))
    Application.put_env(:luft_server, :git_endpoint, "127.0.0.1:#{port}")
    assert call(ctx.reviewer, :post, "/releases/#{hash}/approve", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{hash}/merge", %{}).status == 200

    Postgrex.query!(ctx.db, "UPDATE behavior_releases SET commit_id=$2 WHERE hash=$1", [
      hash,
      String.duplicate("b", 40)
    ])

    assert call(ctx.token, :post, "/releases/#{hash}/activate", %{}).status == 409

    assert call(ctx.token, :get, "/collections") |> json_response(200) |> Map.fetch!("release") ==
             nil

    Postgrex.query!(ctx.db, "UPDATE behavior_releases SET commit_id=$2 WHERE hash=$1", [
      hash,
      detail["commit_id"]
    ])

    # The remote snapshot must also agree with the frozen definition.
    Agent.update(LuftServer.FakeGit, fn state ->
      update_in(state, [detail["repository_key"], :blobs], fn blobs ->
        Map.new(blobs, fn {id, _} -> {id, "{}"} end)
      end)
    end)

    assert call(ctx.token, :post, "/releases/#{hash}/activate", %{}).status == 409
  end

  test "authoring validation is bounded and compile-only; exact proposals are immutable and idempotent",
       ctx do
    inspection = call(ctx.token, :get, "/behaviors") |> json_response(200)
    assert inspection["active"] == nil
    assert inspection["definition"] == nil
    assert inspection["schema"]["properties"]["methods"]["maxProperties"] == 20

    # This compiles but would mutate and loop forever if validation executed it.
    definition =
      put_in(
        ctx.definition,
        ["methods", "support.create", "source"],
        "await Javex.Host.call('resources.create', {values: {subject: 'Do not run', status: 'open', customer: null}}); while (true) {} /*" <>
          String.duplicate("x", 5_000) <> "*/"
      )

    body = %{"definition" => definition, "baseline" => nil}
    validation = call(ctx.token, :post, "/releases/validate", body) |> json_response(200)
    assert validation["valid"] and validation["compatible"]
    assert validation["diagnostics"] == []
    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM behavior_releases", []).rows == [[0]]
    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM behavior_events", []).rows == [[0]]

    assert call(ctx.token, :get, "/collections") |> json_response(200) == %{
             "release" => nil,
             "collections" => []
           }

    for bad <- [
          put_in(body, ["definition", "methods", "support.create", "source"], "return !!!;"),
          put_in(
            body,
            ["definition", "methods", "support.create", "source"],
            String.duplicate("x", 32_769)
          ),
          put_in(body, ["definition", "resources", "support.conversation", "version"], 0)
        ] do
      assert %{"valid" => false, "diagnostics" => [_ | _]} =
               call(ctx.token, :post, "/releases/validate", bad) |> json_response(200)

      assert call(ctx.token, :post, "/releases", bad).status == 422
    end

    first = call(ctx.token, :post, "/releases", body) |> json_response(200)
    assert call(ctx.token, :post, "/releases", body) |> json_response(200) == first
    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM behavior_releases", []).rows == [[1]]
    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM behavior_events", []).rows == [[1]]
    hash = first["hash"]
    detail = call(ctx.token, :get, "/releases/#{hash}") |> json_response(200)
    assert detail["definition"] == definition
    refute detail["can_approve"]
    refute detail["can_activate"]
    assert detail["state"] == "proposed"

    assert call(ctx.reviewer, :get, "/releases/#{hash}")
           |> json_response(200)
           |> Map.fetch!("can_approve")

    no_store = call(ctx.token, :get, "/releases")
    assert get_resp_header(no_store, "cache-control") == ["no-store"]
    assert %{"active" => nil, "releases" => [summary]} = json_response(no_store, 200)
    refute Map.has_key?(summary, "definition")
    assert call(nil, :get, "/releases/#{hash}").status == 401
    assert call(ctx.token, :get, "/releases/#{String.duplicate("a", 64)}").status == 404
  end

  test "review reports exact baseline changes and current compatibility, reviewer and activation authority",
       ctx do
    baseline = install(ctx)

    additive =
      ctx.definition
      |> put_in(["resources", "support.conversation", "version"], 2)
      |> put_in(["resources", "support.conversation", "fields", "resolution"], %{
        "type" => "string",
        "nullable" => true
      })

    hash = propose(ctx, additive, baseline)
    detail = call(ctx.reviewer, :get, "/releases/#{hash}") |> json_response(200)
    assert detail["baseline_definition"] == ctx.definition
    assert detail["definition"] == additive

    assert detail["changes"] == [
             %{
               "path" => "/resources/support.conversation/fields/resolution",
               "kind" => "added",
               "before" => nil,
               "after" => %{"type" => "string", "nullable" => true}
             },
             %{
               "path" => "/resources/support.conversation/version",
               "kind" => "changed",
               "before" => 1,
               "after" => 2
             }
           ]

    assert detail["compatible"] and detail["can_approve"]
    refute detail["can_activate"]
    assert call(ctx.reviewer, :post, "/releases/#{hash}/approve", %{}).status == 200

    assert %{"state" => "approved", "can_activate" => false, "can_merge" => true, "reviewer" => 2} =
             call(ctx.token, :get, "/releases/#{hash}") |> json_response(200)

    Postgrex.query!(
      ctx.db,
      "UPDATE behavior_principals SET grants=jsonb_set(grants,'{owners}','[\"support\"]') WHERE user_id=2",
      []
    )

    assert %{"state" => "proposed", "can_activate" => false, "can_approve" => false} =
             call(ctx.reviewer, :get, "/releases/#{hash}") |> json_response(200)

    assert call(ctx.token, :post, "/releases/#{hash}/activate", %{}).status == 403

    Postgrex.query!(
      ctx.db,
      "UPDATE behavior_principals SET grants=jsonb_set(grants,'{owners}','[\"accounts\",\"support\"]') WHERE user_id=2",
      []
    )

    breaking = put_in(additive, ["methods", "support.close", "source"], "return {}; ")
    other = propose(ctx, breaking, baseline)

    assert %{"compatible" => false, "can_activate" => false} =
             call(ctx.token, :get, "/releases/#{other}") |> json_response(200)

    assert %{"valid" => true, "compatible" => false, "blockers" => [_]} =
             call(ctx.token, :post, "/releases/validate", %{
               "definition" => breaking,
               "baseline" => baseline
             })
             |> json_response(200)

    assert call(ctx.token, :post, "/releases/#{hash}/merge", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{hash}/activate", %{}).status == 200

    assert %{"state" => "active", "can_activate" => false, "can_approve" => false} =
             call(ctx.token, :get, "/releases/#{hash}") |> json_response(200)

    assert %{"state" => "superseded"} =
             call(ctx.token, :get, "/releases/#{baseline}") |> json_response(200)

    assert %{"state" => "stale", "can_activate" => false, "can_approve" => false} =
             call(ctx.reviewer, :get, "/releases/#{other}") |> json_response(200)

    assert call(ctx.token, :post, "/releases/#{other}/activate", %{}).status == 409
    stub_scope(organization: 11)
    assert call(ctx.token, :get, "/releases/#{hash}").status == 403
  end

  test "agent tools author and promote as the triggering participant, never as the subscription owner",
       ctx do
    thread =
      Repo.insert!(%Thread{
        account_id: 100,
        account_handle: "team",
        owner_id: 1,
        owner_session_id: ctx.session.id,
        request_id: Ecto.UUID.generate(),
        request_hash: "test",
        title: "Author a behavior",
        goal: "Create reviewed support",
        provider: "chatgpt",
        model: "model",
        revision: 2
      })

    Repo.insert!(%Participant{thread_id: thread.id, user_id: 2, added_by_id: 1})

    human =
      Repo.insert!(%Message{
        thread_id: thread.id,
        position: 1,
        kind: "human",
        body: "Propose support",
        author_id: 2,
        author_session_id: ctx.reviewer_session.id
      })

    run = Repo.insert!(%Run{thread_id: thread.id, message_id: human.id})
    Lease.want(thread.id, "thread")
    [%{epoch: epoch}] = Lease.claim("authoring-test", 1)
    assert {:ok, {run, _}} = Threads.claim(run.id, epoch)
    tools = Authoring.tools(run)
    refute Enum.any?(tools, &String.contains?(&1.name, "approve"))
    invoke = fn name, args -> Enum.find(tools, &(&1.name == name)).call.(args, %{}) end
    assert {:ok, %{"active" => nil}} = invoke.("inspect_behaviors", %{})
    body = %{"definition" => ctx.definition, "baseline" => nil}
    assert {:ok, %{"valid" => true}} = invoke.("validate_behavior_release", body)
    assert {:ok, %{"hash" => hash}} = invoke.("propose_behavior_release", body)

    assert {:ok, %{"author" => 2, "can_approve" => false}} =
             invoke.("inspect_behavior_releases", %{"hash" => hash})

    assert {:error, :forbidden} = invoke.("promote_behavior_release", %{"hash" => hash})
    assert call(ctx.token, :post, "/releases/#{hash}/approve", %{}).status == 200
    assert {:ok, %{"state" => "merged"}} = invoke.("merge_behavior_release", %{"hash" => hash})
    assert {:ok, %{"state" => "active"}} = invoke.("promote_behavior_release", %{"hash" => hash})

    Postgrex.query!(
      ctx.db,
      "UPDATE behavior_principals SET grants=jsonb_set(grants,'{roles}','[]') WHERE user_id=2",
      []
    )

    assert {:error, :forbidden} = invoke.("inspect_behaviors", %{})
    assert {:error, :forbidden} = invoke.("inspect_behavior_releases", %{})

    assert {:error, :forbidden} =
             invoke.("propose_behavior_release", %{
               "definition" => ctx.definition,
               "baseline" => hash
             })

    assert call(ctx.token, :get, "/behaviors").status == 200
    Lease.release(thread.id, epoch)
    assert {:error, :stale_run} = invoke.("inspect_behaviors", %{})
  end

  test "reviewed activation, generic JS writes, history, search and durable replay", ctx do
    hash = install(ctx)
    customer = invoke(ctx.token, "accounts.create", %{"name" => "Harbor Studio"})
    input = %{"subject" => "Cache upload is slow", "customer" => customer["id"]}
    request_id = Ecto.UUID.generate()
    record = invoke(ctx.token, "support.create", input, request_id)
    assert record["revision"] == 1
    assert record["status"] == "open"
    assert invoke(ctx.token, "support.create", input, request_id) == record

    assert %{"items" => [^record], "has_more" => false} =
             call(ctx.token, :post, "/collections/support.conversation/query", %{
               "search" => "UPLOAD",
               "filters" => %{"status" => "open"},
               "limit" => 1
             })
             |> json_response(200)

    assert %{"items" => []} =
             call(ctx.token, :post, "/collections/support.conversation/query", %{
               "search" => "absent"
             })
             |> json_response(200)

    closed = invoke(ctx.token, "support.close", %{"id" => record["id"], "expected_revision" => 1})
    assert closed["revision"] == 2
    assert closed["status"] == "closed"

    assert %{"record" => ^record, "historical" => true} =
             call(
               ctx.token,
               :get,
               "/collections/support.conversation/records/#{record["id"]}?version=1"
             )
             |> json_response(200)

    assert %{"record" => ^closed, "release" => ^hash, "historical" => false} =
             call(ctx.token, :get, "/collections/support.conversation/records/#{record["id"]}")
             |> json_response(200)

    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM behavior_invocations", []).rows == [[3]]
    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM behavior_versions", []).rows == [[3]]

    assert Postgrex.query!(
             ctx.db,
             "SELECT count(*) FROM behavior_events WHERE kind='invoked'",
             []
           ).rows == [[3]]

    assert call(ctx.token, :post, "/methods/support.create", %{
             "request_id" => request_id,
             "input" => Map.put(input, "subject", "Changed")
           }).status == 409
  end

  test "exact content requires independent review; additive upgrade preserves writers and rejects breaking contracts",
       ctx do
    hash = propose(ctx, ctx.definition, nil)
    assert call(ctx.token, :post, "/releases/#{hash}/approve", %{}).status == 403
    assert call(ctx.token, :post, "/releases/#{hash}/activate", %{}).status == 403
    assert call(ctx.reviewer, :post, "/releases/#{hash}/approve", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{hash}/merge", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{hash}/activate", %{}).status == 200

    additive =
      ctx.definition
      |> put_in(["resources", "support.conversation", "version"], 2)
      |> put_in(["resources", "support.conversation", "fields", "resolution"], %{
        "type" => "string",
        "nullable" => true
      })

    next = propose(ctx, additive, hash)
    assert call(ctx.reviewer, :post, "/releases/#{next}/approve", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{next}/merge", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{next}/activate", %{}).status == 200

    assert invoke(ctx.token, "support.create", %{"subject" => "Old writer", "customer" => nil})[
             "revision"
           ] == 1

    breaking =
      put_in(additive, ["resources", "support.conversation", "fields", "resolution"], %{
        "type" => "string",
        "required" => true
      })

    broken = propose(ctx, breaking, next)
    assert call(ctx.reviewer, :post, "/releases/#{broken}/approve", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{broken}/activate", %{}).status == 409

    assert call(ctx.token, :get, "/collections") |> json_response(200) |> Map.fetch!("release") ==
             next

    assert call(ctx.token, :post, "/releases", %{"definition" => additive, "baseline" => hash}).status ==
             409
  end

  test "every session and related record open rechecks current actor grants and tenant", ctx do
    install(ctx)
    customer = invoke(ctx.token, "accounts.create", %{"name" => "Harbor Studio"})

    record =
      invoke(ctx.token, "support.create", %{"subject" => "Upload", "customer" => customer["id"]})

    thread =
      Repo.insert!(%Thread{
        account_id: 100,
        account_handle: "team",
        owner_id: 1,
        owner_session_id: ctx.session.id,
        request_id: Ecto.UUID.generate(),
        request_hash: "test",
        title: "Support handoff",
        goal: "Find ticket",
        provider: "chatgpt",
        model: "model"
      })

    message =
      Repo.insert!(%Message{
        thread_id: thread.id,
        position: 1,
        kind: "record",
        body: "Open record",
        record_reference: %{"model" => "support.conversation", "id" => record["id"]}
      })

    path = "/threads/#{thread.id}/resources/#{message.id}"
    assert %{"record" => ^record} = call(ctx.token, :get, path) |> json_response(200)

    human =
      Repo.insert!(%Message{
        thread_id: thread.id,
        position: 2,
        kind: "human",
        body: "Open the upload conversation",
        author_id: 1,
        author_session_id: ctx.session.id
      })

    Repo.update!(Ecto.Changeset.change(thread, revision: 3))
    run = Repo.insert!(%Run{thread_id: thread.id, message_id: human.id})
    Lease.want(thread.id, "thread")
    [%{epoch: epoch}] = Lease.claim("behavior-test", 1)
    assert {:ok, {run, _}} = Threads.claim(run.id, epoch)
    assert {:ok, {:ok, queries}} = Records.discover(run, %{})
    assert Enum.any?(queries, &(&1["query"] == "support.conversation.list"))

    assert {:ok, {:ok, %{"references" => [reference]}}} =
             Records.query(run, %{
               "module" => "support.conversation",
               "query" => "support.conversation.list",
               "input" => %{"search" => "Upload"}
             })

    assert reference == message.record_reference
    assert {:ok, _} = Threads.show_record(run, reference)
    Lease.release(thread.id, epoch)
    assert call(nil, :get, path).status == 401

    assert call(ctx.token, :get, String.replace(path, message.id, Ecto.UUID.generate())).status ==
             403

    Postgrex.query!(
      ctx.db,
      "UPDATE behavior_principals SET grants=jsonb_set(grants,'{collections}','[\"support.conversation\"]') WHERE user_id=1",
      []
    )

    assert call(ctx.token, :get, path).status == 200

    assert call(ctx.token, :get, "/collections/accounts.customer/records/#{customer["id"]}").status ==
             403

    Postgrex.query!(
      ctx.db,
      "UPDATE behavior_principals SET grants=jsonb_set(grants,'{collections}','[]') WHERE user_id=1",
      []
    )

    assert call(ctx.token, :get, path).status == 403
    stub_scope(organization: 11)
    # An organization without a behavior workspace lists nothing instead of an error.
    assert %{"collections" => [], "release" => nil} =
             json_response(call(ctx.token, :get, "/collections"), 200)

    assert %{"releases" => [], "active" => nil} =
             json_response(call(ctx.token, :get, "/releases"), 200)

    assert call(ctx.token, :get, path).status == 403
    stub_scope(revoked: true)
    assert call(ctx.token, :get, path).status == 403
  end

  test "sandbox failure after mutation rolls everything back and caller retains submission identity",
       ctx do
    bad =
      put_in(
        ctx.definition,
        ["methods", "support.create", "source"],
        "await Javex.Host.call('resources.create', {values: {subject: input.subject, status: 'open', customer: null}}); while (true) {}"
      )

    install(%{ctx | definition: bad})

    body = %{
      "request_id" => Ecto.UUID.generate(),
      "input" => %{"subject" => "Never commits", "customer" => nil}
    }

    assert call(ctx.token, :post, "/methods/support.create", body).status == 422
    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM behavior_versions", []).rows == [[0]]
    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM behavior_invocations", []).rows == [[0]]

    assert %{"items" => []} =
             call(ctx.token, :post, "/collections/support.conversation/query", %{})
             |> json_response(200)
  end

  test "approved exports cannot leak hidden customer fields through JS, collection search or history",
       ctx do
    definition =
      ctx.definition
      |> put_in(
        ["methods", "accounts.create", "source"],
        "return await Javex.Host.call('resources.create', {values: {name: input.name, billing_note: 'Private billing exception'}});"
      )
      |> put_in(
        ["methods", "support.create", "source"],
        "const customer = await Javex.Host.call('resources.get', {resource: 'accounts.customer', id: input.customer}); return await Javex.Host.call('resources.create', {values: {subject: customer.billing_note ?? customer.name, status: 'open', customer: input.customer}});"
      )

    install(%{ctx | definition: definition})
    customer = invoke(ctx.token, "accounts.create", %{"name" => "Harbor Studio"})
    refute Map.has_key?(customer, "billing_note")

    record =
      invoke(ctx.token, "support.create", %{"subject" => "ignored", "customer" => customer["id"]})

    assert record["subject"] == "Harbor Studio"

    for suffix <- ["", "?version=1"] do
      response =
        call(
          ctx.token,
          :get,
          "/collections/accounts.customer/records/#{customer["id"]}" <> suffix
        )
        |> json_response(200)

      refute Jason.encode!(response) =~ "Private billing"
    end

    assert call(ctx.token, :post, "/collections/accounts.customer/query", %{
             "sort" => "billing_note"
           }).status == 422

    assert %{"items" => []} =
             call(ctx.token, :post, "/collections/accounts.customer/query", %{
               "search" => "Private billing"
             })
             |> json_response(200)
  end

  test "revoked reviewer and actor authority blocks activation and protected result replay",
       ctx do
    hash = propose(ctx, ctx.definition, nil)
    assert call(ctx.reviewer, :post, "/releases/#{hash}/approve", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{hash}/merge", %{}).status == 200

    Postgrex.query!(
      ctx.db,
      "UPDATE behavior_principals SET grants=jsonb_set(grants,'{roles}','[]') WHERE user_id=2",
      []
    )

    assert call(ctx.token, :post, "/releases/#{hash}/activate", %{}).status == 403

    Postgrex.query!(
      ctx.db,
      "UPDATE behavior_principals SET grants=jsonb_set(grants,'{roles}','[\"approve\"]') WHERE user_id=2",
      []
    )

    assert call(ctx.token, :post, "/releases/#{hash}/activate", %{}).status == 200
    request_id = Ecto.UUID.generate()
    input = %{"subject" => "Access lost", "customer" => nil}
    invoke(ctx.token, "support.create", input, request_id)

    Postgrex.query!(
      ctx.db,
      "UPDATE behavior_principals SET grants=jsonb_set(grants,'{methods}','[]') WHERE user_id=1",
      []
    )

    assert call(ctx.token, :post, "/methods/support.create", %{
             "request_id" => request_id,
             "input" => input
           }).status == 403

    assert Postgrex.query!(ctx.db, "SELECT count(*) FROM behavior_invocations", []).rows == [[1]]
  end

  defp propose(ctx, definition, baseline) do
    %{"hash" => hash} =
      call(ctx.token, :post, "/releases", %{"definition" => definition, "baseline" => baseline})
      |> json_response(200)

    hash
  end

  defp install(ctx) do
    hash = propose(ctx, ctx.definition, nil)
    assert call(ctx.reviewer, :post, "/releases/#{hash}/approve", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{hash}/merge", %{}).status == 200
    assert call(ctx.token, :post, "/releases/#{hash}/activate", %{}).status == 200
    hash
  end

  defp invoke(token, method, input, request_id \\ Ecto.UUID.generate()) do
    call(token, :post, "/methods/#{method}", %{"request_id" => request_id, "input" => input})
    |> json_response(200)
  end

  defp call(token, method, path, body \\ nil) do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("origin", Config.public_url())

    conn = if token, do: put_req_cookie(conn, Auth.cookie_name(), token), else: conn
    dispatch(conn, @endpoint, method, @base <> path, if(body, do: Jason.encode!(body)))
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

  defp stub_scope(opts \\ []) do
    Req.Test.stub(LuftServer.Tuist, fn conn ->
      ["Bearer upstream-" <> subject] = get_req_header(conn, "authorization")

      if opts[:revoked] do
        conn |> put_status(403) |> Req.Test.json(%{error: "forbidden"})
      else
        Req.Test.json(conn, %{
          user_id: String.to_integer(subject),
          account_id: opts[:account] || 100,
          organization_id: opts[:organization] || 10,
          can_create_threads: true,
          people: Enum.map(1..2, &%{id: &1, handle: "person-#{&1}", active: true})
        })
      end
    end)
  end
end
