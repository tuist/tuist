defmodule Tuist.Docs.Redirects do
  @moduledoc """
  Resolves documentation URL redirects.

  Rules operate on the portion of the path after `/<locale>/docs`, i.e.
  the "logical" docs path that always starts with "/". The plug fills in
  the locale and the `/docs` segment.

      {:exact, "/old-page", "/new-page"}
      {:prefix, "/old-section/", "/new-section/"}

  Rules are applied in a loop: if a rule matches, the result is fed back
  through all rules until none match. That way compound moves (e.g. a
  page that moved twice across different PRs) resolve in a single 301.

  Rule providers live with the docs subsystem that owns the canonical
  destination paths; this module just applies them consistently.
  """

  alias Tuist.Docs.CLI.Paths, as: CLIPaths

  @rule_sources [CLIPaths]

  @docs_path_regex ~r{^/(?<locale>[^/]+)/docs(?<rest>/.*)?$}
  @max_iterations 8

  def rules, do: Enum.flat_map(@rule_sources, & &1.redirect_rules())

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

        case apply_chain(rest, rules(), false, @max_iterations) do
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
