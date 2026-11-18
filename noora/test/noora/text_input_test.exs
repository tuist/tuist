defmodule Noora.TextInputTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Noora.TextInput

  test "visible label is associated with the explicit input ID" do
    html =
      render_component(&TextInput.text_input/1, %{
        id: "api-url",
        name: "api_url",
        label: "API URL"
      })

    assert html =~ ~r/<label\b[^>]*\bfor="api-url"[^>]*>\s*API URL\s*<\/label>/
    assert html =~ ~r/<input\b[^>]*\bid="api-url"/
  end

  test "visible label is associated with the generated input ID" do
    html =
      render_component(&TextInput.text_input/1, %{
        name: "api_url",
        label: "API URL"
      })

    assert [_, id] = Regex.run(~r/<input\b[^>]*\bid="([^"]+)"/, html)
    assert id != ""

    assert html =~
             ~r/<label\b[^>]*\bfor="#{Regex.escape(id)}"[^>]*>\s*API URL\s*<\/label>/
  end

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

  test "label help is a keyboard-focusable tooltip after the label with an ID stable across renders" do
    assigns = %{
      id: "api-token",
      name: "api_token",
      label: "API access token",
      label_tooltip: "Lets merge request pipelines save cache volumes."
    }

    html = render_component(&TextInput.text_input/1, assigns)

    assert html =~ ~s(id="api-token-label-tooltip")
    assert html =~ ~s(data-positioning-placement="top-start")
    assert html =~ ~s(data-part="trigger" tabindex="0")
    assert html =~ "Lets merge request pipelines save cache volumes."
    assert html == render_component(&TextInput.text_input/1, assigns)
    refute render_component(&TextInput.text_input/1, %{assigns | label_tooltip: nil}) =~ "label-tooltip"
  end
end
