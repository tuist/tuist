defmodule Tuist.Accounts.UserMFA do
  @moduledoc """
  Opt-in authenticator-app MFA. Factor verification and recovery consumption
  serialize on the factor row, including the shared per-user attempt budget.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Accounts.UserToken
  alias Tuist.Repo
  alias Tuist.Time

  require Logger

  schema "user_mfa" do
    belongs_to :user, User
    field :secret, Tuist.Vault.Binary, redact: true
    field :enrollment_session_hash, :binary, redact: true
    field :enrollment_expires_at, :utc_datetime
    field :confirmed_at, :utc_datetime
    field :last_used_at, :utc_datetime
    field :recovery_code_hashes, {:array, :binary}, default: [], redact: true
    field :failed_attempts, :integer, default: 0
    field :attempt_window_started_at, :utc_datetime
  end

  def enabled?(user) do
    Repo.exists?(from factor in __MODULE__, where: factor.user_id == ^user.id and not is_nil(factor.confirmed_at))
  end

  defp fresh_session?(%UserToken{token: token}, %User{id: id}) do
    # Re-read after acquiring the user lock: logout or reset may have revoked
    # the session while this request was waiting to change the factor.
    case Accounts.get_user_session(token) do
      %UserToken{user_id: ^id, auth_provider: provider, inserted_at: created_at} when is_binary(provider) ->
        NaiveDateTime.diff(DateTime.to_naive(Time.utc_now()), created_at) in 0..300

      _ ->
        false
    end
  end

  defp fresh_session?(_, _), do: false

  def begin_enrollment(user, session) do
    transaction(fn ->
      # Lock the user even when no factor exists, so concurrent enrollments
      # cannot overwrite a just-confirmed secret.
      Repo.one!(from user in User, where: user.id == ^user.id, lock: "FOR UPDATE")
      factor = Repo.get_by(__MODULE__, user_id: user.id)

      cond do
        not fresh_session?(session, user) ->
          {:error, :reauthentication_required}

        factor && factor.confirmed_at ->
          {:error, :already_enabled}

        factor && factor.enrollment_session_hash == hash(session.token) &&
            DateTime.after?(factor.enrollment_expires_at, Time.utc_now()) ->
          {:ok, factor}

        true ->
          (factor || %__MODULE__{user_id: user.id})
          |> change(%{
            secret: NimbleTOTP.secret(),
            enrollment_session_hash: hash(session.token),
            enrollment_expires_at: DateTime.add(now(), 300),
            failed_attempts: 0,
            attempt_window_started_at: nil
          })
          |> Repo.insert_or_update()
      end
    end)
  end

  def confirm_enrollment(user, session, code) do
    user
    |> with_factor(fn factor ->
      with true <- fresh_session?(session, user),
           true <- is_nil(factor.confirmed_at),
           true <- factor.enrollment_session_hash == hash(session.token),
           true <- DateTime.after?(factor.enrollment_expires_at, now()),
           {:ok, factor} <- verify_locked(factor, code, false) do
        codes = recovery_codes()
        factor |> change(confirmed_at: now(), recovery_code_hashes: Enum.map(codes, &hash/1)) |> Repo.update!()
        revoked_sessions = revoke_sessions(user)
        session = issue_session(user, auth_params(session))
        {:ok, %{recovery_codes: codes, revoked_sessions: revoked_sessions, session: session}}
      else
        false -> {:error, :enrollment_expired}
        error -> error
      end
    end)
    |> notify_factor_change(user, true)
  end

  def verify(user, code) do
    with_factor(user, fn factor ->
      if factor.confirmed_at, do: verify_locked(factor, code, true), else: {:error, :not_enabled}
    end)
  end

  def disable(user, session, code) do
    user
    |> with_factor(fn factor ->
      with true <- fresh_session?(session, user),
           true <- not is_nil(factor.confirmed_at),
           {:ok, _} <- verify_locked(factor, code, true) do
        Repo.delete!(factor)
        revoked_sessions = revoke_sessions(user)
        session = issue_session(user, auth_params(session))
        {:ok, %{revoked_sessions: revoked_sessions, session: session}}
      else
        false -> {:error, :reauthentication_required}
        error -> error
      end
    end)
    |> notify_factor_change(user, false)
  end

  defp notify_factor_change({:ok, _} = result, user, enabled?) do
    case UserNotifier.deliver_mfa_change_notification(user, enabled?) do
      {:ok, _} -> :ok
      {:error, _} -> Logger.error("MFA factor-change notification failed", auth_user_id: user.id)
    end

    result
  end

  defp notify_factor_change(error, _user, _enabled?), do: error

  def create_challenge(user, auth) do
    {token, session} = UserToken.build_session_token(user, auth)
    Repo.insert!(%{session | context: "mfa"})
    token
  end

  def get_challenge(token) when is_binary(token) do
    Repo.one(
      from session in UserToken,
        join: user in assoc(session, :user),
        where: session.token == ^token and session.context == "mfa" and user.active,
        where: session.inserted_at > ^NaiveDateTime.add(DateTime.to_naive(now()), -300),
        preload: [user: {user, [:account]}]
    )
  end

  def get_challenge(_), do: nil

  def delete_challenge(token) do
    Repo.delete_all(from session in UserToken, where: session.token == ^token and session.context == "mfa")
    :ok
  end

  def complete_challenge(token, code) when is_binary(token) do
    transaction(fn ->
      if challenge = get_challenge(token) do
        lock_user(challenge.user_id)
      end

      # The challenge is single-use independently of the TOTP/recovery code.
      case Repo.one(
             from session in UserToken, where: session.token == ^token and session.context == "mfa", lock: "FOR UPDATE"
           ) do
        nil ->
          {:error, :challenge_expired}

        _ ->
          with %UserToken{} = challenge <- get_challenge(token),
               {:ok, _} <- verify(challenge.user, code) do
            Repo.delete!(challenge)
            {:ok, issue_session(challenge.user, auth_params(challenge))}
          else
            nil -> {:error, :challenge_expired}
            error -> error
          end
      end
    end)
  end

  def complete_challenge(_, _), do: {:error, :challenge_expired}

  # Call only while holding the user lock. Proof consumption, factor changes
  # and session creation must commit together, before reset can revoke them.
  defp issue_session(user, auth) do
    token = Accounts.generate_user_session_token(user, Map.put(auth, :mfa_verified_at, now()))
    Accounts.get_user_session(token, preload: [:account])
  end

  def auth_params(session) do
    %{
      auth_method: String.to_existing_atom(session.auth_provider),
      provider_organization_id: session.auth_provider_organization_id,
      sso_organization_id: session.auth_organization_id
    }
  end

  defp verify_locked(factor, code, allow_recovery?) do
    current = now()
    window = factor.attempt_window_started_at
    attempts = failed_attempts(factor, current)
    code = if is_binary(code), do: String.trim(code), else: ""

    accepted_time = valid_totp_time(factor, code, current)

    recovery_hash = hash(code)
    recovery? = allow_recovery? and Enum.any?(factor.recovery_code_hashes, &Plug.Crypto.secure_compare(&1, recovery_hash))

    cond do
      attempts >= 5 ->
        {:error, :rate_limited}

      accepted_time || recovery? ->
        changes = %{failed_attempts: 0, attempt_window_started_at: nil}

        changes =
          if accepted_time,
            do: Map.put(changes, :last_used_at, accepted_time),
            else: Map.put(changes, :recovery_code_hashes, List.delete(factor.recovery_code_hashes, recovery_hash))

        {:ok, factor |> change(changes) |> Repo.update!()}

      true ->
        factor
        |> change(%{
          failed_attempts: attempts + 1,
          attempt_window_started_at: if(attempts == 0, do: current, else: window)
        })
        |> Repo.update!()

        {:error, :invalid_code}
    end
  end

  defp failed_attempts(%{attempt_window_started_at: nil}, _current), do: 0

  defp failed_attempts(factor, current) do
    if DateTime.diff(current, factor.attempt_window_started_at) < 300, do: factor.failed_attempts, else: 0
  end

  defp valid_totp_time(factor, code, current) do
    Enum.find([current, DateTime.add(current, -30), DateTime.add(current, 30)], fn time ->
      NimbleTOTP.valid?(factor.secret, code, time: time, since: factor.last_used_at)
    end)
  end

  defp revoke_sessions(user) do
    sessions = Repo.all(UserToken.by_user_and_contexts_query(user, ["session"]))
    Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["session", "mfa"]))
    Enum.map(sessions, &UserToken.live_socket_id/1)
  end

  defp with_factor(user, fun) do
    transaction(fn ->
      lock_user(user.id)

      case Repo.one(from factor in __MODULE__, where: factor.user_id == ^user.id, lock: "FOR UPDATE") do
        nil -> {:error, :not_enabled}
        factor -> fun.(factor)
      end
    end)
  end

  defp lock_user(id), do: Repo.one!(from user in User, where: user.id == ^id, lock: "FOR UPDATE")

  defp transaction(fun) do
    case Repo.transaction(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp recovery_codes, do: Enum.map(1..10, fn _ -> Base.encode32(:crypto.strong_rand_bytes(16), padding: false) end)
  defp hash(value), do: :crypto.hash(:sha256, value)
  defp now, do: DateTime.truncate(Time.utc_now(), :second)
end
