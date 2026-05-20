defmodule Tuist.Apple do
  @moduledoc false
  @devices "priv/apple.json"
           |> File.read!()
           |> JSON.decode!()
  def devices do
    @devices
  end
end
