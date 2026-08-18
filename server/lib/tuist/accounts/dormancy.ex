defmodule Tuist.Accounts.Dormancy do
  @moduledoc """
  Retirement of dormant workforce user IDs.

  Implements the inactivity thresholds in the Access control policy:
  disable at 180 days without authenticating, scrub the identity at 365.
  The scope is deliberately narrow — only Tuist operator accounts,
  identified by the operator email domain — because the control this
  satisfies is a workforce access-lifecycle control. Customer accounts are
  deprovisioned by their own identity provider through SCIM, which is both
  faster and their call to make, so they are never touched here.

  ## Why "scrub" and not "delete"

  The control asks for the *user ID* to be deleted, not the user's data.
  `Tuist.Accounts.delete_user/1` is a hard cascading delete that takes the
  account, its projects, and its command events with it, which would destroy
  the very audit trail an auditor expects to still be there. Instead
  `scrub/1` removes every credential and identifier that could authenticate
  the account — password, legacy CLI token, OAuth identities, sessions, and
  the email address — leaving the row as a tombstone that keeps referential
  integrity for historical records. Nothing can log in as a scrubbed user.

  ## Surviving an interrupted run

  The sweep is restartable rather than transactional. Each account is
  actioned on its own, and a run that dies part way through leaves the
  accounts it already handled in their new state. The next run re-queries, so
  finished work simply does not come back: a disabled account is no longer a
  disable candidate, and a scrubbed one drops out of the operator domain
  entirely. Oban's Lifeline plugin returns the orphaned job to the queue, so
  nothing has to be re-driven by hand.

  That restartability is why the six month checkpoint before scrubbing is
  anchored to `disabled_at` and not to `active`. "Currently disabled" is a
  state a crashed run can produce minutes earlier, which would let the very
  next attempt scrub an account it had only just disabled. A timestamp cannot
  be manufactured that way. The corollary is that re-enabling an account must
  clear `disabled_at` along with `active`. There is no re-enable path in the
  codebase today, but a stale timestamp left behind by one would let a later
  disablement inherit a checkpoint it never served.

  Each run also caps how many accounts it actions per threshold and reports
  whether more are waiting, so a single run does a bounded amount of work and
  the next one picks up the remainder.

  ## Accounts with no recorded activity

  `last_sign_in_at` was only populated from the point
  `Tuist.Accounts.touch_last_sign_in/1` shipped, so accounts that have not
  authenticated since then carry `nil`. Those are reported by `sweep/1` under
  `:unknown_activity` and never actioned automatically: treating "no data" as
  "infinitely dormant" would disable every operator on the first run. They are
  picked up by the quarterly manual inactivity check until natural traffic
  fills the column in.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset
  alias Tuist.Accounts.Oauth2Identity
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserToken
  alias Tuist.Environment
  alias Tuist.Repo

  require Logger

  @disable_after_days 180
  @scrub_after_days 365
  @disabled_grace_days 180
  @max_actions_per_run 100
  @tombstone_domain "invalid"

  def disable_after_days, do: @disable_after_days
  def scrub_after_days, do: @scrub_after_days
  def disabled_grace_days, do: @disabled_grace_days
  def max_actions_per_run, do: @max_actions_per_run

  @doc """
  Applies both inactivity thresholds and returns what was actioned.

  The return value is the evidence record for the control: it names every
  account disabled and scrubbed on this pass, plus the accounts that could
  not be assessed. Callers are expected to log or persist it.
  """
  def sweep(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &Tuist.Time.naive_utc_now/0)
    domain = Keyword.get_lazy(opts, :operator_email_domain, &Environment.operator_email_domain/0)
    limit = Keyword.get(opts, :limit, @max_actions_per_run)

    # Both candidate sets are resolved before anything is mutated. Disabling
    # first would flip accounts to `active: false` and hand them straight to
    # the scrub query in the same pass. The `disabled_at` gate below already
    # rules that out, but ordering the reads this way means the guarantee does
    # not rest on a single condition.
    disable_candidates = list_disable_candidates(now, domain, limit)
    scrub_candidates = list_scrub_candidates(now, domain, limit)

    disabled = Enum.map(disable_candidates, &disable(&1, now))
    scrubbed = Enum.map(scrub_candidates, &scrub/1)
    clock_started = Enum.map(list_disabled_without_clock(domain, limit), &start_disabled_clock(&1, now))
    unknown = list_unknown_activity(domain)

    result = %{
      disabled: Enum.map(disabled, & &1.id),
      scrubbed: Enum.map(scrubbed, & &1.id),
      clock_started: Enum.map(clock_started, & &1.id),
      unknown_activity: Enum.map(unknown, & &1.id),
      more_pending: length(disable_candidates) == limit or length(scrub_candidates) == limit
    }

    log_sweep(result)

    result
  end

  @doc """
  Operator accounts that are still active but have not authenticated for
  #{@disable_after_days} days.
  """
  def list_disable_candidates(now, domain, limit \\ @max_actions_per_run) do
    Repo.all(
      from(u in operator_scope(domain),
        where: u.active == true,
        where: not is_nil(u.last_sign_in_at),
        where: u.last_sign_in_at <= ^cutoff(now, @disable_after_days),
        limit: ^limit
      )
    )
  end

  @doc """
  Operator accounts eligible for identity scrubbing: inactive for
  #{@scrub_after_days} days, and disabled for at least
  #{@disabled_grace_days} days.

  The second condition is the reversible checkpoint. Someone on extended
  leave finds their account disabled and can ask for it back long before
  anything irreversible happens to it.

  It is deliberately measured from `disabled_at` rather than from the
  `active` flag. A run that dies after disabling an account leaves it
  disabled, so an `active`-based check would let the retry minutes later
  treat that account as having served its checkpoint and scrub it. Accounts
  disabled before this column existed, or disabled through some other path,
  carry no timestamp and are excluded until `start_disabled_clock/2` gives
  them one.
  """
  def list_scrub_candidates(now, domain, limit \\ @max_actions_per_run) do
    Repo.all(
      from(u in operator_scope(domain),
        where: u.active == false,
        where: not is_nil(u.last_sign_in_at),
        where: u.last_sign_in_at <= ^cutoff(now, @scrub_after_days),
        where: not is_nil(u.disabled_at),
        where: u.disabled_at <= ^utc_cutoff(now, @disabled_grace_days),
        limit: ^limit
      )
    )
  end

  @doc """
  Disabled operator accounts with no record of when they were disabled.

  Nothing is scrubbed on a missing timestamp, so these would otherwise sit
  outside the control forever. `start_disabled_clock/2` stamps them, which
  starts the checkpoint from the moment we first observed the account
  disabled rather than inventing a date we cannot support.
  """
  def list_disabled_without_clock(domain, limit \\ @max_actions_per_run) do
    Repo.all(
      from(u in operator_scope(domain),
        where: u.active == false,
        where: is_nil(u.disabled_at),
        limit: ^limit
      )
    )
  end

  @doc """
  Operator accounts with no recorded authentication, which cannot be
  assessed against either threshold.
  """
  def list_unknown_activity(domain) do
    Repo.all(from(u in operator_scope(domain), where: is_nil(u.last_sign_in_at)))
  end

  @doc """
  Suspends a user ID. Reversible: re-enabling goes through the normal access
  request process.

  Stamping `disabled_at` is what starts the checkpoint before the account
  becomes eligible for scrubbing.
  """
  def disable(%User{} = user, now \\ nil) do
    {:ok, user} =
      user
      |> Changeset.change(active: false, disabled_at: as_utc(now))
      |> Repo.update()

    revoke_sessions(user)

    user
  end

  @doc """
  Records that an already-disabled account is disabled, without changing its
  state, so the scrubbing checkpoint has a defined start.
  """
  def start_disabled_clock(%User{} = user, now \\ nil) do
    {:ok, user} =
      user
      |> Changeset.change(disabled_at: as_utc(now))
      |> Repo.update()

    user
  end

  @doc """
  Removes every credential and identifier that could authenticate the user,
  leaving a tombstone row so historical records keep their foreign keys.
  """
  def scrub(%User{} = user) do
    {:ok, scrubbed} =
      Repo.transaction(fn ->
        revoke_sessions(user)
        Repo.delete_all(from(o in Oauth2Identity, where: o.user_id == ^user.id))

        {:ok, scrubbed} =
          user
          |> Changeset.change(
            active: false,
            email: tombstone_email(user),
            encrypted_password: "",
            token: tombstone_token()
          )
          |> Repo.update()

        scrubbed
      end)

    scrubbed
  end

  defp operator_scope(domain) do
    # Anyone holding an address on the operator domain is workforce, so the
    # filter is deliberately broader than `Accounts.tuist_operator?/1`, which
    # additionally proves Google Workspace membership before granting
    # privileges. Here the safe direction is to catch more staff accounts,
    # not fewer. Already-scrubbed rows fall out for free: their tombstone
    # address is on `.invalid`, so it no longer matches the operator domain.
    suffix = "%@" <> domain

    from(u in User,
      where: like(u.email, ^suffix),
      order_by: [asc: u.id]
    )
  end

  defp cutoff(now, days), do: NaiveDateTime.add(now, -days * 24 * 60 * 60, :second)

  defp utc_cutoff(now, days), do: now |> cutoff(days) |> as_utc()

  # The sweep's clock is a NaiveDateTime so it can be injected in tests, while
  # `disabled_at` is stored with a zone. Both readings come from the same
  # instant rather than each function calling the clock again.
  defp as_utc(nil), do: as_utc(Tuist.Time.naive_utc_now())

  defp as_utc(%NaiveDateTime{} = naive) do
    naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)
  end

  defp as_utc(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)

  defp revoke_sessions(%User{id: id}) do
    Repo.delete_all(from(t in UserToken, where: t.user_id == ^id))
  end

  defp tombstone_email(%User{id: id}), do: "deleted-user-#{id}@#{@tombstone_domain}"

  defp tombstone_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp log_sweep(%{disabled: [], scrubbed: [], clock_started: [], unknown_activity: []}), do: :ok

  defp log_sweep(result) do
    Logger.info("dormant operator account sweep",
      disabled_user_ids: result.disabled,
      scrubbed_user_ids: result.scrubbed,
      disabled_clock_started_user_ids: result.clock_started,
      unassessable_user_ids: result.unknown_activity,
      # A run that fills its window leaves work behind. Saying so keeps a
      # truncated sweep from reading like a complete one.
      more_pending: result.more_pending
    )
  end
end
