defmodule Atlas.Letters.TaxCertificateRequest do
  @moduledoc false

  alias Atlas.Accounts.Account
  alias Atlas.Letters.TaxCertificateProfile

  @subject "Antrag auf Erteilung einer Bescheinigung in Steuersachen"

  def subject, do: @subject

  def sender_snapshot, do: TaxCertificateProfile.sender_snapshot()

  def form_defaults(%Account{} = account) do
    TaxCertificateProfile.form_defaults()
    |> Map.put("submission_to", present(account.legal_name) || present(account.name))
  end

  def missing_sender_fields, do: TaxCertificateProfile.missing_fields()

  def sender_snapshot(%Account{} = account) do
    address = account.address
    billing = account.billing
    signatory = account.signatory

    %{
      sender_name: present(account.legal_name) || present(account.name),
      sender_street: embedded_value(address, :street),
      sender_postal_code: embedded_value(address, :zip),
      sender_city: embedded_value(address, :city),
      sender_country: embedded_country(address),
      signatory_name: embedded_value(signatory, :name),
      signatory_title: embedded_value(signatory, :title),
      tax_id: embedded_value(billing, :tax_id),
      vat_id: embedded_value(billing, :vat_id)
    }
  end

  def missing_sender_fields(%Account{} = account) do
    snapshot = sender_snapshot(account)

    [
      {:sender_name, "legal company name"},
      {:sender_street, "registered street"},
      {:sender_postal_code, "registered postal code"},
      {:sender_city, "registered city"},
      {:sender_country, "registered country (Germany)"},
      {:tax_id, "tax number"},
      {:signatory_name, "authorized signatory"}
    ]
    |> Enum.flat_map(fn {field, label} -> if present?(snapshot[field]), do: [], else: [label] end)
    |> case do
      missing when snapshot.sender_country != "DE" -> Enum.uniq(["registered country (Germany)" | missing])
      missing -> missing
    end
  end

  def body(attrs) when is_map(attrs) do
    company = attrs.sender_name
    tax_number = attrs.tax_id
    vat_line = if present?(attrs.vat_id), do: "Umsatzsteuer-Identifikationsnummer: #{attrs.vat_id}"
    signature_line = signature_line(attrs.signatory_name, attrs.signatory_title)

    [
      "Sehr geehrte Damen und Herren,",
      "",
      "hiermit beantragen wir die Erteilung einer Bescheinigung in Steuersachen für #{company}.",
      "",
      "Unternehmensdaten:",
      company,
      "Steuernummer: #{tax_number}",
      vat_line,
      "#{attrs.sender_street}, #{attrs.sender_postal_code} #{attrs.sender_city}",
      "",
      "Bitte senden Sie die Bescheinigung an die oben genannte Anschrift.",
      "",
      "Mit freundlichen Grüßen,",
      "",
      signature_line
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp normalize_country(value) do
    value
    |> present()
    |> case do
      nil -> nil
      country -> String.upcase(country)
    end
  end

  defp embedded_value(nil, _field), do: nil
  defp embedded_value(embedded, field), do: embedded |> Map.get(field) |> present()
  defp embedded_country(nil), do: nil
  defp embedded_country(address), do: address |> Map.get(:country) |> normalize_country()

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_value), do: nil
  defp present?(value), do: not is_nil(present(value))

  defp signature_line(name, title) do
    case {present(name), present(title)} do
      {nil, _title} -> nil
      {name, nil} -> name
      {name, title} -> "#{name}, #{title}"
    end
  end
end
