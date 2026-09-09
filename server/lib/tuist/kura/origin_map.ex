defmodule Tuist.Kura.OriginMap do
  @moduledoc """
  Translates where a request came from into the cache regions that could serve
  it, nearest first.

  Deployment configuration reviewed like code, not a lookup service: no
  per-request network call, and no address database resident in the server or
  on the nodes. Entries are wrong in the cases geography is wrong about
  networks — corporate egress landing in another country, cloud CI whose
  network distance defies the map — and the fix is an edit here.

  Origins are stored as they were measured and mapped through here when a
  decision is taken, so correcting an entry re-reads the history instead of
  only changing the future. `version/0` stamps the decisions it produced, so a
  decision taken under an older table stays readable as one.
  """

  # Bumped when an entry moves. Recorded on decisions rather than compared
  # against anything: it dates a verdict, it does not gate one.
  @version 2

  # Nearest first, and every list names every candidate region. An origin
  # always has an answer, so a region being unserved or unfunded narrows the
  # choice instead of leaving the account unplaced.
  @zone_preferences %{
    us_east: ["us-east", "ca-east", "us-central", "us-west", "eu-central", "eu-east", "sa-west", "ap-southeast"],
    us_central: ["us-central", "us-east", "ca-east", "us-west", "eu-central", "eu-east", "sa-west", "ap-southeast"],
    us_west: ["us-west", "us-central", "us-east", "ca-east", "sa-west", "ap-southeast", "eu-central", "eu-east"],
    canada_east: ["ca-east", "us-east", "us-central", "us-west", "eu-central", "eu-east", "sa-west", "ap-southeast"],
    europe: ["eu-central", "eu-east", "us-east", "ca-east", "us-central", "us-west", "ap-southeast", "sa-west"],
    europe_east: ["eu-east", "eu-central", "us-east", "ca-east", "us-central", "us-west", "ap-southeast", "sa-west"],
    apac: ["ap-southeast", "us-west", "us-central", "us-east", "eu-central", "eu-east", "ca-east", "sa-west"],
    south_america: ["sa-west", "us-east", "us-central", "ca-east", "us-west", "eu-central", "eu-east", "ap-southeast"],
    africa_middle_east: ["eu-central", "eu-east", "us-east", "ca-east", "us-central", "us-west", "ap-southeast", "sa-west"]
  }

  # Where an origin no entry covers is served from. The same region an account
  # stating no constraint resolves to today, so an unmapped origin changes
  # nothing rather than moving someone somewhere new.
  @default_zone :us_east

  @europe ~w[
    AD AL AT AX BA BE CH CY DE ES FO FR GB GG GI GR HR IE IM IS IT JE LI LU MC
    ME MK MT NL PT RS SI SJ SM VA XK
  ]

  # Nearer Warsaw than Paris, by enough that the routes follow the geography.
  # Helsinki is 930km from Warsaw against 1910 from Paris, Copenhagen 670
  # against 1030, Vilnius 400 against 1600, so the Nordics sit here with the
  # Baltics rather than with western Europe.
  #
  # The boundary stops short of the Balkans, Greece and Cyprus. They are also
  # nearer Warsaw on a straight line, but their transit is provisioned westward
  # and the traffic behind them is small, so they stay on the Paris routes until
  # eu-east has a record. Widening this list is one edit and re-reads history.
  @europe_east ~w[
    BG BY CZ DK EE FI HU LT LV MD NO PL RO RU SE SK UA
  ]

  @africa_middle_east ~w[
    AE AO BF BH BI BJ BW CD CF CG CI CM CV DJ DZ EG EH ER ET GA GH GM GN GQ GW
    IL IQ IR JO KE KM KW LB LR LS LY MA MG ML MR MU MW MZ NA NE NG OM PS QA RW
    SA SC SD SL SN SO SS ST SY SZ TD TG TN TR TZ UG YE ZA ZM ZW
  ]

  @apac ~w[
    AF AM AS AU AZ BD BN BT CK CN FJ FM GE GU HK ID IN JP KG KH KI KP KR KZ LA
    LK MH MM MN MO MV MY NC NF NP NR NU NZ PF PG PH PK PW SB SG TH TJ TK TL TM
    TO TV TW UZ VN VU WS
  ]

  @south_america ~w[
    AG AI AR AW BB BM BO BR BS BZ CL CO CR CU CW DM DO EC GD GP GT GY HN HT JM
    KN KY LC MQ MS MX NI PA PE PR PY SR SV SX TC TT UY VC VE VG VI
  ]

  # The western United States and the Canadian west are nearer Hillsboro than
  # anything else in the catalog; everything else in both countries is nearer
  # Vint Hill or Beauharnois.
  @us_west_subdivisions ~w[AK AZ CA CO HI ID MT NM NV OR UT WA WY]
  @canada_west_subdivisions ~w[AB BC NT YT]

  # The interior, which Chicago serves and neither Vint Hill nor Hillsboro does
  # well: Dallas is 1300km from Chicago against 1900 from Vint Hill, Minneapolis
  # 570 against 1600. Ohio, Kentucky and Tennessee are close to even between the
  # two and stay on us-east; Colorado, Wyoming and Montana are already us-west
  # and are no nearer Chicago than Hillsboro.
  @us_central_subdivisions ~w[AR IA IL IN KS LA MI MN MO ND NE OK SD TX WI]

  @country_zones Map.new(
                   Enum.map(@europe, &{&1, :europe}) ++
                     Enum.map(@europe_east, &{&1, :europe_east}) ++
                     Enum.map(@africa_middle_east, &{&1, :africa_middle_east}) ++
                     Enum.map(@apac, &{&1, :apac}) ++
                     Enum.map(@south_america, &{&1, :south_america}) ++
                     [{"US", :us_east}, {"CA", :canada_east}]
                 )

  @subdivision_zones Map.new(
                       Enum.map(@us_west_subdivisions, &{"US-" <> &1, :us_west}) ++
                         Enum.map(@us_central_subdivisions, &{"US-" <> &1, :us_central}) ++
                         Enum.map(@canada_west_subdivisions, &{"CA-" <> &1, :us_west})
                     )

  def version, do: @version

  @doc """
  Every region the table names, which is every region an origin can be placed
  in through it.
  """
  def candidate_region_ids do
    @zone_preferences |> Map.values() |> List.flatten() |> Enum.uniq()
  end

  @doc """
  The regions that could serve `origin`, nearest first. An origin the table
  does not cover, and a `nil` origin, both answer with the default zone's
  order.
  """
  def candidates(origin) do
    Map.fetch!(@zone_preferences, zone(origin))
  end

  @doc """
  The nearest region to `origin` among `permitted`, or `nil` when none of the
  candidates is permitted. `permitted` is what residency, region availability
  and per-plan budgets have already agreed to.
  """
  def preferred(origin, permitted) do
    permitted = MapSet.new(permitted)

    origin
    |> candidates()
    |> Enum.find(&MapSet.member?(permitted, &1))
  end

  @doc """
  How near `region_id` is to `origin`, smallest first, for ordering a list of
  regions by an origin. A region the table does not name sorts last.
  """
  def distance(origin, region_id) do
    case Enum.find_index(candidates(origin), &(&1 == region_id)) do
      nil -> length(candidate_region_ids())
      index -> index
    end
  end

  # A subdivision is consulted first so the countries holding two regions can
  # split, and falls back to its country so an unmapped subdivision is still
  # placed on the right continent.
  defp zone(origin) when is_binary(origin) do
    case Map.fetch(@subdivision_zones, origin) do
      {:ok, zone} -> zone
      :error -> country_zone(origin)
    end
  end

  defp zone(_origin), do: @default_zone

  defp country_zone(origin) do
    country = origin |> String.split("-", parts: 2) |> List.first()

    Map.get(@country_zones, country, @default_zone)
  end
end
