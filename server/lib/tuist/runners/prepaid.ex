defmodule Tuist.Runners.Prepaid do
  @moduledoc """
  Prepaid runner access, as a money-denominated Stripe credit grant.

  ## The model

  Runner usage is always reported gross, at the on-demand rate, for
  every customer. Prepaid is not a discounted second Price and not a
  pool of minutes decremented inside Tuist: it is a balance of *money*
  on the Stripe customer, scoped to the runner metered Prices, that
  Stripe draws down as those gross-rated line items are invoiced.
  Reporting is byte-for-byte identical for a prepaid customer and a
  pay-as-you-go one, so nothing in the metering path has to know which
  kind of customer it is looking at.

  The discount therefore lives in how over-funded the grant is, not in
  a second rate card. At the agreed macOS terms — $0.075 per baseline
  machine-minute on demand, $0.06 prepaid — a customer paying $X can
  consume $X / 0.8 of on-demand-priced usage, so the grant is funded at
  1.25x what they paid. `@default_funding_ratio_bp` is that 1.25x, in
  basis points.

  Money rather than a minutes ledger, for two reasons:

    * it keeps mixed machine types fungible without pretending a minute
      on one shape is worth a minute on another — the credit is spent
      at whatever each machine actually costs
    * it avoids running a second credit ledger next to Stripe's, which
      would have to stay reconciled with every invoice, refund,
      proration and credit note Stripe issues on its own

  ## Why the Prices are per platform

  A credit grant scopes to specific Prices, which is what lets Linux
  and macOS carry different prepaid terms. With one global runner
  Price, prepaid would collapse to a single discount percentage across
  every machine type. Today a grant covers *every* configured runner
  Price by default, because the fungibility above is the point and
  Linux has no agreed rate yet; an invoice can narrow it to one
  platform when a deal is struck on one platform's terms alone.

  ## Where the terms are configured

  The default ratio and expiry are module attributes here, alongside
  `Tuist.Billing`'s `@unit_prices`, rather than deployment config:
  they are rate-card facts, identical in every environment, and a
  change to either should be a reviewed commit rather than a values
  file edit.

  Per-deal terms come from metadata on the Stripe invoice, because
  prepay is negotiated per customer and one deal's terms must not bind
  the next one's. Because a hand-typed ratio is a money multiplier, an
  out-of-range or unparseable one is rejected outright rather than
  falling back to the default — a `1250` typed for `12500` should stop
  the grant, not quietly issue a tenth of the credit.

  Invoice metadata keys:

    * `tuist_prepaid_runners` — required marker, and the platform
      scope. `"true"`/`"all"` covers every configured runner Price;
      `"macos"`, `"linux"`, or a comma-separated list narrows it.
    * `tuist_prepaid_runners_funding_ratio_bp` — optional, basis
      points of credit per unit paid, so the 1.25x default is `12500`.
      Bounded between par (10000, no discount) and 20000 (50% off).
    * `tuist_prepaid_runners_expires_in_days` — optional, overrides the
      default expiry.

  A prepaid invoice must not carry unrelated line items: the grant is
  funded from the invoice's `amount_paid`, so anything else billed on
  the same invoice would be converted into runner credit too.

  ## Top-ups and expiry

  Neither needs machinery here. Every paid prepaid invoice creates its
  own grant, and Stripe applies whichever grants are live at invoice
  time in priority then expiry order, so a top-up is just another
  grant and an exhausted or expired one simply stops applying —
  usage past it falls through to the on-demand rate it was always
  reported at. That is the second dividend of keeping the balance in
  money: there is no merging, no re-basing, and no expiry sweep to run.

  ## Trials

  A time-boxed runner trial is the same object with `category:
  "promotional"` and a short expiry — see `grant_trial/3`. Stripe
  reports promotional credit separately from purchased credit, which
  is what keeps free trial usage out of recognised revenue. Trial
  grants are given a stronger priority than prepaid ones so free
  credit is consumed before credit the customer paid for.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Billing.CreditGrants
  alias Tuist.KeyValueStore
  alias Tuist.Runners.Billing, as: RunnerBilling

  require Logger

  @platforms [:linux, :macos]

  @bp_basis 10_000
  # 1.25x credit per unit paid: the 20% prepaid discount, expressed as
  # over-funding against the gross on-demand rate usage is reported at.
  @default_funding_ratio_bp 12_500
  # Par. Granting less than was paid would be a premium for prepaying,
  # which is only ever a typo.
  @min_funding_ratio_bp @bp_basis
  # 50% off. Past this a metadata typo is likelier than a real deal.
  @max_funding_ratio_bp 20_000

  @default_expiry_days 365
  @max_expiry_days 1095
  @default_trial_expiry_days 30

  # Stripe applies the lowest number first. Trial credit is free and
  # expires sooner, so it burns ahead of the customer's own money.
  @prepaid_priority 50
  @trial_priority 25

  @marker_key "tuist_prepaid_runners"
  @ratio_key "tuist_prepaid_runners_funding_ratio_bp"
  @expiry_key "tuist_prepaid_runners_expires_in_days"

  @kind_key "tuist_runner_credit"
  @invoice_key "tuist_prepaid_invoice_id"
  @paid_cents_key "tuist_prepaid_paid_cents"
  @granted_ratio_key "tuist_prepaid_funding_ratio_bp"

  @balance_cache_ttl to_timeout(minute: 5)

  @doc """
  Creates the credit grant a paid prepaid invoice has funded.

  Returns `{:ok, grant}` on success, `{:ok, :not_prepaid}` for an
  invoice that carries no prepaid marker (the overwhelming majority —
  every subscription renewal lands here), `{:ok, :already_granted}` when
  a grant for this invoice exists, and `{:error, reason}` otherwise.

  `{:error, :no_runner_prices_configured}` is the state every
  environment is in until the runner Prices are created. It is a
  retryable condition, not a dead end: the money is collected and the
  grant is still owed, so the caller must keep the job alive rather
  than drop it.
  """
  def grant_for_paid_invoice(invoice) do
    metadata = invoice_metadata(invoice)

    with {:ok, platforms} <- platforms_from_metadata(metadata),
         {:ok, customer_id} <- customer_id(invoice),
         {:ok, invoice_id} <- invoice_id(invoice),
         {:ok, amount_paid} <- amount_paid(invoice),
         {:ok, ratio_bp} <- funding_ratio_bp(metadata),
         {:ok, expiry_days} <- expiry_days(metadata),
         {:ok, price_ids} <- price_ids(platforms),
         {:ok, :absent} <- existing_grant(customer_id, invoice_id) do
      CreditGrants.create(%{
        customer_id: customer_id,
        amount_cents: div(amount_paid * ratio_bp, @bp_basis),
        currency: invoice_currency(invoice),
        price_ids: price_ids,
        category: "paid",
        name: "Prepaid runner credit",
        expires_at: DateTime.add(DateTime.utc_now(), expiry_days, :day),
        priority: @prepaid_priority,
        metadata: %{
          @kind_key => "prepaid",
          @invoice_key => invoice_id,
          @paid_cents_key => to_string(amount_paid),
          @granted_ratio_key => to_string(ratio_bp)
        },
        idempotency_key: "runner-prepaid-#{invoice_id}"
      })
    else
      :not_prepaid -> {:ok, :not_prepaid}
      {:ok, {:already_granted, _grant}} -> {:ok, :already_granted}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  True when `invoice` is marked as funding prepaid runner credit.

  A malformed marker counts as prepaid, so `grant_for_paid_invoice/1`
  gets the chance to fail on it. Treating an unparseable scope as "not
  prepaid" would silently swallow a paid invoice.
  """
  def prepaid_invoice?(invoice) do
    invoice |> invoice_metadata() |> platforms_from_metadata() != :not_prepaid
  end

  @doc """
  Grants `amount_cents` of promotional runner credit to `account`,
  expiring after `:expires_in_days` (default #{@default_trial_expiry_days}).

  This is the trial: the same grant a prepaid invoice creates, with
  `category: "promotional"` so Stripe keeps it out of purchased-credit
  reporting, and a shorter clock. `:platforms` narrows the scope the
  same way an invoice can.

  There is no automatic enrolment on top of this — a trial is granted
  deliberately, per account.
  """
  def grant_trial(%Account{customer_id: customer_id}, amount_cents, opts \\ [])
      when is_binary(customer_id) and is_integer(amount_cents) and amount_cents > 0 do
    platforms = Keyword.get(opts, :platforms, @platforms)
    expires_in_days = Keyword.get(opts, :expires_in_days, @default_trial_expiry_days)

    with {:ok, price_ids} <- price_ids(platforms) do
      CreditGrants.create(%{
        customer_id: customer_id,
        amount_cents: amount_cents,
        currency: Keyword.get(opts, :currency, "usd"),
        price_ids: price_ids,
        category: "promotional",
        name: "Runner trial credit",
        expires_at: DateTime.add(DateTime.utc_now(), expires_in_days, :day),
        priority: @trial_priority,
        metadata: %{@kind_key => "trial"}
      })
    end
  end

  @doc """
  Runner credit left on `account`, or `nil` when it has none.

  Reads Stripe rather than anything local: the grant object records
  what was granted and never moves, so what remains is only knowable
  from the balance summary. Expired grants are dropped before the
  balances are fetched, and so are exhausted ones after, so a customer
  who has burned through their prepay sees nothing rather than a row of
  zeroes.

  Returns `%{available: Money.t(), expires_at: DateTime.t() | nil,
  grants: [...]}`, where `expires_at` is the soonest expiry among the
  grants still holding a balance — the date the customer would want a
  warning about.
  """
  def balance(account, opts \\ [])

  def balance(%Account{customer_id: customer_id}, opts) when is_binary(customer_id) do
    cache_key = [:runner_prepaid_balance, customer_id]

    case KeyValueStore.get(cache_key, opts) do
      nil ->
        balance = fetch_balance(customer_id)
        if balance, do: KeyValueStore.put(cache_key, balance, Keyword.put(opts, :ttl, @balance_cache_ttl))
        balance

      cached ->
        cached
    end
  end

  def balance(_account, _opts), do: nil

  @doc """
  The default funding ratio in basis points, for callers that need to
  quote prepaid terms without creating a grant.
  """
  def default_funding_ratio_bp, do: @default_funding_ratio_bp

  defp fetch_balance(customer_id) do
    with {:ok, grants} <- CreditGrants.list_for_customer(customer_id),
         live = Enum.filter(grants, &live_runner_credit?/1),
         {:ok, funded} <- with_balances(customer_id, live) do
      summarize(funded)
    else
      {:error, reason} ->
        Logger.warning("runners: could not read prepaid balance for #{customer_id}: #{inspect(reason)}")
        nil
    end
  end

  defp with_balances(customer_id, grants) do
    Enum.reduce_while(grants, {:ok, []}, fn grant, {:ok, acc} ->
      case CreditGrants.available_balance_cents(customer_id, grant.id) do
        {:ok, 0} -> {:cont, {:ok, acc}}
        {:ok, cents} -> {:cont, {:ok, [{grant, cents} | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp summarize([]), do: nil

  defp summarize(funded) do
    total = funded |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    currency = funded |> hd() |> elem(0) |> grant_currency()

    grants =
      funded
      |> Enum.map(fn {grant, cents} ->
        %{
          id: grant.id,
          kind: grant_kind(grant),
          available: Money.new(cents, currency),
          expires_at: grant_expires_at(grant)
        }
      end)
      |> Enum.sort_by(&expiry_sort_key(&1.expires_at))

    %{
      available: Money.new(total, currency),
      expires_at: grants |> Enum.map(& &1.expires_at) |> Enum.reject(&is_nil/1) |> Enum.min(DateTime, fn -> nil end),
      grants: grants
    }
  end

  # Only grants this module created, and only ones that can still pay
  # for something. A grant Stripe has already expired stays listed
  # forever, so filtering on the marker alone would keep last year's
  # prepay on the page.
  defp live_runner_credit?(grant) do
    grant_kind(grant) != nil and not expired?(grant_expires_at(grant))
  end

  # Soonest expiry first, never-expiring last. Sorting on the struct
  # itself would order by Erlang term comparison, which walks a
  # DateTime's fields alphabetically and puts September 2026 after
  # January 2027.
  defp expiry_sort_key(nil), do: {1, 0}
  defp expiry_sort_key(%DateTime{} = expires_at), do: {0, DateTime.to_unix(expires_at)}

  defp expired?(nil), do: false
  defp expired?(%DateTime{} = expires_at), do: DateTime.before?(expires_at, DateTime.utc_now())

  defp existing_grant(customer_id, invoice_id) do
    case CreditGrants.list_for_customer(customer_id) do
      {:ok, grants} ->
        case Enum.find(grants, &(grant_metadata(&1, @invoice_key) == invoice_id)) do
          nil -> {:ok, :absent}
          grant -> {:ok, {:already_granted, grant}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp price_ids(platforms) do
    configured = configured_runner_prices()

    ids =
      platforms
      |> Enum.map(&Map.get(configured, RunnerBilling.meter_event_name(&1)))
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.uniq()

    if ids == [], do: {:error, :no_runner_prices_configured}, else: {:ok, ids}
  end

  defp configured_runner_prices do
    Map.get(Tuist.Environment.stripe_prices() || %{}, "runners", %{})
  end

  defp platforms_from_metadata(metadata) do
    case metadata |> Map.get(@marker_key) |> normalize() do
      value when value in [nil, "", "false", "0"] -> :not_prepaid
      value when value in ["true", "all", "*"] -> {:ok, @platforms}
      value -> parse_platforms(value)
    end
  end

  defp parse_platforms(value) do
    parsed =
      value
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&platform_from_string/1)

    case Enum.find(parsed, &match?({:error, _reason}, &1)) do
      nil -> {:ok, parsed |> Enum.map(&elem(&1, 1)) |> Enum.uniq()}
      error -> error
    end
  end

  defp platform_from_string("linux"), do: {:ok, :linux}
  defp platform_from_string("macos"), do: {:ok, :macos}
  defp platform_from_string(other), do: {:error, {:unknown_platform, other}}

  defp funding_ratio_bp(metadata) do
    case metadata |> Map.get(@ratio_key) |> normalize() do
      nil -> {:ok, @default_funding_ratio_bp}
      "" -> {:ok, @default_funding_ratio_bp}
      value -> bounded_integer(value, @min_funding_ratio_bp, @max_funding_ratio_bp, :funding_ratio_bp)
    end
  end

  defp expiry_days(metadata) do
    case metadata |> Map.get(@expiry_key) |> normalize() do
      nil -> {:ok, @default_expiry_days}
      "" -> {:ok, @default_expiry_days}
      value -> bounded_integer(value, 1, @max_expiry_days, :expires_in_days)
    end
  end

  defp bounded_integer(value, min, max, field) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= min and parsed <= max -> {:ok, parsed}
      _ -> {:error, {:invalid_metadata, field, value}}
    end
  end

  defp customer_id(invoice) do
    case Map.get(invoice, :customer) do
      id when is_binary(id) and id != "" -> {:ok, id}
      %{id: id} when is_binary(id) -> {:ok, id}
      _ -> {:error, :missing_customer}
    end
  end

  defp invoice_id(invoice) do
    case Map.get(invoice, :id) do
      id when is_binary(id) and id != "" -> {:ok, id}
      _ -> {:error, :missing_invoice_id}
    end
  end

  # `amount_paid` is what the invoice actually collected, which is what
  # the grant is funded from. `total` would fund credit for an invoice
  # that was only partly paid.
  defp amount_paid(invoice) do
    case Map.get(invoice, :amount_paid) do
      amount when is_integer(amount) and amount > 0 -> {:ok, amount}
      amount -> {:error, {:invalid_amount_paid, amount}}
    end
  end

  defp invoice_currency(invoice) do
    case Map.get(invoice, :currency) do
      currency when is_binary(currency) and currency != "" -> currency
      _ -> "usd"
    end
  end

  defp invoice_metadata(invoice) do
    case Map.get(invoice, :metadata) do
      metadata when is_map(metadata) -> stringify_keys(metadata)
      _ -> %{}
    end
  end

  # Stripe preserves metadata keys as strings on the objects it has a
  # struct for, and atomizes them on the ones it does not. Both shapes
  # reach this module — invoices arrive as structs, credit grants as
  # plain maps — so normalize once instead of guessing per call site.
  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp grant_metadata(grant, key) do
    grant
    |> Map.get(:metadata)
    |> case do
      metadata when is_map(metadata) -> metadata |> stringify_keys() |> Map.get(key)
      _ -> nil
    end
  end

  defp grant_kind(grant) do
    case grant_metadata(grant, @kind_key) do
      kind when kind in ["prepaid", "trial"] -> kind
      _ -> nil
    end
  end

  defp grant_expires_at(grant) do
    case Map.get(grant, :expires_at) do
      expires_at when is_integer(expires_at) -> DateTime.from_unix!(expires_at)
      _ -> nil
    end
  end

  defp grant_currency(grant) do
    grant
    |> Map.get(:amount, %{})
    |> Map.get(:monetary, %{})
    |> Map.get(:currency, "usd")
  end

  defp normalize(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp normalize(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize(true), do: "true"
  defp normalize(_value), do: nil
end
