Mix.start()
result_path = System.fetch_env!("BENCH_RESULT")
events_path = System.fetch_env!("BENCH_EVENTS")

state = %{
  phases_ms: %{},
  completed: false,
  elixir: System.version(),
  erlang: to_string(:erlang.system_info(:otp_release))
}

Process.put(:bench_state, state)
write = fn -> File.write!(result_path, JSON.encode!(Process.get(:bench_state))) end

phase = fn name, action ->
  IO.puts("BENCH_PHASE #{name} START")
  write.()
  started = System.monotonic_time(:microsecond)
  value = action.()
  elapsed = (System.monotonic_time(:microsecond) - started) / 1000
  Process.put(:bench_state, put_in(Process.get(:bench_state), [:phases_ms, name], elapsed))
  IO.puts("BENCH_PHASE #{name} END #{elapsed}")
  write.()
  value
end

apps = fn ->
  Mix.Project.build_path()
  |> Path.join("lib/*/ebin/*.app")
  |> Path.wildcard()
  |> Enum.map(&Path.basename(&1, ".app"))
  |> Enum.sort()
end

Mix.Project.in_project(:tuist, File.cwd!(), fn _ ->
  phase.("loadconfig", fn -> Mix.Task.run("loadconfig") end)

  phase.("bootstrap", fn ->
    Mix.Task.run("deps.compile", ["tuist_ex", "--include-children"])
    Mix.Task.run("deps.loadpaths", ["--no-compile", "--no-deps-check"])
  end)

  sdk_ebin = :tuist_ex |> :code.lib_dir() |> to_string() |> Path.join("ebin")

  graph =
    for dep <- Mix.Dep.load_and_cache(),
        do: %{
          app: dep.app,
          fetched: dep.scm.fetchable?(),
          manager: dep.manager,
          compile: dep.opts[:compile] != false
        }

  Process.put(
    :bench_state,
    Map.merge(Process.get(:bench_state), %{bootstrap_apps: apps.(), graph: graph})
  )

  {:ok, reporter} =
    TuistEx.Analytics.CompileReporter.start(
      sampler: nil,
      environment: fn _ -> nil end,
      shell: fn _ -> :ok end,
      submit: fn payload, _ ->
        File.write!(events_path, JSON.encode!(payload))
        :ok
      end
    )

  try do
    phase.("cache_prepare", fn -> TuistEx.DependencyCache.prepare([], reporter) end)

    phase.("dependency_loadpaths", fn ->
      Mix.Task.reenable("deps.loadpaths")
      Mix.Task.reenable("loadpaths")
      Mix.Task.run("deps.loadpaths", [])
    end)

    phase.("server_compile", fn -> Mix.Tasks.Compile.run([]) end)
    Process.put(:bench_state, Map.put(Process.get(:bench_state), :completed, true))
    write.()
  after
    Code.prepend_path(sdk_ebin)
    TuistEx.Analytics.CompileReporter.finish(reporter)
  end
end)

write.()
