defmodule Atlas.GTM.Outreach.Topics do
  @moduledoc false

  @curated_queries [
    %{
      name: "iOS CI engineering blogs",
      source: "brave",
      query: ~s("iOS" "CI" "engineering blog" "Xcode"),
      result_limit: 5,
      metadata: %{
        "topic" => "iOS at scale",
        "topic_source" => "curated",
        "signals" => ["iOS", "CI", "engineering blog", "Xcode"]
      }
    },
    %{
      name: "Swift monorepos",
      source: "brave",
      query: ~s("Swift" "monorepo" "iOS" "build"),
      result_limit: 5,
      metadata: %{
        "topic" => "Swift at scale",
        "topic_source" => "curated",
        "signals" => ["Swift", "monorepo", "iOS", "build"]
      }
    },
    %{
      name: "Xcode build performance",
      source: "brave",
      query: ~s("Xcode" "build times" "iOS" "developer productivity"),
      result_limit: 5,
      metadata: %{
        "topic" => "Xcode build performance",
        "topic_source" => "curated",
        "signals" => ["Xcode", "build times", "iOS", "developer productivity"]
      }
    },
    %{
      name: "Mobile platform hiring",
      source: "brave",
      query: ~s("mobile platform" "iOS" "developer productivity" "hiring"),
      result_limit: 5,
      metadata: %{
        "topic" => "Mobile platform engineering",
        "topic_source" => "curated",
        "signals" => ["mobile platform", "iOS", "developer productivity", "hiring"]
      }
    },
    %{
      name: "Tuist developer posts",
      source: "brave",
      query: ~s("Tuist" "iOS" "Swift" "developer"),
      result_limit: 5,
      metadata: %{
        "topic" => "Tuist mentions",
        "topic_source" => "curated",
        "signals" => ["Tuist", "iOS", "Swift", "developer"]
      }
    },
    %{
      name: "Tuist engineering blogs",
      source: "brave",
      query: ~s("Tuist" "engineering blog" "Xcode"),
      result_limit: 5,
      metadata: %{
        "topic" => "Tuist adopters",
        "topic_source" => "curated",
        "signals" => ["Tuist", "engineering blog", "Xcode"]
      }
    },
    %{
      name: "Tuist project files",
      source: "github",
      query: "Tuist filename:Project.swift",
      result_limit: 5,
      metadata: %{
        "topic" => "Tuist public projects",
        "topic_source" => "curated",
        "signals" => ["Project.swift", "Tuist"]
      }
    },
    %{
      name: "Tuist workspace configs",
      source: "github",
      query: "filename:Tuist.swift",
      result_limit: 5,
      metadata: %{
        "topic" => "Tuist workspace configs",
        "topic_source" => "curated",
        "signals" => ["Tuist.swift", "Tuist"]
      }
    },
    %{
      name: "Swift package manifests",
      source: "github",
      query: "filename:Package.swift iOS",
      result_limit: 5,
      metadata: %{
        "topic" => "Swift package scale",
        "topic_source" => "curated",
        "signals" => ["Package.swift", "SwiftPM", "iOS"]
      }
    },
    %{
      name: "Fastlane iOS pipelines",
      source: "github",
      query: ~s(filename:Fastfile "gym" "scan"),
      result_limit: 5,
      metadata: %{
        "topic" => "iOS CI automation",
        "topic_source" => "curated",
        "signals" => ["Fastfile", "gym", "scan"]
      }
    },
    %{
      name: "XcodeGen project specs",
      source: "github",
      query: ~s(filename:project.yml "xcodegen"),
      result_limit: 5,
      metadata: %{
        "topic" => "iOS project generation",
        "topic_source" => "curated",
        "signals" => ["XcodeGen", "project.yml"]
      }
    }
  ]

  def signal_queries(_opts \\ []), do: @curated_queries

  def curated_queries, do: @curated_queries
end
