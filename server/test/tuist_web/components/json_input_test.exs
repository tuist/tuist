defmodule TuistWeb.Components.JSONInputTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Components.JSONInput

  defp render_input(value, options \\ []) do
    render_component(
      &JSONInput.json_input/1,
      Keyword.merge([id: "claims", name: "policy[claims]", label: "Claims", value: value], options)
    )
  end

  defp textarea_value(document) do
    escaped = document |> Floki.find("textarea") |> Floki.text()
    "<span>value:#{escaped}</span>" |> Floki.parse_fragment!() |> Floki.text() |> String.replace_prefix("value:", "")
  end

  test "keeps a named, labelled native textarea and a decorative, initially hidden overlay" do
    source = ~s({"sub":"production","count":42,"protected":true})
    document = source |> render_input() |> Floki.parse_fragment!()
    textarea = Floki.find(document, "textarea#claims")

    assert Floki.attribute(textarea, "name") == ["policy[claims]"]
    assert Floki.attribute(textarea, "aria-label") == ["Claims"]
    assert [_] = Floki.find(document, "#claims-container.json-input[phx-hook=JSONInput]")
    assert Floki.attribute(textarea, "phx-hook") == []
    assert Floki.attribute(textarea, "phx-debounce") == ["150"]
    assert Floki.attribute(textarea, "maxlength") == ["8192"]
    assert Floki.attribute(textarea, "spellcheck") == ["false"]
    assert textarea_value(document) == source
    assert [_] = Floki.find(document, "[data-part=overlay][hidden][inert][aria-hidden=true]")
    assert Floki.attribute(Floki.find(document, "[data-part=highlight]"), "data-source") == [source]
    assert Floki.text(Floki.find(document, ".property")) =~ "sub"
    assert Floki.text(Floki.find(document, ".string")) =~ "production"
    assert Floki.text(Floki.find(document, ".number")) == "42"
    assert Floki.text(Floki.find(document, ".boolean")) == "true"
    assert Floki.find(document, "[data-highlighted]") == []
  end

  test "escapes HTML in both valid and incomplete JSON without changing the draft" do
    for source <- [
          ~s|{"sub":"</textarea><img src=x onerror=alert(1)>&"}|,
          ~s|{"sub":"</code><script>alert(1)</script>|
        ] do
      document = source |> render_input() |> Floki.parse_fragment!()
      assert Floki.find(document, "img, script") == []
      assert textarea_value(document) == source
      assert Floki.attribute(Floki.find(document, "[data-part=highlight]"), "data-source") == [source]
    end
  end

  test "preserves whitespace, Unicode, trailing lines and incomplete JSON" do
    for source <- [~s({\n\t"sub": "café 🚀",\n), "{}\n\n", ~s({\r\n"sub":"x"\r\n})] do
      document = source |> render_input() |> Floki.parse_fragment!()
      assert textarea_value(document) == source
      assert Floki.attribute(Floki.find(document, "[data-part=highlight]"), "data-source") == [source]
    end
  end

  test "retains the plain textarea for empty and over-8-KiB input, including multibyte text" do
    for source <- ["", String.duplicate(" ", 8193), String.duplicate("é", 4097)] do
      document = source |> render_input() |> Floki.parse_fragment!()
      assert textarea_value(document) == source
      assert Floki.find(document, "[data-part=highlight]") == []
    end
  end

  test "highlights the 8-KiB boundary without relaxing field errors" do
    source = String.pad_trailing("{}", 8192)
    document = source |> render_input(error: "Claims must match exactly.") |> Floki.parse_fragment!()
    assert [_] = Floki.find(document, "[data-part=highlight]")
    assert Floki.text(Floki.find(document, ".noora-text-area[data-error]")) =~ "Claims must match exactly."
  end
end
