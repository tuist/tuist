defmodule Tuist.Application.CertificateTrustTest do
  use ExUnit.Case, async: true

  alias Tuist.Application.CertificateTrust

  # Public certificates from #14511's incident controls. Keep the twelve-key
  # inventory self-contained: four issuer roots and eight intermediates.
  @fixtures Path.join(__DIR__, "fixtures")

  test "leaves the shared CA cache alone outside the macOS xcresult processor" do
    for mode <- [:web, :processor, :swift_registry_sync],
        os <- [{:unix, :darwin}, {:unix, :linux}] do
      assert :ok = CertificateTrust.configure!(mode, os)
    end

    assert :ok = CertificateTrust.configure!(:xcresult_processor, {:unix, :linux})
  end

  test "accepts unrelated public and private trust anchors in both certificate forms" do
    [public] = certificates("isrg-root-x1.pem")

    %{cert: private} =
      :public_key.pkix_test_root_cert(~c"Enterprise test CA", key: {:namedCurve, {1, 2, 840, 10_045, 3, 1, 7}})

    assert :ok = CertificateTrust.assert_clean!([public, private])
    assert :ok = CertificateTrust.assert_clean!([otp_certificate(public), otp_certificate(private)])
  end

  test "rejects an empty effective store" do
    assert_raise RuntimeError, ~r/empty CA store/, fn -> CertificateTrust.assert_clean!([]) end
  end

  test "rejects every incident key in mixed stores and both certificate forms" do
    [healthy] = certificates("isrg-root-x1.pem")
    blocked = certificates("issuer-roots.pem") ++ certificates("distrusted-intermediates.pem")
    assert length(blocked) == 12
    assert length(Enum.uniq(blocked)) == 12

    for der <- blocked, certificate <- [der, otp_certificate(der)] do
      assert_raise RuntimeError, ~r/distrusted CA SPKI [a-f0-9]{64}/, fn ->
        CertificateTrust.assert_clean!([healthy, certificate, healthy])
      end
    end
  end

  defp certificates(name) do
    for {:Certificate, der, :not_encrypted} <- @fixtures |> Path.join(name) |> File.read!() |> :public_key.pem_decode() do
      der
    end
  end

  defp otp_certificate(der), do: {:cert, der, :public_key.pkix_decode_cert(der, :otp)}
end
