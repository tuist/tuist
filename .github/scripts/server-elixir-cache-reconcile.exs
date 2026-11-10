Mix.start()

# Dependency resolution is deliberately outside the measurement. The setup action
# can update transitive locks; fetch the committed revisions without resolving again.
Mix.Project.in_project(:tuist, File.cwd!(), fn _ ->
  Mix.Task.run("loadconfig")
  dependencies = Mix.Dep.load_and_cache()
  lock = Mix.Dep.Lock.read()

  packages =
    for {_, entry} <- lock,
        is_tuple(entry),
        elem(entry, 0) == :hex,
        do: {elem(entry, 6), to_string(elem(entry, 1))}

  Hex.Registry.Server.open()
  Hex.Registry.Server.prefetch(packages)
  Hex.SCM.prefetch(lock)

  for dependency <- dependencies, dependency.scm.fetchable?() do
    if dependency.scm.lock_status(dependency.opts) != :ok do
      dependency.scm.checkout(dependency.opts)
      :ok = dependency.scm.lock_status(dependency.opts)
      IO.puts("Reconciled locked source: #{dependency.app}")
    end
  end

  Mix.Dep.clear_cached()

  for dependency <- Mix.Dep.load_and_cache(),
      dependency.scm.fetchable?(),
      do: :ok = dependency.scm.lock_status(dependency.opts)
end)
