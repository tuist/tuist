defmodule TuistEx.CertificateTrust do
  @moduledoc false

  # Public key evidence: https://emudhra.we-have-a-problem.com/roots.json
  # and https://emudhra.we-have-a-problem.com/impacted-intermediates.json.
  # Local certificate fixtures cover every key. Ship the policy in the Hex package.
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

  def ssl_options(certificates \\ :public_key.cacerts_get()) do
    [
      verify: :verify_peer,
      cacerts: Enum.reject(certificates, &blocked?/1),
      verify_fun: {&verify_certificate/3, nil},
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
  end

  # OTP uses the complete failure tuple to try alternate/cross-signed paths.
  def verify_certificate(_certificate, {:bad_cert, _reason} = failure, _state),
    do: {:fail, failure}

  def verify_certificate(_certificate, {:extension, _extension}, state), do: {:unknown, state}

  def verify_certificate(certificate, event, state) when event in [:valid, :valid_peer] do
    if blocked?(certificate), do: {:fail, :distrusted_certificate_key}, else: {:valid, state}
  rescue
    _ -> {:fail, :invalid_certificate}
  end

  defp blocked?({:cert, der, _decoded}), do: blocked?(der)

  defp blocked?({:OTPCertificate, _, _, _} = certificate) do
    :OTPCertificate |> :public_key.pkix_encode(certificate, :otp) |> blocked?()
  end

  defp blocked?(der) when is_binary(der) do
    {:Certificate, tbs, _algorithm, _signature} = :public_key.pkix_decode_cert(der, :plain)
    spki = :public_key.der_encode(:SubjectPublicKeyInfo, elem(tbs, 7))
    hash = :sha256 |> :crypto.hash(spki) |> Base.encode16(case: :lower)
    MapSet.member?(@blocked, hash)
  end
end
