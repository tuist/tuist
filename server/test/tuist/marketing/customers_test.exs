defmodule Tuist.Marketing.CustomersTest do
  use ExUnit.Case, async: true

  alias Tuist.Marketing.Customers
  alias Tuist.Marketing.Customers.CaseStudy

  describe "get_case_study/2" do
    test "returns localized content when a translation exists" do
      case_study = Customers.get_case_study("/customers/hyperconnect", "ko")

      assert case_study.title == "Hyperconnect가 Tuist로 멀티 서비스 파이프라인을 최적화한 방법"
      assert case_study.excerpt =~ "피드백 루프를 크게 개선"
      assert case_study.body =~ "복수의 서비스 타깃을 동시에 운영"
    end

    test "falls back to English when the requested locale is unavailable" do
      case_study = Customers.get_case_study("/customers/trendyol", "ko")

      assert case_study.title == "Trendyol reduced build times by 65%"
      assert case_study.excerpt =~ "Trendyol reduced build times by 65%"
    end

    test "rejects a result without a before figure" do
      attrs = %{
        "title" => "Example",
        "date" => "2026-01-01",
        "company" => "Example",
        "url" => "https://example.com",
        "founded_date" => "2020",
        "excerpt" => "Example",
        "results" => [%{"metric" => "CI time", "after" => "10 min"}]
      }

      assert_raise ArgumentError, ~r/without metric, before, and after/, fn ->
        CaseStudy.build("example.md", attrs, "")
      end
    end

    test "returns external case studies with their source article URL" do
      case_study = Customers.get_case_study("/customers/delivery-hero")

      assert case_study.title == "Scaling iOS application development with Tuist"

      assert Customers.case_study_href(case_study) ==
               "https://deliveryhero.jobs/blog/scaling-ios-application-development-with-tuist/"

      assert Customers.external_case_study?(case_study)
    end
  end
end
