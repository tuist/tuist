defmodule Atlas.GTM.DynamicAudience do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.IncidentContact
  alias Atlas.Accounts.Term
  alias Atlas.GTM.Audience
  alias Atlas.GTM.AudienceMembership
  alias Atlas.GTM.Subscriber
  alias Atlas.Repo

  @default_page_size 25
  @max_page_size 100

  @doc """
  Finds the account contacts that currently match an audience's saved rules.

  Contacts are deliberately resolved when the audience is read or sent to,
  rather than copied into memberships. That keeps a dynamic audience current
  when an account's lifecycle, contract, or contacts change.
  """
  def contacts(%Audience{} = audience) do
    contacts =
      audience
      |> contacts_query()
      |> preload([:account])
      |> Repo.all()
      |> maybe_limit_contacts_per_account(audience)
      |> unique_contacts()

    Enum.sort_by(contacts, fn contact -> {contact.full_name, contact.email} end)
  end

  def contacts_count(%Audience{} = audience) do
    audience
    |> contacts()
    |> length()
  end

  @doc """
  Returns virtual memberships for display. Flop cannot paginate this source:
  contacts may be shared by more than one account and must be de-duplicated by
  email before slicing the result.
  """
  def list_memberships(%Audience{} = audience, opts \\ []) do
    query = Keyword.get(opts, :query)
    page = normalized_page(Keyword.get(opts, :page))
    page_size = page_size(Keyword.get(opts, :page_size))

    memberships =
      audience
      |> contacts()
      |> maybe_search(query)
      |> Enum.map(&virtual_membership(audience, &1))

    total_count = length(memberships)

    {Enum.slice(memberships, (page - 1) * page_size, page_size),
     %{
       current_page: page,
       page_size: page_size,
       total_count: total_count,
       total_pages: total_pages(total_count, page_size),
       has_next_page?: page * page_size < total_count,
       has_previous_page?: page > 1
     }}
  end

  def matches_subscriber?(%Audience{} = audience, %Subscriber{email: email}) when is_binary(email) do
    normalized_email = String.downcase(email)

    Enum.any?(contacts(audience), fn contact ->
      String.downcase(contact.email) == normalized_email
    end)
  end

  def matches_subscriber?(_audience, _subscriber), do: false

  defp contacts_query(%Audience{} = audience) do
    case recipient_source(audience) do
      "incident_contacts" -> incident_contacts_query(audience)
      _other -> account_contacts_query(audience)
    end
  end

  defp account_contacts_query(%Audience{} = audience) do
    from(contact in Contact,
      join: account in Account,
      as: :account,
      on: contact.account_id == account.id,
      where: not is_nil(contact.email),
      where: is_nil(account.not_an_account_at),
      where: account.segment == ^account_segment(audience),
      where: is_nil(account.status) or account.status != "churned"
    )
    |> maybe_filter_self_hosted(audience)
  end

  defp incident_contacts_query(%Audience{} = audience) do
    from(contact in IncidentContact,
      join: account in Account,
      as: :account,
      on: contact.account_id == account.id,
      where: not is_nil(contact.email),
      where: is_nil(account.not_an_account_at),
      where: account.segment == ^account_segment(audience),
      where: is_nil(account.status) or account.status != "churned"
    )
    |> maybe_filter_self_hosted(audience)
  end

  defp maybe_filter_self_hosted(query, audience) do
    case hosting(audience) do
      "self_hosted" -> active_self_hosted_account(query)
      _other -> query
    end
  end

  defp active_self_hosted_account(query) do
    today = Date.utc_today()

    term =
      from(term in Term,
        where: term.account_id == parent_as(:account).id,
        where: term.on_premise == true,
        where: term.start_date <= ^today,
        where: is_nil(term.end_date) or term.end_date >= ^today,
        select: 1
      )

    where(
      query,
      [account: account],
      account.hosting == "self_hosted" or (account.hosting == "unknown" and exists(term))
    )
  end

  defp account_segment(%Audience{rules: rules}) when is_map(rules) do
    rules
    |> Map.get("account_segment", Map.get(rules, :account_segment, "customer"))
    |> to_string()
  end

  defp account_segment(_audience), do: "customer"

  defp hosting(%Audience{rules: rules}) when is_map(rules) do
    rules
    |> Map.get("hosting", Map.get(rules, :hosting, "all"))
    |> to_string()
  end

  defp hosting(_audience), do: "all"

  defp recipient_source(%Audience{rules: rules}) when is_map(rules) do
    rules
    |> Map.get("recipient_source", Map.get(rules, :recipient_source, "account_contacts"))
    |> to_string()
  end

  defp recipient_source(_audience), do: "account_contacts"

  defp contacts_per_account(%Audience{rules: rules}) when is_map(rules) do
    rules
    |> Map.get("contacts_per_account", Map.get(rules, :contacts_per_account, "all"))
    |> to_string()
  end

  defp contacts_per_account(_audience), do: "all"

  # Account contacts do not currently carry a primary-contact designation. For
  # one-per-account audiences, select the alphabetically first email so a
  # contact is always chosen deterministically until a primary contact exists.
  defp maybe_limit_contacts_per_account(contacts, audience) do
    if recipient_source(audience) == "account_contacts" and contacts_per_account(audience) == "one" do
      contacts
      |> Enum.sort_by(fn contact -> {contact.account_id, String.downcase(contact.email), contact.id} end)
      |> Enum.uniq_by(& &1.account_id)
    else
      contacts
    end
  end

  defp unique_contacts(contacts) do
    Enum.uniq_by(contacts, fn contact -> String.downcase(contact.email) end)
  end

  defp maybe_search(contacts, query) when is_binary(query) do
    case String.trim(query) do
      "" -> contacts
      query -> Enum.filter(contacts, &contact_matches?(&1, query))
    end
  end

  defp maybe_search(contacts, _query), do: contacts

  defp contact_matches?(contact, query) do
    normalized_query = String.downcase(query)

    [contact.full_name, contact.email, contact.account.name]
    |> Enum.any?(fn value ->
      value
      |> to_string()
      |> String.downcase()
      |> String.contains?(normalized_query)
    end)
  end

  defp virtual_membership(audience, contact) do
    subscriber_id = "dynamic-contact-#{contact.id}"

    %AudienceMembership{
      id: "dynamic-membership-#{contact.id}",
      audience_id: audience.id,
      subscriber_id: subscriber_id,
      status: "subscribed",
      subscriber: %Subscriber{
        id: subscriber_id,
        email: contact.email,
        first_name: contact_name(contact),
        source: contact_source(contact),
        user_group: contact.account.name,
        status: "subscribed"
      }
    }
  end

  defp normalized_page(page) when is_integer(page) and page > 0, do: page
  defp normalized_page(_page), do: 1

  defp page_size(value) when is_integer(value) and value > 0, do: min(value, @max_page_size)
  defp page_size(_value), do: @default_page_size

  defp total_pages(0, _page_size), do: 1
  defp total_pages(total_count, page_size), do: ceil(total_count / page_size)

  defp contact_name(%IncidentContact{full_name: nil, role: role}), do: role || "Incident contact"
  defp contact_name(contact), do: contact.full_name

  defp contact_source(%IncidentContact{}), do: "contract"
  defp contact_source(%Contact{}), do: "account contact"
end
