defmodule Tuist.Ecto.Utils do
  @moduledoc ~S"""
  This module provides Ecto-related utilities.
  """

  @doc """
  Given a changelog, it returns true if it contains a unique constraint error for the given field.
  """
  def unique_error?(%{errors: errors}, field) do
    Enum.any?(errors, fn
      {^field, {_, [constraint: :unique, constraint_name: _]}} ->
        true

      _ ->
        false
    end)
  end

  def unique_error?(_changeset, _field) do
    true
  end
end
