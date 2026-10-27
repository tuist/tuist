defmodule Atlas.Assets.Asset do
  @moduledoc """
  A single hardware asset: a laptop, server, network device, monitor, UPS,
  peripheral, or other physical item Tuist owns.

  All lifecycle-owned fields (state, assigned_to_id, retired_on, disposed_on,
  lost_on, recovered_on, pre_loss_state, pre_repair_state, placed_in_service_on,
  disposal_proceeds, disposal_currency) are updated exclusively through
  functions in `Atlas.Assets`. `metadata_changeset/2` and `create_changeset/2`
  do not cast them.

  Book-value depreciation math and category defaults are documented in
  `docs/hardware-inventory-proposal.md`.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Assets.Asset
  alias Atlas.Assets.Assignment
  alias Atlas.Assets.DataCenter
  alias Atlas.Assets.Event
  alias Atlas.Documents.Document
  alias Atlas.Finance.Invoice
  alias Atlas.Finance.Transaction
  alias Atlas.Users.User

  @categories ~w(laptop desktop server network_switch router ups monitor peripheral other)
  @states ~w(in_service in_storage in_repair retired disposed lost returned_to_lessor)
  @locations ~w(data_center office home in_transit other)
  @valuation_treatments ~w(depreciable fully_expensed unknown)
  @ownership_values ~w(owned leased unknown)
  @pre_loss_states ~w(in_service in_storage in_repair)
  @pre_repair_states ~w(in_service in_storage)

  @accepted_document_statuses ~w(uploaded processing ready)

  @useful_life_defaults %{
    "laptop" => 36,
    "desktop" => 48,
    "server" => 60,
    "network_switch" => 60,
    "router" => 60,
    "ups" => 60,
    "monitor" => 60,
    "peripheral" => 24,
    "other" => 36
  }

  @metadata_fields ~w(
    asset_tag
    serial_number
    manufacturer
    model
    name
    specs
    category
    location
    location_detail
    data_center_id
    warranty_end_on
    rack_position
    finance_transaction_id
    finance_invoice_id
    purchase_document_id
    vendor
    notes
  )a

  @creation_fields @metadata_fields ++
                     ~w(purchased_on acquisition_cost acquisition_currency useful_life_months salvage_value valuation_treatment ownership ownership_acquired_on)a

  @derive {
    Flop.Schema,
    filterable: [:category, :state, :location, :assigned_to_id, :valuation_treatment, :data_center_id],
    sortable: [
      :name,
      :category,
      :state,
      :location,
      :acquisition_cost,
      :purchased_on,
      :warranty_end_on,
      :inserted_at
    ],
    default_limit: 50,
    max_limit: 200
  }

  schema "assets" do
    field :asset_tag, :string
    field :serial_number, :string
    field :manufacturer, :string
    field :model, :string
    field :name, :string

    field :category, :string
    field :specs, :map, default: %{}

    field :purchased_on, :date
    field :placed_in_service_on, :date
    field :acquisition_cost, :decimal
    field :acquisition_currency, :string
    field :useful_life_months, :integer
    field :salvage_value, :decimal, default: Decimal.new(0)
    field :valuation_treatment, :string, default: "depreciable"

    field :state, :string, default: "in_storage"
    field :ownership, :string, default: "owned"
    field :ownership_acquired_on, :date
    field :location, :string, default: "office"
    field :location_detail, :string
    field :warranty_end_on, :date

    belongs_to :assigned_to, User, foreign_key: :assigned_to_id
    belongs_to :data_center, DataCenter, foreign_key: :data_center_id

    field :rack_position, :map

    belongs_to :finance_transaction, Transaction, foreign_key: :finance_transaction_id
    belongs_to :finance_invoice, Invoice, foreign_key: :finance_invoice_id
    belongs_to :purchase_document, Document, foreign_key: :purchase_document_id

    field :vendor, :string

    field :pre_loss_state, :string
    field :pre_repair_state, :string

    field :lost_on, :date
    field :recovered_on, :date
    field :retired_on, :date
    field :disposed_on, :date
    field :disposal_proceeds, :decimal
    field :disposal_currency, :string

    field :notes, :string

    has_many :assignments, Assignment
    has_many :events, Event

    timestamps()
  end

  def categories, do: @categories
  def states, do: @states
  def locations, do: @locations
  def valuation_treatments, do: @valuation_treatments
  def ownership_values, do: @ownership_values
  def pre_loss_states, do: @pre_loss_states
  def pre_repair_states, do: @pre_repair_states

  @doc """
  Category-based default for `useful_life_months`. Falls back to 36 for
  unknown categories.
  """
  def default_useful_life_months(category) when is_binary(category) do
    Map.get(@useful_life_defaults, category, 36)
  end

  def default_useful_life_months(_), do: 36

  @doc """
  Changeset for creating a new asset. Rejects lifecycle-owned fields.

  If `useful_life_months` is not supplied, the category default is snapshotted
  onto the row. Explicit values are respected.
  """
  def create_changeset(%Asset{} = asset, attrs) do
    attrs =
      attrs
      |> maybe_default_useful_life_months()
      |> maybe_default_ownership_acquired_on()

    asset
    |> cast(attrs, @creation_fields)
    |> validate_required([
      :name,
      :category,
      :acquisition_cost,
      :acquisition_currency,
      :useful_life_months
    ])
    |> validate_purchased_on_required()
    |> common_validations()
  end

  # `purchased_on` is required when the asset is `:owned` or `:unknown`. It is
  # allowed to be null for `:leased` equipment because we have not (yet)
  # purchased it. Post-exercise, `Atlas.Assets.mark_owned_via_exercise/2`
  # backfills the field.
  defp validate_purchased_on_required(changeset) do
    ownership = get_field(changeset, :ownership) || "owned"

    if ownership == "leased" do
      changeset
    else
      validate_required(changeset, [:purchased_on])
    end
  end

  @doc """
  Changeset for editing non-lifecycle metadata on an existing asset.

  Lifecycle-owned fields (state, assigned_to_id, retired_on, disposed_on,
  lost_on, recovered_on, placed_in_service_on, disposal_proceeds,
  disposal_currency, pre_loss_state, pre_repair_state) are not cast here and
  can only change through the `Atlas.Assets` lifecycle functions.

  Acquisition cost, currency, useful life, salvage value, and valuation
  treatment are also lifecycle-adjacent (they change historical book-value
  reporting) and are edited through a dedicated valuation path in the
  context module, not here.
  """
  def metadata_changeset(%Asset{} = asset, attrs) do
    asset
    |> cast(attrs, @metadata_fields)
    |> common_validations()
  end

  @doc """
  Internal changeset used by lifecycle functions in `Atlas.Assets`. Skips
  metadata-only validations but still enforces state/enum invariants.
  """
  def lifecycle_changeset(%Asset{} = asset, attrs) do
    asset
    |> cast(attrs, [
      :state,
      :assigned_to_id,
      :placed_in_service_on,
      :lost_on,
      :recovered_on,
      :retired_on,
      :disposed_on,
      :disposal_proceeds,
      :disposal_currency,
      :pre_loss_state,
      :pre_repair_state,
      :warranty_end_on,
      :ownership,
      :ownership_acquired_on,
      :purchased_on
    ])
    |> validate_inclusion(:state, @states)
    |> validate_inclusion(:ownership, @ownership_values)
    |> validate_inclusion(:pre_loss_state, @pre_loss_states)
    |> validate_inclusion(:pre_repair_state, @pre_repair_states)
    |> validate_disposal_currency()
    |> foreign_key_constraint(:assigned_to_id)
    |> translate_db_checks()
  end

  defp common_validations(changeset) do
    changeset
    |> update_change(:asset_tag, &normalize_optional_string/1)
    |> update_change(:serial_number, &normalize_optional_string/1)
    |> update_change(:manufacturer, &normalize_optional_string/1)
    |> update_change(:model, &normalize_optional_string/1)
    |> update_change(:vendor, &normalize_optional_string/1)
    |> update_change(:location_detail, &normalize_optional_string/1)
    |> update_change(:acquisition_currency, &normalize_currency/1)
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:location, @locations)
    |> validate_inclusion(:valuation_treatment, @valuation_treatments)
    |> validate_inclusion(:ownership, @ownership_values)
    |> validate_number(:useful_life_months, greater_than: 0)
    |> validate_decimal(:acquisition_cost, :nonneg)
    |> validate_decimal(:salvage_value, :nonneg)
    |> validate_salvage_bounded()
    |> validate_currency(:acquisition_currency)
    |> validate_serial_manufacturer_pair()
    |> validate_document_status()
    |> validate_data_center_location_pair()
    |> foreign_key_constraint(:assigned_to_id)
    |> foreign_key_constraint(:data_center_id)
    |> foreign_key_constraint(:finance_transaction_id)
    |> foreign_key_constraint(:finance_invoice_id)
    |> foreign_key_constraint(:purchase_document_id)
    |> unique_constraint(:asset_tag, name: :assets_asset_tag_index)
    |> unique_constraint(:serial_number, name: :assets_serial_number_index)
    |> translate_db_checks()
  end

  defp translate_db_checks(changeset) do
    changeset
    |> check_constraint(:useful_life_months,
      name: :assets_useful_life_positive,
      message: "must be greater than zero"
    )
    |> check_constraint(:acquisition_cost,
      name: :assets_acquisition_cost_nonneg,
      message: "must be zero or greater"
    )
    |> check_constraint(:salvage_value,
      name: :assets_salvage_nonneg,
      message: "must be zero or greater"
    )
    |> check_constraint(:salvage_value,
      name: :assets_salvage_bounded,
      message: "must be at most acquisition cost"
    )
    |> check_constraint(:manufacturer,
      name: :assets_serial_manufacturer_present,
      message: "is required when a serial number is set"
    )
    |> check_constraint(:disposal_currency,
      name: :assets_disposal_currency_when_proceeds,
      message: "is required when disposal proceeds are set"
    )
    |> check_constraint(:retired_on,
      name: :assets_retired_state_has_date,
      message: "must be set when the asset is retired or disposed"
    )
    |> check_constraint(:disposed_on,
      name: :assets_disposed_state_has_date,
      message: "must be set when the asset is disposed"
    )
    |> check_constraint(:disposed_on,
      name: :assets_disposal_after_retirement,
      message: "must be on or after the retirement date"
    )
    |> check_constraint(:placed_in_service_on,
      name: :assets_in_service_has_place_date,
      message: "is required for an asset that is in service"
    )
    |> check_constraint(:recovered_on,
      name: :assets_recovered_after_lost,
      message: "must be on or after the loss date"
    )
    |> check_constraint(:purchased_on,
      name: :assets_purchased_on_required,
      message: "is required unless the asset is leased"
    )
    |> check_constraint(:ownership,
      name: :assets_ownership_check,
      message: "is not a valid ownership value"
    )
    |> check_constraint(:ownership_acquired_on,
      name: :assets_ownership_acquired_on_iff_owned,
      message: "is required when the asset is owned"
    )
    |> check_constraint(:retired_on,
      name: :assets_retired_on_allowed_states,
      message: "can only be set for retired, disposed, or returned-to-lessor assets"
    )
    |> check_constraint(:data_center_id,
      name: :assets_data_center_iff_location,
      message: "is required when location is data_center and must be null otherwise"
    )
  end

  defp validate_data_center_location_pair(changeset) do
    location = get_field(changeset, :location)
    data_center_id = get_field(changeset, :data_center_id)

    cond do
      location == "data_center" and is_nil(data_center_id) ->
        add_error(changeset, :data_center_id, "is required when location is data_center")

      location != "data_center" and not is_nil(data_center_id) ->
        add_error(changeset, :data_center_id, "must be null when location is not data_center")

      true ->
        changeset
    end
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_currency(nil), do: nil

  defp normalize_currency(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.upcase(trimmed)
    end
  end

  defp validate_decimal(changeset, field, :nonneg) do
    validate_change(changeset, field, fn ^field, value ->
      case value do
        %Decimal{} = decimal ->
          if Decimal.negative?(decimal), do: [{field, "must be zero or greater"}], else: []

        _other ->
          []
      end
    end)
  end

  defp validate_salvage_bounded(changeset) do
    salvage = get_field(changeset, :salvage_value)
    cost = get_field(changeset, :acquisition_cost)

    case {salvage, cost} do
      {%Decimal{} = salvage, %Decimal{} = cost} ->
        if Decimal.compare(salvage, cost) == :gt do
          add_error(changeset, :salvage_value, "must be at most acquisition cost")
        else
          changeset
        end

      _other ->
        changeset
    end
  end

  defp validate_currency(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case value do
        nil ->
          []

        code when is_binary(code) ->
          if valid_currency?(code), do: [], else: [{field, "is not a supported ISO 4217 currency code"}]
      end
    end)
  end

  defp valid_currency?(code) do
    Money.Currency.exists?(code)
  rescue
    _ -> false
  end

  defp validate_disposal_currency(changeset) do
    proceeds = get_field(changeset, :disposal_proceeds)
    currency = get_field(changeset, :disposal_currency)

    cond do
      is_nil(proceeds) -> changeset
      is_nil(currency) -> add_error(changeset, :disposal_currency, "is required when proceeds are set")
      valid_currency?(currency) -> changeset
      true -> add_error(changeset, :disposal_currency, "is not a supported ISO 4217 currency code")
    end
  end

  defp validate_serial_manufacturer_pair(changeset) do
    serial = get_field(changeset, :serial_number)
    manufacturer = get_field(changeset, :manufacturer)

    if is_binary(serial) and is_nil(manufacturer) do
      add_error(changeset, :manufacturer, "is required when a serial number is set")
    else
      changeset
    end
  end

  defp validate_document_status(changeset) do
    case get_change(changeset, :purchase_document_id) do
      nil ->
        changeset

      document_id ->
        case Atlas.Repo.get(Document, document_id) do
          nil ->
            add_error(changeset, :purchase_document_id, "does not exist")

          %Document{status: status} ->
            if status in @accepted_document_statuses do
              changeset
            else
              add_error(
                changeset,
                :purchase_document_id,
                "must reference a completed upload (uploaded/processing/ready)"
              )
            end
        end
    end
  end

  # For a new asset with `ownership = :owned` (the default), the DB check
  # requires `ownership_acquired_on IS NOT NULL`. If the caller did not supply
  # one, snapshot it from `purchased_on` so the record satisfies the invariant
  # without requiring every caller to pass both fields.
  defp maybe_default_ownership_acquired_on(attrs) when is_map(attrs) do
    ownership = fetch_attr(attrs, :ownership) || fetch_attr(attrs, "ownership") || "owned"
    acquired = fetch_attr(attrs, :ownership_acquired_on) || fetch_attr(attrs, "ownership_acquired_on")
    purchased_on = fetch_attr(attrs, :purchased_on) || fetch_attr(attrs, "purchased_on")

    if ownership == "owned" and is_nil(acquired) and not is_nil(purchased_on) do
      put_attr(attrs, :ownership_acquired_on, purchased_on)
    else
      attrs
    end
  end

  defp maybe_default_ownership_acquired_on(attrs), do: attrs

  defp maybe_default_useful_life_months(attrs) when is_map(attrs) do
    category = fetch_attr(attrs, :category) || fetch_attr(attrs, "category")
    supplied = fetch_attr(attrs, :useful_life_months) || fetch_attr(attrs, "useful_life_months")

    case {category, supplied} do
      {nil, _} -> attrs
      {_, value} when not is_nil(value) -> attrs
      {category, nil} -> put_attr(attrs, :useful_life_months, default_useful_life_months(category))
    end
  end

  defp maybe_default_useful_life_months(attrs), do: attrs

  defp fetch_attr(attrs, key) when is_map(attrs) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp put_attr(attrs, key, value) do
    cond do
      Map.has_key?(attrs, key) ->
        Map.put(attrs, key, value)

      Map.has_key?(attrs, to_string(key)) ->
        Map.put(attrs, to_string(key), value)

      match_string_keys?(attrs) ->
        Map.put(attrs, to_string(key), value)

      true ->
        Map.put(attrs, key, value)
    end
  end

  defp match_string_keys?(attrs) do
    Enum.any?(attrs, fn {k, _v} -> is_binary(k) end)
  end
end
