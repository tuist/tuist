defmodule Tuist.Marketing.MDExConverterTest do
  use ExUnit.Case, async: true

  alias Tuist.Marketing.MDExConverter

  describe "compile_markdown/3 for live posts" do
    test "renders code blocks whose content contains curly braces" do
      markdown = """
      ```json
      {"headers": {"Authorization": ["Bearer <token>"]}}
      ```
      """

      html = render_live(markdown)

      assert html =~ "Authorization"
    end

    test "renders mermaid diagrams whose content contains curly braces" do
      markdown = """
      ```mermaid
      graph LR
        A{decision} --> B
      ```
      """

      html = render_live(markdown)

      assert html =~ "A{decision}"
    end
  end

  defp render_live(markdown) do
    {_html, template} = MDExConverter.compile_markdown(markdown, "live.md", true)
    {rendered, _binding} = Code.eval_quoted(template, [assigns: %{}], __ENV__)

    rendered
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
