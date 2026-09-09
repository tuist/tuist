defmodule Tuist.Kura.PlacementNotifier do
  @moduledoc """
  Best-effort Slack context for placement decisions the sweep took on its own.

  Only the unattended ones. An operator applying from the ops UI already knows
  what they did, and announcing it back to them would train the channel to
  read these as routine, which is the opposite of what the automatic ones
  need, since nobody chose them and the account whose cache is refilling has
  no other place the decision shows up.

  Grafana is the paging authority; this is color, not detection. Delivery is
  fire-and-forget in a detached task, so a webhook failure can never fail a
  sweep, and a missing webhook URL disables the notifications entirely.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kura.PlacementProposal
  alias Tuist.Repo

  def notify_applied(%PlacementProposal{} = proposal) do
    case Environment.ops_slack_webhook_url() do
      url when is_binary(url) and url != "" ->
        text = message(proposal, Repo.get(Account, proposal.account_id))
        Task.start(fn -> deliver(url, text) end)
        :ok

      _ ->
        :ok
    end
  end

  defp deliver(url, text) do
    Req.post(url, json: %{text: text}, retry: false, receive_timeout: 5_000)
  end

  defp message(%PlacementProposal{} = proposal, account) do
    handle = if account, do: account.name, else: "account #{proposal.account_id}"

    "Kura placement applied automatically: `#{handle}` #{proposal.kind} #{transition(proposal)}" <>
      " in #{Environment.env()}#{given_up(proposal)}#{evidence(proposal)}"
  end

  defp transition(%PlacementProposal{from_region: nil, to_region: to}), do: "-> #{to}"
  defp transition(%PlacementProposal{from_region: from, to_region: nil}), do: "#{from} ->"
  defp transition(%PlacementProposal{from_region: from, to_region: to}), do: "#{from} -> #{to}"

  # The half of the decision that costs something. An expansion leaves every
  # cache the account holds where it is, so saying nothing here is what tells
  # the channel that one was free.
  defp given_up(%PlacementProposal{kind: :expand}), do: ""

  defp given_up(%PlacementProposal{kind: :relocate} = proposal) do
    if Map.get(proposal.evidence, "retire_source", true) do
      ", retiring #{proposal.from_region}"
    else
      ", keeping #{proposal.from_region}"
    end
  end

  defp given_up(%PlacementProposal{from_region: from}), do: ", retiring #{from}"

  # What the sweep read, so the decision can be judged from the message rather
  # than only looked up afterwards.
  defp evidence(%PlacementProposal{evidence: evidence}) do
    details =
      [
        evidence["region_runs"] && "#{evidence["region_runs"]} runs",
        evidence["share"] && "#{round(evidence["share"] * 100)}% of traffic",
        evidence["active_days"] && "#{evidence["active_days"]} active days"
      ]
      |> Enum.filter(& &1)
      |> Enum.join(", ")

    if details == "", do: "", else: " (#{details})"
  end
end
