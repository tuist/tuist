defmodule TuistEx.Analytics.ConfigTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.Config

  test "reads TUIST_URL and TUIST_PROJECT from the environment" do
    environment = fn
      "TUIST_URL" -> "https://tuist.example"
      "TUIST_PROJECT" -> "acme/widgets"
      _ -> nil
    end

    assert {:ok, resolved} = Config.resolve(environment: environment)
    assert resolved.url == "https://tuist.example"
    assert resolved.project_handle == %{account: "acme", project: "widgets"}
  end

  test "accepts explicit options that override the environment" do
    environment = fn _ -> nil end

    assert {:ok, resolved} =
             Config.resolve(
               environment: environment,
               url: "https://tuist.example",
               project: "acme/widgets"
             )

    assert resolved.url == "https://tuist.example"
    assert resolved.project_handle == %{account: "acme", project: "widgets"}
  end

  test "returns an error when the project handle is missing" do
    environment = fn
      "TUIST_URL" -> "https://tuist.example"
      _ -> nil
    end

    assert {:error, message} = Config.resolve(environment: environment)
    assert message =~ "Missing Tuist project handle"
  end

  test "returns an error when the project handle is malformed" do
    environment = fn
      "TUIST_URL" -> "https://tuist.example"
      "TUIST_PROJECT" -> "acmenoslash"
      _ -> nil
    end

    assert {:error, message} = Config.resolve(environment: environment)
    assert message =~ "Invalid Tuist project handle"
  end

  test "rejects a URL without a scheme" do
    environment = fn
      "TUIST_URL" -> "example.com"
      "TUIST_PROJECT" -> "acme/widgets"
      _ -> nil
    end

    assert {:error, message} = Config.resolve(environment: environment)
    assert message =~ "Invalid Tuist server URL"
  end

  test "rejects a URL with a query string or fragment or userinfo" do
    for candidate <- [
          "https://tuist.example?foo=bar",
          "https://tuist.example#top",
          "https://user:pass@tuist.example"
        ] do
      environment = fn
        "TUIST_URL" -> candidate
        "TUIST_PROJECT" -> "acme/widgets"
        _ -> nil
      end

      assert {:error, message} = Config.resolve(environment: environment)
      assert message =~ "Invalid Tuist server URL"
    end
  end
end
