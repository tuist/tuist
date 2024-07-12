defmodule TuistCloudWeb.API.AuthController do
  use OpenApiSpex.ControllerSpecs
  use TuistCloudWeb, :controller
  alias TuistCloudWeb.API.Schemas.AuthenticationTokens
  alias TuistCloudWeb.Authentication
  alias TuistCloud.Authentication
  alias OpenApiSpex.Schema
  alias TuistCloud.Accounts
  alias TuistCloud.Time

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistCloudWeb.RenderAPIErrorPlug
  )

  @refresh_token_ttl {4, :weeks}
  @access_token_ttl {10, :minutes}

  tags ["Authentication"]

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
           title: "DeviceCodeAuthenticationTokens",
           description: "Token to authenticate the user with.",
           type: :object,
           properties: %{
             token: %Schema{
               type: :string,
               description: "User authentication token",
               deprecated: true
             },
             access_token: %Schema{
               type: :string,
               description: "A short-lived token to authenticate API requests as user."
             },
             refresh_token: %Schema{
               type: :string,
               description: "A token to generate new access tokens when they expire."
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

        {:ok, access_token, _opts} =
          Authentication.encode_and_sign(user, %{},
            token_type: :access,
            ttl: @access_token_ttl
          )

        {:ok, refresh_token, _opts} =
          Authentication.encode_and_sign(user, %{},
            token_type: :refresh,
            ttl: @refresh_token_ttl
          )

        conn
        |> put_status(:ok)
        |> json(%{
          token: user.token,
          access_token: access_token,
          refresh_token: refresh_token
        })
    end
  end

  operation(:refresh_token,
    summary: "Request new tokens.",
    description:
      "This endpoint returns new tokens for a given refresh token if the refresh token is valid.",
    operation_id: "refreshToken",
    request_body:
      {"Token params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           refresh_token: %Schema{
             type: :string,
             description: "User refresh token"
           }
         },
         required: [:refresh_token]
       }},
    responses: %{
      ok: {
        "Succcessfully generated new API tokens.",
        "application/json",
        AuthenticationTokens
      },
      unauthorized:
        {"You need to be authenticated to issue new tokens", "application/json", Error}
    }
  )

  def refresh_token(
        %{
          body_params: %{
            refresh_token: refresh_token
          }
        } = conn,
        _params
      ) do
    case Authentication.refresh(refresh_token, ttl: @refresh_token_ttl) do
      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "The refresh token is expired or invalid"})

      {:ok, _old_token, {new_refresh_token, _new_claims}} ->
        {:ok, _old_token_with_claims, {new_access_token, _new_access_token_claims}} =
          Authentication.exchange(new_refresh_token, "refresh", "access", ttl: @access_token_ttl)

        conn
        |> put_status(:ok)
        |> json(%{
          access_token: new_access_token,
          refresh_token: new_refresh_token
        })
    end
  end

  operation(:authenticate,
    summary: "Authenticate with email and password.",
    description: "This endpoint returns API tokens for a given email and password.",
    operation_id: "authenticate",
    request_body:
      {"Authentication params.", "application/json",
       %Schema{
         type: :object,
         properties: %{
           email: %Schema{
             type: :string,
             description: "The email to authenticate with."
           },
           password: %Schema{
             type: :string,
             description: "The password to authenticate with."
           }
         },
         required: [:email, :password]
       }},
    responses: %{
      ok: {
        "Successfully authenticated and returned new API tokens.",
        "application/json",
        AuthenticationTokens
      },
      unauthorized: {"Invalid email or password.", "application/json", Error}
    }
  )

  def authenticate(
        %{
          body_params: %{
            email: email,
            password: password
          }
        } = conn,
        _params
      ) do
    case Accounts.get_user_by_email_and_password(email, password) do
      {:error, :not_confirmed} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "Please confirm your account before logging in."})

      {:error, :invalid_email_or_password} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "Invalid email or password."})

      {:ok, user} ->
        {:ok, access_token, _opts} =
          Authentication.encode_and_sign(user, %{},
            token_type: :access,
            ttl: @access_token_ttl
          )

        {:ok, refresh_token, _opts} =
          Authentication.encode_and_sign(user, %{},
            token_type: :refresh,
            ttl: @refresh_token_ttl
          )

        conn
        |> put_status(:ok)
        |> json(%{
          access_token: access_token,
          refresh_token: refresh_token
        })
    end
  end
end
