defmodule TuistWeb.Marketing.Components.SetupPromptTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Marketing.Components.SetupPrompt

  test "renders a manually selectable prompt with progressive clipboard enhancement" do
    document =
      (&SetupPrompt.setup_prompt/1)
      |> render_component(id: "setup")
      |> Floki.parse_fragment!()

    assert document |> Floki.find("code[data-part=prompt]") |> Floki.text() |> String.trim() ==
             "Connect my project to Tuist (https://tuist.dev)"

    assert Floki.attribute(document, "#setup", "data-static-hook") == ["SetupPrompt"]
    assert Floki.find(document, "button[data-part=copy][type=button][disabled]") != []
    assert Floki.attribute(document, "button", "aria-describedby") == ["setup-instructions"]
    assert Floki.find(document, "[data-part=status][role=status][aria-live=polite]") != []

    assert Floki.attribute(document, "#setup", "data-error-message") == [
             "Couldn't copy. Select the prompt and copy it manually."
           ]
  end

  test "uses the caller's ID for the instructions" do
    document =
      (&SetupPrompt.setup_prompt/1)
      |> render_component(id: "another-setup")
      |> Floki.parse_fragment!()

    assert Floki.find(document, "#another-setup-instructions") != []
    assert Floki.attribute(document, "button", "aria-describedby") == ["another-setup-instructions"]
  end
end
