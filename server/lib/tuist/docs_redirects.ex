defmodule Tuist.Docs.Redirects do
  @moduledoc """
  Redirect rules for documentation legacy URLs.
  """

  alias Tuist.Docs
  alias Tuist.Docs.Redirects.Loader

  @locale_redirects_source Path.expand("../../../docs/.vitepress/locale-redirects.txt", __DIR__)
  @vitepress_config_source Path.expand("../../../docs/.vitepress/config.mjs", __DIR__)

  @external_resource @locale_redirects_source
  @external_resource @vitepress_config_source

  {redirects, route_prefixes} =
    Loader.load!(@locale_redirects_source, @vitepress_config_source)

  @redirects redirects
  @route_prefixes route_prefixes

  def route_prefixes, do: @route_prefixes

  def redirect_path(path) when is_binary(path) do
    normalized_path = Docs.normalize_path(path)

    Enum.find_value(@redirects, fn %{regex: regex, to: destination_template} ->
      case Regex.named_captures(regex, normalized_path) do
        nil ->
          nil

        captures ->
          destination =
            destination_template
            |> apply_captures(captures)
            |> Docs.normalize_path()

          if destination == normalized_path, do: nil, else: destination
      end
    end)
  end

  defp apply_captures(template, captures) do
    Enum.reduce(captures, template, fn {key, value}, acc ->
      String.replace(acc, ":" <> key, value)
    end)
  end
end
