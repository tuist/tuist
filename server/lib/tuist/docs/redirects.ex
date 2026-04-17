defmodule Tuist.Docs.Redirects do
  @moduledoc """
  Source of truth for documentation URL redirects and the canonical
  paths the rules redirect to.

  Rules operate on the portion of the path after `/<locale>/docs`, i.e.
  the "logical" docs path that always starts with "/". The plug fills in
  the locale and the `/docs` segment.

      {:exact, "/cli", "/references/cli"}
      {:prefix, "/cli/", "/references/cli/"}
      {:prefix, "/references/cli/", "/references/cli/commands/",
       except_starts_with: ["debugging", "directories", "shell-completions", "commands/"]}

  Rules are applied in a loop: if a rule matches, the result is fed back
  through all rules until none match. That way compound moves (e.g. a
  page that moved twice across different PRs) resolve in a single 301.

  ### Canonical paths

  The destination paths (`cli_base`, `cli_commands_base`, …) are also
  exposed as functions so the Renderer and the Sidebar fallback can
  build slugs from the same source as the rules. When URLs move, a
  reviewer sees both the old → new rule and the new canonical path in
  the same diff.
  """

  @cli_base "/references/cli"
  @cli_commands_base @cli_base <> "/commands"
  @cli_static_pages [
    {"debugging", "Debugging"},
    {"directories", "Directories"},
    {"shell-completions", "Shell completions"}
  ]
  @cli_static_slugs Enum.map(@cli_static_pages, &elem(&1, 0))

  @rules [
    # CLI docs moved under References (Diataxis: CLI is reference material)
    {:exact, "/cli", @cli_base},
    {:prefix, "/cli/", @cli_base <> "/"},
    # Auto-generated command pages nested under /references/cli/commands/.
    # The three hand-written pages (debugging, directories, shell-completions)
    # and the /commands/ namespace itself stay flat.
    {:prefix, @cli_base <> "/", @cli_commands_base <> "/", except_starts_with: @cli_static_slugs ++ ["commands/"]}
  ]

  @docs_path_regex ~r{^/(?<locale>[^/]+)/docs(?<rest>/.*)?$}
  @max_iterations 8

  def rules, do: @rules

  @doc "Logical path under `/docs/` where hand-written CLI pages live."
  def cli_base, do: @cli_base

  @doc "Logical path under `/docs/` where auto-generated command pages live."
  def cli_commands_base, do: @cli_commands_base

  @doc """
  Hand-written CLI pages as `{slug_segment, english_label}` tuples.
  The English label is the source string that flows through the
  `priv/docs/strings/*.json` translation map at render time.
  """
  def cli_static_pages, do: @cli_static_pages

  @doc "Slug fragments under `cli_base/` served by hand-written pages (not commands)."
  def cli_static_slugs, do: @cli_static_slugs

  @doc """
  Full English slug (i.e. with the `/en` locale prefix) for a
  hand-written CLI page. For other locales the slug is localized at
  render time by the sidebar, but the filesystem is canonical in `en`.
  """
  def cli_slug(segment), do: "/en" <> @cli_base <> "/" <> segment

  @doc """
  Full English slug for an auto-generated command page.
  Accepts either the command name (`"generate"`) or a full path
  (`"cache/warm"`).
  """
  def cli_command_slug(command_path), do: "/en" <> @cli_commands_base <> "/" <> command_path

  @doc """
  Resolves a request path against the docs redirect rules.

  Returns `{:ok, new_path}` if any rule matches (query string preserved),
  or `:none` otherwise. Rules chain — the result of one rule is fed back
  through all rules until none match further.
  """
  def resolve(request_path, query_string \\ "")

  def resolve(request_path, query_string) when is_binary(request_path) do
    case Regex.named_captures(@docs_path_regex, request_path) do
      %{"locale" => locale, "rest" => rest} ->
        rest = rest || ""

        case apply_chain(rest, @rules, false, @max_iterations) do
          {:ok, new_rest} -> {:ok, build_path(locale, new_rest, query_string)}
          :none -> :none
        end

      nil ->
        :none
    end
  end

  defp apply_chain(path, _rules, changed?, 0) do
    if changed?, do: {:ok, path}, else: :none
  end

  defp apply_chain(path, rules, changed?, remaining) do
    case apply_rules(path, rules) do
      {:ok, new_path} -> apply_chain(new_path, rules, true, remaining - 1)
      :none -> if changed?, do: {:ok, path}, else: :none
    end
  end

  defp apply_rules(_path, []), do: :none

  defp apply_rules(path, [{:exact, from, to} | _rest]) when path == from, do: {:ok, to}

  defp apply_rules(path, [{:prefix, from, to} | rest]) do
    case path do
      ^from <> suffix -> {:ok, to <> suffix}
      _ -> apply_rules(path, rest)
    end
  end

  defp apply_rules(path, [{:prefix, from, to, opts} | rest]) do
    case path do
      ^from <> suffix ->
        if excluded?(suffix, Keyword.get(opts, :except_starts_with, [])) do
          apply_rules(path, rest)
        else
          {:ok, to <> suffix}
        end

      _ ->
        apply_rules(path, rest)
    end
  end

  defp apply_rules(path, [_rule | rest]), do: apply_rules(path, rest)

  defp excluded?(suffix, prefixes), do: Enum.any?(prefixes, &String.starts_with?(suffix, &1))

  defp build_path(locale, rest, "") do
    "/#{locale}/docs#{rest}"
  end

  defp build_path(locale, rest, query_string) do
    "/#{locale}/docs#{rest}?#{query_string}"
  end
end
