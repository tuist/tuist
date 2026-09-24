defmodule TuistWeb.ProjectOIDCSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.OIDC.ProjectProviders
  alias Tuist.OIDC.ScopeRules
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "is reachable from the project settings tabs", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

    assert has_element?(lv, ~s(a[href="/#{organization.account.name}/#{project.name}/settings/oidc"]), "OIDC")
  end

  test "asks to connect GitHub when the project isn't linked to a repository", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/oidc")

    assert has_element?(lv, "[data-part=github-connect-alert]")
    assert has_element?(lv, "#project-oidc-scope-rules")
  end

  test "saves, shows, and removes a rule for a scope", %{conn: conn, organization: organization} do
    project =
      ProjectsFixtures.project_fixture(
        account: organization.account,
        vcs_connection: [repository_full_handle: "tuist/settings-rules"]
      )

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/oidc")

    refute has_element?(lv, "[data-part=github-connect-alert]")
    assert has_element?(lv, "#project-oidc-scope-rules-project-previews-write", "Any")

    lv
    |> form("#project-oidc-scope-rules-project-previews-write-form", %{
      "scope" => "project:previews:write",
      "refs" => "refs/heads/main, refs/tags/v*",
      "job_workflow_refs" => "",
      "environments" => "production"
    })
    |> render_submit()

    assert [%{refs: ["refs/heads/main", "refs/tags/v*"], environments: ["production"]}] =
             ScopeRules.list_project_rules(project)

    assert has_element?(lv, "#project-oidc-scope-rules-project-previews-write", "refs/heads/main, refs/tags/v*")

    render_click(lv, "delete_oidc_rule", %{"scope" => "project:previews:write"})

    assert [] = ScopeRules.list_project_rules(project)
    refute has_element?(lv, "#project-oidc-scope-rules-project-previews-write", "refs/heads/main")
  end

  test "shows a validation error for an empty rule", %{conn: conn, organization: organization} do
    project =
      ProjectsFixtures.project_fixture(
        account: organization.account,
        vcs_connection: [repository_full_handle: "tuist/settings-rules-empty"]
      )

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/oidc")

    html =
      lv
      |> form("#project-oidc-scope-rules-project-cache-write-form", %{
        "scope" => "project:cache:write",
        "refs" => " ",
        "job_workflow_refs" => "",
        "environments" => ""
      })
      |> render_submit()

    assert html =~ "add at least one branch, workflow, or environment pattern"
    assert [] = ScopeRules.list_project_rules(project)
  end

  test "notes that rules only match GitHub Actions tokens", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/oidc")

    assert has_element?(lv, "[data-part=oidc-provider-alert]", "Rules only match GitHub Actions tokens")
  end

  test "warns when the project recently used CircleCI or Bitrise OIDC tokens", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    :ok = ProjectProviders.record_exchange([project], :circleci)
    :ok = ProjectProviders.record_exchange([project], :bitrise)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/oidc")

    assert has_element?(
             lv,
             "[data-part=oidc-provider-alert]",
             "Bitrise and CircleCI runs lose write access when a rule applies"
           )
  end

  test "shows a validation error on the field it belongs to", %{conn: conn, organization: organization} do
    project =
      ProjectsFixtures.project_fixture(
        account: organization.account,
        vcs_connection: [repository_full_handle: "tuist/settings-rules-field-errors"]
      )

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/oidc")

    html =
      lv
      |> form("#project-oidc-scope-rules-project-cache-write-form", %{
        "scope" => "project:cache:write",
        "refs" => "refs/heads/main",
        "job_workflow_refs" => Enum.map_join(1..21, ",", &"org/repo/.github/workflows/w#{&1}.yml@**"),
        "environments" => ""
      })
      |> render_submit()

    erroring_inputs =
      html
      |> Floki.parse_document!()
      |> Floki.find("[data-part=wrapper][data-error]")
      |> Enum.flat_map(&Floki.attribute(&1, "input", "id"))

    assert erroring_inputs == ["project-oidc-scope-rules-project-cache-write-job-workflow-refs"]
  end
end
