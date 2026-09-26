defmodule Mix.Tasks.Tuist.TestTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Tuist.Test, as: Task

  setup do
    formatters = Application.get_env(:ex_unit, :formatters)
    analytics_options = Application.get_env(:tuist_ex, :analytics_options)

    on_exit(fn ->
      if formatters do
        Application.put_env(:ex_unit, :formatters, formatters)
      else
        Application.delete_env(:ex_unit, :formatters)
      end

      if analytics_options do
        Application.put_env(:tuist_ex, :analytics_options, analytics_options)
      else
        Application.delete_env(:tuist_ex, :analytics_options)
      end
    end)
  end

  test "splits mix task args at `--` and parses only the left side" do
    assert {[url: "https://tuist.example"], ["--trace"]} =
             Task.split_args(["--url", "https://tuist.example", "--", "--trace"])
  end

  test "parses --project when no forwarded args are given" do
    assert {[project: "acme/widgets"], []} = Task.split_args(["--project", "acme/widgets"])
  end

  test "configure/1 appends the analytics formatter without dropping existing ones" do
    Application.put_env(:ex_unit, :formatters, [ExUnit.CLIFormatter])
    :ok = Task.configure(project: "acme/widgets")

    formatters = Application.get_env(:ex_unit, :formatters)
    assert ExUnit.CLIFormatter in formatters
    assert TuistEx.Analytics.ExUnitFormatter in formatters
    assert Application.get_env(:tuist_ex, :analytics_options) == [project: "acme/widgets"]
  end

  test "configure/1 does not duplicate the analytics formatter" do
    Application.put_env(:ex_unit, :formatters, [
      ExUnit.CLIFormatter,
      TuistEx.Analytics.ExUnitFormatter
    ])

    :ok = Task.configure([])

    formatters = Application.get_env(:ex_unit, :formatters)
    assert Enum.count(formatters, &(&1 == TuistEx.Analytics.ExUnitFormatter)) == 1
  end

  test "declares :test as the preferred CLI env" do
    # The attribute prevents `mix tuist.test` from picking up whatever env
    # the invoker happened to be in (usually :dev), which otherwise breaks
    # `mix test` before any tests run.
    attrs = Task.__info__(:attributes)
    assert Keyword.get(attrs, :preferred_cli_env) == [:test]
  end
end
