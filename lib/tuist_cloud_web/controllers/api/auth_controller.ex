defmodule TuistCloudWeb.API.AuthController do
  use OpenApiSpex.ControllerSpecs
  use TuistCloudWeb, :controller
  alias OpenApiSpex.Schema
  alias TuistCloud.Accounts
  alias TuistCloud.Time

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistCloudWeb.RenderAPIErrorPlug
  )

  defmodule Error do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        message: %Schema{
          type: :string
        }
      }
    })
  end

  operation(:device_code,
    summary: "Get a specific device code.",
    description:
      "This endpoint returns a token for a given device code if the device code is authenticated.",
    operation_id: "getDeviceCode",
    parameters: [
      device_code: [
        in: :path,
        type: :string,
        required: true,
        description: "The device code to query."
      ]
    ],
    responses: %{
      ok:
        {"The device code is authenticated", "application/json",
         %Schema{
           title: "AuthenticationToken",
           description: "Token to authenticate the user with.",
           type: :object,
           properties: %{
             token: %Schema{
               type: :string,
               description: "User authentication token"
             }
           }
         }},
      accepted:
        {"The device code is not authenticated", "application/json", %Schema{type: :object}},
      bad_request:
        {"The request was not accepted, e.g., when the device code is expired",
         "application/json", Error}
    }
  )

  def device_code(
        %{path_params: %{"device_code" => device_code_string}} = conn,
        _params
      ) do
    device_code = Accounts.get_device_code(device_code_string)

    cond do
      is_nil(device_code) ->
        conn
        |> put_status(:accepted)
        |> json(%{})

      NaiveDateTime.before?(
        device_code.created_at,
        DateTime.to_naive(DateTime.add(Time.utc_now(), -5, :minute))
      ) ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "The device code has expired."})

      !device_code.authenticated ->
        conn
        |> put_status(:accepted)
        |> json(%{})

      device_code.authenticated ->
        user = Accounts.get_user!(device_code.user_id)

        conn
        |> put_status(:ok)
        |> json(%{
          token: user.token
        })
    end
  end
end
