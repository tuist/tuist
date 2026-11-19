defmodule Atlas.MCP.Tools.GetMyBusinessProfile do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "get_my_business_profile",
    schema: %{"type" => "object", "properties" => %{}, "additionalProperties" => false},
    output_schema: Atlas.Users.BusinessProfile.schema()

  alias Atlas.MCP.Tool
  alias Atlas.Users.BusinessProfile

  def description,
    do:
      "Read your opt-in shared business routing profile, separate from your private Pip description. Responsibilities use exact subject identifiers such as account:<UUID> or service:<UUID>."

  def execute(conn, args) when map_size(args) == 0 do
    with true <- BusinessProfile.allowed_context?(conn),
         :ok <- Tool.authorize_authenticated(conn, "Your business profile") do
      BusinessProfile.get(Tool.current_user(conn))
    else
      false -> {:error, "Personal routing consent is unavailable to shared Slack identities."}
      error -> error
    end
  end

  def execute(_, _), do: {:error, "This tool accepts no user selector or arguments."}
end
