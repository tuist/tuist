defmodule TuistWeb.ProjectAuthenticationLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.Socket
  alias Tuist.Authorization
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.UnauthorizedError
  alias TuistWeb.ProjectAuthenticationLive

  test "renders workload identities in the Authentication tab", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/authentication")

    assert has_element?(lv, "#project-authentication h2", "Workload identities")
    assert has_element?(lv, ".noora-tab-menu-horizontal-item[data-selected]", "Authentication")
    assert has_element?(lv, "#fly-oidc-trust-policy-form")
    assert html =~ "Fly.io"
    refute html =~ "Default branch"
    refute html =~ "Project logo"
    assert page_title(lv) == "Authentication · #{project.name} · Tuist"
  end

  test "is linked from every existing project settings tab", %{conn: conn, organization: organization, project: project} do
    for tab <- ["", "/notifications", "/automations", "/bundles"] do
      {:ok, lv, _} = live(conn, "/#{organization.account.name}/#{project.name}/settings#{tab}")

      assert has_element?(
               lv,
               ~s(a[href="/#{organization.account.name}/#{project.name}/settings/authentication"]),
               "Authentication"
             )

      {:ok, authentication, _} =
        lv
        |> element(~s(a[href="/#{organization.account.name}/#{project.name}/settings/authentication"]))
        |> render_click()
        |> follow_redirect(conn)

      assert has_element?(authentication, "#fly-oidc-trust-policy-form")

      {:ok, general, _} =
        authentication
        |> element(~s(.noora-tab-menu-horizontal-item[href="/#{organization.account.name}/#{project.name}/settings"]))
        |> render_click()
        |> follow_redirect(conn)

      refute has_element?(general, "#fly-oidc-trust-policy-form")
    end
  end

  test "is available for every build system", %{conn: conn, organization: organization} do
    for system <- [:xcode, :gradle, :bazel, :once, :mix, :cargo] do
      project = ProjectsFixtures.project_fixture(account: organization.account, build_system: system)
      {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/authentication")
      assert has_element?(lv, "#fly-oidc-trust-policy-form")
    end
  end

  test "requires project update permission on mount", %{project: project, user: user} do
    socket = %Socket{assigns: %{selected_project: project, current_user: user}}
    expect(Authorization, :authorize, fn :project_update, ^user, ^project -> {:error, :forbidden} end)

    assert_raise UnauthorizedError, fn ->
      ProjectAuthenticationLive.mount(%{}, nil, socket)
    end
  end

  test "adds and removes a project-scoped policy", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/authentication")

    lv
    |> form("#fly-oidc-trust-policy-form", %{
      "fly_oidc_trust_policy" => %{
        "issuer" => "https://oidc.fly.io/example-org",
        "organization_id" => "123",
        "application_id" => "456"
      }
    })
    |> render_submit()

    assert [policy] = Projects.list_fly_oidc_trust_policies(project)
    assert has_element?(lv, "#fly-oidc-policy-#{policy.id}", "https://oidc.fly.io/example-org")

    lv |> element("#fly-oidc-policy-#{policy.id} button") |> render_click()
    assert [] = Projects.list_fly_oidc_trust_policies(project)
    refute has_element?(lv, "#fly-oidc-policy-#{policy.id}")
  end

  test "rejects arbitrary issuers", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/authentication")

    html =
      lv
      |> form("#fly-oidc-trust-policy-form", %{
        "fly_oidc_trust_policy" => %{
          "issuer" => "https://example.com",
          "organization_id" => "123",
          "application_id" => "456"
        }
      })
      |> render_submit()

    assert html =~ "must be https://oidc.fly.io/"
    assert [] = Projects.list_fly_oidc_trust_policies(project)
  end

  test "cannot remove another project's policy", %{conn: conn, organization: organization, project: project} do
    other = ProjectsFixtures.project_fixture(account: organization.account)

    {:ok, policy} =
      Projects.create_fly_oidc_trust_policy(other, %{
        issuer: "https://oidc.fly.io/example-org",
        organization_id: "123",
        application_id: "456"
      })

    {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/authentication")
    render_click(lv, "delete_fly_oidc_trust_policy", %{"policy-id" => to_string(policy.id)})
    refute has_element?(lv, "#fly-oidc-policy-#{policy.id}")
    assert [^policy] = Projects.list_fly_oidc_trust_policies(other)
  end

  test "reauthorizes both policy mutations against a fresh project", %{project: project, user: user} do
    socket = %Socket{assigns: %{selected_project: project, current_user: user}}
    {:ok, updated_project} = Projects.update_project(project, %{name: "renamed-project"})

    expect(Authorization, :authorize, 2, fn :project_update, ^user, actual ->
      assert actual.name == updated_project.name
      assert actual.id == project.id
      {:error, :forbidden}
    end)

    for {event, params} <- [
          {"create_fly_oidc_trust_policy", %{"fly_oidc_trust_policy" => %{}}},
          {"delete_fly_oidc_trust_policy", %{"policy-id" => "1"}}
        ] do
      assert_raise UnauthorizedError, fn ->
        ProjectAuthenticationLive.handle_event(event, params, socket)
      end
    end
  end
end
