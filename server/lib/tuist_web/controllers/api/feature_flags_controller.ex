defmodule TuistWeb.API.FeatureFlagsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts.User
  alias Tuist.FeatureFlags
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

  tags ["Feature flags"]

  operation(:index,
    summary: "Lists the feature flags enabled for the signed-in user",
    description:
      "Returns the flags the Tuist app uses to show or hide features. Flags missing from the list are off, including flags this server doesn't know about. Only a user session or the signed-in Tuist app can read them.",
    operation_id: "listFeatureFlags",
    responses: %{
      ok:
        {"The enabled feature flags", "application/json",
         %Schema{
           title: "FeatureFlags",
           type: :object,
           properties: %{
             enabled: %Schema{
               type: :array,
               items: %Schema{type: :string},
               description: "The names of the enabled flags. Known values: `ai`."
             }
           },
           required: [:enabled]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"Only a signed-in user can read feature flags", "application/json", Error}
    }
  )

  def index(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case Authentication.app_user(conn) do
      %User{} = user ->
        json(conn, %{enabled: FeatureFlags.app_flags(user)})

      nil ->
        conn |> put_status(:forbidden) |> json(%{message: "Only a signed-in user can read feature flags."})
    end
  end
end
