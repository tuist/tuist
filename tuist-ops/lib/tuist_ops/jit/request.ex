defmodule TuistOps.JIT.Request do
  @moduledoc """
  A Slack-side elevation request: someone asked to elevate to a
  cluster env for a bounded session, and the approval lifecycle
  for that ask. Goes through:
  `pending → approved | denied | expired | failed | cancelled`.

  An approved request spawns a `TuistOps.JIT.Elevation`; the request
  row is not touched after approval, the elevation owns the
  runtime state.

  Backed by [priv/repo/migrations/20260603120000_create_tailscale_jit_tables.exs](priv/repo/migrations/20260603120000_create_tailscale_jit_tables.exs).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias TuistOps.JIT.Policy

  @statuses ~w(pending approved denied expired failed cancelled)

  schema "tailscale_jit_requests" do
    field :requester_email, :string
    field :requester_slack_id, :string
    field :target_group, :string
    field :github_login, :string
    field :orb_thread_id, :string
    field :intent, :string
    field :ttl_seconds, :integer
    field :status, :string, default: "pending"
    field :slack_channel_id, :string
    field :slack_message_ts, :string
    field :approver_email, :string
    field :approver_slack_id, :string
    field :approved_at, :utc_datetime
    field :denied_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :failure_reason, :string
    field :atlas_approval_id, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a brand-new request, before any approval activity.
  `expires_at` here is the deadline by which a second human must
  approve in Slack (default 10 minutes); the runtime elevation TTL
  lives on the Elevation row instead.

  A request approved in Atlas carries `:atlas_approval_id` instead of
  the Slack fields, and is always an orb thread elevation. Orb thread
  elevations only come from Atlas, never from Slack.
  """
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :requester_email,
      :requester_slack_id,
      :target_group,
      :github_login,
      :orb_thread_id,
      :intent,
      :ttl_seconds,
      :slack_channel_id,
      :expires_at,
      :atlas_approval_id
    ])
    |> validate_required([:requester_email, :target_group, :intent, :ttl_seconds, :expires_at])
    |> validate_approval_channel()
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:ttl_seconds, greater_than: 0, less_than_or_equal_to: 3600)
    |> validate_length(:intent, min: 5, max: 500)
    |> validate_github_login()
    |> validate_orb_thread_id()
    |> unique_constraint(:atlas_approval_id)
  end

  defp validate_approval_channel(changeset) do
    if get_field(changeset, :atlas_approval_id) do
      validate_required(changeset, [:orb_thread_id])
    else
      changeset
      |> validate_required([:requester_slack_id, :slack_channel_id])
      |> validate_change(:orb_thread_id, fn _, _ ->
        [orb_thread_id: "needs an Atlas approval"]
      end)
    end
  end

  # GitHub logins: alphanumerics and single inner hyphens, max 39 chars.
  # Logins are case-insensitive, so they're stored downcased to keep the
  # one-active-elevation-per-login check exact.
  @github_login_format ~r/^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$/

  def github_login_format, do: @github_login_format

  defp validate_github_login(changeset) do
    if Policy.github_admin_group?(get_field(changeset, :target_group)) do
      changeset
      |> update_change(:github_login, &String.downcase/1)
      |> validate_required([:github_login])
      |> validate_format(:github_login, @github_login_format)
    else
      changeset
    end
  end

  # Amp thread IDs, as Atlas's `request_cluster_elevation` takes them
  # and as the Amp workload identity token's `thread_id` claim carries
  # them.
  @orb_thread_id_format ~r/^T-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

  def orb_thread_id?(value), do: is_binary(value) and Regex.match?(@orb_thread_id_format, value)

  # A thread elevation only means something for a cluster env.
  defp validate_orb_thread_id(changeset) do
    case get_field(changeset, :orb_thread_id) do
      nil ->
        changeset

      thread_id ->
        cond do
          not orb_thread_id?(thread_id) ->
            add_error(changeset, :orb_thread_id, "is not an Amp thread ID")

          is_nil(Policy.env_for(get_field(changeset, :target_group))) ->
            add_error(changeset, :orb_thread_id, "only applies to cluster elevations")

          true ->
            changeset
        end
    end
  end

  @doc """
  State-transition changeset. Caller picks the new status; this
  exists so transitions are explicit and the inclusion check stays
  in one place.
  """
  def transition_changeset(request, attrs) do
    request
    |> cast(attrs, [
      :status,
      :slack_message_ts,
      :approver_email,
      :approver_slack_id,
      :approved_at,
      :denied_at,
      :failure_reason
    ])
    |> validate_inclusion(:status, @statuses)
  end

  def statuses, do: @statuses
end
