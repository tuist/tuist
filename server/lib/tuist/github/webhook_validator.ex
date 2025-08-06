defmodule Tuist.GitHub.WebhookValidator do
  @moduledoc """
  Validates GitHub webhook signatures to ensure requests are authentic.
  """
  
  use Bitwise

  @doc """
  Validates a GitHub webhook request by comparing the signature in the request
  with the expected signature calculated from the payload and secret.

  ## Parameters
    - payload: The raw request body as a string
    - signature_header: The value of the X-Hub-Signature-256 header
    - secret: The webhook secret configured in GitHub

  ## Returns
    - {:ok, :valid} if the signature is valid
    - {:error, :invalid_signature} if the signature is invalid
    - {:error, :missing_signature} if the signature header is missing
  """
  def validate_signature(payload, signature_header, secret) when is_binary(payload) and is_binary(secret) do
    case signature_header do
      nil ->
        {:error, :missing_signature}

      "sha256=" <> provided_signature ->
        expected_signature = calculate_signature(payload, secret)

        if secure_compare(provided_signature, expected_signature) do
          {:ok, :valid}
        else
          {:error, :invalid_signature}
        end

      _ ->
        {:error, :invalid_signature}
    end
  end

  def validate_signature(_payload, _signature_header, nil) do
    {:error, :missing_secret}
  end

  defp calculate_signature(payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, payload)
    |> Base.encode16(case: :lower)
  end

  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    if byte_size(a) == byte_size(b) do
      a
      |> :binary.bin_to_list()
      |> Enum.zip(:binary.bin_to_list(b))
      |> Enum.reduce(0, fn {x, y}, acc -> acc ||| bxor(x, y) end) == 0
    else
      false
    end
  end

  defp secure_compare(_a, _b), do: false
end