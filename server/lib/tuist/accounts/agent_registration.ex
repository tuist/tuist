defmodule Tuist.Accounts.AgentRegistration do
  @moduledoc """
  A module that represents agent-auth registrations.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AgentRegistrationEvent
  alias Tuist.Accounts.User

  @registration_types [:anonymous, :email_verification, :agent_provider]
  @statuses [:pending, :claimed, :expired, :revoked]
  @requested_credential_types [:access_token, :api_key]

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "agent_registrations" do
    field :registration_type, Ecto.Enum, values: @registration_types
    field :status, Ecto.Enum, values: @statuses
    field :requested_credential_type, Ecto.Enum, values: @requested_credential_types
    field :email, :string
    field :claim_token_hash, :binary
    field :claim_view_token_hash, :binary
    field :otp_hash, :binary
    field :claim_token_expires_at, :utc_datetime
    field :otp_expires_at, :utc_datetime
    field :claim_attempt_id, :string
    field :otp_attempt_count, :integer, default: 0
    field :registration_ip, :string
    field :claim_requested_ip, :string
    field :claim_completed_ip, :string
    field :claimed_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :issuer, :string
    field :subject, :string
    field :audience, :string
    field :client_id, :string
    field :assertion_jti, :string
    field :credential_jti, :string

    belongs_to :claimed_by_user, User
    belongs_to :account_token, AccountToken, type: UUIDv7
    has_many :events, AgentRegistrationEvent

    timestamps(type: :utc_datetime)
  end

  def create_email_verification_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :registration_type,
      :status,
      :requested_credential_type,
      :email,
      :claim_token_hash,
      :claim_view_token_hash,
      :otp_hash,
      :claim_token_expires_at,
      :otp_expires_at,
      :claim_attempt_id,
      :otp_attempt_count,
      :registration_ip,
      :claim_requested_ip
    ])
    |> update_change(:email, &normalize_email/1)
    |> validate_required([
      :registration_type,
      :status,
      :requested_credential_type,
      :email,
      :claim_token_hash,
      :claim_view_token_hash,
      :otp_hash,
      :claim_token_expires_at,
      :otp_expires_at,
      :claim_attempt_id
    ])
    |> unique_constraint(:claim_token_hash)
    |> unique_constraint(:claim_view_token_hash)
  end

  def create_anonymous_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :registration_type,
      :status,
      :requested_credential_type,
      :email,
      :claim_token_hash,
      :claim_token_expires_at,
      :registration_ip,
      :account_token_id
    ])
    |> validate_required([
      :registration_type,
      :status,
      :requested_credential_type,
      :email,
      :claim_token_hash,
      :claim_token_expires_at,
      :account_token_id
    ])
    |> unique_constraint(:claim_token_hash)
  end

  def create_agent_provider_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :registration_type,
      :status,
      :requested_credential_type,
      :email,
      :claim_token_hash,
      :claim_token_expires_at,
      :claimed_at,
      :claimed_by_user_id,
      :account_token_id,
      :issuer,
      :subject,
      :audience,
      :client_id,
      :assertion_jti,
      :credential_jti
    ])
    |> update_change(:email, &normalize_email/1)
    |> validate_required([
      :registration_type,
      :status,
      :requested_credential_type,
      :email,
      :claim_token_hash,
      :claim_token_expires_at,
      :claimed_at,
      :claimed_by_user_id,
      :issuer,
      :subject,
      :audience,
      :client_id,
      :assertion_jti
    ])
    |> unique_constraint(:claim_token_hash)
  end

  def refresh_claim_changeset(agent_registration, attrs) do
    agent_registration
    |> cast(attrs, [
      :claim_view_token_hash,
      :otp_hash,
      :otp_expires_at,
      :claim_attempt_id,
      :otp_attempt_count,
      :claim_requested_ip,
      :email
    ])
    |> validate_required([
      :claim_view_token_hash,
      :otp_hash,
      :otp_expires_at,
      :claim_attempt_id
    ])
    |> unique_constraint(:claim_view_token_hash)
  end

  def increment_otp_attempts_changeset(agent_registration) do
    change(agent_registration, otp_attempt_count: agent_registration.otp_attempt_count + 1)
  end

  def claim_changeset(agent_registration, attrs) do
    agent_registration
    |> cast(attrs, [:status, :claimed_at, :claim_completed_ip, :claimed_by_user_id, :account_token_id, :credential_jti])
    |> validate_required([:status, :claimed_at, :claimed_by_user_id])
  end

  def expire_changeset(agent_registration) do
    change(agent_registration, status: :expired)
  end

  def revoke_changeset(agent_registration, attrs) do
    agent_registration
    |> cast(attrs, [:status, :revoked_at])
    |> validate_required([:status, :revoked_at])
  end

  defp normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_email(email), do: email
end
