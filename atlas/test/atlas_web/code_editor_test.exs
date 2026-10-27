defmodule AtlasWeb.CodeEditorTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias AtlasWeb.CodeEditor

  test "keeps an escaped native form input and an inaccessible decorative mirror" do
    source = ~s|{"message":"</textarea><script>alert(1)</script>"}|
    form = to_form(%{"source" => source}, as: :automation)

    html =
      render_component(&CodeEditor.code_editor/1, field: form[:source], label: "Workflow definition", language: "json")

    assert html =~ ~s(phx-hook="CodeEditor")
    assert html =~ ~s(data-language="json")
    assert html =~ ~s(name="automation[source]")
    assert html =~ ~s(maxlength="65536")
    assert html =~ ~s(aria-label="Workflow definition")
    assert html =~ ~s(autocomplete="off")
    assert html =~ ~s(autocorrect="off")
    assert html =~ ~s(aria-hidden="true")
    assert html =~ ~s(phx-update="ignore")
    assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    refute html =~ "<script>"
    refute html =~ "contenteditable"
  end
end
