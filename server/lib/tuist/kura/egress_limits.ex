defmodule Tuist.Kura.EgressLimits do
  @moduledoc """
  Per-account, per-region overrides of the Kura egress floor and ceiling.

  Three pairs of numbers decide what a tenant's pods run at, and only one of
  them is a bound:

    * The **operator's override** is the intent. Whichever half staff state is
      the number that applies.
    * The **region's pair** is the default. It says what an account nobody has
      looked at gets, it fills in whichever half the override leaves blank, and
      where the two disagree it gives way. It is sized for the fleet, not for
      the hardware, so it is never a limit on what staff may set.
    * The **node's budget** — the `tuist.dev/egress-mbps` capacity each box
      advertises, its NIC ceiling minus headroom — is the only real cap. The
      form validates against it, and `infra/egress-tree-agent` clamps both
      halves to it on the box itself.

  The override is scoped to a region because the boxes are: the budget is
  declared per machine, so a floor a 3 Gbit/s box can keep is one a 1 Gbit/s box
  cannot, and a single account-wide number would either waste the roomy regions
  or promise what the small ones cannot deliver.

  The pair is delivered through the two fields that already carry the region's
  numbers, rather than through override fields of their own: the floor is the
  KuraInstance's `egressGuaranteedMbps`, the ceiling its
  `kubernetes.io/egress-bandwidth` pod annotation. The server renders both at
  the account's effective rates, and each cascades on the cluster side as it
  always has — the floor to the pod's `tuist.dev/egress-mbps` request and limit,
  both to the `tuist.dev/egress-class` annotation the shared-tree shaper reads.
  One number per knob means the slice the scheduler reserves, the ceiling Cilium
  paces, and the class the shaper builds can never disagree about what the
  tenant's limits are.

  Both are pod-spec state, so a retune moves the StatefulSet's pod template and
  the account's replicas in that region are recreated to pick it up. The cache
  survives: a replica's `data-<sts>-<ordinal>` claim belongs to the ordinal
  rather than to the pod, so the replacement binds the same volume and reopens
  the same warm data. Rolling one replica at a time, with the standby serving
  through each restart, is the whole cost.

  What has to be got right is the floor, because it is also the
  `tuist.dev/egress-mbps` request the scheduler places against. The replacement
  has to fit what its box has left — its own volume pins it to that one box, so
  a request the box cannot satisfy leaves it Pending rather than placing it
  elsewhere. The rollout then stops there, holding the account on its surviving
  replica until the number comes back down. Validate against the node budget
  before saving (`node_budget_mbps/1`), which the form does.

  A change is carried to the cluster by the manifest revision (see
  `Tuist.Kura.Provisioner.KubernetesController`), so it lands on the next
  reconciler tick rather than waiting for an unrelated field to move.
  """

  import Ecto.Query, only: [where: 3]

  alias Ecto.Changeset
  alias Tuist.Accounts.Account
  alias Tuist.Billing.Entitlements
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.EgressLimit
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo

  @floor_field :kura_egress_floor_mbps
  @burst_field :kura_egress_burst_mbps
  @form_fields [@floor_field, @burst_field]
  @form_types %{@floor_field => :integer, @burst_field => :integer}
  # Statuses in which a row holds no pods: teardown took the StatefulSet with
  # them, and `:destroying` is on its way there. Nothing to shape, so they
  # neither receive a change nor constrain one.
  @podless_statuses [:destroying, :destroyed, :archived]
  @no_override %{floor_mbps: nil, burst_mbps: nil}

  @doc """
  The floor and ceiling an account's instances in `region` are shaped at, as
  `%{floor_mbps:, burst_mbps:}`.

  Each half is the account's override for that region when it has one and the
  region's number otherwise. Either may be `nil`, which is what a region that
  governs only one of the two gives every instance on it.

  The region's own floor is what the account's plan entitles it to — the region
  number for an Enterprise account, `0` for the rest, which is what makes the
  default pattern bursty and densely packed. The override is deliberately
  ungated by that entitlement: it is a staff decision about one account, made
  with the box in front of them, while the entitlement is what happens when
  nobody has made one.

  `effective_limits/3` takes that already-resolved region floor, for the
  provisioner, which resolves an account's entitlements once for the whole
  manifest and must not pay for a second subscription lookup here.
  """
  def effective_limits(%Account{} = account, %Regions{} = region) do
    effective_limits(account, region, default_limits(account, region).floor_mbps)
  end

  def effective_limits(%Account{} = account, %Regions{} = region, region_floor_mbps) do
    {floor_mbps, burst_mbps} =
      reconcile(override_for(account, region), region_floor_mbps, Regions.egress_burst_mbps(region))

    %{floor_mbps: floor_mbps, burst_mbps: burst_mbps}
  end

  @doc """
  The pair the account gets in `region` when nobody has overridden anything: the
  region's ceiling, and the floor the account's plan entitles it to.

  Shown to an operator as the value an empty field falls back to, which is why
  it carries the entitlement rather than the region's raw floor — an Air account
  reserves nothing, and a form promising it 25 Mbps would be describing an
  instance that does not exist.
  """
  def default_limits(%Account{} = account, %Regions{} = region) do
    %{
      floor_mbps: region_floor_mbps(region, Entitlements.allows?(account, :guaranteed_egress_floor)),
      burst_mbps: Regions.egress_burst_mbps(region)
    }
  end

  @doc """
  The account's override in `region` as `%{floor_mbps:, burst_mbps:}`, or `nil`
  when the region still decides both numbers there.

  A row with one null column is still an override: the null half resolves from
  the region.
  """
  def override_for(%Account{id: account_id}, %Regions{id: region_id}) do
    case Repo.get_by(EgressLimit, account_id: account_id, region: region_id) do
      nil -> nil
      %EgressLimit{floor_mbps: floor_mbps, burst_mbps: burst_mbps} -> %{floor_mbps: floor_mbps, burst_mbps: burst_mbps}
    end
  end

  @doc """
  Builds a changeset for the ops override form for one region.

  Neither field is required: a blank one is how that half of the override is
  removed, handing that number back to the region. Clearing both removes the row.
  """
  def change_override(%Account{} = account, %Regions{} = region, attrs \\ %{}) do
    override = override_for(account, region) || @no_override

    {%{@floor_field => override.floor_mbps, @burst_field => override.burst_mbps}, @form_types}
    |> Changeset.cast(attrs, @form_fields)
    |> EgressLimit.validate_mbps(@floor_field)
    |> EgressLimit.validate_mbps(@burst_field)
    |> EgressLimit.validate_floor_under_burst(@floor_field, @burst_field)
    |> validate_against_node_budget(region)
    |> validate_against_node_headroom(account, region)
  end

  @doc """
  The pair the form is asking for, as `%{floor_mbps:, burst_mbps:}` with `nil`
  for each half handed back to the region.

  Returns `{:error, changeset}` when the form does not validate, so the caller
  can put it back in front of the operator before anything is written.
  """
  def cast_override(%Account{} = account, %Regions{} = region, attrs) when is_map(attrs) do
    account
    |> change_override(region, attrs)
    |> Changeset.apply_action(:update)
    |> case do
      {:ok, values} ->
        {:ok, %{floor_mbps: Map.get(values, @floor_field), burst_mbps: Map.get(values, @burst_field)}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Writes the account's override for `region`, or removes the row when both
  halves are `nil`. Runs inside the caller's transaction.
  """
  def put_override(%Account{id: account_id}, %Regions{id: region_id}, %{floor_mbps: nil, burst_mbps: nil}) do
    Repo.delete_all(from_account_region(account_id, region_id))
    :ok
  end

  def put_override(%Account{id: account_id}, %Regions{id: region_id}, %{floor_mbps: floor_mbps, burst_mbps: burst_mbps}) do
    %EgressLimit{}
    |> EgressLimit.changeset(%{
      account_id: account_id,
      region: region_id,
      floor_mbps: floor_mbps,
      burst_mbps: burst_mbps
    })
    |> Repo.insert(
      on_conflict: {:replace, [:floor_mbps, :burst_mbps, :updated_at]},
      conflict_target: [:account_id, :region]
    )
    |> case do
      {:ok, _limit} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  The floor a region actually reserves for an account, in Mbit/s: the region's
  number when the account is entitled to a guaranteed floor, `0` when it is not,
  and `nil` where the region reserves none at all.

  Shared with the manifest, which resolves the same number for the CR.
  """
  def region_floor_mbps(%Regions{} = region, entitled?) do
    case Regions.egress_guaranteed_mbps(region) do
      nil -> nil
      mbps -> if entitled?, do: mbps, else: 0
    end
  end

  @doc """
  The account's instances that still hold pods, in the regions that shape egress
  at all. These are the instances an override reaches.
  """
  def governed_servers(%Account{id: account_id}) do
    Server
    |> where([server], server.account_id == ^account_id)
    |> where([server], server.status not in ^@podless_statuses)
    |> Repo.all()
    |> Enum.filter(&governed_region?(&1.region))
  end

  @doc """
  The form fields, so a caller rendering the ops form does not restate them.
  """
  def form_fields, do: {@floor_field, @burst_field}

  # A region's pair is a *default*, not a bound: it says what an account nobody
  # has looked at gets, and it is sized for the fleet rather than for the
  # hardware. So where the operator's half and the region's half contradict each
  # other, the operator's wins and the region's yields — a stated floor of 2000
  # against a defaulted ceiling of 1500 means the operator wants 2000 of
  # headroom, not that they wanted 1500 and mistyped.
  #
  # A pair the operator stated *both* halves of is theirs to keep coherent; the
  # form rejects an inverted one rather than picking a winner behind their back.
  defp reconcile(nil, region_floor, region_burst), do: reconcile(@no_override, region_floor, region_burst)

  defp reconcile(%{floor_mbps: override_floor, burst_mbps: override_burst}, region_floor, region_burst) do
    floor_mbps = resolve(override_floor, region_floor)
    burst_mbps = resolve(override_burst, region_burst)

    cond do
      not (is_integer(floor_mbps) and is_integer(burst_mbps)) -> {floor_mbps, burst_mbps}
      floor_mbps <= burst_mbps -> {floor_mbps, burst_mbps}
      is_nil(override_burst) -> {floor_mbps, floor_mbps}
      is_nil(override_floor) -> {burst_mbps, burst_mbps}
      true -> {floor_mbps, burst_mbps}
    end
  end

  # The box is the one thing that can actually refuse a number. A floor above the
  # budget is a promise the root class cannot keep, and a ceiling above it is
  # headroom the NIC does not have — the agent clamps both on the node, so
  # without this the operator's number would simply be quietly discarded there.
  # Saying so in the form is the difference between setting a limit and thinking
  # you set one.
  #
  # A floor is held to more than that. It is the pod's tuist.dev/egress-mbps
  # request, so it is also what the scheduler bin-packs, and a request no node in
  # the region can satisfy leaves the account's replicas Pending — on the
  # local-NVMe regions with their volumes pinned to a box they can no longer be
  # placed on. An unreadable budget is therefore a reason to refuse a floor
  # rather than to wave it through: the edit can be retried in a minute, while a
  # cache stranded behind an unschedulable pod cannot be undone by retrying
  # anything. The ceiling reserves nothing and stays settable either way.
  defp validate_against_node_budget(changeset, %Regions{} = region) do
    case node_budget_mbps(region) do
      nil ->
        case Changeset.get_field(changeset, @floor_field) do
          value when is_integer(value) ->
            Changeset.add_error(
              changeset,
              @floor_field,
              "cannot be reserved: this region's boxes advertise no egress budget to schedule it against"
            )

          _ ->
            changeset
        end

      budget ->
        Enum.reduce(@form_fields, changeset, fn field, acc ->
          case Changeset.get_field(acc, field) do
            value when is_integer(value) and value > budget ->
              Changeset.add_error(acc, field, "must not exceed the #{budget} Mbps this region's boxes advertise")

            _ ->
              acc
          end
        end)
    end
  end

  # What the box can hold for this account, which is a tighter bound than what it
  # advertises and a different question from it.
  #
  # A floor is the pod's `tuist.dev/egress-mbps` request, so every replica
  # reserves it and the box has to hold all of them at once. The rollout gets
  # there one replica at a time, each step handing in the old reservation before
  # asking for the new, so by the last step the old values are all gone and what
  # remains beside the account is only what other tenants hold:
  #
  #     replicas x floor <= what the box has for this account
  #
  # Deliberately written without what the replicas hold *now*. An account caught
  # mid-rollout holds different values on different replicas, and a rule stated
  # in terms of them answers differently depending on when it is asked — the
  # first version of this check told an operator raising a settled 250 that
  # their limit was 137, because it happened to run while one replica was still
  # on the old value.
  #
  # Skipped where the account has no pods on a box yet: nothing pins it, so the
  # scheduler may place it anywhere in the region and `node_budget_mbps/1` above
  # is the whole of the bound.
  #
  # This is a check against a live reading, so it is not a guarantee — another
  # account can be provisioned onto the box between saving and rolling. It is
  # here to catch the mistake at the point it is made, rather than leaving it to
  # be discovered as a Pending pod thirty minutes later.
  defp validate_against_node_headroom(changeset, %Account{} = account, %Regions{} = region) do
    with floor_mbps when is_integer(floor_mbps) <- Changeset.get_field(changeset, @floor_field),
         %{replicas: replicas, available_mbps: available, node: node} <- node_headroom(account, region),
         true <- floor_mbps * replicas > available do
      Changeset.add_error(
        changeset,
        @floor_field,
        "must be at most #{div(available, replicas)} Mbps: each of the #{replicas} replicas reserves it, " <>
          "and #{node} has #{available} Mbps for this account"
      )
    else
      _ -> changeset
    end
  end

  @doc """
  What the box the account's instances in `region` sit on can hold for that
  account, and across how many replicas, or `nil` when they sit on none yet.
  See `Tuist.Kura.Capacity`.
  """
  def node_headroom(%Account{name: name}, %Regions{id: region_id}) do
    Capacity.egress_headroom(region_id, String.downcase(name))
  end

  @doc """
  The egress budget, in Mbit/s, the region's smallest box advertises, or `nil`
  when it cannot be read. This is the only bound an override has.
  """
  def node_budget_mbps(%Regions{id: region_id}), do: Capacity.egress_budget_mbps(region_id)

  defp governed_region?(region_id) do
    case Regions.fetch(region_id) do
      {:ok, region} -> Regions.egress_governed?(region)
      {:error, _reason} -> false
    end
  end

  defp resolve(nil, region_value), do: region_value
  defp resolve(override_value, _region_value), do: override_value

  defp from_account_region(account_id, region_id) do
    EgressLimit
    |> where([limit], limit.account_id == ^account_id)
    |> where([limit], limit.region == ^region_id)
  end
end
