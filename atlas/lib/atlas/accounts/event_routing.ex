defmodule Atlas.Accounts.EventRouting do
  @moduledoc """
  Shared account-routing helpers for external account events.
  """

  import Ecto.Query

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Accounts.Contact
  alias Atlas.Repo

  @doc """
  Finds an Atlas account matching any of the given email addresses.

  Filters out internal addresses, then tries contact email, account handle,
  and primary domain in that order.
  """
  def find_account(emails) when is_list(emails) do
    %{emails: filtered, domains: domains} = account_match_inputs(emails)

    find_by_contact_email(filtered, :account) ||
      find_by_account_handle(filtered, domains, :account) ||
      find_by_primary_domain(domains, :account)
  end

  @doc """
  Finds a non-account row matching any of the given email addresses.

  This is used by ingestion agents to stop before creating a new account for
  domains or handles that were explicitly marked as not accounts.
  """
  def find_non_account(emails) when is_list(emails) do
    %{emails: filtered, domains: domains} = account_match_inputs(emails)

    find_by_contact_email(filtered, :not_account) ||
      find_by_account_handle(filtered, domains, :not_account) ||
      find_by_primary_domain(domains, :not_account)
  end

  @doc """
  Returns all contacts for an account, ordered by name.
  """
  def list_account_contacts(account_id) do
    Contact
    |> where([contact], contact.account_id == ^account_id)
    |> order_by([contact], asc: contact.full_name)
    |> Repo.all()
  end

  @doc """
  Creates or updates an account discovered from an external event.

  If `"account_id"` is provided, only editable account fields are updated.
  Without an account ID, the account is matched by normalized primary domain
  or generated Granola account key before falling back to creation.
  """
  def upsert_account(params) when is_map(params) do
    attrs = account_attrs(params)

    case param(params, "account_id", :account_id) do
      account_id when is_binary(account_id) and account_id != "" ->
        update_account(account_id, attrs)

      _account_id ->
        create_or_update_account(attrs)
    end
  end

  @doc """
  Creates or updates a contact for an account, identified by `(account_id, email)`.

  Skips internal addresses. `params` keys: `"email"`, `"full_name"`,
  `"title"` (optional), `"notes"` (optional). Returns `{:ok, contact}`,
  `{:ok, :skipped}`, or `{:error, changeset}`.
  """
  def upsert_contact(account_id, params) do
    email = normalize_email(params["email"])

    cond do
      is_nil(email) ->
        {:ok, :skipped}

      internal_email?(email) ->
        {:ok, :skipped}

      true ->
        attrs = Map.take(params, ["full_name", "title", "notes"])

        account = Repo.get!(Account, account_id)

        if Account.not_account?(account) do
          {:error, :not_account}
        else
          case Repo.get_by(Contact, account_id: account_id, email: email) do
            nil -> Accounts.create_contact(account, Map.put(attrs, "email", email))
            contact -> Accounts.update_contact(contact, attrs)
          end
        end
    end
  end

  def internal_email?(email) do
    domain = email_domain(email)
    allowed_domain = Application.get_env(:atlas, :allowed_email_domain)

    domain in Enum.reject([allowed_domain, "atlas.tuist.dev"], &is_nil/1)
  end

  def email_domain(email) when is_binary(email) do
    case String.split(String.downcase(email), "@", parts: 2) do
      [_local, domain] when domain != "" -> domain
      _ -> nil
    end
  end

  def email_domain(_email), do: nil

  def normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  def normalize_email(_email), do: nil

  defp account_match_inputs(emails) do
    filtered =
      emails
      |> Enum.map(&normalize_email/1)
      |> Enum.reject(&(is_nil(&1) or internal_email?(&1)))

    %{emails: filtered, domains: Enum.map(filtered, &email_domain/1) |> Enum.reject(&is_nil/1)}
  end

  defp update_account(account_id, attrs) do
    case Repo.get(Account, account_id) do
      nil ->
        {:error, :not_found}

      account ->
        if Account.not_account?(account) do
          {:error, :not_account}
        else
          Accounts.update_account(account, attrs)
        end
    end
  end

  defp create_or_update_account(attrs) do
    attrs = Map.put_new(attrs, "account_key", account_key(attrs))

    case find_existing_non_account(attrs) do
      %Account{} ->
        {:error, :not_account}

      nil ->
        case find_existing_account(attrs) do
          nil -> Accounts.create_account(attrs)
          account -> Accounts.update_account(account, Map.delete(attrs, "account_key"))
        end
    end
  end

  defp find_existing_account(attrs) do
    find_by_account_key(attrs["account_key"], :account) ||
      find_by_primary_domain_value(attrs["primary_domain"], :account)
  end

  defp find_existing_non_account(attrs) do
    find_by_account_key(attrs["account_key"], :not_account) ||
      find_by_primary_domain_value(attrs["primary_domain"], :not_account)
  end

  defp find_by_account_key(nil, _kind), do: nil

  defp find_by_account_key(account_key, kind) do
    kind
    |> account_query()
    |> where([account: account], account.account_key == ^account_key)
    |> Repo.one()
  end

  defp find_by_primary_domain_value(nil, _kind), do: nil

  defp find_by_primary_domain_value(domain, kind) do
    kind
    |> account_query()
    |> where([account: account], fragment("lower(?)", account.primary_domain) == ^domain)
    |> order_by([account], asc: account.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp account_attrs(params) do
    %{}
    |> put_account_attr("name", param(params, "name", :name), &normalize_optional_string/1)
    |> put_account_attr("primary_domain", param(params, "primary_domain", :primary_domain), &normalize_domain/1)
    |> put_account_attr("url", param(params, "url", :url), &normalize_optional_string/1)
    |> put_account_attr("description", param(params, "description", :description), &normalize_optional_string/1)
    |> put_account_attr("segment", param(params, "segment", :segment) || "lead", &normalize_optional_string/1)
    |> put_account_attr("deal_stage", param(params, "deal_stage", :deal_stage), &normalize_optional_string/1)
  end

  defp put_account_attr(attrs, _key, nil, _normalizer), do: attrs

  defp put_account_attr(attrs, key, value, normalizer) do
    case normalizer.(value) do
      nil -> attrs
      normalized -> Map.put(attrs, key, normalized)
    end
  end

  defp account_key(attrs) do
    slug =
      attrs["primary_domain"] ||
        attrs["name"] ||
        Ecto.UUID.generate()

    "granola:#{slugify(slug)}"
  end

  defp normalize_domain(value) when is_binary(value) do
    value = String.trim(value)

    host =
      case URI.parse(value) do
        %URI{host: host} when is_binary(host) -> host
        _uri -> value
      end

    host
    |> String.downcase()
    |> String.trim()
    |> String.trim_leading("www.")
    |> String.split("/", parts: 2)
    |> List.first()
    |> case do
      "" -> nil
      domain -> if !internal_email?("placeholder@#{domain}"), do: domain
    end
  end

  defp normalize_domain(_value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_value), do: nil

  @doc """
  Turns arbitrary text into an account-key slug segment.

  Downcases, collapses any run of non-alphanumeric characters into a single
  dash, trims leading/trailing dashes, and caps the result at 80 characters.
  Falls back to a generated UUID when nothing usable remains.
  """
  def slugify(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> Ecto.UUID.generate()
      slug -> String.slice(slug, 0, 80)
    end
  end

  defp param(params, string_key, atom_key) do
    Map.get(params, string_key) || Map.get(params, atom_key)
  end

  defp find_by_contact_email([], _kind), do: nil

  defp find_by_contact_email(emails, kind) do
    Contact
    |> join(:inner, [contact], account in Account, on: account.id == contact.account_id, as: :account)
    |> account_kind_filter(kind)
    |> where([contact], contact.email in ^emails)
    |> order_by([contact], asc: contact.inserted_at)
    |> preload([_contact, account: account], account: account)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      contact -> %{account: contact.account, matched_on: %{"type" => "contact_email", "value" => contact.email}}
    end
  end

  defp find_by_account_handle([], [], _kind), do: nil

  defp find_by_account_handle(emails, domains, kind) do
    handles = Enum.uniq(emails ++ domains)

    AccountHandle
    |> join(:inner, [account_handle], account in Account, on: account.id == account_handle.account_id, as: :account)
    |> account_kind_filter(kind)
    |> where([account_handle], fragment("lower(?)", account_handle.handle) in ^handles)
    |> order_by([account_handle], asc: account_handle.inserted_at)
    |> preload([_account_handle, account: account], account: account)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil ->
        nil

      account_handle ->
        %{account: account_handle.account, matched_on: %{"type" => "account_handle", "value" => account_handle.handle}}
    end
  end

  defp find_by_primary_domain([], _kind), do: nil

  defp find_by_primary_domain(domains, kind) do
    domains = Enum.uniq(domains)

    (find_by_primary_domain_exact(domains, kind) || find_by_primary_domain_subdomain(domains, kind))
    |> case do
      nil -> nil
      account -> %{account: account, matched_on: %{"type" => "primary_domain", "value" => account.primary_domain}}
    end
  end

  defp find_by_primary_domain_exact(domains, kind) do
    kind
    |> account_query()
    |> where([account: account], fragment("lower(?)", account.primary_domain) in ^domains)
    |> order_by([account], asc: account.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp find_by_primary_domain_subdomain(domains, kind) do
    dynamic =
      Enum.reduce(domains, dynamic(false), fn domain, dynamic ->
        dynamic(
          [account: account],
          ^dynamic or fragment("? LIKE ('%.' || lower(?))", ^domain, account.primary_domain)
        )
      end)

    kind
    |> account_query()
    |> where(^dynamic)
    |> order_by([account], asc: account.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp account_query(kind) do
    Account
    |> from(as: :account)
    |> account_kind_filter(kind)
  end

  defp account_kind_filter(query, :account) do
    where(query, [account: account], is_nil(account.not_an_account_at))
  end

  defp account_kind_filter(query, :not_account) do
    where(query, [account: account], not is_nil(account.not_an_account_at))
  end
end
