defmodule Tuist.Marketing.CustomersTest do
  use ExUnit.Case, async: true

  alias Tuist.Marketing.Customers

  describe "get_case_study/2" do
    test "returns localized content when a translation exists" do
      case_study = Customers.get_case_study("/customers/hyperconnect", "ko")

      assert case_study.title == "Hyperconnect가 Tuist로 멀티 서비스 파이프라인을 최적화한 방법"
      assert case_study.excerpt =~ "피드백 루프를 크게 개선"
      assert case_study.body =~ "멀티 서비스 운영 모델의 고도화"
    end

    test "falls back to English when the requested locale is unavailable" do
      case_study = Customers.get_case_study("/customers/trendyol", "ko")

      assert case_study.title == "Trendyol reduced build times by 65%"
      assert case_study.excerpt =~ "Trendyol reduced build times by 65%"
    end
  end
end
