defmodule TuistWeb.ProjectBundleSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias Tuist.Bundles
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.BundlesFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "create threshold" do
    test "creates a threshold via the modal", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")

      render_hook(lv, "open_create_threshold_modal")
      render_hook(lv, "update_create_form_name", %{"value" => "My Threshold"})
      render_hook(lv, "update_create_form_metric", %{"metric" => "install_size"})
      render_hook(lv, "update_create_form_deviation", %{"value" => "10.0"})
      render_hook(lv, "update_create_form_baseline_branch", %{"value" => "main"})
      render_hook(lv, "create_threshold")

      thresholds = Bundles.get_project_bundle_thresholds(project)
      assert length(thresholds) == 1
      assert hd(thresholds).name == "My Threshold"
      assert hd(thresholds).deviation_percentage == 10.0
    end
  end

  describe "update threshold" do
    test "updates a threshold", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      threshold = BundlesFixtures.bundle_threshold_fixture(project: project, name: "Original")

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")

      render_hook(lv, "update_edit_form_name", %{"id" => threshold.id, "value" => "Updated"})
      render_hook(lv, "update_threshold", %{"id" => threshold.id})

      {:ok, updated} = Bundles.get_bundle_threshold(threshold.id)
      assert updated.name == "Updated"
    end

    test "does not allow updating a threshold from a different project", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      other_threshold = BundlesFixtures.bundle_threshold_fixture(name: "Other")

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")

      render_hook(lv, "update_threshold", %{"id" => other_threshold.id})

      {:ok, unchanged} = Bundles.get_bundle_threshold(other_threshold.id)
      assert unchanged.name == "Other"
    end
  end

  describe "delete threshold" do
    test "deletes a threshold", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      threshold = BundlesFixtures.bundle_threshold_fixture(project: project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")

      render_hook(lv, "delete_threshold", %{"threshold_id" => threshold.id})

      assert {:error, :not_found} = Bundles.get_bundle_threshold(threshold.id)
    end

    test "does not allow deleting a threshold from a different project", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      other_threshold = BundlesFixtures.bundle_threshold_fixture()

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")

      render_hook(lv, "delete_threshold", %{"threshold_id" => other_threshold.id})

      assert {:ok, _} = Bundles.get_bundle_threshold(other_threshold.id)
    end
  end

  describe "approvals" do
    test "changes the approval policy", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")

      html = render_hook(lv, "select_approval_policy", %{"policy" => "selected"})

      assert Projects.get_project_by_id(project.id).bundle_size_approval_policy == :selected
      assert html =~ "Approvers"
    end

    test "adds and removes an approver", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")

      render_hook(lv, "select_approval_policy", %{"policy" => "selected"})
      render_hook(lv, "update_approver_handle", %{"value" => "octocat"})
      render_hook(lv, "add_approver")

      assert [approver] = Bundles.list_bundle_size_approvers(project)
      assert approver.github_handle == "octocat"

      render_hook(lv, "delete_approver", %{"approver_id" => approver.id})

      assert Bundles.list_bundle_size_approvers(project) == []
    end

    test "surfaces an invalid GitHub username instead of adding it", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")

      render_hook(lv, "select_approval_policy", %{"policy" => "selected"})
      render_hook(lv, "update_approver_handle", %{"value" => "not a login"})
      html = render_hook(lv, "add_approver")

      assert Bundles.list_bundle_size_approvers(project) == []
      assert html =~ "valid GitHub username"
    end

    test "does not allow removing an approver from a different project", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      other_project = ProjectsFixtures.project_fixture()

      {:ok, approver} =
        Bundles.create_bundle_size_approver(%{project_id: other_project.id, github_handle: "octocat"})

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")

      render_hook(lv, "delete_approver", %{"approver_id" => approver.id})

      assert Bundles.list_bundle_size_approvers(other_project) == [approver]
    end
  end
end
