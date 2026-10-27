defmodule Tuist.GitHistory.Repository do
  @moduledoc """
  A Git repository an account's runs come from, identified by its normalized
  remote (`key`: host, owner and name, lowercased). The commit graph, branch
  heads and commit file listings hang off it, so every project that points at
  the repository shares them. Created on first sight of a remote.
  """
  use Ecto.Schema

  schema "git_repositories" do
    field :account_id, :integer
    field :key, :string
    timestamps(type: :utc_datetime)
  end
end
