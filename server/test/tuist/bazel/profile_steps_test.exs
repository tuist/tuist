defmodule Tuist.Bazel.ProfileStepsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Bazel.Action
  alias Tuist.Bazel.Invocation
  alias Tuist.Bazel.Profile
  alias Tuist.Bazel.ProfileDecoder
  alias Tuist.Bazel.ProfileSteps
  alias Tuist.Builds.RecordedSteps
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "indexed pagination, status filters and detail logs distinguish repeated executions" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    build = %Invocation{project_id: project.id, invocation_id: "retry"}

    events =
      for i <- 0..39 do
        %{
          ph: "X",
          name: "Compile #{i}",
          ts: i * 100_000,
          dur: 50_000,
          args: %{out: "same.o", mnemonic: "CppCompile", target: "//:app"}
        }
      end

    compressed =
      :zlib.gzip(JSON.encode!(%{otherData: %{build_id: "retry", profile_start_ts: 10_000}, traceEvents: events}))

    assert :ok = Profile.ingest(project, "retry", compressed)

    for {start, success, log} <- [{10_005, false, "first execution failed"}, {10_105, true, "retry passed"}] do
      assert :ok =
               Action.ingest(project, %{
                 "invocation_id" => "retry",
                 "primary_output" => "same.o",
                 "started_at_ms" => start,
                 "success" => success,
                 "log" => log,
                 "log_truncated" => false
               })
    end

    assert {:ok, %{steps: [failed], pagination_metadata: %{total_count: 1}}} =
             RecordedSteps.list(build, %{status: "failure"})

    assert failed.id == "profile:0"
    assert {:ok, %{status: "failure", log: "first execution failed"}} = RecordedSteps.get(build, failed.id)
    assert {:ok, %{status: "success", log: "retry passed"}} = RecordedSteps.get(build, "profile:1")

    assert {:ok, %{steps: steps, pagination_metadata: %{total_count: 38}}} =
             RecordedSteps.list(build, %{status: "unknown", page: 2, page_size: 3, sort_by: "start_ms"})

    assert Enum.map(steps, & &1.id) == ["profile:5", "profile:6", "profile:7"]

    assert {:ok, %{steps: [%{id: "profile:1"}]}} =
             RecordedSteps.list(build, %{start_ms: 100, end_ms: 150, search: "compile"})

    assert {:error, :not_found} =
             ProfileSteps.get(
               %{build | project_id: project.id + 1},
               Profile.steps_version(build),
               "profile:0"
             )

    assert {:error, :invalid_range} = RecordedSteps.list(build, %{start_ms: 2, end_ms: 1})
  end

  test "actions without BEP start times retain their unique output match" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    build = %Invocation{project_id: project.id, invocation_id: "missing-time"}

    compressed =
      :zlib.gzip(
        JSON.encode!(%{
          otherData: %{build_id: "missing-time", profile_start_ts: 10_000},
          traceEvents: [%{ph: "X", name: "Compile", ts: 1000, dur: 1000, args: %{out: "output.o"}}]
        })
      )

    assert :ok = Profile.ingest(project, "missing-time", compressed)

    assert :ok =
             Action.ingest(project, %{
               "invocation_id" => "missing-time",
               "primary_output" => "output.o",
               "started_at_ms" => 0,
               "success" => false,
               "log" => "missing timestamp diagnostic",
               "log_truncated" => false
             })

    assert {:ok, %{steps: [%{status: "failure"}]}} = RecordedSteps.list(build, %{status: "failure"})
    assert {:ok, %{log: "missing timestamp diagnostic"}} = RecordedSteps.get(build, "profile:0")
    assert [%{status: "failure"}] = Profile.load(build).events
  end

  test "batch validation rejects the entire action batch before inserting rows" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)

    valid = %{
      "invocation_id" => "batch",
      "primary_output" => "out",
      "started_at_ms" => 1,
      "success" => true,
      "log" => "",
      "log_truncated" => false
    }

    assert {:error, :invalid_action} = Action.ingest(project, %{"actions" => [valid, %{}]})

    assert %{log: nil} =
             Action.log(%Invocation{project_id: project.id, invocation_id: "batch"}, %{
               primary_output: "out",
               action_started_at_ms: 1
             })

    assert :ok = Action.ingest(project, %{"actions" => [valid, %{valid | "primary_output" => "out2"}]})

    assert %{log: ""} =
             Action.log(%Invocation{project_id: project.id, invocation_id: "batch"}, %{
               primary_output: "out2",
               action_started_at_ms: 1
             })
  end

  test "decoder bounds nesting and rejects oversized decoded containers" do
    assert {:error, :profile_too_large} =
             ProfileDecoder.decode(String.duplicate("[", 65) <> "0" <> String.duplicate("]", 65))

    assert {:error, :profile_too_large} =
             ProfileDecoder.decode("[" <> Enum.join(List.duplicate("0", 1_000_001), ",") <> "]")
  end
end
