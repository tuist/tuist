defmodule Noora.TextInputTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Noora.TextInput

  test "suffix help opens inward from the right edge and is keyboard-focusable" do
    html =
      render_component(&TextInput.text_input/1, %{
        id: "api-url",
        name: "api_url",
        suffix_hint: "The REST API base URL Tuist servers can access."
      })

    assert html =~ ~s(id="api-url-hint")
    assert html =~ ~s(data-positioning-placement="bottom-end")
    assert html =~ ~s(data-part="trigger" tabindex="0")
    assert html =~ "The REST API base URL Tuist servers can access."
  end
end
