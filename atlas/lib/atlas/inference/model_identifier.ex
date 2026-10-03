defmodule Atlas.Inference.ModelIdentifier do
  @moduledoc """
  Helpers for upstream model identifiers.
  """

  @provider_format ~r/^[a-z0-9][a-z0-9._-]*$/

  def parse(value) when is_binary(value) do
    case String.split(value, "/", parts: 2) do
      [provider, model] ->
        provider = String.trim(provider)
        model = String.trim(model)

        if valid_provider?(provider) and valid_model_path?(model) do
          {:ok, %{provider: provider, model: model}}
        else
          :error
        end

      _parts ->
        :error
    end
  end

  def parse(_value), do: :error

  def model_path?(value) when is_binary(value) do
    valid_model_path?(value)
  end

  def model_path?(_value), do: false

  def upstream_model(value, selected_provider) when is_binary(value) do
    selected_provider = normalize_provider(selected_provider)

    if selected_provider != "" and String.starts_with?(value, selected_provider <> "/") do
      String.replace_prefix(value, selected_provider <> "/", "")
    else
      value
    end
  end

  def upstream_model(value, _selected_provider), do: value

  def upstream_model(value) do
    case parse(value) do
      {:ok, %{model: model}} -> model
      :error -> value
    end
  end

  defp normalize_provider(provider) when is_binary(provider), do: String.trim(provider)
  defp normalize_provider(_provider), do: ""

  defp valid_provider?(provider), do: Regex.match?(@provider_format, provider)

  defp valid_model_path?(model) do
    model != "" and
      not String.match?(model, ~r/\s/) and
      model
      |> String.split("/")
      |> Enum.all?(&(&1 != ""))
  end
end
