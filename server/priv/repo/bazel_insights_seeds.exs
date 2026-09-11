# Bazel insights for the seeded `tuist/bazel-comparison` project: invocations
# and remote cache events from the last 30 days, so the Bazel dashboard and
# the live dashboard in the Bazel announcement blog post have data locally.
# Skips the project when it already has invocations, so it's safe to re-run.

alias Tuist.Bazel
alias Tuist.Projects
alias Tuist.ReapiCache

account_handle = "tuist"
project_handle = "bazel-comparison"

case Projects.get_project_by_account_and_project_handles(account_handle, project_handle) do
  nil ->
    IO.puts("Skipping Bazel insights: #{account_handle}/#{project_handle} doesn't exist")

  project ->
    # The Bazel post's live timeline loads steps from the project's timeline
    # endpoint, which anonymous visitors can only read for public projects.
    if project.visibility != :public do
      {:ok, _project} = Projects.update_project(project, %{visibility: :public})
    end

    if Bazel.invocations_present?(project.id) do
      IO.puts("Bazel insights already seeded for #{account_handle}/#{project_handle}")
    else
      :rand.seed(:exsss, {2026, 9, 9})
      now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      cache_endpoint = "http://localhost:8080"
      timeline_lanes = ["Execution lane 1", "Execution lane 2"]

      invocations =
        for index <- 0..59 do
          failed? = rem(index, 9) == 4
          command = if(rem(index, 4) == 0, do: "test", else: "build")
          duration_ms = 25_000 + :rand.uniform(220_000)
          finished_at = NaiveDateTime.add(now, -(index * 700 + 17) * 60, :second)

          # {lane, start, duration, description}, with start and duration as
          # fractions of the invocation, shaped like the action spans Kura
          # retains for real builds.
          spans = [
            {0, 0.02, 0.36, "Rustc //app:core"},
            {1, 0.03, 0.27, "Rustc //app:network"},
            {1, 0.32, 0.22, "Rustc //app:storage"},
            {0, 0.40, 0.31, "Rustc //app:lib"},
            {1, 0.57, 0.17, "CppCompile //third_party:zstd"},
            {0, 0.74, 0.22, if(command == "test", do: "TestRunner //app:lib_test", else: "Rustc //app:cli")}
          ]

          %{
            invocation_id: UUIDv7.generate(),
            command: command,
            target_patterns: ["//..."],
            is_ci: rem(index, 3) == 0,
            bazel_version: "8.4.2",
            status: if(failed?, do: "failure", else: "success"),
            exit_code: if(failed?, do: 1, else: 0),
            started_at: NaiveDateTime.add(finished_at, -div(duration_ms, 1000), :second),
            finished_at: finished_at,
            duration_ms: duration_ms,
            project_id: project.id,
            account_handle: account_handle,
            project_handle: project_handle,
            cache_endpoint: cache_endpoint,
            build_timeline_duration_ms: duration_ms,
            build_timeline_lanes: timeline_lanes,
            build_timeline_span_lanes: Enum.map(spans, &elem(&1, 0)),
            build_timeline_span_start_ms: Enum.map(spans, &round(elem(&1, 1) * duration_ms)),
            build_timeline_span_durations_ms: Enum.map(spans, &round(elem(&1, 2) * duration_ms)),
            build_timeline_span_categories: Enum.map(spans, fn _span -> "execution" end),
            build_timeline_span_descriptions: Enum.map(spans, &elem(&1, 3))
          }
        end

      Bazel.create_invocations(invocations)

      cache_events =
        for invocation <- invocations, index <- 0..19 do
          %{
            client_kind: "bazel",
            operation: "action_cache",
            outcome: if(:rand.uniform(100) <= 82, do: "hit", else: "miss"),
            action_digest: :sha256 |> :crypto.hash("#{invocation.invocation_id}-#{index}") |> Base.encode16(case: :lower),
            size: 200 + :rand.uniform(4_000),
            duration_ms: 1 + :rand.uniform(20),
            invocation_id: invocation.invocation_id,
            action_mnemonic: "CppCompile",
            target_label: "//app:lib",
            configuration_id: "",
            project_id: project.id,
            account_handle: account_handle,
            project_handle: project_handle,
            cache_endpoint: cache_endpoint,
            # Cache events store `observed_at` with microsecond precision.
            observed_at:
              invocation.started_at
              |> NaiveDateTime.add(index * 5, :second)
              |> DateTime.from_naive!("Etc/UTC")
              |> then(&%{&1 | microsecond: {0, 6}})
          }
        end

      ReapiCache.create_cache_events(cache_events)

      IO.puts("Seeded Bazel insights for #{account_handle}/#{project_handle}")
    end
end
