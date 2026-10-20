defmodule Atlas.Accounts.OrderForms do
  @moduledoc """
  Order-form detection and account-field extraction.

  A signed order form is the source of truth for an account's commercial
  details (currency, contract value, renewal date). This module owns:

    * `signed?/1` — recognizing a document as an executed order form, used by
      both the draft-invoice pipeline and the document-ingest hook.
    * `commercial_attrs/1` — projecting the extracted attributes from a signed
      order form onto an account update map.

  Authoritative fields (`currency`, `current_value`, `next_renewal_date`,
  `segment`) overwrite whatever the account currently holds. Softer fields
  (`deal_stage`, `poc_end_date`) fill blanks only so a hand-curated stage note
  is not clobbered by a freshly uploaded contract.
  """

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Amounts
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage

  @amount_keys ~w(invoice_amount total_amount total amount annual_amount annual_subscription subscription_amount subscription_total contract_value order_total)
  @billing_address_context_paths [
    ["billing"],
    ["billing_details"],
    ["bill_details"],
    ["bill_to"],
    ["customer_details"],
    ["invoice"],
    []
  ]
  @billing_email_paths [
    ["billing", "email"],
    ["billing_details", "email"],
    ["bill_details", "email"],
    ["bill_to", "email"],
    ["customer_details", "email"],
    ["invoice", "email"],
    ["billing_email"],
    ["bill_to_email"],
    ["invoice_email"]
  ]
  @billing_section_pattern ~r/\b(?:bill\s+details|billing\s+details|bill\s+to|payment\s+details|invoice\s+details|customer\s+details)\b(.{0,1800})/is
  @email_pattern ~r/[A-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[A-Z0-9-]+(?:\.[A-Z0-9-]+)+/i
  @country_codes %{
    "australia" => "AU",
    "austria" => "AT",
    "belgium" => "BE",
    "canada" => "CA",
    "denmark" => "DK",
    "finland" => "FI",
    "france" => "FR",
    "germany" => "DE",
    "ireland" => "IE",
    "italy" => "IT",
    "netherlands" => "NL",
    "norway" => "NO",
    "spain" => "ES",
    "sweden" => "SE",
    "switzerland" => "CH",
    "united kingdom" => "GB",
    "uk" => "GB",
    "united states" => "US",
    "united states of america" => "US",
    "usa" => "US"
  }
  @address_label_patterns %{
    line1: ~r/(?:^|\n)\s*Address\s+(?<value>[^\n]+)/i,
    city: ~r/(?:^|\n)\s*City\s+(?<value>[^\n]+)/i,
    state: ~r/(?:^|\n)\s*(?:State|Province|Region)\s+(?<value>[^\n]+)/i,
    postal_code: ~r/(?:^|\n)\s*(?:ZIP\/Postal Code|Zip Code|Postal Code|ZIP|Postal)\s+(?<value>[^\n]+)/i,
    country: ~r/(?:^|\n)\s*Country\s+(?<value>[^\n]+)/i
  }
  @currency_keys ~w(invoice_currency amount_currency currency)
  @period_end_keys ~w(period_end service_period_end end_date renewal_date)

  @doc """
  Returns `true` when the document looks like a signed/executed order form.

  Pages may be passed explicitly when the document was processed in-flight
  and its `pages` association is not yet preloaded; otherwise the function
  reads the document's preloaded pages.
  """
  def signed?(%Document{} = document, pages \\ nil) do
    context = context_text(document)
    full = full_text(document, pages, context)

    String.contains?(full, "order form") and signed_document?(document, context, full)
  end

  # "signed order form" / "executed order form" must hit the document's own
  # context (title, filename, tags, attributes text) — page bodies routinely
  # contain the phrase even when the document itself is a draft, so trusting
  # page text for that match misclassifies unsigned forms.
  @context_signed_phrases ["signed order form", "executed order form"]
  @body_signed_phrases ["fully executed", "signed by", "executed by", "accepted and agreed", "date signed"]

  defp signed_document?(%Document{attributes: attrs} = _document, context, full) do
    signed_attributes?(attrs || %{}) or
      Enum.any?(@context_signed_phrases, &String.contains?(context, &1)) or
      Enum.any?(@body_signed_phrases, &String.contains?(full, &1))
  end

  defp signed_attributes?(attrs) when is_map(attrs) do
    truthy_attribute?(attrs, "signed") or truthy_attribute?(attrs, "executed") or
      present_attribute?(attrs, "signed_at") or present_attribute?(attrs, "executed_at") or
      status_attribute?(attrs, "signature_status") or status_attribute?(attrs, "execution_status") or
      status_attribute?(attrs, "document_status")
  end

  defp signed_attributes?(_attrs), do: false

  defp truthy_attribute?(attrs, key) do
    case nested(attrs, key) do
      true -> true
      value when is_binary(value) -> normalize_text(value) in ["true", "yes", "signed", "executed"]
      _other -> false
    end
  end

  defp present_attribute?(attrs, key), do: present?(nested(attrs, key))

  defp status_attribute?(attrs, key) do
    case nested(attrs, key) do
      value when is_binary(value) ->
        normalize_text(value) in ["signed", "executed", "fully executed", "complete", "completed"]

      _value ->
        false
    end
  end

  @doc """
  Returns an account update map projected from the signed order form.

  Authoritative fields (`currency`, `current_value`, `next_renewal_date`,
  `segment`) are always included when extractable. Softer fields (`deal_stage`,
  `poc_end_date`) are included only when the account currently has no value
  for them, so manual stage curation is preserved.

  When `account` is nil the function returns the unfiltered projection (used
  by callers that want to inspect what would change).
  """
  def commercial_attrs(%Document{} = document, account \\ nil) do
    attrs = document.attributes || %{}

    base =
      %{}
      |> put_currency(attrs)
      |> put_current_value(attrs)
      |> put_next_renewal_date(attrs)
      |> put_lifecycle_to_customer()

    if account do
      base
      |> maybe_put_deal_stage(account)
      |> maybe_put_poc_end_date(account, attrs)
    else
      base
      |> put_deal_stage_unconditional()
      |> put_poc_end_date_unconditional(attrs)
    end
  end

  @doc """
  Extracts the billing email from an order form when available.

  The extractor prefers structured attributes and then scans labeled billing
  sections in the document pages. It deliberately avoids picking the first
  email in the whole document because sales contact emails can appear before
  the customer billing block.
  """
  def billing_email(%Document{} = document, pages \\ nil) do
    attribute_billing_email(document.attributes || %{}) ||
      text_billing_email(document, pages)
  end

  @doc """
  Extracts the billing address from an order form when available.

  The returned map uses Stripe's customer address field names.
  """
  def billing_address(%Document{} = document, pages \\ nil) do
    attribute_billing_address(document.attributes || %{}) ||
      text_billing_address(document, pages)
  end

  defp put_currency(map, attrs) do
    case Enum.find_value(@currency_keys, fn key -> normalize_currency(nested(attrs, key)) end) do
      nil -> map
      currency -> Map.put(map, :currency, currency)
    end
  end

  defp attribute_billing_email(attrs) when is_map(attrs) do
    Enum.find_value(@billing_email_paths, fn path ->
      attrs
      |> nested_path(path)
      |> valid_email()
    end)
  end

  defp attribute_billing_email(_attrs), do: nil

  defp attribute_billing_address(attrs) when is_map(attrs) do
    @billing_address_context_paths
    |> Enum.map(fn path -> address_from_context(nested_path(attrs, path)) end)
    |> merge_addresses()
    |> normalize_address()
  end

  defp attribute_billing_address(_attrs), do: nil

  defp text_billing_email(%Document{} = document, pages) do
    text = pages_text(pages || document.pages)

    @billing_section_pattern
    |> Regex.scan(text, capture: :all_but_first)
    |> Enum.find_value(fn [section] -> first_email(section) end)
  end

  defp first_email(text) when is_binary(text) do
    case Regex.run(@email_pattern, text) do
      [email | _] -> valid_email(email)
      _match -> nil
    end
  end

  defp first_email(_text), do: nil

  defp valid_email(value) when is_binary(value) do
    value = value |> String.trim() |> String.downcase()

    case Regex.run(@email_pattern, value) do
      [email | _] -> email
      _match -> nil
    end
  end

  defp valid_email(_value), do: nil

  defp text_billing_address(%Document{} = document, pages) do
    text = pages_text(pages || document.pages)

    @billing_section_pattern
    |> Regex.scan(text, capture: :all_but_first)
    |> Enum.map(fn [section] -> address_from_text(section) end)
    |> merge_addresses()
    |> normalize_address()
  end

  defp address_from_context(nil), do: nil

  defp address_from_context(context) when is_map(context) do
    context
    |> nested("address")
    |> case do
      %{} = address -> [address, context]
      _value -> [context]
    end
    |> Enum.map(&address_from_map/1)
    |> merge_addresses()
  end

  defp address_from_context(_context), do: nil

  defp address_from_map(map) when is_map(map) do
    %{
      line1: first_text_value(map, ~w(line1 street address billing_address address_line1)),
      line2: first_text_value(map, ~w(line2 address_line2)),
      city: first_text_value(map, ~w(city)),
      state: first_text_value(map, ~w(state province region)),
      postal_code: first_text_value(map, ~w(postal_code postal zip zip_code zip_postal_code)),
      country: first_text_value(map, ~w(country))
    }
  end

  defp address_from_map(_map), do: nil

  defp address_from_text(text) when is_binary(text) do
    @address_label_patterns
    |> Map.new(fn {field, pattern} -> {field, text_value(captured_value(pattern, text))} end)
  end

  defp address_from_text(_text), do: nil

  defp first_text_value(map, keys) do
    Enum.find_value(keys, fn key ->
      map
      |> nested(key)
      |> text_value()
    end)
  end

  defp captured_value(pattern, text) do
    case Regex.named_captures(pattern, text) do
      %{"value" => value} -> value
      _match -> nil
    end
  end

  defp text_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp text_value(_value), do: nil

  defp merge_addresses(addresses) do
    addresses
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(%{}, fn address, acc ->
      Enum.reduce([:line1, :line2, :city, :state, :postal_code, :country], acc, fn field, acc ->
        value = Map.get(address, field)

        if blank?(Map.get(acc, field)) and present?(value) do
          Map.put(acc, field, value)
        else
          acc
        end
      end)
    end)
  end

  defp normalize_address(address) when is_map(address) do
    address
    |> Enum.reduce(%{}, fn
      {:country, value}, acc ->
        case normalize_country(value) do
          nil -> acc
          country -> Map.put(acc, :country, country)
        end

      {field, value}, acc ->
        case text_value(value) do
          nil -> acc
          value -> Map.put(acc, field, value)
        end
    end)
    |> case do
      address when map_size(address) == 0 -> nil
      address -> address
    end
  end

  defp normalize_address(_address), do: nil

  defp normalize_country(value) when is_binary(value) do
    value = String.trim(value)

    if Regex.match?(~r/^[A-Za-z]{2}$/, value) do
      String.upcase(value)
    else
      Map.get(@country_codes, String.downcase(value))
    end
  end

  defp normalize_country(_value), do: nil

  defp put_current_value(map, attrs) do
    case Enum.find_value(@amount_keys, fn key -> nested(attrs, key) end) do
      nil -> map
      value -> Map.put(map, :current_value, to_decimal(value))
    end
    |> reject_nil(:current_value)
  end

  defp put_next_renewal_date(map, attrs) do
    case Enum.find_value(@period_end_keys, fn key -> parse_date(nested(attrs, key)) end) do
      nil -> map
      date -> Map.put(map, :next_renewal_date, date)
    end
  end

  defp put_lifecycle_to_customer(map), do: Map.put(map, :segment, :customer)

  defp put_deal_stage_unconditional(map), do: Map.put(map, :deal_stage, "closed_won")

  defp maybe_put_deal_stage(map, %Account{deal_stage: stage}) when is_binary(stage) and stage != "" do
    map
  end

  defp maybe_put_deal_stage(map, _account), do: Map.put(map, :deal_stage, "closed_won")

  defp put_poc_end_date_unconditional(map, attrs) do
    case Enum.find_value(@period_end_keys, fn key -> parse_date(nested(attrs, key)) end) do
      nil -> map
      date -> Map.put(map, :poc_end_date, date)
    end
  end

  defp maybe_put_poc_end_date(map, %Account{poc_end_date: %Date{}}, _attrs), do: map

  defp maybe_put_poc_end_date(map, _account, attrs), do: put_poc_end_date_unconditional(map, attrs)

  defp reject_nil(map, key) do
    case Map.get(map, key) do
      nil -> Map.delete(map, key)
      _value -> map
    end
  end

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)

  defp to_decimal(value) when is_binary(value) do
    value
    |> String.replace(",", "")
    |> String.replace(~r/[^\d.\-]/, "")
    |> Decimal.parse()
    |> case do
      {decimal, ""} -> decimal
      _other -> nil
    end
  end

  defp to_decimal(_value), do: nil

  defp normalize_currency(value), do: Amounts.normalize_currency(value)

  defp parse_date(%Date{} = date), do: date

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(_value), do: nil

  defp context_text(%Document{} = document) do
    [
      document.title,
      document.original_filename,
      document.document_type && document.document_type.name,
      document.summary,
      tags_text(document.tags),
      attributes_text(document.attributes)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> normalize_text()
  end

  defp full_text(%Document{} = document, pages, context) do
    [context, pages_text(pages || document.pages)]
    |> Enum.join("\n")
    |> normalize_text()
  end

  defp tags_text(tags) when is_list(tags), do: Enum.map_join(tags, " ", & &1.name)
  defp tags_text(_tags), do: ""

  defp attributes_text(attrs) when is_map(attrs) do
    Enum.map_join(attrs, " ", fn {key, value} -> "#{key} #{inspect(value)}" end)
  end

  defp attributes_text(_attrs), do: ""

  defp pages_text(pages) when is_list(pages) do
    pages
    |> Enum.take(12)
    |> Enum.map_join("\n", fn
      %DocumentPage{content: content} -> content
      %{content: content} -> content
      _other -> ""
    end)
  end

  defp pages_text(_pages), do: ""

  defp nested(map, key) when is_map(map) and is_binary(key) do
    atom_key =
      try do
        String.to_existing_atom(key)
      rescue
        ArgumentError -> nil
      end

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      not is_nil(atom_key) and Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> nil
    end
  end

  defp nested(_map, _key), do: nil

  defp nested_path(map, path) when is_map(map) and is_list(path) do
    Enum.reduce_while(path, map, fn key, acc ->
      case nested(acc, key) do
        nil -> {:halt, nil}
        value -> {:cont, value}
      end
    end)
  end

  defp nested_path(_map, _path), do: nil

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true

  defp normalize_text(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9$€£.,]+/u, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_text(value), do: value |> inspect() |> normalize_text()
end
