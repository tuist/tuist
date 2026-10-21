defmodule Tuist.Application.CertificateTrustTest do
  use ExUnit.Case, async: true

  alias Tuist.Application.CertificateTrust

  @fixture Path.join(__DIR__, "fixtures/aaa-certificate-services.pem")

  test "does not alter the shared CA cache outside the macOS processor" do
    assert :ok = CertificateTrust.configure!(:web, {:unix, :darwin})
    assert :ok = CertificateTrust.configure!(:xcresult_processor, {:unix, :linux})
  end

  test "accepts an unrelated public trust anchor" do
    path = Path.join(__DIR__, "fixtures/isrg-root-x1.pem")
    [{:Certificate, der, :not_encrypted}] = path |> File.read!() |> :public_key.pem_decode()
    assert :ok = CertificateTrust.assert_clean!([der])
  end

  test "rejects an empty effective store" do
    assert_raise RuntimeError, ~r/empty CA store/, fn -> CertificateTrust.assert_clean!([]) end
  end

  test "rejects a blocked public key in both OTP and plain certificate forms" do
    for fixture <- [@fixture, Path.join(__DIR__, "fixtures/emsign-ecc-g3.pem")] do
      [{:Certificate, der, :not_encrypted}] = fixture |> File.read!() |> :public_key.pem_decode()

      for certificate <- [der, {:cert, der, :public_key.pkix_decode_cert(der, :otp)}] do
        assert_raise RuntimeError, ~r/distrusted CA SPKI/, fn ->
          CertificateTrust.assert_clean!([certificate])
        end
      end
    end
  end
end
