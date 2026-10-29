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

  # The template's embedded F3 (Arial) font ships a Widths array with zero
  # widths for characters it did not itself use (e.g. T, K, 8, 9), so writing
  # our overlay with F3 makes those glyphs advance zero and collapse onto the
  # next character. We register a base-14 Helvetica reference and use it for
  # every overlay glyph so viewers use their intrinsic metrics.
  @overlay_font_object 137
  @overlay_font_name "FO"

  # Signature image XObject, added only when a signature JPEG is configured.
  @signature_xobject 138
  @signature_xobject_name "Sig"

  # Bottom-left anchor and maximum extent of the signature drawing area on
  # page 2, in points. The image aspect ratio is preserved inside these bounds.
  @signature_x 285
  @signature_y 425
  @signature_max_width 165
  @signature_max_height 32

  @cover_page_object 139
  @cover_content_object 140
  @form_transform_object 141
  @form_restore_object 142

  # Pingen reserves the first page for its address window and postage. Keep the
  # official form on subsequent pages, inset far enough to clear every restricted
  # border, including the 15 mm bottom-left corner, without removing any content.
  @form_transform "q\n0.85 0 0 0.85 44.649 63.144 cm"

  def render(%Letter{} = letter) do
    template = File.read!(template_path())
    verify_template!(template)

    signature = signature_asset()

    append_overlay(
      template,
      page_one_overlay(letter),
      page_two_overlay(letter, signature),
      signature,
      letter
    )
  end

  def signature_configured?, do: signature_asset() != nil

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
        650,
        9,
        12
      ),
      text_at(letter.sender_name, 71, 513),
      text_at(date_value(data, "foundation_date"), 71, 473),
      text_at(map_value(data, "legal_form"), 416, 473),
      text_at(
        "#{letter.sender_street}, #{letter.sender_postal_code} #{letter.sender_city}",
        71,
        433
      ),
      text_at("X", 72, 351),
      text_at(letter.recipient_name, 127, 350),
      text_at(letter.tax_id, 340, 350),
      text_at("X", 482, 279),
      text_at(map_value(data, "submission_to"), 108, 156),
      text_at(map_value(data, "certificate_purpose"), 105, 106)
    ]
    |> Enum.join("\n")
  end

  defp page_two_overlay(letter, signature) do
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
      text_at(map_value(data, "signing_location"), 72, 424),
      text_at(date_value(data, "signing_date") || today_de(), 200, 424),
      draw_signature(signature)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp draw_signature(nil), do: ""

  defp draw_signature(%{width: w, height: h}) do
    aspect = w / h
    max_by_width = {@signature_max_width, @signature_max_width / aspect}
    max_by_height = {@signature_max_height * aspect, @signature_max_height}

    {draw_w, draw_h} =
      if elem(max_by_width, 1) <= @signature_max_height, do: max_by_width, else: max_by_height

    """
    q
    #{Float.round(draw_w * 1.0, 3)} 0 0 #{Float.round(draw_h * 1.0, 3)} #{@signature_x} #{@signature_y} cm
    /#{@signature_xobject_name} Do
    Q
    """
    |> String.trim_trailing()
  end

  defp append_overlay(template, page_one_overlay, page_two_overlay, signature, letter) do
    base_objects = [
      {135, stream_object(page_one_overlay)},
      {136, stream_object(page_two_overlay)},
      {@overlay_font_object, overlay_font_object()},
      {2, "<</Type/Pages/Count 3/Kids[#{@cover_page_object} 0 R 3 0 R 20 0 R]>>"},
      {@cover_page_object, cover_page_dictionary()},
      {@cover_content_object, stream_object(cover_page_overlay(letter))},
      {@form_transform_object, stream_object(@form_transform)},
      {@form_restore_object, stream_object("Q")},
      {3, page_one_dictionary()},
      {20, page_two_dictionary(signature != nil)}
    ]

    objects =
      case signature do
        nil -> base_objects
        asset -> base_objects ++ [{@signature_xobject, signature_xobject(asset)}]
      end

    {body, offsets} =
      Enum.reduce(objects, {template <> "\n", %{}}, fn {number, content}, {body, offsets} ->
        offset = byte_size(body)
        object = "#{number} 0 obj\n#{content}\nendobj\n"
        {body <> object, Map.put(offsets, number, offset)}
      end)

    xref_offset = byte_size(body)

    body <>
      "xref\n0 1\n0000000000 65535 f \n" <>
      (offsets
       |> Enum.sort_by(&elem(&1, 0))
       |> Enum.map_join("", fn {number, offset} -> xref_entry(number, [offset]) end)) <>
      "trailer\n" <>
      "<</Size 143/Root 1 0 R/Info 27 0 R/ID[<8C0274802CDB994689F1DC471476A04F><8C0274802CDB994689F1DC471476A04F>] /Prev #{@template_last_xref}>>\n" <>
      "startxref\n#{xref_offset}\n%%EOF\n"
  end

  defp overlay_font_object do
    "<</Type/Font/Subtype/Type1/BaseFont/Helvetica/Encoding/WinAnsiEncoding>>"
  end

  defp signature_xobject(%{bytes: bytes, width: width, height: height, colorspace: colorspace}) do
    "<</Type/XObject/Subtype/Image/Width #{width}/Height #{height}/ColorSpace#{colorspace}/BitsPerComponent 8/Filter/DCTDecode/Length #{byte_size(bytes)}>>\nstream\n" <>
      bytes <> "\nendstream"
  end

  defp xref_entry(start, offsets) do
    entries =
      Enum.map_join(offsets, "", fn offset ->
        :io_lib.format("~10..0B 00000 n \n", [offset]) |> IO.iodata_to_binary()
      end)

    "#{start} #{length(offsets)}\n#{entries}"
  end

  defp cover_page_dictionary do
    "<</Type/Page/Parent 2 0 R/Resources<</Font<</#{@overlay_font_name} #{@overlay_font_object} 0 R>>>>/MediaBox[0 0 595.32 841.92]/Contents #{@cover_content_object} 0 R>>"
  end

  defp cover_page_overlay(letter) do
    [
      text_block(
        [
          letter.recipient_name,
          letter.recipient_street,
          "#{letter.recipient_postal_code} #{letter.recipient_city}"
        ],
        65,
        655,
        10,
        14
      ),
      text_at("Tax certificate request", 65, 510),
      text_at("Applicant: #{letter.sender_name}", 65, 482),
      text_at("The official application is enclosed.", 65, 454)
    ]
    |> Enum.join("\n")
  end

  defp page_one_dictionary do
    "<</Type/Page/Parent 2 0 R/Resources<</Font<</F1 5 0 R/F2 7 0 R/F3 9 0 R/F4 11 0 R/F5 13 0 R/F6 15 0 R/#{@overlay_font_name} #{@overlay_font_object} 0 R>>/ProcSet[/PDF/Text/ImageB/ImageC/ImageI] >>/MediaBox[ 0 0 595.32 841.92] /Contents[#{@form_transform_object} 0 R 4 0 R 135 0 R #{@form_restore_object} 0 R]/Group<</Type/Group/S/Transparency/CS/DeviceRGB>>/Tabs/S/StructParents 0>>"
  end

  defp page_two_dictionary(signature?) do
    xobject_entry =
      if signature? do
        "/XObject<</#{@signature_xobject_name} #{@signature_xobject} 0 R>>"
      else
        ""
      end

    "<</Type/Page/Parent 2 0 R/Resources<</Font<</F1 5 0 R/F2 7 0 R/F3 9 0 R/F7 22 0 R/F4 11 0 R/#{@overlay_font_name} #{@overlay_font_object} 0 R>>#{xobject_entry}/ProcSet[/PDF/Text/ImageB/ImageC/ImageI] >>/MediaBox[ 0 0 595.32 841.92] /Contents[#{@form_transform_object} 0 R 21 0 R 136 0 R #{@form_restore_object} 0 R]/Group<</Type/Group/S/Transparency/CS/DeviceRGB>>/Tabs/S/StructParents 1>>"
  end

  defp stream_object(content), do: "<</Length #{byte_size(content)} >>\nstream\n#{content}\nendstream"

  defp text_block(lines, x, y, font_size, leading) do
    rendered_lines =
      lines
      |> Enum.map(&pdf_text/1)
      |> Enum.map_join("\n", fn line -> "(#{line}) Tj\nT*" end)

    "BT\n0 g\n/#{@overlay_font_name} #{font_size} Tf\n#{leading} TL\n#{x} #{y} Td\n#{rendered_lines}\nET"
  end

  defp text_at(nil, _x, _y), do: ""
  defp text_at("", _x, _y), do: ""

  defp text_at(value, x, y) do
    "BT\n0 g\n/#{@overlay_font_name} 9 Tf\n#{x} #{y} Td\n(#{pdf_text(value)}) Tj\nET"
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

  defp today_de, do: Calendar.strftime(Date.utc_today(), "%d.%m.%Y")

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  # Loads the configured signatory JPEG (base64 in env, decoded here) and
  # returns its bytes plus dimensions parsed from the SOFn segment. When the
  # env var is unset or the bytes are not a JPEG, returns nil so the render
  # falls back to an unsigned document.
  defp signature_asset do
    case Application.get_env(:atlas, :tax_certificate_profile, [])[:signature_jpeg_base64] do
      nil ->
        nil

      encoded when is_binary(encoded) ->
        case Base.decode64(String.trim(encoded), ignore: :whitespace) do
          {:ok, bytes} -> parse_jpeg(bytes)
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_jpeg(<<0xFF, 0xD8, rest::binary>> = bytes) do
    case find_sof(rest) do
      {:ok, width, height, components} ->
        %{bytes: bytes, width: width, height: height, colorspace: jpeg_colorspace(components)}

      :error ->
        nil
    end
  end

  defp parse_jpeg(_), do: nil

  # SOFn markers (Start Of Frame): FFC0..FFCF except FFC4 (DHT), FFC8 (JPG
  # extension) and FFCC (DAC). Any of these carry width/height at bytes 3..6
  # of the segment payload.
  defp find_sof(<<0xFF, marker, size::16, payload_and_tail::binary>>)
       when marker in 0xC0..0xCF and marker not in [0xC4, 0xC8, 0xCC] do
    <<_precision, height::16, width::16, components, _::binary>> = payload_and_tail
    _ = size
    {:ok, width, height, components}
  end

  defp find_sof(<<0xFF, _marker, size::16, rest::binary>>) when byte_size(rest) >= size - 2 do
    data_size = size - 2
    <<_skip::binary-size(^data_size), tail::binary>> = rest
    find_sof(tail)
  end

  defp find_sof(<<0xFF, 0x00, rest::binary>>), do: find_sof(rest)
  defp find_sof(<<0xFF, rest::binary>>), do: find_sof(rest)
  defp find_sof(_), do: :error

  defp jpeg_colorspace(1), do: "/DeviceGray"
  defp jpeg_colorspace(3), do: "/DeviceRGB"
  defp jpeg_colorspace(4), do: "/DeviceCMYK"
  defp jpeg_colorspace(_), do: "/DeviceRGB"
end
