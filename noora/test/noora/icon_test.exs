defmodule Noora.IconTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Noora.Icon

  test "mirrors directional icons in right-to-left documents, but not media or clock icons" do
    for render <- [
          fn -> render_component(&Icon.icon/1, %{name: "chevron_right"}) end,
          fn -> render_component(&Icon.chevron_right/1, %{}) end,
          fn ->
            render_component(&Icon.icon/1, %{
              id: "disclosure",
              name: "chevron_right",
              active_name: "chevron_down",
              transition: "morph"
            })
          end
        ] do
      assert render.() =~ ~r/<svg[^>]*\sdata-rtl-mirror/
    end

    refute render_component(&Icon.icon/1, %{name: "player_play"}) =~ "data-rtl-mirror"
    refute render_component(&Icon.history/1, %{}) =~ "data-rtl-mirror"
  end
end
