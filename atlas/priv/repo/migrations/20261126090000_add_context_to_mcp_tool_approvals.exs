defmodule Atlas.Repo.Migrations.AddContextToMcpToolApprovals do
  use Ecto.Migration

  # What Atlas looked up to help the person decide, such as a Slack post's
  # conversation name and file previews. It is not part of the digest, so it
  # never changes what an approval covers.
  def change do
    alter table(:mcp_tool_approvals) do
      add :context, :map, null: false, default: %{}
    end
  end
end
