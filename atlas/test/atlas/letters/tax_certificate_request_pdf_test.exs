defmodule Atlas.Letters.TaxCertificateRequestPDFTest do
  use ExUnit.Case, async: true

  alias Atlas.Letters.Letter
  alias Atlas.Letters.TaxCertificateRequestPDF

  test "preserves the official template beneath a postal cover and inset form pages" do
    letter = %Letter{
      recipient_name: "Tax office",
      recipient_street: "Example Street 13",
      recipient_postal_code: "12099",
      recipient_city: "Berlin",
      sender_name: "Example Company",
      sender_street: "Example Street 27a",
      sender_postal_code: "10247",
      sender_city: "Berlin",
      signatory_title: "Managing director",
      tax_id: "123/456/789",
      template_data: %{
        "submission_to" => "Customer",
        "certificate_purpose" => "Supplier compliance"
      }
    }

    document = TaxCertificateRequestPDF.render(letter)

    template =
      File.read!(
        Application.app_dir(
          :atlas,
          "priv/atlas/letters/templates/berlin-tax-certificate-request.pdf"
        )
      )

    assert binary_part(document, 0, byte_size(template)) == template
    [_, page_tree] = ~r/\n2 0 obj\n(.*?)\nendobj/s |> Regex.scan(document) |> List.last()
    assert page_tree =~ "/Count 3"
    assert page_tree =~ "/Kids[139 0 R 3 0 R 20 0 R]"
    assert document =~ "(Tax certificate request) Tj"
    assert document =~ "(Tax office) Tj"
    assert document =~ "(Example Street 13) Tj"

    for contents <- ["4 0 R 135 0 R", "21 0 R 136 0 R"] do
      assert document =~ "/Contents[141 0 R #{contents} 142 0 R]"
    end

    assert document =~ "0.85 0 0 0.85 44.649 63.144 cm"
    [_, offset] = ~r/startxref\n(\d+)\n%%EOF/ |> Regex.scan(document) |> List.last()
    offset = String.to_integer(offset)
    xref = binary_part(document, offset, byte_size(document) - offset)
    assert String.starts_with?(xref, "xref\n")

    for [_, number, object_offset] <- Regex.scan(~r/(\d+) 1\n(\d{10}) 00000 n/, xref) do
      object_offset = String.to_integer(object_offset)
      object = "#{number} 0 obj\n"
      assert binary_part(document, object_offset, byte_size(object)) == object
    end
  end
end
