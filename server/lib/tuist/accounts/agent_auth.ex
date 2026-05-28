defmodule Tuist.Accounts.AgentAuth do
  @moduledoc """
  Workflow for [auth.md](https://workos.com/auth-md) agent registrations.

  Owns identity-assertion verification (ID-JAG), JTI replay protection, the
  email-claim ceremony (claim tokens, claim-view tokens, OTPs), credential
  issuance for access tokens and API keys, audit-event recording, and
  revocation. Lives on its own so the broader `Tuist.Accounts` context stays
  focused on general account management; `Tuist.Accounts` exposes the public
  API via thin delegators so existing callers do not need to know about this
  module.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AgentAuthJTI
  alias Tuist.Accounts.AgentRegistration
  alias Tuist.Accounts.AgentRegistrationEvent
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Repo
  alias Tuist.Time

  require Logger

  @scopes ["mcp"]
  @claim_token_ttl_seconds 30 * 60
  @otp_ttl_seconds 10 * 60
  @access_token_ttl_seconds 24 * 60 * 60
  @max_otp_attempts 5

  def scopes, do: @scopes

  def create_registration(
        %{email: email, requested_credential_type: requested_credential_type, claim_view_url: claim_view_url} = attrs
      )
      when requested_credential_type in [:access_token, :api_key] and is_function(claim_view_url, 1) do
    email = normalize_email(email)

    with :ok <- validate_email(email),
         :ok <- ensure_sso_policy_satisfied(email) do
      now = Time.utc_now()
      claim = build_claim_bundle()

      claim_token_expires_at = DateTime.add(now, @claim_token_ttl_seconds, :second)
      otp_expires_at = DateTime.add(now, @otp_ttl_seconds, :second)

      changeset =
        AgentRegistration.create_email_verification_changeset(%{
          registration_type: :email_verification,
          status: :pending,
          requested_credential_type: requested_credential_type,
          email: email,
          claim_token_hash: claim.claim_token_hash,
          claim_view_token_hash: claim.claim_view_token_hash,
          otp_hash: claim.otp_hash,
          claim_token_expires_at: claim_token_expires_at,
          otp_expires_at: otp_expires_at,
          claim_attempt_id: claim.claim_attempt_id,
          registration_ip: Map.get(attrs, :registration_ip),
          claim_requested_ip: Map.get(attrs, :registration_ip)
        })

      with {:ok, registration} <- Repo.insert(changeset) do
        insert_event!(registration, :created, %{
          actor_ip: Map.get(attrs, :registration_ip),
          metadata: %{
            claim_attempt_id: claim.claim_attempt_id,
            credential_type: Atom.to_string(requested_credential_type),
            registration_type: "email_verification"
          },
          occurred_at: now
        })

        email_delivery =
          UserNotifier.deliver_agent_registration_claim_instructions(%{
            email: email,
            claim_view_url: claim_view_url.(claim.claim_view_token)
          })

        {:ok,
         %{
           registration: registration,
           claim_token: claim.claim_token,
           claim_token_expires_at: claim_token_expires_at,
           email_delivery: email_delivery
         }}
      end
    end
  end

  def create_registration(%{requested_credential_type: requested_credential_type})
      when requested_credential_type not in [:access_token, :api_key] do
    {:error, :unsupported_credential_type}
  end

  def create_registration(%{registration_type: :anonymous, requested_credential_type: :api_key} = attrs) do
    now = Time.utc_now()
    claim_token = prefixed_token("clm")
    claim_token_expires_at = DateTime.add(now, @claim_token_ttl_seconds, :second)

    with {:ok, anonymous_user} <- create_anonymous_user(),
         {:ok, {account_token, api_key}} <-
           Accounts.create_account_token(%{
             account: anonymous_user.account,
             created_by_account: anonymous_user.account,
             scopes: @scopes,
             name: token_name(),
             all_projects: true
           }),
         {:ok, registration} <-
           %{
             registration_type: :anonymous,
             status: :pending,
             requested_credential_type: :api_key,
             email: anonymous_user.email,
             claim_token_hash: hash_secret(claim_token),
             claim_token_expires_at: claim_token_expires_at,
             registration_ip: Map.get(attrs, :registration_ip),
             account_token_id: account_token.id
           }
           |> AgentRegistration.create_anonymous_changeset()
           |> Repo.insert() do
      insert_event!(registration, :created, %{
        actor_ip: Map.get(attrs, :registration_ip),
        metadata: %{
          credential_type: "api_key",
          registration_type: "anonymous"
        },
        occurred_at: now
      })

      {:ok,
       %{
         registration: registration,
         credential_type: :api_key,
         credential: api_key,
         credential_expires_at: nil,
         scopes: @scopes,
         claim_token: claim_token,
         claim_token_expires_at: claim_token_expires_at
       }}
    end
  end

  def create_registration(
        %{
          registration_type: :agent_provider,
          assertion: assertion,
          requested_credential_type: requested_credential_type,
          audience: audience
        } = attrs
      )
      when requested_credential_type in [:access_token, :api_key] do
    now = Time.utc_now()
    registration_ip = Map.get(attrs, :registration_ip)

    # JTI replay-protection is recorded inside verify_jwt and must outlive any
    # rollback of the credential/registration writes below — a transient
    # failure here must not allow the same assertion to be reused.
    with {:ok, claims} <- verify_jwt(assertion, audience, :id_jag),
         {:ok, email} <- verified_email_claim(claims),
         :ok <- ensure_sso_policy_satisfied(email) do
      fn ->
        with {:ok, user} <- get_or_provision_user_from_assertion(claims, email, audience),
             {:ok, credential} <- issue_credential(user, requested_credential_type),
             {:ok, registration} <-
               %{
                 registration_type: :agent_provider,
                 status: :claimed,
                 requested_credential_type: requested_credential_type,
                 email: email,
                 claim_token_hash: hash_secret(prefixed_token("clm")),
                 claim_token_expires_at: DateTime.add(now, @claim_token_ttl_seconds, :second),
                 claimed_at: now,
                 claimed_by_user_id: user.id,
                 account_token_id: credential[:account_token_id],
                 issuer: claims["iss"],
                 subject: claims["sub"],
                 audience: audience,
                 client_id: claims["client_id"],
                 assertion_jti: claims["jti"],
                 credential_jti: credential[:credential_jti]
               }
               |> AgentRegistration.create_agent_provider_changeset()
               |> Repo.insert() do
          insert_event!(registration, :created, %{
            actor_ip: registration_ip,
            claimed_by_user_id: user.id,
            metadata: provider_event_metadata(claims, requested_credential_type),
            occurred_at: now
          })

          insert_event!(registration, :claimed, %{
            actor_ip: registration_ip,
            claimed_by_user_id: user.id,
            metadata: provider_event_metadata(claims, requested_credential_type),
            occurred_at: now
          })

          %{
            registration: registration,
            credential_type: requested_credential_type,
            credential: credential.credential,
            credential_expires_at: credential.expires_at,
            scopes: @scopes
          }
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end
      |> Repo.transaction()
      |> unwrap_repo_transaction()
    end
  end

  def create_registration(_), do: {:error, :invalid_request}

  def revoke_registrations(logout_token, audience) do
    now = Time.utc_now()

    with {:ok, claims} <- verify_jwt(logout_token, audience, :logout),
         :ok <- validate_revocation_event(claims) do
      registrations = list_revocable_provider_registrations(claims, audience)

      Enum.each(registrations, fn registration ->
        revoke_credential(registration)

        {:ok, revoked_registration} =
          registration
          |> AgentRegistration.revoke_changeset(%{status: :revoked, revoked_at: now})
          |> Repo.update()

        insert_event!(revoked_registration, :revoked, %{
          metadata: %{
            issuer: claims["iss"],
            subject: claims["sub"],
            audience: audience,
            assertion_jti: claims["jti"]
          },
          occurred_at: now
        })
      end)

      {:ok, %{revoked_count: length(registrations)}}
    end
  end

  def credential_revoked?(%{"jti" => jti}) when is_binary(jti) do
    Repo.exists?(
      from(r in AgentRegistration,
        where: r.status == :revoked and r.credential_jti == ^jti
      )
    )
  end

  def credential_revoked?(_claims), do: false

  def resend_claim(%{claim_token: claim_token, claim_view_url: claim_view_url} = attrs)
      when is_function(claim_view_url, 1) do
    email = attrs |> Map.get(:email) |> normalize_email()

    fn ->
      with {:ok, registration} <- get_registration_by_claim_token(claim_token, lock: "FOR UPDATE"),
           :ok <- validate_optional_email(email),
           :ok <- ensure_email_matches(registration, email),
           :ok <- ensure_not_claimed(registration),
           :ok <- ensure_claim_token_valid(registration),
           :ok <- ensure_sso_policy_satisfied(email) do
        claim = build_claim_bundle()
        now = Time.utc_now()
        otp_expires_at = DateTime.add(now, @otp_ttl_seconds, :second)

        {:ok, registration} =
          registration
          |> AgentRegistration.refresh_claim_changeset(%{
            claim_view_token_hash: claim.claim_view_token_hash,
            otp_hash: claim.otp_hash,
            otp_expires_at: otp_expires_at,
            claim_attempt_id: claim.claim_attempt_id,
            otp_attempt_count: 0,
            claim_requested_ip: Map.get(attrs, :claim_requested_ip),
            email: email
          })
          |> Repo.update()

        insert_event!(registration, :claim_resent, %{
          actor_ip: Map.get(attrs, :claim_requested_ip),
          metadata: %{claim_attempt_id: claim.claim_attempt_id, email: email},
          occurred_at: now
        })

        email_delivery =
          UserNotifier.deliver_agent_registration_claim_instructions(%{
            email: email,
            claim_view_url: claim_view_url.(claim.claim_view_token)
          })

        %{
          registration: registration,
          otp_expires_at: otp_expires_at,
          email_delivery: email_delivery
        }
      end
    end
    |> Repo.transaction()
    |> unwrap_repo_transaction()
  end

  def complete_claim(%{claim_token: claim_token, otp: otp} = attrs) do
    fn ->
      with {:ok, registration} <- get_registration_by_claim_token(claim_token, lock: "FOR UPDATE"),
           :ok <- ensure_not_claimed(registration),
           :ok <- ensure_claim_token_valid(registration),
           :ok <- ensure_otp_valid(registration),
           :ok <- ensure_sso_policy_satisfied(registration.email),
           true <- secure_compare_hash(hash_secret(otp), registration.otp_hash) do
        user = get_or_provision_user!(registration.email)
        now = Time.utc_now()
        {:ok, credential} = claim_credential(registration, user)

        {:ok, registration} =
          registration
          |> AgentRegistration.claim_changeset(%{
            status: :claimed,
            claimed_at: now,
            claim_completed_ip: Map.get(attrs, :claim_completed_ip),
            claimed_by_user_id: user.id,
            account_token_id: credential[:account_token_id],
            credential_jti: credential[:credential_jti]
          })
          |> Repo.update()

        insert_event!(registration, :claimed, %{
          actor_ip: Map.get(attrs, :claim_completed_ip),
          claimed_by_user_id: user.id,
          metadata: %{claim_attempt_id: registration.claim_attempt_id},
          occurred_at: now
        })

        %{
          registration: registration,
          credential_type: registration.requested_credential_type,
          credential: credential.credential,
          credential_expires_at: credential.expires_at,
          scopes: @scopes
        }
      else
        false ->
          case get_registration_by_claim_token(claim_token, lock: "FOR UPDATE") do
            {:ok, registration} ->
              now = Time.utc_now()

              updated_registration =
                registration
                |> AgentRegistration.increment_otp_attempts_changeset()
                |> Repo.update!()

              insert_event!(updated_registration, :otp_failed, %{
                actor_ip: Map.get(attrs, :claim_completed_ip),
                metadata: %{
                  claim_attempt_id: updated_registration.claim_attempt_id,
                  otp_attempt_count: updated_registration.otp_attempt_count
                },
                occurred_at: now
              })

              if updated_registration.otp_attempt_count >= @max_otp_attempts do
                {:error, :rate_limited}
              else
                {:error, :otp_invalid}
              end

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
    |> Repo.transaction()
    |> unwrap_repo_transaction()
  end

  def get_claim_view(claim_view_token) when is_binary(claim_view_token) do
    with {:ok, registration} <- get_registration_by_claim_view_token(claim_view_token),
         :ok <- ensure_not_claimed(registration),
         :ok <- ensure_claim_token_valid(registration),
         :ok <- ensure_otp_window_valid(registration) do
      {:ok,
       %{
         registration: registration,
         otp: derive_otp(claim_view_token),
         otp_expires_at: registration.otp_expires_at
       }}
    end
  end

  defp validate_email(email) when is_binary(email) do
    if User.email_valid?(email) do
      :ok
    else
      {:error, :invalid_email}
    end
  end

  defp validate_email(_email), do: {:error, :invalid_email}

  defp validate_optional_email(nil), do: :ok
  defp validate_optional_email(email), do: validate_email(email)

  # Mailbox proof (email OTP) and trusted agent-provider assertions both bypass
  # Tuist's configured IdP. If the target email is governed by an SSO-enforced
  # organization, refuse to mint credentials here — the user must sign in
  # through the IdP instead. Defense in depth: this gate runs at every entry
  # point that can introduce a new bound email (create_registration for
  # email-verification and agent-provider, resend_claim, and complete_claim).
  defp ensure_sso_policy_satisfied(nil), do: :ok

  defp ensure_sso_policy_satisfied(email) when is_binary(email) do
    if Accounts.sso_enforced_for_email?(email) do
      {:error, :sso_required}
    else
      :ok
    end
  end

  defp normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_email(_), do: nil

  defp ensure_email_matches(_registration, nil), do: :ok
  defp ensure_email_matches(%AgentRegistration{registration_type: :anonymous}, _email), do: :ok

  defp ensure_email_matches(%AgentRegistration{email: registration_email}, email) do
    if registration_email == email do
      :ok
    else
      {:error, :invalid_claim_token}
    end
  end

  defp ensure_not_claimed(%AgentRegistration{status: :claimed}), do: {:error, :previously_claimed}
  defp ensure_not_claimed(_registration), do: :ok

  defp ensure_claim_token_valid(%AgentRegistration{} = registration) do
    if claim_token_expired?(registration) do
      maybe_expire_registration(registration)
      {:error, :claim_expired}
    else
      :ok
    end
  end

  defp ensure_otp_window_valid(%AgentRegistration{} = registration) do
    if otp_expired?(registration) do
      {:error, :otp_expired}
    else
      :ok
    end
  end

  defp ensure_otp_valid(%AgentRegistration{} = registration) do
    cond do
      registration.otp_attempt_count >= @max_otp_attempts ->
        {:error, :rate_limited}

      otp_expired?(registration) ->
        {:error, :otp_expired}

      true ->
        :ok
    end
  end

  defp verify_jwt(token, audience, token_type) do
    with {:ok, header} <- peek_jwt_header(token),
         :ok <- validate_jwt_type(header, token_type),
         {:ok, issuer} <- peek_jwt_issuer(token),
         {:ok, provider} <- trusted_provider(issuer),
         {:ok, jwks} <- fetch_jwks(provider),
         {:ok, claims} <- verify_jwt_signature(token, jwks, header),
         :ok <- validate_claims(claims, audience, provider, token_type),
         :ok <- record_jti(claims) do
      {:ok, claims}
    end
  end

  defp peek_jwt_header(token) do
    with [header_b64 | _] <- String.split(token, "."),
         {:ok, header_json} <- Base.url_decode64(header_b64, padding: false),
         {:ok, header} <- JSON.decode(header_json) do
      {:ok, header}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp peek_jwt_issuer(token) do
    case JOSE.JWT.peek_payload(token) do
      %JOSE.JWT{fields: %{"iss" => issuer}} when is_binary(issuer) -> {:ok, issuer}
      _ -> {:error, :invalid_issuer}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  defp validate_jwt_type(%{"typ" => "oauth-id-jag+jwt"}, :id_jag), do: :ok
  defp validate_jwt_type(%{"typ" => "logout+jwt"}, :logout), do: :ok
  defp validate_jwt_type(_header, _token_type), do: {:error, :invalid_signature}

  defp trusted_provider(issuer) do
    provider =
      Enum.find(Environment.agent_auth_trusted_providers(), fn provider ->
        provider_value(provider, "issuer") == issuer
      end)

    case provider do
      nil -> {:error, :invalid_issuer}
      provider -> {:ok, provider}
    end
  end

  defp fetch_jwks(provider) do
    cond do
      is_map(provider_value(provider, "jwks")) ->
        {:ok, provider_value(provider, "jwks")}

      is_binary(provider_value(provider, "jwks_uri")) ->
        jwks_uri = provider_value(provider, "jwks_uri")

        KeyValueStore.get_or_update(["agent_auth", "jwks", jwks_uri], [ttl: to_timeout(minute: 15)], fn ->
          case Req.get(jwks_uri, connect_options: [timeout: 10_000]) do
            {:ok, %{status: 200, body: body}} ->
              {:ok, body}

            other ->
              Logger.warning("agent_auth JWKS fetch failed for #{jwks_uri}: #{inspect(other)}")
              {:error, :invalid_signature}
          end
        end)

      is_binary(provider_value(provider, "issuer")) ->
        issuer = provider_value(provider, "issuer")
        fetch_jwks(Map.put(provider, "jwks_uri", "#{issuer}/.well-known/jwks.json"))

      true ->
        {:error, :invalid_signature}
    end
  end

  defp verify_jwt_signature(token, %{"keys" => keys}, header) do
    algorithms = header |> Map.get("alg") |> List.wrap()

    with {:ok, key} <- find_jwk(keys, Map.get(header, "kid")),
         {true, %JOSE.JWT{fields: claims}, _jws} <- JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), algorithms, token) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp verify_jwt_signature(_token, _jwks, _header), do: {:error, :invalid_signature}

  defp find_jwk(keys, nil), do: {:ok, List.first(keys)}

  defp find_jwk(keys, kid) do
    case Enum.find(keys, &(&1["kid"] == kid)) do
      nil -> {:error, :invalid_signature}
      key -> {:ok, key}
    end
  end

  defp validate_claims(claims, audience, provider, token_type) do
    with :ok <- validate_audience(claims, audience),
         :ok <- validate_expiration(claims),
         :ok <- validate_issued_at(claims),
         :ok <- validate_required_claims(claims),
         :ok <- validate_client_id(claims, provider) do
      validate_identity_claims(claims, token_type)
    end
  end

  defp validate_audience(%{"aud" => audience}, audience), do: :ok

  defp validate_audience(%{"aud" => audiences}, audience) when is_list(audiences) do
    if audience in audiences, do: :ok, else: {:error, :invalid_audience}
  end

  defp validate_audience(_claims, _audience), do: {:error, :invalid_audience}

  defp validate_expiration(%{"exp" => exp}) when is_integer(exp) do
    if exp > DateTime.to_unix(Time.utc_now()), do: :ok, else: {:error, :expired}
  end

  defp validate_expiration(_claims), do: {:error, :expired}

  defp validate_issued_at(%{"iat" => iat}) when is_integer(iat) do
    now = DateTime.to_unix(Time.utc_now())

    cond do
      iat > now + 120 -> {:error, :insufficient_user_authentication}
      iat < now - 600 -> {:error, :insufficient_user_authentication}
      true -> :ok
    end
  end

  defp validate_issued_at(_claims), do: {:error, :insufficient_user_authentication}

  defp validate_required_claims(%{"iss" => iss, "sub" => sub, "jti" => jti, "client_id" => client_id})
       when is_binary(iss) and is_binary(sub) and is_binary(jti) and is_binary(client_id) do
    :ok
  end

  defp validate_required_claims(_claims), do: {:error, :invalid_signature}

  defp validate_client_id(%{"client_id" => client_id}, provider) do
    case provider_value(provider, "client_ids") do
      client_ids when is_list(client_ids) and client_ids != [] ->
        if client_id in client_ids, do: :ok, else: {:error, :invalid_client_id}

      _ ->
        :ok
    end
  end

  defp validate_identity_claims(_claims, :logout), do: :ok

  defp validate_identity_claims(%{"email" => email, "email_verified" => true}, :id_jag) when is_binary(email) do
    :ok
  end

  defp validate_identity_claims(_claims, :id_jag), do: {:error, :missing_verified_email}

  defp record_jti(%{"iss" => issuer, "jti" => jti, "exp" => exp}) do
    expires_at = DateTime.from_unix!(exp)

    case %{issuer: issuer, jti: jti, expires_at: expires_at}
         |> AgentAuthJTI.create_changeset()
         |> Repo.insert() do
      {:ok, _jti} -> :ok
      {:error, _changeset} -> {:error, :replay_detected}
    end
  end

  defp verified_email_claim(%{"email" => email, "email_verified" => true}) when is_binary(email) do
    {:ok, normalize_email(email)}
  end

  defp verified_email_claim(_claims), do: {:error, :missing_verified_email}

  defp get_or_provision_user_from_assertion(claims, email, audience) do
    case get_user_by_delegation(claims, audience) do
      %User{} = user -> {:ok, Repo.preload(user, :account)}
      nil -> {:ok, get_or_provision_user!(email)}
    end
  end

  defp get_user_by_delegation(%{"iss" => issuer, "sub" => subject}, audience) do
    from(r in AgentRegistration,
      where:
        r.registration_type == :agent_provider and r.status == :claimed and r.issuer == ^issuer and
          r.subject == ^subject and r.audience == ^audience,
      order_by: [desc: r.claimed_at],
      preload: [claimed_by_user: :account],
      limit: 1
    )
    |> Repo.one()
    |> case do
      %AgentRegistration{claimed_by_user: user} -> user
      nil -> nil
    end
  end

  defp validate_revocation_event(%{"events" => events}) when is_map(events) do
    if Map.has_key?(events, "https://schemas.workos.com/events/agent/auth/identity/assertion/revoked") do
      :ok
    else
      {:error, :invalid_request}
    end
  end

  defp validate_revocation_event(_claims), do: {:error, :invalid_request}

  defp list_revocable_provider_registrations(%{"iss" => issuer, "sub" => subject}, audience) do
    Repo.all(
      from(r in AgentRegistration,
        where:
          r.registration_type == :agent_provider and r.status == :claimed and r.issuer == ^issuer and
            r.subject == ^subject and r.audience == ^audience
      )
    )
  end

  defp revoke_credential(%AgentRegistration{account_token_id: account_token_id}) when not is_nil(account_token_id) do
    Repo.delete_all(from(t in AccountToken, where: t.id == ^account_token_id))
  end

  defp revoke_credential(%AgentRegistration{credential_jti: credential_jti}) when not is_nil(credential_jti) do
    Repo.delete_all(from(t in "guardian_tokens", where: field(t, :jti) == ^credential_jti))
  end

  defp revoke_credential(_registration), do: :ok

  defp provider_event_metadata(claims, requested_credential_type) do
    %{
      issuer: claims["iss"],
      subject: claims["sub"],
      client_id: claims["client_id"],
      assertion_jti: claims["jti"],
      credential_type: Atom.to_string(requested_credential_type),
      registration_type: "agent_provider"
    }
  end

  defp provider_value(provider, key) when is_map(provider) and is_binary(key) do
    case Map.fetch(provider, key) do
      {:ok, value} -> value
      :error -> Map.get(provider, safe_existing_atom(key))
    end
  end

  defp safe_existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp get_registration_by_claim_token(claim_token, opts) do
    claim_token_hash = hash_secret(claim_token)
    preload = Keyword.get(opts, :preload, [])

    query =
      maybe_lock_query(
        from(r in AgentRegistration, where: r.claim_token_hash == ^claim_token_hash, preload: ^preload),
        opts
      )

    case Repo.one(query) do
      nil -> {:error, :invalid_claim_token}
      registration -> {:ok, registration}
    end
  end

  defp get_registration_by_claim_view_token(claim_view_token, opts \\ []) do
    claim_view_token_hash = hash_secret(claim_view_token)

    query = maybe_lock_query(from(r in AgentRegistration, where: r.claim_view_token_hash == ^claim_view_token_hash), opts)

    case Repo.one(query) do
      nil -> {:error, :invalid_claim_token}
      registration -> {:ok, registration}
    end
  end

  defp maybe_lock_query(query, lock: "FOR UPDATE"), do: from(r in query, lock: "FOR UPDATE")
  defp maybe_lock_query(query, _opts), do: query

  defp maybe_expire_registration(%AgentRegistration{status: :pending} = registration) do
    case registration
         |> AgentRegistration.expire_changeset()
         |> Repo.update() do
      {:ok, expired_registration} ->
        insert_event!(expired_registration, :expired, %{
          metadata: %{claim_attempt_id: expired_registration.claim_attempt_id},
          occurred_at: Time.utc_now()
        })

        {:ok, expired_registration}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp maybe_expire_registration(_registration), do: {:ok, nil}

  defp claim_token_expired?(%AgentRegistration{claim_token_expires_at: claim_token_expires_at}) do
    DateTime.compare(claim_token_expires_at, Time.utc_now()) != :gt
  end

  defp otp_expired?(%AgentRegistration{otp_expires_at: otp_expires_at}) do
    DateTime.compare(otp_expires_at, Time.utc_now()) != :gt
  end

  defp build_claim_bundle do
    claim_token = prefixed_token("clm")
    claim_view_token = prefixed_token("clv")
    otp = derive_otp(claim_view_token)

    %{
      claim_token: claim_token,
      claim_token_hash: hash_secret(claim_token),
      claim_view_token: claim_view_token,
      claim_view_token_hash: hash_secret(claim_view_token),
      otp_hash: hash_secret(otp),
      claim_attempt_id: UUIDv7.generate()
    }
  end

  defp prefixed_token(prefix) do
    "#{prefix}_#{Tuist.Tokens.generate_token(24)}"
  end

  defp derive_otp(claim_view_token) do
    <<value::unsigned-integer-size(32), _::binary>> =
      :crypto.mac(:hmac, :sha256, Environment.secret_key_password(), claim_view_token)

    value
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  defp hash_secret(secret) when is_binary(secret) do
    :crypto.hash(:sha256, secret)
  end

  defp claim_credential(%AgentRegistration{registration_type: :anonymous} = registration, user) do
    account_token = Repo.get!(AccountToken, registration.account_token_id)

    {:ok, account_token} =
      account_token
      |> Changeset.change(account_id: user.account.id, created_by_account_id: user.account.id)
      |> Repo.update()

    {:ok,
     %{
       credential: nil,
       expires_at: account_token.expires_at,
       account_token_id: account_token.id,
       credential_jti: nil
     }}
  end

  defp claim_credential(%AgentRegistration{} = registration, user) do
    issue_credential(user, registration.requested_credential_type)
  end

  defp issue_credential(user, :access_token) do
    access_token_expires_at = DateTime.add(Time.utc_now(), @access_token_ttl_seconds, :second)

    {:ok, access_token, claims} =
      Tuist.Guardian.encode_and_sign(
        user.account,
        %{
          "type" => "account",
          "scopes" => @scopes,
          "all_projects" => true,
          "user_id" => user.id,
          "preferred_username" => user.account.name,
          "email" => user.email
        },
        token_type: "access_token",
        ttl: {@access_token_ttl_seconds, :second}
      )

    {:ok,
     %{
       credential: access_token,
       expires_at: access_token_expires_at,
       account_token_id: nil,
       credential_jti: claims["jti"]
     }}
  end

  defp issue_credential(user, :api_key) do
    {:ok, {account_token, api_key}} =
      Accounts.create_account_token(%{
        account: user.account,
        created_by_account: user.account,
        scopes: @scopes,
        name: token_name(),
        all_projects: true
      })

    {:ok,
     %{
       credential: api_key,
       expires_at: account_token.expires_at,
       account_token_id: account_token.id,
       credential_jti: nil
     }}
  end

  defp create_anonymous_user do
    id = UUIDv7.generate()

    Accounts.create_user(
      "agent-#{id}@agents.tuist.local",
      confirmed_at: NaiveDateTime.utc_now(),
      handle: "agent-#{String.slice(id, 0, 12)}"
    )
  end

  defp token_name do
    "agent-auth-#{String.slice(UUIDv7.generate(), 0, 12)}"
  end

  defp secure_compare_hash(left, right) when is_binary(left) and is_binary(right) do
    Plug.Crypto.secure_compare(left, right)
  end

  defp get_or_provision_user!(email) do
    case Accounts.get_user_by_email(email) do
      {:ok, %User{} = user} ->
        maybe_confirm_user!(user)

      {:error, :not_found} ->
        case Accounts.create_user(email, confirmed_at: NaiveDateTime.utc_now()) do
          {:ok, user} ->
            user

          {:error, :email_taken} ->
            {:ok, user} = Accounts.get_user_by_email(email)
            maybe_confirm_user!(user)
        end
    end
  end

  defp maybe_confirm_user!(%User{confirmed_at: nil} = user) do
    {:ok, user} =
      user
      |> User.confirm_changeset()
      |> Repo.update()

    Repo.preload(user, :account)
  end

  defp maybe_confirm_user!(%User{} = user) do
    Repo.preload(user, :account)
  end

  defp insert_event!(%AgentRegistration{} = registration, event_type, attrs) do
    attrs
    |> Map.merge(%{
      agent_registration_id: registration.id,
      event_type: event_type,
      occurred_at: Map.get(attrs, :occurred_at, Time.utc_now())
    })
    |> AgentRegistrationEvent.create_changeset()
    |> Repo.insert!()
  end

  defp unwrap_repo_transaction({:ok, {:error, reason}}), do: {:error, reason}
  defp unwrap_repo_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_repo_transaction({:error, reason}), do: {:error, reason}
end
