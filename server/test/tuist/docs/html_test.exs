defmodule Tuist.Docs.HTMLTest do
  use ExUnit.Case, async: true

  alias Tuist.Docs.HTML

  describe "wrap_tables/1" do
    test "wraps table nodes without mutating Phoenix component tags around them" do
      html = """
      <Noora.Alert.alert status="warning" title="1 > 0">
        <p>Read this first.</p>
      </Noora.Alert.alert>
      <table><thead><tr><th>Name</th></tr></thead><tbody><tr><td>Value</td></tr></tbody></table>
      <.localized_link href="/guides/install-tuist">Install Tuist</.localized_link>
      """

      wrapped = HTML.wrap_tables(html)

      assert wrapped =~ ~s(<Noora.Alert.alert status="warning" title="1 > 0">)
      assert wrapped =~ ~s(<.localized_link href="/guides/install-tuist">)
      assert wrapped =~ ~s(<div id="docs-markdown-table-0" class="noora-table" phx-hook="NooraTable">)
      assert wrapped =~ ~s(<div data-part="scroll-container"><table>)
      assert wrapped =~ ~s(<div data-part="scrollbar" aria-hidden="true"><div data-part="scrollbar-content"></div></div>)

      assert wrapped =~
               ~s(<div data-part="overlay-scrollbar" aria-hidden="true"><div data-part="overlay-thumb"></div></div>)

      refute wrapped =~ "<noora.alert.alert"
      refute wrapped =~ "&lt;.localized_link"
    end

    test "wraps table nodes inside Phoenix component tags" do
      html = """
      <Noora.Alert.alert status="warning">
        <table><tbody><tr><td>Warning</td></tr></tbody></table>
      </Noora.Alert.alert>
      """

      wrapped = HTML.wrap_tables(html)

      assert wrapped =~ ~s(<Noora.Alert.alert status="warning">)
      assert wrapped =~ ~s(<div id="docs-markdown-table-0" class="noora-table" phx-hook="NooraTable">)
      assert wrapped =~ ~s(<div data-part="scroll-container"><table>)
      assert wrapped =~ ~s(</Noora.Alert.alert>)
    end
  end
end
