defmodule Noora.ToggleTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Noora.Toggle

  test "ignored label uses the runtime switch ID before JavaScript mounts" do
    for checked <- [false, true] do
      html =
        render_component(&Toggle.toggle/1, id: "workload-configuration", label: "Show configuration", checked: checked)

      assert html =~ ~s(id="switch:workload-configuration")
      assert html =~ ~s(phx-update="ignore")
      assert html =~ ~s(id="workload-configuration")
      assert html =~ "Show configuration"
    end
  end
end
