defmodule Tuist.Accounts.UserPasskey do
  @moduledoc """
  WebAuthn passkeys. A passkey signs in on its own: registration and every
  assertion require user verification (biometrics or a device PIN), so a
  verified assertion proves possession and a second factor and satisfies MFA.
  Passkeys also complete the MFA challenge after a password, OAuth or SSO
  sign-in. Attestation is not requested; NIST SP 800-63B-4 does not require it
  for syncable authenticators.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserMFA
  alias Tuist.Accounts.Workers.SecurityNotificationWorker
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Time

  require Logger

  @ceremony_timeout 300
  @max_passkeys 20
  # EdDSA, ES256 and RS256 (Windows Hello).
  @algorithms [-8, -7, -257]

  schema "user_passkeys" do
    belongs_to :user, User
    field :name, :string
    field :credential_id, :binary
    field :public_key, :binary, redact: true
    field :user_handle, :binary
    field :sign_count, :integer, default: 0
    field :aaguid, :binary
    field :transports, {:array, :string}, default: []
    field :backup_eligible, :boolean, default: false
    field :backed_up, :boolean, default: false
    field :last_used_at, :utc_datetime
    field :last_challenge_issued_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def ceremony_timeout, do: @ceremony_timeout

  def list(user) do
    Repo.all(from passkey in __MODULE__, where: passkey.user_id == ^user.id, order_by: [asc: passkey.inserted_at])
  end

  @doc """
  Starts a registration ceremony. Returns the state to carry to `register/4`
  and the options for `navigator.credentials.create`. Freshness and the limit
  are checked here too, before the authenticator saves a credential that the
  server would then refuse to register.
  """
  def registration_options(user, session) do
    passkeys = list(user)

    cond do
      not UserMFA.fresh_session?(session, user) -> {:error, :reauthentication_required}
      length(passkeys) >= @max_passkeys -> {:error, :too_many_passkeys}
      true -> {:ok, new_registration(user, passkeys)}
    end
  end

  defp new_registration(user, passkeys) do
    challenge = Wax.new_registration_challenge(wax_options())

    # The WebAuthn user handle is an opaque random identifier, never the user
    # ID or email. All of a user's passkeys share it once one exists.
    user_handle =
      case passkeys do
        [passkey | _] -> passkey.user_handle
        [] -> :crypto.strong_rand_bytes(32)
      end

    options = %{
      challenge: encode(challenge.bytes),
      rp: %{id: challenge.rp_id, name: "Tuist"},
      user: %{id: encode(user_handle), name: user.email, displayName: user.email},
      pubKeyCredParams: Enum.map(@algorithms, &%{type: "public-key", alg: &1}),
      timeout: @ceremony_timeout * 1000,
      attestation: "none",
      authenticatorSelection: %{residentKey: "required", requireResidentKey: true, userVerification: "required"},
      excludeCredentials: descriptors(passkeys)
    }

    {%{challenge: challenge, user_handle: user_handle}, options}
  end

  @doc """
  Verifies a registration response and stores the passkey. Like changing the
  authenticator app, it requires a sign-in within the last five minutes.
  """
  def register(user, session, %{challenge: challenge, user_handle: user_handle}, params) do
    transaction(fn ->
      UserMFA.lock_user(user.id)

      with true <- UserMFA.fresh_session?(session, user) || {:error, :reauthentication_required},
           true <- count(user) < @max_passkeys || {:error, :too_many_passkeys},
           {:ok, attestation_object} <- decode(params["attestation_object"]),
           {:ok, client_data_json} <- decode(params["client_data_json"]),
           :ok <- same_origin_frame(client_data_json),
           {:ok, {%{attested_credential_data: %{} = credential} = auth_data, _attestation}} <-
             wax(fn -> Wax.register(attestation_object, client_data_json, challenge) end),
           # WebAuthn §7.1 step 23; Wax accepts IDs up to 65535 bytes.
           true <- byte_size(credential.credential_id) <= 1023 || {:error, :invalid_passkey},
           :ok <- valid_backup_flags(auth_data) do
        %__MODULE__{user_id: user.id, user_handle: user_handle}
        |> change(%{
          name: name(params["name"]),
          credential_id: credential.credential_id,
          public_key: :erlang.term_to_binary(credential.credential_public_key),
          sign_count: auth_data.sign_count,
          aaguid: Wax.AuthenticatorData.get_aaguid(auth_data),
          transports: transports(params["transports"]),
          backup_eligible: auth_data.flag_backup_eligible,
          backed_up: auth_data.flag_credential_backed_up
        })
        |> unique_constraint(:credential_id)
        |> Repo.insert()
        |> case do
          {:ok, passkey} ->
            SecurityNotificationWorker.enqueue(user, :passkey_added)
            {:ok, passkey}

          {:error, _changeset} ->
            {:error, :already_registered}
        end
      else
        {:ok, _unattested} -> {:error, :invalid_passkey}
        error -> error
      end
    end)
  end

  @doc """
  Renames a user's passkey after a recent sign-in. This only changes its
  label in Tuist, not the credential saved in the password manager.
  """
  def rename(user, session, id, new_name) do
    transaction(fn ->
      UserMFA.lock_user(user.id)

      with true <- UserMFA.fresh_session?(session, user) || {:error, :reauthentication_required},
           %__MODULE__{} = passkey <- Repo.get_by(__MODULE__, id: id, user_id: user.id) || {:error, :not_found} do
        passkey |> change(name: name(new_name)) |> Repo.update()
      end
    end)
  end

  @doc """
  Deletes a passkey. Removing a sign-in method revokes every session, as
  changing the authenticator app does, and moves this browser into a new one.
  """
  def delete(user, session, id) do
    transaction(fn ->
      UserMFA.lock_user(user.id)

      with true <- UserMFA.fresh_session?(session, user) || {:error, :reauthentication_required},
           %__MODULE__{} = passkey <- Repo.get_by(__MODULE__, id: id, user_id: user.id) || {:error, :not_found} do
        Repo.delete!(passkey)
        revoked_sessions = UserMFA.revoke_sessions(user)
        session = UserMFA.issue_session(user, UserMFA.auth_params(session))
        SecurityNotificationWorker.enqueue(user, :passkey_removed)
        {:ok, %{revoked_sessions: revoked_sessions, session: session}}
      end
    end)
  end

  @doc """
  Starts an authentication ceremony. Without a user, the browser offers the
  discoverable passkeys it holds for Tuist (passwordless sign-in); with one,
  only that user's passkeys (the MFA challenge).
  """
  def authentication_options(user \\ nil) do
    challenge = Wax.new_authentication_challenge(wax_options())

    options = %{
      challenge: encode(challenge.bytes),
      rpId: challenge.rp_id,
      timeout: @ceremony_timeout * 1000,
      userVerification: "required",
      allowCredentials: if(user, do: descriptors(list(user)), else: [])
    }

    {challenge, options}
  end

  @doc """
  Verifies a passwordless assertion and returns a new browser session for
  the passkey's user. Like the MFA challenge, verification and session
  creation happen under the user lock, so removing the passkey or resetting
  the password either revokes this session or makes the sign-in fail.
  """
  def authenticate(challenge, params) do
    with {:ok, credential_id} <- decode(params["credential_id"]),
         %__MODULE__{user_id: user_id} <- get_active(credential_id) || {:error, :invalid_passkey} do
      transaction(fn ->
        UserMFA.lock_user(user_id)

        # Re-read under the lock: the passkey may have been removed meanwhile.
        with %__MODULE__{} = passkey <- get_active(credential_id) || {:error, :invalid_passkey},
             {:ok, user_handle} <- decode(params["user_handle"]),
             true <- Plug.Crypto.secure_compare(user_handle, passkey.user_handle) || {:error, :invalid_passkey},
             {:ok, _passkey} <- verify_assertion(passkey, challenge, params) do
          {:ok, UserMFA.issue_session(passkey.user, %{auth_method: :passkey})}
        end
      end)
    end
  end

  @doc """
  Returns a verifier for `UserMFA.complete_challenge/2` that accepts an
  assertion from one of the challenged user's passkeys.
  """
  def challenge_verifier(challenge, params) do
    fn user ->
      with {:ok, credential_id} <- decode(params["credential_id"]),
           %__MODULE__{} = passkey <-
             Repo.get_by(__MODULE__, credential_id: credential_id, user_id: user.id) || {:error, :invalid_passkey} do
        verify_assertion(passkey, challenge, params)
      end
    end
  end

  defp verify_assertion(passkey, challenge, params) do
    cose_key = :erlang.binary_to_term(passkey.public_key, [:safe])

    with {:ok, authenticator_data} <- decode(params["authenticator_data"]),
         {:ok, signature} <- decode(params["signature"]),
         {:ok, client_data_json} <- decode(params["client_data_json"]),
         :ok <- same_origin_frame(client_data_json),
         {:ok, auth_data} <-
           wax(fn ->
             Wax.authenticate(passkey.credential_id, authenticator_data, signature, client_data_json, challenge, [
               {passkey.credential_id, cose_key}
             ])
           end),
         :ok <- valid_backup_flags(auth_data),
         # Backup eligibility is fixed when the credential is created.
         true <- auth_data.flag_backup_eligible == passkey.backup_eligible || {:error, :invalid_passkey} do
      # Ceremony tokens are stateless, so a captured token and assertion
      # could be presented again. Each passkey accepts only challenges issued
      # after the last one it answered. Authenticators that keep a counter
      # must increase it on every use (a regression suggests a cloned key);
      # synced passkeys always report zero.
      issued_at = DateTime.from_unix!(challenge.issued_at)
      received = auth_data.sign_count

      {count, _} =
        Repo.update_all(
          from(row in __MODULE__,
            where: row.id == ^passkey.id,
            where: is_nil(row.last_challenge_issued_at) or row.last_challenge_issued_at < ^issued_at,
            where: (row.sign_count == 0 and ^received == 0) or row.sign_count < ^received,
            update: [
              set: [
                sign_count: ^received,
                backed_up: ^auth_data.flag_credential_backed_up,
                last_challenge_issued_at: ^issued_at,
                last_used_at: ^now(),
                updated_at: ^now()
              ]
            ]
          ),
          []
        )

      if count == 1 do
        {:ok, passkey}
      else
        Logger.warning("Rejected a replayed passkey challenge or non-increasing signature counter")
        {:error, :invalid_passkey}
      end
    end
  end

  # Wax does not check `crossOrigin`. Tuist never asks for passkeys from an
  # embedded frame, so an assertion made inside another site's frame is refused.
  defp same_origin_frame(client_data_json) do
    case JSON.decode(client_data_json) do
      {:ok, %{"crossOrigin" => true}} -> {:error, :invalid_passkey}
      _ -> :ok
    end
  end

  # WebAuthn §7.2 step 18: a credential that is not backup eligible cannot be
  # backed up. Wax does not check this.
  defp valid_backup_flags(%{flag_backup_eligible: false, flag_credential_backed_up: true}), do: {:error, :invalid_passkey}
  defp valid_backup_flags(_auth_data), do: :ok

  defp get_active(credential_id) do
    Repo.one(
      from passkey in __MODULE__,
        join: user in assoc(passkey, :user),
        where: passkey.credential_id == ^credential_id and user.active,
        preload: [user: {user, :account}]
    )
  end

  defp count(user), do: Repo.aggregate(from(passkey in __MODULE__, where: passkey.user_id == ^user.id), :count)

  defp descriptors(passkeys) do
    Enum.map(passkeys, &%{type: "public-key", id: encode(&1.credential_id), transports: &1.transports})
  end

  defp wax_options do
    uri = URI.parse(Environment.app_url(route_type: :app))

    [
      origin: URI.to_string(%URI{scheme: uri.scheme, host: uri.host, port: uri.port}),
      rp_id: uri.host,
      user_verification: "required",
      attestation: "none",
      # Attestation is not requested; never fail a registration because an
      # authenticator sent a statement whose trust root is unknown.
      verify_trust_root: false,
      timeout: @ceremony_timeout
    ]
  end

  # Wax returns errors for invalid ceremonies but raises on some malformed
  # input (for example a non-string challenge in the client data), which
  # browsers never send. Both are a failed verification, not a server error.
  defp wax(verify) do
    case verify.() do
      {:ok, _} = result -> result
      {:error, _exception} -> {:error, :invalid_passkey}
    end
  rescue
    _ -> {:error, :invalid_passkey}
  end

  # Bounded by code points: the column limit counts code points, and one
  # emoji grapheme can hold many.
  defp name(name) when is_binary(name) do
    case name |> String.trim() |> String.codepoints() |> Enum.take(64) |> Enum.join() do
      "" -> "Passkey"
      name -> name
    end
  end

  defp name(_), do: "Passkey"

  @known_transports ~w(ble hybrid internal nfc smart-card usb)
  defp transports(transports) when is_binary(transports) do
    transports |> String.split(",", trim: true) |> Enum.filter(&(&1 in @known_transports))
  end

  defp transports(_), do: []

  defp decode(value) when is_binary(value) do
    case Base.url_decode64(value, padding: false) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_passkey}
    end
  end

  defp decode(_), do: {:error, :invalid_passkey}

  defp encode(bytes), do: Base.url_encode64(bytes, padding: false)

  # Errors roll back: a failed unique insert aborts the PostgreSQL transaction.
  defp transaction(fun) do
    fn ->
      case fun.() do
        {:error, reason} -> Repo.rollback(reason)
        result -> result
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp now, do: DateTime.truncate(Time.utc_now(), :second)
end
