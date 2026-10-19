defmodule Tuist.HomeActivity do
  @moduledoc """
  Bounded, project-scoped activity for companion Home screens.
  New flaky tests entered their current flaky state within the last seven days.
  Failures are historical outcomes, not a claim that an incident is unresolved.
  """

  alias Tuist.BuildMetrics
  alias Tuist.Tests

  @limit 3

  def build_failures(project) when project.build_system in [:xcode, :gradle, :bazel, :once] do
    now = DateTime.utc_now()

    options = [
      build_system: Atom.to_string(project.build_system),
      view: "recent_failures",
      start_datetime: DateTime.add(now, -7, :day),
      end_datetime: now,
      time_field: "started_at",
      limit: @limit,
      include_failure_categories: false
    ]

    options =
      case project.build_system do
        :once -> Keyword.put(options, :kind, "build")
        :bazel -> Keyword.put(options, :command, "build")
        _ -> options
      end

    %{rows: rows} = BuildMetrics.query(project.id, options)

    {:ok,
     Enum.map(rows, fn row ->
       %{
         id: row.id,
         title: title(Enum.join(row.requested_tasks, " "), "Build run"),
         subtitle: row.git_branch || "",
         occurred_at: row.started_at
       }
     end)}
  end

  def build_failures(_project), do: {:error, :unsupported}

  def test_failures(%{build_system: :once}), do: {:error, :unsupported}

  def test_failures(project) do
    since = DateTime.add(DateTime.utc_now(), -7, :day)
    runs = Tests.list_recent_failed_test_runs(project.id, since, @limit)

    {:ok,
     Enum.map(runs, fn run ->
       %{
         id: run.id,
         title: title(run.scheme, "Test run"),
         subtitle: run.git_branch || "",
         occurred_at: timestamp(run.ran_at)
       }
     end)}
  end

  def flaky_tests(%{build_system: :once}), do: {:error, :unsupported}

  def flaky_tests(project) do
    since = DateTime.add(DateTime.utc_now(), -7, :day)

    {:ok,
     project.id
     |> Tests.list_recent_flaky_test_cases(since, @limit)
     |> Enum.map(fn test ->
       %{
         id: test.id,
         title: test.name,
         subtitle: Enum.join(Enum.reject([test.module_name, test.suite_name], &(&1 in [nil, ""])), " · "),
         occurred_at: timestamp(test.marked_flaky_at)
       }
     end)}
  end

  defp title(nil, fallback), do: fallback
  defp title(value, fallback), do: if(String.trim(value) == "", do: fallback, else: value)

  defp timestamp(%NaiveDateTime{} = value), do: value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
  defp timestamp(%DateTime{} = value), do: DateTime.to_unix(value)
end
