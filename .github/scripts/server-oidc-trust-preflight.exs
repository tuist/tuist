unless System.get_env("TUIST_TRUST_LIVE") == "1" do
  raise "Credential-free public trust preflight requires TUIST_TRUST_LIVE=1"
end

try do
  Code.require_file("../../tuist_ex/lib/tuist_ex/certificate_trust.ex", __DIR__)
  Code.require_file("../../tuist_ex/lib/tuist_ex/http.ex", __DIR__)
  Mix.start()
  {:ok, _} = Application.ensure_all_started(:ssl)
  {:ok, _} = Application.ensure_all_started(:inets)

  native_roots = :public_key.cacerts_get()
  protected = TuistEx.CertificateTrust.ssl_options(native_roots)
  native = protected |> Keyword.delete(:verify_fun) |> Keyword.put(:cacerts, native_roots)

  for {name, roots} <- [native: native_roots, protected: Keyword.fetch!(protected, :cacerts)] do
    google_roots =
      Enum.count(roots, fn certificate ->
        der =
          case certificate do
            {:cert, der, _decoded} -> der
            der when is_binary(der) -> der
          end

        {:Certificate, tbs, _, _} = :public_key.pkix_decode_cert(der, :plain)
        subject = :public_key.der_encode(:Name, elem(tbs, 6))
        :binary.match(subject, "GTS Root R4") != :nomatch
      end)

    IO.puts("#{name}: roots=#{length(roots)} gts_root_r4=#{google_roots}")
  end

  connect = fn name, options ->
    options = [active: false, server_name_indication: ~c"tuist.dev"] ++ options

    result =
      case :ssl.connect(~c"tuist.dev", 443, options, 10_000) do
        {:ok, socket} ->
          :ssl.close(socket)
          :accepted

        {:error, {:tls_alert, {alert, _private_message}}} ->
          {:rejected, alert}

        {:error, _private_reason} ->
          {:rejected, :transport_failure}
      end

    IO.inspect(result, label: "#{name} credential-free TLS")
    result == :accepted
  end

  native_ok = connect.(:native, native)
  protected_ok = connect.(:protected, protected)

  http_ok =
    case TuistEx.HTTP.request(:get, "https://tuist.dev/.well-known/openid-configuration") do
      {:ok, status, _private_body} ->
        IO.puts("protected credential-free HTTP: status=#{status}")
        true

      {:error, _private_reason} ->
        IO.puts("protected credential-free HTTP: transport_failure")
        false
    end

  unless native_ok and protected_ok and http_ok do
    raise "Public native/protected certificate preflight failed; refusing credential-bearing OIDC requests"
  end
rescue
  _ ->
    raise "Public trust preflight failed; refusing credential-bearing OIDC requests (private details suppressed)"
end
