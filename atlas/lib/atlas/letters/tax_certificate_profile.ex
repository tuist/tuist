defmodule Atlas.Letters.TaxCertificateProfile do
  @moduledoc false

  @sender_fields [
    {:sender_name, "legal company name"},
    {:sender_street, "registered street"},
    {:sender_postal_code, "registered postal code"},
    {:sender_city, "registered city"},
    {:sender_country, "registered country (Germany)"},
    {:tax_id, "tax number"}
  ]

  @tax_office_fields [
    {:recipient_name, "tax office name"},
    {:recipient_street, "tax office street"},
    {:recipient_postal_code, "tax office postal code"},
    {:recipient_city, "tax office city"}
  ]

  def sender_snapshot do
    %{
      sender_name: profile_value(:sender_name),
      sender_street: profile_value(:sender_street),
      sender_postal_code: profile_value(:sender_postal_code),
      sender_city: profile_value(:sender_city),
      sender_country: profile_value(:sender_country),
      signatory_name: nil,
      signatory_title: profile_value(:signatory_title),
      tax_id: profile_value(:tax_id),
      vat_id: profile_value(:vat_id)
    }
  end

  def form_defaults do
    %{
      "recipient_name" => profile_value(:tax_office_name),
      "recipient_street" => profile_value(:tax_office_street),
      "recipient_postal_code" => profile_value(:tax_office_postal_code),
      "recipient_city" => profile_value(:tax_office_city),
      "recipient_country" => "DE",
      "foundation_date" => profile_value(:foundation_date),
      "legal_form" => profile_value(:legal_form),
      "signing_location" => profile_value(:signing_location)
    }
    |> Enum.reject(fn {_field, value} -> is_nil(value) end)
    |> Map.new()
  end

  def missing_fields do
    sender = sender_snapshot()
    defaults = form_defaults()

    missing =
      @sender_fields
      |> Enum.flat_map(fn {field, label} -> if present?(sender[field]), do: [], else: [label] end)
      |> Kernel.++(
        Enum.flat_map(@tax_office_fields, fn {field, label} ->
          if present?(defaults[Atom.to_string(field)]), do: [], else: [label]
        end)
      )

    case sender.sender_country do
      "DE" -> missing
      _other -> Enum.uniq(["registered country (Germany)" | missing])
    end
  end

  defp profile_value(field) do
    :atlas
    |> Application.get_env(:tax_certificate_profile, [])
    |> Keyword.get(field)
    |> present()
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_value), do: nil
  defp present?(value), do: not is_nil(present(value))
end
