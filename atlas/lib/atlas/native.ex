defmodule Atlas.Native do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Finance.Invoice
  alias Atlas.Finance.Invoices
  alias Atlas.Native.AccountDetails
  alias Atlas.Native.FinanceOverview
  alias Atlas.Repo
  alias Atlas.Tasks.Task
  alias Atlas.Users
  alias Atlas.Users.User

  @task_fields ~w(title description status assignee_id account_id due_on remind_at)a
  @account_fields ~w(name description primary_domain segment status deal_stage currency current_value next_renewal_date legal_name url hosting plan_tier)a

  def can_write?("tasks", %User{}), do: true
  def can_write?("accounts", user), do: Users.has_scope?(user, "accounts:write")
  def can_write?("invoices", user), do: Users.has_scope?(user, "finance:write")

  def fields("tasks"), do: @task_fields -- [:status]
  def fields("accounts"), do: @account_fields
  def fields("invoices"), do: Invoice.manual_fields()

  def list(resource, params, user) do
    now = DateTime.utc_now()

    with :ok <- validate_query(params["query"]),
         :ok <- validate_filters(resource, params),
         {:ok, flop} <-
           Flop.validate(%{"page" => Map.get(params, "page", 1), "page_size" => 25}, pagination_types: [:page]) do
      {items, meta} =
        resource
        |> query()
        |> search(params["query"], resource)
        |> filter(resource, params, now)
        |> group(resource, params["group_by"], now)
        |> Flop.run(flop)

      {:ok,
       %{
         items: Enum.map(items, &record(resource, &1, user, now)),
         page: meta.current_page,
         total_pages: max(meta.total_pages || 0, 1),
         total_count: meta.total_count,
         can_write: can_write?(resource, user),
         options: options(resource),
         summary: if(resource == "invoices", do: Invoices.monthly_invoice_totals(), else: []),
         finance_overview: if(resource == "invoices" and flop.page == 1, do: FinanceOverview.get())
       }}
    else
      _error -> {:error, :invalid_params}
    end
  end

  def get(resource, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = item <- Repo.get(query(resource), id) do
      {:ok, item}
    else
      _missing -> {:error, :not_found}
    end
  end

  def detail(resource, item, user) do
    record = record(resource, item, user)
    if resource == "accounts", do: Map.put(record, :details, AccountDetails.get(item, user)), else: record
  end

  def record(resource, item, user, now \\ DateTime.utc_now())

  def record("tasks", task, user, now) do
    task = Repo.preload(task, [:assignee, :account])

    values =
      task
      |> values(@task_fields)
      |> Map.put(:assignee_name, association_name(task.assignee))
      |> Map.put(:account_name, association_name(task.account))
      |> Map.put(:reminder_group, reminder_group(task, now))

    item(task.id, values, can_write?("tasks", user))
  end

  def record("accounts", account, user, _now) do
    account = Repo.preload(account, :terms)
    {value, currency} = Accounts.contract_value(account)

    fields =
      account
      |> values(@account_fields ++ [:contacts_count, :poc_end_date])
      |> Map.put(:contract_value, string(value))
      |> Map.put(:contract_currency, string(currency))

    item(account.id, fields, can_write?("accounts", user))
  end

  def record("invoices", invoice, user, _now) do
    item(
      invoice.id,
      values(invoice, Invoice.manual_fields()),
      can_write?("invoices", user) and Invoices.manual?(invoice)
    )
  end

  defp item(id, fields, writable), do: %{id: id, fields: fields, can_edit: writable, can_delete: writable}

  defp query("tasks"),
    do: from(task in Task, order_by: [desc: task.inserted_at, desc: task.id], preload: [:assignee, :account])

  defp query("accounts"),
    do:
      from(account in Account,
        where: is_nil(account.not_an_account_at),
        order_by: [asc: account.name, asc: account.id],
        preload: [:terms]
      )

  defp query("invoices"),
    do: from(invoice in Invoice, order_by: [desc_nulls_last: invoice.invoice_date, desc: invoice.id])

  defp search(query, value, resource) when is_binary(value) and value != "" do
    pattern =
      "%#{value |> String.trim() |> String.replace("\\", "\\\\") |> String.replace("%", "\\%") |> String.replace("_", "\\_")}%"

    fields =
      case resource do
        "tasks" -> [:title, :description]
        "accounts" -> [:name, :description, :primary_domain]
        "invoices" -> [:vendor_name, :invoice_number]
      end

    condition =
      Enum.reduce(fields, dynamic(false), fn key, condition ->
        dynamic([item], ^condition or ilike(field(item, ^key), ^pattern))
      end)

    where(query, ^condition)
  end

  defp search(query, _value, _resource), do: query

  defp filter_options("tasks"),
    do: [status: ~w(open completed), assignee_id: :uuid, reminder: ~w(overdue upcoming none), group_by: ~w(reminder)]

  defp filter_options("accounts"),
    do: [
      segment: Enum.map(Account.segments(), &to_string/1),
      status: Account.statuses(),
      deal_stage: Account.deal_stages()
    ]

  defp filter_options("invoices"), do: [status: Invoice.statuses()]

  defp validate_filters(resource, params) do
    options = Map.new(filter_options(resource), fn {key, values} -> {to_string(key), values} end)

    valid? =
      params
      |> Map.drop(["page", "query"])
      |> Enum.all?(fn {key, value} ->
        case Map.fetch(options, key) do
          {:ok, values} when is_binary(value) ->
            value == "" or if(values == :uuid, do: match?({:ok, _}, Ecto.UUID.cast(value)), else: value in values)

          _invalid ->
            false
        end
      end)

    if valid?, do: :ok, else: {:error, :invalid_params}
  end

  defp filter(query, resource, params, now) do
    Enum.reduce(filter_options(resource), query, fn {key, _values}, query ->
      filter_value(query, key, params[to_string(key)], now)
    end)
  end

  defp filter_value(query, _key, value, _now) when value in [nil, ""], do: query
  defp filter_value(query, :group_by, _value, _now), do: query

  defp filter_value(query, :reminder, "overdue", now),
    do: where(query, [task], task.status == "open" and task.remind_at <= ^now)

  defp filter_value(query, :reminder, "upcoming", now),
    do: where(query, [task], task.status == "open" and task.remind_at > ^now)

  defp filter_value(query, :reminder, "none", _now),
    do: where(query, [task], task.status == "open" and is_nil(task.remind_at))

  defp filter_value(query, key, value, _now), do: where(query, [item], field(item, ^key) == ^value)

  defp group(query, "tasks", "reminder", now) do
    query
    |> exclude(:order_by)
    |> order_by([task],
      asc:
        fragment(
          "CASE WHEN ? = 'completed' THEN 3 WHEN ? <= ? THEN 0 WHEN ? > ? THEN 1 ELSE 2 END",
          task.status,
          task.remind_at,
          ^now,
          task.remind_at,
          ^now
        ),
      asc_nulls_last: task.remind_at,
      asc: task.id
    )
  end

  defp group(query, _resource, _group_by, _now), do: query

  defp reminder_group(%Task{status: "completed"}, _now), do: "completed"
  defp reminder_group(%Task{remind_at: nil}, _now), do: "none"
  defp reminder_group(task, now), do: if(DateTime.after?(task.remind_at, now), do: "upcoming", else: "overdue")

  defp options(resource) do
    %{
      users:
        if(resource == "tasks",
          do:
            Repo.all(
              from user in User,
                order_by: [asc: user.name, asc: user.id],
                select: %{id: user.id, name: fragment("coalesce(?, '')", user.name)}
            ),
          else: []
        ),
      accounts:
        if(resource == "tasks",
          do:
            Repo.all(
              from account in Account,
                where: is_nil(account.not_an_account_at),
                order_by: [asc: account.name, asc: account.id],
                select: %{id: account.id, name: account.name}
            ),
          else: []
        ),
      segments: if(resource == "accounts", do: Enum.map(Account.segments(), &to_string/1), else: []),
      statuses: statuses(resource),
      deal_stages: if(resource == "accounts", do: Account.deal_stages(), else: [])
    }
  end

  defp statuses("accounts"), do: Account.statuses()
  defp statuses("invoices"), do: Invoice.statuses()
  defp statuses("tasks"), do: []

  defp values(item, fields), do: Map.new(fields, &{&1, string(Map.get(item, &1))})
  defp string(nil), do: ""
  defp string(%Date{} = value), do: Date.to_iso8601(value)
  defp string(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp string(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp string(value), do: to_string(value)
  defp association_name(nil), do: ""
  defp association_name(item), do: item.name || ""
  defp validate_query(value) when is_binary(value) or is_nil(value), do: :ok
  defp validate_query(_value), do: {:error, :invalid_params}
end
