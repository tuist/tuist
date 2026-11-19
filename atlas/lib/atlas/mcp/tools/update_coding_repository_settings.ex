defmodule Atlas.MCP.Tools.UpdateCodingRepositorySettings do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "update_coding_repository_settings",
    schema: Atlas.CodingRepositories.settings_schema(),
    output_schema: Atlas.CodingRepositories.settings_schema()

  alias Atlas.CodingRepositories
  alias Atlas.MCP.Tool

  def description,
    do:
      "When explicitly requested, set your GitHub installation and default repository for new private coding conversations. Use null to clear either preference. Existing conversations and runs are unchanged; this never clones code, selects a machine or grants execution permission."

  def execute(conn, args) do
    with true <- CodingRepositories.allowed_context?(conn),
         :ok <- Tool.authorize_authenticated(conn, "Personal coding repositories"),
         {:ok, settings} <- CodingRepositories.update(Tool.current_user(conn), args) do
      {:ok, settings}
    else
      false -> {:error, "Personal coding preferences are unavailable to shared Slack identities."}
      {:error, reason} when is_atom(reason) -> {:error, CodingRepositories.error_message(reason)}
      error -> error
    end
  end
end
