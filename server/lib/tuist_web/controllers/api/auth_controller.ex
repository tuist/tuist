defmodule TuistWeb.API.AuthController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.Authentication
  alias Tuist.OAuth.Apple
  alias Tuist.Time
  alias TuistWeb.API.Schemas.AuthenticationTokens

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  @refresh_token_ttl {4, :weeks}
  @access_token_ttl {10, :minutes}

  tags(["Authentication"])

  defmodule Error do
    @moduledoc false
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
    description: "This endpoint returns a token for a given device code if the device code is authenticated.",
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
      accepted: {"The device code is not authenticated", "application/json", %Schema{type: :object}},
      bad_request: {"The request was not accepted, e.g., when the device code is expired", "application/json", Error}
    }
  )

  def device_code(%{path_params: %{"device_code" => device_code_string}} = conn, _params) do
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
        user = Accounts.get_user!(device_code.user_id, preload: [:account])

        {:ok, access_token, _opts} =
          Authentication.encode_and_sign(
            user,
            %{
              email: user.email,
              preferred_username: user.account.name
            },
            token_type: :access,
            ttl: @access_token_ttl
          )

        {:ok, refresh_token, _opts} =
          Authentication.encode_and_sign(
            user,
            %{email: user.email, preferred_username: user.account.name},
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
    description: "This endpoint returns new tokens for a given refresh token if the refresh token is valid.",
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
      unauthorized: {"You need to be authenticated to issue new tokens", "application/json", Error},
      bad_request: {"The token can't be refreshed because it has invalid type", "application/json", Error}
    }
  )

  def refresh_token(%{body_params: %{refresh_token: refresh_token}} = conn, _params) do
    case Authentication.refresh(refresh_token, ttl: @refresh_token_ttl) do
      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "The refresh token is expired or invalid"})

      {:ok, {_old_token, _old_claims}, {new_refresh_token, _new_claims}} ->
        case Authentication.exchange(new_refresh_token, "refresh", "access", ttl: @access_token_ttl) do
          {:ok, _old_token_with_claims, {new_access_token, _new_access_token_claims}} ->
            conn
            |> put_status(:ok)
            |> json(%{
              access_token: new_access_token,
              refresh_token: new_refresh_token
            })

          {:error, reason} ->
            Tuist.Analytics.authentication_token_refresh_error(%{
              reason: if(is_binary(reason), do: reason, else: Atom.to_string(reason)),
              cli_version: TuistWeb.Headers.get_cli_version_string(conn)
            })

            conn
            |> put_status(:unauthorized)
            |> json(%{
              message: "The refresh token is invalid."
            })
        end
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
      unauthorized: {"Invalid email or password.", "application/json", Error},
      too_many_requests: {"You've exceeded the rate limit.", "application/json", Error}
    }
  )

  operation(:authenticate_apple,
    summary: "Authenticate with Apple identity token.",
    description:
      "This endpoint returns API tokens for a given Apple identity token and authorization code from the first-party Tuist iOS app.",
    operation_id: "authenticateApple",
    request_body:
      {"Apple authentication params.", "application/json",
       %Schema{
         type: :object,
         properties: %{
           identity_token: %Schema{
             type: :string,
             description: "The Apple identity token."
           },
           authorization_code: %Schema{
             type: :string,
             description: "The Apple authorization code."
           }
         },
         required: [:identity_token, :authorization_code]
       }},
    responses: %{
      ok: {
        "Successfully authenticated and returned new API tokens.",
        "application/json",
        AuthenticationTokens
      },
      unauthorized: {"Invalid Apple identity token or authorization code.", "application/json", Error},
      bad_request: {"Invalid request parameters.", "application/json", Error}
    }
  )

  def authenticate(conn, params) do
    case TuistWeb.RateLimit.Auth.hit(conn) do
      {:allow, _count} ->
        do_authenticate(conn, params)

      {:deny, _limit} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{message: "You've exceeded the rate limit. Try again later."})
    end
  end

  def do_authenticate(%{body_params: %{email: email, password: password}} = conn, _params) do
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
          Authentication.encode_and_sign(
            user,
            %{email: user.email, preferred_username: user.account.name},
            token_type: :access,
            ttl: @access_token_ttl
          )

        {:ok, refresh_token, _opts} =
          Authentication.encode_and_sign(
            user,
            %{email: user.email, preferred_username: user.account.name},
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

  def authenticate_apple(
        %{body_params: %{identity_token: identity_token, authorization_code: authorization_code}} = conn,
        _params
      ) do
    with {:ok, user} <-
           Apple.verify_apple_identity_token_and_create_user(identity_token, authorization_code),
         {:ok, access_token, _} <-
           Authentication.encode_and_sign(
             user,
             %{email: user.email, preferred_username: user.account.name},
             token_type: :access,
             ttl: @access_token_ttl
           ),
         {:ok, refresh_token, _} <-
           Authentication.encode_and_sign(
             user,
             %{email: user.email, preferred_username: user.account.name},
             token_type: :refresh,
             ttl: @refresh_token_ttl
           ) do
      conn
      |> put_status(:ok)
      |> json(%{access_token: access_token, refresh_token: refresh_token})
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "Apple authentication failed: #{reason}"})
    end
  end
end
