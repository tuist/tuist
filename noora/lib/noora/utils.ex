defmodule Noora.Utils do
  @moduledoc false

  def has_slot_content?(slot, assigns) do
    case slot do
      [%{inner_block: fun} | _] when is_function(fun) ->
        rendered_content?(fun.(assigns, []))

      # LiveView 1.1 compiles slot bodies that don't depend on the
      # component's assigns straight to a Rendered struct instead of a
      # closure, so static slot content must be recognized too.
      [%{inner_block: %Phoenix.LiveView.Rendered{} = rendered} | _] ->
        rendered_content?(rendered)

      _ ->
        false
    end
  end

  # HTML comments don't count as content: with debug annotations on (dev),
  # LiveView wraps every component call in comments, so a slot that renders
  # nothing would otherwise read as filled.
  defp rendered_content?(rendered) do
    rendered
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> String.replace(~r/<!--.*?-->/s, "")
    |> String.trim()
    |> Kernel.!=("")
  end
end
