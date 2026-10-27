defmodule Atlas.Engineering.Specs.Status do
  @moduledoc false

  @values [:draft, :proposed, :approved, :paused, :rejected, :in_progress, :shipped, :archived]

  def values, do: @values
end
