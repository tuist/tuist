defmodule Mix.Tasks.Tuist.CompileTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Tuist.Compile, as: Task

  test "takes the same command line as mix compile, keeping only its own options" do
    assert {[project: "acme/widgets"], ["--force", "--warnings-as-errors"]} =
             Task.split_args(["--force", "--project", "acme/widgets", "--warnings-as-errors"])
  end

  test "forwards non-string arguments to mix compile unchanged" do
    assert {[url: "https://tuist.example"], [{:preload_modules, true}, "--force"]} =
             Task.split_args([{:preload_modules, true}, "--url=https://tuist.example", "--force"])
  end
end
