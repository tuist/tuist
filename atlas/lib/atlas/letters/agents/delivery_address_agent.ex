defmodule Atlas.Letters.Agents.DeliveryAddressAgent do
  @moduledoc false

  use Condukt

  alias Atlas.Agents.Sessions
  alias Atlas.Agents.StyleGuide
  alias Atlas.Documents.Storage
  alias Atlas.Documents.TextExtractor
  alias Atlas.Letters.Letter
  alias Atlas.LLMs.Runner

  @page_character_limit 4_000

  @impl true
  def tools, do: []

  @impl true
  def system_prompt do
    """
    You extract the postal delivery address from an outbound letter.

    Return the recipient's name and German delivery address exactly as supported
    by the letter text. Do not use the sender address. Do not guess a missing
    value. The delivery address must be the address the letter is addressed to.

    #{StyleGuide.prose_rules()}
    """
  end

  def extract(%Letter{document: nil}), do: {:error, :letter_document_not_found}

  def extract(%Letter{} = letter) do
    document = letter.document

    with {:ok, %{body: body}} <- Storage.get_object(document.storage_key),
         {:ok, path} <- Briefly.create(prefix: "atlas-letter", extname: Path.extname(document.original_filename)),
         :ok <- File.write(path, body),
         {:ok, pages} <- TextExtractor.extract_pages(path, document.content_type, document.original_filename),
         {:ok, recipient} <- extract_recipient(document, pages, letter) do
      {:ok, recipient}
    else
      {:error, :empty_document} -> {:error, :delivery_address_not_found}
      {:error, reason} -> {:error, {:delivery_address_extraction_failed, reason}}
    end
  end

  defp extract_recipient(document, pages, letter) do
    case Runner.fetch_config() do
      {:ok, llm} ->
        Sessions.run(
          __MODULE__,
          prompt(document, pages, letter),
          Runner.client_opts(llm) ++ [max_turns: 4, load_project_instructions: false, output: output_schema()]
        )
        |> normalize_result(pages, letter)

      {:error, :llm_not_configured} ->
        recipient_from_pages(pages, letter)
    end
  end

  defp prompt(document, pages, letter) do
    text =
      pages
      |> Enum.take(3)
      |> Enum.map_join("\n\n", fn page ->
        "Page #{page.page_number}:\n#{String.slice(page.content, 0, @page_character_limit)}"
      end)

    """
    Extract the delivery address for this outbound letter.

    Filename: #{document.original_filename}
    Sender address: #{letter_address(letter)}

    Letter text:
    #{text}
    """
  end

  defp output_schema do
    %{
      type: "object",
      properties: %{
        recipient_name: %{type: "string"},
        recipient_street: %{type: "string"},
        recipient_postal_code: %{type: "string"},
        recipient_city: %{type: "string"},
        recipient_country: %{type: "string"},
        recipient_reference: %{type: "string"}
      },
      required: ["recipient_name", "recipient_street", "recipient_postal_code", "recipient_city"]
    }
  end

  defp normalize_result({:ok, result}, pages, letter) when is_map(result) do
    recipient = %{
      recipient_name: clean_string(value(result, :recipient_name)),
      recipient_street: clean_string(value(result, :recipient_street)),
      recipient_postal_code: clean_postal_code(value(result, :recipient_postal_code)),
      recipient_city: clean_string(value(result, :recipient_city)),
      recipient_country: clean_country(value(result, :recipient_country)),
      recipient_reference: clean_string(value(result, :recipient_reference))
    }

    if Enum.all?(
         [:recipient_name, :recipient_street, :recipient_postal_code, :recipient_city, :recipient_country],
         &recipient[&1]
       ) do
      {:ok, recipient}
    else
      recipient_from_pages(pages, letter)
    end
  end

  defp normalize_result({:ok, _other}, pages, letter), do: recipient_from_pages(pages, letter)
  defp normalize_result({:error, _reason}, pages, letter), do: recipient_from_pages(pages, letter)

  defp recipient_from_pages(pages, letter) do
    lines =
      pages
      |> Enum.map_join("\n", & &1.content)
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    lines
    |> Enum.with_index()
    |> Enum.find_value(fn {line, index} ->
      with [_, postal_code, city] <- Regex.run(~r/^(?:D-)?(\d{5})\s+(.+)$/, line),
           true <- index >= 2,
           street when is_binary(street) <- Enum.at(lines, index - 1),
           name when is_binary(name) <- Enum.at(lines, index - 2),
           true <- street_address?(street),
           false <- sender_address?(postal_code, city, name, street, letter) do
        {:ok,
         %{
           recipient_name: name,
           recipient_street: street,
           recipient_postal_code: postal_code,
           recipient_city: city,
           recipient_country: "DE",
           recipient_reference: nil
         }}
      else
        _ -> nil
      end
    end)
    |> case do
      nil -> {:error, :delivery_address_not_found}
      result -> result
    end
  end

  defp sender_address?(postal_code, city, name, street, letter) do
    postal_code == letter.sender_postal_code and
      same_string?(city, letter.sender_city) and
      (same_string?(name, letter.sender_name) or same_string?(street, letter.sender_street))
  end

  defp letter_address(letter) do
    [letter.sender_name, letter.sender_street, [letter.sender_postal_code, letter.sender_city] |> Enum.join(" ")]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end

  defp street_address?(line), do: Regex.match?(~r/\d/, line)

  defp value(map, key), do: Map.get(map, Atom.to_string(key)) || Map.get(map, key)

  defp clean_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp clean_string(_value), do: nil

  defp clean_postal_code(value) do
    case clean_string(value) do
      value when is_binary(value) ->
        case Regex.run(~r/^(?:D-)?(\d{5})$/, value) do
          [_, postal_code] -> postal_code
          _ -> nil
        end

      nil ->
        nil
    end
  end

  defp clean_country(value) do
    case clean_string(value) do
      nil -> "DE"
      value when value in ["DE", "de", "Germany", "germany", "Deutschland", "deutschland"] -> "DE"
      _ -> nil
    end
  end

  defp same_string?(left, right) when is_binary(left) and is_binary(right),
    do: String.downcase(String.trim(left)) == String.downcase(String.trim(right))

  defp same_string?(_left, _right), do: false
end
