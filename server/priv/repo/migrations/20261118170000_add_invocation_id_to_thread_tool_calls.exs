defmodule Tuist.Repo.Migrations.AddInvocationIdToThreadToolCalls do
  use Ecto.Migration

  # The model's id for a built-in tool call, so a Bash call's command, which
  # the sandbox names after it, finds the call to report build progress on.
  # Nullable: earlier rows and external tool calls have none.
  def change do
    alter table(:thread_tool_calls) do
      add :invocation_id, :string
    end
  end
end
