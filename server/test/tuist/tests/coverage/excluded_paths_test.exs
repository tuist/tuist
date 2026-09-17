defmodule Tuist.Tests.Coverage.ExcludedPathsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Environment
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage.ExcludedPaths

  defp excluded?(globs, path),
    do: globs |> ExcludedPaths.pattern() |> ExcludedPaths.compile() |> ExcludedPaths.excluded?(path)

  describe "pattern/1" do
    test "matches whole repository-relative paths with Git's glob rules" do
      assert excluded?(["**/Derived/**"], "Derived/Sources/Bundle.swift")
      assert excluded?(["**/Derived/**"], "app/Derived/Sources/Bundle.swift")
      refute excluded?(["**/Derived/**"], "Sources/Derived.swift")

      assert excluded?(["**/*.generated.swift"], "Strings.generated.swift")
      assert excluded?(["**/*.generated.swift"], "Sources/App/Strings.generated.swift")

      assert excluded?(["Sources/API/*.swift"], "Sources/API/Client.swift")
      refute excluded?(["Sources/API/*.swift"], "Sources/API/Nested/Client.swift")
      refute excluded?(["Sources/API/*.swift"], "Other/Sources/API/Client.swift")

      assert excluded?(["Sources/?.swift"], "Sources/A.swift")
      refute excluded?(["Sources/?.swift"], "Sources/AB.swift")
      assert excluded?(["Sources/[!B]*.swift"], "Sources/A.swift")
      refute excluded?(["Sources/[!B]*.swift"], "Sources/B.swift")
    end

    test "takes every other character literally, including an unclosed class" do
      assert excluded?(["Sources/a+b (1).swift"], "Sources/a+b (1).swift")
      refute excluded?(["Sources/a+b (1).swift"], "Sources/aab (1).swift")
      assert excluded?(["Sources/weird[.swift"], "Sources/weird[.swift")
      refute excluded?(["Sources/*.swift"], "Sources.swift")
    end

    test "excludes nothing without globs" do
      assert ExcludedPaths.pattern([]) == nil
      refute excluded?([], "Derived/Sources/Bundle.swift")
    end
  end

  describe "globs/1" do
    test "prefers the project's globs, then the server's, then the defaults" do
      assert ExcludedPaths.globs(%Project{coverage_excluded_path_globs: ["A/**"]}) == ["A/**"]
      assert ExcludedPaths.globs(%Project{coverage_excluded_path_globs: []}) == []
      assert ExcludedPaths.globs(%Project{coverage_excluded_path_globs: nil}) == ExcludedPaths.defaults()

      stub(Environment, :coverage_excluded_path_globs, fn -> ["Server/**"] end)
      assert ExcludedPaths.globs(%Project{coverage_excluded_path_globs: nil}) == ["Server/**"]
      assert ExcludedPaths.globs(nil) == ["Server/**"]
    end
  end
end
