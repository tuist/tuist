defmodule TuistEx.Analytics.Metadata do
  @moduledoc false

  alias TuistEx.Analytics.Config

  # Collects the customer-supplied `custom_metadata` payload the Tuist
  # dashboards use for filtering and grouping runs.
  #
  # Precedence (highest first):
  #   TUIST_TAGS / TUIST_VALUES environment variables
  #   `--tag foo` / `--value key=val` runtime options
  #   `Mix.Project.config()[:tuist][:tags]` and `[:values]`

  # The server refuses a report whose metadata breaks these rules, so entries
  # that do are left out here: a mistyped tag must not cost the whole report.
  @max_tags 50
  @max_tag_length 50
  @max_values 20
  @max_key_length 50
  @max_value_length 500

  def collect(options \\ []) do
    environment = Keyword.get(options, :environment, &System.get_env/1)
    project = Config.project_tuist_config()

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
    |> Enum.filter(&valid_tag?/1)
    |> Enum.uniq()
    |> Enum.take(@max_tags)
  end

  defp collect_values(options, environment, project) do
    from_env = parse_values(environment.("TUIST_VALUES"))
    from_options = options |> Keyword.get_values(:value) |> Map.new(&parse_value_pair/1)
    from_project = project |> Keyword.get(:values, %{}) |> Map.new()

    from_project
    |> Map.merge(from_options)
    |> Map.merge(from_env)
    |> Map.new(fn {key, value} -> {normalize_string(key), normalize_string(value)} end)
    |> Enum.filter(&valid_value?/1)
    |> Enum.sort()
    |> Enum.take(@max_values)
    |> Map.new()
  end

  defp valid_tag?(tag), do: String.length(tag) <= @max_tag_length and tag =~ ~r/^[a-zA-Z0-9_-]+$/

  defp valid_value?({key, value}) do
    key != "" and value != "" and String.length(key) <= @max_key_length and
      String.length(value) <= @max_value_length
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
end
