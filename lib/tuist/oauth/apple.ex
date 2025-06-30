defmodule Tuist.OAuth.Apple do
  @moduledoc """
  Apple OAuth client secret generation and authentication for Sign in with Apple.
  """

  alias Tuist.Accounts

  @doc """
  Generates the client secret for Apple OAuth using the private key.
  The client secret is a JWT token that expires in 6 months but cached for 5 months.
  Uses Redis for persistent caching across deployments.
  """
  def client_secret(config \\ []) do
    client_id = Keyword.get(config, :client_id, Tuist.Environment.apple_service_client_id())
    cache_key = [__MODULE__, "client_secret", client_id]

    cache_opts = [
      # 5 months
      ttl: to_timeout(day: 30 * 5),
      persist_across_deployments: true
    ]

    Tuist.KeyValueStore.get_or_update(cache_key, cache_opts, fn ->
      generate_client_secret(client_id)
    end)
  end

  defp generate_client_secret(client_id) do
    UeberauthApple.generate_client_secret(%{
      client_id: client_id,
      # 6 months
      expires_in: 86_400 * 180,
      key_id: Tuist.Environment.apple_private_key_id(),
      team_id: Tuist.Environment.apple_team_id(),
      private_key: Tuist.Environment.apple_private_key()
    })
  end

  @doc """
  Verifies Apple identity token and creates or finds user.
  """
  def verify_apple_identity_token_and_create_user(identity_token, authorization_code) do
    with :ok <- validate_apple_authorization_code(authorization_code) do
      fields = JOSE.JWT.peek_payload(identity_token).fields
      sub = fields["sub"]
      email = fields["email"]

      auth = %Ueberauth.Auth{
        provider: :apple,
        uid: sub,
        info: %Ueberauth.Auth.Info{
          email: email
        },
        extra: %Ueberauth.Auth.Extra{
          raw_info: %{
            user: %{
              "sub" => sub,
              "email" => email
            },
            token: %{
              "identity_token" => identity_token,
              "authorization_code" => authorization_code
            }
          }
        }
      }

      user = Accounts.find_or_create_user_from_oauth2(auth, preload: [:account])
      {:ok, user}
    end
  end

  defp validate_apple_authorization_code(authorization_code) do
    body = %{
      client_id: Tuist.Environment.apple_app_client_id(),
      client_secret: client_secret(client_id: Tuist.Environment.apple_app_client_id()),
      code: authorization_code,
      grant_type: "authorization_code"
    }

    case Req.post("https://appleid.apple.com/auth/token",
           form: body,
           headers: [{"content-type", "application/x-www-form-urlencoded"}]
         ) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: _body}} ->
        {:error, "Apple authorization code validation failed with #{status} error code."}

      {:error, _exception} ->
        {:error, "The request to Apple to validate the token has failed."}
    end
  end
end
