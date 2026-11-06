defmodule Atlas.MCP.Tools.UpdateMyBusinessProfile do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "update_my_business_profile",
    schema: Atlas.Users.BusinessProfile.schema(),
    output_schema: Atlas.Users.BusinessProfile.schema()

  alias Atlas.MCP.Tool
  alias Atlas.Users.BusinessProfile

  def description,
    do:
      "Replace only your shared business routing profile when explicitly asked. Enabling opts into automatic matching and sharing routing reasons with source readers. Use exact account/service subject IDs, expertise tags and a business role. This grants no permissions and never edits your private Pip description."

  def execute(conn, args) do
    with true <- BusinessProfile.allowed_context?(conn),
         :ok <- Tool.authorize_authenticated(conn, "Your business profile") do
      case BusinessProfile.update(Tool.current_user(conn), args, interface: "mcp") do
        {:ok, profile} -> {:ok, profile}
        {:error, _} -> {:error, "Invalid shared business profile."}
      end
    else
      false -> {:error, "Personal routing consent is unavailable to shared Slack identities."}
      error -> error
    end
  end
end
