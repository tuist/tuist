defmodule TuistWeb.GenerateRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runs.Analytics, as: RunsAnalytics
  alias TuistTestSupport.Fixtures.CommandEventsFixtures

  describe "lists latest generate runs" do
    setup do
      copy(RunsAnalytics)

      stub(RunsAnalytics, :runs_analytics, fn _, _, _ ->
        %{runs_per_period: %{}, dates: [], values: [], count: 0, trend: 0}
      end)

      stub(RunsAnalytics, :runs_duration_analytics, fn _, _ -> %{dates: [], values: []} end)
      :ok
    end

    test "lists latest generate runs", %{
      conn: conn,
      user: user,
      organization: organization,
      project: project
    } do
      # Given
      _generate_run_one =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          user_id: user.id,
          name: "generate",
          command_arguments: ["generate", "App"]
        )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "generate",
        command_arguments: ["generate", "AppTwo"]
      )

      _generate_run_one =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          user_id: user.id,
          name: "generate",
          command_arguments: ["generate", "App"]
        )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "generate",
        command_arguments: ["generate", "AppTwo"]
      )

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/module-cache/generate-runs")

      # Then
      assert has_element?(lv, "span", "generate App")
      assert has_element?(lv, "span", "generate AppTwo")
    end

    test "handles cursor mismatch when sort order changes", %{
      conn: conn,
      user: user,
      organization: organization,
      project: project
    } do
      for i <- 1..25 do
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          user_id: user.id,
          name: "generate",
          command_arguments: ["generate", "App-#{i}"],
          duration: i * 1000
        )
      end

      # Generate a cursor with created_at sorting
      {_events, %{end_cursor: cursor}} =
        Tuist.CommandEvents.list_command_events(%{
          filters: [
            %{field: :project_id, op: :==, value: project.id},
            %{field: :name, op: :in, value: ["generate"]}
          ],
          order_by: [:created_at],
          order_directions: [:desc],
          first: 20
        })

      # Navigate with duration sorting but use the cursor from created_at sorting
      # Before the fix, this would raise Flop.InvalidParamsError
      assert {:ok, lv, _html} =
               live(
                 conn,
                 ~p"/#{organization.account.name}/#{project.name}/module-cache/generate-runs?generate_runs_sort_by=duration&generate_runs_sort_order=asc&after=#{cursor}"
               )

      assert has_element?(lv, "span", "generate App-1")
    end

    test "filters generate runs by user with ran_by filter", %{
      conn: conn,
      user: user,
      organization: organization,
      project: project
    } do
      other_user = TuistTestSupport.Fixtures.AccountsFixtures.user_fixture()
      :ok = Tuist.Accounts.add_user_to_organization(other_user, organization)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "generate",
        command_arguments: ["generate", "UserApp"]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: other_user.id,
        name: "generate",
        command_arguments: ["generate", "OtherUserApp"]
      )

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/module-cache/generate-runs?filter_ran_by_op===&filter_ran_by_val=#{user.id}"
        )

      assert has_element?(lv, "span", "generate UserApp")
      refute has_element?(lv, "span", "generate OtherUserApp")
    end

    test "filters generate runs by displayed command", %{
      conn: conn,
      user: user,
      organization: organization,
      project: project
    } do
      matching_run =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          user_id: user.id,
          name: "generate",
          command_arguments: ["generate", "--configuration", "DebugStaging"]
        )

      other_run =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          user_id: user.id,
          name: "generate",
          command_arguments: ["generate", "--configuration", "Release"]
        )

      query =
        URI.encode_query(%{
          "filter_name_op" => "==",
          "filter_name_val" => "tuist generate --configuration DebugStaging"
        })

      {:ok, lv, _html} =
        live(
          conn,
          "/#{organization.account.name}/#{project.name}/module-cache/generate-runs?#{query}"
        )

      assert has_element?(lv, "tr##{matching_run.id}")
      refute has_element?(lv, "tr##{other_run.id}")
    end

    test "filters generate runs when the command filter contains only the tuist prefix", %{
      conn: conn,
      user: user,
      organization: organization,
      project: project
    } do
      generate_run =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          user_id: user.id,
          name: "generate",
          command_arguments: ["generate", "--configuration", "DebugStaging"]
        )

      query =
        URI.encode_query(%{
          "filter_name_op" => "=~",
          "filter_name_val" => "tuist"
        })

      {:ok, lv, _html} =
        live(
          conn,
          "/#{organization.account.name}/#{project.name}/module-cache/generate-runs?#{query}"
        )

      assert has_element?(lv, "tr##{generate_run.id}")
    end

    test "displays the command name when generate run arguments are empty", %{
      conn: conn,
      user: user,
      organization: organization,
      project: project
    } do
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "generate",
        command_arguments: []
      )

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/module-cache/generate-runs")

      assert has_element?(lv, "span", "tuist generate")
    end

    test "truncates the command column for runs with a long argument list", %{
      conn: conn,
      user: user,
      organization: organization,
      project: project
    } do
      # Given - a generate run with many target arguments, which otherwise widens the command
      # column unbounded and pushes every other column off-screen.
      targets = Enum.map(1..40, &"Target#{&1}")

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "generate",
        command_arguments: ["generate" | targets]
      )

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/module-cache/generate-runs")

      # Then - the command cell truncates (the default for text_and_description cells) so the
      # column can no longer grow unbounded.
      assert has_element?(
               lv,
               ~s([data-part="cell"][data-type="text_and_description"][data-truncate]),
               "generate Target1"
             )
    end

    test "filters generate runs whose branch does not contain a substring", %{
      conn: conn,
      user: user,
      organization: organization,
      project: project
    } do
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "generate",
        command_arguments: ["generate", "QueuedApp"],
        git_branch: "feature/gh-readonly-queue/main"
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "generate",
        command_arguments: ["generate", "RegularApp"],
        git_branch: "feature/main"
      )

      query =
        URI.encode_query(%{
          "filter_git_branch_op" => "!=~",
          "filter_git_branch_val" => "gh-readonly-queue"
        })

      {:ok, lv, html} =
        live(
          conn,
          "/#{organization.account.name}/#{project.name}/module-cache/generate-runs?#{query}"
        )

      assert html =~ "does not contain"
      assert has_element?(lv, "span", "generate RegularApp")
      refute has_element?(lv, "span", "generate QueuedApp")
    end
  end
end
