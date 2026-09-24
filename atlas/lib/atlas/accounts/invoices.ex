defmodule Atlas.Accounts.Invoices do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Amounts
  alias Atlas.Accounts.ExchangeRates
  alias Atlas.Accounts.Invoice
  alias Atlas.Accounts.InvoicePaidNotifier
  alias Atlas.Accounts.OrderForms
  alias Atlas.Accounts.StripeCustomers
  alias Atlas.Audit
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.Repo
  alias Atlas.Stripe

  require Logger

  @stripe_invoice_reconciliation_limit 100
  @sales_overview_invoice_limit 25
  @outstanding_summary_limit 100
  @sales_overview_displayed_statuses ~w(open draft)
  @order_form_scan_limit 50
  @default_invoice_days_until_due 30
  @enterprise_product_name "Tuist Enterprise"
  @invoice_amount_keys ~w(invoice_amount total_amount total amount annual_amount annual_subscription subscription_amount subscription_total contract_value order_total)
  @invoice_currency_keys ~w(invoice_currency amount_currency currency)
  @invoice_line_item_keys ~w(invoice_line_items line_items items)
  @payment_terms_keys ~w(days_until_due payment_terms_days net_terms payment_terms)
  @period_start_keys ~w(period_start service_period_start start_date effective_date)
  @period_end_keys ~w(period_end service_period_end end_date renewal_date)
  @seat_count_keys ~w(seats seat_count number_of_seats quantity users user_count licenses license_count)

  # Bank-transfer footer printed at the bottom of every Stripe invoice.
  # Configured at runtime via ATLAS_INVOICE_FOOTER so real beneficiary and
  # account details stay out of source. See config/runtime.exs.
  defp invoice_footer, do: Application.get_env(:atlas, :invoice_footer, "")

  @doc """
  Fetches a page of Stripe invoices for the sales overview: open invoices and
  draft (scheduled) invoices, both with a non-zero balance.

  Supports cursor pagination via Stripe's `starting_after` / `ending_before`.
  Pass `:after` (id) to advance to the next page or `:before` (id) to go back.

  Each invoice is enriched with the matching Atlas account when one exists, via
  the account `stripe_customer_id`. Returns
  `{[%{invoice: invoice, account: account}], meta}` where `meta` carries the
  cursor info needed to render Prev/Next controls. Returns an empty list and
  empty meta when Stripe is disabled or the upstream call fails so the page
  renders gracefully.
  """
  def sales_overview_invoices(opts \\ []) do
    limit = Keyword.get(opts, :limit, @sales_overview_invoice_limit)
    after_cursor = cursor_value(Keyword.get(opts, :after))
    before_cursor = if !after_cursor, do: cursor_value(Keyword.get(opts, :before))

    client = stripe_client(opts)

    case client.list_invoices_page(
           limit: limit,
           status: "open",
           after: after_cursor,
           before: before_cursor,
           fixture_key: Keyword.get(opts, :stripe_fixture)
         ) do
      {:ok, %{invoices: stripe_invoices, has_more: has_more}} ->
        rows =
          stripe_invoices
          |> Enum.filter(&displayed_in_overview?/1)
          |> attach_accounts()
          |> Enum.sort(&compare_overview_invoices/2)

        meta = build_overview_meta(stripe_invoices, has_more, after_cursor, before_cursor)
        {rows, meta}

      _other ->
        {[], empty_overview_meta()}
    end
  end

  defp displayed_in_overview?(%Stripe.Invoice{status: status} = invoice)
       when status in @sales_overview_displayed_statuses, do: positive_amount?(invoice)

  defp displayed_in_overview?(_invoice), do: false

  defp cursor_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      cursor -> cursor
    end
  end

  defp cursor_value(_value), do: nil

  defp build_overview_meta([], _has_more, after_cursor, before_cursor) do
    %{
      has_next_page?: false,
      has_previous_page?: not is_nil(after_cursor) or not is_nil(before_cursor),
      start_cursor: nil,
      end_cursor: nil
    }
  end

  defp build_overview_meta(stripe_invoices, has_more, after_cursor, before_cursor) do
    %{
      has_next_page?: has_next_page?(has_more, after_cursor, before_cursor),
      has_previous_page?: has_previous_page?(has_more, after_cursor, before_cursor),
      start_cursor: stripe_invoices |> List.first() |> Map.get(:id),
      end_cursor: stripe_invoices |> List.last() |> Map.get(:id)
    }
  end

  defp empty_overview_meta do
    %{has_next_page?: false, has_previous_page?: false, start_cursor: nil, end_cursor: nil}
  end

  defp has_next_page?(_has_more, nil, before_cursor) when not is_nil(before_cursor), do: true
  defp has_next_page?(has_more, _after, _before), do: has_more

  defp has_previous_page?(_has_more, after_cursor, nil) when not is_nil(after_cursor), do: true
  defp has_previous_page?(has_more, nil, before_cursor) when not is_nil(before_cursor), do: has_more
  defp has_previous_page?(_has_more, _after, _before), do: false

  defp list_stripe_invoices_by_status(status, opts) do
    client = stripe_client(opts)

    case client.list_invoices_by_status(status, client_opts(opts)) do
      {:ok, invoices} -> invoices
      _other -> []
    end
  end

  @doc """
  Aggregates outstanding (open, non-zero) Stripe invoices into a single EUR
  total along with counts. USD/other-currency amounts are converted using the
  same ECB reference rates as `revenue_snapshot/0`. Returns zeroed totals when
  Stripe is disabled or the upstream call fails.
  """
  def outstanding_invoices_summary(today \\ Date.utc_today()) do
    invoices =
      list_stripe_invoices_by_status("open", limit: @outstanding_summary_limit)
      |> Enum.filter(&positive_amount?/1)

    exchange_rates = load_exchange_rates(invoices)
    build_outstanding_summary(invoices, exchange_rates, today)
  end

  defp load_exchange_rates(invoices) do
    currencies =
      invoices
      |> Enum.map(& &1.amount_currency)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&String.upcase/1)
      |> Enum.reject(&(&1 == "EUR"))
      |> Enum.uniq()

    case currencies do
      [] ->
        %{published_on: nil, rates: %{}}

      currencies ->
        client = exchange_rates_client()

        case client.latest_rates(currencies) do
          {:ok, rates} ->
            rates

          {:error, reason} ->
            Logger.warning("Failed to load ECB exchange rates for outstanding invoices: #{inspect(reason)}")
            %{published_on: nil, rates: %{}}
        end
    end
  end

  defp build_outstanding_summary(invoices, exchange_rates, today) do
    {total_eur, count, overdue_count} =
      Enum.reduce(invoices, {Decimal.new(0), 0, 0}, fn invoice, {sum, count, overdue} ->
        sum = maybe_add_eur(sum, invoice, exchange_rates)
        overdue = overdue + if invoice_overdue?(invoice, today), do: 1, else: 0
        {sum, count + 1, overdue}
      end)

    %{
      total_eur: Decimal.round(total_eur, 2),
      count: count,
      overdue_count: overdue_count,
      published_on: exchange_rates.published_on
    }
  end

  defp maybe_add_eur(sum, %Stripe.Invoice{amount_value: %Decimal{} = value, amount_currency: currency}, exchange_rates)
       when is_binary(currency) do
    case convert_to_eur(value, currency, exchange_rates) do
      {:ok, eur_value} -> Decimal.add(sum, eur_value)
      :skip -> sum
    end
  end

  defp maybe_add_eur(sum, _invoice, _exchange_rates), do: sum

  defp convert_to_eur(value, currency, exchange_rates) do
    case String.upcase(currency) do
      "EUR" ->
        {:ok, value}

      code ->
        case Map.get(exchange_rates.rates, code) do
          %Decimal{} = rate -> {:ok, Decimal.div(value, rate)}
          _missing -> :skip
        end
    end
  end

  defp invoice_overdue?(%Stripe.Invoice{due_date: %Date{} = due_date}, today), do: Date.before?(due_date, today)

  defp invoice_overdue?(_invoice, _today), do: false

  defp positive_amount?(%Stripe.Invoice{amount_value: %Decimal{} = amount}),
    do: Decimal.compare(amount, Decimal.new(0)) == :gt

  defp positive_amount?(%{amount_value: %Decimal{} = amount}), do: Decimal.compare(amount, Decimal.new(0)) == :gt

  defp positive_amount?(_invoice), do: false

  defp attach_accounts([]), do: []

  defp attach_accounts(invoices) do
    customer_ids =
      invoices
      |> Enum.map(& &1.customer_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    accounts_by_customer =
      case customer_ids do
        [] ->
          %{}

        ids ->
          from(a in Account, where: a.stripe_customer_id in ^ids, select: {a.stripe_customer_id, a})
          |> Repo.all()
          |> Map.new()
      end

    Enum.map(invoices, fn invoice ->
      %{invoice: invoice, account: Map.get(accounts_by_customer, invoice.customer_id)}
    end)
  end

  defp compare_overview_invoices(%{invoice: a}, %{invoice: b}) do
    {status_rank(a.status), nil_last(a.due_date), neg_amount(a.amount_value)} <=
      {status_rank(b.status), nil_last(b.due_date), neg_amount(b.amount_value)}
  end

  defp status_rank("open"), do: 0
  defp status_rank("draft"), do: 1
  defp status_rank(_), do: 2

  defp nil_last(nil), do: {1, nil}
  defp nil_last(%Date{} = date), do: {0, Date.to_iso8601(date)}

  defp neg_amount(nil), do: 0
  defp neg_amount(%Decimal{} = amount), do: Decimal.negate(amount) |> Decimal.to_float()

  def upcoming_invoices(%Account{invoices: invoices}, today \\ Date.utc_today()) when is_list(invoices) do
    invoices
    |> Enum.filter(&upcoming_invoice?(&1, today))
    |> Enum.sort(&compare_invoice_dates_asc/2)
  end

  def reconciled_stripe_invoices(%Account{invoices: invoices}) when is_list(invoices) do
    invoices
    |> Enum.filter(&(&1.source == "stripe" and positive_amount?(&1)))
    |> Enum.sort(&compare_invoice_dates_desc/2)
  end

  @doc """
  Fetches invoices for the account from Stripe.

  Returns `{:ok, invoices}` when Stripe is reachable, `{:error, reason}` on
  upstream/transport failures, and `:disabled` when the account has no
  `stripe_customer_id` or no Stripe API key is configured.
  """
  def stripe_invoices(account, opts \\ [])

  def stripe_invoices(%Account{stripe_customer_id: nil}, _opts), do: :disabled

  def stripe_invoices(%Account{stripe_customer_id: customer_id}, opts) when is_binary(customer_id) do
    customer_id = String.trim(customer_id)

    if customer_id == "" do
      :disabled
    else
      client = stripe_client(opts)
      client.list_invoices(customer_id, client_opts(opts))
    end
  end

  @doc """
  Creates a Stripe draft invoice for an account from its most recent signed
  order form.

  The Stripe invoice remains a draft. Atlas never finalizes or sends it from
  this path.

  Pass `line_items: [%{description, amount, currency, ...}, ...]` in `opts` to
  bypass auto-extraction when the caller (typically the Slack agent) already
  has the values in hand. The latest signed order form is still resolved and
  linked as the source document.
  """
  def create_stripe_draft_invoice_from_latest_signed_order_form(account_or_id, opts \\ [])

  def create_stripe_draft_invoice_from_latest_signed_order_form(account_id, opts) when is_binary(account_id) do
    case Repo.get(Account, account_id) do
      nil -> {:error, :not_found}
      account -> create_stripe_draft_invoice_from_latest_signed_order_form(account, opts)
    end
  end

  def create_stripe_draft_invoice_from_latest_signed_order_form(%Account{} = account, opts) do
    with {:ok, document} <- latest_signed_order_form(account, opts),
         {:ok, %{account: account, customer: customer, status: customer_status}} <-
           ensure_stripe_customer(account, document, opts),
         {:ok, customer_id} <- stripe_customer_id(account),
         {:ok, draft_attrs} <- draft_invoice_attrs(account, document, opts),
         {:ok, stripe_invoice} <- create_stripe_draft_invoice(customer_id, draft_attrs, opts),
         {:ok, stored_invoice} <- upsert_stripe_invoice(account, stripe_invoice) do
      result = %{
        account: account,
        source_document: document,
        draft_invoice: stored_invoice,
        stripe_invoice: stripe_invoice,
        line_items: draft_attrs.line_items,
        days_until_due: draft_attrs.days_until_due,
        stripe_customer: customer,
        stripe_customer_status: customer_status
      }

      audit_draft_invoice("account_invoice.stripe_draft_created", result)
      {:ok, result}
    end
  end

  defp ensure_stripe_customer(%Account{} = account, %Document{} = document, opts) do
    billing_email = OrderForms.billing_email(document)
    billing_address = OrderForms.billing_address(document)

    opts =
      if is_binary(billing_email) do
        Keyword.put(opts, :billing_email, billing_email)
      else
        opts
      end

    opts =
      if is_map(billing_address) do
        Keyword.put(opts, :billing_address, billing_address)
      else
        opts
      end

    StripeCustomers.find_or_create_for_account(account, opts)
  end

  @doc """
  Edits an existing Stripe draft invoice for an account.

  By default re-extracts line items from the account's most recent signed
  order form and attaches them to the invoice (useful when an earlier
  `create_stripe_draft_invoice_from_latest_signed_order_form/2` failed to
  attach them). Also accepts optional invoice fields the caller wants to
  update on Stripe: `:description`, `:footer`, `:days_until_due`, `:metadata`
  (merged keywise on Stripe's side).

  Pass `attach_order_form_line_items: false` to skip the order-form lookup
  and just update invoice fields. Pass `line_items: [...]` to attach
  caller-supplied line items instead of running auto-extraction (used when
  the order form lives on pages the extractor does not scan).
  """
  @invoice_edit_keys [:description, :footer, :days_until_due, :metadata]

  def edit_stripe_draft_invoice(account_or_id, invoice_id, edit_attrs \\ %{}, opts \\ [])

  def edit_stripe_draft_invoice(account_id, invoice_id, edit_attrs, opts) when is_binary(account_id) do
    case Repo.get(Account, account_id) do
      nil -> {:error, :not_found}
      account -> edit_stripe_draft_invoice(account, invoice_id, edit_attrs, opts)
    end
  end

  def edit_stripe_draft_invoice(%Account{} = account, invoice_id, edit_attrs, opts)
      when is_binary(invoice_id) and is_map(edit_attrs) do
    explicit_items = Map.get(edit_attrs, :line_items)
    attach_line_items? = Map.get(edit_attrs, :attach_order_form_line_items, true)
    update_attrs = Map.take(edit_attrs, @invoice_edit_keys)

    with {:ok, document, line_items} <-
           resolve_edit_line_items(account, explicit_items, attach_line_items?, opts),
         :ok <- maybe_update_stripe_invoice(invoice_id, update_attrs, opts),
         {:ok, stripe_invoice} <- attach_or_retrieve_invoice(invoice_id, line_items, opts),
         {:ok, stored_invoice} <- upsert_stripe_invoice(account, stripe_invoice) do
      result = %{
        account: account,
        source_document: document,
        draft_invoice: stored_invoice,
        stripe_invoice: stripe_invoice,
        line_items: line_items,
        updated_invoice_fields: Map.keys(update_attrs)
      }

      audit_draft_invoice("account_invoice.stripe_draft_updated", result)
      {:ok, result}
    end
  end

  defp resolve_edit_line_items(_account, items, _attach?, _opts) when is_list(items) and items != [] do
    with {:ok, parsed} <- explicit_line_items(items), do: {:ok, nil, parsed}
  end

  defp resolve_edit_line_items(account, _items, attach?, opts), do: load_order_form_line_items(account, attach?, opts)

  defp load_order_form_line_items(_account, false, _opts), do: {:ok, nil, []}

  defp load_order_form_line_items(account, true, opts) do
    with {:ok, document} <- latest_signed_order_form(account, opts),
         {:ok, draft_attrs} <- draft_invoice_attrs(account, document, opts) do
      {:ok, document, draft_attrs.line_items}
    end
  end

  defp maybe_update_stripe_invoice(_invoice_id, attrs, _opts) when map_size(attrs) == 0, do: :ok

  defp maybe_update_stripe_invoice(invoice_id, attrs, opts) do
    opts
    |> stripe_client()
    |> case do
      client -> client.update_invoice(invoice_id, attrs, client_opts(opts))
    end
    |> case do
      {:ok, %Stripe.Invoice{}} -> :ok
      :disabled -> {:error, :stripe_disabled}
      {:error, reason} -> {:error, reason}
    end
  end

  defp attach_or_retrieve_invoice(invoice_id, [], opts), do: get_stripe_invoice(invoice_id, opts)

  defp attach_or_retrieve_invoice(invoice_id, line_items, opts),
    do: add_stripe_invoice_items(invoice_id, line_items, opts)

  defp get_stripe_invoice(invoice_id, opts) do
    opts
    |> stripe_client()
    |> case do
      client -> client.get_invoice(invoice_id, client_opts(opts))
    end
    |> case do
      {:ok, %Stripe.Invoice{} = invoice} -> {:ok, invoice}
      :disabled -> {:error, :stripe_disabled}
      {:error, reason} -> {:error, reason}
    end
  end

  def reconcile_stripe_invoices(account_id) when is_binary(account_id) do
    case Repo.get(Account, account_id) do
      nil -> {:error, :not_found}
      account -> reconcile_stripe_invoices(account)
    end
  end

  def reconcile_stripe_invoices(%Account{} = account) do
    case stripe_invoices(account, limit: @stripe_invoice_reconciliation_limit) do
      {:ok, stripe_invoices} ->
        with {:ok, count} <- upsert_stripe_invoices(account, stripe_invoices) do
          result = %{account_id: account.id, invoices: count}

          Audit.record("account_invoice.stripe_reconciled", %{
            target_type: "account",
            target_id: account.id,
            target_label: account.name,
            metadata: %{
              "path" => "/commercial/sales/accounts/#{account.id}",
              "invoice_count" => count
            }
          })

          {:ok, result}
        end

      other ->
        other
    end
  end

  defp upcoming_invoice?(%{due_date: nil}, _today), do: true
  defp upcoming_invoice?(%{due_date: %Date{} = date}, today), do: Date.compare(date, today) in [:eq, :gt]

  defp compare_invoice_dates_asc(%{due_date: nil}, %{due_date: nil}), do: true
  defp compare_invoice_dates_asc(%{due_date: nil}, _), do: false
  defp compare_invoice_dates_asc(_, %{due_date: nil}), do: true
  defp compare_invoice_dates_asc(%{due_date: a}, %{due_date: b}), do: Date.compare(a, b) != :gt

  defp compare_invoice_dates_desc(%{due_date: nil}, _), do: true
  defp compare_invoice_dates_desc(_, %{due_date: nil}), do: false
  defp compare_invoice_dates_desc(%{due_date: a}, %{due_date: b}), do: Date.compare(a, b) != :lt

  defp upsert_stripe_invoices(account, stripe_invoices) do
    count =
      Enum.reduce(stripe_invoices, 0, fn stripe_invoice, count ->
        case upsert_stripe_invoice(account, stripe_invoice) do
          {:ok, _invoice} ->
            count + 1

          {:error, changeset} ->
            Logger.warning(
              "Skipping Stripe invoice #{inspect(stripe_invoice.id)} for account #{account.id}: #{inspect(changeset.errors)}"
            )

            count
        end
      end)

    {:ok, count}
  end

  def upsert_stripe_invoice(account, %Stripe.Invoice{} = stripe_invoice) do
    prior_status = existing_invoice_status(stripe_invoice.id)

    result =
      %Invoice{account_id: account.id}
      |> Invoice.changeset(stripe_invoice_attrs(stripe_invoice))
      |> Repo.insert(
        on_conflict:
          {:replace,
           [
             :account_id,
             :number,
             :due_date,
             :amount_value,
             :amount_currency,
             :status,
             :stripe_url,
             :updated_at
           ]},
        conflict_target: [:source, :external_id]
      )

    with {:ok, %Invoice{} = invoice} <- result do
      maybe_notify_paid(account, invoice, prior_status)
    end

    result
  end

  defp existing_invoice_status(external_id) when is_binary(external_id) do
    case Repo.get_by(Invoice, source: "stripe", external_id: external_id) do
      nil -> :new
      %Invoice{status: status} -> status
    end
  end

  defp existing_invoice_status(_external_id), do: :new

  defp maybe_notify_paid(%Account{} = account, %Invoice{status: "paid"} = invoice, prior_status)
       when is_binary(prior_status) and prior_status != "paid" do
    InvoicePaidNotifier.notify(account, invoice)
  end

  defp maybe_notify_paid(_account, _invoice, _prior_status), do: :ok

  defp audit_draft_invoice(action, result) do
    account = result.account
    invoice = result.draft_invoice

    Audit.record(action, %{
      target_type: "account_invoice",
      target_id: invoice.id,
      target_label: invoice.number || invoice.external_id,
      metadata: %{
        "path" => "/commercial/sales/accounts/#{account.id}",
        "account_id" => account.id,
        "stripe_invoice_id" => invoice.external_id,
        "source_document_id" => result.source_document && result.source_document.id,
        "line_item_count" => length(result.line_items),
        "updated_fields" => Enum.map(Map.get(result, :updated_invoice_fields, []), &Atom.to_string/1),
        "amount" => invoice.amount_value,
        "currency" => invoice.amount_currency,
        "status" => invoice.status
      }
    })
  end

  defp stripe_invoice_attrs(%Stripe.Invoice{} = stripe_invoice) do
    %{
      external_id: stripe_invoice.id,
      source: "stripe",
      number: stripe_invoice.number,
      due_date: stripe_invoice.due_date,
      amount_value: stripe_invoice.amount_value,
      amount_currency: stripe_invoice.amount_currency,
      status: stripe_invoice.status,
      stripe_url: stripe_invoice.hosted_url || stripe_invoice.pdf_url || stripe_invoice.dashboard_url
    }
  end

  defp stripe_customer_id(%Account{stripe_customer_id: customer_id}) when is_binary(customer_id) do
    case String.trim(customer_id) do
      "" -> {:error, :missing_stripe_customer_id}
      customer_id -> {:ok, customer_id}
    end
  end

  defp stripe_customer_id(_account), do: {:error, :missing_stripe_customer_id}

  defp latest_signed_order_form(%Account{id: account_id}, opts) do
    limit = Keyword.get(opts, :document_scan_limit, @order_form_scan_limit)

    documents =
      Document
      |> where([document], document.account_id == ^account_id)
      |> where([document], document.status == "ready")
      |> order_by([document], desc_nulls_last: document.document_date, desc: document.inserted_at, desc: document.id)
      |> limit(^limit)
      |> preload([:document_type, :tags, pages: ^pages_query()])
      |> Repo.all()

    case Enum.find(documents, &signed_order_form?/1) do
      nil -> {:error, :signed_order_form_not_found}
      document -> {:ok, document}
    end
  end

  defp pages_query, do: from(page in DocumentPage, order_by: [asc: page.page_number])

  defp signed_order_form?(%Document{} = document), do: OrderForms.signed?(document)

  defp line_items_currency([%{currency: currency} | _]), do: currency
  defp line_items_currency(_line_items), do: nil

  defp draft_invoice_attrs(%Account{} = account, %Document{} = document, opts) do
    with {:ok, line_items} <- invoice_line_items(account, document, opts) do
      idempotency_key = draft_invoice_idempotency_key(account, document, line_items)

      {:ok,
       %{
         collection_method: "send_invoice",
         currency: line_items_currency(line_items),
         days_until_due: days_until_due(document),
         footer: invoice_footer(),
         metadata:
           compact_metadata(%{
             "atlas_account_id" => account.id,
             "atlas_account_key" => account.account_key,
             "atlas_document_id" => document.id,
             "atlas_source" => "latest_signed_order_form",
             "source_document_title" => document.title,
             "po_number" =>
               document_attribute(document, ["po_number"]) || document_attribute(document, ["purchase_order"])
           }),
         idempotency_key: idempotency_key,
         line_items:
           Enum.map(line_items, fn line_item ->
             line_item
             |> Map.put(:idempotency_key, idempotency_key)
             |> Map.update(:metadata, %{}, fn metadata ->
               compact_metadata(Map.merge(%{"atlas_document_id" => document.id}, metadata || %{}))
             end)
           end)
       }}
    end
  end

  defp invoice_line_items(%Account{} = account, %Document{} = document, opts) do
    case Keyword.get(opts, :line_items) do
      items when is_list(items) and items != [] ->
        explicit_line_items(items)

      _other ->
        document_invoice_line_items(account, document)
    end
  end

  defp document_invoice_line_items(%Account{} = account, %Document{} = document) do
    case document_line_item_attrs(document) do
      [_item | _] = items ->
        items
        |> Enum.with_index(1)
        |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
          case line_item_from_attrs(account, document, item, index) do
            {:ok, line_item} -> {:cont, {:ok, [line_item | acc]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, line_items} -> {:ok, Enum.reverse(line_items)}
          error -> error
        end

      _items ->
        scalar_line_item(account, document)
    end
  end

  defp explicit_line_items(items) when is_list(items) do
    items
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      case explicit_line_item(item, index) do
        {:ok, line_item} -> {:cont, {:ok, [line_item | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, line_items} -> {:ok, Enum.reverse(line_items)}
      error -> error
    end
  end

  defp explicit_line_item(item, index) when is_map(item) do
    description = item |> explicit_field("description") |> trimmed_string()
    amount = item |> explicit_field("amount") |> explicit_amount()
    currency = item |> explicit_field("currency") |> normalize_currency()
    quantity = item |> explicit_field("quantity") |> parse_positive_integer()
    period_start = item |> explicit_field("period_start") |> parse_date()
    period_end = item |> explicit_field("period_end") |> parse_date()

    with {:ok, description} <- present_string(description, :missing_line_item_description),
         {:ok, amount} <- positive_amount(amount),
         {:ok, currency} <- present_currency(currency),
         {:ok, amount_cents} <- amount_cents(amount) do
      {:ok,
       %{
         description: description,
         amount_value: amount,
         amount_cents: amount_cents,
         currency: currency,
         period_start: period_start,
         period_end: period_end,
         quantity: quantity,
         unit_amount_decimal: unit_amount_decimal(amount_cents, quantity),
         metadata: explicit_line_item_metadata(index, quantity, period_start, period_end)
       }}
    else
      {:error, :missing_amount} -> {:error, :missing_invoice_amount}
      {:error, :missing_currency} -> {:error, :missing_invoice_currency}
      error -> error
    end
  end

  defp explicit_line_item(_item, _index), do: {:error, :invalid_line_items}

  defp explicit_field(item, key) do
    case Map.get(item, key) do
      nil -> Map.get(item, String.to_existing_atom(key))
      value -> value
    end
  rescue
    ArgumentError -> nil
  end

  defp trimmed_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trimmed_string(_value), do: nil

  defp explicit_amount(%Decimal{} = decimal), do: decimal
  defp explicit_amount(value) when is_integer(value), do: Decimal.new(value)
  defp explicit_amount(value) when is_float(value), do: Decimal.from_float(value)

  defp explicit_amount(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(",", "")
    |> decimal()
  end

  defp explicit_amount(_value), do: nil

  defp present_string(nil, error), do: {:error, error}
  defp present_string(value, _error) when is_binary(value), do: {:ok, value}

  defp explicit_line_item_metadata(index, quantity, period_start, period_end) do
    compact_metadata(%{
      "line_item_index" => index,
      "quantity" => quantity,
      "term_start" => period_start,
      "term_end" => period_end,
      "term_duration_days" => term_duration_days(period_start, period_end)
    })
  end

  defp document_line_item_attrs(%Document{attributes: attrs}) when is_map(attrs) do
    direct =
      Enum.find_value(@invoice_line_item_keys, fn key ->
        case nested_value(attrs, [key]) do
          value when is_list(value) -> value
          _value -> nil
        end
      end)

    invoice =
      case nested_value(attrs, ["invoice"]) do
        %{} = invoice -> Enum.find_value(@invoice_line_item_keys, &list_value(invoice, &1))
        _value -> nil
      end

    direct || invoice || []
  end

  defp document_line_item_attrs(_document), do: []

  defp list_value(map, key) do
    case nested_value(map, [key]) do
      value when is_list(value) -> value
      _value -> nil
    end
  end

  defp line_item_from_attrs(%Account{} = account, %Document{} = document, item, index) when is_map(item) do
    {amount_value, amount_currency} = amount_and_currency_from_attrs(item)
    seats = seat_count_from_attrs(item) || document_seat_count(document)
    period_start = first_date(item, @period_start_keys) || document_period_start(document)
    period_end = first_date(item, @period_end_keys) || document_period_end(document)

    currency =
      normalize_currency(
        amount_currency || currency_from_attrs(item) || document_currency(document) || account.currency
      )

    with {:ok, amount} <- positive_amount(amount_value),
         {:ok, currency} <- present_currency(currency),
         {:ok, amount_cents} <- amount_cents(amount) do
      {:ok,
       %{
         description: enterprise_line_item_description(seats, period_start, period_end),
         amount_value: amount,
         amount_cents: amount_cents,
         currency: currency,
         period_start: period_start,
         period_end: period_end,
         quantity: seats,
         unit_amount_decimal: unit_amount_decimal(amount_cents, seats),
         metadata: line_item_metadata(index, seats, period_start, period_end)
       }}
    end
  end

  defp line_item_from_attrs(_account, _document, _item, _index), do: {:error, :invalid_line_items}

  defp scalar_line_item(%Account{} = account, %Document{} = document) do
    {amount_value, amount_currency} = amount_and_currency_from_document(document)
    currency = normalize_currency(amount_currency || document_currency(document) || account.currency)
    seats = document_seat_count(document)
    period_start = document_period_start(document)
    period_end = document_period_end(document)

    with {:ok, amount} <- positive_amount(amount_value),
         {:ok, currency} <- present_currency(currency),
         {:ok, amount_cents} <- amount_cents(amount) do
      {:ok,
       [
         %{
           description: enterprise_line_item_description(seats, period_start, period_end),
           amount_value: amount,
           amount_cents: amount_cents,
           currency: currency,
           period_start: period_start,
           period_end: period_end,
           quantity: seats,
           unit_amount_decimal: unit_amount_decimal(amount_cents, seats),
           metadata: line_item_metadata(1, seats, period_start, period_end)
         }
       ]}
    else
      {:error, :missing_amount} -> {:error, :missing_invoice_amount}
      {:error, :missing_currency} -> {:error, :missing_invoice_currency}
      error -> error
    end
  end

  defp amount_and_currency_from_attrs(attrs) when is_map(attrs) do
    Enum.find_value(@invoice_amount_keys, fn key ->
      attrs
      |> nested_value([key])
      |> amount_and_currency_from_value()
      |> case do
        {nil, nil} -> nil
        result -> result
      end
    end) || {nil, nil}
  end

  defp amount_and_currency_from_document(%Document{} = document) do
    amount_and_currency_from_attrs(document.attributes || %{})
    |> case do
      {nil, nil} -> amount_and_currency_from_text(document_full_text(document))
      result -> result
    end
  end

  defp amount_and_currency_from_value(nil), do: {nil, nil}
  defp amount_and_currency_from_value(%Decimal{} = amount), do: {amount, nil}
  defp amount_and_currency_from_value(value) when is_integer(value), do: {Decimal.new(value), nil}
  defp amount_and_currency_from_value(value) when is_float(value), do: {Decimal.from_float(value), nil}

  defp amount_and_currency_from_value(value) when is_binary(value) do
    currency = currency_from_text(value)

    amount =
      value
      |> String.replace(",", "")
      |> case do
        text ->
          case Regex.run(~r/-?\d+(?:\.\d+)?/, text) do
            [amount | _] -> decimal(amount)
            _match -> nil
          end
      end

    {amount, currency}
  end

  defp amount_and_currency_from_value(_value), do: {nil, nil}

  defp amount_and_currency_from_text(text) do
    pattern =
      ~r/(?:total|amount due|annual subscription|subscription fee|order total|fees?).{0,80}?(?:(?<currency_prefix>[A-Z]{3}|[$€£])\s*)?(?<amount>\d[\d,]*(?:\.\d{1,2})?)\s*(?<currency_suffix>[A-Z]{3})?/i

    case Regex.named_captures(pattern, text) do
      %{"amount" => amount} = captures ->
        currency =
          currency_from_text(captures["currency_prefix"]) ||
            currency_from_text(captures["currency_suffix"])

        {decimal(String.replace(amount, ",", "")), currency}

      nil ->
        {nil, nil}
    end
  end

  defp positive_amount(nil), do: {:error, :missing_amount}

  defp positive_amount(%Decimal{} = amount) do
    if Decimal.compare(amount, Decimal.new(0)) == :gt do
      {:ok, amount}
    else
      {:error, :invalid_invoice_amount}
    end
  end

  defp positive_amount(_amount), do: {:error, :missing_amount}

  defp amount_cents(%Decimal{} = amount) do
    cents = Decimal.mult(amount, Decimal.new(100))
    rounded = Decimal.round(cents, 0)

    if Decimal.equal?(cents, rounded) do
      {:ok, rounded |> Decimal.to_string(:normal) |> String.to_integer()}
    else
      {:error, :invalid_invoice_amount_precision}
    end
  end

  defp present_currency(nil), do: {:error, :missing_currency}
  defp present_currency(currency), do: {:ok, currency}

  defp document_currency(%Document{attributes: attrs}) when is_map(attrs) do
    Enum.find_value(@invoice_currency_keys, fn key ->
      attrs
      |> nested_value([key])
      |> normalize_currency()
    end)
  end

  defp document_currency(_document), do: nil

  defp currency_from_attrs(attrs) when is_map(attrs) do
    Enum.find_value(@invoice_currency_keys, fn key ->
      attrs
      |> nested_value([key])
      |> normalize_currency()
    end)
  end

  defp currency_from_text(nil), do: nil
  defp currency_from_text("$"), do: "USD"
  defp currency_from_text("€"), do: "EUR"
  defp currency_from_text("£"), do: "GBP"

  defp currency_from_text(text) when is_binary(text) do
    cond do
      String.contains?(text, "$") ->
        "USD"

      String.contains?(text, "€") ->
        "EUR"

      String.contains?(text, "£") ->
        "GBP"

      true ->
        case Regex.run(~r/\b(USD|EUR|GBP|CAD|AUD|CHF|JPY|SEK|NOK|DKK)\b/i, text) do
          [_, currency] -> normalize_currency(currency)
          _match -> nil
        end
    end
  end

  defp currency_from_text(_text), do: nil

  defp normalize_currency(value), do: Amounts.normalize_currency(value)

  defp decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      _other -> nil
    end
  end

  defp days_until_due(%Document{attributes: attrs}) when is_map(attrs) do
    Enum.find_value(@payment_terms_keys, fn key ->
      attrs
      |> nested_value([key])
      |> parse_days_until_due()
    end) || @default_invoice_days_until_due
  end

  defp days_until_due(_document), do: @default_invoice_days_until_due

  defp parse_days_until_due(value) when is_integer(value) and value > 0, do: value

  defp parse_days_until_due(value) when is_binary(value) do
    case Regex.run(~r/\d+/, value) do
      [days | _] -> String.to_integer(days)
      _match -> nil
    end
  end

  defp parse_days_until_due(_value), do: nil

  defp seat_count_from_attrs(attrs) when is_map(attrs) do
    Enum.find_value(@seat_count_keys, fn key ->
      attrs
      |> nested_value([key])
      |> parse_positive_integer()
    end)
  end

  defp seat_count_from_attrs(_attrs), do: nil

  defp document_seat_count(%Document{} = document) do
    seat_count_from_attrs(document.attributes || %{}) ||
      seat_count_from_text(document_full_text(document))
  end

  defp seat_count_from_text(text) when is_binary(text) do
    patterns = [
      ~r/\b(?<seats>\d{1,6})\s+(?:seats?|licenses?|users?)\b/i,
      ~r/\b(?:seats?|licenses?|users?)\s*[:\-]?\s*(?<seats>\d{1,6})\b/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.named_captures(pattern, text) do
        %{"seats" => seats} -> parse_positive_integer(seats)
        _captures -> nil
      end
    end)
  end

  defp seat_count_from_text(_text), do: nil

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Regex.run(~r/\d+/, value) do
      [integer | _] ->
        parse_positive_integer(String.to_integer(integer))

      _match ->
        nil
    end
  end

  defp parse_positive_integer(_value), do: nil

  defp enterprise_line_item_description(seats, period_start, period_end) do
    [
      @enterprise_product_name,
      seat_description(seats),
      term_description(period_start, period_end)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" - ")
  end

  defp seat_description(seats) when is_integer(seats) and seats > 0, do: "#{seats} seats"
  defp seat_description(_seats), do: nil

  defp term_description(%Date{} = period_start, %Date{} = period_end) do
    "#{Date.to_iso8601(period_start)} to #{Date.to_iso8601(period_end)}"
  end

  defp term_description(%Date{} = period_start, nil), do: "from #{Date.to_iso8601(period_start)}"
  defp term_description(nil, %Date{} = period_end), do: "through #{Date.to_iso8601(period_end)}"
  defp term_description(_period_start, _period_end), do: nil

  defp unit_amount_decimal(_amount_cents, seats) when not (is_integer(seats) and seats > 0), do: nil

  defp unit_amount_decimal(amount_cents, seats) when is_integer(amount_cents) do
    amount_cents
    |> Decimal.new()
    |> Decimal.div(Decimal.new(seats))
    |> Decimal.round(12)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp line_item_metadata(index, seats, period_start, period_end) do
    compact_metadata(%{
      "line_item_index" => index,
      "product_name" => @enterprise_product_name,
      "seats" => seats,
      "term_start" => period_start,
      "term_end" => period_end,
      "term_duration_days" => term_duration_days(period_start, period_end)
    })
  end

  defp term_duration_days(%Date{} = period_start, %Date{} = period_end) do
    if Date.compare(period_end, period_start) in [:gt, :eq] do
      Date.diff(period_end, period_start) + 1
    end
  end

  defp term_duration_days(_period_start, _period_end), do: nil

  defp document_period_start(document), do: first_date(document.attributes || %{}, @period_start_keys)
  defp document_period_end(document), do: first_date(document.attributes || %{}, @period_end_keys)

  defp first_date(attrs, keys) when is_map(attrs) do
    Enum.find_value(keys, fn key -> attrs |> nested_value([key]) |> parse_date() end)
  end

  defp first_date(_attrs, _keys), do: nil

  defp parse_date(%Date{} = date), do: date

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(_value), do: nil

  defp create_stripe_draft_invoice(customer_id, draft_attrs, opts) do
    opts
    |> stripe_client()
    |> case do
      client -> client.create_draft_invoice(customer_id, draft_attrs, client_opts(opts))
    end
    |> case do
      {:ok, %Stripe.Invoice{} = invoice} -> {:ok, invoice}
      :disabled -> {:error, :stripe_disabled}
      {:error, reason} -> {:error, reason}
    end
  end

  defp add_stripe_invoice_items(invoice_id, line_items, opts) do
    opts
    |> stripe_client()
    |> case do
      client -> client.add_invoice_items(invoice_id, line_items, client_opts(opts))
    end
    |> case do
      {:ok, %Stripe.Invoice{} = invoice} -> {:ok, invoice}
      :disabled -> {:error, :stripe_disabled}
      {:error, reason} -> {:error, reason}
    end
  end

  defp draft_invoice_idempotency_key(%Account{} = account, %Document{} = document, line_items) do
    signature =
      line_items
      |> Enum.map(fn line_item ->
        %{
          amount_cents: line_item.amount_cents,
          currency: line_item.currency,
          description: line_item.description,
          quantity: line_item[:quantity],
          period_start: line_item[:period_start],
          period_end: line_item[:period_end]
        }
      end)
      |> JSON.encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> String.slice(0, 24)

    "atlas:order-form-invoice:#{account.id}:#{document.id}:#{signature}"
  end

  defp compact_metadata(metadata) do
    metadata
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new(fn {key, value} -> {key, value |> to_string() |> String.slice(0, 500)} end)
  end

  defp document_attribute(%Document{attributes: attrs}, path) when is_map(attrs), do: nested_value(attrs, path)
  defp document_attribute(_document, _path), do: nil

  defp nested_value(map, path) when is_map(map) and is_list(path) do
    Enum.reduce_while(path, map, fn key, acc ->
      atom_key = existing_atom_key(key)

      cond do
        is_map(acc) and Map.has_key?(acc, key) -> {:cont, Map.get(acc, key)}
        is_map(acc) and not is_nil(atom_key) and Map.has_key?(acc, atom_key) -> {:cont, Map.get(acc, atom_key)}
        true -> {:halt, nil}
      end
    end)
  end

  defp nested_value(_map, _path), do: nil

  defp existing_atom_key(key) when is_atom(key), do: key

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp existing_atom_key(_key), do: nil

  defp document_context_text(%Document{} = document) do
    [
      document.title,
      document.original_filename,
      document.document_type && document.document_type.name,
      document.summary,
      Enum.map_join(document.tags || [], " ", & &1.name),
      attributes_text(document.attributes)
    ]
    |> normalize_document_text()
  end

  defp document_full_text(%Document{} = document) do
    [
      document_context_text(document),
      document.pages |> Enum.take(12) |> Enum.map_join("\n", & &1.content)
    ]
    |> normalize_document_text()
  end

  defp attributes_text(attrs) when is_map(attrs) do
    attrs
    |> Enum.map_join(" ", fn {key, value} -> "#{key} #{inspect(value)}" end)
  end

  defp attributes_text(_attrs), do: ""

  defp normalize_document_text(values) when is_list(values) do
    values
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> normalize_document_text()
  end

  defp normalize_document_text(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9$€£.,]+/u, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_document_text(value), do: value |> inspect() |> normalize_document_text()

  defp stripe_client(opts) do
    Keyword.get(opts, :stripe_client) ||
      :atlas
      |> Application.get_env(:accounts, [])
      |> Keyword.get(:stripe_client, Stripe)
  end

  defp exchange_rates_client do
    :atlas
    |> Application.get_env(:accounts, [])
    |> Keyword.get(:exchange_rates_client, ExchangeRates)
  end

  defp client_opts(opts), do: Keyword.delete(opts, :stripe_client)
end
