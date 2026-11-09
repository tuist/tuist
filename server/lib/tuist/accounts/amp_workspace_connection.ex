defmodule Tuist.Accounts.AmpWorkspaceConnection do
  @moduledoc """
  An Amp workspace, optionally narrowed to one Amp project, whose orbs get CI
  access to every project owned by the account.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  schema "account_amp_workspace_connections" do
    field :workspace_id, Ecto.UUID
    field :project_id, Ecto.UUID
    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def changeset(connection \\ %__MODULE__{}, attrs) do
    connection
    |> cast(attrs, [:workspace_id, :project_id], empty_values: [""])
    |> validate_required([:workspace_id])
    |> unique_constraint(:workspace_id,
      name: :account_amp_workspace_connections_account_id_workspace_id_index,
      message: "is already connected to this account"
    )
  end
end
