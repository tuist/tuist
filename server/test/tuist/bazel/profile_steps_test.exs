defmodule Tuist.Bazel.ProfileStepsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Bazel.Action
  alias Tuist.Bazel.Invocation
  alias Tuist.Bazel.Profile
  alias Tuist.Bazel.ProfileDecoder
  alias Tuist.Bazel.ProfileSteps
  alias Tuist.Bazel.Timeline
  alias Tuist.Builds.RecordedSteps
  alias Tuist.ClickHouseRepo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "retained IDs remain readable after the indexed profile is published" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)

    build = %Invocation{
      project_id: project.id,
      invocation_id: "boundary",
      duration_ms: 100,
      build_timeline_span_lanes: [0],
      build_timeline_span_start_ms: [0],
      build_timeline_span_durations_ms: [100],
      build_timeline_span_categories: ["execution"],
      build_timeline_span_descriptions: ["Retained action"]
    }

    assert {:ok, %{steps: [%{id: id}]}} = RecordedSteps.list(build, %{})

    compressed =
      :zlib.gzip(
        JSON.encode!(%{
          otherData: %{build_id: "boundary"},
          traceEvents: [%{ph: "X", name: "Profile action", ts: 0, dur: 1000}]
        })
      )

    assert :ok = Profile.ingest(project, "boundary", compressed)
    assert Timeline.available?(build)
    assert {:ok, %{title: "Retained action", id: ^id}} = RecordedSteps.get(build, id)
    assert {:ok, %{title: "Profile action"}} = RecordedSteps.get(build, "profile:0")
    assert {:error, :not_found} = RecordedSteps.get(build, "profile:999")
    assert {:error, :not_found} = RecordedSteps.get(build, "999")

    assert {:ok, %{steps: [], availability: "available"}} = RecordedSteps.list(build, %{search: "no match"})

    ClickHouseRepo.query!(
      "ALTER TABLE bazel_profile_steps DELETE WHERE project_id = {$0:Int64} AND invocation_id = {$1:String} SETTINGS mutations_sync = 1",
      [project.id, "boundary"]
    )

    assert {:ok, %{steps: [], availability: "unavailable"}} = RecordedSteps.list(build, %{})
    refute Timeline.available?(build)
  end

  test "legacy action correlation treats a zero profile epoch as unavailable" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    build = %Invocation{project_id: project.id, invocation_id: "zero-origin"}

    assert :ok =
             Action.ingest(project, %{
               "invocation_id" => "zero-origin",
               "primary_output" => "out.o",
               "started_at_ms" => 1_700_000_000_000,
               "success" => true,
               "log" => "matched",
               "log_truncated" => false
             })

    timeline = %{
      events: [%{primary_output: "out.o", start_ms: 0, duration_ms: 1000, status: "unknown"}],
      profile_started_at_ms: 0,
      logs_available: false
    }

    assert %{events: [%{status: "success"}]} = Action.enrich(timeline, build)
  end

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

    assert :ok =
             Action.ingest(project, %{
               "invocation_id" => "missing-time",
               "primary_output" => "output.o",
               "started_at_ms" => 10_001,
               "success" => true,
               "log" => "another execution",
               "log_truncated" => false
             })

    assert {:ok, %{status: "unknown", log: nil}} = RecordedSteps.get(build, "profile:0")
    assert [%{status: "unknown"} = ambiguous] = Profile.load(build).events
    assert %{log: nil} = Action.log(build, ambiguous)
  end

  test "full timeline outcomes support 20,000 distinct outputs without an HTTP IN parameter" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    build = %Invocation{project_id: project.id, invocation_id: "large-profile"}
    prefix = String.duplicate("build/output/", 10)

    events =
      for i <- 1..20_000 do
        %{
          ph: "X",
          name: "Compile #{i}",
          ts: i * 1000,
          dur: 1000,
          args: %{out: "#{prefix}#{i}.o", target: "//:app", mnemonic: "CppCompile"}
        }
      end

    compressed = :zlib.gzip(JSON.encode!(%{otherData: %{build_id: build.invocation_id}, traceEvents: events}))
    assert :ok = Profile.ingest(project, build.invocation_id, compressed)

    action = %{
      "invocation_id" => build.invocation_id,
      "primary_output" => "#{prefix}20000.o",
      "started_at_ms" => 0,
      "success" => false,
      "log" => "compile failed",
      "log_truncated" => false
    }

    assert :ok = Action.ingest(project, action)
    assert :ok = Action.ingest(project, %{action | "invocation_id" => "other-build", "primary_output" => "#{prefix}1.o"})
    timeline = Profile.load(build)
    assert length(timeline.events) == 20_000
    assert timeline.logs_available
    assert hd(timeline.events).status == "unknown"
    assert List.last(timeline.events).status == "failure"
    assert %{log: "compile failed"} = Action.log(build, List.last(timeline.events))
    assert length(Action.enrich(timeline, build).events) == 20_000
  end

  test "decoder budgets heap terms without charging their external representation again" do
    event = %{
      ph: "X",
      cat: "action processing",
      name: "Compiling Sources/App/main.swift",
      ts: 1000,
      dur: 2000,
      pid: 1,
      tid: 42,
      args: %{target: "//App:App", mnemonic: "SwiftCompile", out: "bazel-out/bin/App/main.o"}
    }

    json = JSON.encode!(%{otherData: %{build_id: "large"}, traceEvents: List.duplicate(event, 80_000)})
    assert {:ok, %{"traceEvents" => events}} = ProfileDecoder.decode(json)
    assert length(events) == 80_000

    oversized = JSON.encode!(%{traceEvents: List.duplicate(event, 100_000)})
    assert {:error, :profile_too_large} = ProfileDecoder.decode(oversized)
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
