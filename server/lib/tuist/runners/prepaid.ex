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
  kind of customer it is looking at. The discount lives in how
  over-funded the grant is, not in a second rate card.

  Money rather than a minutes ledger, for two reasons:

    * it keeps mixed machine types fungible without pretending a minute
      on one shape is worth a minute on another: the credit is spent
      at whatever each machine actually costs
    * it avoids running a second credit ledger next to Stripe's, which
      would have to stay reconciled with every invoice, refund,
      proration and credit note Stripe issues on its own

  A grant scopes to specific Prices, which is what lets Linux and macOS
  carry different prepaid terms. Usage past a grant, or after it
  expires, falls through to the on-demand rate it was always reported
  at, so an exhausted grant needs no machinery here.

  ## Prepaid pools

  Prepaid runner time is sold for a contract term, usually a year paid
  up front by bank transfer. Usage is often seasonal, so the deal is a
  *pool*: one grant, usable for the whole term.

  A pool is granted by an operator with `grant_pool/2`, not from an invoice.
  The term's first and last day are contract dates someone knows when the
  deal is closed, so they are entered rather than inferred from Stripe. A
  term can be shorter than a year, to line a new contract up with the end
  of an earlier one. The invoice charging for the pool is an ordinary one
  with nothing on it for this module to read; its id is recorded on the
  grant so the credit can be traced to its charge.

  Stripe decides which invoices a grant pays for by when their periods end,
  so the term is turned into invoices on the account's billing cycle: the
  first whose period ends after the contract starts, through the one whose
  period holds its last day. `pool_coverage/3` works them out, and the ops
  form shows them before anything is granted. A grant already applied to an
  invoice cannot be voided, so a used pool is withdrawn by expiring it in
  Stripe.

  The terms are written for a person. The *credit multiplier* is how much
  credit each dollar paid buys: the on-demand price per minute divided by
  the deal's prepaid price per minute, so a $1,000 payment at 1.25 grants
  $1,250 of credit. It is held between 1.0 and 2.0 and recorded on the
  grant in basis points.

  Monthly prepaid grants made before pools were the only prepaid offering
  are still read by `balance/2` until Stripe expires them.

  ## Trials are not this

  A runner trial is an account that is not billed for runner usage at
  all, open-ended until cancelled. That cannot be a credit grant, which
  is a finite pot that runs out, so it lives in `Tuist.Runners.Trials`
  and works by keeping the runner item off the subscription. Grants here
  are only ever the paid kind.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.CreditGrants
  alias Tuist.KeyValueStore
  alias Tuist.Runners.Billing, as: RunnerBilling

  require Logger

  @platforms [:linux, :macos]

  @bp_basis 10_000

  # Hundredths of a US cent per compute-unit minute, one minute on the
  # platform's baseline machine, on demand: $0.05 on the macOS 8 vCPU /
  # 24 GB baseline and $0.0024 on the Linux 2 vCPU / 8 GB one, which puts
  # the 1 vCPU / 2 GB Linux machine at $0.001. This duplicates what each
  # platform's Stripe Price says, the same way `Tuist.Billing.UsagePricing`
  # duplicates the usage meter Prices, and has to be kept in step with it
  # by hand.
  @on_demand_rates %{macos: 500, linux: 24}

  # US cents per minute on the macOS baseline, the machine credit is
  # quoted in.
  @macos_on_demand_rate div(@on_demand_rates.macos, 100)

  # Par. Granting less than was paid would be a premium for prepaying,
  # which is only ever a typo.
  @min_funding_ratio_bp @bp_basis
  # 50% off. Past this a typo is likelier than a real deal.
  @max_funding_ratio_bp 20_000

  @prepaid_priority 50

  @kind_key "tuist_runner_credit"
  @invoice_key "tuist_prepaid_invoice_id"
  @paid_cents_key "tuist_prepaid_paid_cents"
  @granted_ratio_key "tuist_prepaid_funding_ratio_bp"

  @pool_kind "pool"
  # A yearly contract, granted up to a month before it starts.
  @max_pool_months 13

  @balance_cache_ttl to_timeout(minute: 5)

  # Stripe applies a grant only to an invoice whose period ends before the
  # grant expires, and the invoice closing a period ends exactly when the
  # period does, so a grant expiring at that instant never pays for the
  # usage it was bought for. Stripe finalizes that invoice within 72 hours
  # even when its invoice.created webhook keeps failing, and the next
  # period's invoice is a month away.
  @expiry_grace_days 4

  @doc """
  What `total_ms` of `platform`'s compute-unit milliseconds costs at the
  gross on-demand rate.

  Proportional to the millisecond, because that is how the runner Price
  charges: its tiers are in raw meter units and Stripe applies no
  rounding to them. Only the final amount is resolved to whole cents.

  Not the same as costing whole minutes. Half a minute of runner time is
  worth half a minute's money, not nothing, and a figure that truncated
  to minutes would understate every bill that is not a round number.
  """
  def on_demand_cost_for_milliseconds(platform, total_ms)
      when is_map_key(@on_demand_rates, platform) and is_integer(total_ms) and total_ms >= 0 do
    Money.new(div(total_ms * Map.fetch!(@on_demand_rates, platform), 6_000_000), :USD)
  end

  @doc """
  `on_demand_cost_for_milliseconds/2` in dollars, unrounded, for a chart
  that sums many small amounts. Resolving each to whole cents first would
  drop most of a day of small Linux machines.
  """
  def on_demand_dollars(platform, total_ms)
      when is_map_key(@on_demand_rates, platform) and is_integer(total_ms) and total_ms >= 0 do
    total_ms * Map.fetch!(@on_demand_rates, platform) / 600_000_000
  end

  @doc """
  What `minutes` of runner time costs at the gross on-demand rate, on
  the macOS baseline machine.

  This is what usage accrues at for everyone, prepaid or not, and so
  what a customer's runner usage is worth before any credit or trial is
  applied. Truncates to whole minutes the same way the Stripe Price
  does, so the figure shown matches the quantity that would be invoiced
  rather than running slightly ahead of it.
  """
  def on_demand_cost(minutes) when is_integer(minutes) and minutes >= 0 do
    Money.new(minutes * @macos_on_demand_rate, :USD)
  end

  @doc """
  Grants `account` a prepaid pool: runner credit paid up front for a whole
  contract term. See "Prepaid pools" above.

  `attrs` carries the agreed terms:

    * `:paid_cents` - what the customer paid for the pool, in US cents.
    * `:credit_multiplier` - how much credit each unit paid buys, as a
      `Decimal`. `1.4` turns a $8,000 payment into $11,200 of credit.
    * `:platforms` - the runner platforms the credit pays for.
    * `:starts_on` - the first day of the contract.
    * `:expires_on` - the last day of the contract, at most a year after
      the first.
    * `:invoice_id` - optional, the Stripe invoice that charged for the pool,
      recorded on the grant so the credit can be traced to its charge.

  Nothing is billed here: the charge is an ordinary invoice raised on its
  own. Returns `{:ok, grant}`, `{:error, {:invalid_pool, field}}` for a term
  no pool should have, or `{:error, reason}` when Stripe refuses the grant.
  """
  def grant_pool(%Account{customer_id: customer_id} = account, attrs) when is_binary(customer_id) and is_map(attrs) do
    with {:ok, paid_cents} <- pool_paid_cents(attrs[:paid_cents]),
         {:ok, ratio_bp} <- pool_funding_ratio_bp(attrs[:credit_multiplier]),
         {:ok, platforms} <- pool_platforms(attrs[:platforms]),
         :ok <- pool_term(attrs[:starts_on], attrs[:expires_on]),
         :ok <- pool_end(attrs[:expires_on]),
         {:ok, invoice_metadata} <- pool_invoice_metadata(attrs[:invoice_id]),
         {:ok, price_ids} <- price_ids(platforms) do
      coverage = pool_coverage(Billing.current_billing_period(account), attrs.starts_on, attrs.expires_on)
      terms = [paid_cents, ratio_bp, platforms, attrs.starts_on, attrs.expires_on, attrs[:invoice_id]]

      result =
        CreditGrants.create(%{
          customer_id: customer_id,
          amount_cents: div(paid_cents * ratio_bp, @bp_basis),
          currency: "usd",
          price_ids: price_ids,
          category: "paid",
          name: "Prepaid runner pool",
          effective_at: coverage.effective_at,
          expires_at: coverage.expires_at,
          priority: @prepaid_priority,
          metadata:
            Map.merge(invoice_metadata, %{
              @kind_key => @pool_kind,
              @paid_cents_key => to_string(paid_cents),
              @granted_ratio_key => to_string(ratio_bp)
            }),
          # Keyed on the terms, so a form submitted twice grants once.
          idempotency_key: "runner-prepaid-pool-#{customer_id}-#{terms_digest(terms)}"
        })

      refresh_balance(customer_id)
      result
    end
  end

  @doc """
  What a pool paying `paid_cents` at `credit_multiplier` grants, as the
  credit and the minutes it buys on the macOS 8 vCPU / 24 GB baseline.
  `:error` for terms `grant_pool/2` would refuse.
  """
  def quote_pool(paid_cents, credit_multiplier) do
    with {:ok, paid_cents} <- pool_paid_cents(paid_cents),
         {:ok, ratio_bp} <- pool_funding_ratio_bp(credit_multiplier) do
      granted_cents = div(paid_cents * ratio_bp, @bp_basis)
      {:ok, %{granted: Money.new(granted_cents, :USD), minutes: minutes_for(granted_cents)}}
    else
      {:error, _reason} -> :error
    end
  end

  @doc """
  Which invoices a pool for a contract from `starts_on` through `expires_on`
  pays for, on an account billed over `billing_period`, the `{start, end}`
  of one of its billing periods, or `nil` when it has none.

  Stripe pays an invoice from a grant when the invoice's period ends at or
  after the grant takes effect and before it expires. The pool takes effect
  just after the contract starts, so an invoice whose period ends as the
  contract starts, and so carries none of its usage, does not draw on it.
  It expires `@expiry_grace_days` after the invoice whose period holds the
  contract's last day, which on a cycle renewing mid-month or yearly closes
  after the contract does. An invoice straddling either end of the contract
  carries usage from both sides of it, and the pool pays for all of it.

  Returns `effective_at`, `nil` once the contract is running, since Stripe
  only takes one in the future and the pool then takes effect when it is
  granted; `expires_at`; and when the first and last invoice it pays for
  close, both `nil` without a billing cycle to read them from.
  """
  def pool_coverage(billing_period, %Date{} = starts_on, %Date{} = expires_on) do
    now = DateTime.utc_now()
    contract_end = start_of_day(Date.add(expires_on, 1))
    effective_at = DateTime.add(start_of_day(starts_on), 1, :second)
    effective_at = if DateTime.after?(effective_at, now), do: effective_at

    case period_ends(billing_period) do
      nil ->
        %{
          effective_at: effective_at,
          expires_at: past_period_end(contract_end),
          first_invoice_at: nil,
          last_invoice_at: nil
        }

      period_ends ->
        last_invoice_at = Enum.find(period_ends, &(not DateTime.before?(&1, contract_end)))

        %{
          effective_at: effective_at,
          expires_at: past_period_end(last_invoice_at),
          first_invoice_at: Enum.find(period_ends, &(not DateTime.before?(&1, effective_at || now))),
          last_invoice_at: last_invoice_at
        }
    end
  end

  # When the account's billing periods end, from the one given onward, for a
  # monthly or yearly cycle. Stripe keeps a cycle on its anchor day, which
  # month arithmetic from a period that started on a clamped day (February 28
  # for an anchor on the 31st) can undershoot by up to three days. The grace
  # after the last invoice covers that, at worst carrying the pool one
  # invoice further at a month end.
  defp period_ends({%DateTime{} = period_start, %DateTime{} = period_end}) do
    interval =
      Enum.find([1, 12], fn months ->
        abs(DateTime.diff(DateTime.shift(period_start, month: months), period_end, :day)) <= 3
      end)

    if interval do
      1 |> Stream.iterate(&(&1 + 1)) |> Stream.map(&DateTime.shift(period_start, month: &1 * interval))
    end
  end

  defp period_ends(_billing_period), do: nil

  defp start_of_day(date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  defp pool_paid_cents(paid_cents) when is_integer(paid_cents) and paid_cents > 0, do: {:ok, paid_cents}
  defp pool_paid_cents(_paid_cents), do: invalid_pool(:paid_cents)

  # The multiplier is the funding ratio, written for a person rather than in
  # basis points. It has to land on a whole basis point inside the band, so
  # a `12500` typed for `1.25` stops the grant instead of issuing ten
  # thousand times the credit.
  defp pool_funding_ratio_bp(%Decimal{} = credit_multiplier) do
    ratio_bp = Decimal.mult(credit_multiplier, @bp_basis)

    with true <- Decimal.integer?(ratio_bp),
         ratio_bp = Decimal.to_integer(ratio_bp),
         true <- ratio_bp >= @min_funding_ratio_bp and ratio_bp <= @max_funding_ratio_bp do
      {:ok, ratio_bp}
    else
      false -> invalid_pool(:credit_multiplier)
    end
  end

  defp pool_funding_ratio_bp(_credit_multiplier), do: invalid_pool(:credit_multiplier)

  defp pool_platforms([_platform | _rest] = platforms) do
    if Enum.all?(platforms, &(&1 in @platforms)),
      do: {:ok, platforms |> Enum.uniq() |> Enum.sort()},
      else: invalid_pool(:platforms)
  end

  defp pool_platforms(_platforms), do: invalid_pool(:platforms)

  # A term runs from its first day through its last, and lasts at most a
  # year, so its last day falls before the same date a year on.
  defp pool_term(%Date{} = starts_on, %Date{} = expires_on) do
    if Date.after?(starts_on, expires_on) or Date.after?(Date.add(expires_on, 1), Date.shift(starts_on, year: 1)),
      do: invalid_pool(:term),
      else: :ok
  end

  defp pool_term(_starts_on, _expires_on), do: invalid_pool(:term)

  # A contract already over, or one ending further out than a year-long term
  # starting within a month, is a typo.
  defp pool_end(%Date{} = expires_on) do
    today = DateTime.to_date(DateTime.utc_now())

    if Date.after?(expires_on, today) and not Date.after?(expires_on, Date.shift(today, month: @max_pool_months)),
      do: :ok,
      else: invalid_pool(:expires_on)
  end

  defp pool_invoice_metadata(nil), do: {:ok, %{}}

  defp pool_invoice_metadata(invoice_id) when is_binary(invoice_id) do
    case String.trim(invoice_id) do
      "" -> {:ok, %{}}
      "in_" <> _rest = invoice_id -> {:ok, %{@invoice_key => invoice_id}}
      _other -> invalid_pool(:invoice_id)
    end
  end

  defp pool_invoice_metadata(_invoice_id), do: invalid_pool(:invoice_id)

  defp invalid_pool(field), do: {:error, {:invalid_pool, field}}

  defp terms_digest(terms) do
    :sha256 |> :crypto.hash(:erlang.term_to_binary(terms)) |> Base.encode16(case: :lower) |> binary_part(0, 16)
  end

  @doc """
  Re-reads the balance and replaces the cached copy with it.

  Callers that have just changed the grants need this: `balance/2` is
  cached for minutes, so without it the next read serves the figure from
  before the change and the operator sees nothing happen.
  """
  def refresh_balance(customer_id) when is_binary(customer_id) do
    balance = fetch_balance(customer_id)

    # Written even when there is nothing left. `summarize/1` answers nil
    # for an account holding none, and skipping the write would leave the
    # entry from before the change to be served for the rest of its life
    # — which is what made a balance impossible to clear. A cached nil
    # reads as a miss, so the next call fetches rather than serving it.
    KeyValueStore.invalidate(balance_cache_key(customer_id), cache: :display)
    KeyValueStore.put(balance_cache_key(customer_id), balance, cache: :display, ttl: @balance_cache_ttl)

    balance
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
    # Versioned: the cached value is a map this module shapes, so a
    # deploy that changes that shape would otherwise serve stale entries
    # to new code until the TTL lapsed. Bump on any shape change.
    cache_key = balance_cache_key(customer_id)
    opts = Keyword.put_new(opts, :cache, :display)

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

  # Versioned: the cached value is a map this module shapes, so a deploy
  # that changes that shape would otherwise serve stale entries to new
  # code until the TTL lapsed. Bump on any shape change.
  defp balance_cache_key(customer_id), do: [:runner_prepaid_balance, :v3, customer_id]

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
          available_minutes: minutes_for(cents),
          expires_at: grant_expires_at(grant)
        }
      end)
      |> Enum.sort_by(&expiry_sort_key(&1.expires_at))

    granted = funded |> Enum.map(fn {grant, _cents} -> grant_amount_cents(grant) end) |> Enum.sum()
    period = funded |> Enum.map(&period_cents/1) |> Enum.sum()

    %{
      available: Money.new(total, currency),
      # What was bought, which does not move as it is spent. The balance
      # answers "what is left"; this answers "what was purchased", and a
      # reader checking their entitlement wants the second.
      granted: Money.new(granted, currency),
      granted_minutes: minutes_for(granted),
      # What the current billing period can run on. See `period_cents/1`.
      period_minutes: minutes_for(period),
      expires_at: grants |> Enum.map(& &1.expires_at) |> Enum.reject(&is_nil/1) |> Enum.min(DateTime, fn -> nil end),
      grants: grants
    }
  end

  # Stripe draws credit down only when an invoice closes, so mid-period a
  # monthly grant still holds everything it was bought with, and that
  # purchase is the figure that stays put as the period's usage accrues. A
  # pool has already paid for the periods before this one, so its purchase
  # would count a whole term toward a single month: what it has left is
  # what this period can run on.
  defp period_cents({grant, available_cents}) do
    if pool?(grant), do: available_cents, else: grant_amount_cents(grant)
  end

  defp pool?(grant), do: grant_kind(grant) == @pool_kind

  # Credit is spent at the gross on-demand rate, so that rate is what
  # turns an amount of money into the minutes it buys on the baseline
  # machine.
  defp minutes_for(cents), do: div(cents, @macos_on_demand_rate)

  defp past_period_end(period_end), do: DateTime.add(period_end, @expiry_grace_days, :day)

  defp grant_amount_cents(grant) do
    grant
    |> Map.get(:amount, %{})
    |> Map.get(:monetary, %{})
    |> Map.get(:value, 0)
  end

  # Only grants this module created, and only ones that can still pay
  # for something. A grant Stripe has already expired stays listed
  # forever, so filtering on the marker alone would keep last year's
  # prepay on the page.
  defp live_runner_credit?(grant) do
    grant_kind(grant) != nil and not expired?(grant_expires_at(grant)) and not voided?(grant)
  end

  # A voided grant stays in the listing with its original amount, so
  # without this it would still read as live although nothing draws on it.
  defp voided?(grant), do: not is_nil(Map.get(grant, :voided_at))

  # Soonest expiry first, never-expiring last. Sorting on the struct
  # itself would order by Erlang term comparison, which walks a
  # DateTime's fields alphabetically and puts September 2026 after
  # January 2027.
  defp expiry_sort_key(nil), do: {1, 0}
  defp expiry_sort_key(%DateTime{} = expires_at), do: {0, DateTime.to_unix(expires_at)}

  defp expired?(nil), do: false
  defp expired?(%DateTime{} = expires_at), do: DateTime.before?(expires_at, DateTime.utc_now())

  # A grant also covers the platform's retired Prices, so it pays for a
  # subscription that has not been moved off one yet.
  defp price_ids(platforms) do
    prices = Tuist.Environment.stripe_prices() || %{}
    configured = Map.get(prices, "runners", %{})
    retired = Map.get(prices, "retired_runners", %{})

    meters =
      platforms
      |> Enum.map(&RunnerBilling.meter_event_name/1)
      |> Enum.filter(&(is_binary(configured[&1]) and configured[&1] != ""))

    ids =
      meters
      |> Enum.flat_map(&[configured[&1] | List.wrap(retired[&1])])
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.uniq()

    if ids == [], do: {:error, :no_runner_prices_configured}, else: {:ok, ids}
  end

  # Stripe preserves metadata keys as strings on the objects it has a
  # struct for, and atomizes them on the ones it does not. Credit grants
  # arrive as plain maps, so normalize instead of guessing.
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

  # "prepaid" is the monthly kind no longer sold, still read until the
  # last of those grants expires.
  defp grant_kind(grant) do
    case grant_metadata(grant, @kind_key) do
      kind when kind in ["prepaid", "trial", @pool_kind] -> kind
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
end
