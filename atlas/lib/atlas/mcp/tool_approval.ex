defmodule Atlas.MCP.ToolApproval do
  @moduledoc """
  A person's sign-off on one call to an approval-gated upstream tool.

  The row pins the exact arguments, so the approval covers that call and no
  other. It is spent by the first matching call after approval and lapses at
  `expires_at` whether or not it was used.
  """
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Users.User

  @statuses ~w(pending approved rejected)

  schema "mcp_tool_approvals" do
    field :server_name, :string
    field :tool_name, :string
    field :arguments, :map, default: %{}
    field :arguments_digest, :string
    field :status, :string, default: "pending"
    field :decided_at, :utc_datetime
    field :consumed_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(approval, attrs) do
    approval
    |> cast(attrs, [:user_id, :server_name, :tool_name, :arguments, :arguments_digest, :status, :expires_at])
    |> validate_required([:user_id, :server_name, :tool_name, :arguments_digest, :status, :expires_at])
    |> validate_inclusion(:status, @statuses)
  end
end
