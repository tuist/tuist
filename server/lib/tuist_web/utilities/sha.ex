defmodule TuistWeb.Utilities.SHA do
  @moduledoc """
  Utilities for formatting commit SHAs.

  This module provides functions to format and display commit SHAs
  consistently across the application.
  """

  @doc """
  Formats a commit SHA for display by taking the first 7 characters.

  ## Parameters

    * `sha` - The commit SHA string, or nil

  ## Examples

      iex> TuistWeb.Utilities.SHA.format_commit_sha("abc123def456789")
      "abc123d"

      iex> TuistWeb.Utilities.SHA.format_commit_sha(nil)
      "None"

      iex> TuistWeb.Utilities.SHA.format_commit_sha("")
      "None"
  """
  @spec format_commit_sha(String.t() | nil) :: String.t()
  def format_commit_sha(nil), do: "None"
  def format_commit_sha(""), do: "None"

  def format_commit_sha(sha) when is_binary(sha) do
    String.slice(sha, 0, 7)
  end
end
