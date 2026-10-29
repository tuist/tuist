defmodule TuistWeb.Components.CacheOutputListTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Components.CacheOutputList

  test "uses Xcode's compact hash popover with the copy action inside it" do
    key = "sha256:" <> String.duplicate("a", 64) <> ":0"

    html =
      render_component(&CacheOutputList.cache_output_list/1,
        id: "task-outputs",
        outputs: [%{key: key, label: "CAS object:"}]
      )

    document = Floki.parse_fragment!(html)

    assert length(Floki.find(document, "[data-part=cas-output-item]")) == 1
    assert document |> Floki.find("[data-part=cas-output-label]") |> Floki.text() == "CAS object:..."

    assert document |> Floki.find("[data-part=cas-output-item] [data-part=trigger]") |> Floki.text() ==
             String.slice(key, 0, 40)

    assert document |> Floki.find("[data-part=hash-tooltip-text]") |> Floki.text() == key
    assert length(Floki.find(document, "[data-part=hash-tooltip-content] [data-clipboard-value='#{key}']")) == 1
    assert Floki.find(document, "[data-part=cas-output-item] > button") == []
  end

  test "preserves supplied Xcode types and escapes labels and keys" do
    html =
      render_component(&CacheOutputList.cache_output_list/1,
        id: "xcode-outputs",
        outputs: [%{key: "<script>bad</script>", label: "CAS output <Tree>:"}]
      )

    assert html =~ "CAS output &lt;Tree&gt;:"
    assert html =~ "&lt;script&gt;bad&lt;/script&gt;"
    refute html =~ "<script>"
  end
end
