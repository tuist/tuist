defmodule Atlas.Nudges.Signals.InvitedTeammatesSso do
  @moduledoc """
  Fires when a paying customer's Tuist organization has grown past
  `@threshold` distinct members and SSO is not yet configured. The pitch
  is to walk the operator through setting SSO up.

  Data lives on the Tuist server, so this signal reads through
  `Atlas.TuistServer.query/2` (the internal read-only proxy) rather than
  Atlas's own database.
  """

  @behaviour Atlas.Nudges.Signal

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Nudges
  alias Atlas.Nudges.Proposal
  alias Atlas.Repo
  alias Atlas.TuistServer

  @signal_name "invited_teammates_sso"
  @threshold 5
  @handle_pattern ~r/\A[a-zA-Z0-9._-]+\z/

  @impl true
  def name, do: @signal_name

  @impl true
  def candidate_account_ids do
    Account
    |> where([a], not is_nil(a.plan_tier) and a.plan_tier != "free")
    |> where([a], is_nil(a.not_an_account_at))
    |> select([a], a.id)
    |> Repo.all()
  end

  @impl true
  def evaluate(%Account{} = account) do
    with {:ok, handle} <- primary_handle(account),
         {:ok, %{organization_id: org_id, member_count: member_count, sso_configured: sso_configured}} <-
           fetch_org_facts(handle),
         true <- present?(org_id),
         false <- sso_configured,
         true <- member_count >= @threshold do
      dispatch(account, handle, org_id, member_count)
    else
      false ->
        maybe_close_episode(account)

      {:error, _reason} ->
        :skip

      :error ->
        :skip
    end
  end

  defp dispatch(account, handle, org_id, member_count) do
    evidence = %{
      "member_count" => member_count,
      "threshold" => @threshold,
      "tuist_organization_id" => org_id
    }

    case Nudges.open_or_touch_episode(account, @signal_name, evidence) do
      {:existing, _episode} ->
        :skip

      {:opened, episode} ->
        {:ok, build_proposal(account, handle, episode, member_count, evidence)}

      {:error, _reason} ->
        :skip
    end
  end

  defp build_proposal(account, handle, episode, member_count, evidence) do
    contact = Nudges.select_contact_for(account)

    %Proposal{
      dedup_key: "#{@signal_name}:#{episode.id}",
      title: "#{account_label(account, handle)}: SSO conversation (#{member_count} members)",
      rationale:
        "#{account_label(account, handle)}'s Tuist organization now has #{member_count} members " <>
          "and does not have SSO configured. A quick call to walk through Okta/Google/OAuth2 setup is likely welcome.",
      evidence: evidence,
      draft_subject: "SSO setup for #{account_label(account, handle)}",
      draft_body: draft_body(account, handle, member_count),
      contact_id: contact && contact.id,
      severity: "normal",
      expires_in_days: 14
    }
  end

  defp draft_body(account, handle, member_count) do
    """
    Hi,

    I noticed the #{account_label(account, handle)} Tuist organization has grown to #{member_count} members. \
    At that size we usually recommend teams set up SSO so onboarding and offboarding stay clean and audit-friendly.

    Tuist supports Okta, Google, and generic OAuth2, and I'd be happy to walk you through the setup in a short call. \
    Would that be useful?

    Best,
    """
  end

  defp maybe_close_episode(%Account{} = account) do
    _ = Nudges.close_episode(account, @signal_name)
    :skip
  end

  defp primary_handle(%Account{id: account_id}) do
    case Repo.one(
           from h in AccountHandle,
             where: h.account_id == ^account_id,
             order_by: [asc: h.inserted_at],
             limit: 1
         ) do
      %AccountHandle{handle: handle} when is_binary(handle) ->
        if Regex.match?(@handle_pattern, handle), do: {:ok, handle}, else: :error

      _other ->
        :error
    end
  end

  defp fetch_org_facts(handle) do
    sql = """
    SELECT o.id AS organization_id,
           o.sso_provider IS NOT NULL AS sso_configured,
           (SELECT count(DISTINCT ur.user_id)
              FROM users_roles ur
              JOIN roles r ON r.id = ur.role_id
             WHERE r.resource_type = 'Organization'
               AND r.resource_id = o.id) AS member_count
    FROM accounts a
    JOIN organizations o ON o.id = a.organization_id
    WHERE a.name = '#{escape(handle)}'
    """

    case TuistServer.query(sql, limit: 1) do
      {:ok, %{"rows" => [row | _]}} ->
        {:ok,
         %{
           organization_id: Map.get(row, "organization_id"),
           sso_configured: Map.get(row, "sso_configured") == true,
           member_count: to_integer(Map.get(row, "member_count"))
         }}

      {:ok, %{"rows" => []}} ->
        {:error, :not_an_organization}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp account_label(%Account{name: name}, _handle) when is_binary(name) and name != "", do: name
  defp account_label(_account, handle), do: handle

  defp escape(handle), do: String.replace(handle, "'", "''")

  defp present?(value) when is_integer(value), do: true
  defp present?(value) when is_binary(value) and value != "", do: true
  defp present?(_value), do: false

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: value |> Integer.parse() |> elem_or_zero()
  defp to_integer(_value), do: 0

  defp elem_or_zero({int, _rest}), do: int
  defp elem_or_zero(:error), do: 0
end
