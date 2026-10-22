defmodule Noora.TextAreaTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  test "forwards native autocomplete and autocorrect attributes" do
    html =
      render_component(&Noora.TextArea.text_area/1,
        id: "source",
        name: "source",
        value: "<script>text</script>",
        autocomplete: "off",
        autocorrect: "off",
        spellcheck: "false"
      )

    assert html =~ ~s(autocomplete="off")
    assert html =~ ~s(autocorrect="off")
    assert html =~ ~s(spellcheck="false")
    assert html =~ "&lt;script&gt;text&lt;/script&gt;"
    refute html =~ "<script>"
  end
end
