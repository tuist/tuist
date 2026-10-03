defmodule Atlas.Assets.Event do
  @moduledoc """
  A physical observation attached to an asset: a repair, an incident, a
  paid warranty extension, or a free-form note.

  Events are user-facing history entries that live alongside the assignment
  timeline in the dashboard. Lifecycle transitions (place-in-service,
  assign, return, retire, dispose, mark_lost, recover, mark_in_repair,
  mark_repaired) do not write to this table; they surface through
  `Atlas.Audit` and through the state fields on the asset itself.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Assets.Asset
  alias Atlas.Assets.Event
  alias Atlas.Finance.Transaction

  @event_types ~w(repaired warranty_extended incident note)

  @derive {
    Flop.Schema,
    filterable: [:asset_id, :event_type], sortable: [:occurred_on, :inserted_at], default_limit: 50, max_limit: 200
  }

  schema "asset_events" do
    belongs_to :asset, Asset

    field :event_type, :string
    field :occurred_on, :date
    field :notes, :string

    field :expenditure, :decimal
    field :expenditure_currency, :string

    belongs_to :finance_transaction, Transaction, foreign_key: :finance_transaction_id

    field :previous_warranty_end_on, :date
    field :new_warranty_end_on, :date

    field :client_reference, :string

    timestamps()
  end

  def event_types, do: @event_types

  def changeset(%Event{} = event, attrs) do
    event
    |> cast(attrs, [
      :asset_id,
      :event_type,
      :occurred_on,
      :notes,
      :expenditure,
      :expenditure_currency,
      :finance_transaction_id,
      :previous_warranty_end_on,
      :new_warranty_end_on,
      :client_reference
    ])
    |> validate_required([:asset_id, :event_type, :occurred_on])
    |> validate_inclusion(:event_type, @event_types)
    |> update_change(:expenditure_currency, &normalize_currency/1)
    |> validate_expenditure_currency()
    |> validate_expenditure_currency_supported()
    |> validate_warranty_extension_fields()
    |> foreign_key_constraint(:asset_id)
    |> foreign_key_constraint(:finance_transaction_id)
    |> unique_constraint([:asset_id, :client_reference],
      name: :asset_events_client_reference_index,
      message: "has already been recorded for this asset"
    )
    |> check_constraint(:expenditure_currency,
      name: :asset_events_expenditure_currency_when_amount,
      message: "is required when an expenditure amount is set"
    )
    |> check_constraint(:new_warranty_end_on,
      name: :asset_events_warranty_ext_dates,
      message: "must be on or after the previous warranty end date"
    )
    |> check_constraint(:event_type, name: :asset_events_event_type_check, message: "is not a valid event type")
  end

  defp normalize_currency(nil), do: nil
  defp normalize_currency(value) when is_binary(value), do: value |> String.trim() |> String.upcase() |> nil_if_empty()
  defp nil_if_empty(""), do: nil
  defp nil_if_empty(value), do: value

  defp validate_expenditure_currency(changeset) do
    expenditure = get_field(changeset, :expenditure)
    currency = get_field(changeset, :expenditure_currency)

    if not is_nil(expenditure) and is_nil(currency) do
      add_error(changeset, :expenditure_currency, "is required when an expenditure amount is set")
    else
      changeset
    end
  end

  defp validate_expenditure_currency_supported(changeset) do
    case get_field(changeset, :expenditure_currency) do
      nil ->
        changeset

      code when is_binary(code) ->
        if supported_currency?(code) do
          changeset
        else
          add_error(changeset, :expenditure_currency, "is not a supported ISO 4217 currency code")
        end
    end
  end

  defp validate_warranty_extension_fields(changeset) do
    case get_field(changeset, :event_type) do
      "warranty_extended" ->
        previous = get_field(changeset, :previous_warranty_end_on)
        new = get_field(changeset, :new_warranty_end_on)

        cond do
          is_nil(previous) ->
            add_error(changeset, :previous_warranty_end_on, "is required for warranty extensions")

          is_nil(new) ->
            add_error(changeset, :new_warranty_end_on, "is required for warranty extensions")

          not Date.after?(new, previous) ->
            add_error(changeset, :new_warranty_end_on, "must be after the previous warranty end date")

          true ->
            changeset
        end

      _other ->
        changeset
    end
  end

  defp supported_currency?(code) do
    Money.Currency.exists?(code)
  rescue
    _ -> false
  end
end
