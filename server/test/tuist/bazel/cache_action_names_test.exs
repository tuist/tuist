defmodule Tuist.Bazel.CacheActionNamesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Bazel.Profile
  alias Tuist.Bazel.ProfileSteps
  alias Tuist.IngestRepo
  alias Tuist.ReapiCache
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    %{project: ProjectsFixtures.project_fixture(build_system: :bazel)}
  end

  test "legacy events and events without a published profile retain the mnemonic", %{project: project} do
    cache_event(project, "legacy", %{})
    profile(project, "legacy", [step("Compile main.cc", "main.o")])
    assert [%{action_display_name: "CppCompile", output_path: ""}] = events(project, "legacy")

    cache_event(project, "no-profile", %{output_path: "main.o"})
    assert [%{action_display_name: "CppCompile"}] = events(project, "no-profile")
  end

  test "an exact output match enriches both the write and its preceding miss without changing counts", %{project: project} do
    cache_event(project, "build", %{outcome: "miss"})
    cache_event(project, "build", %{outcome: "write", output_path: "main.o"})
    profile(project, "build", [step("Compile main.cc", "main.o")])

    assert {rows, %{total_count: 2}} = ReapiCache.list_invocation_cache_events(project.id, "build")
    assert Enum.all?(rows, &(&1.action_display_name == "Compile main.cc"))
    assert Enum.sort(Enum.map(rows, & &1.outcome)) == ["miss", "write"]
    assert %{hits: 0, misses: 1} = ReapiCache.invocation_summary(project.id, "build")
  end

  test "output hints do not cross configurations or action digests", %{project: project} do
    cache_event(project, "build", %{output_path: "main.o"})
    cache_event(project, "build", %{configuration_id: "other", outcome: "miss"})
    cache_event(project, "build", %{action_digest: "other", outcome: "miss"})
    profile(project, "build", [step("Compile main.cc", "main.o")])

    assert Enum.sort(Enum.map(events(project, "build"), & &1.action_display_name)) ==
             ["Compile main.cc", "CppCompile", "CppCompile"]
  end

  test "reported names, mnemonics and target labels are searchable", %{project: project} do
    cache_event(project, "build", %{output_path: "main.o"})
    profile(project, "build", [step("Compile main.cc", "main.o")])

    for search <- ["main.cc", "CppCompile", "//:app"] do
      assert {[%{action_display_name: "Compile main.cc"}], %{total_count: 1}} =
               ReapiCache.list_invocation_cache_events(project.id, "build", %{
                 filters: [%{field: :action_search, op: :=~, value: search}]
               })
    end
  end

  test "action sorting follows visible labels and does not enrich content objects", %{project: project} do
    cache_event(project, "build", %{action_digest: "a", output_path: "a.o"})
    cache_event(project, "build", %{action_digest: "b", output_path: "b.o"})
    cache_event(project, "build", %{action_digest: "a", operation: "cas"})
    profile(project, "build", [step("Zebra", "a.o"), step("Alpha", "b.o")])

    {rows, _} =
      ReapiCache.list_invocation_cache_events(project.id, "build", %{
        order_by: [:action_display_name],
        order_directions: [:asc]
      })

    assert Enum.map(rows, & &1.action_display_name) == ["Alpha", "CppCompile", "Zebra"]
  end

  test "conflicting descriptions or output hints fall back rather than guessing", %{project: project} do
    cache_event(project, "titles", %{output_path: "same.o"})
    profile(project, "titles", [step("First action", "same.o"), step("Second action", "same.o")])
    assert [%{action_display_name: "CppCompile"}] = events(project, "titles")

    cache_event(project, "outputs", %{output_path: "a.o"})
    cache_event(project, "outputs", %{output_path: "b.o"})
    profile(project, "outputs", [step("First action", "a.o"), step("Second action", "b.o")])
    assert Enum.all?(events(project, "outputs"), &(&1.action_display_name == "CppCompile"))
  end

  test "matching is project, invocation, target, mnemonic and published-version scoped", %{project: project} do
    cache_event(project, "build", %{output_path: "main.o"})
    other = ProjectsFixtures.project_fixture(build_system: :bazel)
    profile(other, "build", [step("Other tenant", "main.o")])
    profile(project, "different-build", [step("Other invocation", "main.o")])

    profile(project, "build", [
      step("Other target", "main.o", target: "//:other"),
      step("Other mnemonic", "main.o", mnemonic: "SwiftCompile")
    ])

    assert [%{action_display_name: "CppCompile"}] = events(project, "build")

    # Stale rows are not part of the published profile version.
    IngestRepo.insert_all(ProfileSteps, [
      %{
        project_id: project.id,
        invocation_id: "build",
        version: "stale",
        event_id: "stale",
        title: "Stale action",
        project: "",
        target: "//:app",
        category: "CppCompile",
        primary_output: "main.o",
        start_ms: 0.0,
        duration_ms: 1.0,
        profile_started_at_ms: 0,
        inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      }
    ])

    assert [%{action_display_name: "CppCompile"}] = events(project, "build")
  end

  defp events(project, invocation) do
    {events, _} = ReapiCache.list_invocation_cache_events(project.id, invocation)
    events
  end

  defp cache_event(project, invocation, attrs) do
    ReapiCache.create_cache_events([
      Map.merge(
        %{
          client_kind: "bazel",
          operation: "action_cache",
          outcome: "hit",
          action_digest: "digest",
          size: 42,
          duration_us: 1_000,
          invocation_id: invocation,
          action_mnemonic: "CppCompile",
          target_label: "//:app",
          configuration_id: "config",
          project_id: project.id,
          account_handle: project.account.name,
          project_handle: project.name,
          cache_endpoint: "cache.tuist.dev"
        },
        attrs
      )
    ])
  end

  defp profile(project, invocation, events) do
    :ok =
      Profile.ingest(
        project,
        invocation,
        :zlib.gzip(JSON.encode!(%{otherData: %{build_id: invocation}, traceEvents: events}))
      )
  end

  defp step(name, output, opts \\ []) do
    %{
      ph: "X",
      name: name,
      ts: 0,
      dur: 1000,
      out: output,
      args: %{
        target: Keyword.get(opts, :target, "//:app"),
        mnemonic: Keyword.get(opts, :mnemonic, "CppCompile")
      }
    }
  end
end
