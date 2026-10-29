defmodule Noora.ButtonTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Noora.Button

  test "renders the defaults from the shared button contract" do
    html = render_component(&Button.button/1, %{label: "Create project"})

    assert html =~ ~s(class="noora-button")
    assert html =~ ~s(data-variant="primary")
    assert html =~ ~s(data-size="large")
    assert html =~ ">Create project</span>"
  end

  test "keeps LiveView navigation in the Phoenix adapter" do
    html = render_component(&Button.button/1, %{label: "Projects", navigate: "/projects"})

    assert html =~ ~s(href="/projects")
    assert html =~ ~s(data-phx-link="redirect")
    assert html =~ ~s(data-phx-link-state="push")
  end
end
