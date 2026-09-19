defmodule Atlas.Letters.Pingen do
  @moduledoc false

  alias Atlas.Letters.Config
  alias Atlas.Letters.Letter

  require Logger

  @json_api_content_type "application/vnd.api+json"

  def send_letter(%Letter{} = letter, pdf) when is_binary(pdf) do
    with :ok <- enabled(),
         {:ok, token} <- access_token(),
         {:ok, upload} <- request_file_upload(token),
         :ok <- upload_file(upload.url, pdf),
         {:ok, response} <- create_letter(token, upload, letter) do
      {:ok, normalize_letter(response)}
    end
  end

  def get_letter(pingen_letter_id) when is_binary(pingen_letter_id) do
    with :ok <- enabled(),
         {:ok, token} <- access_token(),
         {:ok, response} <- get_letter(token, pingen_letter_id) do
      {:ok, normalize_letter(response)}
    end
  end

  defp enabled do
    if Config.configured?(), do: :ok, else: :disabled
  end

  defp access_token do
    request =
      Req.new(
        url: url(Config.identity_base_url(), "/auth/access-tokens"),
        receive_timeout: Config.receive_timeout()
      )
      |> Req.merge(
        form: [
          grant_type: "client_credentials",
          client_id: Config.client_id(),
          client_secret: Config.client_secret(),
          scope: "letter organisation_read"
        ]
      )

    case Req.post(request) do
      {:ok, %Req.Response{status: status, body: %{"access_token" => token}}} when status in 200..299 ->
        {:ok, token}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Pingen access token request failed: status=#{status} body=#{inspect(body)}")
        {:error, {:pingen_token_request_failed, status}}

      {:error, reason} ->
        Logger.warning("Pingen access token request failed: #{inspect(reason)}")
        {:error, {:pingen_token_request_failed, reason}}
    end
  end

  defp request_file_upload(token) do
    case Req.get(api_request(token, "/file-upload")) do
      {:ok, %Req.Response{status: status, body: %{"data" => %{"attributes" => attributes}}}}
      when status in 200..299 ->
        with url when is_binary(url) and url != "" <- attributes["url"],
             signature when is_binary(signature) and signature != "" <- attributes["url_signature"] do
          {:ok, %{url: url, signature: signature}}
        else
          _ -> {:error, :pingen_file_upload_response_invalid}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        log_provider_error("file upload request", status, body)
        {:error, {:pingen_file_upload_request_failed, status}}

      {:error, reason} ->
        Logger.warning("Pingen file upload request failed: #{inspect(reason)}")
        {:error, {:pingen_file_upload_request_failed, reason}}
    end
  end

  defp upload_file(url, pdf) do
    request =
      Req.new(url: url, receive_timeout: Config.receive_timeout(), headers: [{"content-type", "application/pdf"}])

    case Req.put(request, body: pdf) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        log_provider_error("file upload", status, body)
        {:error, {:pingen_file_upload_failed, status}}

      {:error, reason} ->
        Logger.warning("Pingen file upload failed: #{inspect(reason)}")
        {:error, {:pingen_file_upload_failed, reason}}
    end
  end

  defp create_letter(token, upload, %Letter{} = letter) do
    body = %{
      "data" => %{
        "type" => "letters",
        "attributes" => %{
          "file_original_name" => file_name(letter),
          "file_url" => upload.url,
          "file_url_signature" => upload.signature,
          "address_position" => "left",
          "auto_send" => true,
          "delivery_product" => Config.delivery_product(),
          "print_mode" => Config.print_mode(),
          "print_spectrum" => Config.print_spectrum(),
          "sender_address" => sender_address(letter),
          "meta_data" => %{"atlas_letter_id" => letter.id, "kind" => letter.kind}
        }
      }
    }

    request =
      api_request(token, "/organisations/#{Config.organisation_id()}/deliveries/letters")
      |> Req.merge(headers: [{"idempotency-key", letter.id}], json: body)

    case Req.post(request) do
      {:ok, %Req.Response{status: status, body: response}} when status in 200..299 and is_map(response) ->
        {:ok, response}

      {:ok, %Req.Response{status: status, body: body}} ->
        log_provider_error("letter creation", status, body)
        {:error, {:pingen_letter_creation_failed, status}}

      {:error, reason} ->
        Logger.warning("Pingen letter creation failed: #{inspect(reason)}")
        {:error, {:pingen_letter_creation_failed, reason}}
    end
  end

  defp get_letter(token, pingen_letter_id) do
    request = api_request(token, "/organisations/#{Config.organisation_id()}/deliveries/letters/#{pingen_letter_id}")

    case Req.get(request) do
      {:ok, %Req.Response{status: status, body: response}} when status in 200..299 and is_map(response) ->
        {:ok, response}

      {:ok, %Req.Response{status: status, body: body}} ->
        log_provider_error("letter status check", status, body)
        {:error, {:pingen_letter_status_failed, status}}

      {:error, reason} ->
        Logger.warning("Pingen letter status check failed: #{inspect(reason)}")
        {:error, {:pingen_letter_status_failed, reason}}
    end
  end

  defp api_request(token, path) do
    Req.new(
      url: url(Config.api_base_url(), path),
      auth: {:bearer, token},
      receive_timeout: Config.receive_timeout(),
      headers: [
        {"accept", @json_api_content_type},
        {"content-type", @json_api_content_type}
      ]
    )
  end

  defp normalize_letter(%{"data" => %{"id" => id, "attributes" => attributes}}) when is_map(attributes) do
    %{
      id: id,
      status: attributes["status"],
      tracking_number: attributes["tracking_number"],
      submitted_at: parse_datetime(attributes["submitted_at"]),
      delivered_at: parse_datetime(attributes["delivered_at"]),
      undeliverable_at: parse_datetime(attributes["undeliverable_at"]),
      raw: attributes
    }
  end

  defp normalize_letter(_response), do: %{id: nil, status: nil, tracking_number: nil, raw: %{}}

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    normalized_value = Regex.replace(~r/([+-]\d{2})(\d{2})$/, value, "\\1:\\2")

    case DateTime.from_iso8601(normalized_value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _ -> nil
    end
  end

  defp sender_address(letter) do
    [
      letter.sender_name,
      letter.sender_street,
      "#{letter.sender_postal_code} #{letter.sender_city}",
      letter.sender_country
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" | ")
  end

  defp file_name(letter), do: "atlas-#{letter.kind}-#{letter.id}.pdf"

  defp url(base_url, path) do
    base_url
    |> URI.parse()
    |> URI.append_path(path)
    |> URI.to_string()
  end

  defp log_provider_error(operation, status, body) do
    request_id =
      case body do
        %{"request_id" => value} -> value
        _ -> nil
      end

    Logger.warning("Pingen #{operation} failed: status=#{status} request_id=#{inspect(request_id)}")
  end
end
