defmodule Tuist.TestImpactAnalysis.TrackedFiles do
  @moduledoc """
  The tracked files of coverage-based test selection: files a change to
  which can affect any test without showing in coverage, so it runs every
  test (`tracked_file_changed`). A changed file that no evidence includes
  and no tracked pattern matches selects nothing.

  The patterns are the build system's defaults (`Tuist.GitHistory.settings/1`)
  plus those the project configured, which its client sends with each runs
  request (`tracked_files`), repository-relative globs. A pattern starting
  with `!` excludes the files it matches, defaults included, so a project
  can opt out of a default.
  """
  alias Tuist.GitHistory
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage.ExcludedPaths

  defstruct includes: [], exclude_globs: [], excludes: nil, include_pattern: nil

  @doc """
  The matcher for a project's defaults and its configured `patterns`: each
  include with whether it's a default, and the excludes.
  """
  def matcher(%Project{} = project, patterns \\ []) do
    {excludes, configured} =
      (patterns || [])
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 in ["", "!"]))
      |> Enum.split_with(&String.starts_with?(&1, "!"))

    excludes = Enum.map(excludes, &String.trim_leading(&1, "!"))
    defaults = GitHistory.settings(project).tracked_file_globs

    includes =
      Enum.map(defaults, &{&1, &1 not in configured}) ++ for(glob <- configured, glob not in defaults, do: {glob, false})

    %__MODULE__{
      includes: Enum.map(includes, fn {glob, default?} -> {glob, default?, glob |> regex() |> Regex.compile!()} end),
      exclude_globs: excludes,
      excludes: excludes |> ExcludedPaths.pattern() |> ExcludedPaths.compile(),
      include_pattern: includes |> Enum.map(&elem(&1, 0)) |> ExcludedPaths.pattern()
    }
  end

  @doc """
  The include pattern a tracked file matches, as `%{pattern, default}`, or
  nil when none does or an exclude matches it.
  """
  def match(%__MODULE__{} = matcher, path) do
    if ExcludedPaths.excluded?(matcher.excludes, path) do
      nil
    else
      Enum.find_value(matcher.includes, fn {glob, default?, regex} ->
        if Regex.match?(regex, path), do: %{pattern: glob, default: default?}
      end)
    end
  end

  @doc "Whether `path` is a tracked file."
  def tracked?(%__MODULE__{} = matcher, path), do: not is_nil(match(matcher, path))

  @doc """
  The first changed file, in path order, that's a tracked file, as `%{path,
  pattern, default}`; nil when none is.
  """
  def first_match(%__MODULE__{} = matcher, changed_files) do
    changed_files
    |> Enum.map(& &1.path)
    |> Enum.sort()
    |> Enum.find_value(fn path ->
      case match(matcher, path) do
        nil -> nil
        match -> Map.put(match, :path, path)
      end
    end)
  end

  @doc """
  Keeps the tracked ones of `files` (`%{path}`) read from a query narrowed
  by `include_pattern`: those no exclude matches.
  """
  def reject_excluded(%__MODULE__{excludes: nil}, files), do: files

  def reject_excluded(%__MODULE__{} = matcher, files),
    do: Enum.reject(files, &ExcludedPaths.excluded?(matcher.excludes, &1.path))

  @doc """
  The effective patterns, as `%{pattern, default}`: the includes in the
  order they're matched, defaults first, then the excludes with their `!`.
  """
  def patterns(%__MODULE__{} = matcher) do
    Enum.map(matcher.includes, fn {glob, default?, _regex} -> %{pattern: glob, default: default?} end) ++
      Enum.map(matcher.exclude_globs, &%{pattern: "!" <> &1, default: false})
  end

  defp regex(glob), do: ExcludedPaths.pattern([glob])
end
