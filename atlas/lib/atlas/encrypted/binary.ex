defmodule Atlas.Encrypted.Binary do
  use Cloak.Ecto.Binary, vault: Atlas.Vault
end
