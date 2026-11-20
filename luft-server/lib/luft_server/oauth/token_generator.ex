defmodule LuftServer.OAuth.TokenGenerator do
  @moduledoc "Boruta token serialization for the claims Luft native clients display."
  @behaviour Boruta.Oauth.TokenGenerator

  alias Boruta.Ecto.Token
  alias LuftServer.OAuth.Clients
  alias LuftServer.Sessions
  alias LuftServerWeb.Endpoint
  alias Plug.Crypto.KeyGenerator

  @impl true
  def generate(:access_token, %Token{type: "access_token", sub: id, access_token_ttl: ttl}) do
    session = Sessions.get_by_id(id)
    now = System.system_time(:second)

    claims = %{
      "iss" => "luft",
      "aud" => Clients.client_id(),
      "sub" => session.user_sub,
      "sid" => session.id,
      "type" => "account",
      "preferred_username" => session.handle,
      "email" => session.email,
      "iat" => now,
      "exp" => min(now + ttl, DateTime.to_unix(session.expires_at)),
      "jti" => Boruta.TokenGenerator.generate()
    }

    secret = Application.fetch_env!(:luft_server, Endpoint)[:secret_key_base]

    key =
      secret
      |> KeyGenerator.generate("luft native access signing v1",
        length: 32,
        cache: Plug.Crypto.Keys
      )
      |> JOSE.JWK.from_oct()

    {_, access} = key |> JOSE.JWT.sign(%{"alg" => "HS256"}, claims) |> JOSE.JWS.compact()
    access
  end

  def generate(:refresh_token, token),
    do: "luft_refresh_" <> Boruta.TokenGenerator.generate(:refresh_token, token)

  def generate(type, token), do: Boruta.TokenGenerator.generate(type, token)

  @impl true
  defdelegate secret(client), to: Boruta.TokenGenerator

  @impl true
  defdelegate tx_code_input_mode(), to: Boruta.TokenGenerator

  @impl true
  defdelegate tx_code_length(), to: Boruta.TokenGenerator
end
