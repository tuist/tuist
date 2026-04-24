defmodule Tuist.Marketing.Customers.CaseParser do
  @moduledoc false
  alias Tuist.Marketing.MDExConverter

  def parse(path, contents) do
    [frontmatter_string, body] =
      contents |> String.replace(~r/^---\n/, "") |> String.split(["\n---\n"], parts: 2)

    frontmatter = YamlElixir.read_from_string!(frontmatter_string)
    {body_html, _} = MDExConverter.compile_markdown(body, path, false)

    translations =
      frontmatter
      |> Map.get("translations", %{})
      |> Enum.into(%{}, fn {locale, translation} ->
        {locale, compile_translation_body(translation, path, locale)}
      end)

    {Map.put(frontmatter, "translations", translations), body_html}
  end

  defp compile_translation_body(translation, path, locale) do
    case Map.get(translation, "body") do
      nil ->
        translation

      body ->
        {body_html, _} = MDExConverter.compile_markdown(body, "#{path}:#{locale}", false)
        Map.put(translation, "body", body_html)
    end
  end
end
