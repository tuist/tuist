defmodule Atlas.Letters.TaxCertificateRequestPDF do
  @moduledoc false

  alias Atlas.Letters.Letter

  @template_path "priv/atlas/letters/templates/berlin-tax-certificate-request.pdf"
  @template_checksum "86d4ce6bfea5252ff288beecf32ef56b9d01b3300bd87237f984fa2b30b8918f"

  # The official template has no AcroForm fields. These object identifiers and
  # the trailer offset belong to the checked-in, checksum-verified source PDF.
  # We append content streams and replacement page dictionaries as an ordinary
  # incremental PDF update, preserving the government form beneath the values.
  @template_last_xref 47_017

  def render(%Letter{} = letter) do
    template = File.read!(template_path())
    verify_template!(template)

    append_overlay(template, page_one_overlay(letter), page_two_overlay(letter))
  end

  def template_metadata do
    %{
      "key" => "berlin-tax-certificate-request",
      "source_url" =>
        "https://www.berlin.de/sen/finanzen/dokumentendownload/steuern/informationen-fuer-steuerzahler-/steuerklassen/antrag-auf-erteilung-einer-bescheinigung-in-steuersachen-2016.pdf",
      "checksum_sha256" => @template_checksum
    }
  end

  defp template_path, do: Application.app_dir(:atlas, @template_path)

  defp verify_template!(template) do
    checksum = :crypto.hash(:sha256, template) |> Base.encode16(case: :lower)

    if checksum != @template_checksum do
      raise "The checked-in Berlin tax-certificate template does not match its recorded checksum."
    end
  end

  defp page_one_overlay(letter) do
    data = letter.template_data || %{}

    [
      text_block(
        [
          letter.recipient_name,
          letter.recipient_street,
          "#{letter.recipient_postal_code} #{letter.recipient_city}"
        ],
        59,
        645,
        9,
        10
      ),
      text_at(letter.sender_name, 71, 510),
      text_at(date_value(data, "foundation_date"), 71, 470),
      text_at(map_value(data, "legal_form"), 416, 470),
      text_at("#{letter.sender_street}, #{letter.sender_postal_code} #{letter.sender_city}", 71, 430),
      text_at("X", 72, 351),
      text_at(letter.recipient_name, 245, 360),
      text_at(letter.tax_id, 432, 360),
      text_at("X", 483, 287),
      text_at(map_value(data, "submission_to"), 108, 158),
      text_at(map_value(data, "certificate_purpose"), 105, 108)
    ]
    |> Enum.join("\n")
  end

  defp page_two_overlay(letter) do
    data = letter.template_data || %{}
    signatory_title = String.downcase(letter.signatory_title || "")

    role_overlay =
      if String.contains?(signatory_title, "geschäftsführer") or
           String.contains?(signatory_title, "geschaeftsfuehrer") do
        text_at("X", 108, 644)
      else
        [text_at("X", 108, 616), text_at(letter.signatory_title, 125, 572)] |> Enum.join("\n")
      end

    [
      text_at("X", 72, 704),
      role_overlay,
      text_at(map_value(data, "signing_location"), 72, 420)
    ]
    |> Enum.join("\n")
  end

  defp append_overlay(template, page_one_overlay, page_two_overlay) do
    objects = [
      {135, stream_object(page_one_overlay)},
      {136, stream_object(page_two_overlay)},
      {3, page_one_dictionary()},
      {20, page_two_dictionary()}
    ]

    {body, offsets} =
      Enum.reduce(objects, {template <> "\n", %{}}, fn {number, content}, {body, offsets} ->
        offset = byte_size(body)
        object = "#{number} 0 obj\n#{content}\nendobj\n"
        {body <> object, Map.put(offsets, number, offset)}
      end)

    xref_offset = byte_size(body)

    body <>
      "xref\n" <>
      xref_entry(3, [Map.fetch!(offsets, 3)]) <>
      xref_entry(20, [Map.fetch!(offsets, 20)]) <>
      xref_entry(135, [Map.fetch!(offsets, 135), Map.fetch!(offsets, 136)]) <>
      "trailer\n" <>
      "<</Size 137/Root 1 0 R/Info 27 0 R/ID[<8C0274802CDB994689F1DC471476A04F><8C0274802CDB994689F1DC471476A04F>] /Prev #{@template_last_xref}>>\n" <>
      "startxref\n#{xref_offset}\n%%EOF\n"
  end

  defp xref_entry(start, offsets) do
    entries =
      Enum.map_join(offsets, "", fn offset ->
        :io_lib.format("~10..0B 00000 n \n", [offset]) |> IO.iodata_to_binary()
      end)

    "#{start} #{length(offsets)}\n#{entries}"
  end

  defp page_one_dictionary do
    "<</Type/Page/Parent 2 0 R/Resources<</Font<</F1 5 0 R/F2 7 0 R/F3 9 0 R/F4 11 0 R/F5 13 0 R/F6 15 0 R>>/ProcSet[/PDF/Text/ImageB/ImageC/ImageI] >>/MediaBox[ 0 0 595.32 841.92] /Contents[4 0 R 135 0 R]/Group<</Type/Group/S/Transparency/CS/DeviceRGB>>/Tabs/S/StructParents 0>>"
  end

  defp page_two_dictionary do
    "<</Type/Page/Parent 2 0 R/Resources<</Font<</F1 5 0 R/F2 7 0 R/F3 9 0 R/F7 22 0 R/F4 11 0 R>>/ProcSet[/PDF/Text/ImageB/ImageC/ImageI] >>/MediaBox[ 0 0 595.32 841.92] /Contents[21 0 R 136 0 R]/Group<</Type/Group/S/Transparency/CS/DeviceRGB>>/Tabs/S/StructParents 1>>"
  end

  defp stream_object(content), do: "<</Length #{byte_size(content)} >>\nstream\n#{content}\nendstream"

  defp text_block(lines, x, y, font_size, leading) do
    rendered_lines =
      lines
      |> Enum.map(&pdf_text/1)
      |> Enum.map_join("\n", fn line -> "(#{line}) Tj\nT*" end)

    "BT\n0 g\n/F3 #{font_size} Tf\n#{leading} TL\n#{x} #{y} Td\n#{rendered_lines}\nET"
  end

  defp text_at(value, x, y) do
    "BT\n0 g\n/F3 9 Tf\n#{x} #{y} Td\n(#{pdf_text(value)}) Tj\nET"
  end

  defp pdf_text(nil), do: ""

  defp pdf_text(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
    |> :unicode.characters_to_binary(:utf8, :latin1)
  end

  defp map_value(data, key), do: data |> Map.get(key) |> blank_to_nil()

  defp date_value(data, key) do
    case Map.get(data, key) do
      %Date{} = value -> Calendar.strftime(value, "%d.%m.%Y")
      value -> blank_to_nil(value)
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
