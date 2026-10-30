defmodule Atlas.MCP.Tools.ListCodingRepositories do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "list_coding_repositories",
    schema: %{
      "type" => "object",
      "properties" => %{
        "installation_id" => %{"type" => "string", "pattern" => "^[1-9][0-9]{0,19}$"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.CodingRepositories.catalog_schema()

  alias Atlas.CodingRepositories
  alias Atlas.MCP.Tool

  def description,
    do:
      "List your GitHub App installations, personal coding settings and repositories accessible to both you and the selected installation. Omit installation_id to use your saved source. No credentials, local paths or execution authority are returned."

  def execute(conn, args) do
    with true <- CodingRepositories.allowed_context?(conn),
         :ok <- Tool.authorize_authenticated(conn, "Personal coding repositories"),
         true <- Map.keys(args) -- ["installation_id"] == [],
         {:ok, catalog} <- CodingRepositories.catalog(Tool.current_user(conn), Map.get(args, "installation_id", :saved)) do
      {:ok, catalog}
    else
      false -> {:error, "Personal repository discovery is unavailable in this context or the arguments are invalid."}
      {:error, reason} when is_atom(reason) -> {:error, CodingRepositories.error_message(reason)}
      error -> error
    end
  end
end
