defmodule Pulse.PromQL.NativeHistogram do
  @moduledoc """
  Arithmetic PromQL needs for Prometheus native histograms
  (`Pulse.Record.NativeHistogram`).

  Ported from Prometheus v3.5.0 (Apache-2.0, Copyright The Prometheus
  Authors), with Mimir dd039cdd's NaN-sum quantile correction, compensated
  histogram aggregation, reset detection and bucket trimming described below:

    * `model/histogram/float_histogram.go` — `Add`, `Sub`, `Mul`, `Div`,
      `TrimBuckets`, `ReduceResolution`, `Compact(0)`, `DetectReset`, `Equals`, the zero
      bucket reconciliation and the bucket iterators.
    * `model/histogram/generic.go` — `getBound` (including the precomputed
      `exponentialBounds` table and the `math.MaxFloat64` special case), bucket
      inclusivity, `reduceResolution` and `targetIdx`.
    * `promql/quantile.go` — `HistogramQuantile` and `HistogramFraction`.
    * `promql/functions.go` — `histogram_count/sum/avg/stddev/stdvar`.
    * `util/jsonutil/marshal.go` — the bucket order and boundary rules
      `/api/v1/query` reports.

  Interpolation uses ports of Go's pure `math.Log`, `math.Log2`, `math.Exp2`
  and `math.Ldexp`, evaluated without fused multiply-add, so results are
  bit-identical to Prometheus's amd64 release builds rather than to whatever
  the platform's libm returns.

  `detect_reset?/2` follows Mimir's complete previous-bucket traversal and
  compensated zero-threshold widening. Differing custom layouts use plain
  common-bound rollups to detect decreases, not layout changes. NaN-sum
  quantiles instead follow Mimir dd039cdd's corrected interpolation in the
  selected bucket, rather than Prometheus 3.5.0's last-bucket quirk. Addition
  and subtraction of differing custom layouts coarsen both inputs to their
  common bounds. `trim/3` follows Mimir's logarithmic/linear interpolation,
  biased zero buckets and explicit infinite-bound rules. Changed populations
  recompute totals in source order; no-op trims retain the original totals.

  Values Prometheus would compute as NaN or ±Inf use the atoms of
  `Pulse.PromQL.Number` (`:nan`, `:infinity`, `:negative_infinity`).

  Results of `add/2` and `sub/2` hold the same buckets at the same indexes as
  Prometheus, but runs of adjacent indexes always share one span (Prometheus
  may split them with zero-offset spans). PromQL compacts every such result
  before exposing it, so pass results through `compact/1` before comparing them
  with `equal?/2`.
  """

  import Bitwise

  alias Pulse.PromQL.Number
  alias Pulse.Record.NativeHistogram, as: Histogram

  @custom_schema -53
  # math.MaxFloat64.
  <<max_float::float-64>> = <<0x7FEFFFFFFFFFFFFF::64>>
  @max_float max_float
  @two_pow_minus_53 1.1102230246251565e-16

  # Constants of Go's math.Log and math.Exp2 (from FreeBSD's msun).
  @ln2_hi 6.93147180369123816490e-01
  @ln2_lo 1.90821492927058770002e-10
  @sqrt2_half 0.7071067811865476
  @log_l1 6.666666666666735130e-01
  @log_l2 3.999999999940941908e-01
  @log_l3 2.857142874366239149e-01
  @log_l4 2.222219843214978396e-01
  @log_l5 1.818357216161805012e-01
  @log_l6 1.531383769920937332e-01
  @log_l7 1.479819860511658591e-01
  @exp_p1 1.66666666666666657415e-01
  @exp_p2 -2.77777777770155933842e-03
  @exp_p3 6.61375632143793436117e-05
  @exp_p4 -1.65339022054652515390e-06
  @exp_p5 4.13813679705723846039e-08
  @log2_e 1.4426950408889634

  # Prometheus's `exponentialBounds`: bucket bounds in [0.5, 1) for schemas 0..8.
  @exponential_bounds {
    {0.5},
    {0.5, 0.7071067811865475},
    {0.5, 0.5946035575013605, 0.7071067811865475, 0.8408964152537144},
    {
      0.5,
      0.5452538663326288,
      0.5946035575013605,
      0.6484197773255048,
      0.7071067811865475,
      0.7711054127039704,
      0.8408964152537144,
      0.9170040432046711
    },
    {
      0.5,
      0.5221368912137069,
      0.5452538663326288,
      0.5693943173783458,
      0.5946035575013605,
      0.620928906036742,
      0.6484197773255048,
      0.6771277734684463,
      0.7071067811865475,
      0.7384130729697496,
      0.7711054127039704,
      0.805245165974627,
      0.8408964152537144,
      0.8781260801866495,
      0.9170040432046711,
      0.9576032806985735
    },
    {
      0.5,
      0.5109485743270583,
      0.5221368912137069,
      0.5335702003384117,
      0.5452538663326288,
      0.5571933712979462,
      0.5693943173783458,
      0.5818624293887887,
      0.5946035575013605,
      0.6076236799902344,
      0.620928906036742,
      0.6345254785958666,
      0.6484197773255048,
      0.6626183215798706,
      0.6771277734684463,
      0.6919549409819159,
      0.7071067811865475,
      0.7225904034885232,
      0.7384130729697496,
      0.7545822137967112,
      0.7711054127039704,
      0.7879904225539431,
      0.805245165974627,
      0.8228777390769823,
      0.8408964152537144,
      0.8593096490612387,
      0.8781260801866495,
      0.8973545375015533,
      0.9170040432046711,
      0.9370838170551498,
      0.9576032806985735,
      0.9785720620876999
    },
    {
      0.5,
      0.5054446430258502,
      0.5109485743270583,
      0.5165124395106142,
      0.5221368912137069,
      0.5278225891802786,
      0.5335702003384117,
      0.5393803988785598,
      0.5452538663326288,
      0.5511912916539204,
      0.5571933712979462,
      0.5632608093041209,
      0.5693943173783458,
      0.5755946149764913,
      0.5818624293887887,
      0.5881984958251406,
      0.5946035575013605,
      0.6010783657263515,
      0.6076236799902344,
      0.6142402680534349,
      0.620928906036742,
      0.6276903785123455,
      0.6345254785958666,
      0.6414350080393891,
      0.6484197773255048,
      0.6554806057623822,
      0.6626183215798706,
      0.6698337620266515,
      0.6771277734684463,
      0.6845012114872953,
      0.6919549409819159,
      0.6994898362691555,
      0.7071067811865475,
      0.7148066691959849,
      0.7225904034885232,
      0.7304588970903234,
      0.7384130729697496,
      0.7464538641456323,
      0.7545822137967112,
      0.762799075372269,
      0.7711054127039704,
      0.7795022001189185,
      0.7879904225539431,
      0.7965710756711334,
      0.805245165974627,
      0.8140137109286738,
      0.8228777390769823,
      0.8318382901633681,
      0.8408964152537144,
      0.8500531768592616,
      0.8593096490612387,
      0.8686669176368529,
      0.8781260801866495,
      0.8876882462632604,
      0.8973545375015533,
      0.9071260877501991,
      0.9170040432046711,
      0.9269895625416926,
      0.9370838170551498,
      0.9472879907934827,
      0.9576032806985735,
      0.9680308967461471,
      0.9785720620876999,
      0.9892280131939752
    },
    {
      0.5,
      0.5027149505564014,
      0.5054446430258502,
      0.5081891574554764,
      0.5109485743270583,
      0.5137229745593818,
      0.5165124395106142,
      0.5193170509806894,
      0.5221368912137069,
      0.5249720429003435,
      0.5278225891802786,
      0.5306886136446309,
      0.5335702003384117,
      0.5364674337629877,
      0.5393803988785598,
      0.5423091811066545,
      0.5452538663326288,
      0.5482145409081883,
      0.5511912916539204,
      0.5541842058618393,
      0.5571933712979462,
      0.5602188762048033,
      0.5632608093041209,
      0.5663192597993595,
      0.5693943173783458,
      0.572486072215902,
      0.5755946149764913,
      0.5787200368168754,
      0.5818624293887887,
      0.585021884841625,
      0.5881984958251406,
      0.5913923554921704,
      0.5946035575013605,
      0.5978321960199137,
      0.6010783657263515,
      0.6043421618132907,
      0.6076236799902344,
      0.6109230164863786,
      0.6142402680534349,
      0.6175755319684665,
      0.620928906036742,
      0.6243004885946023,
      0.6276903785123455,
      0.6310986751971253,
      0.6345254785958666,
      0.637970889198196,
      0.6414350080393891,
      0.6449179367033329,
      0.6484197773255048,
      0.6519406325959679,
      0.6554806057623822,
      0.659039800633032,
      0.6626183215798706,
      0.6662162735415805,
      0.6698337620266515,
      0.6734708931164728,
      0.6771277734684463,
      0.6808045103191123,
      0.6845012114872953,
      0.688217985377265,
      0.6919549409819159,
      0.6957121878859629,
      0.6994898362691555,
      0.7032879969095076,
      0.7071067811865475,
      0.7109463010845827,
      0.7148066691959849,
      0.718687998724491,
      0.7225904034885232,
      0.7265139979245261,
      0.7304588970903234,
      0.7344252166684908,
      0.7384130729697496,
      0.7424225829363761,
      0.7464538641456323,
      0.7505070348132126,
      0.7545822137967112,
      0.7586795205991071,
      0.762799075372269,
      0.7669409989204777,
      0.7711054127039704,
      0.7752924388424999,
      0.7795022001189185,
      0.7837348199827764,
      0.7879904225539431,
      0.7922691326262467,
      0.7965710756711334,
      0.8008963778413465,
      0.805245165974627,
      0.8096175675974316,
      0.8140137109286738,
      0.8184337248834821,
      0.8228777390769823,
      0.8273458838280969,
      0.8318382901633681,
      0.8363550898207981,
      0.8408964152537144,
      0.8454623996346523,
      0.8500531768592616,
      0.8546688815502312,
      0.8593096490612387,
      0.8639756154809185,
      0.8686669176368529,
      0.8733836930995842,
      0.8781260801866495,
      0.8828942179666361,
      0.8876882462632604,
      0.8925083056594671,
      0.8973545375015533,
      0.9022270839033115,
      0.9071260877501991,
      0.9120516927035263,
      0.9170040432046711,
      0.9219832844793128,
      0.9269895625416926,
      0.9320230241988943,
      0.9370838170551498,
      0.9421720895161669,
      0.9472879907934827,
      0.9524316709088368,
      0.9576032806985735,
      0.9628029718180622,
      0.9680308967461471,
      0.9732872087896164,
      0.9785720620876999,
      0.9838856116165875,
      0.9892280131939752,
      0.9945994234836328
    },
    {
      0.5,
      0.5013556375251013,
      0.5027149505564014,
      0.5040779490592088,
      0.5054446430258502,
      0.5068150424757447,
      0.5081891574554764,
      0.509566998038869,
      0.5109485743270583,
      0.5123338964485679,
      0.5137229745593818,
      0.5151158188430205,
      0.5165124395106142,
      0.5179128468009786,
      0.5193170509806894,
      0.520725062344158,
      0.5221368912137069,
      0.5235525479396449,
      0.5249720429003435,
      0.526395386502313,
      0.5278225891802786,
      0.5292536613972564,
      0.5306886136446309,
      0.5321274564422321,
      0.5335702003384117,
      0.5350168559101208,
      0.5364674337629877,
      0.5379219445313954,
      0.5393803988785598,
      0.5408428074966075,
      0.5423091811066545,
      0.5437795304588847,
      0.5452538663326288,
      0.5467321995364429,
      0.5482145409081883,
      0.549700901315111,
      0.5511912916539204,
      0.5526857228508706,
      0.5541842058618393,
      0.5556867516724088,
      0.5571933712979462,
      0.5587040757836845,
      0.5602188762048033,
      0.5617377836665098,
      0.5632608093041209,
      0.564787964283144,
      0.5663192597993595,
      0.5678547070789026,
      0.5693943173783458,
      0.5709381019847808,
      0.572486072215902,
      0.5740382394200894,
      0.5755946149764913,
      0.5771552102951081,
      0.5787200368168754,
      0.5802891060137493,
      0.5818624293887887,
      0.5834400184762408,
      0.585021884841625,
      0.5866080400818185,
      0.5881984958251406,
      0.5897932637314379,
      0.5913923554921704,
      0.5929957828304968,
      0.5946035575013605,
      0.5962156912915756,
      0.5978321960199137,
      0.5994530835371903,
      0.6010783657263515,
      0.6027080545025619,
      0.6043421618132907,
      0.6059806996384005,
      0.6076236799902344,
      0.6092711149137041,
      0.6109230164863786,
      0.6125793968185725,
      0.6142402680534349,
      0.6159056423670379,
      0.6175755319684665,
      0.6192499490999082,
      0.620928906036742,
      0.622612415087629,
      0.6243004885946023,
      0.6259931389331581,
      0.6276903785123455,
      0.6293922197748583,
      0.6310986751971253,
      0.6328097572894031,
      0.6345254785958666,
      0.6362458516947014,
      0.637970889198196,
      0.6397006037528346,
      0.6414350080393891,
      0.6431741147730128,
      0.6449179367033329,
      0.6466664866145447,
      0.6484197773255048,
      0.6501778216898253,
      0.6519406325959679,
      0.6537082229673385,
      0.6554806057623822,
      0.6572577939746774,
      0.659039800633032,
      0.6608266388015788,
      0.6626183215798706,
      0.6644148621029772,
      0.6662162735415805,
      0.6680225691020727,
      0.6698337620266515,
      0.6716498655934177,
      0.6734708931164728,
      0.6752968579460171,
      0.6771277734684463,
      0.6789636531064505,
      0.6808045103191123,
      0.6826503586020058,
      0.6845012114872953,
      0.6863570825438342,
      0.688217985377265,
      0.690083933630119,
      0.6919549409819159,
      0.6938310211492645,
      0.6957121878859629,
      0.6975984549830999,
      0.6994898362691555,
      0.7013863456101023,
      0.7032879969095076,
      0.7051948041086352,
      0.7071067811865475,
      0.7090239421602076,
      0.7109463010845827,
      0.7128738720527471,
      0.7148066691959849,
      0.7167447066838943,
      0.718687998724491,
      0.7206365595643126,
      0.7225904034885232,
      0.7245495448210174,
      0.7265139979245261,
      0.7284837772007218,
      0.7304588970903234,
      0.7324393720732029,
      0.7344252166684908,
      0.7364164454346837,
      0.7384130729697496,
      0.7404151139112358,
      0.7424225829363761,
      0.7444354947621984,
      0.7464538641456323,
      0.7484777058836176,
      0.7505070348132126,
      0.7525418658117031,
      0.7545822137967112,
      0.7566280937263048,
      0.7586795205991071,
      0.7607365094544071,
      0.762799075372269,
      0.7648672334736434,
      0.7669409989204777,
      0.7690203869158282,
      0.7711054127039704,
      0.7731960915705107,
      0.7752924388424999,
      0.7773944698885442,
      0.7795022001189185,
      0.7816156449856788,
      0.7837348199827764,
      0.7858597406461707,
      0.7879904225539431,
      0.7901268813264122,
      0.7922691326262467,
      0.7944171921585818,
      0.7965710756711334,
      0.7987307989543135,
      0.8008963778413465,
      0.8030678282083853,
      0.805245165974627,
      0.8074284071024302,
      0.8096175675974316,
      0.8118126635086642,
      0.8140137109286738,
      0.8162207259936375,
      0.8184337248834821,
      0.820652723822003,
      0.8228777390769823,
      0.8251087869603088,
      0.8273458838280969,
      0.8295890460808079,
      0.8318382901633681,
      0.8340936325652911,
      0.8363550898207981,
      0.8386226785089391,
      0.8408964152537144,
      0.8431763167241966,
      0.8454623996346523,
      0.8477546807446661,
      0.8500531768592616,
      0.8523579048290255,
      0.8546688815502312,
      0.8569861239649629,
      0.8593096490612387,
      0.8616394738731368,
      0.8639756154809185,
      0.8663180910111553,
      0.8686669176368529,
      0.871022112577578,
      0.8733836930995842,
      0.8757516765159389,
      0.8781260801866495,
      0.8805069215187917,
      0.8828942179666361,
      0.8852879870317771,
      0.8876882462632604,
      0.890095013257712,
      0.8925083056594671,
      0.8949281411607002,
      0.8973545375015533,
      0.8997875124702672,
      0.9022270839033115,
      0.9046732696855155,
      0.9071260877501991,
      0.909585556079304,
      0.9120516927035263,
      0.9145245157024483,
      0.9170040432046711,
      0.9194902933879467,
      0.9219832844793128,
      0.9244830347552253,
      0.9269895625416926,
      0.92950288621441,
      0.9320230241988943,
      0.9345499949706191,
      0.9370838170551498,
      0.93962450902828,
      0.9421720895161669,
      0.9447265771954693,
      0.9472879907934827,
      0.9498563490882775,
      0.9524316709088368,
      0.9550139751351947,
      0.9576032806985735,
      0.9601996065815236,
      0.9628029718180622,
      0.9654133954938133,
      0.9680308967461471,
      0.9706554947643201,
      0.9732872087896164,
      0.9759260581154889,
      0.9785720620876999,
      0.9812252401044634,
      0.9838856116165875,
      0.9865531961276168,
      0.9892280131939752,
      0.9919100824251095,
      0.9945994234836328,
      0.9972960560854698
    }
  }

  @type value :: number() | :nan | :infinity | :negative_infinity
  @type boundary_rule :: 0..3
  @type info :: :nan_result | :nan_skew | :nan_observations

  ## Arithmetic

  @doc """
  Adds `b` to `a` (Prometheus's `FloatHistogram.Add`): reconciles to the lower
  schema and the larger zero threshold, merges buckets and resolves the
  counter reset hint. Differing custom bounds coarsen as in Mimir.
  """
  @spec add(Histogram.t(), Histogram.t()) ::
          {:ok, Histogram.t()} | {:error, :incompatible_schema}
  def add(%Histogram{} = a, %Histogram{} = b) do
    a = %{a | counter_reset_hint: add_hint(a.counter_reset_hint, b.counter_reset_hint)}

    case compatible(a, b) do
      :ok -> {:ok, combine(a, b, false)}
      {:error, :incompatible_bounds} -> {:ok, combine_custom(a, b, false)}
      error -> error
    end
  end

  @doc """
  Mimir dd039cdd's `KahanAdd`. Keeps a separate compensation histogram across
  additions and layout changes; callers add it only when finishing aggregation.
  Ordinary binary `add/2` deliberately keeps its uncompensated semantics.
  """
  def compensated_add(h, other, correction \\ nil) do
    if custom?(h) == custom?(other) do
      correction = correction || zero_compensation(h)
      {h, correction} = if custom?(h), do: {h, correction}, else: compensated_zero(h, other, correction)
      {count, count_c} = Number.compensated_add(other.count, h.count, correction.count)
      {sum, sum_c} = Number.compensated_add(other.sum, h.sum, correction.sum)
      h = %{h | count: count, sum: sum, counter_reset_hint: add_hint(h.counter_reset_hint, other.counter_reset_hint)}
      correction = %{correction | count: count_c, sum: sum_c}
      {h, correction} = compensated_sides(h, other, correction)
      {:ok, h, correction}
    else
      {:error, :incompatible_schema}
    end
  end

  @doc "Whether any histogram count, sum, bucket or custom bound has overflowed."
  def overflow?(h) do
    Enum.any?([h.count, h.sum, h.zero_count | h.positive_buckets ++ h.negative_buckets ++ h.custom_values], fn value ->
      value in [:infinity, :negative_infinity]
    end)
  end

  defp zero_compensation(h) do
    %{
      h
      | count: 0.0,
        sum: 0.0,
        zero_count: 0.0,
        positive_buckets: Enum.map(h.positive_buckets, fn _ -> 0.0 end),
        negative_buckets: Enum.map(h.negative_buckets, fn _ -> 0.0 end)
    }
  end

  defp compensated_sides(%{schema: @custom_schema} = h, other, c) do
    if floats_match?(h.custom_values, other.custom_values) do
      positive = merge_compensated(paired_entries(h, c, :positive), paired_entries(other, nil, :positive))
      put_compensated_sides(h, c, positive, [])
    else
      bounds = intersect_bounds(h.custom_values, other.custom_values)
      counts = map_compensated_custom(h, c, bounds, %{})
      counts = map_compensated_custom(other, nil, bounds, counts)

      positive =
        for index <- 0..length(bounds),
            {sum, c} = Map.get(counts, index, {0.0, 0.0}),
            not zero?(sum) or not zero?(c),
            do: {index, {sum, c}}

      put_compensated_sides(%{h | custom_values: bounds}, %{c | custom_values: bounds}, positive, [])
    end
  end

  defp compensated_sides(h, other, c) do
    schema = min(h.schema, other.schema)

    [positive, negative] =
      Enum.map([:positive, :negative], fn side ->
        left = reduce_compensated(paired_entries(h, c, side), h.schema, schema)

        right =
          other
          |> paired_entries(nil, side)
          |> reduce_compensated(other.schema, schema)
          |> Enum.drop_while(fn {index, _} -> le?(bound(index, schema, {}), h.zero_threshold) end)

        merge_compensated(left, right)
      end)

    put_compensated_sides(%{h | schema: schema}, %{c | schema: schema}, positive, negative)
  end

  defp paired_entries(h, nil, side), do: Enum.map(entries(h, side), fn {index, value} -> {index, {value, 0.0}} end)

  defp paired_entries(h, c, side) do
    Enum.zip_with(entries(h, side), entries(c, side), fn {index, value}, {index, correction} ->
      {index, {value, correction}}
    end)
  end

  defp put_compensated_sides(h, c, positive, negative) do
    {positive_spans, positive_values} = to_spans(positive)
    {negative_spans, negative_values} = to_spans(negative)
    h = %{h | positive_spans: positive_spans, negative_spans: negative_spans}
    c = %{c | positive_spans: positive_spans, negative_spans: negative_spans, zero_threshold: h.zero_threshold}

    {%{
       h
       | positive_buckets: Enum.map(positive_values, &elem(&1, 0)),
         negative_buckets: Enum.map(negative_values, &elem(&1, 0))
     },
     %{
       c
       | positive_buckets: Enum.map(positive_values, &elem(&1, 1)),
         negative_buckets: Enum.map(negative_values, &elem(&1, 1))
     }}
  end

  defp merge_compensated(left, right), do: merge_compensated(left, right, [])
  defp merge_compensated([], right, acc), do: Enum.reverse(acc, right)
  defp merge_compensated(left, [], acc), do: Enum.reverse(acc, left)

  defp merge_compensated([{index, {sum, c}} | left], [{index, {value, correction}} | right], acc) do
    {sum, c} = Number.compensated_add(value, sum, c)
    result = if zero?(correction), do: {sum, c}, else: Number.compensated_add(correction, sum, c)
    merge_compensated(left, right, [{index, result} | acc])
  end

  defp merge_compensated([{index, _} = entry | left], [{other, _} | _] = right, acc) when index < other,
    do: merge_compensated(left, right, [entry | acc])

  defp merge_compensated(left, [entry | right], acc), do: merge_compensated(left, right, [entry | acc])

  defp reduce_compensated(entries, schema, schema), do: entries

  defp reduce_compensated(entries, schema, target) do
    entries
    |> Enum.reduce([], fn {index, {value, c}}, acc ->
      index = target_index(index, schema, target)

      case acc do
        [{^index, {sum, correction}} | rest] ->
          {sum, correction} = Number.compensated_add(value, sum, correction)
          [{index, Number.compensated_add(c, sum, correction)} | rest]

        rest ->
          [{index, {value, c}} | rest]
      end
    end)
    |> Enum.reverse()
  end

  defp map_compensated_custom(h, c, bounds, counts) do
    source = List.to_tuple(h.custom_values)

    h
    |> paired_entries(c, :positive)
    |> Enum.reduce({bounds, 0, counts}, fn {index, {value, correction}}, {bounds, target, counts} ->
      upper = if index < tuple_size(source), do: elem(source, index), else: :infinity
      {passed, bounds} = Enum.split_while(bounds, &lt?(&1, upper))
      target = target + length(passed)
      {sum, total_c} = Map.get(counts, target, {0.0, 0.0})
      {sum, total_c} = Number.compensated_add(value, sum, total_c)
      total = if c, do: Number.compensated_add(correction, sum, total_c), else: {sum, total_c}
      {bounds, target, Map.put(counts, target, total)}
    end)
    |> elem(2)
  end

  defp compensated_zero(h, other, c) do
    {h, c, other_count, other_c} = reconcile_compensated_zero(h, other, c, other.zero_count, other.zero_threshold, 0.0)
    {count, correction} = Number.compensated_add(other_count, h.zero_count, c.zero_count)
    {count, correction} = Number.compensated_add(other_c, count, correction)
    {%{h | zero_count: count}, %{c | zero_count: correction}}
  end

  defp reconcile_compensated_zero(%{zero_threshold: threshold} = h, _other, c, count, threshold, correction),
    do: {h, c, count, correction}

  defp reconcile_compensated_zero(h, other, c, count, threshold, correction) do
    {count, threshold, correction} =
      if gt?(h.zero_threshold, threshold),
        do: larger_compensated_zero(other, nil, h.zero_threshold, 0.0),
        else: {count, threshold, correction}

    {h, c} =
      if gt?(threshold, h.zero_threshold) do
        {zero, threshold, zero_c} = larger_compensated_zero(h, c, threshold, c.zero_count)
        trim_compensated_zero(%{h | zero_count: zero, zero_threshold: threshold}, %{c | zero_count: zero_c})
      else
        {h, c}
      end

    reconcile_compensated_zero(h, other, c, count, threshold, correction)
  end

  defp trim_compensated_zero(h, c) do
    [positive, negative] =
      Enum.map([:positive, :negative], fn side ->
        h
        |> paired_entries(c, side)
        |> Enum.reject(fn {index, {value, correction}} ->
          lt?(bound(index - 1, h.schema, {}), h.zero_threshold) or (zero?(value) and zero?(correction))
        end)
      end)

    put_compensated_sides(h, c, positive, negative)
  end

  # Widening may restart when a negative bucket crosses the new boundary.
  # As in upstream, the compensation carries across that restart.
  defp larger_compensated_zero(h, c, threshold, correction) do
    if threshold == h.zero_threshold do
      {h.zero_count, threshold, correction}
    else
      {count, correction, threshold} = absorb_compensated_zero(h, c, :positive, h.zero_count, correction, threshold)
      {count, correction, larger} = absorb_compensated_zero(h, c, :negative, count, correction, threshold)

      if larger > threshold,
        do: larger_compensated_zero(h, c, larger, correction),
        else: {count, threshold, correction}
    end
  end

  defp absorb_compensated_zero(h, c, side, count, correction, threshold) do
    h
    |> paired_entries(c, side)
    |> Enum.reduce_while({count, correction, threshold}, &absorb_compensated_bucket(&1, &2, h.schema, c != nil))
  end

  defp absorb_compensated_bucket({index, {value, value_c}}, {count, correction, threshold}, schema, correction?) do
    lower = bound(index - 1, schema, {})
    upper = bound(index, schema, {})

    if ge?(lower, threshold) do
      {:halt, {count, correction, threshold}}
    else
      {count, correction} = Number.compensated_add(value, count, correction)

      {count, correction} =
        if correction?, do: Number.compensated_add(value_c, count, correction), else: {count, correction}

      larger = if zero?(value), do: threshold, else: upper

      if gt?(upper, threshold),
        do: {:halt, {count, correction, larger}},
        else: {:cont, {count, correction, threshold}}
    end
  end

  @doc "Subtracts `b` from `a`, reconciling custom bounds as in Mimir; the hint of `a` is kept."
  @spec sub(Histogram.t(), Histogram.t()) ::
          {:ok, Histogram.t()} | {:error, :incompatible_schema}
  def sub(%Histogram{} = a, %Histogram{} = b) do
    case compatible(a, b) do
      :ok -> {:ok, combine(a, b, true)}
      {:error, :incompatible_bounds} -> {:ok, combine_custom(a, b, true)}
      error -> error
    end
  end

  @doc "Multiplies every count and sum by `factor`; negative factors produce gauges (`Mul`)."
  @spec scale(Histogram.t(), value()) :: Histogram.t()
  def scale(%Histogram{} = h, factor) do
    %{
      h
      | counter_reset_hint: if(lt?(factor, 0), do: :gauge, else: h.counter_reset_hint),
        zero_count: Number.multiply(h.zero_count, factor),
        count: Number.multiply(h.count, factor),
        sum: Number.multiply(h.sum, factor),
        positive_buckets: Enum.map(h.positive_buckets, &Number.multiply(&1, factor)),
        negative_buckets: Enum.map(h.negative_buckets, &Number.multiply(&1, factor))
    }
  end

  @doc """
  Divides like `scale/2` (`Div`). Dividing by zero turns the zero count, count
  and sum into ±Inf or NaN and removes every bucket, without changing the hint.
  Negative nonzero divisors produce gauges, as in Mimir dd039cdd.
  """
  @spec divide(Histogram.t(), value()) :: Histogram.t()
  def divide(%Histogram{} = h, divisor) do
    h = %{
      h
      | zero_count: Number.divide(h.zero_count, divisor),
        count: Number.divide(h.count, divisor),
        sum: Number.divide(h.sum, divisor)
    }

    if zero?(divisor) do
      %{h | positive_spans: [], positive_buckets: [], negative_spans: [], negative_buckets: []}
    else
      %{
        h
        | counter_reset_hint: if(lt?(divisor, 0), do: :gauge, else: h.counter_reset_hint),
          positive_buckets: Enum.map(h.positive_buckets, &Number.divide(&1, divisor)),
          negative_buckets: Enum.map(h.negative_buckets, &Number.divide(&1, divisor))
      }
    end
  end

  @doc """
  Mimir's `TrimBuckets`: retain values below `cutoff` when `upper?` is true,
  above it otherwise, estimating split bucket populations and retained sums.
  No-op trims preserve the original totals, layout and reset hint.
  """
  @spec trim(Histogram.t(), value(), boolean()) :: Histogram.t()
  def trim(%Histogram{} = h, cutoff, upper?) do
    {positive, totals, has_positive?} = trim_side(h, :positive, cutoff, upper?, {0.0, 0.0, false})
    {negative, {count, sum, changed?}, has_negative?} = trim_side(h, :negative, cutoff, upper?, totals)

    {zero, count, sum, changed?} =
      if gt?(h.zero_count, 0) do
        {zero, midpoint} = trim_zero(h, cutoff, upper?, has_positive?, has_negative?)

        {zero, Number.add(count, zero), Number.add(sum, Number.multiply(midpoint, zero)),
         changed? or Number.compare("!=", zero, h.zero_count)}
      else
        {h.zero_count, count, sum, changed?}
      end

    if changed? do
      h = %{h | positive_buckets: positive, negative_buckets: negative, zero_count: zero, count: count, sum: sum}
      compact(h)
    else
      h
    end
  end

  defp trim_side(h, side, cutoff, upper?, totals) do
    {buckets, {totals, populated?}} =
      h
      |> side_buckets(side)
      |> Enum.map_reduce({totals, false}, fn bucket, {{count, sum, changed?} = totals, populated?} ->
        if zero?(bucket.count) do
          {bucket.count, {totals, populated?}}
        else
          {keep, midpoint} = trim_bucket(bucket, cutoff, upper?, side == :positive, custom?(h))

          totals =
            {Number.add(count, keep), Number.add(sum, Number.multiply(midpoint, keep)),
             changed? or Number.compare("!=", keep, bucket.count)}

          {keep, {totals, true}}
        end
      end)

    {buckets, totals, populated?}
  end

  defp trim_bucket(bucket, cutoff, upper?, positive?, linear?) do
    keep_all? = if upper?, do: le?(bucket.upper, cutoff), else: ge?(bucket.lower, cutoff)
    contains? = if upper?, do: lt?(bucket.lower, cutoff), else: gt?(bucket.upper, cutoff)

    cond do
      keep_all? ->
        {bucket.count, trim_midpoint(bucket.lower, bucket.upper, positive?, linear?)}

      not contains? ->
        {0.0, 0.0}

      bucket.lower == :negative_infinity or bucket.upper == :infinity ->
        trim_infinite(bucket, cutoff, upper?)

      true ->
        below = trim_split(bucket, cutoff, linear?)

        if upper?,
          do: {below, trim_midpoint(bucket.lower, cutoff, positive?, linear?)},
          else: {minus(bucket.count, below), trim_midpoint(cutoff, bucket.upper, positive?, linear?)}
    end
  end

  defp trim_infinite(%{lower: :negative_infinity} = b, rhs, true) do
    cond do
      ge?(rhs, b.upper) ->
        {b.count, 0.0}

      gt?(rhs, 0) and gt?(b.upper, 0) and b.upper != :infinity ->
        {Number.divide(Number.multiply(b.count, rhs), b.upper), Number.divide(rhs, 2.0)}

      le?(b.upper, 0) ->
        {b.count, rhs}

      true ->
        {0.0, zero_if_infinite(b.upper)}
    end
  end

  defp trim_infinite(%{lower: :negative_infinity} = b, rhs, false) do
    cond do
      rhs == :negative_infinity ->
        {b.count, 0.0}

      ge?(rhs, 0) and gt?(b.upper, rhs) and b.upper != :infinity ->
        {Number.multiply(b.count, minus(1.0, Number.divide(rhs, b.upper))),
         Number.divide(Number.add(rhs, b.upper), 2.0)}

      true ->
        {0.0, zero_if_infinite(b.upper)}
    end
  end

  defp trim_infinite(b, rhs, upper?) do
    cond do
      upper? -> {0.0, zero_if_infinite(b.lower)}
      ge?(rhs, b.lower) -> {b.count, rhs}
      true -> {0.0, zero_if_infinite(b.lower)}
    end
  end

  defp zero_if_infinite(value) when value in [:infinity, :negative_infinity], do: 0.0
  defp zero_if_infinite(value), do: value

  defp trim_split(b, cutoff, linear?) do
    cond do
      le?(cutoff, b.lower) ->
        0.0

      ge?(cutoff, b.upper) ->
        b.count

      linear? ->
        Number.multiply(b.count, Number.divide(minus(cutoff, b.lower), minus(b.upper, b.lower)))

      true ->
        lower = b.lower |> abs_value() |> log2()
        upper = b.upper |> abs_value() |> log2()
        value = cutoff |> abs_value() |> log2()

        fraction =
          if gt?(cutoff, 0),
            do: Number.divide(minus(value, lower), minus(upper, lower)),
            else: minus(1.0, Number.divide(minus(value, upper), minus(lower, upper)))

        Number.multiply(b.count, fraction)
    end
  end

  defp trim_zero(h, cutoff, upper?, has_positive?, has_negative?) do
    lower = if has_positive? and not has_negative?, do: 0.0, else: Number.negate(h.zero_threshold)
    upper = if has_negative? and not has_positive?, do: 0.0, else: h.zero_threshold
    trim_zero_interval(lower, upper, h.zero_count, cutoff, upper?)
  end

  defp trim_zero_interval(lower, upper, count, cutoff, true) do
    cond do
      le?(cutoff, lower) ->
        {0.0, 0.0}

      ge?(cutoff, upper) ->
        {count, Number.divide(Number.add(lower, upper), 2.0)}

      true ->
        {Number.multiply(count, Number.divide(minus(cutoff, lower), minus(upper, lower))),
         Number.divide(Number.add(lower, cutoff), 2.0)}
    end
  end

  defp trim_zero_interval(lower, upper, count, cutoff, false) do
    cond do
      le?(cutoff, lower) ->
        {count, Number.divide(Number.add(lower, upper), 2.0)}

      ge?(cutoff, upper) ->
        {0.0, 0.0}

      true ->
        {Number.multiply(count, Number.divide(minus(upper, cutoff), minus(upper, lower))),
         Number.divide(Number.add(cutoff, upper), 2.0)}
    end
  end

  defp trim_midpoint(lower, upper, _positive?, _linear?) when lower in [:negative_infinity, :infinity] do
    cond do
      upper in [:negative_infinity, :infinity] ->
        0.0

      gt?(upper, 0) ->
        Number.divide(upper, 2.0)

      true ->
        upper
    end
  end

  defp trim_midpoint(lower, upper, _positive?, _linear?) when upper in [:negative_infinity, :infinity], do: lower

  defp trim_midpoint(lower, upper, _positive?, true), do: Number.divide(Number.add(lower, upper), 2.0)

  defp trim_midpoint(lower, upper, positive?, false) do
    midpoint = lower |> Number.multiply(upper) |> abs_value() |> sqrt()
    if positive?, do: midpoint, else: Number.negate(midpoint)
  end

  @doc """
  Merges buckets down to `target_schema` (`ReduceResolution`), keeping empty
  buckets. A target equal to the current schema returns `h` unchanged; a higher
  target or a custom-bucket histogram raises, where Prometheus panics.
  """
  @spec reduce_resolution(Histogram.t(), integer()) :: Histogram.t()
  def reduce_resolution(%Histogram{schema: schema} = h, schema), do: h

  def reduce_resolution(%Histogram{} = h, target) do
    cond do
      custom?(h) -> raise ArgumentError, "cannot reduce resolution when there are custom buckets"
      target == @custom_schema -> raise ArgumentError, "cannot reduce resolution to custom buckets schema"
      target > h.schema -> raise ArgumentError, "cannot reduce resolution from schema #{h.schema} to #{target}"
      true -> do_reduce_resolution(h, target)
    end
  end

  @doc "Removes empty buckets and merges adjacent spans (`Compact(0)`)."
  @spec compact(Histogram.t()) :: Histogram.t()
  def compact(%Histogram{} = h) do
    {positive_spans, positive_buckets} = h |> entries(:positive) |> Enum.reject(&zero?(elem(&1, 1))) |> to_spans()
    {negative_spans, negative_buckets} = h |> entries(:negative) |> Enum.reject(&zero?(elem(&1, 1))) |> to_spans()

    %{
      h
      | positive_spans: positive_spans,
        positive_buckets: positive_buckets,
        negative_spans: negative_spans,
        negative_buckets: negative_buckets
    }
  end

  ## Counter resets and equality

  @doc """
  Whether `current` holds a counter reset relative to `previous`
  (`DetectReset`): the `:yes`/`:no` hints decide directly, otherwise any
  decreased count, zero bucket, bucket, increased resolution, decreased zero
  threshold or changed bucket family is a reset. Differing custom bounds
  compare bucket totals rolled up to their common boundaries, including +Inf.
  """
  @spec detect_reset?(Histogram.t(), Histogram.t()) :: boolean()
  def detect_reset?(%Histogram{counter_reset_hint: :yes}, %Histogram{}), do: true
  def detect_reset?(%Histogram{counter_reset_hint: :no}, %Histogram{}), do: false

  def detect_reset?(%Histogram{} = h, %Histogram{} = previous) do
    cond do
      lt?(h.count, previous.count) -> true
      custom?(h) != custom?(previous) -> true
      custom?(h) and not floats_match?(h.custom_values, previous.custom_values) -> custom_reset?(h, previous)
      h.schema > previous.schema -> true
      lt?(h.zero_threshold, previous.zero_threshold) -> true
      true -> detect_bucket_reset?(h, previous)
    end
  end

  defp custom_reset?(h, previous) do
    bounds = intersect_bounds(h.custom_values, previous.custom_values)

    h
    |> custom_rollups(bounds)
    |> Enum.zip(custom_rollups(previous, bounds))
    |> Enum.any?(fn {current, previous} -> lt?(current, previous) end)
  end

  defp custom_rollups(h, bounds) do
    source = List.to_tuple(h.custom_values)

    {counts, _} =
      Enum.map_reduce(bounds ++ [:infinity], entries(h, :positive), fn upper, entries ->
        {included, remaining} =
          Enum.split_while(entries, fn {index, _} -> le?(bound(index, @custom_schema, source), upper) end)

        # Reset detection uses plain source-ordered addition, unlike subtraction.
        sum = Enum.reduce(included, 0.0, fn {_, count}, sum -> Number.add(sum, count) end)
        {sum, remaining}
      end)

    counts
  end

  defp detect_bucket_reset?(h, previous) do
    {previous_zero_count, threshold, _correction} = larger_compensated_zero(previous, nil, h.zero_threshold, 0.0)

    cond do
      threshold != h.zero_threshold -> true
      lt?(h.zero_count, previous_zero_count) -> true
      true -> Enum.any?([:positive, :negative], &side_reset?(h, previous, &1))
    end
  end

  defp side_reset?(h, previous, side) do
    current = target_entries(h, side, h.zero_threshold, h.schema)
    previous = target_entries(previous, side, h.zero_threshold, h.schema)
    entries_reset?(current, previous)
  end

  # Exhausting current buckets does not prove a reset until a remaining
  # previous bucket has nonzero population; leading empty buckets cannot hide it.
  defp entries_reset?(_current, []), do: false
  defp entries_reset?([], previous), do: Enum.any?(previous, fn {_, count} -> not zero?(count) end)

  defp entries_reset?([{index, _} | current], [{previous_index, _} | _] = previous) when index < previous_index,
    do: entries_reset?(current, previous)

  defp entries_reset?([{index, _} | _] = current, [{previous_index, count} | rest]) when index > previous_index,
    do: not zero?(count) or entries_reset?(current, rest)

  defp entries_reset?([{_, count} | _] = current, [{_, previous_count} | rest]),
    do: lt?(count, previous_count) or entries_reset?(current, rest)

  @doc """
  Prometheus's `FloatHistogram.Equals`: counts, sums and buckets compare by bit
  pattern, spans by the bucket layout they describe (zero-length spans are
  ignored, zero-offset splits are not).
  """
  @spec equal?(Histogram.t(), Histogram.t()) :: boolean()
  def equal?(%Histogram{} = a, %Histogram{} = b) do
    a.schema == b.schema and same_bits?(a.count, b.count) and same_bits?(a.sum, b.sum) and
      (not custom?(a) or floats_match?(a.custom_values, b.custom_values)) and
      a.zero_threshold == b.zero_threshold and same_bits?(a.zero_count, b.zero_count) and
      side_equal?(a.negative_spans, a.negative_buckets, b.negative_spans, b.negative_buckets) and
      side_equal?(a.positive_spans, a.positive_buckets, b.positive_spans, b.positive_buckets)
  end

  defp side_equal?(spans, buckets, other_spans, other_buckets),
    do: spans_match?(spans, other_spans) and floats_match?(buckets, other_buckets)

  ## PromQL functions

  @doc "`histogram_count`: the observation count."
  @spec count(Histogram.t()) :: value()
  def count(%Histogram{count: count}), do: count

  @doc "`histogram_sum`: the sum of observations."
  @spec sum(Histogram.t()) :: value()
  def sum(%Histogram{sum: sum}), do: sum

  @doc "`histogram_avg`: sum divided by count (NaN for an empty histogram)."
  @spec avg(Histogram.t()) :: value()
  def avg(%Histogram{} = h), do: Number.divide(h.sum, h.count)

  @doc """
  `histogram_stdvar`: the variance estimated from bucket midpoints (geometric
  for exponential buckets, arithmetic for custom buckets, zero for the zero
  bucket), Kahan-summed like Prometheus.
  """
  @spec stdvar(Histogram.t()) :: value()
  def stdvar(%Histogram{} = h) do
    mean = Number.divide(h.sum, h.count)

    {variance, correction} =
      h
      |> all_buckets(:forward)
      |> Enum.reject(&zero?(&1.count))
      |> Enum.reduce({0.0, 0.0}, fn bucket, {variance, correction} ->
        delta = minus(midpoint(h, bucket), mean)
        bucket.count |> Number.multiply(delta) |> Number.multiply(delta) |> Number.compensated_add(variance, correction)
      end)

    variance |> Number.add(correction) |> Number.divide(h.count)
  end

  @doc "`histogram_stddev`: the square root of `stdvar/1`."
  @spec stddev(Histogram.t()) :: value()
  def stddev(%Histogram{} = h), do: h |> stdvar() |> sqrt()

  defp midpoint(h, bucket) do
    cond do
      custom?(h) ->
        bucket.upper |> Number.add(bucket.lower) |> Number.divide(2.0)

      le?(bucket.lower, 0) and ge?(bucket.upper, 0) ->
        0.0

      true ->
        value = bucket.upper |> Number.multiply(bucket.lower) |> sqrt()
        if lt?(bucket.upper, 0), do: Number.negate(value), else: value
    end
  end

  @doc "`histogram_quantile` for a native histogram; see `quantile_with_info/2`."
  @spec quantile(value(), Histogram.t()) :: value()
  def quantile(q, %Histogram{} = h), do: q |> quantile_with_info(h) |> elem(0)

  @doc """
  Prometheus's `HistogramQuantile`, returning the value and the info
  annotations it would raise: `:nan_result` (the quantile fell above every
  bucket because of NaN observations) or `:nan_skew` (NaN observations may
  skew the result higher).

  q < 0 is -Inf, q > 1 is +Inf, NaN q or an empty histogram is NaN. Within a
  bucket the value is interpolated exponentially for exponential buckets and
  linearly for custom buckets and the zero bucket.
  """
  @spec quantile_with_info(value(), Histogram.t()) :: {value(), [info()]}
  def quantile_with_info(q, %Histogram{} = h) do
    cond do
      lt?(q, 0) -> {:negative_infinity, []}
      gt?(q, 1) -> {:infinity, []}
      zero?(h.count) or q == :nan -> {:nan, []}
      true -> locate_quantile(q, h)
    end
  end

  defp locate_quantile(q, h) do
    forward? = h.sum == :nan or lt?(q, 0.5)

    {buckets, rank} =
      if forward?,
        do: {all_buckets(h, :forward), Number.multiply(q, h.count)},
        else: {all_buckets(h, :reverse), Number.multiply(minus(1.0, q), h.count)}

    {bucket, count, rest} = find_rank(buckets, rank, empty_bucket(), 0.0)
    count = if gt?(count, h.count), do: h.count, else: count

    case quantile_bounds(h, bucket) do
      {:done, value} ->
        {value, []}

      {:ok, bucket} ->
        cond do
          not lt?(count, rank) -> interpolate_quantile(h, bucket, rank, count, rest, forward?)
          h.sum == :nan -> {:nan, [:nan_result]}
          true -> {bucket.upper, []}
        end
    end
  end

  defp find_rank([], _rank, bucket, count), do: {bucket, count, []}

  defp find_rank([bucket | rest], rank, _previous, count) do
    if zero?(bucket.count) do
      find_rank(rest, rank, bucket, count)
    else
      count = Number.add(count, bucket.count)
      if ge?(count, rank), do: {bucket, count, rest}, else: find_rank(rest, rank, bucket, count)
    end
  end

  # Custom buckets: the first one starts at zero (or answers its upper bound
  # when that is not positive), the +Inf one answers its lower bound.
  defp quantile_bounds(%{schema: @custom_schema}, bucket) do
    cond do
      bucket.lower == :negative_infinity and le?(bucket.upper, 0) -> {:done, bucket.upper}
      bucket.lower == :negative_infinity -> {:ok, %{bucket | lower: 0.0}}
      bucket.upper == :infinity -> {:done, bucket.lower}
      true -> {:ok, bucket}
    end
  end

  defp quantile_bounds(h, bucket) do
    if lt?(bucket.lower, 0) and gt?(bucket.upper, 0) do
      {:ok, zero_bucket_bounds(h, bucket)}
    else
      {:ok, bucket}
    end
  end

  # The zero bucket of a histogram with buckets on only one side ends at zero.
  defp zero_bucket_bounds(h, bucket) do
    cond do
      h.negative_buckets == [] and h.positive_buckets != [] -> %{bucket | lower: 0.0}
      h.positive_buckets == [] and h.negative_buckets != [] -> %{bucket | upper: 0.0}
      true -> bucket
    end
  end

  defp interpolate_quantile(h, bucket, rank, count, rest, forward?) do
    rank =
      if forward?,
        do: minus(rank, minus(count, bucket.count)),
        else: minus(count, rank)

    infos =
      if h.sum == :nan and lt?(Enum.reduce(rest, count, &Number.add(&2, &1.count)), h.count),
        do: [:nan_skew],
        else: []

    fraction = Number.divide(rank, bucket.count)
    {interpolate(h, bucket, fraction), infos}
  end

  defp interpolate(h, %{lower: lower, upper: upper}, fraction) do
    if custom?(h) or (le?(lower, 0) and ge?(upper, 0)) do
      Number.add(lower, upper |> minus(lower) |> Number.multiply(fraction))
    else
      log_lower = lower |> abs_value() |> log2()
      log_upper = upper |> abs_value() |> log2()

      if gt?(lower, 0) do
        exp2(Number.add(log_lower, log_upper |> minus(log_lower) |> Number.multiply(fraction)))
      else
        inverse = minus(1.0, fraction)
        log = Number.add(log_upper, log_lower |> minus(log_upper) |> Number.multiply(inverse))
        log |> exp2() |> Number.negate()
      end
    end
  end

  @doc "`histogram_fraction`; see `fraction_with_info/3`."
  @spec fraction(value(), value(), Histogram.t()) :: value()
  def fraction(lower, upper, %Histogram{} = h), do: lower |> fraction_with_info(upper, h) |> elem(0)

  @doc """
  Prometheus's `HistogramFraction`: the estimated fraction of observations
  between `lower` and `upper`, with `:nan_observations` when NaN observations
  were excluded from every fraction.
  """
  @spec fraction_with_info(value(), value(), Histogram.t()) :: {value(), [info()]}
  def fraction_with_info(lower, upper, %Histogram{} = h) do
    cond do
      zero?(h.count) or lower == :nan or upper == :nan -> {:nan, []}
      ge?(lower, upper) -> {0.0, []}
      true -> locate_fraction(lower, upper, h)
    end
  end

  defp locate_fraction(lower, upper, h) do
    state = %{rank: 0.0, count: 0.0, lower_rank: 0.0, upper_rank: 0.0, lower_set?: false, upper_set?: false}
    {state, rest} = fraction_ranks(all_buckets(h, :forward), lower, upper, h, state)

    {count, infos} =
      if h.sum == :nan do
        count = Enum.reduce(rest, state.count, &Number.add(&2, &1.count))
        {count, if(lt?(count, h.count), do: [:nan_observations], else: [])}
      else
        {h.count, []}
      end

    lower_rank = if state.lower_set? and not gt?(state.lower_rank, count), do: state.lower_rank, else: count
    upper_rank = if state.upper_set? and not gt?(state.upper_rank, count), do: state.upper_rank, else: count
    {upper_rank |> minus(lower_rank) |> Number.divide(h.count), infos}
  end

  defp fraction_ranks([], _lower, _upper, _h, state), do: {state, []}

  defp fraction_ranks([bucket | rest], lower, upper, h, state) do
    state = %{state | count: Number.add(state.count, bucket.count)}
    {bucket, linear?} = fraction_bucket(h, bucket)

    state =
      state
      |> set_rank_at_bound(:lower, ge?(bucket.lower, lower), state.rank)
      |> set_rank_at_bound(:upper, ge?(bucket.lower, upper), state.rank)

    if state.lower_set? and state.upper_set? do
      {state, rest}
    else
      state =
        state
        |> set_rank_at_bound(:lower, inside?(bucket, lower), fn -> rank_at(bucket, lower, state.rank, linear?) end)
        |> set_rank_at_bound(:upper, inside?(bucket, upper), fn -> rank_at(bucket, upper, state.rank, linear?) end)

      if state.lower_set? and state.upper_set?,
        do: {state, rest},
        else: fraction_ranks(rest, lower, upper, h, %{state | rank: Number.add(state.rank, bucket.count)})
    end
  end

  defp fraction_bucket(%{schema: @custom_schema}, bucket) do
    bucket =
      if bucket.lower == :negative_infinity and gt?(bucket.upper, 0),
        do: %{bucket | lower: 0.0},
        else: bucket

    {bucket, true}
  end

  defp fraction_bucket(h, bucket) do
    zero_bucket? = le?(bucket.lower, 0) and ge?(bucket.upper, 0)
    bucket = if zero_bucket?, do: zero_bucket_bounds(h, bucket), else: bucket
    {bucket, zero_bucket?}
  end

  defp set_rank_at_bound(state, :lower, true, rank) when not state.lower_set?,
    do: %{state | lower_rank: resolve(rank), lower_set?: true}

  defp set_rank_at_bound(state, :upper, true, rank) when not state.upper_set?,
    do: %{state | upper_rank: resolve(rank), upper_set?: true}

  defp set_rank_at_bound(state, _bound, _hit?, _rank), do: state

  defp resolve(rank) when is_function(rank, 0), do: rank.()
  defp resolve(rank), do: rank

  defp inside?(bucket, value), do: lt?(bucket.lower, value) and gt?(bucket.upper, value)

  # Finite values cannot interpolate an infinite-width first custom bucket.
  # Its full population lies below any finite interior bound, as in Mimir.
  defp rank_at(%{lower: :negative_infinity} = bucket, _value, _rank, true), do: bucket.count

  defp rank_at(bucket, value, rank, true = _linear?) do
    fraction = Number.divide(minus(value, bucket.lower), minus(bucket.upper, bucket.lower))
    Number.add(rank, Number.multiply(bucket.count, fraction))
  end

  defp rank_at(bucket, value, rank, false = _linear?) do
    log_lower = bucket.lower |> abs_value() |> log2()
    log_upper = bucket.upper |> abs_value() |> log2()
    log_value = value |> abs_value() |> log2()

    fraction =
      if gt?(value, 0) do
        Number.divide(minus(log_value, log_lower), minus(log_upper, log_lower))
      else
        minus(1.0, Number.divide(minus(log_value, log_upper), minus(log_lower, log_upper)))
      end

    Number.add(rank, Number.multiply(bucket.count, fraction))
  end

  @doc """
  Every populated bucket as `/api/v1/query` reports it, in Prometheus's order
  (negative buckets from the lowest, the zero bucket, then positive buckets):
  `{boundary_rule, lower, upper, count}` with rule 0 = (lower, upper],
  1 = [lower, upper), 2 = (lower, upper), 3 = [lower, upper].
  """
  @spec buckets(Histogram.t()) :: [{boundary_rule(), value(), value(), value()}]
  def buckets(%Histogram{} = h) do
    for bucket <- all_buckets(h, :forward), not zero?(bucket.count) do
      {boundary_rule(bucket), bucket.lower, bucket.upper, bucket.count}
    end
  end

  defp boundary_rule(%{lower_inclusive?: true, upper_inclusive?: true}), do: 3
  defp boundary_rule(%{lower_inclusive?: true}), do: 1
  defp boundary_rule(%{upper_inclusive?: true}), do: 0
  defp boundary_rule(_bucket), do: 2

  # FloatHistogram.String uses the individual side iterators, not the
  # zero-clipped AllBucketIterator used by the HTTP histogram envelope.
  def value_text(%Histogram{} = h) do
    zero =
      if zero?(h.zero_count),
        do: [],
        else: [
          %{
            lower: Number.negate(h.zero_threshold),
            upper: h.zero_threshold,
            count: h.zero_count,
            lower_inclusive?: true,
            upper_inclusive?: true
          }
        ]

    buckets = Enum.reverse(side_buckets(h, :negative), zero ++ side_buckets(h, :positive))

    [
      "{count:",
      Number.format(h.count, :general),
      ", sum:",
      Number.format(h.sum, :general),
      for(bucket <- buckets, not zero?(bucket.count), do: bucket_text(bucket)),
      "}"
    ]
  end

  defp bucket_text(bucket) do
    [
      ", ",
      if(bucket.lower_inclusive?, do: "[", else: "("),
      Number.format(bucket.lower, :general),
      ",",
      Number.format(bucket.upper, :general),
      if(bucket.upper_inclusive?, do: "]", else: ")"),
      ":",
      Number.format(bucket.count, :general)
    ]
  end

  ## Add and Sub

  defp compatible(a, b) do
    cond do
      custom?(a) != custom?(b) -> {:error, :incompatible_schema}
      custom?(a) and not floats_match?(a.custom_values, b.custom_values) -> {:error, :incompatible_bounds}
      true -> :ok
    end
  end

  # Mimir's intersectCustomBucketBounds/addCustomBucketsWithMismatches.
  # Roll each input bucket up to the next common upper bound (or +Inf),
  # preserving source order and Neumaier compensation across both inputs.
  defp combine_custom(a, b, subtract?) do
    op = if subtract?, do: "-", else: "+"
    bounds = intersect_bounds(a.custom_values, b.custom_values)
    counts = a |> map_custom(bounds, %{}, false) |> then(&map_custom(b, bounds, &1, subtract?))

    entries =
      for index <- 0..length(bounds),
          {sum, correction} = Map.get(counts, index, {0.0, 0.0}),
          not zero?(sum) or not zero?(correction),
          do: {index, sum}

    {spans, buckets} = to_spans(entries)

    %{
      a
      | count: Number.binary(op, a.count, b.count),
        sum: Number.binary(op, a.sum, b.sum),
        custom_values: bounds,
        positive_spans: spans,
        positive_buckets: buckets
    }
  end

  defp intersect_bounds([], _), do: []
  defp intersect_bounds(_, []), do: []
  defp intersect_bounds([a | as], [b | bs]) when a == b, do: [a | intersect_bounds(as, bs)]
  defp intersect_bounds([a | as], [b | _] = bs) when a < b, do: intersect_bounds(as, bs)
  defp intersect_bounds(as, [_ | bs]), do: intersect_bounds(as, bs)

  defp map_custom(h, bounds, counts, subtract?) do
    source = List.to_tuple(h.custom_values)

    h
    |> entries(:positive)
    |> Enum.reduce({bounds, 0, counts}, fn {index, value}, {bounds, target, counts} ->
      upper = if index < tuple_size(source), do: elem(source, index), else: :infinity
      {passed, bounds} = Enum.split_while(bounds, &lt?(&1, upper))
      target = target + length(passed)
      {sum, correction} = Map.get(counts, target, {0.0, 0.0})
      value = if subtract?, do: Number.negate(value), else: value
      counts = Map.put(counts, target, Number.compensated_add(value, sum, correction))
      {bounds, target, counts}
    end)
    |> elem(2)
  end

  defp add_hint(hint, hint), do: hint
  defp add_hint(:gauge, _other), do: :gauge
  defp add_hint(_hint, :gauge), do: :gauge
  # Unknown absorbs everything else, including a direct :yes/:no collision.
  defp add_hint(_hint, _other), do: :unknown

  defp combine(h, other, subtract?) do
    op = if subtract?, do: "-", else: "+"

    {h, other_zero_count} =
      if custom?(h), do: {h, nil}, else: reconcile_zero_buckets(h, other)

    h = %{
      h
      | zero_count: if(custom?(h), do: h.zero_count, else: Number.binary(op, h.zero_count, other_zero_count)),
        count: Number.binary(op, h.count, other.count),
        sum: Number.binary(op, h.sum, other.sum)
    }

    {h, other} = reconcile_schemas(h, other)
    put_sides(h, other, subtract?)
  end

  defp reconcile_schemas(h, other) do
    cond do
      custom?(h) -> {h, other}
      other.schema < h.schema -> {do_reduce_resolution(h, other.schema), other}
      other.schema > h.schema -> {h, do_reduce_resolution(other, h.schema)}
      true -> {h, other}
    end
  end

  defp put_sides(h, other, subtract?) do
    {positive_spans, positive_buckets} = merge_buckets(h, other, :positive, subtract?)

    if custom?(h) do
      %{h | positive_spans: positive_spans, positive_buckets: positive_buckets}
    else
      {negative_spans, negative_buckets} = merge_buckets(h, other, :negative, subtract?)

      %{
        h
        | positive_spans: positive_spans,
          positive_buckets: positive_buckets,
          negative_spans: negative_spans,
          negative_buckets: negative_buckets
      }
    end
  end

  # Prometheus's addBuckets: the other histogram's buckets below the zero
  # threshold are ignored, the rest are inserted or added.
  defp merge_buckets(h, other, side, subtract?) do
    others =
      other
      |> entries(side)
      |> Enum.drop_while(fn {index, _} ->
        exponential?(h.schema) and le?(bound(index, h.schema, {}), h.zero_threshold)
      end)
      |> Enum.map(fn {index, count} -> {index, if(subtract?, do: Number.multiply(count, -1.0), else: count)} end)

    h |> entries(side) |> merge_entries(others, []) |> to_spans()
  end

  defp merge_entries([], others, acc), do: Enum.reverse(acc, others)
  defp merge_entries(entries, [], acc), do: Enum.reverse(acc, entries)

  defp merge_entries([{index, count} | entries], [{index, other} | others], acc),
    do: merge_entries(entries, others, [{index, Number.add(count, other)} | acc])

  defp merge_entries([{index, _} = entry | entries], [{other_index, _} | _] = others, acc) when index < other_index,
    do: merge_entries(entries, others, [entry | acc])

  defp merge_entries(entries, [entry | others], acc), do: merge_entries(entries, others, [entry | acc])

  ## Zero bucket reconciliation

  # Widens both zero buckets until their thresholds agree and neither cuts
  # through a populated bucket. Returns `h` widened (and trimmed) plus the zero
  # count `other` would have at that threshold.
  defp reconcile_zero_buckets(h, other), do: reconcile_zero_buckets(h, other, other.zero_count, other.zero_threshold)

  defp reconcile_zero_buckets(%{zero_threshold: threshold} = h, _other, other_count, threshold), do: {h, other_count}

  defp reconcile_zero_buckets(h, other, other_count, other_threshold) do
    {other_count, other_threshold} =
      if gt?(h.zero_threshold, other_threshold),
        do: zero_count_for_larger_threshold(other, h.zero_threshold),
        else: {other_count, other_threshold}

    h =
      if gt?(other_threshold, h.zero_threshold) do
        {zero_count, threshold} = zero_count_for_larger_threshold(h, other_threshold)
        trim_buckets_in_zero_bucket(%{h | zero_count: zero_count, zero_threshold: threshold})
      else
        h
      end

    reconcile_zero_buckets(h, other, other_count, other_threshold)
  end

  # The zero count `h` would have with a zero threshold of at least `larger`,
  # and that threshold, raised to the edge of any populated bucket it cuts.
  defp zero_count_for_larger_threshold(%{zero_threshold: threshold} = h, threshold), do: {h.zero_count, threshold}

  defp zero_count_for_larger_threshold(h, larger) do
    if lt?(larger, h.zero_threshold) do
      raise ArgumentError, "new threshold #{inspect(larger)} is less than old threshold #{inspect(h.zero_threshold)}"
    end

    {count, larger} = absorb_positive(side_buckets(h, :positive), h.zero_count, larger)

    case absorb_negative(side_buckets(h, :negative), count, larger) do
      {:restart, larger} -> zero_count_for_larger_threshold(h, larger)
      {:ok, count} -> {count, larger}
    end
  end

  defp absorb_positive([], count, larger), do: {count, larger}

  defp absorb_positive([bucket | rest], count, larger) do
    cond do
      ge?(bucket.lower, larger) ->
        {count, larger}

      gt?(bucket.upper, larger) ->
        {Number.add(count, bucket.count), if(zero?(bucket.count), do: larger, else: bucket.upper)}

      true ->
        absorb_positive(rest, Number.add(count, bucket.count), larger)
    end
  end

  defp absorb_negative([], count, _larger), do: {:ok, count}

  defp absorb_negative([bucket | rest], count, larger) do
    cond do
      le?(bucket.upper, Number.negate(larger)) -> {:ok, count}
      not lt?(bucket.lower, Number.negate(larger)) -> absorb_negative(rest, Number.add(count, bucket.count), larger)
      zero?(bucket.count) -> {:ok, Number.add(count, bucket.count)}
      true -> {:restart, Number.negate(bucket.lower)}
    end
  end

  # Zeroes the buckets now inside the zero bucket (their counts already moved
  # there), then compacts the whole histogram as Prometheus does.
  defp trim_buckets_in_zero_bucket(h) do
    positive = h |> side_buckets(:positive) |> Enum.count(&lt?(&1.lower, h.zero_threshold))
    negative = h |> side_buckets(:negative) |> Enum.count(&gt?(&1.upper, Number.negate(h.zero_threshold)))

    compact(%{
      h
      | positive_buckets: zero_leading(h.positive_buckets, positive),
        negative_buckets: zero_leading(h.negative_buckets, negative)
    })
  end

  defp zero_leading(buckets, count) do
    {leading, rest} = Enum.split(buckets, count)
    Enum.map(leading, fn _ -> 0.0 end) ++ rest
  end

  ## Resolution

  defp do_reduce_resolution(h, target) do
    {positive_spans, positive_buckets} = h |> entries(:positive) |> reduce_entries(h.schema, target) |> to_spans()
    {negative_spans, negative_buckets} = h |> entries(:negative) |> reduce_entries(h.schema, target) |> to_spans()

    %{
      h
      | schema: target,
        positive_spans: positive_spans,
        positive_buckets: positive_buckets,
        negative_spans: negative_spans,
        negative_buckets: negative_buckets
    }
  end

  # Prometheus's reduceResolution on absolute counts: a merged bucket starts
  # with its first original count.
  defp reduce_entries(entries, schema, target) do
    entries
    |> Enum.reduce([], fn {index, count}, acc ->
      target_index = target_index(index, schema, target)

      case acc do
        [{^target_index, total} | acc] -> [{target_index, Number.add(total, count)} | acc]
        acc -> [{target_index, count} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp target_index(index, schema, target), do: ((index - 1) >>> (schema - target)) + 1

  # floatBucketIterator: merges to `target` (summing from zero) and skips
  # leading exponential buckets whose upper bound is ≤ `start`.
  defp target_entries(h, side, start, target) do
    entries = entries(h, side)

    entries =
      if target == h.schema do
        entries
      else
        entries
        |> Enum.chunk_by(fn {index, _} -> target_index(index, h.schema, target) end)
        |> Enum.map(fn [{index, _} | _] = chunk ->
          {target_index(index, h.schema, target), Enum.reduce(chunk, 0.0, &Number.add(&2, elem(&1, 1)))}
        end)
      end

    if start == 0 or not exponential?(target),
      do: entries,
      else: Enum.drop_while(entries, fn {index, _} -> le?(bound(index, target, {}), start) end)
  end

  ## Bucket iteration

  # `{index, count}` for every bucket a side's spans describe, in index order.
  defp entries(h, :positive), do: expand(h.positive_spans, h.positive_buckets)
  defp entries(h, :negative), do: expand(h.negative_spans, h.negative_buckets)

  defp expand(spans, buckets) do
    spans
    |> Enum.reduce({0, buckets, []}, fn {offset, length}, {position, buckets, acc} ->
      start = position + offset
      {counts, buckets} = Enum.split(buckets, length)
      indexed = counts |> Enum.with_index(start) |> Enum.map(fn {count, index} -> {index, count} end)
      {start + length, buckets, Enum.reverse(indexed, acc)}
    end)
    |> elem(2)
    |> Enum.reverse()
  end

  # Spans with adjacent indexes fused into one run, as Compact leaves them.
  defp to_spans(entries) do
    {spans, buckets, _} =
      Enum.reduce(entries, {[], [], nil}, fn {index, count}, {spans, buckets, last} ->
        spans =
          case spans do
            [{offset, length} | rest] when index == last + 1 -> [{offset, length + 1} | rest]
            [] -> [{index, 1}]
            spans -> [{index - last - 1, 1} | spans]
          end

        {spans, [count | buckets], index}
      end)

    {Enum.reverse(spans), Enum.reverse(buckets)}
  end

  # One side's buckets with bounds, ascending in absolute value
  # (PositiveBucketIterator / NegativeBucketIterator).
  defp side_buckets(h, side) do
    custom_values = if side == :positive, do: List.to_tuple(h.custom_values), else: {}
    h |> entries(side) |> Enum.map(&bucket_at(&1, h.schema, side, custom_values))
  end

  defp bucket_at({index, count}, schema, side, custom_values) do
    {lower, upper} =
      case side do
        :positive ->
          {bound(index - 1, schema, custom_values), bound(index, schema, custom_values)}

        :negative ->
          {Number.negate(bound(index, schema, custom_values)), Number.negate(bound(index - 1, schema, custom_values))}
      end

    {lower_inclusive?, upper_inclusive?} =
      if schema == @custom_schema, do: {index == 0, true}, else: {lt?(lower, 0), gt?(upper, 0)}

    %{
      index: index,
      count: count,
      lower: lower,
      upper: upper,
      lower_inclusive?: lower_inclusive?,
      upper_inclusive?: upper_inclusive?
    }
  end

  defp empty_bucket,
    do: %{index: 0, count: 0.0, lower: 0.0, upper: 0.0, lower_inclusive?: false, upper_inclusive?: false}

  # AllBucketIterator (:forward) and AllReverseBucketIterator (:reverse): the
  # zero bucket only appears when populated, and buckets overlapping it are
  # clipped to the zero threshold.
  defp all_buckets(h, direction) do
    negative = side_buckets(h, :negative)
    positive = side_buckets(h, :positive)

    zero =
      if gt?(h.zero_count, 0) do
        [
          %{
            index: 0,
            count: h.zero_count,
            lower: Number.negate(h.zero_threshold),
            upper: h.zero_threshold,
            lower_inclusive?: true,
            upper_inclusive?: true
          }
        ]
      else
        []
      end

    ordered =
      case direction do
        :forward -> Enum.reverse(negative, zero ++ positive)
        :reverse -> Enum.reverse(positive, zero ++ negative)
      end

    Enum.map(ordered, &clip_to_zero_bucket(&1, h.zero_threshold))
  end

  defp clip_to_zero_bucket(bucket, threshold) do
    cond do
      lt?(bucket.upper, 0) and gt?(bucket.upper, Number.negate(threshold)) ->
        %{bucket | upper: Number.negate(threshold)}

      gt?(bucket.lower, 0) and lt?(bucket.lower, threshold) ->
        %{bucket | lower: threshold}

      true ->
        bucket
    end
  end

  ## Bounds

  defp bound(index, @custom_schema, custom_values) do
    length = tuple_size(custom_values)

    cond do
      index > length or index < -1 ->
        raise ArgumentError, "index #{index} out of bounds for custom bounds of length #{length}"

      index == length ->
        :infinity

      index == -1 ->
        :negative_infinity

      true ->
        elem(custom_values, index)
    end
  end

  defp bound(index, schema, _custom_values), do: exponential_bound(index, schema)

  # getBoundExponential: the last finite bucket ends at math.MaxFloat64.
  defp exponential_bound(index, schema) when schema < 0 do
    exp = index <<< -schema
    if exp == 1024, do: @max_float, else: ldexp(1.0, exp)
  end

  defp exponential_bound(index, schema) do
    frac = @exponential_bounds |> elem(schema) |> elem(index &&& (1 <<< schema) - 1)
    exp = (index >>> schema) + 1
    if frac == 0.5 and exp == 1025, do: @max_float, else: ldexp(frac, exp)
  end

  ## Go math ports

  # math.Ldexp for a finite, positive, normal `frac`.
  defp ldexp(frac, exp) do
    <<0::1, biased::11, mantissa::52>> = <<frac::float-64>>
    exp = biased - 1023 + exp

    cond do
      exp < -1075 ->
        0.0

      exp > 1023 ->
        :infinity

      exp < -1022 ->
        <<value::float-64>> = <<0::1, exp + 53 + 1023::11, mantissa::52>>
        value * @two_pow_minus_53

      true ->
        <<value::float-64>> = <<0::1, exp + 1023::11, mantissa::52>>
        value
    end
  end

  # math.Frexp for a finite, positive value: {frac in [0.5, 1), exp}.
  defp frexp(value) do
    case <<value::float-64>> do
      <<0::1, 0::11, _::52>> ->
        {frac, exp} = frexp(value * 4_503_599_627_370_496.0)
        {frac, exp - 52}

      <<0::1, biased::11, mantissa::52>> ->
        <<frac::float-64>> = <<0::1, 1022::11, mantissa::52>>
        {frac, biased - 1022}
    end
  end

  # math.Log2: exact for powers of two, otherwise Log(frac)/Ln2 + exp.
  defp log2(:nan), do: :nan
  defp log2(:infinity), do: :infinity
  defp log2(value) when value < 0, do: :nan
  defp log2(value) when value == 0, do: :negative_infinity

  defp log2(value) do
    case frexp(value) do
      {0.5, exp} -> exp - 1.0
      {frac, exp} -> log(frac) * @log2_e + exp
    end
  end

  # Go's pure math.Log (FreeBSD's e_log.c), for finite positive values.
  defp log(value) do
    {f1, ki} = frexp(value)
    {f1, ki} = if f1 < @sqrt2_half, do: {f1 * 2, ki - 1}, else: {f1, ki}
    f = f1 - 1
    k = ki * 1.0

    s = f / (2 + f)
    s2 = s * s
    s4 = s2 * s2
    t1 = s2 * (@log_l1 + s4 * (@log_l3 + s4 * (@log_l5 + s4 * @log_l7)))
    t2 = s4 * (@log_l2 + s4 * (@log_l4 + s4 * @log_l6))
    r = t1 + t2
    hfsq = 0.5 * f * f
    k * @ln2_hi - (hfsq - (s * (hfsq + r) + k * @ln2_lo) - f)
  end

  # Go's pure math.Exp2 (amd64 has no assembly version).
  defp exp2(:nan), do: :nan
  defp exp2(:infinity), do: :infinity
  defp exp2(:negative_infinity), do: 0.0
  defp exp2(value) when value > 1_023.9999999999999, do: :infinity
  defp exp2(value) when value < -1_074.0, do: 0.0

  defp exp2(value) do
    k =
      cond do
        value > 0 -> trunc(value + 0.5)
        value < 0 -> trunc(value - 0.5)
        true -> 0
      end

    t = value - k
    hi = t * @ln2_hi
    lo = -t * @ln2_lo

    # expmulti
    r = hi - lo
    t = r * r
    c = r - t * (@exp_p1 + t * (@exp_p2 + t * (@exp_p3 + t * (@exp_p4 + t * @exp_p5))))
    y = 1 - (lo - r * c / (2 - c) - hi)
    ldexp(y, k)
  end

  defp sqrt(:nan), do: :nan
  defp sqrt(:infinity), do: :infinity
  defp sqrt(:negative_infinity), do: :nan
  defp sqrt(value) when value < 0, do: :nan
  defp sqrt(value), do: :math.sqrt(value)

  defp abs_value(:negative_infinity), do: :infinity
  defp abs_value(value) when is_atom(value), do: value
  defp abs_value(value), do: abs(value)

  ## Helpers

  defp custom?(%Histogram{schema: schema}), do: schema == @custom_schema
  defp exponential?(schema), do: schema >= -4 and schema <= 8

  defp minus(a, b), do: Number.binary("-", a, b)
  defp zero?(value), do: is_number(value) and value == 0
  defp lt?(a, b), do: Number.compare("<", a, b)
  defp gt?(a, b), do: Number.compare(">", a, b)
  defp le?(a, b), do: Number.compare("<=", a, b)
  defp ge?(a, b), do: Number.compare(">=", a, b)

  defp same_bits?(a, b) when is_number(a) and is_number(b), do: <<a::float-64>> == <<b::float-64>>
  defp same_bits?(a, b), do: a == b

  defp floats_match?(a, b), do: length(a) == length(b) and Enum.all?(Enum.zip(a, b), fn {x, y} -> same_bits?(x, y) end)

  # spansMatch: zero-length spans fold their offset into the next span.
  defp spans_match?([], []), do: true
  defp spans_match?([], rest), do: Enum.all?(rest, &(elem(&1, 1) == 0))
  defp spans_match?(rest, []), do: Enum.all?(rest, &(elem(&1, 1) == 0))

  defp spans_match?(a, b) do
    {span_a, rest_a} = fold_empty_spans(a)
    {span_b, rest_b} = fold_empty_spans(b)

    cond do
      elem(span_a, 1) == 0 and elem(span_b, 1) == 0 -> true
      span_a != span_b -> false
      true -> spans_match?(rest_a, rest_b)
    end
  end

  defp fold_empty_spans([{_, length} = span | rest]) when length > 0, do: {span, rest}

  defp fold_empty_spans([{offset, 0} | rest]) do
    {empty, rest} = Enum.split_while(rest, &(elem(&1, 1) == 0))
    offset = Enum.reduce(empty, offset, &(elem(&1, 0) + &2))

    case rest do
      [{next_offset, length} | rest] -> {{offset + next_offset, length}, rest}
      [] -> {{offset, 0}, []}
    end
  end
end
