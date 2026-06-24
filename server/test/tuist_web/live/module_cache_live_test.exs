defmodule TuistWeb.ModuleCacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistWeb.Runs.ModuleCacheTab

  describe "module cache page" do
    test "displays analytics widgets", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-01-01 10:20:30Z] end)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: ["C"],
        created_at: ~N[2024-01-01 03:00:00]
      )

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/module-cache")

      # Then
      assert has_element?(lv, "#widget-cache-hit-rate")
      assert has_element?(lv, "#widget-cache-hits")
      assert has_element?(lv, "#widget-cache-misses")
    end
  end

  describe "subhashes_list/1" do
    test "renders destinations in a deterministic sorted order regardless of input order" do
      # Given
      target_a = target_fixture(destinations: ["mac_with_ipad_design", "iphone", "ipad"])
      target_b = target_fixture(destinations: ["ipad", "mac_with_ipad_design", "iphone"])

      # When
      html_a = render_component(&ModuleCacheTab.subhashes_list/1, target: target_a)
      html_b = render_component(&ModuleCacheTab.subhashes_list/1, target: target_b)

      # Then
      assert html_a =~ "iPad, iPhone, Mac with iPad design"
      assert html_a == html_b
    end
  end

  defp target_fixture(attrs) do
    Map.merge(
      %{
        name: "AnalyticsSharedTypes",
        binary_cache_hit: 0,
        binary_cache_hash: "hash",
        product: "",
        product_name: "",
        bundle_id: "",
        external_hash: "",
        sources_hash: "",
        resources_hash: "",
        copy_files_hash: "",
        core_data_models_hash: "",
        target_scripts_hash: "",
        environment_hash: "",
        headers_hash: "",
        deployment_target_hash: "",
        info_plist_hash: "",
        entitlements_hash: "",
        dependencies_hash: "",
        project_settings_hash: "",
        target_settings_hash: "",
        buildable_folders_hash: "",
        destinations: [],
        additional_strings: []
      },
      Map.new(attrs)
    )
  end
end
