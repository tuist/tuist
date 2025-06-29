defmodule Tuist.OAuth do
  @moduledoc """
  A module for managing OAuth clients and related operations.
  """

  alias Boruta.Ecto.Client

  @doc """
  Creates an OAuth client with the specified configuration.
  """
  def create_client do
    id = SecureRandom.uuid()
    secret = SecureRandom.hex(64)
    private_key = JOSE.JWK.generate_key({:rsa, 2048, 65_537})
    public_key = JOSE.JWK.to_public(private_key)
    {_type, public_pem} = JOSE.JWK.to_pem(public_key)
    {_type, private_pem} = JOSE.JWK.to_pem(private_key)

    client_attrs = %{
      id: id,
      secret: secret,
      name: "Tuist",
      # one day
      access_token_ttl: 60 * 60 * 24,
      # one minute
      authorization_code_ttl: 60,
      # one month
      refresh_token_ttl: 60 * 60 * 24 * 30,
      # one day
      id_token_ttl: 60 * 60 * 24,
      id_token_signature_alg: "RS256",
      userinfo_signed_response_alg: "RS256",
      redirect_uris: ["tuist://oauth-callback"],
      authorize_scope: false,
      supported_grant_types: [
        "client_credentials",
        "password",
        "authorization_code",
        "refresh_token",
        "implicit",
        "revoke",
        "introspect"
      ],
      pkce: true,
      public_refresh_token: false,
      public_revoke: false,
      confidential: false,
      token_endpont_auth_methods: [
        "client_secret_basic",
        "client_secret_post",
        "client_secret_jwt",
        "private_key_jwt"
      ],
      token_endpoint_jwt_auth_alg: "HS256",
      jwt_public_key: nil
    }

    %Client{}
    |> Client.create_changeset(client_attrs)
    |> Client.key_pair_changeset(%{
      public_key: public_pem,
      private_key: private_pem
    })
    |> Boruta.Config.repo().insert()
  end
end
