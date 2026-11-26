defmodule Tuist.Marketing.Attribution.SignupAttribution do
  @moduledoc """
  The campaign a user came from when they signed up in the browser (first
  touch). A visit from another site without campaign parameters has that site
  as its source and `referral` as its medium.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  schema "signup_attributions" do
    belongs_to :user, Tuist.Accounts.User, primary_key: true
    field :source, :string
    field :medium, :string
    field :campaign, :string
    field :content, :string
    field :term, :string
    field :inserted_at, :utc_datetime
  end

  def changeset(attribution, attrs) do
    attribution
    |> cast(attrs, [:source, :medium, :campaign, :content, :term])
    |> validate_required([:source])
    # The columns are `varchar(255)`; a longer value must fail the changeset,
    # not the sign-up transaction.
    |> validate_length(:source, max: 255, count: :codepoints)
    |> validate_length(:medium, max: 255, count: :codepoints)
    |> validate_length(:campaign, max: 255, count: :codepoints)
    |> validate_length(:content, max: 255, count: :codepoints)
    |> validate_length(:term, max: 255, count: :codepoints)
    |> put_change(:inserted_at, DateTime.truncate(DateTime.utc_now(), :second))
  end
end
