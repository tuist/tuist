defmodule Atlas.NativeThemes do
  @moduledoc """
  Public, instance-wide appearance data for native clients. No user data or permissions.
  """

  @external_resource Path.expand("../../priv/native_themes.json", __DIR__)
  @defaults @external_resource |> File.read!() |> Jason.decode!()
  @palette_keys ~w(background surface text secondary_text border accent on_accent tint)
  @theme_keys ~w(id name description typography button_radius card_radius light dark)

  def catalog(config \\ Application.get_env(:atlas, :native_theme_catalog)) do
    case validate(config) do
      {:ok, catalog} -> catalog
      :error -> @defaults
    end
  end

  def validate(%{
        "schema_version" => 1,
        "revision" => revision,
        "default_theme_id" => default,
        "themes" => themes
      })
      when is_list(themes) and length(themes) in 1..16 do
    ids = Enum.map(themes, fn theme -> if is_map(theme), do: theme["id"] end)

    if text?(revision, 128) and default in ids and Enum.uniq(ids) == ids and
         Enum.all?(themes, &theme?/1) do
      {:ok,
       %{
         "schema_version" => 1,
         "revision" => revision,
         "default_theme_id" => default,
         "themes" =>
           Enum.map(themes, fn theme ->
             theme
             |> Map.take(@theme_keys)
             |> Map.update!("light", &Map.take(&1, @palette_keys))
             |> Map.update!("dark", &Map.take(&1, @palette_keys))
           end)
       }}
    else
      :error
    end
  end

  def validate(_), do: :error

  defp theme?(theme) when is_map(theme) do
    text?(theme["id"], 64) and Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, theme["id"]) and
      theme["id"] != "server-default" and
      text?(theme["name"], 80) and text?(theme["description"], 160) and
      theme["typography"] in ~w(standard strong rounded) and radius?(theme["button_radius"], 24) and
      radius?(theme["card_radius"], 32) and palette?(theme["light"]) and palette?(theme["dark"])
  end

  defp theme?(_), do: false

  defp text?(value, max),
    do: is_binary(value) and byte_size(value) in 1..max and String.trim(value) != ""

  defp radius?(value, max), do: is_number(value) and value >= 0 and value <= max

  defp palette?(palette) when is_map(palette) do
    Enum.all?(@palette_keys, fn key ->
      is_binary(palette[key]) and Regex.match?(~r/^#[0-9a-fA-F]{6}$/, palette[key])
    end) and
      Enum.all?(~w(background surface), fn surface ->
        Enum.all?(~w(text secondary_text tint), &(contrast(palette[&1], palette[surface]) >= 4.5))
      end) and contrast(palette["accent"], palette["on_accent"]) >= 4.5
  end

  defp palette?(_), do: false

  defp contrast(left, right) do
    a = luminance(left)
    b = luminance(right)
    (max(a, b) + 0.05) / (min(a, b) + 0.05)
  end

  defp luminance("#" <> hex) do
    hex
    |> Base.decode16!(case: :mixed)
    |> :binary.bin_to_list()
    |> Enum.zip([0.2126, 0.7152, 0.0722])
    |> Enum.reduce(0, fn {channel, weight}, sum ->
      value = channel / 255

      linear =
        if value <= 0.04045, do: value / 12.92, else: :math.pow((value + 0.055) / 1.055, 2.4)

      sum + linear * weight
    end)
  end
end
