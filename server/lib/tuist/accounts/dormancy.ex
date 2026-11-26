defmodule Tuist.Accounts.Dormancy do
  @moduledoc """
  Retirement of dormant workforce user IDs.

  Implements the inactivity thresholds in the Access control policy:
  disable at 180 days without authenticating, scrub the identity at 365.
  The scope is workforce accounts only, because the control this satisfies
  is a workforce access-lifecycle control:

    * accounts on the operator email domain, and
    * every member of an organization Tuist owns
      (`Tuist.Environment.internal_organization_handles/0`), whatever their
      email domain. Bot, test and contractor accounts live there, and a
      dormant one without a second factor is exactly the entry point of
      Bitrise's November 2026 incident.

  Customer accounts are deprovisioned by their own identity provider through
  SCIM, which is both faster and their call to make, so they are never
  touched here.

  ## Why "scrub" and not "delete"

  The control asks for the *user ID* to be deleted, not the user's data.
  `Tuist.Accounts.delete_user/1` is a hard cascading delete that takes the
  account, its projects, and its command events with it, which would destroy
  the very audit trail an auditor expects to still be there. Instead
  `scrub/1` removes every credential and identifier that could authenticate
  the account — password, OAuth identities, sessions, and
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
  authenticated since then carry `nil`. Treating "no data" as "infinitely
  dormant" would disable every such account on the first run, and ignoring
  them would leave a never-used bot account outside the control forever.

  Instead a `nil` is read as "last active no later than when tracking began,
  or when the account was created if that is later"
  (`activity_tracking_started_at/0`). Every authentication since tracking
  began writes the column, so an account still at `nil` provably has not
  authenticated since then. Such accounts age from that floor: the oldest
  ones reach the disable threshold 180 days after tracking began, and an
  account created and never used is disabled 180 days after its creation.
  `sweep/1` still lists them under `:unknown_activity` so the evidence record
  shows which accounts were judged on the floor rather than a sign-in.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.Oauth2Identity
  alias Tuist.Accounts.Role
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserRole
  alias Tuist.Accounts.UserToken
  alias Tuist.Environment
  alias Tuist.Repo

  require Logger

  @disable_after_days 180
  @scrub_after_days 365
  @disabled_grace_days 180
  @max_actions_per_run 100
  @tombstone_domain "invalid"
  # A margin after `touch_last_sign_in/1` shipped (commit 0153512ccc,
  # 2026-08-20) and reached production, so no account that authenticated
  # before it is mistaken for one that never did.
  @activity_tracking_started_at ~N[2026-09-01 00:00:00]

  def disable_after_days, do: @disable_after_days
  def scrub_after_days, do: @scrub_after_days
  def disabled_grace_days, do: @disabled_grace_days
  def max_actions_per_run, do: @max_actions_per_run
  def activity_tracking_started_at, do: @activity_tracking_started_at

  # The instant an account was last seen active: its recorded sign-in, or for
  # an account with none, the later of its creation and the start of tracking.
  # See "Accounts with no recorded activity" in the moduledoc.
  defmacrop last_activity(user) do
    floor = Macro.escape(@activity_tracking_started_at)

    quote do
      fragment(
        "COALESCE(?, GREATEST(?, ?))",
        unquote(user).last_sign_in_at,
        unquote(user).created_at,
        type(^unquote(floor), :naive_datetime)
      )
    end
  end

  @doc """
  Applies both inactivity thresholds and returns what was actioned.

  The return value is the evidence record for the control: it names every
  account disabled and scrubbed on this pass, plus the accounts that could
  not be assessed. Callers are expected to log or persist it.
  """
  def sweep(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &Tuist.Time.naive_utc_now/0)
    domain = Keyword.get_lazy(opts, :operator_email_domain, &Environment.operator_email_domain/0)

    handles =
      Keyword.get_lazy(opts, :internal_organization_handles, &Environment.internal_organization_handles/0)

    scope = {domain, handles}
    limit = Keyword.get(opts, :limit, @max_actions_per_run)

    # Both candidate sets are resolved before anything is mutated. Disabling
    # first would flip accounts to `active: false` and hand them straight to
    # the scrub query in the same pass. The `disabled_at` gate below already
    # rules that out, but ordering the reads this way means the guarantee does
    # not rest on a single condition.
    disable_candidates = list_disable_candidates(now, scope, limit)
    scrub_candidates = list_scrub_candidates(now, scope, limit)

    # Both the disable and the scrub re-assert eligibility in the WHERE clause
    # of the write itself, so a candidate that signs in between being selected
    # and being actioned is skipped rather than locked out. Selecting and then
    # writing unconditionally would let a sweep disable someone who came back
    # while it was running.
    clock_candidates = list_disabled_without_clock(scope, limit)

    disabled = Enum.flat_map(disable_candidates, &disable_if_still_dormant(&1, now))
    scrubbed = Enum.flat_map(scrub_candidates, &scrub_if_still_eligible(&1, now))
    clock_started = Enum.map(clock_candidates, &start_disabled_clock(&1, now))
    unknown = list_unknown_activity(scope)

    result = %{
      disabled: Enum.map(disabled, & &1.id),
      scrubbed: Enum.map(scrubbed, & &1.id),
      clock_started: Enum.map(clock_started, & &1.id),
      unknown_activity: Enum.map(unknown, & &1.id),
      more_pending:
        length(disable_candidates) == limit or length(scrub_candidates) == limit or
          length(clock_candidates) == limit
    }

    log_sweep(result)

    result
  end

  @doc """
  Workforce accounts that are still active but have not authenticated for
  #{@disable_after_days} days. `scope` is `{operator_email_domain,
  internal_organization_handles}`.
  """
  def list_disable_candidates(now, scope, limit \\ @max_actions_per_run) do
    Repo.all(
      from(u in workforce_scope(scope),
        where: u.active == true,
        where: last_activity(u) <= ^cutoff(now, @disable_after_days),
        limit: ^limit
      )
    )
  end

  @doc """
  Workforce accounts eligible for identity scrubbing: inactive for
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
  def list_scrub_candidates(now, scope, limit \\ @max_actions_per_run) do
    Repo.all(
      from(u in workforce_scope(scope),
        where: u.active == false,
        where: last_activity(u) <= ^cutoff(now, @scrub_after_days),
        where: not is_nil(u.disabled_at),
        where: u.disabled_at <= ^utc_cutoff(now, @disabled_grace_days),
        limit: ^limit
      )
    )
  end

  @doc """
  Disabled workforce accounts with no record of when they were disabled.

  Nothing is scrubbed on a missing timestamp, so these would otherwise sit
  outside the control forever. `start_disabled_clock/2` stamps them, which
  starts the checkpoint from the moment we first observed the account
  disabled rather than inventing a date we cannot support.
  """
  def list_disabled_without_clock(scope, limit \\ @max_actions_per_run) do
    Repo.all(
      from(u in workforce_scope(scope),
        where: u.active == false,
        where: is_nil(u.disabled_at),
        limit: ^limit
      )
    )
  end

  @doc """
  Workforce accounts with no recorded authentication, which are assessed
  against the activity-tracking floor rather than a sign-in.
  """
  def list_unknown_activity(scope) do
    Repo.all(from(u in workforce_scope(scope), where: is_nil(u.last_sign_in_at)))
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
            encrypted_password: ""
          )
          |> Repo.update()

        scrubbed
      end)

    scrubbed
  end

  # The sweep's writes re-assert the condition that selected the account, so
  # they are a no-op if it stopped being true after selection. Returns a list
  # so the caller can flat_map and drop a skipped account without a sentinel.
  defp disable_if_still_dormant(%User{} = user, now) do
    {count, _} =
      Repo.update_all(
        from(u in User,
          where: u.id == ^user.id,
          where: u.active == true,
          where: last_activity(u) <= ^cutoff(now, @disable_after_days)
        ),
        set: [active: false, disabled_at: as_utc(now), updated_at: naive(now)]
      )

    if count == 1 do
      revoke_sessions(user)
      [%{user | active: false}]
    else
      []
    end
  end

  # Same guarantee on the irreversible step, where it matters most. The
  # tombstone write carries every condition that made the account a candidate,
  # so an account that was re-enabled or that signed in after selection cannot
  # be scrubbed by a sweep already in flight.
  defp scrub_if_still_eligible(%User{} = user, now) do
    result =
      Repo.transaction(fn ->
        {count, _} =
          Repo.update_all(
            from(u in User,
              where: u.id == ^user.id,
              where: u.active == false,
              where: last_activity(u) <= ^cutoff(now, @scrub_after_days),
              where: not is_nil(u.disabled_at),
              where: u.disabled_at <= ^utc_cutoff(now, @disabled_grace_days)
            ),
            set: tombstone_attrs(user, now)
          )

        if count == 1 do
          revoke_sessions(user)
          Repo.delete_all(from(o in Oauth2Identity, where: o.user_id == ^user.id))
          user
        else
          Repo.rollback(:no_longer_eligible)
        end
      end)

    case result do
      {:ok, scrubbed} -> [scrubbed]
      {:error, :no_longer_eligible} -> []
    end
  end

  defp tombstone_attrs(%User{} = user, now) do
    [
      active: false,
      email: tombstone_email(user),
      encrypted_password: "",
      updated_at: naive(now)
    ]
  end

  defp naive(nil), do: NaiveDateTime.truncate(Tuist.Time.naive_utc_now(), :second)
  defp naive(%NaiveDateTime{} = now), do: NaiveDateTime.truncate(now, :second)

  defp workforce_scope({domain, handles}) do
    # Anyone holding an address on the operator domain is workforce, so the
    # filter is deliberately broader than `Accounts.tuist_operator?/1`, which
    # additionally proves Google Workspace membership before granting
    # privileges. Here the safe direction is to catch more staff accounts,
    # not fewer. So is anyone holding a role in an organization Tuist owns,
    # which is where bot, test and contractor accounts on other domains live.
    #
    # Scrubbed rows are excluded by their tombstone address. On the operator
    # domain that alone would do, but a scrubbed member of an internal
    # organization keeps its role row, so it has to be excluded explicitly.
    suffix = "%@" <> domain
    tombstone = "%@" <> @tombstone_domain

    internal_member_ids =
      from(ur in UserRole,
        join: r in Role,
        on: r.id == ur.role_id and r.resource_type == "Organization",
        join: a in Account,
        on: a.organization_id == r.resource_id,
        where: fragment("lower(?)", a.name) in ^handles,
        select: ur.user_id
      )

    from(u in User,
      where: like(u.email, ^suffix) or u.id in subquery(internal_member_ids),
      where: not like(u.email, ^tombstone),
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

  # Deleting the rows stops the next session lookup, but a LiveView socket that
  # is already connected holds its authenticated user in assigns and never
  # repeats that lookup, so it would keep working after the sweep disabled the
  # account. The tokens are collected before the delete so the same disconnect
  # the password reset flow performs can be broadcast for each one.
  defp revoke_sessions(%User{id: id}) do
    session_tokens =
      Repo.all(from(t in UserToken, where: t.user_id == ^id and t.context == "session"))

    Repo.delete_all(from(t in UserToken, where: t.user_id == ^id))

    # Published straight to the shared pubsub rather than through the endpoint,
    # which is what the endpoint does internally, because a `Tuist` module may
    # not reference `TuistWeb`. The payload matches what a LiveView's
    # disconnect listener expects.
    Enum.each(session_tokens, fn token ->
      topic = UserToken.live_socket_id(token)

      Phoenix.PubSub.broadcast(Tuist.PubSub, topic, %Phoenix.Socket.Broadcast{
        topic: topic,
        event: "disconnect",
        payload: %{}
      })
    end)
  end

  defp tombstone_email(%User{id: id}), do: "deleted-user-#{id}@#{@tombstone_domain}"

  defp log_sweep(%{disabled: [], scrubbed: [], clock_started: [], unknown_activity: []}), do: :ok

  defp log_sweep(result) do
    Logger.info("dormant workforce account sweep",
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
