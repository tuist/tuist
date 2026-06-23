defmodule TuistOps.Previews.SlackBlocksTest do
  use ExUnit.Case, async: true

  alias TuistOps.Previews.Preview
  alias TuistOps.Previews.SlackBlocks

  test "provisioning renders expiry from ttl_seconds" do
    inserted_at = ~U[2026-06-23 08:00:00Z]

    preview = %Preview{
      slug: "demo",
      host: "demo.preview.tuist.dev",
      requester_slack_id: "U123",
      reason: "debugging preview",
      ttl_seconds: 3600,
      inserted_at: inserted_at,
      updated_at: inserted_at
    }

    [_, %{elements: [%{text: text}]}, _] = SlackBlocks.provisioning(preview)

    assert text ==
             "GitHub Actions is provisioning it. It expires <!date^1782205200^{date_short_pretty} at {time}|soon>."
  end
end
