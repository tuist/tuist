defmodule Tuist.Tests.Coverage.ExcludedPaths do
  @moduledoc """
  The paths left out of every coverage figure: generated code, whose lines no
  test is expected to cover and which would otherwise dominate a pull request
  that regenerates it. The same defaults apply to every project for now:

  - `**/Derived/**`: what Tuist generates into a project's `Derived` directory
    (resource and bundle accessors);
  - `**/*.generated.swift`: SwiftGen's and Sourcery's conventional output;
  - `**/*.pb.swift`, `**/*.grpc.swift`: Swift Protobuf and gRPC stubs.

  Dependency checkouts never reach a figure (the parser leaves them out), and
  neither does test code (`is_test`).

  Globs match the whole repository-relative path, with Git's pathspec glob
  rules: `*` and `?` stay within a directory, `**/` matches any number of
  directories, and `/**` everything inside a directory.

  Excluded files are still stored with their line data, and left out of a
  run's totals, targets, files, patch coverage and gaps when those are read.
  """

  @globs ["**/Derived/**", "**/*.generated.swift", "**/*.pb.swift", "**/*.grpc.swift"]

  @doc "The globs every project's coverage leaves out."
  def globs, do: @globs

  @doc """
  One anchored regular expression matching any of the globs, valid for both
  ClickHouse's `match` (RE2) and Elixir's `Regex`, or nil when there are no
  globs.
  """
  def pattern([]), do: nil

  def pattern(globs) when is_list(globs) do
    "^(?:" <> Enum.map_join(globs, "|", &glob_regex/1) <> ")$"
  end

  @doc "The pattern for a project (or its id), as `pattern/1`: the same for every project for now."
  def pattern_for_project(_project), do: pattern(@globs)

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
