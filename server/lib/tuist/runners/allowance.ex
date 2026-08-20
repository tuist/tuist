defmodule Tuist.Runners.Allowance do
  @moduledoc """
  The free monthly runner allowance, and whether an account may keep
  dispatching once it is spent.

  Every plan gets the same allowance, because it is a tier on the runner
  Price rather than a plan attribute: the first
  `free_monthly_minutes/0` baseline machine-minutes of each billing
  period cost nothing, and usage past that is charged at the standard
  rate. What differs by plan is whether exceeding it is *possible*.

  A paid plan can exceed it and be billed for the excess. A free account
  cannot: it has no subscription for the excess to land on, so without a
  cap its runner usage would be unbounded and unbillable. That is the
  one thing this module enforces.

  ## Why the cap is here and not in the Price

  Stripe can express the free tier but not refuse the work. The Price
  stops charging below the allowance; only dispatch can stop a job from
  running past it. The two have to agree, so
  `free_monthly_minutes/0` and the Price's first tier are the same
  number stated twice, and have to be changed together — the same
  hand-kept duplication `Tuist.Billing`'s `@unit_prices` carries.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.KeyValueStore
  alias Tuist.Runners.Billing, as: RunnerBilling

  # Must match the first tier of that environment's runner Price. The
  # default is the real allowance; staging lowers both together so the
  # cap and the paid tier can be reached without burning a hundred
  # minutes of real Mac time to get there. Lowering only this would move
  # the cap without moving the Price, so an account would be cut off
  # before it could ever reach the charged tier.
  @default_free_monthly_minutes 100

  # Dispatch is a hot path and this adds an aggregate over
  # `runner_sessions` to it, so the answer is cached briefly. The cost is
  # that an account can overshoot by whatever it starts inside the TTL;
  # the cap is a spend control, not a hard quota, and bounded overshoot
  # is the right trade against querying on every claim.
  @usage_cache_ttl to_timeout(second: 30)

  @doc """
  Baseline machine-minutes every account gets free each billing period.
  """
  def free_monthly_minutes do
    Application.get_env(:tuist, :runner_free_monthly_minutes, @default_free_monthly_minutes)
  end

  @doc """
  True when `account` must not be given another runner job.

  Only ever true for an account with no paid plan. A paid account is
  never blocked: going past the allowance is exactly what it is billed
  for.
  """
  def exhausted?(%Account{} = account) do
    case Billing.effective_plan(account) do
      :air -> minutes_used(account) >= free_monthly_minutes()
      _plan -> false
    end
  end

  @doc """
  Baseline machine-minutes `account` has used in the current calendar
  month, truncated the way the Price rounds.

  Calendar month rather than the Stripe billing period because the
  accounts this gates have no subscription, so there is no period to
  read. For a paid account the figure is only ever advisory: nothing is
  blocked on it.
  """
  def minutes_used(%Account{id: account_id}) do
    KeyValueStore.get_or_update(
      [:runner_allowance, account_id],
      [ttl: @usage_cache_ttl],
      fn ->
        now = DateTime.utc_now()
        month_start = %{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 6}}

        account_id
        |> RunnerBilling.compute_milliseconds(month_start, now)
        |> div(60_000)
      end
    )
  end

  @doc """
  Minutes left on `account`'s allowance, floored at zero.
  """
  def minutes_remaining(%Account{} = account) do
    max(free_monthly_minutes() - minutes_used(account), 0)
  end
end
