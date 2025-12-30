defmodule TuistTestSupport.Fixtures.CommandEventsFixtures do
  @moduledoc """
  Fixtures for command events.
  """

  import TuistTestSupport.Utilities, only: [with_flushed_ingestion_buffers: 1]

  alias Tuist.CommandEvents
  alias Tuist.Time
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def command_event_fixture(attrs \\ []) do
    project_id =
      Keyword.get_lazy(attrs, :project_id, fn ->
        ProjectsFixtures.project_fixture().id
      end)

    created_at = Keyword.get_lazy(attrs, :created_at, fn -> Time.utc_now() end)

    ran_at =
      Keyword.get_lazy(attrs, :ran_at, fn ->
        default_ran_at(created_at)
      end)

    with_flushed_ingestion_buffers(fn ->
      CommandEvents.create_command_event(
        %{
          name: Keyword.get(attrs, :name, "generate"),
          subcommand: Keyword.get(attrs, :subcommand, ""),
          command_arguments: Keyword.get(attrs, :command_arguments, []),
          duration: Keyword.get(attrs, :duration, 0),
          tuist_version: "4.1.0",
          swift_version: "5.2",
          macos_version: "10.15",
          project_id: project_id,
          cacheable_targets: Keyword.get(attrs, :cacheable_targets, []),
          local_cache_target_hits: Keyword.get(attrs, :local_cache_target_hits, []),
          remote_cache_target_hits: Keyword.get(attrs, :remote_cache_target_hits, []),
          test_targets: Keyword.get(attrs, :test_targets, []),
          local_test_target_hits: Keyword.get(attrs, :local_test_target_hits, []),
          remote_test_target_hits: Keyword.get(attrs, :remote_test_target_hits, []),
          is_ci: Keyword.get(attrs, :is_ci, false),
          client_id: "client-id",
          user_id: Keyword.get(attrs, :user_id, 1),
          status: Keyword.get(attrs, :status, :success),
          error_message: Keyword.get(attrs, :error_message),
          preview_id: Keyword.get(attrs, :preview_id),
          git_commit_sha: Keyword.get(attrs, :git_commit_sha),
          git_ref: Keyword.get(attrs, :git_ref),
          git_branch: Keyword.get(attrs, :git_branch),
          created_at: created_at,
          ran_at: ran_at,
          build_run_id: Keyword.get(attrs, :build_run_id),
          test_run_id: Keyword.get(attrs, :test_run_id)
        },
        preload: Keyword.get(attrs, :preload, [])
      )
    end)
  end

  def invocation_record_fixture do
    ~S"""
    {
      "_type" : {
        "_name" : "ActionsInvocationRecord"
      },
      "actions" : {
        "_type" : {
          "_name" : "Array"
        },
        "_values" : [
          {
            "_type" : {
              "_name" : "ActionRecord"
            },
            "actionResult" : {
              "_type" : {
                "_name" : "ActionResult"
              },
              "coverage" : {
                "_type" : {
                  "_name" : "CodeCoverageInfo"
                }
              },
              "diagnosticsRef" : {
                "_type" : {
                  "_name" : "Reference"
                },
                "id" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "0~qGOLXEY4oa_cQdjyOFs8KD6Srsit1LXbaAelq0PZmwtH4UqwhvYSjut0OOO60p6Irw5OqbhjUVOq9p0n7nu9SQ=="
                }
              },
              "issues" : {
                "_type" : {
                  "_name" : "ResultIssueSummaries"
                },
                "testFailureSummaries" : {
                  "_type" : {
                    "_name" : "Array"
                  },
                  "_values" : [
                    {
                      "_type" : {
                        "_name" : "TestFailureIssueSummary",
                        "_supertype" : {
                          "_name" : "IssueSummary"
                        }
                      },
                      "documentLocationInCreatingWorkspace" : {
                        "_type" : {
                          "_name" : "DocumentLocation"
                        },
                        "concreteTypeName" : {
                          "_type" : {
                            "_name" : "String"
                          },
                          "_value" : "DVTTextDocumentLocation"
                        },
                        "url" : {
                          "_type" : {
                            "_name" : "String"
                          },
                          "_value" : "file:\/\/\/Users\/marekfort\/Developer\/tuist\/fixtures\/ios_app_with_frameworks\/Framework2\/Tests\/Framework2FileTests.swift#EndingLineNumber=7&StartingLineNumber=7"
                        }
                      },
                      "issueType" : {
                        "_type" : {
                          "_name" : "String"
                        },
                        "_value" : "Uncategorized"
                      },
                      "message" : {
                        "_type" : {
                          "_name" : "String"
                        },
                        "_value" : "XCTAssertEqual failed: (\"Framework2File.hello() no\") is not equal to (\"Framework2File.hello()\")"
                      },
                      "testCaseName" : {
                        "_type" : {
                          "_name" : "String"
                        },
                        "_value" : "Framework2Tests.testHello()"
                      }
                    }
                  ]
                }
              },
              "logRef" : {
                "_type" : {
                  "_name" : "Reference"
                },
                "id" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "0~fSAOzL3muyccMx1j_Xoh6JKgiZT7uQDXKj00ZV05qYPNUzZt0OY2X4ZN9ebzKyiQULj6nUhu02LfIuAm6Zi95w=="
                },
                "targetType" : {
                  "_type" : {
                    "_name" : "TypeDefinition"
                  },
                  "name" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "ActivityLogSection"
                  }
                }
              },
              "metrics" : {
                "_type" : {
                  "_name" : "ResultMetrics"
                },
                "testsCount" : {
                  "_type" : {
                    "_name" : "Int"
                  },
                  "_value" : "5"
                },
                "testsFailedCount" : {
                  "_type" : {
                    "_name" : "Int"
                  },
                  "_value" : "1"
                }
              },
              "resultName" : {
                "_type" : {
                  "_name" : "String"
                },
                "_value" : "action"
              },
              "status" : {
                "_type" : {
                  "_name" : "String"
                },
                "_value" : "failed"
              },
              "testsRef" : {
                "_type" : {
                  "_name" : "Reference"
                },
                "id" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "0~_nJcMfmYtL75ZA_SPkjI1RYzgbEkjbq_o2hffLy4RQuPOW81Uu0xIwZX0ntR4Tof5xv2Jwe8opnwD7IVBQ_VOQ=="
                },
                "targetType" : {
                  "_type" : {
                    "_name" : "TypeDefinition"
                  },
                  "name" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "ActionTestPlanRunSummaries"
                  }
                }
              }
            },
            "buildResult" : {
              "_type" : {
                "_name" : "ActionResult"
              },
              "coverage" : {
                "_type" : {
                  "_name" : "CodeCoverageInfo"
                }
              },
              "issues" : {
                "_type" : {
                  "_name" : "ResultIssueSummaries"
                }
              },
              "logRef" : {
                "_type" : {
                  "_name" : "Reference"
                },
                "id" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "0~kwc_xSbP6MnD1JJrGl_8M133NGVKkFDV0IXb15bNCpOT2NKTvKhM0hvkFNZFY4qn0_l7jBj9a6Qd4bFaDGP0Tw=="
                },
                "targetType" : {
                  "_type" : {
                    "_name" : "TypeDefinition"
                  },
                  "name" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "ActivityLogSection"
                  }
                }
              },
              "metrics" : {
                "_type" : {
                  "_name" : "ResultMetrics"
                }
              },
              "resultName" : {
                "_type" : {
                  "_name" : "String"
                },
                "_value" : "build"
              },
              "status" : {
                "_type" : {
                  "_name" : "String"
                },
                "_value" : "succeeded"
              }
            },
            "endedTime" : {
              "_type" : {
                "_name" : "Date"
              },
              "_value" : "2024-06-01T20:07:05.109+0200"
            },
            "runDestination" : {
              "_type" : {
                "_name" : "ActionRunDestinationRecord"
              },
              "displayName" : {
                "_type" : {
                  "_name" : "String"
                },
                "_value" : "iPad Pro (12.9-inch) (6th generation)"
              },
              "localComputerRecord" : {
                "_type" : {
                  "_name" : "ActionDeviceRecord"
                },
                "busSpeedInMHz" : {
                  "_type" : {
                    "_name" : "Int"
                  },
                  "_value" : "0"
                },
                "cpuCount" : {
                  "_type" : {
                    "_name" : "Int"
                  },
                  "_value" : "1"
                },
                "cpuKind" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "Apple M3 Pro"
                },
                "cpuSpeedInMHz" : {
                  "_type" : {
                    "_name" : "Int"
                  },
                  "_value" : "0"
                },
                "identifier" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "00006030-0002315A0A28001C"
                },
                "isConcreteDevice" : {
                  "_type" : {
                    "_name" : "Bool"
                  },
                  "_value" : "true"
                },
                "logicalCPUCoresPerPackage" : {
                  "_type" : {
                    "_name" : "Int"
                  },
                  "_value" : "11"
                },
                "modelCode" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "Mac15,6"
                },
                "modelName" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "MacBook Pro"
                },
                "modelUTI" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "com.apple.macbookpro-14-late-2023-2"
                },
                "name" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "My Mac"
                },
                "nativeArchitecture" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "arm64e"
                },
                "operatingSystemVersion" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "14.1"
                },
                "operatingSystemVersionWithBuildNumber" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "14.1 (23B2073)"
                },
                "physicalCPUCoresPerPackage" : {
                  "_type" : {
                    "_name" : "Int"
                  },
                  "_value" : "11"
                },
                "platformRecord" : {
                  "_type" : {
                    "_name" : "ActionPlatformRecord"
                  },
                  "identifier" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "com.apple.platform.macosx"
                  },
                  "userDescription" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "macOS"
                  }
                },
                "ramSizeInMegabytes" : {
                  "_type" : {
                    "_name" : "Int"
                  },
                  "_value" : "36864"
                }
              },
              "targetArchitecture" : {
                "_type" : {
                  "_name" : "String"
                },
                "_value" : "arm64"
              },
              "targetDeviceRecord" : {
                "_type" : {
                  "_name" : "ActionDeviceRecord"
                },
                "busSpeedInMHz" : {
                  "_type" : {
                    "_name" : "Int"
                  },
                  "_value" : "0"
                },
                "cpuCount" : {
                  "_type" : {
                    "_name" : "Int"
                  },
                  "_value" : "0"
                },
                "cpuSpeedInMHz" : {
                  "_type" : {
                    "_name" : "Int"
                  },
                  "_value" : "0"
                },
                "identifier" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "6DAFB815-7E1C-4CED-B316-83D9B49E552E"
                },
                "isConcreteDevice" : {
                  "_type" : {
                    "_name" : "Bool"
                  },
                  "_value" : "true"
                },
                "logicalCPUCoresPerPackage" : {
                  "_type" : {
                    "_name" : "Int"
                  },
                  "_value" : "0"
                },
                "modelCode" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "iPad14,5"
                },
                "modelName" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "iPad Pro (12.9-inch) (6th generation)"
                },
                "modelUTI" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "com.apple.ipad-pro-12point9-6th-1"
                },
                "name" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "iPad Pro (12.9-inch) (6th generation)"
                },
                "nativeArchitecture" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "arm64"
                },
                "operatingSystemVersion" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "17.4"
                },
                "operatingSystemVersionWithBuildNumber" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "17.4 (21E213)"
                },
                "physicalCPUCoresPerPackage" : {
                  "_type" : {
                    "_name" : "Int"
                  },
                  "_value" : "0"
                },
                "platformRecord" : {
                  "_type" : {
                    "_name" : "ActionPlatformRecord"
                  },
                  "identifier" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "com.apple.platform.iphonesimulator"
                  },
                  "userDescription" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "iOS Simulator"
                  }
                },
                "ramSizeInMegabytes" : {
                  "_type" : {
                    "_name" : "Int"
                  },
                  "_value" : "0"
                }
              },
              "targetSDKRecord" : {
                "_type" : {
                  "_name" : "ActionSDKRecord"
                },
                "identifier" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "iphonesimulator17.4"
                },
                "name" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "Simulator - iOS 17.4"
                },
                "operatingSystemVersion" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "17.4"
                }
              }
            },
            "schemeCommandName" : {
              "_type" : {
                "_name" : "String"
              },
              "_value" : "Test"
            },
            "schemeTaskName" : {
              "_type" : {
                "_name" : "String"
              },
              "_value" : "BuildAndAction"
            },
            "startedTime" : {
              "_type" : {
                "_name" : "Date"
              },
              "_value" : "2024-06-01T20:06:44.973+0200"
            },
            "testPlanName" : {
              "_type" : {
                "_name" : "String"
              },
              "_value" : "Workspace-Workspace"
            },
            "title" : {
              "_type" : {
                "_name" : "String"
              },
              "_value" : "Testing workspace Workspace with scheme Workspace-Workspace"
            }
          }
        ]
      },
      "issues" : {
        "_type" : {
          "_name" : "ResultIssueSummaries"
        },
        "testFailureSummaries" : {
          "_type" : {
            "_name" : "Array"
          },
          "_values" : [
            {
              "_type" : {
                "_name" : "TestFailureIssueSummary",
                "_supertype" : {
                  "_name" : "IssueSummary"
                }
              },
              "documentLocationInCreatingWorkspace" : {
                "_type" : {
                  "_name" : "DocumentLocation"
                },
                "concreteTypeName" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "DVTTextDocumentLocation"
                },
                "url" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "file:\/\/\/Users\/marekfort\/Developer\/tuist\/fixtures\/ios_app_with_frameworks\/Framework2\/Tests\/Framework2FileTests.swift#EndingLineNumber=7&StartingLineNumber=7"
                }
              },
              "issueType" : {
                "_type" : {
                  "_name" : "String"
                },
                "_value" : "Uncategorized"
              },
              "message" : {
                "_type" : {
                  "_name" : "String"
                },
                "_value" : "XCTAssertEqual failed: (\"Framework2File.hello() no\") is not equal to (\"Framework2File.hello()\")"
              },
              "testCaseName" : {
                "_type" : {
                  "_name" : "String"
                },
                "_value" : "Framework2Tests.testHello()"
              }
            }
          ]
        }
      },
      "metadataRef" : {
        "_type" : {
          "_name" : "Reference"
        },
        "id" : {
          "_type" : {
            "_name" : "String"
          },
          "_value" : "0~HZ7s_NPU1MwA1A8LgGSJSp1_6mS8Q6RUREImgW41FR6jbBjdT34nSR1Nws_CU89RSOYfkuLbAD7w4pm_ufIu1w=="
        },
        "targetType" : {
          "_type" : {
            "_name" : "TypeDefinition"
          },
          "name" : {
            "_type" : {
              "_name" : "String"
            },
            "_value" : "ActionsInvocationMetadata"
          }
        }
      },
      "metrics" : {
        "_type" : {
          "_name" : "ResultMetrics"
        },
        "testsCount" : {
          "_type" : {
            "_name" : "Int"
          },
          "_value" : "5"
        },
        "testsFailedCount" : {
          "_type" : {
            "_name" : "Int"
          },
          "_value" : "1"
        }
      }
    }
    """
  end

  def test_plan_object_fixture do
    ~S"""
    {
      "_type" : {
        "_name" : "ActionTestPlanRunSummaries"
      },
      "summaries" : {
        "_type" : {
          "_name" : "Array"
        },
        "_values" : [
          {
            "_type" : {
              "_name" : "ActionTestPlanRunSummary",
              "_supertype" : {
                "_name" : "ActionAbstractTestSummary"
              }
            },
            "name" : {
              "_type" : {
                "_name" : "String"
              },
              "_value" : "Test Scheme Action"
            },
            "testableSummaries" : {
              "_type" : {
                "_name" : "Array"
              },
              "_values" : [
                {
                  "_type" : {
                    "_name" : "ActionTestableSummary",
                    "_supertype" : {
                      "_name" : "ActionAbstractTestSummary"
                    }
                  },
                  "diagnosticsDirectoryName" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "AppTests-8D23C1BA-5CD9-4CF4-A983-B3C364DE70E4-Configuration-Test Scheme Action-Iteration-1"
                  },
                  "identifierURL" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "test:\/\/com.apple.xcode\/MainApp\/AppTests"
                  },
                  "name" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "AppTests"
                  },
                  "projectRelativePath" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "App\/MainApp.xcodeproj"
                  },
                  "targetName" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "AppTests"
                  },
                  "testKind" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "app hosted"
                  },
                  "testLanguage" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : ""
                  },
                  "testRegion" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : ""
                  },
                  "tests" : {
                    "_type" : {
                      "_name" : "Array"
                    },
                    "_values" : [
                      {
                        "_type" : {
                          "_name" : "ActionTestSummaryGroup",
                          "_supertype" : {
                            "_name" : "ActionTestSummaryIdentifiableObject",
                            "_supertype" : {
                              "_name" : "ActionAbstractTestSummary"
                            }
                          }
                        },
                        "duration" : {
                          "_type" : {
                            "_name" : "Double"
                          },
                          "_value" : "0.0049179792404174805"
                        },
                        "identifier" : {
                          "_type" : {
                            "_name" : "String"
                          },
                          "_value" : "All tests"
                        },
                        "identifierURL" : {
                          "_type" : {
                            "_name" : "String"
                          },
                          "_value" : "test:\/\/com.apple.xcode\/MainApp\/AppTests\/All%20tests"
                        },
                        "name" : {
                          "_type" : {
                            "_name" : "String"
                          },
                          "_value" : "All tests"
                        },
                        "subtests" : {
                          "_type" : {
                            "_name" : "Array"
                          },
                          "_values" : [
                            {
                              "_type" : {
                                "_name" : "ActionTestSummaryGroup",
                                "_supertype" : {
                                  "_name" : "ActionTestSummaryIdentifiableObject",
                                  "_supertype" : {
                                    "_name" : "ActionAbstractTestSummary"
                                  }
                                }
                              },
                              "duration" : {
                                "_type" : {
                                  "_name" : "Double"
                                },
                                "_value" : "0.004400968551635742"
                              },
                              "identifier" : {
                                "_type" : {
                                  "_name" : "String"
                                },
                                "_value" : "AppTests.xctest"
                              },
                              "identifierURL" : {
                                "_type" : {
                                  "_name" : "String"
                                },
                                "_value" : "test:\/\/com.apple.xcode\/MainApp\/AppTests\/AppTests.xctest"
                              },
                              "name" : {
                                "_type" : {
                                  "_name" : "String"
                                },
                                "_value" : "AppTests.xctest"
                              },
                              "subtests" : {
                                "_type" : {
                                  "_name" : "Array"
                                },
                                "_values" : [
                                  {
                                    "_type" : {
                                      "_name" : "ActionTestSummaryGroup",
                                      "_supertype" : {
                                        "_name" : "ActionTestSummaryIdentifiableObject",
                                        "_supertype" : {
                                          "_name" : "ActionAbstractTestSummary"
                                        }
                                      }
                                    },
                                    "duration" : {
                                      "_type" : {
                                        "_name" : "Double"
                                      },
                                      "_value" : "0.004132986068725586"
                                    },
                                    "identifier" : {
                                      "_type" : {
                                        "_name" : "String"
                                      },
                                      "_value" : "AppDelegateTests"
                                    },
                                    "identifierURL" : {
                                      "_type" : {
                                        "_name" : "String"
                                      },
                                      "_value" : "test:\/\/com.apple.xcode\/MainApp\/AppTests\/AppDelegateTests"
                                    },
                                    "name" : {
                                      "_type" : {
                                        "_name" : "String"
                                      },
                                      "_value" : "AppDelegateTests"
                                    },
                                    "subtests" : {
                                      "_type" : {
                                        "_name" : "Array"
                                      },
                                      "_values" : [
                                        {
                                          "_type" : {
                                            "_name" : "ActionTestMetadata",
                                            "_supertype" : {
                                              "_name" : "ActionTestSummaryIdentifiableObject",
                                              "_supertype" : {
                                                "_name" : "ActionAbstractTestSummary"
                                              }
                                            }
                                          },
                                          "duration" : {
                                            "_type" : {
                                              "_name" : "Double"
                                            },
                                            "_value" : "0.003908991813659668"
                                          },
                                          "identifier" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "AppDelegateTests\/testHello()"
                                          },
                                          "identifierURL" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "test:\/\/com.apple.xcode\/MainApp\/AppTests\/AppDelegateTests\/testHello"
                                          },
                                          "name" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "testHello()"
                                          },
                                          "testStatus" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "Success"
                                          }
                                        }
                                      ]
                                    }
                                  }
                                ]
                              }
                            }
                          ]
                        }
                      }
                    ]
                  }
                },
                {
                  "_type" : {
                    "_name" : "ActionTestableSummary",
                    "_supertype" : {
                      "_name" : "ActionAbstractTestSummary"
                    }
                  },
                  "diagnosticsDirectoryName" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "Framework1Tests-4D92428E-A378-40B8-A64D-5C016A6EBF07-Configuration-Test Scheme Action-Iteration-1"
                  },
                  "identifierURL" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "test:\/\/com.apple.xcode\/Framework1\/Framework1Tests"
                  },
                  "name" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "Framework1Tests"
                  },
                  "projectRelativePath" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "Framework1\/Framework1.xcodeproj"
                  },
                  "targetName" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "Framework1Tests"
                  },
                  "testKind" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "xctest-tool hosted"
                  },
                  "testLanguage" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : ""
                  },
                  "testRegion" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : ""
                  },
                  "tests" : {
                    "_type" : {
                      "_name" : "Array"
                    },
                    "_values" : [
                      {
                        "_type" : {
                          "_name" : "ActionTestSummaryGroup",
                          "_supertype" : {
                            "_name" : "ActionTestSummaryIdentifiableObject",
                            "_supertype" : {
                              "_name" : "ActionAbstractTestSummary"
                            }
                          }
                        },
                        "duration" : {
                          "_type" : {
                            "_name" : "Double"
                          },
                          "_value" : "0.0020619630813598633"
                        },
                        "identifier" : {
                          "_type" : {
                            "_name" : "String"
                          },
                          "_value" : "All tests"
                        },
                        "identifierURL" : {
                          "_type" : {
                            "_name" : "String"
                          },
                          "_value" : "test:\/\/com.apple.xcode\/Framework1\/Framework1Tests\/All%20tests"
                        },
                        "name" : {
                          "_type" : {
                            "_name" : "String"
                          },
                          "_value" : "All tests"
                        },
                        "subtests" : {
                          "_type" : {
                            "_name" : "Array"
                          },
                          "_values" : [
                            {
                              "_type" : {
                                "_name" : "ActionTestSummaryGroup",
                                "_supertype" : {
                                  "_name" : "ActionTestSummaryIdentifiableObject",
                                  "_supertype" : {
                                    "_name" : "ActionAbstractTestSummary"
                                  }
                                }
                              },
                              "duration" : {
                                "_type" : {
                                  "_name" : "Double"
                                },
                                "_value" : "0.0015490055084228516"
                              },
                              "identifier" : {
                                "_type" : {
                                  "_name" : "String"
                                },
                                "_value" : "Framework1Tests.xctest"
                              },
                              "identifierURL" : {
                                "_type" : {
                                  "_name" : "String"
                                },
                                "_value" : "test:\/\/com.apple.xcode\/Framework1\/Framework1Tests\/Framework1Tests.xctest"
                              },
                              "name" : {
                                "_type" : {
                                  "_name" : "String"
                                },
                                "_value" : "Framework1Tests.xctest"
                              },
                              "subtests" : {
                                "_type" : {
                                  "_name" : "Array"
                                },
                                "_values" : [
                                  {
                                    "_type" : {
                                      "_name" : "ActionTestSummaryGroup",
                                      "_supertype" : {
                                        "_name" : "ActionTestSummaryIdentifiableObject",
                                        "_supertype" : {
                                          "_name" : "ActionAbstractTestSummary"
                                        }
                                      }
                                    },
                                    "duration" : {
                                      "_type" : {
                                        "_name" : "Double"
                                      },
                                      "_value" : "0.0012860298156738281"
                                    },
                                    "identifier" : {
                                      "_type" : {
                                        "_name" : "String"
                                      },
                                      "_value" : "Framework1Tests"
                                    },
                                    "identifierURL" : {
                                      "_type" : {
                                        "_name" : "String"
                                      },
                                      "_value" : "test:\/\/com.apple.xcode\/Framework1\/Framework1Tests\/Framework1Tests"
                                    },
                                    "name" : {
                                      "_type" : {
                                        "_name" : "String"
                                      },
                                      "_value" : "Framework1Tests"
                                    },
                                    "subtests" : {
                                      "_type" : {
                                        "_name" : "Array"
                                      },
                                      "_values" : [
                                        {
                                          "_type" : {
                                            "_name" : "ActionTestMetadata",
                                            "_supertype" : {
                                              "_name" : "ActionTestSummaryIdentifiableObject",
                                              "_supertype" : {
                                                "_name" : "ActionAbstractTestSummary"
                                              }
                                            }
                                          },
                                          "duration" : {
                                            "_type" : {
                                              "_name" : "Double"
                                            },
                                            "_value" : "0.0007480382919311523"
                                          },
                                          "identifier" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "Framework1Tests\/testHello()"
                                          },
                                          "identifierURL" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "test:\/\/com.apple.xcode\/Framework1\/Framework1Tests\/Framework1Tests\/testHello"
                                          },
                                          "name" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "testHello()"
                                          },
                                          "testStatus" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "Success"
                                          }
                                        },
                                        {
                                          "_type" : {
                                            "_name" : "ActionTestMetadata",
                                            "_supertype" : {
                                              "_name" : "ActionTestSummaryIdentifiableObject",
                                              "_supertype" : {
                                                "_name" : "ActionAbstractTestSummary"
                                              }
                                            }
                                          },
                                          "duration" : {
                                            "_type" : {
                                              "_name" : "Double"
                                            },
                                            "_value" : "0.0002499818801879883"
                                          },
                                          "identifier" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "Framework1Tests\/testHelloFromFramework2()"
                                          },
                                          "identifierURL" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "test:\/\/com.apple.xcode\/Framework1\/Framework1Tests\/Framework1Tests\/testHelloFromFramework2"
                                          },
                                          "name" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "testHelloFromFramework2()"
                                          },
                                          "testStatus" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "Success"
                                          }
                                        }
                                      ]
                                    }
                                  }
                                ]
                              }
                            }
                          ]
                        }
                      }
                    ]
                  }
                },
                {
                  "_type" : {
                    "_name" : "ActionTestableSummary",
                    "_supertype" : {
                      "_name" : "ActionAbstractTestSummary"
                    }
                  },
                  "diagnosticsDirectoryName" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "Framework2Tests-BC059841-B8DB-469E-8035-4D07530E525B-Configuration-Test Scheme Action-Iteration-1"
                  },
                  "identifierURL" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "test:\/\/com.apple.xcode\/Framework2\/Framework2Tests"
                  },
                  "name" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "Framework2Tests"
                  },
                  "projectRelativePath" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "Framework2\/Framework2.xcodeproj"
                  },
                  "targetName" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "Framework2Tests"
                  },
                  "testKind" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "xctest-tool hosted"
                  },
                  "testLanguage" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : ""
                  },
                  "testRegion" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : ""
                  },
                  "tests" : {
                    "_type" : {
                      "_name" : "Array"
                    },
                    "_values" : [
                      {
                        "_type" : {
                          "_name" : "ActionTestSummaryGroup",
                          "_supertype" : {
                            "_name" : "ActionTestSummaryIdentifiableObject",
                            "_supertype" : {
                              "_name" : "ActionAbstractTestSummary"
                            }
                          }
                        },
                        "duration" : {
                          "_type" : {
                            "_name" : "Double"
                          },
                          "_value" : "0.04535102844238281"
                        },
                        "identifier" : {
                          "_type" : {
                            "_name" : "String"
                          },
                          "_value" : "All tests"
                        },
                        "identifierURL" : {
                          "_type" : {
                            "_name" : "String"
                          },
                          "_value" : "test:\/\/com.apple.xcode\/Framework2\/Framework2Tests\/All%20tests"
                        },
                        "name" : {
                          "_type" : {
                            "_name" : "String"
                          },
                          "_value" : "All tests"
                        },
                        "subtests" : {
                          "_type" : {
                            "_name" : "Array"
                          },
                          "_values" : [
                            {
                              "_type" : {
                                "_name" : "ActionTestSummaryGroup",
                                "_supertype" : {
                                  "_name" : "ActionTestSummaryIdentifiableObject",
                                  "_supertype" : {
                                    "_name" : "ActionAbstractTestSummary"
                                  }
                                }
                              },
                              "duration" : {
                                "_type" : {
                                  "_name" : "Double"
                                },
                                "_value" : "0.04487204551696777"
                              },
                              "identifier" : {
                                "_type" : {
                                  "_name" : "String"
                                },
                                "_value" : "Framework2Tests.xctest"
                              },
                              "identifierURL" : {
                                "_type" : {
                                  "_name" : "String"
                                },
                                "_value" : "test:\/\/com.apple.xcode\/Framework2\/Framework2Tests\/Framework2Tests.xctest"
                              },
                              "name" : {
                                "_type" : {
                                  "_name" : "String"
                                },
                                "_value" : "Framework2Tests.xctest"
                              },
                              "subtests" : {
                                "_type" : {
                                  "_name" : "Array"
                                },
                                "_values" : [
                                  {
                                    "_type" : {
                                      "_name" : "ActionTestSummaryGroup",
                                      "_supertype" : {
                                        "_name" : "ActionTestSummaryIdentifiableObject",
                                        "_supertype" : {
                                          "_name" : "ActionAbstractTestSummary"
                                        }
                                      }
                                    },
                                    "duration" : {
                                      "_type" : {
                                        "_name" : "Double"
                                      },
                                      "_value" : "0.044090986251831055"
                                    },
                                    "identifier" : {
                                      "_type" : {
                                        "_name" : "String"
                                      },
                                      "_value" : "Framework2Tests"
                                    },
                                    "identifierURL" : {
                                      "_type" : {
                                        "_name" : "String"
                                      },
                                      "_value" : "test:\/\/com.apple.xcode\/Framework2\/Framework2Tests\/Framework2Tests"
                                    },
                                    "name" : {
                                      "_type" : {
                                        "_name" : "String"
                                      },
                                      "_value" : "Framework2Tests"
                                    },
                                    "subtests" : {
                                      "_type" : {
                                        "_name" : "Array"
                                      },
                                      "_values" : [
                                        {
                                          "_type" : {
                                            "_name" : "ActionTestMetadata",
                                            "_supertype" : {
                                              "_name" : "ActionTestSummaryIdentifiableObject",
                                              "_supertype" : {
                                                "_name" : "ActionAbstractTestSummary"
                                              }
                                            }
                                          },
                                          "duration" : {
                                            "_type" : {
                                              "_name" : "Double"
                                            },
                                            "_value" : "0.043884992599487305"
                                          },
                                          "identifier" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "Framework2Tests\/testHello()"
                                          },
                                          "identifierURL" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "test:\/\/com.apple.xcode\/Framework2\/Framework2Tests\/Framework2Tests\/testHello"
                                          },
                                          "name" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "testHello()"
                                          },
                                          "summaryRef" : {
                                            "_type" : {
                                              "_name" : "Reference"
                                            },
                                            "id" : {
                                              "_type" : {
                                                "_name" : "String"
                                              },
                                              "_value" : "0~ZoBVUs_b49tCzL1WLyiIrDZiTyQGUoY2NuxMWNElkg7KHtcLN9SQJKFXQoVsffR3WyfAqsoxep1U3gNiQLLOsA=="
                                            },
                                            "targetType" : {
                                              "_type" : {
                                                "_name" : "TypeDefinition"
                                              },
                                              "name" : {
                                                "_type" : {
                                                  "_name" : "String"
                                                },
                                                "_value" : "ActionTestSummary"
                                              },
                                              "supertype" : {
                                                "_type" : {
                                                  "_name" : "TypeDefinition"
                                                },
                                                "name" : {
                                                  "_type" : {
                                                    "_name" : "String"
                                                  },
                                                  "_value" : "ActionTestSummaryIdentifiableObject"
                                                },
                                                "supertype" : {
                                                  "_type" : {
                                                    "_name" : "TypeDefinition"
                                                  },
                                                  "name" : {
                                                    "_type" : {
                                                      "_name" : "String"
                                                    },
                                                    "_value" : "ActionAbstractTestSummary"
                                                  }
                                                }
                                              }
                                            }
                                          },
                                          "testStatus" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "Failure"
                                          }
                                        }
                                      ]
                                    }
                                  },
                                  {
                                    "_type" : {
                                      "_name" : "ActionTestSummaryGroup",
                                      "_supertype" : {
                                        "_name" : "ActionTestSummaryIdentifiableObject",
                                        "_supertype" : {
                                          "_name" : "ActionAbstractTestSummary"
                                        }
                                      }
                                    },
                                    "duration" : {
                                      "_type" : {
                                        "_name" : "Double"
                                      },
                                      "_value" : "0.00044095516204833984"
                                    },
                                    "identifier" : {
                                      "_type" : {
                                        "_name" : "String"
                                      },
                                      "_value" : "MyPublicClassTests"
                                    },
                                    "identifierURL" : {
                                      "_type" : {
                                        "_name" : "String"
                                      },
                                      "_value" : "test:\/\/com.apple.xcode\/Framework2\/Framework2Tests\/MyPublicClassTests"
                                    },
                                    "name" : {
                                      "_type" : {
                                        "_name" : "String"
                                      },
                                      "_value" : "MyPublicClassTests"
                                    },
                                    "subtests" : {
                                      "_type" : {
                                        "_name" : "Array"
                                      },
                                      "_values" : [
                                        {
                                          "_type" : {
                                            "_name" : "ActionTestMetadata",
                                            "_supertype" : {
                                              "_name" : "ActionTestSummaryIdentifiableObject",
                                              "_supertype" : {
                                                "_name" : "ActionAbstractTestSummary"
                                              }
                                            }
                                          },
                                          "duration" : {
                                            "_type" : {
                                              "_name" : "Double"
                                            },
                                            "_value" : "0.00027310848236083984"
                                          },
                                          "identifier" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "MyPublicClassTests\/testHello()"
                                          },
                                          "identifierURL" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "test:\/\/com.apple.xcode\/Framework2\/Framework2Tests\/MyPublicClassTests\/testHello"
                                          },
                                          "name" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "testHello()"
                                          },
                                          "testStatus" : {
                                            "_type" : {
                                              "_name" : "String"
                                            },
                                            "_value" : "Success"
                                          }
                                        }
                                      ]
                                    }
                                  }
                                ]
                              }
                            }
                          ]
                        }
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
    """
  end

  defp default_ran_at(%DateTime{} = created_at), do: created_at

  defp default_ran_at(%NaiveDateTime{} = created_at) do
    DateTime.from_naive!(created_at, "Etc/UTC")
  end

  defp default_ran_at(<<_::binary>> = created_at), do: created_at

  defp default_ran_at(_), do: DateTime.utc_now()
end
