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

  The default ratio is a module attribute here, alongside
  `Tuist.Billing`'s `@unit_prices`, rather than deployment config:
  they are rate-card facts, identical in every environment, and a
  change to either should be a reviewed commit rather than a values
  file edit.

  Per-deal terms come from metadata on the Stripe invoice *line*,
  because prepay is negotiated per customer and one deal's terms must
  not bind the next one's. Because a hand-typed ratio is a money
  multiplier, an out-of-range or unparseable one is rejected outright
  rather than falling back to the default — a `1250` typed for `12500`
  should stop the grant, not quietly issue a tenth of the credit.

  Line metadata keys:

    * `tuist_prepaid_runners` — required marker, and the platform
      scope. `"true"`/`"all"` covers every configured runner Price;
      `"macos"`, `"linux"`, or a comma-separated list narrows it.
    * `tuist_prepaid_runners_funding_ratio_bp` — optional, basis
      points of credit per unit paid, so the 1.25x default is `12500`.
      Bounded between par (10000, no discount) and 20000 (50% off).

  ## Why the line and not the invoice

  A prepaid charge rides along on the customer's ordinary monthly
  invoice rather than arriving as a separate bill, so the invoice it
  lands on also carries that month's metered usage. Marking the
  *invoice* and funding from its `amount_paid` would convert the whole
  bill into runner credit; marking the *line* and funding from the sum
  of marked lines takes exactly the prepaid portion and nothing else.

  It also means the prepaid charge is created as a pending Stripe
  invoice item, which Stripe sweeps onto the next invoice on its own.
  Nothing here has to know when the billing period closes. Note that a
  customer with no subscription never has an invoice generated, so a
  pending item on such an account would sit unbilled indefinitely.

  Each marked line becomes its own grant, carrying that line's own
  terms. Two top-ups bought in one month at different ratios stay
  independently priced instead of being averaged into one balance.

  ## Top-ups and expiry

  Minutes belong to the month they were bought for. Every grant
  expires at the end of the billing period the paying invoice covered,
  so nothing rolls over: what an account does not spend that month is
  gone, and next month's minutes arrive on their own invoice.

  Neither top-ups nor expiry need machinery here. Every prepaid line
  creates its own grant, and Stripe applies whichever grants are live
  at invoice time in priority then expiry order, so a top-up is just
  another grant and an exhausted or expired one simply stops applying
  — usage past it falls through to the on-demand rate it was always
  reported at. That is the second dividend of keeping the balance in
  money: there is no merging, no re-basing, and no expiry sweep to run.

  ## When the grant happens

  Selling minutes grants them, rather than waiting for the invoice
  carrying the charge to be paid: an account that buys minutes can run
  on them immediately, which is the whole point of selling them. The
  charge still rides the next monthly bill, so an account that never
  pays it has spent minutes it owes for — accepted deliberately, on the
  grounds that an account which has agreed to prepay and then vanishes
  is rare enough not to justify withholding what it bought.

  `grant_for_paid_invoice/1` remains the path for lines that reach an
  invoice without a grant, which is what a failure to grant at sale
  time degrades to. It skips lines already granted, matching the
  invoice item id the up-front grant recorded as well as the line id,
  since a line and the invoice item it came from are different objects
  with different ids.

  ## Trials are not this

  A runner trial is an account that is not billed for runner usage at
  all, open-ended until cancelled. That cannot be a credit grant, which
  is a finite pot that runs out, so it lives in `Tuist.Runners.Trials`
  and works by keeping the runner item off the subscription. Grants here
  are only ever the paid kind.
  """

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.CreditGrants
  alias Tuist.Billing.Invoices
  alias Tuist.KeyValueStore
  alias Tuist.Runners.Billing, as: RunnerBilling

  require Logger

  @platforms [:linux, :macos]

  @bp_basis 10_000

  # Tenths of a cent per machine-minute on the macOS 6 vCPU / 14 GB
  # baseline: $0.075 on demand, $0.06 prepaid. Tenths because $0.075 is
  # not a whole number of cents. These duplicate what the Stripe Price
  # says, the same way `Tuist.Billing`'s `@unit_prices` does, and have
  # to be kept in step with it by hand.
  @macos_on_demand_rate 75
  @macos_prepaid_rate 60

  # The 20% prepaid discount, expressed as over-funding against the
  # gross on-demand rate usage is reported at, and derived from the two
  # rates rather than restated: 75/60 is 1.25x. Only macOS has an
  # agreed rate, so this is the ratio for every platform until Linux
  # gets one.
  @default_funding_ratio_bp div(@bp_basis * @macos_on_demand_rate, @macos_prepaid_rate)
  # Par. Granting less than was paid would be a premium for prepaying,
  # which is only ever a typo.
  @min_funding_ratio_bp @bp_basis
  # 50% off. Past this a metadata typo is likelier than a real deal.
  @max_funding_ratio_bp 20_000

  @prepaid_priority 50

  @marker_key "tuist_prepaid_runners"
  @ratio_key "tuist_prepaid_runners_funding_ratio_bp"

  @kind_key "tuist_runner_credit"
  @invoice_key "tuist_prepaid_invoice_id"
  @line_key "tuist_prepaid_invoice_line_id"
  @paid_cents_key "tuist_prepaid_paid_cents"
  @granted_ratio_key "tuist_prepaid_funding_ratio_bp"

  @balance_cache_ttl to_timeout(minute: 5)

  @doc """
  Creates a credit grant for every prepaid line on a paid invoice.

  Returns `{:ok, grants}` with the grants it created, `{:ok,
  :not_prepaid}` for an invoice carrying no marked line (the
  overwhelming majority — every ordinary monthly bill lands here), and
  `{:error, reason}` otherwise. A line that already has a grant is
  skipped rather than granted twice, so a retry after a partial failure
  finishes the remaining lines and leaves the rest alone.

  `{:error, :no_runner_prices_configured}` is the state every
  environment is in until the runner Prices are created. It is a
  retryable condition, not a dead end: the money is collected and the
  grant is still owed, so the caller must keep the job alive rather
  than drop it.
  """
  def grant_for_paid_invoice(invoice) do
    with {:ok, customer_id} <- customer_id(invoice),
         {:ok, invoice_id} <- invoice_id(invoice),
         {:ok, lines} <- Invoices.list_lines(invoice_id) do
      case Enum.filter(lines, &prepaid_line?/1) do
        [] -> {:ok, :not_prepaid}
        marked -> grant_lines(customer_id, invoice_id, marked, invoice_currency(invoice))
      end
    end
  end

  # Existing grants are read once and matched by line id, rather than
  # per line, so an invoice carrying several prepaid lines costs one
  # lookup instead of one each.
  defp grant_lines(customer_id, invoice_id, lines, currency) do
    with {:ok, granted_line_ids} <- granted_line_ids(customer_id) do
      expires_at = expires_at(customer_id)

      lines
      |> Enum.reject(&granted?(granted_line_ids, &1))
      |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
        case grant_line(customer_id, invoice_id, line, currency, expires_at) do
          {:ok, grant} -> {:cont, {:ok, [grant | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, grants} -> {:ok, Enum.reverse(grants)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp grant_line(customer_id, invoice_id, line, currency, expires_at) do
    metadata = line_metadata(line)

    with {:ok, platforms} <- platforms_from_metadata(metadata),
         {:ok, amount} <- line_amount(line),
         {:ok, ratio_bp} <- funding_ratio_bp(metadata),
         {:ok, price_ids} <- price_ids(platforms) do
      CreditGrants.create(%{
        customer_id: customer_id,
        amount_cents: div(amount * ratio_bp, @bp_basis),
        currency: currency,
        price_ids: price_ids,
        category: "paid",
        name: "Prepaid runner credit",
        expires_at: expires_at,
        priority: @prepaid_priority,
        metadata: %{
          @kind_key => "prepaid",
          @invoice_key => invoice_id,
          @line_key => line_id(line),
          @paid_cents_key => to_string(amount),
          @granted_ratio_key => to_string(ratio_bp)
        },
        idempotency_key: "runner-prepaid-#{invoice_id}-#{line_id(line)}"
      })
    else
      # A line marked prepaid whose scope will not parse is a mistake
      # worth surfacing, not a line to skip: it was paid for.
      :not_prepaid -> {:error, {:unmarked_line, line_id(line)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp granted_line_ids(customer_id) do
    case CreditGrants.list_for_customer(customer_id) do
      {:ok, grants} ->
        {:ok,
         grants
         |> Enum.map(&grant_metadata(&1, @line_key))
         |> Enum.reject(&is_nil/1)
         |> MapSet.new()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepaid_line?(line) do
    line |> line_metadata() |> platforms_from_metadata() != :not_prepaid
  end

  defp line_id(line), do: Map.get(line, :id)

  # A line billed up front was granted against the invoice item's id,
  # which the line carries in `invoice_item`. Matching on the line id
  # alone would grant those minutes a second time when the invoice is
  # paid.
  defp granted?(granted_line_ids, line) do
    [line_id(line), Map.get(line, :invoice_item)]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(&MapSet.member?(granted_line_ids, &1))
  end

  defp line_metadata(line) do
    case Map.get(line, :metadata) do
      metadata when is_map(metadata) -> stringify_keys(metadata)
      _ -> %{}
    end
  end

  # The line's own amount, which is the prepaid portion of the bill and
  # nothing else. A zero or credited line funds no grant.
  defp line_amount(line) do
    case Map.get(line, :amount) do
      amount when is_integer(amount) and amount > 0 -> {:ok, amount}
      amount -> {:error, {:invalid_line_amount, amount}}
    end
  end

  @doc """
  What `minutes` of prepaid runner time costs and buys.

  Quoted against the macOS 6 vCPU / 14 GB baseline, the only machine
  with an agreed rate. Returns the amount to invoice, the credit that
  payment funds, and the ratio between them.

  The minute count is honest only for the baseline machine. Credit is
  money, and a larger machine costs proportionally more per minute, so
  the same balance buys fewer minutes on one. That is the point of
  holding the balance in money rather than minutes, and the reason this
  is a quote rather than a stored figure.
  """
  def quote_minutes(minutes) when is_integer(minutes) and minutes > 0 do
    invoiced_cents = div(minutes * @macos_prepaid_rate, 10)

    %{
      minutes: minutes,
      invoiced: Money.new(invoiced_cents, :USD),
      granted: Money.new(div(invoiced_cents * @default_funding_ratio_bp, @bp_basis), :USD),
      funding_ratio_bp: @default_funding_ratio_bp
    }
  end

  @doc """
  What `total_ms` of compute-unit milliseconds costs at the gross
  on-demand rate.

  Proportional to the millisecond, because that is how the runner Price
  charges: its tiers are in raw meter units and Stripe applies no
  rounding to them. Only the final amount is resolved to whole cents.

  Not the same as costing whole minutes. Half a minute of runner time is
  worth half a minute's money, not nothing, and a figure that truncated
  to minutes would understate every bill that is not a round number.
  """
  def on_demand_cost_for_milliseconds(total_ms) when is_integer(total_ms) and total_ms >= 0 do
    Money.new(div(total_ms * @macos_on_demand_rate, 600_000), :USD)
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
    Money.new(div(minutes * @macos_on_demand_rate, 10), :USD)
  end

  @doc """
  Bills `account` for `minutes` of prepaid runner time.

  Creates a *pending* Stripe invoice item rather than its own invoice,
  so the charge rides along on the customer's next ordinary monthly
  bill instead of arriving as a separate one. Stripe sweeps pending
  items onto the next invoice it generates; nothing here has to know
  when the period closes.

  The credit is not granted now. It is granted when that invoice is
  paid, by `grant_for_paid_invoice/1`, so credit never exists ahead of
  the money behind it.

  An account with no subscription never has an invoice generated, so a
  pending item on one would sit unbilled indefinitely. Callers should
  check before offering this.
  """
  def bill_prepaid_minutes(%Account{customer_id: customer_id}, minutes, opts \\ [])
      when is_binary(customer_id) and is_integer(minutes) and minutes > 0 do
    quote = quote_minutes(minutes)
    platforms = Keyword.get(opts, :platforms, @platforms)

    with {:ok, item} <-
           Stripe.Invoiceitem.create(%{
             customer: customer_id,
             amount: quote.invoiced.amount,
             currency: "usd",
             description: "Prepaid runner minutes (#{minutes} on macOS 6 vCPU / 14 GB)",
             metadata: %{@marker_key => Enum.map_join(platforms, ",", &to_string/1)}
           }),
         {:ok, _grant} <- grant_billed_item(customer_id, item, quote, platforms) do
      {:ok, item}
    end
  end

  @doc """
  Sets the account's prepaid minutes to `minutes`, replacing whatever it
  holds rather than adding to it.

  Setting is not adding. The account ends up holding the number given,
  as a single grant, so an operator correcting a figure types the figure
  they want rather than the difference from one they have to work out.

  Replacing means withdrawing what is there: the grant is voided and the
  charge behind it deleted, which is only honest while that charge is
  still pending. A grant the customer has already been invoiced for is
  refused with `{:error, {:already_invoiced, item_id}}` — taking those
  minutes back needs a refund, which belongs in Stripe rather than
  behind a button here.

  `0` clears the balance and bills nothing.
  """
  def set_minutes(account, minutes, opts \\ [])

  def set_minutes(%Account{customer_id: customer_id} = account, minutes, opts)
      when is_binary(customer_id) and is_integer(minutes) and minutes >= 0 do
    with {:ok, grants} <- CreditGrants.list_for_customer(customer_id),
         held = Enum.filter(grants, &live_runner_credit?/1),
         {:ok, items} <- withdrawable_items(held),
         :ok <- withdraw(held, items) do
      result = if minutes > 0, do: bill_prepaid_minutes(account, minutes, opts), else: {:ok, :cleared}

      refresh_balance(customer_id)
      result
    end
  end

  @doc """
  Re-reads the balance and replaces the cached copy with it.

  Callers that have just changed the grants need this: `balance/2` is
  cached for minutes, so without it the next read serves the figure from
  before the change and the operator sees nothing happen.
  """
  def refresh_balance(customer_id) when is_binary(customer_id) do
    balance = fetch_balance(customer_id)

    if balance do
      KeyValueStore.put(balance_cache_key(customer_id), balance, ttl: @balance_cache_ttl)
    end

    balance
  end

  # Every held grant is checked before any of them is withdrawn, so a
  # set that cannot go through leaves the account exactly as it was
  # rather than half-emptied.
  defp withdrawable_items(grants) do
    Enum.reduce_while(grants, {:ok, []}, fn grant, {:ok, acc} ->
      item_id = grant_metadata(grant, @line_key)

      cond do
        is_nil(item_id) ->
          {:halt, {:error, {:not_withdrawable, grant_id(grant)}}}

        # Granted from a paid invoice, so the money is in.
        not is_nil(grant_metadata(grant, @invoice_key)) ->
          {:halt, {:error, {:already_invoiced, item_id}}}

        true ->
          case Stripe.Invoiceitem.retrieve(item_id) do
            {:ok, %{invoice: nil}} -> {:cont, {:ok, [item_id | acc]}}
            {:ok, _invoiced} -> {:halt, {:error, {:already_invoiced, item_id}}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
  end

  defp withdraw(grants, item_ids) do
    with :ok <- each_ok(item_ids, &Stripe.Invoiceitem.delete/1) do
      each_ok(grants, fn grant -> CreditGrants.void(grant_id(grant)) end)
    end
  end

  defp each_ok(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp grant_id(grant), do: Map.get(grant, :id) || Map.get(grant, "id")

  # The minutes are granted here rather than on `invoice.paid`, so the
  # account can spend them the moment they are sold. The charge still
  # rides the next monthly bill.
  #
  # Failing to grant returns the error rather than swallowing it: the
  # charge is already on the customer, and leaving no grant for the item
  # means `grant_for_paid_invoice/1` issues it when the invoice is paid,
  # which is the behaviour this replaced.
  defp grant_billed_item(customer_id, item, quote, platforms) do
    with {:ok, price_ids} <- price_ids(platforms) do
      CreditGrants.create(%{
        customer_id: customer_id,
        amount_cents: quote.granted.amount,
        currency: "usd",
        price_ids: price_ids,
        category: "paid",
        name: "Prepaid runner credit",
        expires_at: expires_at(customer_id),
        priority: @prepaid_priority,
        metadata: %{
          @kind_key => "prepaid",
          @line_key => item.id,
          @paid_cents_key => to_string(quote.invoiced.amount),
          @granted_ratio_key => to_string(quote.funding_ratio_bp)
        },
        idempotency_key: "runner-prepaid-item-#{item.id}"
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
    # Versioned: the cached value is a map this module shapes, so a
    # deploy that changes that shape would otherwise serve stale entries
    # to new code until the TTL lapsed. Bump on any shape change.
    cache_key = balance_cache_key(customer_id)

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

  # Versioned: the cached value is a map this module shapes, so a deploy
  # that changes that shape would otherwise serve stale entries to new
  # code until the TTL lapsed. Bump on any shape change.
  defp balance_cache_key(customer_id), do: [:runner_prepaid_balance, :v2, customer_id]

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

    %{
      available: Money.new(total, currency),
      # What was bought, which does not move as it is spent. The balance
      # answers "what is left"; this answers "what was purchased", and a
      # reader checking their entitlement wants the second.
      granted: Money.new(granted, currency),
      granted_minutes: minutes_for(granted),
      expires_at: grants |> Enum.map(& &1.expires_at) |> Enum.reject(&is_nil/1) |> Enum.min(DateTime, fn -> nil end),
      grants: grants
    }
  end

  # Credit is spent at the gross on-demand rate, so that rate is what
  # turns an amount of money into the minutes it buys on the baseline
  # machine.
  defp minutes_for(cents), do: div(cents * 10, @macos_on_demand_rate)

  # Minutes belong to the month they were bought for and do not roll
  # over, so the grant dies with the billing period the invoice paid
  # for — capped at a month, because runner items ride the account's own
  # subscription and an annual enterprise term reports a year-long
  # period. Dating a grant from that would hand each of those accounts a
  # year of minutes to bank. An account Stripe reports no period for
  # still has to get what it paid for, and a month keeps that promise on
  # the same footing.
  defp expires_at(customer_id) do
    monthly = DateTime.shift(DateTime.utc_now(), month: 1)

    with {:ok, account} <- Accounts.get_account_from_customer_id(customer_id),
         {_period_start, period_end} <- Billing.current_billing_period(account) do
      Enum.min([period_end, monthly], DateTime)
    else
      _ -> monthly
    end
  end

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

  defp invoice_currency(invoice) do
    case Map.get(invoice, :currency) do
      currency when is_binary(currency) and currency != "" -> currency
      _ -> "usd"
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
