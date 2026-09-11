defmodule Tuist.Bazel.ProfileTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Bazel.Invocation
  alias Tuist.Bazel.Profile
  alias Tuist.Bazel.Timeline
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "retains every profile interval beyond the summary limit and converts resource units" do
    events =
      Enum.map(0..99, fn i ->
        %{
          "ph" => "X",
          "name" => "Compile #{i}",
          "ts" => i * 1000,
          "dur" => 500,
          "args" => %{"target" => "//:app", "mnemonic" => "CppCompile"}
        }
      end) ++
        [
          %{"ph" => "C", "name" => "CPU usage (total)", "ts" => 10_000, "args" => %{"system cpu" => 4.5}},
          %{"ph" => "C", "name" => "Memory usage (total)", "ts" => 10_000, "args" => %{"system memory" => 1024}},
          %{
            "ph" => "C",
            "name" => "Network Down usage (total)",
            "ts" => 10_000,
            "args" => %{"system network down (Mbps)" => 8}
          }
        ]

    assert {:ok, timeline} = Profile.normalize(profile(events), "build-1", "app")
    assert timeline.total_count == 100
    assert timeline.coverage == "trace_profile"
    assert timeline.target_count == 1
    assert timeline.duration == 99.5

    assert [%{offset_ms: 10.0, cpu_usage_cores: 4.5, memory_used_bytes: 1_073_741_824, network_bytes_in: 1_000_000.0}] =
             timeline.machine_metrics

    assert hd(timeline.machine_metrics).duration_ms == 89.5

    refute Map.has_key?(hd(timeline.machine_metrics), :disk_bytes_read)
    assert List.last(timeline.events).duration_ms == 0.5
  end

  test "counter buckets cover short builds and clip only the final bucket of longer builds" do
    counters =
      Enum.map([8000, 1_008_000], fn ts ->
        %{"ph" => "C", "name" => "CPU usage (total)", "ts" => ts, "args" => %{"system cpu" => 1.8}}
      end)

    short = %{"ph" => "X", "name" => "Compile", "ts" => 0, "dur" => 403_000}
    assert {:ok, timeline} = Profile.normalize(profile([short, hd(counters)]), "build-1", "app")
    assert [%{offset_ms: 8.0, duration_ms: 395.0, cpu_usage_cores: 1.8}] = timeline.machine_metrics
    assert timeline.duration == 403.0

    long = %{short | "dur" => 1_403_000}
    assert {:ok, timeline} = Profile.normalize(profile([long | counters]), "build-1", "app")

    assert [%{duration_ms: 1000}, %{offset_ms: 1008.0, duration_ms: 395.0}] = timeline.machine_metrics
    assert timeline.duration == 1403.0
  end

  test "previously ingested counter points are loaded with their native bucket intervals" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)

    Tuist.IngestRepo.insert_all(Profile, [
      %{
        project_id: project.id,
        invocation_id: "old-build",
        inserted_at: ~N[2026-09-10 00:00:00],
        payload:
          JSON.encode!(%{
            "future_profile_property_abc123" => %{"unrecognized_nested_key" => "ignored"},
            :events => [],
            :duration => 403,
            logs_available: false,
            machine_metrics: [%{offset_ms: 8, cpu_usage_cores: 1.8}]
          })
      }
    ])

    timeline = Profile.load(%Invocation{project_id: project.id, invocation_id: "old-build"})
    assert [%{offset_ms: 8, duration_ms: 395, cpu_usage_cores: 1.8}] = timeline.machine_metrics

    for count <- ["", "0", "-1", "1", "12x", "2.5", "65537"] do
      invalid =
        Profile.load(%Invocation{
          project_id: project.id,
          invocation_id: "old-build",
          custom_values: %{"TUIST_CPU_COUNT" => count}
        })

      refute Map.has_key?(hd(invalid.machine_metrics), :cpu_usage_percent)
    end

    normalized =
      Profile.load(%Invocation{
        project_id: project.id,
        invocation_id: "old-build",
        custom_values: %{"TUIST_CPU_COUNT" => "12"}
      })

    assert [%{cpu_usage_percent: 15.0, cpu_usage_cores: 1.8}] = normalized.machine_metrics
  end

  test "tolerates native floating-point rounding at full CPU utilization" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)

    Tuist.IngestRepo.insert_all(Profile, [
      %{
        project_id: project.id,
        invocation_id: "rounding-build",
        inserted_at: ~N[2026-09-10 00:00:00],
        payload:
          JSON.encode!(%{
            events: [],
            duration: 1000,
            logs_available: false,
            machine_metrics: [%{offset_ms: 0, cpu_usage_cores: 11.000000000000004}]
          })
      }
    ])

    timeline =
      Profile.load(%Invocation{
        project_id: project.id,
        invocation_id: "rounding-build",
        custom_values: %{"TUIST_CPU_COUNT" => "11"}
      })

    assert [%{cpu_usage_percent: 100.0, cpu_usage_cores: 11.000000000000004}] = timeline.machine_metrics
  end

  test "rejects the wrong invocation and malformed profiles" do
    assert {:error, :invalid_profile} = Profile.normalize(profile([]), "another-build", "app")
    assert {:error, _} = Profile.decode("not gzip")
    assert {:error, _} = Profile.decode(:zlib.gzip("not JSON"))
  end

  test "drops trailing empty buckets while preserving real idle measurements and the timeline bounds" do
    samples = [
      %{offset_ms: 10, cpu_usage_cores: 2, memory_used_bytes: 1024},
      %{offset_ms: 1010, cpu_usage_cores: 0, memory_used_bytes: 0},
      %{offset_ms: 2010, cpu_usage_cores: 0, memory_used_bytes: 1024, network_bytes_in: 0},
      %{offset_ms: 3010, cpu_usage_cores: 0, memory_used_bytes: 0, network_bytes_in: 0},
      %{offset_ms: 4010, cpu_usage_cores: 0, memory_used_bytes: 0, network_bytes_in: 0}
    ]

    counters = Enum.flat_map(samples, &counter_events/1)
    step = %{"ph" => "X", "name" => "Build", "ts" => 0, "dur" => 4_100_000}
    assert {:ok, timeline} = Profile.normalize(profile([step | counters]), "build-1", "app")
    assert Enum.map(timeline.machine_metrics, & &1.offset_ms) == [10.0, 1010.0, 2010.0]
    assert timeline.has_metrics
    assert timeline.duration == 4100.0
    assert %{duration_ms: 1000, cpu_usage_cores: 0} = last = List.last(timeline.machine_metrics)
    assert last.network_bytes_in == 0
  end

  test "does not discard zero CPU-only buckets or partially nonzero final buckets" do
    for sample <- [
          %{offset_ms: 10, cpu_usage_cores: 0},
          %{offset_ms: 10, cpu_usage_cores: 1, memory_used_bytes: 0},
          %{offset_ms: 10, memory_used_bytes: 0, network_bytes_in: 1}
        ] do
      assert {:ok, timeline} = Profile.normalize(profile(counter_events(sample)), "build-1", "app")
      assert length(timeline.machine_metrics) == 1
      assert timeline.has_metrics
    end
  end

  test "removes padding from already stored profiles and hides metrics when only padding remains" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    padding = %{offset_ms: 1010, cpu_usage_cores: 0, memory_used_bytes: 0}

    for {id, samples} <- [
          {"padded", [%{offset_ms: 10, cpu_usage_cores: 2, memory_used_bytes: 1024}, padding]},
          {"empty", [padding]}
        ] do
      Tuist.IngestRepo.insert_all(Profile, [
        %{
          project_id: project.id,
          invocation_id: id,
          inserted_at: ~N[2026-09-10 00:00:00],
          payload:
            JSON.encode!(%{
              events: [],
              duration: 1200,
              has_metrics: true,
              logs_available: false,
              machine_metrics: samples
            })
        }
      ])
    end

    timeline = Profile.load(%Invocation{project_id: project.id, invocation_id: "padded"})
    assert [%{offset_ms: 10, duration_ms: 1000, cpu_usage_cores: 2}] = timeline.machine_metrics
    assert timeline.duration == 1200

    assert %{machine_metrics: [], has_metrics: false} =
             Profile.load(%Invocation{project_id: project.id, invocation_id: "empty"})

    assert {:ok, %{machine_metrics: [], has_metrics: false}} =
             Profile.normalize(profile(counter_events(padding)), "build-1", "app")
  end

  test "ingestion is idempotent, scoped by project and replaces the legacy summary" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    event = %{"ph" => "X", "name" => "Compile", "ts" => 500, "dur" => 1500}
    gzip = [event] |> profile() |> JSON.encode!() |> :zlib.gzip()
    assert :ok = Profile.ingest(project, "build-1", gzip)
    assert :ok = Profile.ingest(project, "build-1", gzip)
    invocation = %Invocation{project_id: project.id, invocation_id: "build-1"}
    assert %{total_count: 1, coverage: "trace_profile"} = timeline = Timeline.load(invocation)
    bootstrap = Timeline.bootstrap(invocation)
    assert bootstrap.coverage == "trace_profile"
    assert bootstrap.duration == timeline.duration
    assert bootstrap.machine_metrics == timeline.machine_metrics
    refute Map.has_key?(bootstrap, :events)
    refute Map.has_key?(bootstrap, :total_count)
    assert nil == Profile.load(%{invocation | project_id: project.id + 1})
  end

  test "native resource keys survive additional counter metadata" do
    events = [
      %{"ph" => "C", "name" => "CPU usage (total)", "ts" => 0, "args" => %{"system cpu" => 2, "metadata" => 999}},
      %{
        "ph" => "C",
        "name" => "Memory usage (total)",
        "ts" => 0,
        "args" => %{"system memory" => 1024, "metadata" => "added"}
      },
      %{
        "ph" => "C",
        "name" => "Network Up usage (total)",
        "ts" => 0,
        "args" => %{"system network up (Mbps)" => 8, "metadata" => "added"}
      },
      %{"ph" => "C", "name" => "Network Down usage (total)", "ts" => 0, "args" => %{"metadata" => 42}}
    ]

    assert {:ok, %{machine_metrics: [sample]}} = Profile.normalize(profile(events), "build-1", "app")
    assert sample.cpu_usage_cores == 2
    assert sample.memory_used_bytes == 1_073_741_824
    assert sample.network_bytes_out == 1_000_000
    refute Map.has_key?(sample, :network_bytes_in)
  end

  defp profile(events), do: %{"otherData" => %{"build_id" => "build-1"}, "traceEvents" => events}

  defp counter_events(sample) do
    Enum.flat_map(
      [
        {:cpu_usage_cores, "CPU usage (total)", "system cpu"},
        {:memory_used_bytes, "Memory usage (total)", "system memory"},
        {:network_bytes_in, "Network Down usage (total)", "system network down (Mbps)"}
      ],
      fn {field, name, key} ->
        case Map.fetch(sample, field) do
          {:ok, value} -> [%{"ph" => "C", "name" => name, "ts" => sample.offset_ms * 1000, "args" => %{key => value}}]
          :error -> []
        end
      end
    )
  end
end
