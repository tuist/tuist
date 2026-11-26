defmodule Atlas.Connections.Provider do
  @moduledoc false

  alias Atlas.Connections.Config

  @providers %{
    "github" => %{
      name: "GitHub",
      authorize_url: "https://github.com/login/oauth/authorize",
      token_url: "https://github.com/login/oauth/access_token",
      profile_url: "https://api.github.com/user",
      # GitHub App permissions come from its registration, not OAuth scopes.
      scopes: ~w(offline_access)
    },
    "slack" => %{
      name: "Slack",
      authorize_url: "https://slack.com/oauth/v2/authorize",
      token_url: "https://slack.com/api/oauth.v2.access",
      profile_url: "https://slack.com/api/auth.test",
      # History and file scopes back the conversation, file and posting tools;
      # the read scopes name a post's conversation and DM partner for its
      # approver. Connections made before a scope was added must reconnect to use it.
      scopes:
        ~w(search:read chat:write channels:history groups:history im:history mpim:history files:read files:write channels:read groups:read im:read mpim:read users:read)
    },
    "google" => %{
      name: "Google",
      authorize_url: "https://accounts.google.com/o/oauth2/v2/auth",
      token_url: "https://oauth2.googleapis.com/token",
      profile_url: "https://www.googleapis.com/oauth2/v3/userinfo",
      scopes: [
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/drive.file",
        "https://www.googleapis.com/auth/calendar.readonly"
      ]
    },
    # Business API transfer requests accept only OAuth. Requests still need an
    # approver's strong customer authentication in Qonto before money moves.
    "qonto" => %{
      name: "Qonto",
      authorize_url: "https://oauth.qonto.com/oauth2/auth",
      token_url: "https://oauth.qonto.com/oauth2/token",
      profile_url: "https://thirdparty.qonto.com/v2/membership",
      scopes: ~w(offline_access membership.read request_transfers.write)
    },
    # Not a personal connection: Atlas.GTM.SocialAccounts holds X grants for
    # post tracking and reuses this config to exchange and refresh them. Access
    # tokens last two hours; offline.access adds a rotating refresh token.
    "x" => %{
      name: "X",
      authorize_url: "https://x.com/i/oauth2/authorize",
      token_url: "https://api.x.com/2/oauth2/token",
      profile_url: "https://api.x.com/2/users/me",
      scopes: ~w(tweet.read users.read offline.access)
    },
    # Also not a personal connection: Atlas.GTM.SocialAccounts holds the grant
    # of a LinkedIn Page administrator and reads that Page's posts and their
    # statistics (Community Management API). LinkedIn's standard web flow uses
    # no PKCE, and the Page is found through the admin's roles, not a profile.
    "linkedin" => %{
      name: "LinkedIn",
      authorize_url: "https://www.linkedin.com/oauth/v2/authorization",
      token_url: "https://www.linkedin.com/oauth/v2/accessToken",
      profile_url: nil,
      scopes: ~w(rw_organization_admin r_organization_social)
    }
  }

  # Each Gmail consent is a separate opt-in on top of the base Google grant.
  # Nothing here sends mail on its own: gmail.compose sends only drafts the
  # mailbox owner approved in Atlas.
  @gmail_consents %{
    "read" => "https://www.googleapis.com/auth/gmail.readonly",
    "compose" => "https://www.googleapis.com/auth/gmail.compose"
  }

  def providers, do: ~w(github slack google qonto)

  @doc "Scopes for the requested Gmail consents (`read`, `compose`); unknown names request nothing."
  def gmail_scopes(consents) when is_list(consents) do
    for {name, scope} <- Enum.sort(@gmail_consents), name in consents, do: scope
  end

  def gmail_scopes(_consents), do: []

  def config(provider) do
    case Map.fetch(@providers, provider) do
      {:ok, config} ->
        {:ok, Map.merge(config, Config.credentials(provider))}

      :error ->
        {:error, :unsupported_provider}
    end
  end

  def configured?(provider) do
    case config(provider) do
      {:ok, %{client_id: id, client_secret: secret}} -> present?(id) and present?(secret)
      _ -> false
    end
  end

  def authorization_url(provider, redirect_uri, state, verifier, opts \\ []) do
    with {:ok, config} <- configured(provider) do
      scopes =
        if provider == "google",
          do: config.scopes ++ gmail_scopes(Keyword.get(opts, :gmail, [])),
          else: config.scopes

      params = %{
        "client_id" => config.client_id,
        "redirect_uri" => redirect_uri,
        "response_type" => "code",
        "state" => state
      }

      params =
        case provider do
          "slack" ->
            Map.put(params, "user_scope", Enum.join(config.scopes, ","))

          "linkedin" ->
            Map.put(params, "scope", Enum.join(config.scopes, " "))

          _ ->
            challenge = :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)

            params
            |> Map.put("scope", Enum.join(scopes, " "))
            |> Map.put("code_challenge", challenge)
            |> Map.put("code_challenge_method", "S256")
        end

      params =
        if provider == "google",
          do: Map.merge(params, %{"access_type" => "offline", "prompt" => "consent"}),
          else: params

      {:ok, config.authorize_url <> "?" <> URI.encode_query(params)}
    end
  end

  def exchange(provider, code, redirect_uri, verifier) do
    params = %{"grant_type" => "authorization_code", "code" => code, "redirect_uri" => redirect_uri}
    params = if provider in ~w(slack linkedin), do: params, else: Map.put(params, "code_verifier", verifier)

    with {:ok, attrs} <- token_request(provider, params),
         {:ok, identity} <- identity(provider, attrs.access_token) do
      {:ok, Map.merge(attrs, identity)}
    end
  end

  def refresh(provider, refresh_token) do
    token_request(provider, %{"grant_type" => "refresh_token", "refresh_token" => refresh_token})
  end

  defp configured(provider) do
    if configured?(provider), do: config(provider), else: {:error, :not_configured}
  end

  defp token_request(provider, params) do
    with {:ok, config} <- configured(provider),
         {:ok, body} <- request(:post, config.token_url, client_credentials(provider, config, params)) do
      # A Slack install may also return a bot token. Only retain the user's token.
      token = if provider == "slack", do: body["authed_user"] || body, else: body

      if provider != "slack" || token["token_type"] == "user",
        do: token_attrs(token),
        else: {:error, :missing_user_token}
    end
  end

  # X requires confidential clients to authenticate with HTTP Basic, not form fields.
  defp client_credentials("x", config, params),
    do: [form: params, auth: {:basic, "#{config.client_id}:#{config.client_secret}"}]

  defp client_credentials(_provider, config, params),
    do: [form: Map.merge(params, %{"client_id" => config.client_id, "client_secret" => config.client_secret})]

  defp token_attrs(%{"access_token" => token} = body) when is_binary(token) and token != "" do
    {:ok,
     %{
       access_token: token,
       refresh_token: body["refresh_token"],
       scopes: String.split(body["scope"] || "", [" ", ","], trim: true),
       expires_at: expires_at(body["expires_in"]),
       needs_authorization: false
     }}
  end

  defp token_attrs(_body), do: {:error, :invalid_token_response}

  defp identity(provider, token) do
    {:ok, config} = config(provider)
    if config.profile_url, do: profile_identity(provider, config, token), else: {:ok, %{}}
  end

  defp profile_identity(provider, config, token) do
    with {:ok, body} <- request(:get, config.profile_url, auth: {:bearer, token}) do
      profile(provider, body)
    end
  end

  defp profile("github", %{"id" => id, "login" => login}) do
    {:ok, %{provider_user_id: to_string(id), account_name: login, workspace_id: nil}}
  end

  defp profile("slack", %{"user_id" => id, "user" => name, "team_id" => team_id} = body) do
    {:ok, %{provider_user_id: id, account_name: "#{name} · #{body["team"] || team_id}", workspace_id: team_id}}
  end

  defp profile("google", %{"sub" => id, "email" => email}) do
    {:ok, %{provider_user_id: id, account_name: email, workspace_id: nil}}
  end

  defp profile("qonto", %{"membership" => %{"id" => id} = membership}) do
    name = Enum.join(Enum.reject([membership["first_name"], membership["last_name"]], &(&1 in [nil, ""])), " ")
    {:ok, %{provider_user_id: id, account_name: membership["email"] || name, workspace_id: nil}}
  end

  defp profile("x", %{"data" => %{"id" => id, "username" => username}}) do
    {:ok, %{provider_user_id: id, account_name: "@" <> username, workspace_id: nil}}
  end

  defp profile(_provider, _body), do: {:error, :invalid_profile_response}

  defp request(method, url, opts) do
    opts = Keyword.merge([headers: [{"accept", "application/json"}], retry: false, redirect: false], opts)

    case Req.request([method: method, url: url] ++ opts) do
      {:ok, %Req.Response{body: %{"error" => "invalid_grant"}}} ->
        {:error, :needs_authorization}

      {:ok, %Req.Response{body: %{"error" => error}}}
      when error in ["invalid_refresh_token", "token_revoked", "bad_refresh_token"] ->
        {:error, :needs_authorization}

      {:ok, %Req.Response{body: %{"ok" => false}}} ->
        {:error, :provider_rejected}

      {:ok, %Req.Response{body: %{"error" => _}}} ->
        {:error, :provider_rejected}

      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, body}

      _ ->
        {:error, :provider_unavailable}
    end
  end

  defp expires_at(nil), do: nil

  defp expires_at(seconds) when is_integer(seconds) and seconds > 0 do
    DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.truncate(:second)
  end

  defp expires_at(seconds) when is_binary(seconds) do
    case Integer.parse(seconds) do
      {seconds, ""} -> expires_at(seconds)
      _ -> nil
    end
  end

  defp expires_at(_seconds), do: nil

  defp present?(value), do: is_binary(value) and value != ""
end
