defmodule TuistWeb.ColocatedCSS do
  @moduledoc false
  use Phoenix.LiveView.ColocatedCSS

  @impl true
  def transform("style", _attributes, css, _metadata), do: {:ok, css, []}
end
