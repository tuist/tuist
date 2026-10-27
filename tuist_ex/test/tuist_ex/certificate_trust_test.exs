defmodule TuistEx.CertificateTrustTest do
  use ExUnit.Case, async: true

  alias TuistEx.CertificateTrust

  test "rejects all twelve actual policy keys as DER and OTP certificates" do
    certificates = certificates("issuer-roots") ++ certificates("distrusted-intermediates")
    assert length(certificates) == 12
    assert CertificateTrust.blocked_spki_hashes() == MapSet.new(certificates, &spki/1)

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
      assert {:fail, {:bad_cert, ^reason}} =
               CertificateTrust.verify_certificate(nil, {:bad_cert, reason}, nil)
    end

    assert {:unknown, :state} =
             CertificateTrust.verify_certificate(
               nil,
               {:extension, {:Extension, {1, 2, 3, 4}, true, <<5, 0>>}},
               :state
             )

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

  test "actual OTP and Mint handshakes reject otherwise accepted leaf, intermediate and absent-root keys" do
    {:ok, _} = Application.ensure_all_started(:ssl)
    key = [digest: :sha256, key: {:rsa, 2048, 65_537}]

    configuration =
      :public_key.pkix_test_data(%{
        root: key,
        intermediates: [key],
        peer:
          key ++ [extensions: [{:Extension, {2, 5, 29, 17}, false, [{:dNSName, ~c"localhost"}]}]]
      })

    [root, intermediate] = Enum.uniq(configuration[:cacerts])
    leaf = configuration[:cert]

    configuration =
      configuration |> Keyword.put(:cert, [leaf, intermediate]) |> Keyword.put(:cacerts, [])

    for transport <- [:otp, :mint], denied <- [leaf, intermediate, root] do
      assert {:ok, _} = connect(configuration, ~c"localhost", [root], transport, :native)
      assert {:ok, _} = connect(configuration, ~c"localhost", [root], transport)

      assert {:error, _} =
               connect(configuration, ~c"localhost", [root], transport, {:deny, [spki(denied)]})

      assert {:ok, _} = connect(configuration, ~c"localhost", [root], transport)
    end

    # Additional restrictions cannot replace or remove the shipped policy.
    for der <- certificates("issuer-roots") ++ certificates("distrusted-intermediates") do
      {callback, state} = CertificateTrust.ssl_options([root], [spki(leaf)])[:verify_fun]
      assert {:fail, :distrusted_certificate_key} = callback.(der, :valid_peer, state)
    end
  end

  test "unknown critical extensions remain native failures on OTP and Mint" do
    {:ok, _} = Application.ensure_all_started(:ssl)
    key = [digest: :sha256, key: {:rsa, 2048, 65_537}]

    configuration =
      :public_key.pkix_test_data(%{
        root: key,
        peer:
          key ++
            [
              extensions: [
                {:Extension, {2, 5, 29, 17}, false, [{:dNSName, ~c"localhost"}]},
                {:Extension, {1, 3, 6, 1, 4, 1, 55555, 1}, true, <<5, 0>>}
              ]
            ]
      })

    for transport <- [:otp, :mint], verification <- [:native, :protected] do
      assert {:error, _} =
               connect(
                 configuration,
                 ~c"localhost",
                 configuration[:cacerts],
                 transport,
                 verification
               )
    end
  end

  test "preserves native cross-signed path repair without accepting an unknown anchor" do
    {:ok, _} = Application.ensure_all_started(:ssl)
    key_options = [digest: :sha256, key: {:rsa, 2048, 65_537}]
    trusted = :public_key.pkix_test_root_cert(~c"Trusted anchor", key_options)
    absent = :public_key.pkix_test_root_cert(~c"Absent anchor", key_options)

    configuration =
      :public_key.pkix_test_data(%{
        root: trusted,
        peer: [
          digest: :sha256,
          key: {:rsa, 2048, 65_537},
          extensions: [{:Extension, {2, 5, 29, 17}, false, [{:dNSName, ~c"localhost"}]}]
        ]
      })

    {:OTPCertificate, trusted_tbs, _, _} = :public_key.pkix_decode_cert(trusted.cert, :otp)
    {:OTPCertificate, absent_tbs, _, _} = :public_key.pkix_decode_cert(absent.cert, :otp)
    cross_tbs = put_elem(trusted_tbs, 4, elem(absent_tbs, 6))
    cross_signed = :public_key.pkix_sign(cross_tbs, absent.key)

    # Serve the cross-sign, not the available self-signed anchor. OTP initially
    # finds an unknown issuer, then substitutes its trusted version of that key.
    configuration =
      configuration
      |> Keyword.put(:cert, [Keyword.fetch!(configuration, :cert), cross_signed])
      |> Keyword.put(:cacerts, [])

    options = CertificateTrust.ssl_options([trusted.cert])

    assert {:error, {:bad_cert, :unknown_ca}} =
             :public_key.pkix_path_validation(:unknown_ca, [cross_signed],
               verify_fun: options[:verify_fun]
             )

    legacy_callback = fn
      _certificate, {:bad_cert, reason}, _state -> {:fail, reason}
      certificate, event, state -> CertificateTrust.verify_certificate(certificate, event, state)
    end

    for transport <- [:otp, :mint] do
      assert {:ok, _} = connect(configuration, ~c"localhost", [trusted.cert], transport, :native)

      if transport == :otp do
        assert {:error, {:tls_alert, {:handshake_failure, _private_message}}} =
                 connect(configuration, ~c"localhost", [trusted.cert], transport, legacy_callback)
      end

      assert {:ok, _} = connect(configuration, ~c"localhost", [trusted.cert], transport)

      assert {:error, _} =
               connect(
                 configuration,
                 ~c"localhost",
                 certificates("positive-isrg-root-x1"),
                 transport
               )
    end
  end

  defp connect(configuration, hostname, roots, transport, verification \\ :protected) do
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

    additional =
      case verification do
        {:deny, hashes} -> hashes
        _ -> []
      end

    options = CertificateTrust.ssl_options(roots, additional) ++ [active: false]

    options =
      cond do
        verification == :native -> Keyword.delete(options, :verify_fun)
        is_function(verification, 3) -> Keyword.put(options, :verify_fun, {verification, nil})
        true -> options
      end

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

  defp spki(der) do
    {:Certificate, tbs, _, _} = :public_key.pkix_decode_cert(der, :plain)

    :sha256
    |> :crypto.hash(:public_key.der_encode(:SubjectPublicKeyInfo, elem(tbs, 7)))
    |> Base.encode16(case: :lower)
  end

  defp certificates(name) do
    "fixtures/certificate_trust/#{name}.pem"
    |> Path.expand(__DIR__)
    |> File.read!()
    |> :public_key.pem_decode()
    |> Enum.map(fn {:Certificate, der, :not_encrypted} -> der end)
  end
end
