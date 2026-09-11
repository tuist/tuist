defmodule Tuist.Marketing.BazelShowcaseTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Bazel
  alias Tuist.Bazel.Invocation
  alias Tuist.Marketing.BazelShowcase
  alias Tuist.ReapiCache
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "load/1" do
    test "returns not found when the project doesn't exist" do
      assert BazelShowcase.load("missing/project") == {:error, :not_found}
    end

    test "returns not found for a malformed handle" do
      assert BazelShowcase.load("missing") == {:error, :not_found}
    end

    test "aggregates the project's Bazel analytics without identifying fields" do
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)
      project_id = project.id

      stub(Bazel, :summary, fn ^project_id, _opts ->
        %{total: 4, successful: 3, failed: 1, median_duration_ms: 1200}
      end)

      stub(ReapiCache, :summary, fn ^project_id, _opts -> %{hit_rate: 82.5} end)

      stub(Bazel, :recent_invocations, fn ^project_id, opts ->
        assert Keyword.get(opts, :limit) == 30

        [
          %{
            command: "build",
            status: "success",
            duration_ms: 1000,
            finished_at: ~N[2026-09-10 12:00:00],
            git_branch: "feature/secret",
            git_commit_sha: "abc123",
            target_patterns: ["//app:all"],
            cache: %{}
          }
        ]
      end)

      assert {:ok, data} = BazelShowcase.load("#{project.account.name}/#{project.name}")

      assert data.invocations == 4
      assert data.success_rate == 75.0
      assert data.median_duration_ms == 1200
      assert data.cache_hit_rate == 82.5

      assert data.recent_invocations == [
               %{command: "build", status: "success", duration_ms: 1000, finished_at: ~N[2026-09-10 12:00:00]}
             ]
    end

    test "reports no success rate when there are no invocations" do
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

      stub(Bazel, :summary, fn _project_id, _opts ->
        %{total: 0, successful: 0, failed: 0, median_duration_ms: 0}
      end)

      stub(ReapiCache, :summary, fn _project_id, _opts -> %{hit_rate: nil} end)
      stub(Bazel, :recent_invocations, fn _project_id, _opts -> [] end)

      assert {:ok, data} = BazelShowcase.load("#{project.account.name}/#{project.name}")

      assert data.success_rate == nil
      assert data.cache_hit_rate == nil
      assert data.recent_invocations == []
    end
  end

  describe "load_timeline_invocation/1" do
    test "returns not found when the project doesn't exist" do
      assert BazelShowcase.load_timeline_invocation("missing/project") == {:error, :not_found}
    end

    test "picks the recent invocation with the richest timeline, preferring the newest on ties" do
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)
      project_id = project.id

      stub(Bazel, :recent_invocations, fn ^project_id, opts ->
        assert Keyword.get(opts, :limit) == 50

        [
          %Invocation{invocation_id: "newest-without-timeline", build_timeline_span_start_ms: []},
          %Invocation{invocation_id: "newer", build_timeline_span_start_ms: [0, 10]},
          %Invocation{invocation_id: "richest", build_timeline_span_start_ms: [0, 10, 20]},
          %Invocation{invocation_id: "older-tie", build_timeline_span_start_ms: [0, 10, 20]}
        ]
      end)

      assert {:ok, %{project: %{id: ^project_id}, invocation: %Invocation{invocation_id: "richest"}}} =
               BazelShowcase.load_timeline_invocation("#{project.account.name}/#{project.name}")
    end

    test "returns not found when no recent invocation has a timeline" do
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

      stub(Bazel, :recent_invocations, fn _project_id, _opts ->
        [%Invocation{invocation_id: "without-timeline", build_timeline_span_start_ms: []}]
      end)

      assert BazelShowcase.load_timeline_invocation("#{project.account.name}/#{project.name}") ==
               {:error, :not_found}
    end
  end
end
