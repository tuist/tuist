defmodule TuistWeb.API.ReportPublishingAuthorizationTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.ClickHouseRepo
  alias Tuist.Projects
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Plugs.ReportPublishingPlug

  @routes [
    {:xcode, "/builds", "builds", 200},
    {:xcode, "/xcode/builds", "builds", 200},
    {:gradle, "/gradle/builds", "builds", 201},
    {:mix, "/mix/builds", "builds", 201},
    {:xcode, "/tests", "tests", 200},
    {:bazel, "/bazel/publishing", "builds", 200}
  ]

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Tuist.Environment, :network_trusted_report_publishing_enabled?, fn -> true end)
    %{user: user}
  end

  defp project(user, system), do: ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: system)

  defp account_token(account, scopes, opts \\ %{}) do
    {:ok, {record, token}} =
      Accounts.create_account_token(
        Map.merge(
          %{account: account, scopes: scopes, all_projects: true, name: "auth-#{System.unique_integer([:positive])}"},
          opts
        )
      )

    {record, token}
  end

  defp body(:gradle, _), do: %{duration_ms: 1, status: "success", tasks: []}
  defp body(:mix, _), do: %{id: UUIDv7.generate(), duration_ms: 1, status: "success"}
  defp body(:bazel, _), do: %{}
  defp body(_, "/tests"), do: %{id: UUIDv7.generate(), duration: 1, status: "success", is_ci: false, test_modules: []}
  defp body(_, _), do: %{id: UUIDv7.generate(), duration: 1, status: "success", is_ci: false}

  defp publish(conn, project, suffix, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-tuist-actor-id", project.account.name)
    |> post("/api/projects/#{project.account.name}/#{project.name}#{suffix}", body)
  end

  defp report_schema(_, "/tests"), do: Tuist.Tests.Test
  defp report_schema(:bazel, _), do: nil
  defp report_schema(:gradle, _), do: Tuist.Gradle.Build
  defp report_schema(:mix, _), do: Tuist.Mix.Build
  defp report_schema(_, _), do: Tuist.Builds.Build

  defp reports(project, system, suffix) do
    Tuist.Builds.Build.Buffer.flush()
    Tuist.Gradle.Build.Buffer.flush()
    Tuist.Tests.Test.Buffer.flush()

    case report_schema(system, suffix) do
      nil -> []
      schema -> ClickHouseRepo.all(from(r in schema, where: r.project_id == ^project.id, order_by: r.id))
    end
  end

  for {system, suffix, resource, success} <- @routes do
    @system system
    @suffix suffix
    @resource resource
    @success success

    test "#{suffix} rejects insufficient scopes without downgrading, and accepts a real write token", %{
      conn: conn,
      user: user
    } do
      project = project(user, @system)
      {_, read_token} = account_token(user.account, ["project:#{@resource}:read"])
      {_, write_token} = account_token(user.account, ["project:#{@resource}:write"])

      denied =
        conn
        |> put_req_header("authorization", "Bearer #{read_token}")
        |> publish(project, @suffix, body(@system, @suffix))

      assert json_response(denied, 403)
      refute ReportPublishingPlug.network_publisher?(denied)
      assert reports(project, @system, @suffix) == []
      wrong_resource = if @resource == "builds", do: "tests", else: "builds"
      {_, wrong_token} = account_token(user.account, ["project:#{wrong_resource}:write"])

      assert conn
             |> put_req_header("authorization", "Bearer #{wrong_token}")
             |> publish(project, @suffix, body(@system, @suffix))
             |> json_response(403)

      assert reports(project, @system, @suffix) == []

      stub(Tuist.Environment, :network_trusted_report_publishing_enabled?, fn -> false end)

      accepted =
        conn
        |> put_req_header("authorization", "Bearer #{write_token}")
        |> publish(project, @suffix, body(@system, @suffix))

      response = json_response(accepted, @success)
      refute ReportPublishingPlug.network_publisher?(accepted)

      if @system == :bazel do
        assert response == %{"network_trusted" => false}
      else
        [stored] = reports(project, @system, @suffix)
        assert stored.submission_auth == "token"
        assert stored.actor_account_id == 0
        assert stored.claimed_actor_id == project.account.name
        assert Tuist.ReportActor.actor(stored).verified_account_handle == nil
      end
    end

    test "#{suffix} revocation after successful authentication never downgrades", %{conn: conn, user: user} do
      project = project(user, @system)
      {account_model, account_token} = account_token(user.account, ["project:#{@resource}:write"])
      project_token = Projects.create_project_token(project)
      {:ok, project_model} = Projects.get_project_token(project_token)

      assert conn
             |> put_req_header("authorization", "Bearer #{project.token}")
             |> publish(project, @suffix, body(@system, @suffix))
             |> json_response(@success)

      for {model, token, revoke} <- [
            {account_model, account_token, &Accounts.delete_account_token/1},
            {project_model, project_token, &Projects.revoke_project_token/1}
          ] do
        authenticated = put_req_header(conn, "authorization", "Bearer #{token}")

        forged =
          Map.merge(body(@system, @suffix), %{
            actor_account_id: user.account.id,
            account_id: -1,
            submission_auth: "network_trusted"
          })

        assert authenticated |> publish(project, @suffix, forged) |> json_response(@success)
        before = reports(project, @system, @suffix)
        assert Enum.all?(before, &(&1.submission_auth == "token" and &1.actor_account_id == 0))
        revoke.(model)
        assert authenticated |> publish(project, @suffix, body(@system, @suffix)) |> json_response(401)
        assert reports(project, @system, @suffix) == before
      end
    end

    test "#{suffix} denies viewers and attributes authorized organization members", %{conn: conn, user: user} do
      organization = AccountsFixtures.organization_fixture()
      project = project(%{account: organization.account}, @system)
      viewer = AccountsFixtures.user_fixture(preload: [:account])
      :ok = Accounts.add_user_to_organization(viewer, organization, role: :viewer)
      :ok = Accounts.add_user_to_organization(user, organization, role: :user)
      {:ok, viewer_token, _} = Tuist.Guardian.encode_and_sign(viewer, %{}, token_type: "access_token")
      {:ok, member_token, _} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token")

      assert conn
             |> put_req_header("authorization", "Bearer #{viewer_token}")
             |> publish(project, @suffix, body(@system, @suffix))
             |> json_response(403)

      assert reports(project, @system, @suffix) == []

      assert conn
             |> put_req_header("authorization", "Bearer #{member_token}")
             |> publish(project, @suffix, body(@system, @suffix))
             |> json_response(@success)

      if @system != :bazel do
        [stored] = reports(project, @system, @suffix)
        assert stored.submission_auth == "token"
        assert stored.actor_account_id == user.account.id
        assert Tuist.ReportActor.actor(Tuist.ReportActor.preload(stored)).verified_account_handle == user.account.name
      end
    end

    test "#{suffix} OAuth account credentials attribute their issuer, not client fields", %{conn: conn, user: user} do
      organization = AccountsFixtures.organization_fixture()
      :ok = Accounts.add_user_to_organization(user, organization, role: :user)
      project = project(%{account: organization.account}, @system)
      foreign = AccountsFixtures.user_fixture(preload: [:account])

      {:ok, token, _} =
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

      forged =
        Map.merge(body(@system, @suffix), %{
          actor_account_id: foreign.account.id,
          account_id: foreign.account.id,
          submission_auth: "network_trusted"
        })

      accepted = conn |> put_req_header("authorization", "Bearer #{token}") |> publish(project, @suffix, forged)
      assert json_response(accepted, @success)
      refute ReportPublishingPlug.network_publisher?(accepted)

      if @system != :bazel do
        [stored] = reports(project, @system, @suffix)
        assert stored.submission_auth == "token"
        assert stored.actor_account_id == user.account.id
        assert Tuist.ReportActor.actor(Tuist.ReportActor.preload(stored)).verified_account_handle == user.account.name
      end
    end

    test "#{suffix} never treats a browser session cookie as a reporting credential", %{conn: conn, user: user} do
      project = project(user, @system)

      browser =
        %{conn | secret_key_base: TuistWeb.Endpoint.config(:secret_key_base)}
        |> init_test_session(%{})
        |> TuistWeb.Authentication.log_in_user(user, %{"remember_me" => "true"})
        |> recycle()

      assert map_size(fetch_cookies(browser).req_cookies) > 0
      stub(Tuist.Environment, :network_trusted_report_publishing_enabled?, fn -> false end)
      assert browser |> publish(project, @suffix, body(@system, @suffix)) |> json_response(401)
      stub(Tuist.Environment, :network_trusted_report_publishing_enabled?, fn -> true end)
      published = publish(browser, project, @suffix, body(@system, @suffix))
      assert json_response(published, @success)

      if @system == :bazel do
        assert json_response(published, @success) == %{"network_trusted" => true}
      else
        [stored] = reports(project, @system, @suffix)
        assert stored.submission_auth == "network_trusted"
        assert stored.actor_account_id == 0
      end
    end

    test "#{suffix} rejects browser-simple non-JSON content without consuming publishing quota", %{conn: conn, user: user} do
      project = project(user, @system)
      reject(TuistWeb.RateLimit, :hit, 2)

      for content_type <- ["text/plain", "application/x-www-form-urlencoded"] do
        denied =
          conn
          |> put_req_header("content-type", content_type)
          |> post("/api/projects/#{project.account.name}/#{project.name}#{@suffix}", JSON.encode!(body(@system, @suffix)))

        assert json_response(denied, 415)
      end

      assert reports(project, @system, @suffix) == []
    end

    test "#{suffix} refuses unsigned publishing when disabled or hosted", %{conn: conn, user: user} do
      project = project(user, @system)

      for {hosted, enabled} <- [{false, false}, {true, true}] do
        stub(Tuist.Environment, :network_trusted_report_publishing_enabled?, fn ->
          Tuist.Environment.network_trusted_report_publishing_enabled?(hosted, enabled)
        end)

        assert conn |> publish(project, @suffix, body(@system, @suffix)) |> json_response(401)
      end
    end

    test "#{suffix} rejects wrong-project credentials and cross-account users and tokens", %{conn: conn, user: user} do
      project = project(user, @system)
      sibling = project(user, @system)
      other_user = AccountsFixtures.user_fixture(preload: [:account])

      {_, restricted_token} =
        account_token(user.account, ["project:#{@resource}:write"], %{all_projects: false, project_ids: [sibling.id]})

      {_, foreign_token} = account_token(other_user.account, ["project:#{@resource}:write"])
      {:ok, user_token, _} = Tuist.Guardian.encode_and_sign(other_user, %{}, token_type: "access_token")

      for token <- [sibling.token, restricted_token, foreign_token, user_token] do
        denied =
          conn |> put_req_header("authorization", "Bearer #{token}") |> publish(project, @suffix, body(@system, @suffix))

        assert json_response(denied, 403)
        refute ReportPublishingPlug.network_publisher?(denied)
      end

      assert reports(project, @system, @suffix) == []
    end

    test "#{suffix} never downgrades malformed, duplicated, expired or revoked credentials", %{conn: conn, user: user} do
      project = project(user, @system)
      {revoked, revoked_token} = account_token(user.account, ["project:#{@resource}:write"])
      {:ok, _} = Accounts.delete_account_token(revoked)

      {expired, expired_token} = account_token(user.account, ["project:#{@resource}:write"])

      Repo.update!(
        Ecto.Changeset.change(expired,
          expires_at: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
        )
      )

      {_, valid_token} = account_token(user.account, ["project:#{@resource}:write"])

      {:ok, expired_jwt, _} =
        Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token", ttl: {-10, :minute})

      for header <- [
            "bearer #{valid_token}",
            "Bearer  #{valid_token}",
            "Token #{valid_token}",
            " Bearer #{valid_token}",
            "Bearer #{expired_jwt}",
            "",
            "Bearer",
            "Bearer ",
            "Basic garbage",
            "Bearer invalid",
            "Bearer #{expired_token}",
            "Bearer #{revoked_token}"
          ] do
        denied =
          conn
          |> TuistWeb.Authentication.put_current_user(user)
          |> TuistWeb.Authentication.put_current_project(project)
          |> assign(:current_subject, %AuthenticatedAccount{
            account: user.account,
            scopes: ["project:#{@resource}:write"],
            all_projects: true
          })
          |> put_req_header("authorization", header)
          |> publish(project, @suffix, body(@system, @suffix))

        assert json_response(denied, 401)
        refute TuistWeb.Authentication.authenticated?(denied)
        refute ReportPublishingPlug.network_publisher?(denied)
      end

      duplicate = %{
        conn
        | req_headers: [
            {"authorization", "Bearer #{valid_token}"},
            {"authorization", "Bearer invalid"} | conn.req_headers
          ]
      }

      assert duplicate |> publish(project, @suffix, body(@system, @suffix)) |> json_response(401)

      duplicate = %{
        conn
        | req_headers: [
            {"authorization", "Bearer #{valid_token}"},
            {"authorization", "Bearer #{valid_token}"} | conn.req_headers
          ]
      }

      assert duplicate |> publish(project, @suffix, body(@system, @suffix)) |> json_response(401)
      assert reports(project, @system, @suffix) == []
    end
  end

  test "authenticated outsiders cannot read private reports but public read authorization is preserved", %{
    conn: conn,
    user: user
  } do
    private = project(user, :gradle)
    public = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle, visibility: :public)
    outsider = AccountsFixtures.user_fixture(preload: [:account])
    {:ok, token, _} = Tuist.Guardian.encode_and_sign(outsider, %{}, token_type: "access_token")
    authenticated = put_req_header(conn, "authorization", "Bearer #{token}")

    for suffix <- ["/builds", "/tests", "/gradle/builds"] do
      assert authenticated |> get("/api/projects/#{private.account.name}/#{private.name}#{suffix}") |> json_response(403)
      assert authenticated |> get("/api/projects/#{public.account.name}/#{public.name}#{suffix}") |> json_response(200)
    end

    for suffix <- ["/gradle/builds/#{UUIDv7.generate()}", "/builds/gradle/#{UUIDv7.generate()}/tasks"] do
      assert authenticated |> get("/api/projects/#{private.account.name}/#{private.name}#{suffix}") |> json_response(403)
    end
  end

  test "coerced processing hints and forged server-owned fields never reach storage", %{conn: conn, user: user} do
    project = project(user, :xcode)
    reject(Tuist.Builds, :create_build, 1)

    for attrs <- [
          %{xcode_cache_upload_enabled: "true"},
          %{xcode_cache_upload_enabled: true},
          %{submission_auth: "token"},
          %{actor_account_id: user.account.id},
          %{account_id: user.account.id}
        ] do
      assert conn |> publish(project, "/builds", Map.merge(body(:xcode, "/builds"), attrs)) |> json_response(400)
    end

    assert reports(project, :xcode, "/builds") == []
  end

  test "report-only instance enablement never unlocks private reads, mutation or artifact endpoints", %{
    conn: conn,
    user: user
  } do
    project = project(user, :xcode)
    prefix = "/api/projects/#{project.account.name}/#{project.name}"
    id = UUIDv7.generate()

    for path <- [
          "/builds",
          "/xcode/builds",
          "/xcode/builds/#{id}/steps",
          "/tests",
          "/tests/test-cases",
          "/tests/test-cases/runs/#{id}/attachments",
          "/gradle/builds",
          "/gradle/builds/#{id}",
          "/gradle/builds/#{id}/steps",
          "/builds/gradle/#{id}/tasks",
          "/bazel/invocations",
          "/bazel/invocations/#{id}",
          "/bazel/invocations/#{id}/logs",
          "/previews",
          "/bundles",
          "/tests/coverage/settings",
          "/tests/git-history/settings",
          "/tests/shards/reference/0"
        ] do
      assert conn |> put_req_header("x-tuist-actor-id", user.account.name) |> get(prefix <> path) |> json_response(401)
    end

    for path <- [
          "/builds/upload/start",
          "/builds/upload/generate-url",
          "/builds/upload/complete",
          "/tests/attachments",
          "/tests/crash-reports",
          "/tests/coverage/uploads",
          "/tests/coverage/commits/#{String.duplicate("a", 40)}/complete",
          "/tests/git-history/commits/missing",
          "/tests/git-history/commits",
          "/tests/git-history/listings",
          "/tests/shards",
          "/tests/shards/upload/start",
          "/tests/stress-new-tests/plan",
          "/automations/alerts",
          "/previews/start",
          "/bundles",
          "/runs"
        ] do
      assert conn |> put_req_header("content-type", "application/json") |> post(prefix <> path, %{}) |> json_response(401)
    end

    assert conn
           |> put_req_header("content-type", "application/json")
           |> patch(prefix <> "/tests/test-cases/#{id}", %{})
           |> json_response(401)

    assert conn |> get("/api/cache/access") |> json_response(401)
    assert conn |> get(prefix <> "/tokens") |> json_response(401)
    assert conn |> delete("/api/projects/#{project.id}") |> json_response(401)
    assert conn |> put_req_header("content-type", "application/json") |> put(prefix, %{}) |> json_response(401)
    assert conn |> put_req_header("content-type", "application/json") |> post("/api/analytics", %{}) |> json_response(401)
    assert conn |> put_req_header("content-type", "application/json") |> post("/mcp", %{}) |> json_response(401)
  end
end
