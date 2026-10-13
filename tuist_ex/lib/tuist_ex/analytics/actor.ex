defmodule TuistEx.Analytics.Actor do
  @moduledoc false

  alias TuistEx.Analytics.Config

  def identifier(options \\ []) do
    environment = Keyword.get(options, :environment, &System.get_env/1)

    value =
      with nil <- environment.("TUIST_ACTOR_ID"),
           nil <- Keyword.get(options, :actor_id),
           nil <- Keyword.get(Config.project_tuist_config(options), :actor_id) do
        Enum.find_value(~w(USER USERNAME LOGNAME), fn key ->
          case environment.(key) do
            "" -> nil
            value -> value
          end
        end)
      end

    if is_binary(value) and byte_size(value) in 1..128 and String.valid?(value) and
         Regex.match?(~r/\A[\x21-\x7e]+\z/, value) do
      value
    end
  end

  def headers(options \\ []) do
    case identifier(options) do
      nil -> []
      id -> [{"x-tuist-actor-id", id}]
    end
  end
end
