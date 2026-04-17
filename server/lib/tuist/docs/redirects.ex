defmodule Tuist.Docs.Redirects do
  @moduledoc """
  Source of truth for documentation URL redirects.

  Rules are expressed as tuples and operate on the portion of the path
  after `/<locale>/docs`, i.e. the "logical" docs path that always starts
  with "/". The plug fills in the locale and the `/docs` segment.

      {:exact,  "/cli",  "/references/cli"}
      {:prefix, "/cli/", "/references/cli/"}

  Exact rules match the path exactly. Prefix rules match when the path
  starts with `from` and carry any suffix over to `to`.

  This module is the place to add redirects when docs are renamed or
  reorganized. Keep entries grouped with a comment explaining the move.
  """

  @rules [
    # CLI docs moved under References (Diataxis: CLI is reference material)
    {:exact, "/cli", "/references/cli"},
    {:prefix, "/cli/", "/references/cli/"}
  ]

  @docs_path_regex ~r{^/(?<locale>[^/]+)/docs(?<rest>/.*)?$}

  def rules, do: @rules

  @doc """
  Resolves a request path against the docs redirect rules.

  Returns `{:ok, new_path}` if a rule matches (query string preserved),
  or `:none` otherwise.
  """
  def resolve(request_path, query_string \\ "")

  def resolve(request_path, query_string) when is_binary(request_path) do
    case Regex.named_captures(@docs_path_regex, request_path) do
      %{"locale" => locale, "rest" => rest} ->
        rest = rest || ""

        case apply_rules(rest, @rules) do
          {:ok, new_rest} ->
            {:ok, build_path(locale, new_rest, query_string)}

          :none ->
            :none
        end

      nil ->
        :none
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

  defp apply_rules(path, [_rule | rest]), do: apply_rules(path, rest)

  defp build_path(locale, rest, "") do
    "/#{locale}/docs#{rest}"
  end

  defp build_path(locale, rest, query_string) do
    "/#{locale}/docs#{rest}?#{query_string}"
  end
end
