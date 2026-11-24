defmodule Tuist.Tests.Coverage.Comparison do
  @moduledoc """
  A commit's coverage against its pull request's base, as the pull request
  comment reports it (`Tuist.VCS`).

  Only a complete commit is compared (`Commits.status/1`): an in-progress
  one may still be missing schemes or shards, and an incomplete one's figure
  is a lower bound, so a change from either would mislead.

  The base is the commit the pull request branched from: the merge base the
  commit's runs reported (`test_runs.merge_base_sha`, from the client's
  `git merge-base` with the base branch) or, when none did, the merge base
  the commit graph gives with the base branch's head
  (`Tuist.GitHistory.merge_base/4`). When the base has no complete figure
  (its pipeline hasn't signalled completion, its figure is a lower bound, or
  no run measured it), the comparison falls back to the nearest commit on
  the base's first-parent chain that has one
  (`Commits.nearest_first_parent_in/3`): along the base branch, never into a
  branch merged into it, and never into the pull request's own commits,
  which descend from the base. With no such commit the change is unknown.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.History
  alias Tuist.Tests.CoverageCommit

  @doc """
  The commit's coverage compared with its base, or nil when no run gave the
  commit a figure. `status` is the commit's (`Commits.status/1`) and `head`
  its row with the figure it stands with (`History.with_coverage/1`). Only a
  `:complete` commit has the rest:

  - `requested_base_sha`: the pull request's base commit, nil when unknown;
  - `requested_base_measured`: whether a run gave `requested_base_sha` a
    figure, complete or not;
  - `base`: the commit compared with, `requested_base_sha` itself or its
    nearest first-parent ancestor with a complete figure, with `distance`
    commits between them; nil when there is none;
  - `change`: the change in percentage points from `base`, nil without one;
  - `targets`: every target of the commit with its `coverage` and its
    `change` from `base`, nil for a target the base didn't have;
  - `changed_files`: at most `:files` (10 by default) files whose coverage
    changed most from `base` (`Commits.changed_files/5`).
  """
  def compare(%Project{} = project, sha, opts \\ []) do
    case Commits.summary(project.id, sha) do
      nil ->
        nil

      summary ->
        head = History.with_coverage(summary)

        case Commits.status(summary) do
          :complete -> complete(project, head, Keyword.get(opts, :files, 10))
          status -> %{status: status, head: head}
        end
    end
  end

  defp complete(project, head, files) do
    requested = base_sha(project, head)
    base = requested && nearest_complete(project.id, head.git_repository_id, requested)

    [targets, base_targets, changed_files] =
      Tuist.Tasks.parallel_tasks([
        fn -> Commits.targets(project.id, head.git_commit_sha) end,
        fn -> if base, do: Commits.targets(project.id, base.git_commit_sha), else: [] end,
        fn ->
          if base, do: Commits.changed_files(project.id, base.git_commit_sha, head.git_commit_sha, files), else: []
        end
      ])

    %{
      status: :complete,
      head: head,
      requested_base_sha: requested,
      requested_base_measured: measured?(project, requested, base),
      base: base,
      change: base && Float.round(head.coverage - base.coverage, 1),
      targets: target_changes(targets, base && Map.new(base_targets, &{&1.name, &1})),
      changed_files: changed_files
    }
  end

  defp target_changes(targets, before) do
    Enum.map(targets, fn target ->
      coverage = Coverage.percentage(target.covered_lines, target.executable_lines)

      change =
        case before && Map.get(before, target.name) do
          %{executable_lines: executable} = previous when executable > 0 ->
            Float.round(coverage - Coverage.percentage(previous.covered_lines, executable), 1)

          _ ->
            nil
        end

      target |> Map.put(:coverage, coverage) |> Map.put(:change, change)
    end)
  end

  defp measured?(_project, nil, _base), do: false
  defp measured?(_project, sha, %{git_commit_sha: sha}), do: true
  defp measured?(project, sha, _base), do: not is_nil(Commits.summary(project.id, sha))

  defp base_sha(project, head) do
    reported_merge_base(head) || graph_merge_base(project, head)
  end

  # The newest one the commit's runs reported: runs of the same commit
  # against the same base branch report the same merge base, and a newer run
  # saw a base branch at least as far along.
  defp reported_merge_base(head) do
    ClickHouseRepo.one(
      from(t in Commits.measured_runs_query(head),
        where: t.merge_base_sha != "",
        order_by: [desc: t.inserted_at],
        limit: 1,
        select: t.merge_base_sha
      )
    )
  end

  defp graph_merge_base(_project, %{git_repository_id: repository_id}) when repository_id in [nil, 0], do: nil

  defp graph_merge_base(project, head) do
    branch = if head.base_branch in [nil, ""], do: project.default_branch, else: head.base_branch

    case GitHistory.ref(head.git_repository_id, branch) do
      %{head_sha: base_head} when is_binary(base_head) and base_head != head.git_commit_sha ->
        GitHistory.merge_base(head.git_repository_id, head.git_commit_sha, base_head)

      _ ->
        nil
    end
  end

  # The base itself when its figure is complete, which needs no graph, else
  # the nearest commit with one on its first-parent chain.
  defp nearest_complete(project_id, repository_id, sha) do
    complete =
      CoverageCommit
      |> where([c], c.project_id == ^project_id and c.complete)
      |> Commits.comparable()
      |> Commits.complete_figures()

    found =
      cond do
        Repo.exists?(where(complete, [c], c.git_commit_sha == ^sha)) ->
          {sha, 0}

        repository_id in [nil, 0] ->
          nil

        true ->
          Commits.nearest_first_parent_in(complete, repository_id, sha)
      end

    case found do
      nil ->
        nil

      {base_sha, distance} ->
        project_id |> Commits.summary(base_sha) |> History.with_coverage() |> Map.put(:distance, distance)
    end
  end
end
