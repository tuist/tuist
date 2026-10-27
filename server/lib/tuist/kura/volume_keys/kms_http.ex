defmodule Tuist.Kura.VolumeKeys.KMSHTTP do
  @moduledoc """
  Bounded HTTPS transport for key material. Unlike the shared ExAws/Finch
  path, this transport does not emit request/response bodies in telemetry.
  Never log a request, response, exception or transport error here.
  """

  def post(url, headers, content_type, body) do
    request =
      {String.to_charlist(url), Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end),
       to_charlist(content_type), body}

    options = [
      timeout: 5_000,
      connect_timeout: 3_000,
      autoredirect: false,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    ]

    case :httpc.request(:post, request, options, body_format: :binary) do
      {:ok, {{_, 200, _}, _, response}} -> {:ok, response}
      _ -> {:error, :kms_unavailable}
    end
  rescue
    _ -> {:error, :kms_unavailable}
  end
end
