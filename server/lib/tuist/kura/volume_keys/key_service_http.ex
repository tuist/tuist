defmodule Tuist.Kura.VolumeKeys.KeyServiceHTTP do
  @moduledoc """
  Bounded HTTPS transport for key material. Unlike the shared ExAws/Finch
  path, this transport does not emit request/response bodies in telemetry.
  Never log a request, response, exception or transport error here.
  """

  def post(url, headers, content_type, body, ca_cert_file \\ nil) do
    request =
      {String.to_charlist(url), Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end),
       to_charlist(content_type), body}

    options = [
      timeout: 5_000,
      connect_timeout: 3_000,
      autoredirect: false,
      ssl:
        [
          verify: :verify_peer,
          customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
        ] ++ trust_options(ca_cert_file)
    ]

    case :httpc.request(:post, request, options, body_format: :binary) do
      {:ok, {{_, 200, _}, _, response}} -> {:ok, response}
      _ -> {:error, :key_service_unavailable}
    end
  rescue
    _ -> {:error, :key_service_unavailable}
  end

  defp trust_options(nil), do: [cacerts: :public_key.cacerts_get()]
  defp trust_options(path), do: [cacertfile: String.to_charlist(path)]
end
