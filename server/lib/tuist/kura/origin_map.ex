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
  @version 5

  # Nearest first, and every list names every candidate region. An origin
  # always has an answer, so a region being unserved or unfunded narrows the
  # choice instead of leaving the account unplaced.
  @zone_preferences %{
    us_east: ["us-east", "ca-east", "us-central", "us-west", "eu-west", "eu-east", "sa-west", "ap-southeast"],
    us_central: ["us-central", "us-east", "ca-east", "us-west", "eu-west", "eu-east", "sa-west", "ap-southeast"],
    us_west: ["us-west", "us-central", "us-east", "ca-east", "sa-west", "ap-southeast", "eu-west", "eu-east"],
    canada_east: ["ca-east", "us-east", "us-central", "us-west", "eu-west", "eu-east", "sa-west", "ap-southeast"],
    europe: ["eu-west", "eu-east", "us-east", "ca-east", "us-central", "us-west", "ap-southeast", "sa-west"],
    europe_east: ["eu-east", "eu-west", "us-east", "ca-east", "us-central", "us-west", "ap-southeast", "sa-west"],
    apac: ["ap-southeast", "us-west", "us-central", "us-east", "eu-west", "eu-east", "ca-east", "sa-west"],
    south_america: ["sa-west", "us-east", "us-central", "ca-east", "us-west", "eu-west", "eu-east", "ap-southeast"],
    africa_middle_east: [
      "eu-west",
      "eu-east",
      "us-east",
      "ca-east",
      "us-central",
      "us-west",
      "ap-southeast",
      "sa-west"
    ]
  }

  # Where an origin no entry covers is served from. The same region an account
  # stating no constraint resolves to today, so an unmapped origin changes
  # nothing rather than moving someone somewhere new.
  @default_zone :us_east

  @europe ~w[
    AD AT AX BE CH DE ES FO FR GB GG GI IE IM IS IT JE LI LU MC MT NL PT SI
    SJ SM VA
  ]

  # Nearer Warsaw than Paris, by enough that the routes follow the geography.
  # Helsinki is 930km from Warsaw against 1910 from Paris, Copenhagen 670
  # against 1030, Vilnius 400 against 1600, so the Nordics sit here with the
  # Baltics rather than with western Europe.
  #
  # The Balkans, Greece and Cyprus sit here on the same test: Belgrade is 829km
  # from Warsaw against 1445 from Paris, Zagreb 802 against 1080, Athens 1598
  # against 2096, Nicosia 2133 against 2950.
  #
  # Slovenia stays west. Ljubljana is 833km from Warsaw against 964 from Paris,
  # a margin narrower than anything else here and too narrow to take the
  # straight line for the route.
  @europe_east ~w[
    AL BA BG BY CY CZ DK EE FI GR HR HU LT LV MD ME MK NO PL RO RS RU SE SK
    UA XK
  ]

  # Réunion and Mayotte are nearer Singapore on the straight line, 5811km and
  # 6650 against 9365 and 8042 to Paris, but their transit is the French cables
  # north-west and the Mozambique Channel around them is already here. Saint
  # Helena is 6736km from Santiago against 7251 from Paris and lands on the
  # African coast.
  @africa_middle_east ~w[
    AE AO BF BH BI BJ BW CD CF CG CI CM CV DJ DZ EG EH ER ET GA GH GM GN GQ GW
    IL IQ IR JO KE KM KW LB LR LS LY MA MG ML MR MU MW MZ NA NE NG OM PS QA RE
    RW SA SC SD SH SL SN SO SS ST SY SZ TD TG TN TR TZ UG YE YT ZA ZM ZW
  ]

  @apac ~w[
    AF AM AS AU AZ BD BN BT CC CK CN CX FJ FM GE GU HK HM ID IN IO JP KG KH KI
    KP KR KZ LA LK MH MM MN MO MP MV MY NC NF NP NR NU NZ PF PG PH PK PW SB SG
    TF TH TJ TK TL TM TO TV TW UZ VN VU WF WS
  ]

  # Latin America and the Caribbean. The South Atlantic outliers are here on
  # distance: Stanley is 2277km from Santiago, Grytviken 3528, Adamstown 5764
  # against 7883 to Hillsboro. The Caribbean codes follow the block they sit
  # in rather than their own nearest region, which for Gustavia is Vint Hill
  # at 2730km against 5770 to Santiago; that block moves as one or not at all.
  @south_america ~w[
    AG AI AQ AR AW BB BL BM BO BQ BR BS BV BZ CL CO CR CU CW DM DO EC FK GD GF
    GP GS GT GY HN HT JM KN KY LC MF MQ MS MX NI PA PE PN PR PY SR SV SX TC TT
    UY VC VE VG VI
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
                     [
                       {"US", :us_east},
                       {"CA", :canada_east},
                       # Nuuk is 3301km from Vint Hill and Saint-Pierre 1964,
                       # both nearer Beauharnois still. ca-east is in the
                       # catalog and not served, so these resolve to us-east
                       # today exactly as CA does, and follow Montreal rather
                       # than Virginia if it ever is.
                       {"GL", :canada_east},
                       {"PM", :canada_east},
                       # Midway, Wake and Johnston. Navassa is Caribbean rather
                       # than Pacific and one code cannot say both.
                       {"UM", :us_west}
                     ]
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
