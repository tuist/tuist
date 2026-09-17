defmodule Atlas.Accounts.StripeCustomers do
  @moduledoc """
  Finds or creates a Stripe customer for an Atlas account.

  When the account already has a `stripe_customer_id`, returns it unchanged.
  Otherwise queries Stripe's customer search API for plausible matches (by
  name and by primary domain), ranks them with `String.jaro_distance/2`, and:

    * returns the top match when its score is at or above `@match_threshold`
      and no runner-up sits within `@ambiguity_window`
    * surfaces `{:error, {:ambiguous_stripe_customer, candidates}}` when
      multiple candidates tie within the window so a human can disambiguate
    * creates a new Stripe customer from the account's identity (name, legal
      name, address, billing email) when nothing matches confidently

  On a successful find/create the resolved `cus_…` id is persisted on the
  account via `Atlas.Accounts.update_account/2`.
  """

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Account.Address
  alias Atlas.Accounts.Account.Billing
  alias Atlas.Audit
  alias Atlas.Stripe

  @match_threshold 0.88
  @ambiguity_window 0.05
  @candidate_limit 10

  @doc """
  Returns `{:ok, %{status: :existing | :matched | :created, account: account,
  customer: %Stripe.Customer{} | nil}}` when the account ends up linked to a
  Stripe customer.

  Returns `{:error, {:ambiguous_stripe_customer, [%Stripe.Customer{}]}}` when
  multiple candidates score similarly, `{:error, :stripe_disabled}` when no
  Stripe API key is configured, or `{:error, reason}` on transport/HTTP error.
  """
  def find_or_create_for_account(%Account{} = account, opts \\ []) do
    case existing_customer_id(account) do
      {:ok, customer_id} ->
        sync_existing_customer_profile(account, customer_id, opts)

      :missing ->
        resolve(account, opts)
    end
  end

  defp existing_customer_id(%Account{stripe_customer_id: customer_id}) when is_binary(customer_id) do
    case String.trim(customer_id) do
      "" -> :missing
      trimmed -> {:ok, trimmed}
    end
  end

  defp existing_customer_id(_account), do: :missing

  defp resolve(%Account{} = account, opts) do
    with {:ok, candidates} <- search_candidates(account, opts) do
      case rank(account, candidates) do
        {:matched, customer} ->
          with {:ok, customer} <- maybe_update_customer_profile(customer, account, opts) do
            link_account(account, customer, :matched)
          end

        :ambiguous ->
          {:error, {:ambiguous_stripe_customer, candidates}}

        :no_match ->
          create_and_link(account, opts)
      end
    end
  end

  defp sync_existing_customer_profile(%Account{} = account, customer_id, opts) do
    if billing_profile_present?(account, opts) do
      client = stripe_client(opts)
      client_opts = client_opts(opts)

      with {:ok, customer} <- get_customer(client, customer_id, client_opts),
           {:ok, customer} <- maybe_update_customer_profile(customer, account, opts) do
        {:ok, %{status: :existing, account: account, customer: customer}}
      end
    else
      {:ok, %{status: :existing, account: account, customer: nil}}
    end
  end

  defp get_customer(client, customer_id, client_opts) do
    case client.get_customer(customer_id, client_opts) do
      {:ok, %Stripe.Customer{} = customer} -> {:ok, customer}
      :disabled -> {:error, :stripe_disabled}
      {:error, reason} -> {:error, reason}
    end
  end

  defp search_candidates(account, opts) do
    queries = candidate_queries(account, opts)
    client = stripe_client(opts)
    client_opts = client_opts(opts)

    Enum.reduce_while(queries, {:ok, []}, fn query, {:ok, acc} ->
      case client.search_customers(query, [{:limit, @candidate_limit} | client_opts]) do
        {:ok, customers} -> {:cont, {:ok, dedupe(acc ++ customers)}}
        :disabled -> {:halt, {:error, :stripe_disabled}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp candidate_queries(%Account{} = account, opts) do
    [
      build_query("name", account.name),
      build_query("name", account.legal_name),
      domain_query(account.primary_domain),
      email_query(billing_email(account, opts))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp build_query(_field, value) when value in [nil, ""], do: nil

  defp build_query(field, value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> "#{field}:'#{escape_query_value(trimmed)}'"
    end
  end

  defp domain_query(nil), do: nil
  defp domain_query(""), do: nil

  defp domain_query(domain) when is_binary(domain) do
    case String.trim(domain) do
      "" -> nil
      trimmed -> "email~\"@#{escape_query_value(trimmed)}\""
    end
  end

  defp email_query(nil), do: nil
  defp email_query(""), do: nil
  defp email_query(email) when is_binary(email), do: build_query("email", email)

  defp escape_query_value(value), do: String.replace(value, "'", "\\'")

  defp account_billing_email(%Account{billing: %Billing{email: email}}) when is_binary(email), do: email
  defp account_billing_email(_account), do: nil

  defp dedupe(customers) do
    customers
    |> Enum.reduce({MapSet.new(), []}, fn customer, {seen, acc} ->
      if MapSet.member?(seen, customer.id) do
        {seen, acc}
      else
        {MapSet.put(seen, customer.id), [customer | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp rank(_account, []), do: :no_match

  defp rank(account, candidates) do
    scored =
      candidates
      |> Enum.map(fn customer -> {score(account, customer), customer} end)
      |> Enum.sort_by(&elem(&1, 0), :desc)

    case scored do
      [{top_score, _customer} | _] when top_score < @match_threshold ->
        :no_match

      [{top_score, top_customer}] ->
        if top_score >= @match_threshold, do: {:matched, top_customer}, else: :no_match

      [{top_score, top_customer}, {second_score, _second} | _] ->
        cond do
          top_score - second_score >= @ambiguity_window -> {:matched, top_customer}
          second_score < @match_threshold -> {:matched, top_customer}
          true -> :ambiguous
        end
    end
  end

  defp score(%Account{} = account, %Stripe.Customer{} = customer) do
    targets =
      [account.name, account.legal_name]
      |> Enum.reject(&blank?/1)
      |> Enum.map(&normalize/1)

    customer_name = customer.name |> normalize()

    name_score =
      if customer_name == "" or targets == [] do
        0.0
      else
        targets
        |> Enum.map(&String.jaro_distance(&1, customer_name))
        |> Enum.max(fn -> 0.0 end)
      end

    domain_bonus =
      if is_binary(account.primary_domain) and account.primary_domain != "" and
           email_matches_domain?(customer.email, account.primary_domain) do
        0.1
      else
        0.0
      end

    name_score + domain_bonus
  end

  defp email_matches_domain?(email, domain) when is_binary(email) and is_binary(domain) do
    String.contains?(String.downcase(email), "@" <> String.downcase(String.trim(domain)))
  end

  defp email_matches_domain?(_email, _domain), do: false

  defp normalize(nil), do: ""

  defp normalize(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/\b(inc\.?|llc\.?|ltd\.?|corp\.?|corporation|co\.?|gmbh|s\.?a\.?|s\.?l\.?|labs?)\b/u, " ")
    |> String.replace(~r/[^a-z0-9 ]+/u, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp link_account(account, %Stripe.Customer{id: customer_id} = customer, status) do
    case Accounts.update_account(account, %{stripe_customer_id: customer_id}) do
      {:ok, updated} -> {:ok, %{status: status, account: updated, customer: customer}}
      {:error, reason} -> {:error, {:account_update_failed, reason}}
    end
  end

  defp create_and_link(account, opts) do
    client = stripe_client(opts)
    client_opts = client_opts(opts)

    case client.create_customer(customer_attrs(account, opts), client_opts) do
      {:ok, %Stripe.Customer{} = customer} -> link_account(account, customer, :created)
      :disabled -> {:error, :stripe_disabled}
      {:error, reason} -> {:error, reason}
    end
  end

  defp billing_profile_present?(%Account{} = account, opts) do
    not is_nil(billing_email(account, opts)) or not is_nil(billing_address(account, opts))
  end

  defp maybe_update_customer_profile(%Stripe.Customer{} = customer, %Account{} = account, opts) do
    attrs =
      %{}
      |> maybe_put_missing_email(customer, account, opts)
      |> maybe_put_missing_address(customer, account, opts)

    if map_size(attrs) == 0 do
      {:ok, customer}
    else
      client = stripe_client(opts)
      client_opts = client_opts(opts)

      case client.update_customer(customer.id, attrs, client_opts) do
        {:ok, %Stripe.Customer{} = customer} ->
          audit_customer_profile_update(account, customer, attrs)
          {:ok, customer}

        :disabled ->
          {:error, :stripe_disabled}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp maybe_put_missing_email(attrs, %Stripe.Customer{} = customer, %Account{} = account, opts) do
    email = billing_email(account, opts)

    if is_nil(email) or present?(customer.email) do
      attrs
    else
      Map.put(attrs, :email, email)
    end
  end

  defp maybe_put_missing_address(attrs, %Stripe.Customer{} = customer, %Account{} = account, opts) do
    address = billing_address(account, opts)
    missing_address = missing_address_fields(customer.address, address)

    if is_nil(missing_address) do
      attrs
    else
      Map.put(attrs, :address, missing_address)
    end
  end

  defp missing_address_fields(_customer_address, nil), do: nil

  defp missing_address_fields(customer_address, address) when is_map(address) do
    customer_address = if is_map(customer_address), do: customer_address, else: %{}

    address
    |> Enum.reject(fn {field, value} -> blank?(value) or present?(address_value(customer_address, field)) end)
    |> Map.new()
    |> case do
      address when map_size(address) == 0 -> nil
      address -> address
    end
  end

  defp address_value(address, field) when is_map(address) do
    Map.get(address, field) || Map.get(address, to_string(field))
  end

  defp customer_attrs(%Account{} = account, opts) do
    %{
      name: account.legal_name || account.name,
      email: billing_email(account, opts),
      description: customer_description(account),
      address: billing_address(account, opts),
      metadata:
        compact(%{
          "atlas_account_id" => account.id,
          "atlas_account_key" => account.account_key,
          "atlas_primary_domain" => account.primary_domain
        })
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp customer_description(%Account{description: description}) when is_binary(description) do
    case String.trim(description) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, 350)
    end
  end

  defp customer_description(_account), do: nil

  defp billing_email(%Account{} = account, opts) do
    opts
    |> Keyword.get(:billing_email)
    |> normalize_email()
    |> case do
      nil -> account_billing_email(account)
      email -> email
    end
  end

  defp normalize_email(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      email -> String.downcase(email)
    end
  end

  defp normalize_email(_value), do: nil

  defp billing_address(%Account{} = account, opts) do
    opts
    |> Keyword.get(:billing_address)
    |> normalize_address()
    |> case do
      nil -> address_attrs(account.address)
      address -> address
    end
  end

  defp normalize_address(address) when is_map(address) do
    address
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      field = address_field(key)

      if is_nil(field) or blank?(value) do
        acc
      else
        Map.put(acc, field, String.trim(to_string(value)))
      end
    end)
    |> case do
      address when map_size(address) == 0 -> nil
      address -> address
    end
  end

  defp normalize_address(_address), do: nil

  defp address_field(:line1), do: :line1
  defp address_field("line1"), do: :line1
  defp address_field(:line2), do: :line2
  defp address_field("line2"), do: :line2
  defp address_field(:city), do: :city
  defp address_field("city"), do: :city
  defp address_field(:state), do: :state
  defp address_field("state"), do: :state
  defp address_field(:postal_code), do: :postal_code
  defp address_field("postal_code"), do: :postal_code
  defp address_field(:country), do: :country
  defp address_field("country"), do: :country
  defp address_field(_field), do: nil

  defp address_attrs(%Address{} = address) do
    %{
      line1: address.street,
      city: address.city,
      postal_code: address.zip,
      country: address.country
    }
    |> Enum.reject(fn {_key, value} -> blank?(value) end)
    |> Map.new()
  end

  defp address_attrs(_address), do: nil

  defp present?(value), do: not blank?(value)

  defp audit_customer_profile_update(%Account{} = account, %Stripe.Customer{} = customer, attrs) do
    Audit.record("stripe_customer.profile_updated", %{
      target_type: "stripe_customer",
      target_id: customer.id,
      target_label: account.name,
      metadata: %{
        "account_id" => account.id,
        "path" => "/accounts/#{account.id}",
        "stripe_customer_id" => customer.id,
        "changed" => changed_profile_fields(attrs)
      }
    })
  end

  defp changed_profile_fields(attrs) do
    attrs
    |> Enum.flat_map(fn
      {:address, address} when is_map(address) -> Enum.map(Map.keys(address), &"address.#{&1}")
      {field, _value} -> [to_string(field)]
    end)
    |> Enum.sort()
  end

  defp compact(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp stripe_client(opts) do
    Keyword.get(opts, :stripe_client) ||
      :atlas
      |> Application.get_env(:accounts, [])
      |> Keyword.get(:stripe_client, Stripe)
  end

  defp client_opts(opts), do: Keyword.drop(opts, [:stripe_client, :billing_email, :billing_address])
end
