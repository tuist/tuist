# Inserts the module-invalidation demo series into the dev DB's `tuist/tuist`
# project so the Module Cache dashboard's invalidation card has data locally.
# Run with: mise exec -- mix run priv/repo/seed_module_invalidations.exs
alias Tuist.CommandEvents.Event
alias Tuist.IngestRepo
alias Tuist.Projects
alias Tuist.Xcode.XcodeTarget

{:ok, tuist_project} = Projects.get_project_by_slug("tuist/tuist")

invalidation_modules = [
  {"Core", "framework", 2, 0, 0},
  {"Networking", "framework", 0, 2, 1},
  {"DesignSystem", "framework", 3, 6, 0},
  {"Analytics", "framework", 8, 3, 2},
  {"Features", "app", 9, 2, 0},
  {"Persistence", "static_library", 18, 22, 4}
]

invalidation_deps = %{
  "Core" => [],
  "Persistence" => ["Core"],
  "Networking" => ["Core"],
  "DesignSystem" => ["Core"],
  "Analytics" => ["Core", "Networking"],
  "Features" => ["Networking", "Analytics", "DesignSystem", "Persistence"]
}

invalidation_days = 30
# Events use DateTime64(6) columns (microsecond precision); xcode_targets'
# inserted_at is second precision, so it is truncated per-target below.
invalidation_now = NaiveDateTime.utc_now()

module_version = fn
  0, _day, _offset -> 0
  period, day, offset -> div(day + offset, period)
end

day_changed = fn
  0, _day, _offset -> false
  period, day, offset -> day > 0 and rem(day + offset, period) == 0
end

random_hex = fn length ->
  bytes = div(length, 2) + 1
  bytes |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower) |> binary_part(0, length)
end

invalidation_rows =
  Enum.map(0..(invalidation_days - 1), fn day ->
    ran_at = NaiveDateTime.add(invalidation_now, -(invalidation_days - 1 - day) * 86_400, :second)
    event_id = UUIDv7.generate()
    xcode_project_id = UUIDv7.generate()

    targets =
      Enum.map(invalidation_modules, fn {name, product, own_p, dep_p, dep_off} ->
        own_changed = day_changed.(own_p, day, 0)
        dep_changed = day_changed.(dep_p, day, dep_off)
        miss? = day == 0 or own_changed or dep_changed
        hit = if miss?, do: 0, else: Enum.random([1, 2])
        own_hash = "own-#{name}-#{module_version.(own_p, day, 0)}"
        dep_hash = "dep-#{name}-#{module_version.(dep_p, day, dep_off)}"

        %{
          id: UUIDv7.generate(),
          name: name,
          product: product,
          binary_cache_hash: "bh-#{name}-#{own_hash}-#{dep_hash}",
          binary_cache_hit: hit,
          selective_testing_hash: nil,
          selective_testing_hit: 0,
          binary_build_duration: Enum.random(5_000..40_000),
          xcode_project_id: xcode_project_id,
          command_event_id: event_id,
          inserted_at: NaiveDateTime.truncate(ran_at, :second),
          bundle_id: "com.tuist.demo.#{String.downcase(name)}",
          product_name: name,
          destinations: ["iphone"],
          sources_hash: own_hash,
          dependencies_hash: dep_hash,
          external_hash: "",
          additional_strings: [],
          dependencies: Map.get(invalidation_deps, name, [])
        }
      end)

    %{event_id: event_id, ran_at: ran_at, is_ci: rem(day, 3) == 0, targets: targets}
  end)

invalidation_events =
  Enum.map(invalidation_rows, fn row ->
    %{
      id: row.event_id,
      name: "generate",
      duration: Enum.random(20_000..120_000),
      tuist_version: "4.1.0",
      project_id: tuist_project.id,
      cacheable_targets: Enum.map(row.targets, & &1.name),
      local_cache_target_hits: for(t <- row.targets, t.binary_cache_hit == 1, do: t.name),
      remote_cache_target_hits: for(t <- row.targets, t.binary_cache_hit == 2, do: t.name),
      test_targets: [],
      local_test_target_hits: [],
      remote_test_target_hits: [],
      swift_version: "5.9",
      macos_version: "14.0",
      subcommand: "",
      command_arguments: ["generate"],
      is_ci: row.is_ci,
      user_id: nil,
      client_id: "client-id",
      status: 0,
      error_message: nil,
      preview_id: nil,
      git_ref: "refs/heads/main",
      git_commit_sha: random_hex.(40),
      git_branch: "main",
      created_at: row.ran_at,
      updated_at: row.ran_at,
      ran_at: row.ran_at,
      build_run_id: nil
    }
  end)

invalidation_targets = Enum.flat_map(invalidation_rows, & &1.targets)

IngestRepo.insert_all(Event, invalidation_events, timeout: 120_000)
IngestRepo.insert_all(XcodeTarget, invalidation_targets, timeout: 120_000)

IO.puts(
  "Module invalidation demo data for tuist/tuist: " <>
    "#{length(invalidation_events)} runs, #{length(invalidation_targets)} targets"
)
