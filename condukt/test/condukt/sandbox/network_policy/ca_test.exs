defmodule Condukt.Sandbox.NetworkPolicy.CATest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox.NetworkPolicy.CA

  describe "generate/1" do
    test "returns a struct with PEM-encoded cert and key" do
      {:ok, ca} = CA.generate(common_name: "test-session")

      assert ca.common_name == "test-session"
      assert ca.cert_pem =~ "-----BEGIN CERTIFICATE-----"
      assert ca.cert_pem =~ "-----END CERTIFICATE-----"
      assert ca.key_pem =~ "-----BEGIN PRIVATE KEY-----"
      assert ca.key_pem =~ "-----END PRIVATE KEY-----"
    end

    test "produces a parseable X.509 certificate with CA basic constraint" do
      {:ok, ca} = CA.generate(common_name: "x")

      cert = X509.Certificate.from_pem!(ca.cert_pem)
      ext = X509.Certificate.extension(cert, :basic_constraints)

      assert {:Extension, _oid, _critical, {:BasicConstraints, true, _}} = ext
    end

    test "subject CN matches the requested common_name" do
      {:ok, ca} = CA.generate(common_name: "session-xyz")

      cert = X509.Certificate.from_pem!(ca.cert_pem)
      subject = X509.Certificate.subject(cert)

      assert X509.RDNSequence.get_attr(subject, :commonName) == ["session-xyz"]
    end

    test "validity window covers now and excludes a year out" do
      {:ok, ca} = CA.generate(common_name: "x", validity_hours: 24, skew_hours: 1)

      now = DateTime.utc_now()
      year_out = DateTime.add(now, 365 * 24 * 3600, :second)

      assert DateTime.compare(ca.not_before, now) in [:lt, :eq]
      assert DateTime.after?(ca.not_after, now)
      assert DateTime.before?(ca.not_after, year_out)
    end

    test "each call produces an independent keypair" do
      {:ok, ca1} = CA.generate(common_name: "a")
      {:ok, ca2} = CA.generate(common_name: "a")

      refute ca1.cert_pem == ca2.cert_pem
      refute ca1.key_pem == ca2.key_pem
    end

    test "raises when common_name is missing" do
      assert_raise KeyError, fn ->
        CA.generate([])
      end
    end
  end
end
