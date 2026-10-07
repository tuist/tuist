defmodule TuistWeb.ProjectBundleSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias Tuist.Bundles
  alias Tuist.Projects
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.BundlesFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "create threshold" do
    for metric <- ["install_size", "download_size"] do
      @metric metric
      test "creates an absolute #{@metric} limit in decimal MB", %{
        conn: conn,
        organization: organization,
        project: project
      } do
        {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")
        render_hook(lv, "open_create_threshold_modal")
        render_hook(lv, "update_create_form_name", %{"value" => "Absolute"})
        render_hook(lv, "update_create_form_metric", %{"metric" => @metric})
        render_hook(lv, "update_create_form_unit", %{"unit" => "megabytes"})
        render_hook(lv, "update_create_form_deviation", %{"value" => "1.5"})
        html = render_hook(lv, "create_threshold")

        assert [threshold] = Bundles.get_project_bundle_thresholds(project)
        assert threshold.metric == String.to_existing_atom(@metric)
        assert threshold.deviation_bytes == 1_500_000
        assert is_nil(threshold.deviation_percentage)
        assert html =~ "1.5 MB"
      end
    end

    test "invalid limits never save a stale value", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")
      render_hook(lv, "update_create_form_name", %{"value" => "Invalid"})

      for {unit, values} <- [
            {"percentage", ["", "0", "-1", "0.47oops", 5]},
            {"megabytes", ["", "0", "-1", "1.5MB", "0.0000001", "9223372036854.775808", "NaN", "Infinity"]}
          ],
          value <- values do
        render_hook(lv, "update_create_form_unit", %{"unit" => unit})
        render_hook(lv, "update_create_form_deviation", %{"value" => "1.5"})
        render_hook(lv, "update_create_form_deviation", %{"value" => value})
        html = render_hook(lv, "create_threshold")
        assert html =~ "Enter a valid size threshold."
        assert Bundles.get_project_bundle_thresholds(project) == []
      end
    end

    test "escapes draft values in the threshold description", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")
      html = render_hook(lv, "update_create_form_deviation", %{"value" => "<script>alert(1)</script>"})
      assert html =~ "&lt;script&gt;"
      refute html =~ "<script>alert(1)</script>"
    end

    test "resets the unit on dismissal and reopening", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")
      render_hook(lv, "update_create_form_unit", %{"unit" => "megabytes"})
      render_hook(lv, "close_create_threshold_modal")
      render_hook(lv, "open_create_threshold_modal")
      render_hook(lv, "update_create_form_name", %{"value" => "Default"})
      render_hook(lv, "create_threshold")
      assert [threshold] = Bundles.get_project_bundle_thresholds(project)
      assert threshold.deviation_percentage == 5.0
      assert is_nil(threshold.deviation_bytes)
    end

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
    test "preserves percentages and switches units in both directions", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      threshold = BundlesFixtures.bundle_threshold_fixture(project: project, deviation_percentage: 0.47)
      {:ok, lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")
      assert html =~ "0.47%"
      render_hook(lv, "update_edit_form_name", %{"id" => threshold.id, "value" => "Renamed"})
      render_hook(lv, "update_threshold", %{"id" => threshold.id})
      assert {:ok, %{deviation_percentage: 0.47, deviation_bytes: nil}} = Bundles.get_bundle_threshold(threshold.id)

      render_hook(lv, "update_edit_form_unit", %{"id" => threshold.id, "unit" => "megabytes"})
      render_hook(lv, "update_edit_form_deviation", %{"id" => threshold.id, "value" => "1.500001"})
      render_hook(lv, "update_threshold", %{"id" => threshold.id})
      assert {:ok, %{deviation_percentage: nil, deviation_bytes: 1_500_001}} = Bundles.get_bundle_threshold(threshold.id)

      render_hook(lv, "update_edit_form_name", %{"id" => threshold.id, "value" => "Absolute renamed"})
      render_hook(lv, "update_threshold", %{"id" => threshold.id})
      assert {:ok, %{deviation_bytes: 1_500_001}} = Bundles.get_bundle_threshold(threshold.id)

      render_hook(lv, "update_edit_form_unit", %{"id" => threshold.id, "unit" => "percentage"})
      render_hook(lv, "update_edit_form_deviation", %{"id" => threshold.id, "value" => "0.47"})
      render_hook(lv, "update_threshold", %{"id" => threshold.id})
      assert {:ok, %{deviation_percentage: 0.47, deviation_bytes: nil}} = Bundles.get_bundle_threshold(threshold.id)
    end

    test "invalid edits preserve the persisted rule and cancellation restores it", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      threshold = BundlesFixtures.bundle_threshold_fixture(project: project, deviation_bytes: 1_500_001)
      {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")

      for value <- ["", "0", "-1", "1.5MB", "0.0000001", "9223372036854.775808", "NaN", "Infinity", 5] do
        render_hook(lv, "update_edit_form_deviation", %{"id" => threshold.id, "value" => value})
        html = render_hook(lv, "update_threshold", %{"id" => threshold.id})
        assert html =~ "Enter a valid size threshold."
        assert {:ok, ^threshold} = Bundles.get_bundle_threshold(threshold.id)
      end

      render_hook(lv, "close_edit_threshold_modal", %{"id" => threshold.id})
      render_hook(lv, "update_threshold", %{"id" => threshold.id})
      assert {:ok, %{deviation_bytes: 1_500_001}} = Bundles.get_bundle_threshold(threshold.id)
    end

    test "changing units requires a new value instead of reinterpreting the old limit", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      threshold = BundlesFixtures.bundle_threshold_fixture(project: project, deviation_percentage: 0.47)
      {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")
      render_hook(lv, "update_edit_form_unit", %{"id" => threshold.id, "unit" => "megabytes"})
      html = render_hook(lv, "update_threshold", %{"id" => threshold.id})
      assert html =~ "Enter a valid size threshold."
      assert {:ok, ^threshold} = Bundles.get_bundle_threshold(threshold.id)
      render_hook(lv, "update_create_form_name", %{"value" => "New absolute"})
      render_hook(lv, "update_create_form_unit", %{"unit" => "megabytes"})
      render_hook(lv, "create_threshold")
      assert Bundles.get_project_bundle_thresholds(project) == [threshold]
    end

    test "clears validation errors when the user corrects the form", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      threshold = BundlesFixtures.bundle_threshold_fixture(project: project, deviation_bytes: 1_500_000)
      {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")
      render_hook(lv, "update_create_form_deviation", %{"value" => ""})
      assert render_hook(lv, "create_threshold") =~ "Enter a valid size threshold."
      refute render_hook(lv, "update_create_form_deviation", %{"value" => "0.47"}) =~ "Enter a valid size threshold."

      render_hook(lv, "update_edit_form_name", %{"id" => threshold.id, "value" => ""})
      assert render_hook(lv, "update_threshold", %{"id" => threshold.id}) =~ "The size threshold could not be saved."

      refute render_hook(lv, "update_edit_form_name", %{"id" => threshold.id, "value" => "Valid"}) =~
               "The size threshold could not be saved."
    end

    test "reports changeset failures separately from invalid limits", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      threshold = BundlesFixtures.bundle_threshold_fixture(project: project, deviation_percentage: 0.47)
      {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")
      html = render_hook(lv, "create_threshold")
      assert html =~ "The size threshold could not be saved."
      render_hook(lv, "update_edit_form_name", %{"id" => threshold.id, "value" => ""})
      html = render_hook(lv, "update_threshold", %{"id" => threshold.id})
      assert html =~ "The size threshold could not be saved."
      assert {:ok, ^threshold} = Bundles.get_bundle_threshold(threshold.id)
    end

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

      expect(VCS, :get_user_by_username, fn _ -> {:ok, %VCS.User{id: "583231", username: "octocat"}} end)

      render_hook(lv, "select_approval_policy", %{"policy" => "selected"})
      render_hook(lv, "open_add_approver_modal")
      render_hook(lv, "update_approver_handle", %{"value" => "octocat"})
      render_hook(lv, "add_approver")

      assert [approver] = Bundles.list_bundle_size_approvers(project)
      assert approver.github_handle == "octocat"
      assert approver.github_id == "583231"

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

      expect(VCS, :get_user_by_username, fn _ -> {:error, :not_found} end)

      render_hook(lv, "select_approval_policy", %{"policy" => "selected"})
      render_hook(lv, "open_add_approver_modal")
      render_hook(lv, "update_approver_handle", %{"value" => "ghost"})
      html = render_hook(lv, "add_approver")

      assert Bundles.list_bundle_size_approvers(project) == []
      assert html =~ "No GitHub user with that username"
    end

    test "explains that the project needs a GitHub connection before approvers can be added", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")

      expect(VCS, :get_user_by_username, fn _ -> {:error, :no_vcs_connection} end)

      render_hook(lv, "select_approval_policy", %{"policy" => "selected"})
      render_hook(lv, "open_add_approver_modal")
      render_hook(lv, "update_approver_handle", %{"value" => "octocat"})
      html = render_hook(lv, "add_approver")

      assert Bundles.list_bundle_size_approvers(project) == []
      assert html =~ "Connect the Tuist GitHub App"
    end

    test "surfaces an unreachable GitHub as something to retry, not a missing account", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")

      expect(VCS, :get_user_by_username, fn _ -> {:error, :unavailable} end)

      render_hook(lv, "select_approval_policy", %{"policy" => "selected"})
      render_hook(lv, "open_add_approver_modal")
      render_hook(lv, "update_approver_handle", %{"value" => "octocat"})
      html = render_hook(lv, "add_approver")

      assert Bundles.list_bundle_size_approvers(project) == []
      assert html =~ "Couldn&#39;t reach GitHub"
    end

    test "clears the pending username when the modal is dismissed", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")

      render_hook(lv, "select_approval_policy", %{"policy" => "selected"})
      # Not the field's placeholder, which is always present in the markup.
      render_hook(lv, "open_add_approver_modal")
      render_hook(lv, "update_approver_handle", %{"value" => "ramonarguello"})
      render_hook(lv, "close_add_approver_modal")
      html = render_hook(lv, "open_add_approver_modal")

      assert Bundles.list_bundle_size_approvers(project) == []
      refute html =~ "ramonarguello"
    end

    test "does not allow removing an approver from a different project", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      other_project = ProjectsFixtures.project_fixture()

      approver = BundlesFixtures.bundle_size_approver_fixture(project: other_project, github_handle: "octocat")

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/bundles")

      render_hook(lv, "delete_approver", %{"approver_id" => approver.id})

      assert Bundles.list_bundle_size_approvers(other_project) == [approver]
    end
  end
end
