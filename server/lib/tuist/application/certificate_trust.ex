defmodule Tuist.Application.CertificateTrust do
  @moduledoc false

  # The Go policy test checks equality with infra/certificate-trust/policy.json.
  @blocked MapSet.new(~w(
    8d417db2dd8bf5e3084d1e3f196d583849d81bdd4c00c70b9d39369e96b8c782
    bd153ed7b0434f6886b17bce8bbe84ed340c7132d702a8f4fa318f756ecbd6f3
    ebed6475c2c2d80fcb199f3fe8dd6e6b3ce60b77eb15d4e42c3dec0c6f5b5105
    49dd353dc2b919a3770645117d0e60c16115e7d1bc259eefe734b00ea434fe5f
    e0254c7fcdc265e2f0f8a428dabb75ab4ae039b4872d62f5ee57f0877d5a8a41
    5c0660a2b164910d8ff589c18e14552e9e0ec237dcefe2cb736d41a4811f81a0
    43bffa19d6ef651451f6841e019931e96f6f2eaeff28ab4b6f1ce4576de2717b
    63ecefee431d49523bc1136c4e72d0206a477086caf606cd5cf025686c109cf8
    ec4ffa1ad0ac88081314b7aaffef6a91f97cd57291bb5ba686c5415f5eb4f6b6
    92c063d67e8f14db71d288e11266ffdaf69cbf115f7bab14f3bc2f68d25e0e30
    c619e4780ed8e0abeda24ad732567de4383a7ea941338f6d1a7d1b49ac792fe9
    0a6c2b2ca5b364207954171987ac9d2178561569d8205457e77ca90c32ede282
  ))

  def configure!(:xcresult_processor, {:unix, :darwin}) do
    # OTP exports keychain certificates without consulting Apple's deny settings.
    :ok = :public_key.cacerts_load(~c"/etc/ssl/cert.pem")
    assert_clean!(:public_key.cacerts_get())
  end

  def configure!(_, _), do: :ok

  def assert_clean!([]), do: raise("Refusing to start with an empty CA store")

  def assert_clean!(certificates) do
    Enum.each(certificates, fn certificate ->
      der =
        case certificate do
          {:cert, der, _decoded} -> der
          der when is_binary(der) -> der
        end

      {:Certificate, tbs, _algorithm, _signature} = :public_key.pkix_decode_cert(der, :plain)
      spki = :public_key.der_encode(:SubjectPublicKeyInfo, elem(tbs, 7))
      hash = :sha256 |> :crypto.hash(spki) |> Base.encode16(case: :lower)

      if MapSet.member?(@blocked, hash) do
        raise "Refusing to start with distrusted CA SPKI #{hash}"
      end
    end)

    :ok
  end
end
