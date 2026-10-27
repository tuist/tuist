defmodule TuistWeb.RunDetailLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias Tuist.CommandEvents
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    stub(CommandEvents, :has_result_bundle?, fn _ -> false end)
    %{conn: conn, user: user}
  end

  describe "run detail" do
    test "JSON comparison retains individual hash inputs and historical unknowns", %{
      conn: conn,
      organization: organization,
      project: project,
      user: user
    } do
      run = CommandEventsFixtures.command_event_fixture(project: project, name: "test", user_id: user.id)
      graph = XcodeFixtures.xcode_graph_fixture(command_event_id: run.id)
      xcode_project = XcodeFixtures.xcode_project_fixture(xcode_graph_id: graph.id)

      for {purpose, destinations} <- [{:binary_cache_hash, ["iPhone"]}, {:selective_testing_hash, ["mac"]}] do
        XcodeFixtures.xcode_target_fixture([
          {purpose, "hash"},
          {:name, "Target"},
          {:dependencies, ["Networking", "Core"]},
          {:xcode_project_id, xcode_project.id},
          {:destinations, ["iphone", "ipad", "mac"]},
          {:hashed_destinations, destinations},
          {:embedded_product_references_hash, ""},
          {:foreign_build_hash, "foreign"},
          {:test_device, ""},
          {:test_runtime, ""}
        ])

        XcodeFixtures.xcode_target_fixture([
          {purpose, "old"},
          {:name, "Historical"},
          {:xcode_project_id, xcode_project.id},
          {:destinations, ["iphone", "ipad", "mac"]}
        ])
      end

      for {tab, button, expected} <- [
            {"module-cache", "copy-binary-cache-json", ["iPhone"]},
            {"test-optimizations", "copy-selective-testing-json", ["mac"]}
          ] do
        {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/runs/#{run.id}?tab=#{tab}")

        [json] =
          lv |> render() |> Floki.parse_fragment!() |> Floki.find("##{button}") |> Floki.attribute("data-clipboard-value")

        targets = JSON.decode!(json)
        library = Enum.find(targets, &(&1["name"] == "Target"))
        historical = Enum.find(targets, &(&1["name"] == "Historical"))
        assert library["hashed_destinations"] == expected
        assert historical["hashed_destinations"] == nil
        assert Map.has_key?(historical, "hashed_destinations")
        assert library["embedded_product_references_hash"] == ""
        assert library["foreign_build_hash"] == "foreign"
        assert library["dependencies"] == ["Core", "Networking"]
        assert library["test_device"] == ""
        assert library["test_runtime"] == ""

        for field <- ["embedded_product_references_hash", "foreign_build_hash", "test_device", "test_runtime"] do
          assert historical[field] == nil
          assert Map.has_key?(historical, field)
        end

        refute Map.has_key?(library, "destinations")
        refute Map.has_key?(historical, "destinations")
      end
    end

    test "JSON comparison derives empty destination availability from the CLI version", %{
      conn: conn,
      organization: organization,
      project: project,
      user: user
    } do
      for {version, expected} <- [{"4.207.0", nil}, {"4.208.0", []}] do
        run =
          CommandEventsFixtures.command_event_fixture(
            project: project,
            name: "test",
            user_id: user.id,
            tuist_version: version
          )

        graph = XcodeFixtures.xcode_graph_fixture(command_event_id: run.id)
        xcode_project = XcodeFixtures.xcode_project_fixture(xcode_graph_id: graph.id)

        for purpose <- [:binary_cache_hash, :selective_testing_hash] do
          XcodeFixtures.xcode_target_fixture([{purpose, "hash"}, {:xcode_project_id, xcode_project.id}])
        end

        for {tab, button} <- [
              {"module-cache", "copy-binary-cache-json"},
              {"test-optimizations", "copy-selective-testing-json"}
            ] do
          {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/runs/#{run.id}?tab=#{tab}")

          [json] =
            lv
            |> render()
            |> Floki.parse_fragment!()
            |> Floki.find("##{button}")
            |> Floki.attribute("data-clipboard-value")

          assert [%{"hashed_destinations" => ^expected}] = JSON.decode!(json)
        end
      end
    end

    test "shows details of a test run", %{
      conn: conn,
      organization: organization,
      project: project,
      user: user
    } do
      # Given
      test_run =
        CommandEventsFixtures.command_event_fixture(
          project: project,
          name: "test",
          command_arguments: ["test", "App"],
          test_targets: ["AppTests"],
          user_id: user.id
        )

      xcode_graph = XcodeFixtures.xcode_graph_fixture(command_event_id: test_run.id)

      xcode_project =
        XcodeFixtures.xcode_project_fixture(xcode_graph_id: xcode_graph.id)

      _xcode_target =
        XcodeFixtures.xcode_target_fixture(
          name: "AppTests",
          xcode_project_id: xcode_project.id,
          selective_testing_hash: "AppTests-hash"
        )

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/runs/#{test_run.id}")

      # Then
      assert has_element?(lv, "span", "Selective Testing")
      assert has_element?(lv, "span", "tuist test App")
    end

    test "shows details of a cache run", %{
      conn: conn,
      organization: organization,
      project: project,
      user: user
    } do
      # Given
      cache_run =
        CommandEventsFixtures.command_event_fixture(
          project: project,
          name: "cache",
          command_arguments: ["cache"],
          cacheable_targets: ["Framework"],
          user_id: user.id
        )

      xcode_graph = XcodeFixtures.xcode_graph_fixture(command_event_id: cache_run.id)

      xcode_project =
        XcodeFixtures.xcode_project_fixture(xcode_graph_id: xcode_graph.id)

      _xcode_target =
        XcodeFixtures.xcode_target_fixture(
          name: "AppTests",
          xcode_project_id: xcode_project.id,
          binary_cache_hash: "AppTests-hash"
        )

      # When
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/runs/#{cache_run.id}?tab=module-cache"
        )

      # Then
      assert has_element?(lv, "span", "Module Cache")
      assert has_element?(lv, "table span", "AppTests")
      assert has_element?(lv, "table span", "AppTests-hash")
    end

    test "shows CI run without user", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      ci_run =
        CommandEventsFixtures.command_event_fixture(
          project: project,
          name: "cache",
          is_ci: true,
          user_id: nil,
          cacheable_targets: ["Framework"]
        )

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/runs/#{ci_run.id}")

      # Then
      assert has_element?(lv, "h1", "tuist cache")
      assert has_element?(lv, "[data-part=\"metadata\"]", "Ran by")
      # Should show CI badge for runs without a user
      assert has_element?(lv, ".noora-badge", "CI")
    end

    test "shows download result button when available", %{
      conn: conn,
      organization: organization,
      project: project,
      user: user
    } do
      # Given
      stub(CommandEvents, :has_result_bundle?, fn _ -> true end)

      test_run =
        with_flushed_ingestion_buffers(fn ->
          CommandEventsFixtures.command_event_fixture(
            project: project,
            name: "test",
            cacheable_targets: ["Framework"],
            user_id: user.id
          )
        end)

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/runs/#{test_run.id}")

      # Then
      assert has_element?(lv, ".noora-button", "Download result")
    end

    test "filters selective testing modules by hit", %{
      conn: conn,
      organization: organization,
      project: project,
      user: user
    } do
      # Given
      test_run =
        CommandEventsFixtures.command_event_fixture(
          project: project,
          name: "test",
          command_arguments: ["test", "App"],
          test_targets: ["AppTests", "FrameworkTests", "UtilsTests"],
          user_id: user.id
        )

      xcode_graph = XcodeFixtures.xcode_graph_fixture(command_event_id: test_run.id)

      xcode_project =
        XcodeFixtures.xcode_project_fixture(xcode_graph_id: xcode_graph.id)

      _local =
        XcodeFixtures.xcode_target_fixture(
          name: "AppTests",
          xcode_project_id: xcode_project.id,
          selective_testing_hash: "AppTests-hash",
          selective_testing_hit: :local
        )

      _remote =
        XcodeFixtures.xcode_target_fixture(
          name: "FrameworkTests",
          xcode_project_id: xcode_project.id,
          selective_testing_hash: "FrameworkTests-hash",
          selective_testing_hit: :remote
        )

      _miss =
        XcodeFixtures.xcode_target_fixture(
          name: "UtilsTests",
          xcode_project_id: xcode_project.id,
          selective_testing_hash: "UtilsTests-hash",
          selective_testing_hit: :miss
        )

      # When (no filter)
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/runs/#{test_run.id}?tab=test-optimizations"
        )

      # Then all three modules are listed
      assert has_element?(lv, "#selective-testing-table span", "AppTests")
      assert has_element?(lv, "#selective-testing-table span", "FrameworkTests")
      assert has_element?(lv, "#selective-testing-table span", "UtilsTests")

      # When filtering by :miss
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/runs/#{test_run.id}?tab=test-optimizations&filter_selective_testing_hit_op===&filter_selective_testing_hit_val=miss"
        )

      # Then only the miss module is listed
      refute has_element?(lv, "#selective-testing-table span", "AppTests")
      refute has_element?(lv, "#selective-testing-table span", "FrameworkTests")
      assert has_element?(lv, "#selective-testing-table span", "UtilsTests")
    end

    test "does not show download result button when not available", %{
      conn: conn,
      organization: organization,
      project: project,
      user: user
    } do
      # Given
      stub(CommandEvents, :has_result_bundle?, fn _ -> false end)

      test_run =
        CommandEventsFixtures.command_event_fixture(
          project: project,
          name: "test",
          cacheable_targets: ["Framework"],
          user_id: user.id
        )

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/runs/#{test_run.id}")

      # Then
      refute has_element?(lv, ".noora-button", "Download result")
    end
  end
end
