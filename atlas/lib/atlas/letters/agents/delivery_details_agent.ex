defmodule Atlas.Letters.Agents.DeliveryDetailsAgent do
  @moduledoc """
  Builds the immutable delivery details a reviewer needs before approving a letter.
  """

  alias Atlas.Letters.Agents.DeliveryAddressAgent
  alias Atlas.Letters.Config
  alias Atlas.Letters.Letter

  @recipient_fields [:recipient_name, :recipient_street, :recipient_postal_code, :recipient_city, :recipient_country]
  @sender_fields [:sender_name, :sender_street, :sender_postal_code, :sender_city, :sender_country]

  def prepare(%Letter{kind: "uploaded_letter"} = letter) do
    with {:ok, recipient} <- DeliveryAddressAgent.extract(letter),
         [] <- missing_fields(letter, recipient) do
      {:ok, %{delivery_details: details(letter, recipient), recipient: recipient}}
    else
      fields when is_list(fields) -> {:error, {:delivery_details_missing, fields}}
      {:error, _reason} = error -> error
    end
  end

  def prepare(%Letter{} = letter) do
    recipient = recipient_attributes(letter)

    case missing_fields(letter, recipient) do
      [] -> {:ok, %{delivery_details: details(letter, recipient), recipient: recipient}}
      fields -> {:error, {:delivery_details_missing, fields}}
    end
  end

  defp details(letter, recipient) do
    %{
      "recipient" => address(recipient),
      "sender" => address(letter, @sender_fields),
      "recipient_reference" => Map.get(recipient, :recipient_reference) || letter.recipient_reference,
      "delivery_product" => Config.delivery_product(),
      "print_mode" => Config.print_mode(),
      "print_spectrum" => Config.print_spectrum()
    }
  end

  defp address(letter, fields) when is_list(fields) do
    Map.new(fields, fn field ->
      key =
        field
        |> Atom.to_string()
        |> String.replace_prefix("recipient_", "")
        |> String.replace_prefix("sender_", "")

      {key, Map.fetch!(letter, field)}
    end)
  end

  defp address(attributes) do
    Map.new(attributes, fn {field, value} ->
      key = field |> Atom.to_string() |> String.replace_prefix("recipient_", "")
      {key, value}
    end)
  end

  defp recipient_attributes(letter) do
    Map.new(@recipient_fields, &{&1, Map.fetch!(letter, &1)})
  end

  defp missing_fields(letter, recipient) do
    recipient_missing = Enum.filter(@recipient_fields, &missing?(Map.fetch!(recipient, &1)))
    sender_missing = Enum.filter(@sender_fields, &missing?(Map.fetch!(letter, &1)))

    recipient_missing ++ sender_missing
  end

  defp missing?(value), do: value in [nil, ""]
end
