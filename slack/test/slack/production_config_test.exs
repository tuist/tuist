defmodule Slack.ProductionConfigTest do
  use ExUnit.Case, async: true

  test "production uses bundled timezone data without writing into the read-only release" do
    config = Config.Reader.read!(Path.expand("../../config/config.exs", __DIR__), env: :prod)

    assert config[:tzdata][:autoupdate] == :disabled
  end
end
