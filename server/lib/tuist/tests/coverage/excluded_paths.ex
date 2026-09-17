defmodule Tuist.Tests.Coverage.ExcludedPaths do
  @moduledoc """
  The paths a project leaves out of every coverage figure: generated code, above
  all, whose lines no test is expected to cover and which would otherwise
  dominate a pull request that regenerates it. Only the project decides what is
  generated in its repository, so nothing is excluded unless it sets globs.

  Globs match the whole repository-relative path, with Git's pathspec glob
  rules: `*` and `?` stay within a directory, `**/` matches any number of
  directories, and `/**` everything inside a directory.

  Excluded files are still stored with their line data. They are left out of
  a run's totals, targets, files, patch coverage and gaps when those are read,
  so changing the globs applies to every run whose per-file coverage is still
  retained (`Tuist.Tests.Coverage.recompute_totals/2` republishes their totals).
  """

  alias Tuist.Projects
  alias Tuist.Projects.Project

  @doc "The project's globs; none for a project that set none."
  def globs(%Project{coverage_excluded_path_globs: globs}) when is_list(globs), do: globs
  def globs(_project), do: []

  @doc """
  One anchored regular expression matching any of the globs, valid for both
  ClickHouse's `match` (RE2) and Elixir's `Regex`, or nil when there are no
  globs.
  """
  def pattern([]), do: nil

  def pattern(globs) when is_list(globs) do
    "^(?:" <> Enum.map_join(globs, "|", &glob_regex/1) <> ")$"
  end

  @doc "The pattern for the project with the given id, as `pattern/1`."
  def pattern_for_project(%Project{} = project), do: project |> globs() |> pattern()

  def pattern_for_project(project_id) do
    project_id |> Projects.get_project_by_id() |> globs() |> pattern()
  end

  @doc "Whether a path is excluded by a pattern from `pattern/1`."
  def excluded?(nil, _path), do: false
  def excluded?(pattern, path) when is_binary(pattern), do: pattern |> Regex.compile!() |> Regex.match?(path)
  def excluded?(%Regex{} = regex, path), do: Regex.match?(regex, path)

  @doc "A compiled `pattern/1`, for matching many paths."
  def compile(nil), do: nil
  def compile(pattern), do: Regex.compile!(pattern)

  defp glob_regex(glob) do
    regex = translate(glob, "", true)

    case Regex.compile("^(?:#{regex})$") do
      {:ok, _} -> regex
      {:error, _} -> escape(glob)
    end
  end

  # `at_segment_start` is whether the next character begins a path segment,
  # which is where `**/` and `/**` have their directory meaning.
  defp translate("", acc, _at_segment_start), do: acc

  defp translate("**/" <> rest, acc, true), do: translate(rest, acc <> "(?:.*/)?", true)
  defp translate("**", acc, true), do: acc <> ".*"
  defp translate("**" <> rest, acc, false), do: translate(rest, acc <> "[^/]*", false)
  defp translate("*" <> rest, acc, _), do: translate(rest, acc <> "[^/]*", false)
  defp translate("?" <> rest, acc, _), do: translate(rest, acc <> "[^/]", false)
  defp translate("/" <> rest, acc, _), do: translate(rest, acc <> "/", true)
  defp translate("\\" <> <<char::utf8, rest::binary>>, acc, _), do: translate(rest, acc <> escape(<<char::utf8>>), false)

  defp translate("[" <> rest = glob, acc, _) do
    case String.split(rest, "]", parts: 2) do
      [class, rest] when class != "" ->
        class =
          case class do
            "!" <> negated -> "^" <> escape_class(negated)
            "^" <> negated -> "^" <> escape_class(negated)
            class -> escape_class(class)
          end

        translate(rest, acc <> "[" <> class <> "]", false)

      _ ->
        <<char::utf8, rest::binary>> = glob
        translate(rest, acc <> escape(<<char::utf8>>), false)
    end
  end

  defp translate(<<char::utf8, rest::binary>>, acc, _), do: translate(rest, acc <> escape(<<char::utf8>>), false)

  defp escape_class(class), do: String.replace(class, ["\\", "[", "^"], &("\\" <> &1))

  # Only the metacharacters both RE2 and PCRE know: RE2 rejects escaped
  # letters, digits and spaces.
  defp escape(text),
    do: String.replace(text, [".", "^", "$", "|", "?", "*", "+", "(", ")", "[", "]", "{", "}", "\\"], &("\\" <> &1))
end
