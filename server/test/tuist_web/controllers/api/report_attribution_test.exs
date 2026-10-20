defmodule TuistWeb.API.ReportAttributionTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Builds.Build.Buffer
  alias Tuist.ClickHouseRepo
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests.Test
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @routes [
    {:build, :xcode, "/builds", "builds", 200},
    {:build_alias, :xcode, "/xcode/builds", "builds", 200},
    {:gradle, :gradle, "/gradle/builds", "builds", 201},
    {:mix, :mix, "/mix/builds", "builds", 201},
    {:test, :xcode, "/tests", "tests", 200},
    {:legacy_build, :xcode, "/runs", "runs", 200},
    {:legacy_test, :xcode, "/runs", "runs", 200},
    {:event, :xcode, "/analytics", "runs", 200},
    {:event_test, :xcode, "/analytics", "runs", 200}
  ]

  setup do
    organization = AccountsFixtures.organization_fixture()
    user = AccountsFixtures.user_fixture(preload: [:account])
    :ok = Accounts.add_user_to_organization(user, organization, role: :user)
    %{organization: organization, user: user}
  end

  defp token(account, resource, permission \\ "write") do
    {:ok, {_record, token}} =
      Accounts.create_account_token(%{
        account: account,
        name: "attribution-#{System.unique_integer([:positive])}",
        scopes: ["project:#{resource}:#{permission}"],
        all_projects: true
      })

    token
  end

  defp body(:gradle), do: %{duration_ms: 1, status: "success", tasks: []}
  defp body(:mix), do: %{id: UUIDv7.generate(), duration_ms: 1, status: "success"}
  defp body(:legacy_test), do: :test |> body() |> Map.put(:type, "test") |> Map.put(:macos_version, "15.0")
  defp body(:legacy_build), do: Map.put(body(:build), :type, "build")

  defp body(:test) do
    Map.put(body(:build), :test_modules, [
      %{
        name: "Module",
        status: "success",
        duration: 1,
        test_suites: [],
        test_cases: [%{name: "test_example", status: "success", duration: 1}]
      }
    ])
  end

  defp body(:event_test),
    do:
      :event
      |> body()
      |> Map.put(:name, "test")
      |> Map.put(:status, "success")
      |> Map.put(:command_arguments, ["test", "App"])

  defp body(:event) do
    %{
      id: UUIDv7.generate(),
      name: "generate",
      command_arguments: ["App"],
      duration: 1,
      tuist_version: "4.110.0",
      swift_version: "6.0",
      macos_version: "15.0",
      is_ci: true,
      client_id: "attribution-test",
      cacheable_targets: [],
      local_cache_target_hits: [],
      remote_cache_target_hits: []
    }
  end

  defp body(_), do: %{id: UUIDv7.generate(), duration: 1, status: "success", is_ci: true}

  defp publish(conn, project, kind, path, payload) do
    url =
      if kind in [:event, :event_test],
        do: "/api/analytics?project_id=#{project.account.name}/#{project.name}",
        else: "/api/projects/#{project.account.name}/#{project.name}#{path}"

    conn |> put_req_header("content-type", "application/json") |> post(url, payload)
  end

  defp schema(:gradle), do: Tuist.Gradle.Build
  defp schema(:mix), do: Tuist.Mix.Build
  defp schema(kind) when kind in [:test, :legacy_test], do: Test
  defp schema(kind) when kind in [:event, :event_test], do: Tuist.CommandEvents.Event
  defp schema(_), do: Tuist.Builds.Build

  defp reports(project, kind) do
    Buffer.flush()
    Tuist.Gradle.Build.Buffer.flush()
    Tuist.Mix.Build.Buffer.flush()
    Tuist.Tests.Test.Buffer.flush()
    Tuist.Tests.TestCaseRun.Buffer.flush()
    Tuist.CommandEvents.Event.Buffer.flush()
    schema = schema(kind)
    records = ClickHouseRepo.all(from(r in schema, where: r.project_id == ^project.id, order_by: r.id))

    if kind == :event_test do
      tests = ClickHouseRepo.all(from(r in Test, where: r.project_id == ^project.id))
      assert length(tests) == length(records)

      assert Enum.all?(tests, fn test ->
               Enum.any?(
                 records,
                 &(Map.take(&1, Tuist.ReportActor.fields()) == Map.take(test, Tuist.ReportActor.fields()))
               )
             end)
    end

    records
  end

  defp assert_child_actor(project, parent, response) do
    [child] = ClickHouseRepo.all(from(r in Tuist.Tests.TestCaseRun, where: r.project_id == ^project.id))
    assert child.actor_account_id == parent.actor_account_id
    assert child.claimed_actor_id == parent.claimed_actor_id
    assert child.submission_auth == parent.submission_auth
    assert [child_response] = response["test_case_runs"]
    assert child_response["actor"] == response["actor"]
  end

  test "API reads distinguish historical publishers, new unknown actors, and verified individuals", %{
    conn: conn,
    organization: organization,
    user: user
  } do
    project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
    base = %{project_id: project.id, account_id: organization.account.id, duration: 1, status: "success", is_ci: true}
    {:ok, legacy} = Tuist.Builds.create_build(Map.put(base, :id, UUIDv7.generate()))
    {:ok, unknown} = Tuist.Builds.create_build(Map.merge(base, %{id: UUIDv7.generate(), submission_auth: "token"}))

    {:ok, verified} =
      Tuist.Builds.create_build(
        Map.merge(base, %{
          id: UUIDv7.generate(),
          actor_account_id: user.account.id,
          claimed_actor_id: "unverified",
          submission_auth: "token"
        })
      )

    Buffer.flush()
    {:ok, access_token, _} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token")
    conn = put_req_header(conn, "authorization", "Bearer #{access_token}")
    path = "/api/projects/#{project.account.name}/#{project.name}/xcode/builds"
    response = conn |> get(path) |> json_response(200)
    by_id = Map.new(response["builds"], &{&1["id"], &1["actor"]})
    assert by_id[legacy.id]["source"] == "legacy"
    assert by_id[legacy.id]["name"] == organization.account.name
    assert by_id[unknown.id]["source"] == "unknown"
    assert by_id[unknown.id]["name"] == "Unknown"
    assert by_id[verified.id]["source"] == "verified"
    assert by_id[verified.id]["verified_account_handle"] == user.account.name

    for record <- [legacy, unknown, verified] do
      detail = conn |> get("#{path}/#{record.id}") |> json_response(200)
      assert detail["actor"] == by_id[record.id]
    end
  end

  for {kind, system, path, resource, success} <- @routes do
    @kind kind
    @system system
    @path path
    @resource resource
    @success success

    test "#{kind}: shared credentials preserve the publisher and cannot forge a verified actor", context do
      %{conn: conn, organization: organization, user: user} = context
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id, build_system: @system)
      access_token = token(organization.account, @resource)
      foreign = AccountsFixtures.user_fixture(preload: [:account])
      before_users = Repo.aggregate(Accounts.User, :count)

      payload =
        Map.merge(body(@kind), %{
          account_id: foreign.account.id,
          actor_account_id: foreign.account.id,
          claimed_actor_id: "body-claim",
          submission_auth: "forged",
          user_id: user.id
        })

      response =
        conn
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> put_req_header("x-tuist-actor-id", foreign.account.name)
        |> publish(project, @kind, @path, payload)
        |> json_response(@success)

      [stored] = reports(project, @kind)
      assert stored.actor_account_id == 0
      assert stored.claimed_actor_id == foreign.account.name
      assert stored.submission_auth == "token"
      if @kind not in [:event, :event_test], do: assert(stored.account_id == organization.account.id)
      assert Repo.aggregate(Accounts.User, :count) == before_users
      assert response["actor"]["source"] == "reported"
      assert response["actor"]["verified_account_handle"] == nil
      assert response["actor"]["name"] == foreign.account.name
      if @kind == :test, do: assert_child_actor(project, stored, response)
    end

    test "#{kind}: OAuth-issued organization credentials attribute the individual issuer", context do
      %{conn: conn, organization: organization, user: user} = context
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id, build_system: @system)

      {:ok, access_token, _} =
        Tuist.Authentication.encode_and_sign(
          organization.account,
          %{
            "type" => "account",
            "scopes" => ["project:#{@resource}:write"],
            "all_projects" => true,
            "user_id" => user.id
          },
          token_type: "access_token"
        )

      response =
        conn
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> put_req_header("x-tuist-actor-id", "someone-else")
        |> publish(project, @kind, @path, Map.merge(body(@kind), %{actor_account_id: 0, submission_auth: "forged"}))
        |> json_response(@success)

      [stored] = reports(project, @kind)
      assert stored.actor_account_id == user.account.id
      assert stored.claimed_actor_id == "someone-else"
      assert stored.submission_auth == "token"
      if @kind not in [:event, :event_test], do: assert(stored.account_id == organization.account.id)
      assert response["actor"]["source"] == "verified"
      assert response["actor"]["verified_account_handle"] == user.account.name
      assert response["actor"]["name"] == user.account.name
      if @kind == :test, do: assert_child_actor(project, stored, response)
    end

    test "#{kind}: individual JWT identity wins with no claim or an invalid claim", context do
      %{conn: conn, organization: organization, user: user} = context
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id, build_system: @system)
      {:ok, access_token, _} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token")

      for claim <- [nil, "", "invalid claim", "é", String.duplicate("a", 129)] do
        authorized = put_req_header(conn, "authorization", "Bearer #{access_token}")
        authorized = if claim, do: put_req_header(authorized, "x-tuist-actor-id", claim), else: authorized
        response = authorized |> publish(project, @kind, @path, body(@kind)) |> json_response(@success)
        assert response["actor"]["source"] == "verified"
        assert response["actor"]["claimed_actor_id"] == ""
      end

      stored = reports(project, @kind)
      assert length(stored) == 5

      assert Enum.all?(
               stored,
               &(&1.actor_account_id == user.account.id && &1.claimed_actor_id == "" && &1.submission_auth == "token")
             )
    end

    test "#{kind}: claims cannot grant authentication, write scope, or another project's access", context do
      %{conn: conn, organization: organization, user: user} = context
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id, build_system: @system)
      claimed = put_req_header(conn, "x-tuist-actor-id", user.account.name)
      assert claimed |> publish(project, @kind, @path, body(@kind)) |> json_response(401)

      assert claimed
             |> put_req_header("authorization", "Bearer invalid")
             |> publish(project, @kind, @path, body(@kind))
             |> json_response(401)

      read_token = token(organization.account, @resource, "read")

      assert claimed
             |> put_req_header("authorization", "Bearer #{read_token}")
             |> publish(project, @kind, @path, body(@kind))
             |> json_response(403)

      other = ProjectsFixtures.project_fixture(build_system: @system)
      wrong_project_token = Projects.create_project_token(other)

      assert claimed
             |> put_req_header("authorization", "Bearer #{wrong_project_token}")
             |> publish(project, @kind, @path, body(@kind))
             |> json_response(403)

      assert reports(project, @kind) == []
    end

    if kind in [:build, :build_alias, :test, :legacy_build] do
      test "#{kind}: retries preserve stored attribution instead of the retrying identity", context do
        %{conn: conn, organization: organization, user: user} = context
        project = ProjectsFixtures.project_fixture(account_id: organization.account.id, build_system: @system)
        payload = body(@kind)
        {:ok, original_token, _} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token")

        original =
          conn
          |> put_req_header("authorization", "Bearer #{original_token}")
          |> put_req_header("x-tuist-actor-id", "original-claim")
          |> publish(project, @kind, @path, payload)
          |> json_response(@success)

        [stored] = reports(project, @kind)
        retrying_user = AccountsFixtures.user_fixture(preload: [:account])
        :ok = Accounts.add_user_to_organization(retrying_user, organization, role: :user)
        {:ok, retry_token, _} = Tuist.Guardian.encode_and_sign(retrying_user, %{}, token_type: "access_token")

        retried =
          conn
          |> put_req_header("authorization", "Bearer #{retry_token}")
          |> put_req_header("x-tuist-actor-id", "retry-claim")
          |> publish(project, @kind, @path, payload)
          |> json_response(@success)

        assert retried["id"] == original["id"]
        assert retried["actor"] == original["actor"]
        assert retried["actor"]["verified_account_handle"] == user.account.name
        assert retried["actor"]["claimed_actor_id"] == "original-claim"
        [after_retry] = reports(project, @kind)
        assert Map.take(after_retry, Tuist.ReportActor.fields()) == Map.take(stored, Tuist.ReportActor.fields())
        if @kind == :test, do: assert_child_actor(project, after_retry, retried)
      end
    end

    test "#{kind}: project credentials and missing claims never imply a verified person", context do
      %{conn: conn, organization: organization} = context
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id, build_system: @system)
      project_token = Projects.create_project_token(project)

      for credential <- [project.token, project_token] do
        response =
          conn
          |> put_req_header("authorization", "Bearer #{credential}")
          |> publish(project, @kind, @path, body(@kind))
          |> json_response(@success)

        assert response["actor"]["source"] == "unknown"
        assert response["actor"]["verified_account_handle"] == nil
      end

      stored = reports(project, @kind)
      assert length(stored) == 2
      assert Enum.all?(stored, &(&1.actor_account_id == 0 && &1.claimed_actor_id == "" && &1.submission_auth == "token"))
    end
  end
end
