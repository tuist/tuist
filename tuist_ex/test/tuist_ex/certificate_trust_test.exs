defmodule TuistEx.CertificateTrustTest do
  use ExUnit.Case, async: true

  alias TuistEx.CertificateTrust

  test "rejects all twelve actual policy keys as DER and OTP certificates" do
    certificates = certificates("issuer-roots") ++ certificates("distrusted-intermediates")
    assert length(certificates) == 12

    for der <- certificates,
        certificate <- [der, :public_key.pkix_decode_cert(der, :otp)],
        event <- [:valid, :valid_peer] do
      assert {:fail, :distrusted_certificate_key} =
               CertificateTrust.verify_certificate(certificate, event, nil)
    end
  end

  test "filters blocked anchors without changing the VM CA cache or unrelated anchors" do
    [positive] = certificates("positive-isrg-root-x1")
    blocked = certificates("issuer-roots")
    encoded = Enum.map(blocked, &{:cert, &1, :public_key.pkix_decode_cert(&1, :otp)})

    for roots <- [blocked ++ [positive], encoded ++ [positive]] do
      options = CertificateTrust.ssl_options(roots)
      assert options[:cacerts] == [positive]
      assert options[:verify] == :verify_peer
      assert {callback, nil} = options[:verify_fun]
      assert is_function(callback, 3)
      assert is_function(options[:customize_hostname_check][:match_fun], 2)
    end

    assert CertificateTrust.ssl_options(blocked)[:cacerts] == []
  end

  test "preserves unrelated chains and does not override normal verification failures" do
    for certificate <- certificates("positive-isrg-root-x1") ++ certificates("positive-isrg-r11"),
        event <- [:valid, :valid_peer] do
      assert {:valid, :state} = CertificateTrust.verify_certificate(certificate, event, :state)
    end

    for reason <- [:cert_expired, :invalid_signature, :hostname_check_failed, :unknown_ca] do
      assert {:fail, ^reason} = CertificateTrust.verify_certificate(nil, {:bad_cert, reason}, nil)
    end

    assert {:unknown, :state} =
             CertificateTrust.verify_certificate(nil, {:extension, :critical}, :state)

    assert {:fail, :invalid_certificate} =
             CertificateTrust.verify_certificate(<<0>>, :valid_peer, nil)
  end

  test "actual OTP and Mint HTTP/2 TLS handshakes preserve private CAs and reject invalid trust" do
    {:ok, _} = Application.ensure_all_started(:ssl)

    configuration =
      :public_key.pkix_test_data(%{
        root: [digest: :sha256, key: {:rsa, 2048, 65_537}],
        peer: [
          digest: :sha256,
          key: {:rsa, 2048, 65_537},
          extensions: [{:Extension, {2, 5, 29, 17}, false, [{:dNSName, ~c"localhost"}]}]
        ]
      })

    roots = Keyword.fetch!(configuration, :cacerts)

    for transport <- [:otp, :mint] do
      assert {:ok, _} = connect(configuration, ~c"localhost", roots, transport)
      assert {:error, _} = connect(configuration, ~c"127.0.0.1", roots, transport)

      assert {:error, _} =
               connect(
                 configuration,
                 ~c"localhost",
                 certificates("positive-isrg-root-x1"),
                 transport
               )
    end
  end

  defp connect(configuration, hostname, roots, transport) do
    {:ok, listener} =
      :ssl.listen(
        0,
        configuration ++ [active: false, reuseaddr: true, alpn_preferred_protocols: ["h2"]]
      )

    {:ok, {_, port}} = :ssl.sockname(listener)

    server =
      Task.async(fn ->
        with {:ok, socket} <- :ssl.transport_accept(listener, 5_000),
             {:ok, socket} <- :ssl.handshake(socket, 5_000) do
          receive do
            :close -> :ssl.close(socket)
          after
            5_000 -> :ssl.close(socket)
          end
        end
      end)

    options = CertificateTrust.ssl_options(roots) ++ [active: false]

    result =
      case transport do
        :otp ->
          :ssl.connect(hostname, port, options, 5_000)

        :mint ->
          Mint.HTTP2.connect(:https, List.to_string(hostname), port, transport_opts: options)
      end

    if match?({:ok, _}, result) do
      case transport do
        :otp -> :ssl.close(elem(result, 1))
        :mint -> Mint.HTTP2.close(elem(result, 1))
      end
    end

    send(server.pid, :close)
    Task.await(server, 10_000)
    :ssl.close(listener)
    result
  end

  defp certificates(name) do
    "fixtures/certificate_trust/#{name}.pem"
    |> Path.expand(__DIR__)
    |> File.read!()
    |> :public_key.pem_decode()
    |> Enum.map(fn {:Certificate, der, :not_encrypted} -> der end)
  end
end
