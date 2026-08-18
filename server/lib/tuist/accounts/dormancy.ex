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
  @tombstone_domain "invalid"

  def disable_after_days, do: @disable_after_days
  def scrub_after_days, do: @scrub_after_days

  @doc """
  Applies both inactivity thresholds and returns what was actioned.

  The return value is the evidence record for the control: it names every
  account disabled and scrubbed on this pass, plus the accounts that could
  not be assessed. Callers are expected to log or persist it.
  """
  def sweep(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &Tuist.Time.naive_utc_now/0)
    domain = Keyword.get_lazy(opts, :operator_email_domain, &Environment.operator_email_domain/0)

    # Both candidate sets are resolved before anything is mutated. Disabling
    # first would flip accounts to `active: false` and hand them straight to
    # the scrub query in the same pass, so an account crossing both thresholds
    # would lose its credentials without ever sitting visibly disabled. The
    # first run after deployment is exactly when that would bite, because every
    # long-dormant account crosses both thresholds at once.
    disable_candidates = list_disable_candidates(now, domain)
    scrub_candidates = list_scrub_candidates(now, domain)

    disabled = Enum.map(disable_candidates, &disable/1)
    scrubbed = Enum.map(scrub_candidates, &scrub/1)
    unknown = list_unknown_activity(domain)

    result = %{
      disabled: Enum.map(disabled, & &1.id),
      scrubbed: Enum.map(scrubbed, & &1.id),
      unknown_activity: Enum.map(unknown, & &1.id)
    }

    log_sweep(result)

    result
  end

  @doc """
  Operator accounts that are still active but have not authenticated for
  #{@disable_after_days} days.
  """
  def list_disable_candidates(now, domain) do
    Repo.all(
      from(u in operator_scope(domain),
        where: u.active == true,
        where: not is_nil(u.last_sign_in_at),
        where: u.last_sign_in_at <= ^cutoff(now, @disable_after_days)
      )
    )
  end

  @doc """
  Operator accounts eligible for identity scrubbing: inactive for
  #{@scrub_after_days} days AND already disabled.

  Requiring the account to be disabled first means an identity is only ever
  destroyed after it has sat visibly disabled for roughly six months, which
  gives someone on extended leave an obvious, reversible checkpoint before
  anything irreversible happens.
  """
  def list_scrub_candidates(now, domain) do
    Repo.all(
      from(u in operator_scope(domain),
        where: u.active == false,
        where: not is_nil(u.last_sign_in_at),
        where: u.last_sign_in_at <= ^cutoff(now, @scrub_after_days)
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
  """
  def disable(%User{} = user) do
    {:ok, user} =
      user
      |> Changeset.change(active: false)
      |> Repo.update()

    revoke_sessions(user)

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

  defp revoke_sessions(%User{id: id}) do
    Repo.delete_all(from(t in UserToken, where: t.user_id == ^id))
  end

  defp tombstone_email(%User{id: id}), do: "deleted-user-#{id}@#{@tombstone_domain}"

  defp tombstone_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp log_sweep(%{disabled: [], scrubbed: [], unknown_activity: []}), do: :ok

  defp log_sweep(result) do
    Logger.info("dormant operator account sweep",
      disabled_user_ids: result.disabled,
      scrubbed_user_ids: result.scrubbed,
      unassessable_user_ids: result.unknown_activity
    )
  end
end
