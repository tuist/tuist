defmodule Atlas.Accounts.Term do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Amounts

  @payments ~w(monthly yearly whole-term)

  def payments, do: @payments

  @doc """
  Returns the account's preloaded terms, or an empty list when the association
  was not loaded.
  """
  def loaded(account) do
    case Map.get(account, :terms, []) do
      %Ecto.Association.NotLoaded{} -> []
      terms when is_list(terms) -> terms
      _terms -> []
    end
  end

  schema "account_terms" do
    field :external_id, :string
    field :source, :string

    field :payment, :string
    field :start_date, :date
    field :end_date, :date
    field :price_per_seat, :decimal
    field :seats, :integer
    field :discount, :decimal
    field :total, :decimal
    field :currency, :string
    field :on_premise, :boolean, default: false
    field :renewal_notice_weeks, :integer
    field :po_number, :string

    belongs_to :account, Account

    timestamps()
  end

  def changeset(term, attrs) do
    term
    |> cast(attrs, [
      :external_id,
      :source,
      :payment,
      :start_date,
      :end_date,
      :price_per_seat,
      :seats,
      :discount,
      :total,
      :currency,
      :on_premise,
      :renewal_notice_weeks,
      :po_number
    ])
    |> validate_required([:source, :payment, :start_date, :total, :account_id])
    |> validate_inclusion(:payment, @payments)
    |> update_change(:currency, &Amounts.normalize_currency/1)
  end
end
