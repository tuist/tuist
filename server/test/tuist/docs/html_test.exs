defmodule Tuist.Docs.HTMLTest do
  use ExUnit.Case, async: true

  alias Tuist.Docs.HTML

  describe "wrap_code_blocks/1" do
    test "adds copy source markup from rendered code contents" do
      html =
        ~s(<pre><code class="language-sh"><span>tuist</span> <span>registry</span> <span>setup</span> &lt;App&gt;</code></pre>)

      wrapped = HTML.wrap_code_blocks(html)

      assert wrapped =~ ~s(<template data-part="copy-source">tuist registry setup &lt;App&gt;</template>)
      assert wrapped =~ ~s(<div data-part="language">sh</div>)

      assert wrapped =~
               ~s(<div data-part="code"><code><span>tuist</span> <span>registry</span> <span>setup</span> &lt;App&gt;</code>)
    end
  end

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

      assert wrapped =~
               ~s(<div id="docs-markdown-table-0" class="noora-table" phx-hook="NooraTable">)

      assert wrapped =~ ~s(<div data-part="scroll-container"><table>)

      assert wrapped =~
               ~s(<div data-part="scrollbar" aria-hidden="true"><div data-part="scrollbar-content"></div></div>)

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

      assert wrapped =~
               ~s(<div id="docs-markdown-table-0" class="noora-table" phx-hook="NooraTable">)

      assert wrapped =~ ~s(<div data-part="scroll-container"><table>)
      assert wrapped =~ ~s(</Noora.Alert.alert>)
    end

    test "wraps table nodes without mutating code window contents" do
      code_window = """
      <div class="code-window"><div data-part="bar"><div data-part="language">swift</div><div data-part="copy"></div></div><div data-part="code"><code><span style="color:#CF222E">let</span> target <span style="color:#0550AE">=</span> <span style="color:#8250DF">Target</span>(
        name: <span style="color:#0A3069">&quot;App&quot;</span>
      )</code></div></div>
      """

      html = """
      #{code_window}
      <table><tbody><tr><td>Value</td></tr></tbody></table>
      """

      wrapped = HTML.wrap_tables(html)

      assert wrapped =~ String.trim(code_window)

      assert wrapped =~
               ~s(<div id="docs-markdown-table-0" class="noora-table" phx-hook="NooraTable">)

      assert wrapped =~ ~s(<div data-part="scroll-container"><table>)
    end
  end
end
