# Invoked by openbao_integration.rb against its disposable local service only.
# Uses the production provider and TLS transport; no HTTP or identity mocks.
alias Tuist.Environment
alias Tuist.Kura.VolumeKeys.OpenBaoShareProvider

Application.ensure_all_started(:inets)
Application.ensure_all_started(:ssl)

ensure = fn condition, description ->
  if !condition, do: raise(description)
end

{:ok, config} = Environment.kura_volume_openbao()
ensure.(config.address == "https://localhost:18820", "refusing a non-local integration target")
[mode, state_file] = System.argv()
aad = "kura-tenant-key/v1|integration-tenant|1|0"

case mode do
  "seed" ->
    plaintext = :crypto.strong_rand_bytes(32)
    result = OpenBaoShareProvider.wrap(plaintext, aad)
    ensure.(match?({:ok, _}, result), "real Transit encrypt failed")
    {:ok, wrapped} = result
    ensure.(OpenBaoShareProvider.unwrap(wrapped, aad) == {:ok, plaintext}, "real Transit round trip failed")
    File.write!(state_file, :erlang.term_to_binary({plaintext, wrapped}))
    File.chmod!(state_file, 0o600)

  "verify" ->
    {plaintext, wrapped} = state_file |> File.read!() |> :erlang.binary_to_term([:safe])
    ensure.(OpenBaoShareProvider.unwrap(wrapped, aad) == {:ok, plaintext}, "saved share did not recover")

    for changed <- ["kura-tenant-key/v1|other|1|0", "kura-tenant-key/v1|integration-tenant|2|0", aad <> "1"] do
      ensure.(
        OpenBaoShareProvider.unwrap(wrapped, changed) == {:error, :key_service_unavailable},
        "context substitution accepted"
      )
    end

  "rotated" ->
    {plaintext, wrapped} = state_file |> File.read!() |> :erlang.binary_to_term([:safe])
    ensure.(OpenBaoShareProvider.unwrap(wrapped, aad) == {:ok, plaintext}, "rotation lost the old version")
    result = OpenBaoShareProvider.wrap(plaintext, aad)
    ensure.(match?({:ok, _}, result), "post-rotation encrypt failed")
    {:ok, new} = result
    ensure.(String.starts_with?(new["ciphertext"], "vault:v2:"), "new encryption did not use rotated key")
    ensure.(OpenBaoShareProvider.unwrap(new, aad) == {:ok, plaintext}, "rotated envelope changed the share")

  "denied" ->
    {_, wrapped} = state_file |> File.read!() |> :erlang.binary_to_term([:safe])

    ensure.(
      OpenBaoShareProvider.unwrap(wrapped, aad) == {:error, :key_service_unavailable},
      "unauthorized or sealed access accepted"
    )
end

IO.puts("PASS: production OpenBao provider #{mode}")
