defmodule TuistWeb.Noora.Utils do
  @moduledoc false

  def has_slot_content?(slot, assigns) do
    case slot do
      [%{inner_block: fun} | _] when is_function(fun) ->
        fun.(assigns, [])
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()
        |> String.trim()
        |> Kernel.!=("")

      _ ->
        false
    end
  end
end
