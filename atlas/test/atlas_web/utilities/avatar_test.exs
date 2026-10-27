defmodule AtlasWeb.Utilities.AvatarTest do
  use ExUnit.Case, async: true

  alias AtlasWeb.Utilities.Avatar

  test "builds a normalized Gravatar URL when an email is available" do
    assert Avatar.gravatar_url("  PERSON@Example.com ") ==
             "https://gravatar.com/avatar/7de8517bce4457e8390aa4006a1880fb?d=404"
  end

  test "returns nil when an email is unavailable" do
    assert Avatar.gravatar_url(nil) == nil
    assert Avatar.gravatar_url("  ") == nil
  end
end
