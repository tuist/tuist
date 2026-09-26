defmodule TuistEx.Analytics.Metadata do
  @moduledoc false

  # Collects the customer-supplied `custom_metadata` payload the Tuist
  # dashboards use for filtering and grouping runs.
  #
  # Precedence (highest first):
  #   TUIST_TAGS / TUIST_VALUES environment variables
  #   `--tag foo` / `--value key=val` runtime options
  #   `Mix.Project.config()[:tuist][:tags]` and `[:values]`

  def collect(options \\ []) do
    environment = Keyword.get(options, :environment, &System.get_env/1)
    project = project_tuist_config()

    tags = collect_tags(options, environment, project)
    values = collect_values(options, environment, project)

    if !(tags == [] and map_size(values) == 0) do
      %{tags: tags, values: values}
    end
  end

  defp collect_tags(options, environment, project) do
    from_env = parse_tags(environment.("TUIST_TAGS"))
    from_options = List.wrap(Keyword.get_values(options, :tag))
    from_project = List.wrap(Keyword.get(project, :tags, []))

    (from_env ++ from_options ++ from_project)
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp collect_values(options, environment, project) do
    from_env = parse_values(environment.("TUIST_VALUES"))
    from_options = options |> Keyword.get_values(:value) |> Map.new(&parse_value_pair/1)
    from_project = project |> Keyword.get(:values, %{}) |> Map.new()

    from_project
    |> Map.merge(from_options)
    |> Map.merge(from_env)
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    |> Map.new(fn {k, v} -> {normalize_string(k), normalize_string(v)} end)
  end

  defp parse_tags(nil), do: []
  defp parse_tags(""), do: []

  defp parse_tags(binary) when is_binary(binary),
    do: binary |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

  defp parse_values(nil), do: %{}
  defp parse_values(""), do: %{}

  defp parse_values(binary) when is_binary(binary) do
    binary
    |> String.split(",", trim: true)
    |> Map.new(&parse_value_pair/1)
  end

  defp parse_value_pair(pair) when is_binary(pair) do
    case String.split(pair, "=", parts: 2) do
      [key, value] -> {String.trim(key), String.trim(value)}
      [key] -> {String.trim(key), ""}
    end
  end

  defp parse_value_pair(_), do: {"", ""}

  defp normalize_string(nil), do: ""
  defp normalize_string(value) when is_binary(value), do: value
  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string(value), do: to_string(value)

  defp project_tuist_config do
    case Mix.Project.config()[:tuist] do
      value when is_list(value) -> value
      _ -> []
    end
  rescue
    _ -> []
  end
end
