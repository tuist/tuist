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

    test "returns not found for a private project" do
      project = private_project()

      assert BazelShowcase.load("#{project.account.name}/#{project.name}") == {:error, :not_found}
    end

    test "aggregates the project's Bazel analytics without identifying fields" do
      project = public_project()
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
      project = public_project()

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

    test "returns not found for a private project" do
      project = private_project()

      assert BazelShowcase.load_timeline_invocation("#{project.account.name}/#{project.name}") == {:error, :not_found}
    end

    test "picks the richest timeline from the analytics period, preferring the newest on ties" do
      project = public_project()
      project_id = project.id

      stub(Bazel, :recent_invocations, fn ^project_id, opts ->
        assert Keyword.get(opts, :limit) == 50
        assert DateTime.diff(opts[:end_datetime], opts[:start_datetime], :day) == BazelShowcase.period_days()

        [
          %Invocation{invocation_id: "newest-without-timeline", build_timeline_span_start_ms: []},
          %Invocation{invocation_id: "newer", build_timeline_span_start_ms: [0, 10]},
          %Invocation{invocation_id: "richest", build_timeline_span_start_ms: [0, 10, 20]},
          %Invocation{invocation_id: "older-tie", build_timeline_span_start_ms: [0, 10, 20]}
        ]
      end)

      assert {:ok,
              %{
                project: %{id: ^project_id},
                invocation: %Invocation{invocation_id: "richest"},
                timeline: %{coverage: "retained_action_spans"}
              }} = BazelShowcase.load_timeline_invocation("#{project.account.name}/#{project.name}")
    end

    test "returns not found when no recent invocation has a timeline" do
      project = public_project()

      stub(Bazel, :recent_invocations, fn _project_id, _opts ->
        [%Invocation{invocation_id: "without-timeline", build_timeline_span_start_ms: []}]
      end)

      assert BazelShowcase.load_timeline_invocation("#{project.account.name}/#{project.name}") ==
               {:error, :not_found}
    end
  end

  describe "load_timeline_steps/2" do
    test "returns the invocation's timeline without machine metrics" do
      project = public_project()
      project_id = project.id

      invocation = %Invocation{
        invocation_id: "invocation-id",
        project_id: project_id,
        project_handle: project.name,
        duration_ms: 1_000,
        build_timeline_duration_ms: 1_000,
        build_timeline_span_lanes: [0],
        build_timeline_span_start_ms: [100],
        build_timeline_span_durations_ms: [400],
        build_timeline_span_categories: ["execution"],
        build_timeline_span_descriptions: ["Rustc //app:lib"]
      }

      stub(Bazel, :get_invocation, fn ^project_id, "invocation-id", _opts -> {:ok, invocation} end)

      assert {:ok, steps} = BazelShowcase.load_timeline_steps("#{project.account.name}/#{project.name}", "invocation-id")

      assert [%{title: "Rustc //app:lib", start_ms: 100, duration_ms: 400}] = steps.events
      refute Map.has_key?(steps, :machine_metrics)
    end

    test "returns not found when the invocation doesn't exist" do
      project = public_project()

      stub(Bazel, :get_invocation, fn _project_id, _invocation_id, _opts -> {:error, :not_found} end)

      assert BazelShowcase.load_timeline_steps("#{project.account.name}/#{project.name}", "missing") ==
               {:error, :not_found}
    end

    test "returns not found for a private project" do
      project = private_project()

      assert BazelShowcase.load_timeline_steps("#{project.account.name}/#{project.name}", "invocation-id") ==
               {:error, :not_found}
    end
  end

  describe "timeline_steps/1" do
    test "returns not found for an invocation that isn't the showcase's" do
      assert BazelShowcase.timeline_steps("any-invocation") == {:error, :not_found}
    end
  end

  defp public_project, do: Repo.preload(ProjectsFixtures.project_fixture(visibility: :public), :account)
  defp private_project, do: Repo.preload(ProjectsFixtures.project_fixture(visibility: :private), :account)
end
