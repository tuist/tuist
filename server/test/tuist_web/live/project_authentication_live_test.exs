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

  @policy_params %{
    "name" => "Fly.io production",
    "issuer" => "https://oidc.fly.io/example-org",
    "jwks_url" => "https://oidc.fly.io/example-org/.well-known/jwks",
    "audience" => "tuist",
    "claims" => ~s({"org_id": "123", "app_id": "456"})
  }

  defp authentication_path(organization, project),
    do: ~p"/#{organization.account.name}/#{project.name}/settings/authentication"

  defp submit_policy(lv, params) do
    lv
    |> form("#oidc-trust-policy-form", %{"oidc_trust_policy" => params})
    |> render_submit()
  end

  test "renders workload identities in the Authentication tab", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, html} = live(conn, authentication_path(organization, project))

    assert has_element?(lv, "#project-authentication h2", "Workload identities")
    assert has_element?(lv, ".noora-tab-menu-horizontal-item[data-selected]", "Authentication")
    assert has_element?(lv, "#oidc-trust-policy-form")
    assert has_element?(lv, "#oidc-trust-policy-form textarea[name='oidc_trust_policy[claims]']")
    assert has_element?(lv, "#oidc-template", "Custom provider")
    assert has_element?(lv, "#oidc-template", "Fly.io Machines")
    assert html =~ "Allow trusted workloads to access this project without long-lived tokens."
    refute has_element?(lv, "#oidc-trust-policy-form [data-part='example']")
    refute has_element?(lv, "#oidc-workload-setup")
    refute html =~ "A token must come from the exact issuer"
    refute html =~ "Default branch"
    refute html =~ "Project logo"
    assert page_title(lv) == "Authentication · #{project.name} · Tuist"
  end

  defp select_template(lv, template), do: render_hook(lv, "select_oidc_template", %{"value" => [template]})

  defp fill_fly_template(lv, overrides \\ %{}) do
    values =
      Map.merge(%{"organization_slug" => "example-org", "organization_id" => "123", "application_id" => "456"}, overrides)

    lv |> form("#oidc-trust-policy-form", %{"fly_template" => values}) |> render_change()
  end

  test "Fly template generates editable issuer, JWKS and exact string claims", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))
    select_template(lv, "fly")
    assert has_element?(lv, "#oidc-fly-template")
    assert has_element?(lv, "#oidc_trust_policy_name[value='Fly.io Machines']")
    assert has_element?(lv, "[data-part='advanced']:not([open])")
    fill_fly_template(lv)
    assert has_element?(lv, "#oidc_trust_policy_issuer[value='https://oidc.fly.io/example-org']")
    assert has_element?(lv, "#oidc_trust_policy_jwks_url[value='https://oidc.fly.io/example-org/.well-known/jwks']")
    assert has_element?(lv, "#oidc-trust-policy-claims", ~s("org_id":"123"))
    lv |> form("#oidc-trust-policy-form") |> render_submit()
    assert [policy] = Projects.list_oidc_trust_policies(project)
    assert policy.claims === %{"org_id" => "123", "app_id" => "456"}
    assert policy.issuer == @policy_params["issuer"]
    assert policy.jwks_url == @policy_params["jwks_url"]
    refute has_element?(lv, "#oidc-fly-template")
    assert has_element?(lv, "#oidc-template-select-custom [data-part='label']", "Custom provider")
    assert has_element?(lv, "#oidc-workload-setup", "TUIST_OIDC_ACCOUNT")
    assert has_element?(lv, "#oidc-workload-setup", organization.account.name)
    assert has_element?(lv, "#oidc-workload-setup", "tuist auth login")
  end

  test "helper edits update generated fields without keeping stale identities", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))
    select_template(lv, "fly")
    fill_fly_template(lv)
    fill_fly_template(lv, %{"organization_slug" => "another-org", "application_id" => "789"})
    assert has_element?(lv, "#oidc_trust_policy_issuer[value='https://oidc.fly.io/another-org']")
    assert has_element?(lv, "#oidc-trust-policy-claims", ~s("app_id":"789"))
    fill_fly_template(lv, %{"organization_slug" => "", "application_id" => ""})
    refute has_element?(lv, "#oidc_trust_policy_issuer[value='https://oidc.fly.io/another-org']")
    lv |> form("#oidc-trust-policy-form") |> render_submit()
    assert [] = Projects.list_oidc_trust_policies(project)
    assert has_element?(lv, "#oidc-trust-policy-form", "Enter a valid Fly.io organization slug")
  end

  test "queued helper events cannot restore stale generated values", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))
    select_template(lv, "fly")
    fill_fly_template(lv)
    fill_fly_template(lv, %{"organization_slug" => "another-org"})

    render_change(lv, "change_oidc_trust_policy", %{
      "_target" => ["fly_template", "organization_slug"],
      "oidc_trust_policy" => Map.put(@policy_params, "name", "Fly.io Machines"),
      "fly_template" => %{"organization_slug" => "latest-org", "organization_id" => "123", "application_id" => "456"}
    })

    assert has_element?(lv, "#oidc_trust_policy_issuer[value='https://oidc.fly.io/latest-org']")
    assert has_element?(lv, "#oidc_trust_policy_jwks_url[value='https://oidc.fly.io/latest-org/.well-known/jwks']")

    render_change(lv, "change_oidc_trust_policy", %{
      "_target" => ["oidc_trust_policy", "name"],
      "oidc_trust_policy" => Map.put(@policy_params, "name", "My deployment"),
      "fly_template" => %{"organization_slug" => "latest-org", "organization_id" => "123", "application_id" => "456"}
    })

    assert has_element?(lv, "#oidc_trust_policy_name[value='My deployment']")
    assert has_element?(lv, "#oidc_trust_policy_issuer[value='https://oidc.fly.io/latest-org']")
  end

  test "template changes preserve manually edited configuration", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))
    select_template(lv, "fly")
    fill_fly_template(lv)

    params = %{
      @policy_params
      | "name" => "My service",
        "audience" => "custom",
        "claims" => ~s({"sub":"deployment"}),
        "issuer" => "https://custom.example",
        "jwks_url" => "https://custom.example/keys"
    }

    lv |> form("#oidc-trust-policy-form", %{"oidc_trust_policy" => params}) |> render_change()
    fill_fly_template(lv, %{"organization_slug" => "another-org", "application_id" => "789"})
    select_template(lv, "custom")
    select_template(lv, "fly")
    assert has_element?(lv, "#oidc_trust_policy_name[value='My service']")
    assert has_element?(lv, "#oidc_trust_policy_audience[value='custom']")
    assert has_element?(lv, "#oidc_trust_policy_issuer[value='https://custom.example']")
    assert has_element?(lv, "#oidc_trust_policy_jwks_url[value='https://custom.example/keys']")
    assert has_element?(lv, "#oidc-trust-policy-claims", ~s({"sub":"deployment"}))
    select_template(lv, "custom")
    lv |> form("#oidc-trust-policy-form") |> render_submit()
    assert [policy] = Projects.list_oidc_trust_policies(project)
    assert policy.claims == %{"sub" => "deployment"}
  end

  test "selecting a template does not replace an existing custom draft", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))

    params = %{
      @policy_params
      | "name" => "Custom deployment",
        "issuer" => "https://identity.example.com",
        "jwks_url" => "https://identity.example.com/jwks",
        "claims" => ~s({"sub":"service:production"})
    }

    lv |> form("#oidc-trust-policy-form", %{"oidc_trust_policy" => params}) |> render_change()
    select_template(lv, "fly")
    fill_fly_template(lv)
    assert has_element?(lv, "#oidc_trust_policy_name[value='Custom deployment']")
    assert has_element?(lv, "[data-part='advanced'][open] #oidc-trust-policy-claims", params["claims"])
    assert has_element?(lv, "#oidc-template-overrides", "Your manual changes override this template.")
    lv |> form("#oidc-trust-policy-form") |> render_submit()
    assert [policy] = Projects.list_oidc_trust_policies(project)
    assert policy.issuer == params["issuer"]
    assert policy.jwks_url == params["jwks_url"]
    assert policy.claims == %{"sub" => "service:production"}
  end

  test "overrides are no longer highlighted when helper values match them", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))
    select_template(lv, "fly")
    fill_fly_template(lv)

    lv
    |> form("#oidc-trust-policy-form", %{"oidc_trust_policy" => %{"issuer" => "https://oidc.fly.io/another-org"}})
    |> render_change()

    assert has_element?(lv, "[data-part='advanced'][open]")
    assert has_element?(lv, "#oidc-template-overrides")
    fill_fly_template(lv, %{"organization_slug" => "another-org"})
    refute has_element?(lv, "[data-part='advanced'][open]")
    refute has_element?(lv, "#oidc-template-overrides")
  end

  test "editing visible fields does not warn about hidden overrides", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))
    select_template(lv, "fly")
    fill_fly_template(lv)

    lv
    |> form("#oidc-trust-policy-form", %{"oidc_trust_policy" => %{"name" => "Production", "audience" => "custom"}})
    |> render_change()

    refute has_element?(lv, "[data-part='advanced'][open]")
    refute has_element?(lv, "#oidc-template-overrides")
  end

  test "invalid helper values and unknown templates never create policies", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))
    select_template(lv, "unknown")
    refute has_element?(lv, "#oidc-fly-template")
    select_template(lv, "fly")

    for invalid <- [
          %{"organization_slug" => "../another"},
          %{"organization_slug" => "org?query"},
          %{"organization_id" => "app-name"},
          %{"application_id" => "1.2"},
          %{"application_id" => String.duplicate("1", 256)}
        ] do
      fill_fly_template(lv, invalid)
      lv |> form("#oidc-trust-policy-form") |> render_submit()
      assert has_element?(lv, "#oidc-trust-policy-form", "Enter a valid Fly.io organization slug")
      assert [] = Projects.list_oidc_trust_policies(project)
    end
  end

  test "advanced errors expand the generated configuration", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))
    select_template(lv, "fly")
    fill_fly_template(lv)
    submit_policy(lv, %{@policy_params | "claims" => "not JSON"})
    assert has_element?(lv, "[data-part='advanced'][open]", "Claims must be valid JSON.")
    assert [] = Projects.list_oidc_trust_policies(project)
  end

  test "existing Mix policies show the Elixir login command", %{conn: conn, organization: organization} do
    project = ProjectsFixtures.project_fixture(account: organization.account, build_system: :mix)
    {:ok, _} = Projects.create_oidc_trust_policy(project, Map.put(@policy_params, "claims", %{"sub" => "builder"}))
    {:ok, lv, _} = live(conn, authentication_path(organization, project))
    assert has_element?(lv, "#oidc-workload-setup", "mix tuist.login")
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

      assert has_element?(authentication, "#oidc-trust-policy-form")

      {:ok, general, _} =
        authentication
        |> element(~s(.noora-tab-menu-horizontal-item[href="/#{organization.account.name}/#{project.name}/settings"]))
        |> render_click()
        |> follow_redirect(conn)

      refute has_element?(general, "#oidc-trust-policy-form")
    end
  end

  test "is available for every build system", %{conn: conn, organization: organization} do
    for system <- [:xcode, :gradle, :bazel, :once, :mix, :cargo] do
      project = ProjectsFixtures.project_fixture(account: organization.account, build_system: system)
      {:ok, lv, _} = live(conn, authentication_path(organization, project))
      assert has_element?(lv, "#oidc-trust-policy-form")
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
    {:ok, lv, _} = live(conn, authentication_path(organization, project))

    submit_policy(lv, @policy_params)

    assert [policy] = Projects.list_oidc_trust_policies(project)
    assert policy.name == "Fly.io production"
    assert policy.issuer == "https://oidc.fly.io/example-org"
    assert policy.jwks_url == "https://oidc.fly.io/example-org/.well-known/jwks"
    assert policy.audience == "tuist"
    assert policy.claims == %{"org_id" => "123", "app_id" => "456"}
    assert has_element?(lv, "#oidc-trust-policy-#{policy.id}", "https://oidc.fly.io/example-org")
    assert has_element?(lv, "#oidc-trust-policy-#{policy.id}", ~s(org_id = "123"))

    lv |> element("#oidc-trust-policy-#{policy.id} button") |> render_click()
    assert [] = Projects.list_oidc_trust_policies(project)
    refute has_element?(lv, "#oidc-trust-policy-#{policy.id}")
  end

  test "keeps integer and boolean claim types from the JSON editor", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))

    submit_policy(lv, %{@policy_params | "claims" => ~s({"project_id": 42, "protected": true})})

    assert [policy] = Projects.list_oidc_trust_policies(project)
    assert policy.claims === %{"project_id" => 42, "protected" => true}
    assert has_element?(lv, "#oidc-trust-policy-#{policy.id}", "project_id = 42")
    assert has_element?(lv, "#oidc-trust-policy-#{policy.id}", "protected = true")
  end

  test "renders invalid claims JSON inline and keeps the input", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))

    submit_policy(lv, %{@policy_params | "claims" => ~s({"org_id": "123",})})

    assert has_element?(lv, "#oidc-trust-policy-form .noora-text-area[data-error]", "Claims must be valid JSON.")
    assert has_element?(lv, "#oidc-trust-policy-claims", ~s({"org_id": "123",}))
    assert has_element?(lv, "#oidc_trust_policy_issuer[value='https://oidc.fly.io/example-org']")
    assert [] = Projects.list_oidc_trust_policies(project)
  end

  test "rejects oversized JSON even when browser limits are bypassed", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))
    params = %{@policy_params | "claims" => String.duplicate(" ", 8193)}
    render_submit(lv, "create_oidc_trust_policy", %{"oidc_trust_policy" => params})

    assert has_element?(
             lv,
             "#oidc-trust-policy-form .noora-text-area[data-error]",
             "Claims must be valid JSON of at most 8 KiB."
           )

    assert [] = Projects.list_oidc_trust_policies(project)
  end

  test "requires claims to be a JSON object", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))

    for claims <- [~s(["org_id"]), ~s("org_id"), "42", "null"] do
      submit_policy(lv, %{@policy_params | "claims" => claims})

      assert has_element?(
               lv,
               "#oidc-trust-policy-form .noora-text-area[data-error]",
               "Claims must be a JSON object."
             )
    end

    assert [] = Projects.list_oidc_trust_policies(project)
  end

  test "renders changeset claim errors inline", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))

    for claims <- ["{}", ~s({"org_id": {"id": "123"}}), ~s({"org_id": ["123"]}), ~s({"iss": "https://example.com"})] do
      submit_policy(lv, %{@policy_params | "claims" => claims})
      assert has_element?(lv, "#oidc-trust-policy-form .noora-text-area[data-error]")
    end

    assert [] = Projects.list_oidc_trust_policies(project)
  end

  test "shows the per-project policy limit inline", %{conn: conn, organization: organization, project: project} do
    for index <- 1..20 do
      {:ok, _} =
        Projects.create_oidc_trust_policy(project, %{
          name: "Policy #{index}",
          issuer: "https://oidc.fly.io/example-org",
          jwks_url: "https://oidc.fly.io/example-org/.well-known/jwks",
          audience: "tuist",
          claims: %{"app_id" => to_string(index)}
        })
    end

    {:ok, lv, _} = live(conn, authentication_path(organization, project))

    submit_policy(lv, @policy_params)

    assert has_element?(lv, "#oidc-trust-policy-form [data-part='wrapper'][data-error]")
    assert has_element?(lv, "#oidc-trust-policy-claims", ~s({"org_id": "123", "app_id": "456"}))
    assert length(Projects.list_oidc_trust_policies(project)) == 20
  end

  test "requires unique policy names per project", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))

    submit_policy(lv, @policy_params)
    submit_policy(lv, %{@policy_params | "claims" => ~s({"org_id": "123", "app_id": "789"})})

    assert has_element?(lv, "#oidc-trust-policy-form [data-part='wrapper'][data-error]")
    assert has_element?(lv, "#oidc_trust_policy_name[value='Fly.io production']")
    assert [_policy] = Projects.list_oidc_trust_policies(project)
  end

  test "rejects built-in provider issuers", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))

    for issuer <- [
          "https://token.actions.githubusercontent.com",
          "https://token.actions.githubusercontent.com/enterprise",
          "https://oidc.circleci.com/org/0000",
          "https://token.builds.bitrise.io"
        ] do
      submit_policy(lv, %{@policy_params | "issuer" => issuer, "jwks_url" => issuer <> "/.well-known/jwks"})
      assert has_element?(lv, "#oidc-trust-policy-form [data-part='wrapper'][data-error]")
    end

    assert [] = Projects.list_oidc_trust_policies(project)
  end

  test "rejects non-HTTPS issuers and JWKS URLs", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))

    for params <- [
          %{@policy_params | "issuer" => "http://oidc.example.com"},
          %{@policy_params | "jwks_url" => "http://oidc.fly.io/example-org/.well-known/jwks"}
        ] do
      submit_policy(lv, params)
      assert has_element?(lv, "#oidc-trust-policy-form [data-part='wrapper'][data-error]")
    end

    assert [] = Projects.list_oidc_trust_policies(project)
  end

  test "cannot remove another project's policy", %{conn: conn, organization: organization, project: project} do
    other = ProjectsFixtures.project_fixture(account: organization.account)

    {:ok, policy} =
      Projects.create_oidc_trust_policy(other, %{
        name: "Other project",
        issuer: "https://oidc.fly.io/example-org",
        jwks_url: "https://oidc.fly.io/example-org/.well-known/jwks",
        audience: "tuist",
        claims: %{"org_id" => "123", "app_id" => "456"}
      })

    {:ok, lv, _} = live(conn, authentication_path(organization, project))
    render_click(lv, "delete_oidc_trust_policy", %{"policy-id" => to_string(policy.id)})
    refute has_element?(lv, "#oidc-trust-policy-#{policy.id}")
    assert [%{id: id}] = Projects.list_oidc_trust_policies(other)
    assert id == policy.id
  end

  test "ignores malformed policy IDs", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _} = live(conn, authentication_path(organization, project))

    reject(&Projects.delete_oidc_trust_policy/2)

    render_click(lv, "delete_oidc_trust_policy", %{"policy-id" => "not-an-id"})

    assert Process.alive?(lv.pid)
    assert has_element?(lv, "#oidc-trust-policy-form")
  end

  test "reauthorizes both policy mutations against a fresh project", %{project: project, user: user} do
    socket = %Socket{assigns: %{selected_project: project, current_user: user}}
    {:ok, updated_project} = Projects.update_project(project, %{name: "renamed-project"})

    expect(Authorization, :authorize, 2, fn :project_update, ^user, actual ->
      assert actual.name == updated_project.name
      assert actual.id == project.id
      {:error, :forbidden}
    end)

    reject(&Projects.create_oidc_trust_policy/2)
    reject(&Projects.delete_oidc_trust_policy/2)

    for {event, params} <- [
          {"create_oidc_trust_policy", %{"oidc_trust_policy" => @policy_params}},
          {"delete_oidc_trust_policy", %{"policy-id" => "1"}}
        ] do
      assert_raise UnauthorizedError, fn ->
        ProjectAuthenticationLive.handle_event(event, params, socket)
      end
    end
  end
end
