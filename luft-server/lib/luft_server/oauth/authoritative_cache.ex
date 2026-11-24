defmodule LuftServer.OAuth.AuthoritativeCache do
  @moduledoc "Boruta entity reads always fall through to PostgreSQL, including after revocation."

  def get(_key), do: nil
  def put(_key, _value, _opts \\ []), do: :ok
  def delete(_key), do: :ok
end
