defmodule Tuist.Accounts.SSOLoginDomainVerification do
  @moduledoc false

  @lookup_timeout 5_000

  def record_name(domain), do: "_tuist-verification.#{domain}"
  def record_value(token), do: "tuist-domain-verification=#{token}"

  def verified?(domain, token) do
    expected_value = record_value(token)

    domain
    |> record_name()
    |> String.to_charlist()
    |> :inet_res.lookup(:in, :txt, [], @lookup_timeout)
    |> Enum.any?(fn chunks ->
      chunks
      |> List.flatten()
      |> List.to_string()
      |> Kernel.==(expected_value)
    end)
  catch
    _, _ -> false
  end
end
