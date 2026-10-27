# Loaded before SDK BEAMs are available, including when Mix compiles in OS workers.
code_paths = :code.get_path()

try do
  Mix.Task.run("deps.compile", ["tuist_ex", "--include-children"])
after
  Code.prepend_paths(code_paths -- :code.get_path())
end

Mix.Task.run("deps.loadpaths", ["--no-compile", "--no-deps-check"])
Mix.Task.run("tuist.compile", args)
