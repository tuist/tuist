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

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
