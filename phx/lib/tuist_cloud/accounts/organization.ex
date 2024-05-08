defmodule TuistCloud.Accounts.Organization do
  alias TuistCloud.Accounts.Invitation

  @moduledoc ~S"""
  A module that represents the organizations table.
  """
  use Ecto.Schema

  schema "organizations" do
    has_many(:invitations, Invitation)
    timestamps(inserted_at: :created_at)
  end
end
