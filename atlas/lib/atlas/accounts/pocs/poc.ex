defmodule Atlas.Accounts.POCs.POC do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.POCs.Context
  alias Atlas.Accounts.POCs.ScopeFeature
  alias Atlas.Accounts.POCs.TimelineEntry
  alias Atlas.Users.User

  @statuses ~w(draft active closed_won closed_lost)
  @hosting_values ~w(unknown cloud self_hosted)
  @accent_color_regex ~r/^#[0-9a-fA-F]{6}$/

  schema "pocs" do
    field :title, :string
    field :status, :string, default: "draft"
    field :hosting, :string, default: "unknown"
    field :starts_on, :date
    field :ends_on, :date
    field :public_token, Ecto.UUID
    field :brand_accent_color, :string
    field :brand_logo_url, :string
    field :summary, :string

    belongs_to :account, Account
    belongs_to :created_by_user, User
    belongs_to :updated_by_user, User

    has_one :context, Context, on_replace: :update
    has_many :scope_features, ScopeFeature
    has_many :timeline_entries, TimelineEntry

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def hosting_values, do: @hosting_values

  def public?(%__MODULE__{public_token: token}) when is_binary(token), do: true
  def public?(_poc), do: false

  def changeset(poc, attrs) do
    poc
    |> cast(attrs, [
      :account_id,
      :title,
      :status,
      :hosting,
      :starts_on,
      :ends_on,
      :brand_accent_color,
      :brand_logo_url,
      :summary
    ])
    |> validate_required([:account_id, :title])
    |> validate_length(:title, min: 2, max: 160)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:hosting, @hosting_values)
    |> validate_format(:brand_accent_color, @accent_color_regex, message: "must be a hex color like #1a2b3c")
    |> validate_length(:brand_logo_url, max: 2048)
    |> validate_length(:summary, max: 8000)
    |> validate_ends_after_starts()
    |> foreign_key_constraint(:account_id)
  end

  def public_token_changeset(poc, token) do
    poc
    |> change(public_token: token)
    |> unique_constraint(:public_token)
  end

  defp validate_ends_after_starts(changeset) do
    starts_on = get_field(changeset, :starts_on)
    ends_on = get_field(changeset, :ends_on)

    if starts_on && ends_on && Date.before?(ends_on, starts_on) do
      add_error(changeset, :ends_on, "must be on or after the start date")
    else
      changeset
    end
  end
end
