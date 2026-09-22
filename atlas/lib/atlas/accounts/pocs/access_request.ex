defmodule Atlas.Accounts.POCs.AccessRequest do
  @moduledoc """
  A visitor's request for access to a POC's public brief.

  Access requires **both** proof of email ownership (the visitor clicks a
  verification link sent to them) and operator approval from Slack. Once both
  are recorded, a signed session cookie is minted for that browser and
  subsequent visits skip the gate entirely. Ops can revoke a specific
  approval at any time without rotating the POC's public token.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.POCs.POC
  alias Atlas.Users.User

  schema "poc_access_requests" do
    field :email, :string
    field :requester_ip, :string
    field :requester_user_agent, :string
    field :slack_channel_id, :string
    field :slack_message_ts, :string
    field :verification_token_hash, :string
    field :verification_expires_at, :utc_datetime
    field :verified_at, :utc_datetime
    field :approved_at, :utc_datetime
    field :denied_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :poc, POC
    belongs_to :approved_by_user, User
    belongs_to :denied_by_user, User
    belongs_to :revoked_by_user, User

    timestamps(type: :utc_datetime)
  end

  def create_changeset(request, attrs) do
    request
    |> cast(attrs, [
      :poc_id,
      :email,
      :requester_ip,
      :requester_user_agent,
      :verification_token_hash,
      :verification_expires_at,
      :expires_at
    ])
    |> validate_required([
      :poc_id,
      :email,
      :verification_token_hash,
      :verification_expires_at,
      :expires_at
    ])
    |> update_change(:email, &String.downcase(String.trim(&1)))
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
    |> foreign_key_constraint(:poc_id)
  end

  # The email verification link's clock. Once past this timestamp, the
  # visitor must submit the email form again to mint a fresh token.
  def verification_expired?(%__MODULE__{verification_expires_at: %DateTime{} = expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  def verification_expired?(%__MODULE__{}), do: true

  def slack_message_changeset(request, attrs) do
    request
    |> cast(attrs, [:slack_channel_id, :slack_message_ts])
  end

  def status(%__MODULE__{revoked_at: %DateTime{}}), do: :revoked
  def status(%__MODULE__{denied_at: %DateTime{}}), do: :denied
  def status(%__MODULE__{approved_at: %DateTime{}, verified_at: %DateTime{}}), do: :granted
  def status(%__MODULE__{approved_at: %DateTime{}}), do: :awaiting_email
  def status(%__MODULE__{verified_at: %DateTime{}}), do: :awaiting_approval
  def status(%__MODULE__{}), do: :pending

  def active?(%__MODULE__{} = request), do: status(request) == :granted and not expired?(request)

  def expired?(%__MODULE__{expires_at: %DateTime{} = expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  def expired?(%__MODULE__{}), do: true
end
