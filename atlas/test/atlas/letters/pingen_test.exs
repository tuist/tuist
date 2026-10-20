defmodule Atlas.Letters.PingenTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Letters.Config
  alias Atlas.Letters.Letter
  alias Atlas.Letters.Pingen

  setup :verify_on_exit!

  test "submits letters using supported provider attributes and preserves the idempotency key" do
    stub(Config, :configured?, fn -> true end)
    stub(Config, :client_id, fn -> "client" end)
    stub(Config, :client_secret, fn -> "secret" end)
    stub(Config, :identity_base_url, fn -> "https://identity.example.com" end)
    stub(Config, :api_base_url, fn -> "https://api.example.com" end)
    stub(Config, :organisation_id, fn -> "organisation" end)
    stub(Config, :receive_timeout, fn -> 15_000 end)
    stub(Config, :delivery_product, fn -> "fast" end)
    stub(Config, :print_mode, fn -> "simplex" end)
    stub(Config, :print_spectrum, fn -> "color" end)

    letter = %Letter{
      id: "letter-id",
      kind: "tax_certificate_request",
      sender_name: "Tuist GmbH",
      sender_street: "Jessnerstrasse 27a",
      sender_postal_code: "10247",
      sender_city: "Berlin",
      sender_country: "DE"
    }

    expect(Req, :post, fn request ->
      assert URI.to_string(request.url) == "https://identity.example.com/auth/access-tokens"
      {:ok, %Req.Response{status: 200, body: %{"access_token" => "token"}}}
    end)

    expect(Req, :get, fn request ->
      assert URI.to_string(request.url) == "https://api.example.com/file-upload"

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "data" => %{
             "attributes" => %{
               "url" => "https://upload.example.com/letter",
               "url_signature" => "signature"
             }
           }
         }
       }}
    end)

    expect(Req, :put, fn request, opts ->
      assert URI.to_string(request.url) == "https://upload.example.com/letter"
      assert opts[:body] == "signed document"
      {:ok, %Req.Response{status: 200}}
    end)

    expect(Req, :post, fn request ->
      assert URI.to_string(request.url) ==
               "https://api.example.com/organisations/organisation/deliveries/letters"

      assert request.options.auth == {:bearer, "token"}
      assert Req.Request.get_header(request, "idempotency-key") == [letter.id]

      assert request.options.json == %{
               "data" => %{
                 "type" => "letters",
                 "attributes" => %{
                   "file_original_name" => "atlas-tax_certificate_request-letter-id.pdf",
                   "file_url" => "https://upload.example.com/letter",
                   "file_url_signature" => "signature",
                   "address_position" => "left",
                   "auto_send" => true,
                   "delivery_product" => "fast",
                   "print_mode" => "simplex",
                   "print_spectrum" => "color"
                 }
               }
             }

      {:ok,
       %Req.Response{
         status: 201,
         body: %{"data" => %{"id" => "provider-id", "attributes" => %{}}}
       }}
    end)

    assert {:ok, %{id: "provider-id"}} = Pingen.send_letter(letter, "signed document")
  end
end
