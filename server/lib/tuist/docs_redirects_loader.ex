defmodule Tuist.Docs.Redirects.Loader do
  @moduledoc false

  def load!(locale_redirects_source, vitepress_config_source) do
    redirects =
      ((locale_redirects_source |> File.read!() |> extract_redirect_lines()) ++
         (vitepress_config_source |> File.read!() |> extract_redirect_lines()))
      |> Enum.map(&parse_redirect_line!/1)
      |> Enum.map(fn {from, to} ->
        from = String.replace(from, ":locale", "en")
        to = String.replace(to, ":locale", "en")
        {from, to}
      end)
      |> Enum.reject(fn {from, to} -> excluded_path?(from) or excluded_path?(to) end)
      |> Enum.uniq()
      |> Enum.map(fn {from, to} ->
        %{
          from: from,
          to: to,
          regex: compile_source_pattern(from)
        }
      end)

    route_prefixes =
      redirects
      |> Enum.map(&route_prefix/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == "en"))
      |> Enum.uniq()
      |> Enum.sort()

    {redirects, route_prefixes}
  end

  defp extract_redirect_lines(contents) do
    contents
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(String.starts_with?(&1, "/") and String.ends_with?(&1, "301")))
  end

  defp parse_redirect_line!(line) do
    case Regex.named_captures(~r/^(?<from>\/\S*)\s+(?<to>\S+)\s+301$/, line) do
      %{"from" => from, "to" => to} ->
        {from, to}

      _ ->
        raise ArgumentError, "Invalid docs redirect line: #{line}"
    end
  end

  defp excluded_path?(path) do
    String.starts_with?(path, "/cli") or
      String.starts_with?(path, "/en/cli") or
      String.contains?(path, "/cli/") or
      String.contains?(path, "/project-description/")
  end

  defp route_prefix(%{from: "/" <> rest}) do
    rest
    |> String.split("/", trim: true)
    |> List.first()
  end

  defp route_prefix(_), do: nil

  defp compile_source_pattern("/") do
    ~r/^\/?$/
  end

  defp compile_source_pattern(source_pattern) do
    segments = String.split(source_pattern, "/", trim: true)
    last_index = length(segments) - 1

    regex_source =
      segments
      |> Enum.with_index()
      |> Enum.map_join("", fn {segment, index} ->
        cond do
          segment == "*" and index == last_index ->
            "(?:/(?<splat>.*))?"

          segment == "*" ->
            "/(?<splat>.*)"

          String.starts_with?(segment, ":") ->
            param_name = String.trim_leading(segment, ":")
            "/(?<#{param_name}>[^/]+)"

          true ->
            "/" <> Regex.escape(segment)
        end
      end)

    Regex.compile!("^#{regex_source}/?$")
  end
end
