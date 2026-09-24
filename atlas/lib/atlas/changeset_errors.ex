defmodule Atlas.ChangesetErrors do
  @moduledoc """
  Helpers for rendering changeset errors in non-form contexts.
  """

  @doc """
  Formats a changeset's validation errors as a compact string.
  """
  def format(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> inspect()
  end
end
