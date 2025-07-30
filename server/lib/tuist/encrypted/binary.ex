defmodule Tuist.Encrypted.Binary do
  use Cloak.Ecto.Binary, vault: Tuist.Vault
end