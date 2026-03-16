defmodule TuistWeb.GradleBuildRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures

  setup %{project: project, conn: conn} do
    project =
      project
      |> Ecto.Changeset.change(build_system: :gradle)
      |> Tuist.Repo.update!()

    conn = Plug.Conn.assign(conn, :selected_project, project)
    %{project: project, conn: conn}
  end

  test "lists latest gradle build runs", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "my-android-app",
      status: "success"
    )

    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "my-other-app",
      status: "failure"
    )

    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs")

    assert has_element?(lv, "span", "my-android-app")
    assert has_element?(lv, "span", "my-other-app")
  end

  test "filters build runs by status", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "passing-build",
      status: "success"
    )

    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "failing-build",
      status: "failure"
    )

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs?filter_status_op===&filter_status_val=success"
      )

    assert has_element?(lv, "span", "passing-build")
    refute has_element?(lv, "span", "failing-build")
  end

  test "filters build runs by branch", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "main-build",
      git_branch: "main"
    )

    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "feature-build",
      git_branch: "feature/new-thing"
    )

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs?filter_git_branch_op==~&filter_git_branch_val=main"
      )

    assert has_element?(lv, "span", "main-build")
    refute has_element?(lv, "span", "feature-build")
  end

  test "filters build runs by environment (CI)", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "ci-build",
      is_ci: true
    )

    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "local-build",
      is_ci: false
    )

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs?filter_is_ci_op===&filter_is_ci_val=ci"
      )

    assert has_element?(lv, "span", "ci-build")
    refute has_element?(lv, "span", "local-build")
  end

  test "filters build runs by ran_by user", %{
    conn: conn,
    user: user,
    organization: organization,
    project: project
  } do
    other_user = AccountsFixtures.user_fixture()
    :ok = Tuist.Accounts.add_user_to_organization(other_user, organization)

    GradleFixtures.build_fixture(
      project_id: project.id,
      account_id: user.account.id,
      root_project_name: "user-build",
      is_ci: false
    )

    GradleFixtures.build_fixture(
      project_id: project.id,
      account_id: other_user.account.id,
      root_project_name: "other-user-build",
      is_ci: false
    )

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs?filter_ran_by_op===&filter_ran_by_val=#{user.account.id}"
      )

    assert has_element?(lv, "span", "user-build")
    refute has_element?(lv, "span", "other-user-build")
  end

  test "filters build runs by ran_by CI", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "ci-build",
      is_ci: true
    )

    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "local-build",
      is_ci: false
    )

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs?filter_ran_by_op===&filter_ran_by_val=ci"
      )

    assert has_element?(lv, "span", "ci-build")
    refute has_element?(lv, "span", "local-build")
  end

  test "filters build runs by gradle version", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "gradle-8-build",
      gradle_version: "8.5"
    )

    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "gradle-7-build",
      gradle_version: "7.6"
    )

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs?filter_gradle_version_op==~&filter_gradle_version_val=8.5"
      )

    assert has_element?(lv, "span", "gradle-8-build")
    refute has_element?(lv, "span", "gradle-7-build")
  end

  test "filters build runs by java version", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "java-17-build",
      java_version: "17.0.1"
    )

    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "java-21-build",
      java_version: "21.0.2"
    )

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs?filter_java_version_op==~&filter_java_version_val=17"
      )

    assert has_element?(lv, "span", "java-17-build")
    refute has_element?(lv, "span", "java-21-build")
  end

  test "search filters build runs by project name", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "my-android-app"
    )

    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "other-project"
    )

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs?search=my-android"
      )

    assert has_element?(lv, "span", "my-android-app")
    refute has_element?(lv, "span", "other-project")
  end
end
