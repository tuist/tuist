defmodule TuistTestSupport.Fixtures.TestSelectionFixtures do
  @moduledoc """
  Fixtures for test selection plans, their decisions and changed files.
  """
  alias Tuist.IngestRepo
  alias Tuist.Tests.TestSelection
  alias Tuist.Tests.TestSelectionChangedFile
  alias Tuist.Tests.TestSelectionDecision

  @doc """
  Inserts a plan for `project_id` with the given `decisions` (maps over a
  decision's fields; `decision`, `module_name` and `name` at least) and
  `changed_files` (maps with `path` at least), and returns the plan.
  """
  def selection_fixture(attrs \\ []) do
    project_id = Keyword.fetch!(attrs, :project_id)
    id = Keyword.get(attrs, :id, UUIDv7.generate())
    inserted_at = Keyword.get(attrs, :inserted_at, NaiveDateTime.utc_now())

    decisions =
      attrs
      |> Keyword.get(:decisions, [])
      |> Enum.map(fn decision ->
        Map.merge(
          %{
            id: UUIDv7.generate(),
            test_selection_id: id,
            project_id: project_id,
            scheme: "App",
            scope_kind: Keyword.get(attrs, :scope, "test"),
            module_name: "AppTests",
            suite_name: "",
            name: "",
            test_case_id: nil,
            source_path: "Tests/AppTests/AppTests.swift",
            reason: if(decision[:decision] == "selected", do: "covers_changed_file", else: "unaffected"),
            covered_paths: [],
            changed_paths: [],
            evidence_test_run_id: nil,
            duration: 100,
            inserted_at: inserted_at
          },
          decision
        )
      end)

    changed_files =
      attrs
      |> Keyword.get(:changed_files, [])
      |> Enum.map(
        &Map.merge(
          %{
            test_selection_id: id,
            project_id: project_id,
            status: "modified",
            kind: "source",
            selected_count: 0,
            inserted_at: inserted_at
          },
          &1
        )
      )

    count = fn value -> Enum.count(decisions, &(&1.decision == value)) end

    selection = %{
      id: id,
      project_id: project_id,
      git_commit_sha: Keyword.get(attrs, :git_commit_sha, "a1b2c3d4e5f6"),
      git_branch: Keyword.get(attrs, :git_branch, "main"),
      scope: Keyword.get(attrs, :scope, "test"),
      mode: Keyword.get(attrs, :mode, "dry_run"),
      baseline_commit_sha: Keyword.get(attrs, :baseline_commit_sha, "0f0f0f0f0f0f"),
      fallback_reason: Keyword.get(attrs, :fallback_reason, ""),
      selected_count: count.("selected"),
      skipped_count: count.("skipped"),
      changed_files_count: length(changed_files),
      skipped_duration: decisions |> Enum.filter(&(&1.decision == "skipped")) |> Enum.map(& &1.duration) |> Enum.sum(),
      inserted_at: inserted_at
    }

    IngestRepo.insert_all(TestSelection, [selection])
    if decisions != [], do: IngestRepo.insert_all(TestSelectionDecision, decisions)
    if changed_files != [], do: IngestRepo.insert_all(TestSelectionChangedFile, changed_files)

    struct(TestSelection, selection)
  end
end
