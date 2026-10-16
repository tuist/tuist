defmodule Atlas.Accounts.Account do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account.Address
  alias Atlas.Accounts.Account.Billing
  alias Atlas.Accounts.Account.Signatory
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Accounts.Amounts
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.DealStage
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.IncidentContact
  alias Atlas.Accounts.Invoice
  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.OutcomeProposal
  alias Atlas.Accounts.ServiceLevel
  alias Atlas.Accounts.ServiceLevelExtractionCheck
  alias Atlas.Accounts.Term
  alias Atlas.Documents.Document
  alias Atlas.Letters.Letter
  alias Atlas.Licenses.License
  alias Atlas.Support.Thread, as: SupportThread

  @segments [:customer, :lead, :prospect]
  @statuses ~w(active churned paused trial)
  @license_deal_stages ~w(poc)
  @hosting_values ~w(unknown cloud self_hosted)
  @plan_tiers ~w(enterprise pro free)
  @editable_fields [
    :name,
    :description,
    :primary_domain,
    :url,
    :legal_name,
    :contract_id,
    :status,
    :churned_date,
    :churn_reason,
    :segment,
    :deal_stage,
    :parent_account_id,
    :currency,
    :current_value,
    :next_renewal_date,
    :poc_end_date,
    :stripe_customer_id,
    :hosting,
    :plan_tier
  ]
  def segments, do: @segments
  def statuses, do: @statuses
  def hosting_values, do: @hosting_values
  def plan_tiers, do: @plan_tiers
  def deal_stages, do: DealStage.keys()
  def license_deal_stages, do: @license_deal_stages

  def enterprise?(%__MODULE__{plan_tier: "enterprise"}), do: true
  def enterprise?(_), do: false

  def not_account?(%__MODULE__{not_an_account_at: %DateTime{}}), do: true
  def not_account?(_account), do: false

  # Customers hold licenses because they bought one; accounts running a POC hold one to evaluate Tuist.
  def license_eligible?(%__MODULE__{segment: :customer}), do: true
  def license_eligible?(%__MODULE__{deal_stage: deal_stage}), do: deal_stage in @license_deal_stages
  def license_eligible?(_account), do: false

  schema "accounts" do
    field :account_key, :string
    field :name, :string
    field :description, :string
    field :primary_domain, :string
    field :url, :string
    field :legal_name, :string
    field :contract_id, :string
    field :status, :string
    field :churned_date, :date
    field :churn_reason, :string
    field :segment, Ecto.Enum, values: @segments
    field :deal_stage, :string
    field :currency, :string
    field :current_value, :decimal
    field :next_renewal_date, :date
    field :poc_end_date, :date
    field :stripe_customer_id, :string
    field :hosting, :string, default: "unknown"
    field :plan_tier, :string
    field :overview_summary, :string
    field :overview_summary_generated_at, :utc_datetime
    field :outcome_review_company_slack_posted_at, :utc_datetime
    field :outcome_proposals_checked_at, :utc_datetime
    field :latest_activity_at, :utc_datetime
    field :not_an_account_at, :utc_datetime
    field :not_an_account_reason, :string
    field :contacts_count, :integer, default: 0
    field :metadata, :map, default: %{}
    field :deal_stage_changed_at, :utc_datetime

    belongs_to :parent_account, __MODULE__, foreign_key: :parent_account_id

    embeds_one :address, Address, on_replace: :update
    embeds_one :billing, Billing, on_replace: :update
    embeds_one :signatory, Signatory, on_replace: :update

    has_many :child_accounts, __MODULE__, foreign_key: :parent_account_id
    has_many :contacts, Contact
    has_many :account_handles, AccountHandle
    has_many :invoices, Invoice
    has_many :terms, Term
    has_many :incident_contacts, IncidentContact
    has_many :service_levels, ServiceLevel
    has_many :service_level_extraction_checks, ServiceLevelExtractionCheck
    has_many :events, Event
    has_many :documents, Document
    has_many :outcomes, Outcome
    has_many :outcome_proposals, OutcomeProposal
    has_many :licenses, License
    has_many :letters, Letter
    has_many :support_threads, SupportThread

    timestamps()
  end

  def changeset(account, attrs) do
    attrs = normalize_parent_account_id_attr(attrs)

    account
    |> cast(attrs, [
      :account_key,
      :name,
      :description,
      :primary_domain,
      :url,
      :legal_name,
      :contract_id,
      :status,
      :churned_date,
      :churn_reason,
      :segment,
      :deal_stage,
      :parent_account_id,
      :currency,
      :current_value,
      :next_renewal_date,
      :poc_end_date,
      :stripe_customer_id,
      :hosting,
      :plan_tier,
      :latest_activity_at,
      :contacts_count,
      :metadata
    ])
    |> validate_required([:account_key, :name, :segment])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:hosting, @hosting_values)
    |> validate_inclusion(:plan_tier, @plan_tiers)
    |> validate_inclusion(:deal_stage, DealStage.keys())
    |> validate_parent_account_not_self()
    |> update_change(:currency, &Amounts.normalize_currency/1)
    |> stamp_deal_stage_changed_at()
    |> cast_embed(:address, with: &Address.changeset/2)
    |> cast_embed(:billing, with: &Billing.changeset/2)
    |> cast_embed(:signatory, with: &Signatory.changeset/2)
    |> update_change(:name, &String.trim/1)
    |> unique_constraint(:account_key)
    |> foreign_key_constraint(:parent_account_id)
    |> check_constraint(:parent_account_id,
      name: :accounts_parent_account_not_self,
      message: "can't be the same account"
    )
  end

  def manual_changeset(account, attrs) do
    account
    |> edit_changeset(attrs)
    |> validate_required([:account_key])
    |> unique_constraint(:account_key)
  end

  def edit_changeset(account, attrs) do
    attrs = normalize_parent_account_id_attr(attrs)

    account
    |> cast(attrs, @editable_fields)
    |> clear_deal_stage_sentinel()
    |> normalize_optional_string_field(:deal_stage)
    |> validate_required([:name, :segment])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:hosting, @hosting_values)
    |> validate_inclusion(:plan_tier, @plan_tiers)
    |> validate_inclusion(:deal_stage, DealStage.keys())
    |> validate_parent_account_not_self()
    |> validate_number(:current_value, greater_than_or_equal_to: 0)
    |> update_change(:name, &String.trim/1)
    |> update_change(:currency, &Amounts.normalize_currency/1)
    |> normalize_optional_string_fields()
    |> stamp_deal_stage_changed_at()
    |> cast_embed(:address, with: &Address.changeset/2)
    |> cast_embed(:billing, with: &Billing.changeset/2)
    |> cast_embed(:signatory, with: &Signatory.changeset/2)
    |> foreign_key_constraint(:parent_account_id)
    |> check_constraint(:parent_account_id,
      name: :accounts_parent_account_not_self,
      message: "can't be the same account"
    )
  end

  @doc """
  Dedicated changeset for outcome review workers. This field is not user-editable.
  """
  def outcome_review_changeset(account, attrs) do
    account
    |> cast(attrs, [:outcome_review_company_slack_posted_at])
  end

  @doc """
  Records when the proposal agent last evaluated an account. This field is not
  user-editable.
  """
  def outcome_proposals_checked_changeset(account, attrs) do
    cast(account, attrs, [:outcome_proposals_checked_at])
  end

  @doc """
  Marks a persisted account row as a non-account so its identifiers remain
  available to block future automated account creation.
  """
  def not_account_changeset(account, attrs, now \\ utc_now()) do
    reason =
      attrs
      |> not_account_reason_attr()
      |> normalize_optional_string_value()

    change(account, %{
      not_an_account_at: account.not_an_account_at || DateTime.truncate(now, :second),
      not_an_account_reason: reason
    })
  end

  defp normalize_optional_string_fields(changeset) do
    Enum.reduce(
      [
        :description,
        :primary_domain,
        :url,
        :legal_name,
        :contract_id,
        :churn_reason,
        :stripe_customer_id
      ],
      changeset,
      fn field, changeset -> normalize_optional_string_field(changeset, field) end
    )
  end

  defp normalize_optional_string_field(changeset, field) do
    update_change(changeset, field, fn
      nil ->
        nil

      value ->
        normalize_optional_string_value(value)
    end)
  end

  defp not_account_reason_attr(attrs) when is_map(attrs) do
    Enum.find_value(["reason", :reason, "not_an_account_reason", :not_an_account_reason], &Map.get(attrs, &1))
  end

  defp not_account_reason_attr(_attrs), do: nil

  defp normalize_optional_string_value(nil), do: nil

  defp normalize_optional_string_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string_value(_value), do: nil

  defp clear_deal_stage_sentinel(changeset) do
    update_change(changeset, :deal_stage, fn
      "_none" -> nil
      value -> value
    end)
  end

  defp normalize_parent_account_id_attr(attrs) when is_map(attrs) do
    attrs
    |> normalize_parent_account_id_key("parent_account_id")
    |> normalize_parent_account_id_key(:parent_account_id)
  end

  defp normalize_parent_account_id_key(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} when value in ["", "_none"] -> Map.put(attrs, key, nil)
      _other -> attrs
    end
  end

  defp validate_parent_account_not_self(changeset) do
    account_id = get_field(changeset, :id)
    parent_account_id = get_field(changeset, :parent_account_id)

    if account_id && parent_account_id == account_id do
      add_error(changeset, :parent_account_id, "can't be the same account")
    else
      changeset
    end
  end

  defp stamp_deal_stage_changed_at(changeset) do
    case fetch_change(changeset, :deal_stage) do
      :error -> changeset
      {:ok, _new_stage} -> put_change(changeset, :deal_stage_changed_at, utc_now())
    end
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
