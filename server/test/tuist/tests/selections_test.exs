defmodule Tuist.Tests.SelectionsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Tests.Selections
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.TestSelectionFixtures

  setup do
    %{project: ProjectsFixtures.project_fixture()}
  end

  defp decisions(project) do
    then(
      [
        %{
          decision: "selected",
          module_name: "SearchTests",
          suite_name: "SearchViewModelTests",
          name: "test_load()",
          duration: 300
        },
        %{
          decision: "skipped",
          module_name: "AuthTests",
          suite_name: "SessionTests",
          name: "test_refresh()",
          duration: 500
        },
        %{
          decision: "skipped",
          module_name: "AuthTests",
          suite_name: "SessionTests",
          name: "test_reset()",
          scheme: "Core",
          duration: 200
        },
        %{
          decision: "selected",
          module_name: "SearchTests",
          suite_name: "SearchViewTests",
          name: "test_body()",
          reason: "flaky",
          duration: 100
        }
      ],
      &TestSelectionFixtures.selection_fixture(project_id: project.id, git_commit_sha: "abc123", decisions: &1)
    )
  end

  describe "get/2" do
    test "returns the commit's latest plan", %{project: project} do
      TestSelectionFixtures.selection_fixture(
        project_id: project.id,
        git_commit_sha: "abc123",
        mode: "dry_run",
        inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60, :second)
      )

      latest = TestSelectionFixtures.selection_fixture(project_id: project.id, git_commit_sha: "abc123", mode: "enabled")

      assert {:ok, %{id: id, mode: "enabled"}} = Selections.get(project.id, "abc123")
      assert id == latest.id
      assert {:error, :not_found} = Selections.get(project.id, "missing")
    end
  end

  describe "summary/1" do
    test "adds up the plan's decisions", %{project: project} do
      selection = decisions(project)

      summary = Selections.summary(selection)

      assert summary.selected == 2
      assert summary.skipped == 2
      assert summary.skip_rate == 50.0
      assert summary.skipped_duration == 700
      assert summary.targets == 2
      assert summary.selected_targets == 1
      assert summary.schemes == ["App", "Core"]

      assert summary.reasons == [
               %{decision: "selected", reason: "covers_changed_file", count: 1},
               %{decision: "selected", reason: "flaky", count: 1},
               %{decision: "skipped", reason: "unaffected", count: 2}
             ]
    end
  end

  describe "decisions/2" do
    test "lists selected decisions first, then by name", %{project: project} do
      selection = decisions(project)

      {rows, meta} = Selections.decisions(selection)

      assert Enum.map(rows, &{&1.decision, &1.name}) == [
               {"selected", "test_load()"},
               {"selected", "test_body()"},
               {"skipped", "test_refresh()"},
               {"skipped", "test_reset()"}
             ]

      assert meta.total_count == 4
    end

    test "filters by decision, scheme and search, and sorts by duration", %{project: project} do
      selection = decisions(project)

      assert {[%{name: "test_reset()"}], _meta} = Selections.decisions(selection, scheme: "Core")

      assert {rows, _meta} = Selections.decisions(selection, decision: "skipped")
      assert Enum.map(rows, & &1.name) == ["test_refresh()", "test_reset()"]

      assert {[%{name: "test_body()"}], _meta} = Selections.decisions(selection, search: "viewtests")

      assert {rows, _meta} = Selections.decisions(selection, sort_by: "duration", sort_order: "desc")
      assert Enum.map(rows, & &1.duration) == [500, 300, 200, 100]
    end

    test "pages", %{project: project} do
      selection = decisions(project)

      {rows, meta} = Selections.decisions(selection, page: 2, page_size: 3)

      assert length(rows) == 1
      assert meta.total_pages == 2
      assert meta.current_page == 2
    end
  end

  describe "get_decision/2" do
    test "returns one of the plan's decisions", %{project: project} do
      selection = decisions(project)
      {[decision | _rest], _meta} = Selections.decisions(selection)

      assert {:ok, %{name: "test_load()"}} = Selections.get_decision(selection, decision.id)
      assert {:error, :not_found} = Selections.get_decision(selection, Ecto.UUID.generate())
      assert {:error, :not_found} = Selections.get_decision(selection, "not-a-uuid")
    end
  end

  describe "changed_files/2" do
    test "lists the files that selected tests first and filters by kind and path", %{project: project} do
      selection =
        TestSelectionFixtures.selection_fixture(
          project_id: project.id,
          changed_files: [
            %{path: "docs/README.md", kind: "ignored"},
            %{path: "Sources/Search/Search.swift", selected_count: 3},
            %{path: "Sources/Auth/Session.swift", selected_count: 1}
          ]
        )

      {rows, meta} = Selections.changed_files(selection)

      assert Enum.map(rows, & &1.path) == [
               "Sources/Search/Search.swift",
               "Sources/Auth/Session.swift",
               "docs/README.md"
             ]

      assert meta.total_count == 3
      assert {[%{path: "docs/README.md"}], _meta} = Selections.changed_files(selection, kind: "ignored")
      assert {[%{path: "Sources/Auth/Session.swift"}], _meta} = Selections.changed_files(selection, search: "auth")
    end
  end

  describe "list/2" do
    test "lists the project's plans newest first with their commits' test runs", %{project: project} do
      TestSelectionFixtures.selection_fixture(
        project_id: project.id,
        git_commit_sha: "older",
        git_branch: "feature/search",
        inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)
      )

      TestSelectionFixtures.selection_fixture(project_id: project.id, git_commit_sha: "newer", scope: "target")
      RunsFixtures.test_fixture(project_id: project.id, git_commit_sha: "older")
      RunsFixtures.test_fixture(project_id: project.id, git_commit_sha: "older")

      {rows, meta} = Selections.list(project.id)

      assert Enum.map(rows, &{&1.git_commit_sha, &1.test_runs_count}) == [{"newer", 0}, {"older", 2}]
      assert meta.total_count == 2
      assert {[%{git_commit_sha: "older"}], _meta} = Selections.list(project.id, search: "search")
      assert {[%{git_commit_sha: "newer"}], _meta} = Selections.list(project.id, search: "new")
      assert {[%{git_commit_sha: "newer"}], _meta} = Selections.list(project.id, scope: "target")
    end
  end

  describe "analytics/2" do
    test "adds up the period's plans", %{project: project} do
      decisions(project)

      now = DateTime.utc_now()
      analytics = Selections.analytics(project.id, {DateTime.add(now, -7, :day), DateTime.add(now, 60, :second)})

      assert analytics.totals.selections == 1
      assert analytics.totals.selected == 2
      assert analytics.totals.skipped == 2
      assert analytics.totals.skip_rate == 50.0
      assert Enum.sum(analytics.selected) == 2
      assert Enum.sum(analytics.skipped) == 2
      assert length(analytics.dates) == 8
    end
  end
end
