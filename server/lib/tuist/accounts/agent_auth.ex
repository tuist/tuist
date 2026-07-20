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
  alias Tuist.Accounts.AgentAuthCredential
  alias Tuist.Accounts.AgentAuthJTI
  alias Tuist.Accounts.AgentAuthSigningKey
  alias Tuist.Accounts.AgentRegistration
  alias Tuist.Accounts.AgentRegistrationEvent
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Accounts.Workers.ExpireAgentRegistrationWorker
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Repo
  alias Tuist.Time

  require Logger

  @scopes ["mcp"]
  @claim_token_ttl_seconds 30 * 60
  @otp_ttl_seconds 10 * 60
  @access_token_ttl_seconds 24 * 60 * 60
  @protocol_access_token_ttl_seconds 60 * 60
  @protocol_poll_interval_seconds 5
  @id_jag_max_auth_age_seconds 60 * 60
  @clock_skew_seconds 120
  @max_otp_attempts 5
  @assertion_revoked_event "https://schemas.workos.com/events/agent/auth/identity/assertion/revoked"

  def scopes, do: @scopes
  def protocol_poll_interval_seconds, do: @protocol_poll_interval_seconds
  def id_jag_max_auth_age_seconds, do: @id_jag_max_auth_age_seconds

  def service_jwks, do: AgentAuthSigningKey.jwks()

  def create_protocol_registration(%{registration_type: :anonymous, audience: audience} = attrs) do
    now = Time.utc_now()
    claim_token = prefixed_token("clm")
    claim_token_expires_at = DateTime.add(now, @claim_token_ttl_seconds, :second)

    with {:ok, anonymous_user} <- create_anonymous_user(),
         {:ok, {account_token, _discarded_api_key}} <-
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
             requested_credential_type: :access_token,
             email: anonymous_user.email,
             claim_token_hash: hash_secret(claim_token),
             claim_token_expires_at: claim_token_expires_at,
             registration_ip: Map.get(attrs, :registration_ip),
             account_token_id: account_token.id
           }
           |> AgentRegistration.create_anonymous_changeset()
           |> Repo.insert(),
         {:ok, _job} <- schedule_protocol_expiration(registration, claim_token_expires_at),
         {:ok, signed} <- AgentAuthSigningKey.sign(registration, audience, version: 1) do
      insert_event!(registration, :created, %{
        actor_ip: Map.get(attrs, :registration_ip),
        metadata: %{registration_type: "anonymous"},
        occurred_at: now
      })

      insert_event!(registration, :assertion_issued, %{
        actor_ip: Map.get(attrs, :registration_ip),
        metadata: %{version: 1},
        occurred_at: now
      })

      {:ok,
       %{
         registration: registration,
         identity_assertion: signed.assertion,
         assertion_expires_at: signed.expires_at,
         claim_token: claim_token,
         claim_token_expires_at: claim_token_expires_at,
         pre_claim_scopes: @scopes,
         post_claim_scopes: @scopes
       }}
    end
  end

  def create_protocol_registration(%{registration_type: :service_auth, login_hint: login_hint} = attrs) do
    email = normalize_email(login_hint)

    with :ok <- validate_email(email) do
      now = Time.utc_now()
      claim = build_claim_bundle()
      claim_token_expires_at = DateTime.add(now, @claim_token_ttl_seconds, :second)
      otp_expires_at = DateTime.add(now, @otp_ttl_seconds, :second)

      with {:ok, registration} <-
             %{
               registration_type: :email_verification,
               status: :pending,
               requested_credential_type: :access_token,
               email: email,
               claim_token_hash: claim.claim_token_hash,
               claim_view_token_hash: claim.claim_view_token_hash,
               otp_hash: claim.otp_hash,
               claim_token_expires_at: claim_token_expires_at,
               otp_expires_at: otp_expires_at,
               claim_attempt_id: claim.claim_attempt_id,
               registration_ip: Map.get(attrs, :registration_ip),
               claim_requested_ip: Map.get(attrs, :registration_ip)
             }
             |> AgentRegistration.create_email_verification_changeset()
             |> Repo.insert(),
           {:ok, _job} <- schedule_protocol_expiration(registration, claim_token_expires_at) do
        insert_event!(registration, :created, %{
          actor_ip: Map.get(attrs, :registration_ip),
          metadata: %{registration_type: "service_auth"},
          occurred_at: now
        })

        insert_event!(registration, :claim_resent, %{
          actor_ip: Map.get(attrs, :registration_ip),
          metadata: %{claim_attempt_id: claim.claim_attempt_id, email: email},
          occurred_at: now
        })

        insert_protocol_claim_events!(registration, claim, email, Map.get(attrs, :registration_ip), now)

        {:ok,
         %{
           registration: registration,
           claim_token: claim.claim_token,
           claim_token_expires_at: claim_token_expires_at,
           claim_view_token: claim.claim_view_token,
           user_code: claim.user_code,
           user_code_expires_at: otp_expires_at,
           post_claim_scopes: @scopes
         }}
      end
    end
  end

  def create_protocol_registration(
        %{registration_type: :agent_provider, assertion: assertion, audience: audience} = attrs
      ) do
    registration_ip = Map.get(attrs, :registration_ip)

    with {:ok, claims} <- verify_jwt(assertion, audience, :id_jag, require_fresh_auth: true),
         {:ok, email} <- verified_email_claim(claims) do
      case get_user_by_delegation(claims, audience) do
        %User{} = user ->
          registration = get_delegation_registration!(claims, audience)
          issue_protocol_assertion(registration, audience, user, registration_ip)

        nil ->
          case Accounts.get_user_by_email(email) do
            {:ok, _user} -> create_protocol_step_up(claims, email, audience, registration_ip)
            {:error, :not_found} -> create_protocol_provider_registration(claims, email, audience, registration_ip)
          end
      end
    end
  end

  def create_protocol_registration(_attrs), do: {:error, :invalid_request}

  def expire_protocol_registration(registration_id) when is_binary(registration_id) do
    fn ->
      case Repo.one(from(r in AgentRegistration, where: r.id == ^registration_id, lock: "FOR UPDATE")) do
        %AgentRegistration{status: :pending} = registration ->
          if claim_token_expired?(registration), do: maybe_expire_registration(registration), else: :ok

        _ ->
          :ok
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, {:error, reason}} -> {:error, reason}
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def expire_protocol_registration(_registration_id), do: :ok

  def initiate_protocol_claim(%{claim_token: claim_token, email: email} = attrs) do
    email = normalize_email(email)

    fn ->
      with :ok <- validate_email(email),
           {:ok, registration} <- get_registration_by_claim_token(claim_token, lock: "FOR UPDATE"),
           :ok <- ensure_protocol_claim_startable(registration),
           :ok <- ensure_email_matches(registration, email),
           :ok <- ensure_not_claimed(registration),
           :ok <- ensure_claim_token_valid(registration) do
        claim = build_claim_bundle()
        now = DateTime.truncate(Time.utc_now(), :second)

        otp_expires_at =
          now
          |> DateTime.add(@otp_ttl_seconds, :second)
          |> earliest_datetime(registration.claim_token_expires_at)

        {:ok, registration} =
          registration
          |> AgentRegistration.refresh_claim_changeset(%{
            claim_view_token_hash: claim.claim_view_token_hash,
            otp_hash: claim.otp_hash,
            otp_expires_at: otp_expires_at,
            claim_attempt_id: claim.claim_attempt_id,
            otp_attempt_count: 0,
            claim_requested_ip: Map.get(attrs, :claim_requested_ip),
            email: email,
            last_polled_at: nil
          })
          |> Repo.update()

        insert_event!(registration, :claim_resent, %{
          actor_ip: Map.get(attrs, :claim_requested_ip),
          metadata: %{claim_attempt_id: claim.claim_attempt_id, email: email},
          occurred_at: now
        })

        insert_protocol_claim_events!(registration, claim, email, Map.get(attrs, :claim_requested_ip), now)

        %{
          registration: registration,
          claim_view_token: claim.claim_view_token,
          user_code: claim.user_code,
          user_code_expires_at: otp_expires_at
        }
      end
    end
    |> Repo.transaction()
    |> unwrap_repo_transaction()
  end

  def get_protocol_claim_view(claim_view_token, %User{} = user) do
    with {:ok, registration} <- get_registration_by_claim_view_token(claim_view_token),
         :ok <- ensure_not_claimed(registration),
         :ok <- ensure_claim_token_valid(registration),
         :ok <- ensure_otp_window_valid(registration),
         :ok <- ensure_claim_user_matches(registration, user) do
      {:ok, %{registration: registration, provider_name: provider_display_name(registration)}}
    end
  end

  def confirm_protocol_claim(%{claim_view_token: claim_view_token, user_code: user_code, user: %User{} = user} = attrs) do
    fn ->
      with {:ok, registration} <- get_registration_by_claim_view_token(claim_view_token, lock: "FOR UPDATE"),
           :ok <- ensure_not_claimed(registration),
           :ok <- ensure_claim_token_valid(registration),
           :ok <- ensure_otp_valid(registration),
           :ok <- ensure_claim_user_matches(registration, user),
           :ok <- ensure_browser_sso_policy_satisfied(user, Map.get(attrs, :auth_method)),
           true <- secure_compare_hash(hash_secret(user_code), registration.otp_hash) do
        now = Time.utc_now()
        user = Repo.preload(user, :account)
        :ok = bind_protocol_registration(registration, user)

        {:ok, registration} =
          registration
          |> AgentRegistration.claim_changeset(%{
            status: :claimed,
            claimed_at: now,
            claim_completed_ip: Map.get(attrs, :claim_completed_ip),
            claimed_by_user_id: user.id,
            account_token_id: registration.account_token_id
          })
          |> Repo.update()

        if registration.registration_type == :anonymous do
          revoke_registration_credentials(registration.id, now)
        end

        insert_event!(registration, :claimed, %{
          actor_ip: Map.get(attrs, :claim_completed_ip),
          claimed_by_user_id: user.id,
          metadata: %{claim_attempt_id: registration.claim_attempt_id},
          occurred_at: now
        })

        insert_event!(registration, :claim_confirmed, %{
          actor_ip: Map.get(attrs, :claim_completed_ip),
          claimed_by_user_id: user.id,
          metadata: %{claim_attempt_id: registration.claim_attempt_id},
          occurred_at: now
        })

        %{registration: registration}
      else
        false -> record_failed_user_code_attempt(claim_view_token, attrs)
        {:error, reason} -> {:error, reason}
      end
    end
    |> Repo.transaction()
    |> unwrap_repo_transaction()
  end

  def exchange_protocol_assertion(assertion, audience, resource \\ nil) do
    with :ok <- validate_protocol_resource(resource, audience),
         {:ok, claims} <- AgentAuthSigningKey.verify(assertion, audience),
         {:ok, registration} <- get_registration_from_service_assertion(claims),
         :ok <- ensure_protocol_assertion_current(registration, claims) do
      issue_protocol_access_token(registration)
    end
  end

  def poll_protocol_claim(claim_token, audience) do
    fn ->
      with {:ok, registration} <- get_registration_by_claim_token(claim_token, lock: "FOR UPDATE"),
           :ok <- ensure_claim_pollable(registration),
           :ok <- enforce_poll_interval(registration) do
        now = DateTime.truncate(Time.utc_now(), :second)
        {:ok, registration} = registration |> AgentRegistration.poll_changeset(now) |> Repo.update()

        resolve_polled_claim(registration, audience, now)
      end
    end
    |> Repo.transaction()
    |> unwrap_repo_transaction()
  end

  defp resolve_polled_claim(%{status: :claimed} = registration, audience, now) do
    registration = Repo.preload(registration, claimed_by_user: :account)

    with {:ok, token} <- issue_protocol_access_token(registration),
         {:ok, signed} <-
           AgentAuthSigningKey.sign(registration, audience,
             version: 2,
             email: registration.claimed_by_user.email,
             email_verified: true
           ) do
      insert_event!(registration, :assertion_issued, %{
        claimed_by_user_id: registration.claimed_by_user_id,
        metadata: %{version: 2},
        occurred_at: now
      })

      Map.merge(token, %{
        identity_assertion: signed.assertion,
        assertion_expires_at: signed.expires_at
      })
    end
  end

  defp resolve_polled_claim(registration, _audience, _now) do
    if otp_expired?(registration) do
      {:error, :expired_token}
    else
      {:error, :authorization_pending}
    end
  end

  def revoke_protocol_access_token(token) when is_binary(token) do
    with {:ok, %{"jti" => jti}} <- Tuist.Guardian.decode_and_verify(token),
         %AgentAuthCredential{} = credential <-
           AgentAuthCredential |> Repo.get_by(jti: jti) |> Repo.preload(:agent_registration),
         nil <- credential.revoked_at do
      now = DateTime.truncate(Time.utc_now(), :second)
      {:ok, credential} = credential |> AgentAuthCredential.revoke_changeset(now) |> Repo.update()

      insert_event!(credential.agent_registration, :token_revoked, %{
        metadata: %{credential_jti: jti},
        occurred_at: now
      })
    else
      _ -> :ok
    end

    :ok
  rescue
    _ -> :ok
  end

  def revoke_protocol_access_token(_token), do: :ok

  def receive_protocol_event(token, audience) do
    with {:ok, claims} <- verify_jwt(token, audience, :security_event, defer_jti: true),
         {:ok, event_types} <- validate_security_events(claims) do
      process_security_event(claims, event_types, audience)
    end
  end

  # The replay marker and the revocation writes have to land together. If the
  # marker committed on its own and the revocation then failed, the provider's
  # retry would be rejected as replay_detected while the credentials stayed
  # active, silently dropping the revocation.
  defp process_security_event(claims, event_types, audience) do
    fn ->
      with :ok <- record_jti(claims) do
        if @assertion_revoked_event in event_types do
          revoke_provider_delegation(claims, audience)
        end

        :ok
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def claimed_user_for_account_token(account_token_id) when is_binary(account_token_id) do
    from(r in AgentRegistration,
      where:
        r.account_token_id == ^account_token_id and r.status == :claimed and
          not is_nil(r.claimed_by_user_id),
      order_by: [desc: r.claimed_at],
      preload: [claimed_by_user: :account],
      limit: 1
    )
    |> Repo.one()
    |> case do
      %AgentRegistration{claimed_by_user: %User{} = user} -> user
      _ -> nil
    end
  end

  def claimed_user_for_account_token(_account_token_id), do: nil

  def claimed_user_for_registration(registration_id) when is_binary(registration_id) do
    from(r in AgentRegistration,
      where: r.id == ^registration_id and r.status == :claimed and not is_nil(r.claimed_by_user_id),
      preload: [claimed_by_user: :account]
    )
    |> Repo.one()
    |> case do
      %AgentRegistration{claimed_by_user: %User{} = user} -> user
      _ -> nil
    end
  end

  def claimed_user_for_registration(_registration_id), do: nil

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

  def credential_revoked?(%{"jti" => jti} = claims) when is_binary(jti) do
    if Map.has_key?(claims, "agent_registration_id") do
      protocol_credential_revoked?(jti)
    else
      legacy_credential_revoked?(jti)
    end
  end

  def credential_revoked?(_claims), do: false

  defp protocol_credential_revoked?(jti) do
    case Repo.get_by(AgentAuthCredential, jti: jti) do
      %AgentAuthCredential{revoked_at: revoked_at, agent_registration_id: registration_id} ->
        not is_nil(revoked_at) or
          Repo.exists?(
            from(r in AgentRegistration,
              where: r.id == ^registration_id and r.status in [:expired, :revoked]
            )
          )

      nil ->
        legacy_credential_revoked?(jti)
    end
  end

  defp legacy_credential_revoked?(jti) do
    Repo.exists?(
      from(r in AgentRegistration,
        where: r.status == :revoked and r.credential_jti == ^jti
      )
    )
  end

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
            email: email,
            last_polled_at: nil
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
          record_failed_otp_attempt(claim_token, attrs)

        {:error, reason} ->
          {:error, reason}
      end
    end
    |> Repo.transaction()
    |> unwrap_repo_transaction()
  end

  defp record_failed_otp_attempt(claim_token, attrs) do
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

  defp verify_jwt(token, audience, token_type, opts \\ []) do
    with {:ok, header} <- peek_jwt_header(token),
         :ok <- validate_jwt_type(header, token_type),
         {:ok, issuer} <- peek_jwt_issuer(token),
         {:ok, provider} <- trusted_provider(issuer),
         {:ok, claims} <- verify_jwt_with_provider_keys(token, provider, header),
         :ok <- validate_claims(claims, audience, provider, token_type, opts),
         :ok <- maybe_record_jti(claims, opts) do
      {:ok, claims}
    end
  end

  # Callers that need the replay marker committed together with their own writes
  # defer it and call record_jti/1 themselves inside their transaction.
  defp maybe_record_jti(claims, opts) do
    if Keyword.get(opts, :defer_jti, false), do: :ok, else: record_jti(claims)
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
  defp validate_jwt_type(%{"typ" => "secevent+jwt"}, :security_event), do: :ok
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
        fetch_jwks(Map.put(provider, "jwks_uri", provider_jwks_uri(provider)))

      true ->
        {:error, :invalid_signature}
    end
  end

  defp verify_jwt_with_provider_keys(token, provider, header) do
    with {:ok, jwks} <- fetch_jwks(provider) do
      case verify_jwt_signature(token, jwks, header) do
        {:error, :invalid_key} ->
          with {:ok, refreshed_jwks} <- refresh_jwks(provider) do
            verify_jwt_signature(token, refreshed_jwks, header)
          end

        result ->
          result
      end
    end
  end

  defp refresh_jwks(provider) do
    if is_map(provider_value(provider, "jwks")) do
      {:error, :invalid_key}
    else
      with jwks_uri when is_binary(jwks_uri) <- provider_jwks_uri(provider),
           {:ok, %{status: 200, body: body}} <- Req.get(jwks_uri, connect_options: [timeout: 10_000]) do
        KeyValueStore.put(["agent_auth", "jwks", jwks_uri], {:ok, body}, ttl: to_timeout(minute: 15))
        {:ok, body}
      else
        _ -> {:error, :invalid_key}
      end
    end
  end

  defp provider_jwks_uri(provider) do
    provider_value(provider, "jwks_uri") ||
      case provider_value(provider, "issuer") do
        issuer when is_binary(issuer) -> "#{String.trim_trailing(issuer, "/")}/.well-known/jwks.json"
        _ -> nil
      end
  end

  defp verify_jwt_signature(token, %{"keys" => keys}, header) do
    algorithms = header |> Map.get("alg") |> List.wrap()

    with {:ok, key} <- find_jwk(keys, Map.get(header, "kid")),
         {true, %JOSE.JWT{fields: claims}, _jws} <- JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), algorithms, token) do
      {:ok, claims}
    else
      {:error, :invalid_key} -> {:error, :invalid_key}
      _ -> {:error, :invalid_signature}
    end
  end

  defp verify_jwt_signature(_token, _jwks, _header), do: {:error, :invalid_signature}

  defp find_jwk(_keys, nil), do: {:error, :invalid_key}

  defp find_jwk(keys, kid) do
    case Enum.find(keys, &(&1["kid"] == kid)) do
      nil -> {:error, :invalid_key}
      key -> {:ok, key}
    end
  end

  defp validate_claims(claims, audience, provider, token_type, opts) do
    with :ok <- validate_audience(claims, audience),
         :ok <- validate_expiration_for_token(claims, token_type),
         :ok <- validate_issued_at(claims),
         :ok <- validate_required_claims(claims, token_type),
         :ok <- validate_client_id_for_token(claims, provider, token_type),
         :ok <- validate_identity_claims(claims, token_type) do
      validate_auth_freshness(claims, opts)
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

  defp validate_expiration_for_token(%{"exp" => _exp} = claims, :security_event), do: validate_expiration(claims)
  defp validate_expiration_for_token(_claims, :security_event), do: :ok
  defp validate_expiration_for_token(claims, _token_type), do: validate_expiration(claims)

  defp validate_issued_at(%{"iat" => iat}) when is_integer(iat) do
    now = DateTime.to_unix(Time.utc_now())

    cond do
      iat > now + 120 -> {:error, :insufficient_user_authentication}
      iat < now - 600 -> {:error, :insufficient_user_authentication}
      true -> :ok
    end
  end

  defp validate_issued_at(_claims), do: {:error, :insufficient_user_authentication}

  defp validate_required_claims(%{"iss" => iss, "sub" => sub, "jti" => jti, "client_id" => client_id}, :id_jag)
       when is_binary(iss) and is_binary(sub) and is_binary(jti) and is_binary(client_id) do
    :ok
  end

  defp validate_required_claims(%{"iss" => iss, "sub" => sub, "jti" => jti}, token_type)
       when token_type in [:logout, :security_event] and is_binary(iss) and is_binary(sub) and is_binary(jti), do: :ok

  defp validate_required_claims(_claims, _token_type), do: {:error, :invalid_signature}

  defp validate_client_id_for_token(claims, provider, :id_jag), do: validate_client_id(claims, provider)
  defp validate_client_id_for_token(_claims, _provider, _token_type), do: :ok

  defp validate_client_id(%{"client_id" => client_id}, provider) do
    case provider_value(provider, "client_ids") do
      client_ids when is_list(client_ids) and client_ids != [] ->
        if client_id in client_ids, do: :ok, else: {:error, :invalid_client_id}

      _ ->
        :ok
    end
  end

  defp validate_identity_claims(_claims, :logout), do: :ok
  defp validate_identity_claims(_claims, :security_event), do: :ok

  defp validate_identity_claims(%{"email" => email, "email_verified" => true}, :id_jag) when is_binary(email) do
    :ok
  end

  defp validate_identity_claims(_claims, :id_jag), do: {:error, :missing_verified_email}

  defp validate_auth_freshness(claims, require_fresh_auth: true) do
    case claims do
      %{"auth_time" => auth_time} when is_integer(auth_time) ->
        age = DateTime.to_unix(Time.utc_now()) - auth_time

        cond do
          age < -@clock_skew_seconds -> {:error, :auth_time_too_old}
          age > @id_jag_max_auth_age_seconds + @clock_skew_seconds -> {:error, :auth_time_too_old}
          true -> :ok
        end

      _ ->
        {:error, :auth_time_missing}
    end
  end

  defp validate_auth_freshness(_claims, _opts), do: :ok

  defp record_jti(%{"iss" => issuer, "jti" => jti, "exp" => exp}) do
    expires_at = DateTime.from_unix!(exp)

    insert_jti(issuer, jti, expires_at)
  end

  defp record_jti(%{"iss" => issuer, "jti" => jti}) do
    expires_at = Time.utc_now() |> DateTime.add(10, :minute) |> DateTime.truncate(:second)
    insert_jti(issuer, jti, expires_at)
  end

  defp insert_jti(issuer, jti, expires_at) do
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
      registration_type: "agent_provider",
      agent_platform: claims["agent_platform"],
      agent_context_id: claims["agent_context_id"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
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

  defp create_protocol_provider_registration(claims, email, audience, registration_ip) do
    if Accounts.sso_enforced_for_email?(email) do
      create_protocol_step_up(claims, email, audience, registration_ip)
    else
      now = Time.utc_now()
      user = get_or_provision_user!(email)

      with {:ok, registration} <-
             %{
               registration_type: :agent_provider,
               status: :claimed,
               requested_credential_type: :access_token,
               email: email,
               claim_token_hash: hash_secret(prefixed_token("clm")),
               claim_token_expires_at: DateTime.add(now, @claim_token_ttl_seconds, :second),
               claimed_at: now,
               claimed_by_user_id: user.id,
               issuer: claims["iss"],
               subject: claims["sub"],
               audience: audience,
               client_id: claims["client_id"],
               assertion_jti: claims["jti"]
             }
             |> AgentRegistration.create_agent_provider_changeset()
             |> Repo.insert() do
        insert_event!(registration, :created, %{
          actor_ip: registration_ip,
          claimed_by_user_id: user.id,
          metadata: provider_event_metadata(claims, :access_token),
          occurred_at: now
        })

        insert_event!(registration, :claimed, %{
          actor_ip: registration_ip,
          claimed_by_user_id: user.id,
          metadata: provider_event_metadata(claims, :access_token),
          occurred_at: now
        })

        issue_protocol_assertion(registration, audience, user, registration_ip)
      end
    end
  end

  defp create_protocol_step_up(claims, email, audience, registration_ip) do
    case get_pending_provider_registration(claims, audience) do
      %AgentRegistration{} = registration ->
        if claim_token_expired?(registration) do
          maybe_expire_registration(registration)
          create_protocol_step_up_registration(claims, email, audience, registration_ip)
        else
          refresh_protocol_step_up(registration, claims, email, registration_ip)
        end

      nil ->
        create_protocol_step_up_registration(claims, email, audience, registration_ip)
    end
  end

  defp create_protocol_step_up_registration(claims, email, audience, registration_ip) do
    now = Time.utc_now()
    claim = build_claim_bundle()
    claim_token_expires_at = DateTime.add(now, @claim_token_ttl_seconds, :second)
    otp_expires_at = DateTime.add(now, @otp_ttl_seconds, :second)

    with {:ok, registration} <-
           %{
             registration_type: :agent_provider,
             status: :pending,
             requested_credential_type: :access_token,
             email: email,
             claim_token_hash: claim.claim_token_hash,
             claim_view_token_hash: claim.claim_view_token_hash,
             otp_hash: claim.otp_hash,
             claim_token_expires_at: claim_token_expires_at,
             otp_expires_at: otp_expires_at,
             claim_attempt_id: claim.claim_attempt_id,
             registration_ip: registration_ip,
             claim_requested_ip: registration_ip,
             issuer: claims["iss"],
             subject: claims["sub"],
             audience: audience,
             client_id: claims["client_id"],
             assertion_jti: claims["jti"]
           }
           |> AgentRegistration.create_pending_agent_provider_changeset()
           |> Repo.insert(),
         {:ok, _job} <- schedule_protocol_expiration(registration, claim_token_expires_at) do
      insert_event!(registration, :created, %{
        actor_ip: registration_ip,
        metadata: provider_event_metadata(claims, :access_token),
        occurred_at: now
      })

      insert_event!(registration, :claim_resent, %{
        actor_ip: registration_ip,
        metadata: %{claim_attempt_id: claim.claim_attempt_id, email: email},
        occurred_at: now
      })

      insert_protocol_claim_events!(registration, claim, email, registration_ip, now)

      {:interaction_required,
       %{
         registration: registration,
         claim_token: claim.claim_token,
         claim_token_expires_at: claim_token_expires_at,
         claim_view_token: claim.claim_view_token,
         user_code: claim.user_code,
         user_code_expires_at: otp_expires_at,
         post_claim_scopes: @scopes
       }}
    end
  end

  defp refresh_protocol_step_up(registration, claims, email, registration_ip) do
    now = Time.utc_now()
    claim = build_claim_bundle()

    otp_expires_at =
      now
      |> DateTime.add(@otp_ttl_seconds, :second)
      |> earliest_datetime(registration.claim_token_expires_at)

    with {:ok, registration} <-
           registration
           |> AgentRegistration.refresh_provider_step_up_changeset(%{
             claim_token_hash: claim.claim_token_hash,
             claim_view_token_hash: claim.claim_view_token_hash,
             otp_hash: claim.otp_hash,
             otp_expires_at: otp_expires_at,
             claim_attempt_id: claim.claim_attempt_id,
             otp_attempt_count: 0,
             claim_requested_ip: registration_ip,
             assertion_jti: claims["jti"],
             last_polled_at: nil
           })
           |> Repo.update() do
      insert_event!(registration, :claim_resent, %{
        actor_ip: registration_ip,
        metadata: %{claim_attempt_id: claim.claim_attempt_id, email: email},
        occurred_at: now
      })

      insert_protocol_claim_events!(registration, claim, email, registration_ip, now)

      {:interaction_required,
       %{
         registration: registration,
         claim_token: claim.claim_token,
         claim_token_expires_at: registration.claim_token_expires_at,
         claim_view_token: claim.claim_view_token,
         user_code: claim.user_code,
         user_code_expires_at: otp_expires_at,
         post_claim_scopes: @scopes
       }}
    end
  end

  defp get_pending_provider_registration(%{"iss" => issuer, "sub" => subject}, audience) do
    Repo.one(
      from(r in AgentRegistration,
        where:
          r.registration_type == :agent_provider and r.status == :pending and r.issuer == ^issuer and
            r.subject == ^subject and r.audience == ^audience,
        order_by: [desc: r.inserted_at],
        limit: 1
      )
    )
  end

  defp issue_protocol_assertion(registration, audience, user, actor_ip) do
    user = Repo.preload(user, :account)

    with {:ok, signed} <-
           AgentAuthSigningKey.sign(registration, audience,
             version: 2,
             email: user.email,
             email_verified: true
           ) do
      insert_event!(registration, :assertion_issued, %{
        actor_ip: actor_ip,
        claimed_by_user_id: user.id,
        metadata: %{version: 2},
        occurred_at: Time.utc_now()
      })

      {:ok,
       %{
         registration: registration,
         identity_assertion: signed.assertion,
         assertion_expires_at: signed.expires_at,
         scopes: @scopes
       }}
    end
  end

  defp get_delegation_registration!(%{"iss" => issuer, "sub" => subject}, audience) do
    Repo.one!(
      from(r in AgentRegistration,
        where:
          r.registration_type == :agent_provider and r.status == :claimed and r.issuer == ^issuer and
            r.subject == ^subject and r.audience == ^audience,
        order_by: [desc: r.claimed_at],
        limit: 1
      )
    )
  end

  defp ensure_claim_user_matches(%AgentRegistration{email: email}, %User{email: user_email}) do
    if normalize_email(email) == normalize_email(user_email), do: :ok, else: {:error, :wrong_account}
  end

  defp ensure_protocol_claim_startable(%AgentRegistration{registration_type: :anonymous}), do: :ok
  defp ensure_protocol_claim_startable(_registration), do: {:error, :claim_not_available}

  defp ensure_browser_sso_policy_satisfied(%User{} = user, auth_method) do
    if Accounts.sso_enforced_for_email?(user.email) do
      with {:ok, organization} <- Accounts.sso_organization_for_user_email(user.email),
           true <- auth_method == organization.sso_provider,
           true <- Accounts.belongs_to_sso_organization?(user, organization) do
        :ok
      else
        _ -> {:error, :sso_required}
      end
    else
      :ok
    end
  end

  defp bind_protocol_registration(%AgentRegistration{registration_type: :anonymous} = registration, user) do
    {:ok, _credential} = claim_credential(registration, user)
    :ok
  end

  defp bind_protocol_registration(_registration, _user), do: :ok

  defp record_failed_user_code_attempt(claim_view_token, attrs) do
    case get_registration_by_claim_view_token(claim_view_token, lock: "FOR UPDATE") do
      {:ok, registration} ->
        now = Time.utc_now()

        registration =
          registration
          |> AgentRegistration.increment_otp_attempts_changeset()
          |> Repo.update!()

        insert_event!(registration, :otp_failed, %{
          actor_ip: Map.get(attrs, :claim_completed_ip),
          metadata: %{
            claim_attempt_id: registration.claim_attempt_id,
            otp_attempt_count: registration.otp_attempt_count
          },
          occurred_at: now
        })

        if registration.otp_attempt_count >= @max_otp_attempts,
          do: {:error, :rate_limited},
          else: {:error, :user_code_invalid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp provider_display_name(%AgentRegistration{issuer: nil}), do: nil

  defp provider_display_name(%AgentRegistration{issuer: issuer}) do
    case trusted_provider(issuer) do
      {:ok, provider} -> provider_value(provider, "display_name") || issuer
      _ -> issuer
    end
  end

  defp validate_protocol_resource(nil, _audience), do: :ok
  defp validate_protocol_resource("", _audience), do: :ok
  defp validate_protocol_resource(resource, audience) when resource == audience <> "/mcp", do: :ok
  defp validate_protocol_resource(_resource, _audience), do: {:error, :invalid_target}

  defp get_registration_from_service_assertion(%{"sub" => "reg_" <> registration_id}) do
    case Repo.get(AgentRegistration, registration_id) do
      %AgentRegistration{} = registration -> {:ok, registration}
      nil -> {:error, :invalid_grant}
    end
  end

  defp get_registration_from_service_assertion(_claims), do: {:error, :invalid_grant}

  defp ensure_protocol_assertion_current(%AgentRegistration{status: status}, _claims) when status in [:expired, :revoked],
    do: {:error, :invalid_grant}

  defp ensure_protocol_assertion_current(
         %AgentRegistration{registration_type: :anonymous, status: :pending} = registration,
         %{"agent_auth_version" => 1}
       ) do
    case ensure_claim_token_valid(registration) do
      :ok -> :ok
      {:error, _reason} -> {:error, :invalid_grant}
    end
  end

  defp ensure_protocol_assertion_current(%AgentRegistration{status: :claimed}, %{"agent_auth_version" => 2}), do: :ok
  defp ensure_protocol_assertion_current(_registration, _claims), do: {:error, :invalid_grant}

  defp issue_protocol_access_token(%AgentRegistration{} = registration) do
    with {:ok, user} <- protocol_registration_user(registration) do
      user = Repo.preload(user, :account)

      expires_at =
        Time.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.add(@protocol_access_token_ttl_seconds, :second)

      {:ok, access_token, claims} =
        Tuist.Guardian.encode_and_sign(
          user.account,
          %{
            "type" => "account",
            "scopes" => @scopes,
            "all_projects" => true,
            "user_id" => user.id,
            "preferred_username" => user.account.name,
            "email" => user.email,
            "agent_registration_id" => registration.id
          },
          token_type: "access_token",
          ttl: {@protocol_access_token_ttl_seconds, :second}
        )

      with {:ok, _credential} <-
             %{
               agent_registration_id: registration.id,
               jti: claims["jti"],
               expires_at: expires_at
             }
             |> AgentAuthCredential.create_changeset()
             |> Repo.insert() do
        insert_event!(registration, :token_issued, %{
          claimed_by_user_id: registration.claimed_by_user_id,
          metadata: %{credential_jti: claims["jti"], scope: Enum.join(@scopes, " ")},
          occurred_at: Time.utc_now()
        })

        {:ok,
         %{
           access_token: access_token,
           token_type: "Bearer",
           expires_in: @protocol_access_token_ttl_seconds,
           scope: Enum.join(@scopes, " ")
         }}
      end
    end
  end

  defp protocol_registration_user(%AgentRegistration{status: :claimed, claimed_by_user_id: user_id})
       when not is_nil(user_id) do
    case User |> Repo.get(user_id) |> Repo.preload(:account) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :invalid_grant}
    end
  end

  defp protocol_registration_user(%AgentRegistration{
         registration_type: :anonymous,
         status: :pending,
         account_token_id: account_token_id
       }) do
    case AccountToken |> Repo.get(account_token_id) |> Repo.preload(account: :user) do
      %AccountToken{account: %{user: %User{} = user}} -> {:ok, Repo.preload(user, :account)}
      _ -> {:error, :invalid_grant}
    end
  end

  defp protocol_registration_user(_registration), do: {:error, :invalid_grant}

  defp ensure_claim_pollable(%AgentRegistration{status: status}) when status in [:expired, :revoked],
    do: {:error, :expired_token}

  defp ensure_claim_pollable(%AgentRegistration{status: :claimed} = registration) do
    if claim_token_expired?(registration), do: {:error, :expired_token}, else: :ok
  end

  defp ensure_claim_pollable(%AgentRegistration{} = registration) do
    if claim_token_expired?(registration) do
      maybe_expire_registration(registration)
      {:error, :expired_token}
    else
      :ok
    end
  end

  defp enforce_poll_interval(%AgentRegistration{last_polled_at: nil}), do: :ok

  defp enforce_poll_interval(%AgentRegistration{last_polled_at: last_polled_at}) do
    if DateTime.diff(Time.utc_now(), last_polled_at, :second) < @protocol_poll_interval_seconds,
      do: {:error, :slow_down},
      else: :ok
  end

  defp validate_security_events(%{"events" => events}) when is_map(events) and map_size(events) > 0 do
    {:ok, Map.keys(events)}
  end

  defp validate_security_events(_claims), do: {:error, :invalid_request}

  defp revoke_provider_delegation(claims, audience) do
    now = Time.utc_now()
    registrations = list_revocable_provider_registrations(claims, audience)

    Enum.each(registrations, fn registration ->
      revoke_credential(registration)
      revoke_registration_credentials(registration.id, now)

      {:ok, registration} =
        registration
        |> AgentRegistration.revoke_changeset(%{status: :revoked, revoked_at: now})
        |> Repo.update()

      insert_event!(registration, :revoked, %{
        metadata: %{
          issuer: claims["iss"],
          subject: claims["sub"],
          audience: audience,
          assertion_jti: claims["jti"]
        },
        occurred_at: now
      })
    end)

    :ok
  end

  defp revoke_registration_credentials(registration_id, revoked_at) do
    Repo.update_all(
      from(c in AgentAuthCredential, where: c.agent_registration_id == ^registration_id and is_nil(c.revoked_at)),
      set: [revoked_at: revoked_at, updated_at: revoked_at]
    )

    :ok
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
      user_code: otp,
      otp_hash: hash_secret(otp),
      claim_attempt_id: "cla_#{UUIDv7.generate()}"
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

  defp insert_protocol_claim_events!(registration, claim, email, actor_ip, occurred_at) do
    metadata = %{claim_attempt_id: claim.claim_attempt_id, email: email}

    insert_event!(registration, :claim_requested, %{
      actor_ip: actor_ip,
      metadata: metadata,
      occurred_at: occurred_at
    })

    insert_event!(registration, :user_code_minted, %{
      actor_ip: actor_ip,
      metadata: metadata,
      occurred_at: occurred_at
    })
  end

  defp schedule_protocol_expiration(registration, expires_at) do
    schedule_in = max(DateTime.diff(expires_at, Time.utc_now(), :second), 0)

    %{registration_id: registration.id}
    |> ExpireAgentRegistrationWorker.new(schedule_in: schedule_in)
    |> Oban.insert()
  end

  defp earliest_datetime(first, second) do
    case DateTime.compare(first, second) do
      :gt -> second
      _ -> first
    end
  end

  defp unwrap_repo_transaction({:ok, {:error, reason}}), do: {:error, reason}
  defp unwrap_repo_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_repo_transaction({:error, reason}), do: {:error, reason}
end
