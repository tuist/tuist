import Foundation

extension AnalyticsArtifactUploadServiceTests {
    var invocationRecordMockString: String {
        #"""
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
                      "_value" : "0~OswFMxdHsqFpfWmB3LFdBaMZLu-tXkrmvBsNwQ0BKaT9taUvjiIfOuMGRBR-MawOmNo0LnXLkdHQm5N67mVz1w=="
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
                              "_value" : "file:\/\/\/Users\/builder\/clone\/Tests\/TuistDependenciesAcceptanceTests\/DependenciesAcceptanceTests.swift#EndingLineNumber=40&StartingLineNumber=40"
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
                            "_value" : "failed: caught error: \"The 'xcodebuild' command exited with error code 65 and message:\n2024-05-20 12:44:17.788570+0000 xcodebuild[14114:50965] [devicemanager] DeviceManager sending check-in request: F988FF5A-CDAC-42C9-9C3F-BE87134AD171\n2024-05-20 12:44:17.790440+0000 xcodebuild[14114:50965] [devicemanager] DeviceManager check-in (F988FF5A-CDAC-42C9-9C3F-BE87134AD171) completed successfully\n2024-05-20 12:44:17.793515+0000 xcodebuild[14114:50961] [All] MobileDevice.framework version: 1643.100.58\n2024-05-20 12:44:17.798111+0000 xcodebuild[14114:50961] [All] RemotePairing.framework version: 117.100.41\n2024-05-20 12:44:17.798690+0000 xcodebuild[14114:50961] [library] USBMuxListenerCreateFiltered:898 Created 0x600003581f40\n2024-05-20 12:44:17.798774+0000 xcodebuild[14114:50961] [All] Subscribed for device notifications from usbmuxd.\n2024-05-20 12:44:18.054503+0000 xcodebuild[14114:50949] [general] initializing workspace at path \/var\/folders\/w2\/rrf5p87d1bbfyphxc7jdnyvh0000gn\/T\/TemporaryDirectory.AMHRiB\/ios_app_with_spm_dependencies\/App.xcworkspace\n2024-05-20 12:44:18.055591+0000 xcodebuild[14114:50949] [general] setting up workspace \/var\/folders\/w2\/rrf5p87d1bbfyphxc7jdnyvh0000gn\/T\/TemporaryDirectory.AMHRiB\/ios_app_with_spm_dependencies\/App.xcworkspace\n2024-05-20 12:44:18.071588+0000 xcodebuild[14114:50949] [general] using plugin library at \/Applications\/Xcode-15.3.app\/Contents\/SharedFrameworks\/SwiftPM.framework\/SharedSupport\/PluginAPI\n2024-05-20 12:44:18.071680+0000 xcodebuild[14114:50949] [general] synchronizing contents of workspace at path \/var\/folders\/w2\/rrf5p87d1bbfyphxc7jdnyvh0000gn\/T\/TemporaryDirectory.AMHRiB\/ios_app_with_spm_dependencies\/App.xcworkspace\n2024-05-20 12:44:18.071698+0000 xcodebuild[14114:50949] [general] marking workspace as having finished initial package resolution\n--- xcodebuild: WARNING: Using the first of multiple matching destinations:\n{ platform:iOS Simulator, id:2B6F50E6-2782-405A-94DF-E659C9398717, OS:17.4, name:iPad Pro (12.9-inch) (6th generation) }\n{ platform:iOS Simulator, id:2B6F50E6-2782-405A-94DF-E659C9398717, OS:17.4, name:iPad Pro (12.9-inch) (6th generation) }\n2024-05-20 12:44:18.106264+0000 xcodebuild[14114:50949] [building] creating scheme operation preamble operations for build command Build\nTesting failed:\n\tCompiling for iOS 14.0, but module 'App' has a minimum deployment target of iOS 16.0: \/Users\/builder\/Library\/Developer\/Xcode\/DerivedData\/App-fzcodvpjdyxljhcxfidulaohhxre\/Build\/Products\/Debug-iphonesimulator\/App.swiftmodule\/arm64-apple-ios-simulator.swiftmodule\n\tTesting cancelled because the build failed.\n\n** TEST FAILED **\n\n\nThe following build commands failed:\n\tSwiftEmitModule normal arm64 Emitting\\ module\\ for\\ AppTests (in target 'AppTests' from project 'App')\n(1 failure)\n\""
                          },
                          "testCaseName" : {
                            "_type" : {
                              "_name" : "String"
                            },
                            "_value" : "DependenciesAcceptanceTestIosAppWithSPMDependencies.test_ios_app_spm_dependencies()"
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
                      "_value" : "0~P3EqtGf1QBDVW81JX_KQylSrGzn-HJAEOm1bhpBdwiiWhpaRIfCbhxtixsVOOLHp6jGB-YAVUqA1rmIc7dBy4g=="
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
                      "_value" : "3"
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
                      "_value" : "0~8YCjlb3k7BnCmnR4_ZFg18UnVp4hOkZw8KiWEX8RunY_pe9wBaIbW90Jo1HePHl7st5Le_nRyAP4_dSvsdxYpw=="
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
                      "_value" : "0~JlTezqV63xbUrp0gsF4KV89HvbbNAfQ_g5JOvwR1ecy70PjnlqcfDdyHgggMuhSwJYY9MSoVtKYHzmxj3ZaRcw=="
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
                  "_value" : "2024-05-20T12:44:51.162+0000"
                },
                "runDestination" : {
                  "_type" : {
                    "_name" : "ActionRunDestinationRecord"
                  },
                  "displayName" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "My Mac"
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
                      "_value" : "Apple M1 (Virtual)"
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
                      "_value" : "0000FE00-343A79319AA17942"
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
                      "_value" : "4"
                    },
                    "modelCode" : {
                      "_type" : {
                        "_name" : "String"
                      },
                      "_value" : "VirtualMac2,1"
                    },
                    "modelName" : {
                      "_type" : {
                        "_name" : "String"
                      },
                      "_value" : "Apple Virtual Machine 1"
                    },
                    "modelUTI" : {
                      "_type" : {
                        "_name" : "String"
                      },
                      "_value" : "com.apple.virtual-machine"
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
                      "_value" : "14.3.1"
                    },
                    "operatingSystemVersionWithBuildNumber" : {
                      "_type" : {
                        "_name" : "String"
                      },
                      "_value" : "14.3.1 (23D60)"
                    },
                    "physicalCPUCoresPerPackage" : {
                      "_type" : {
                        "_name" : "Int"
                      },
                      "_value" : "4"
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
                      "_value" : "8192"
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
                      "_value" : "1"
                    },
                    "cpuKind" : {
                      "_type" : {
                        "_name" : "String"
                      },
                      "_value" : "Apple M1 (Virtual)"
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
                      "_value" : "0000FE00-343A79319AA17942"
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
                      "_value" : "4"
                    },
                    "modelCode" : {
                      "_type" : {
                        "_name" : "String"
                      },
                      "_value" : "VirtualMac2,1"
                    },
                    "modelName" : {
                      "_type" : {
                        "_name" : "String"
                      },
                      "_value" : "Apple Virtual Machine 1"
                    },
                    "modelUTI" : {
                      "_type" : {
                        "_name" : "String"
                      },
                      "_value" : "com.apple.virtual-machine"
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
                      "_value" : "14.3.1"
                    },
                    "operatingSystemVersionWithBuildNumber" : {
                      "_type" : {
                        "_name" : "String"
                      },
                      "_value" : "14.3.1 (23D60)"
                    },
                    "physicalCPUCoresPerPackage" : {
                      "_type" : {
                        "_name" : "Int"
                      },
                      "_value" : "4"
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
                      "_value" : "8192"
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
                      "_value" : "macosx14.4"
                    },
                    "name" : {
                      "_type" : {
                        "_name" : "String"
                      },
                      "_value" : "macOS 14.4"
                    },
                    "operatingSystemVersion" : {
                      "_type" : {
                        "_name" : "String"
                      },
                      "_value" : "14.4"
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
                  "_value" : "2024-05-20T12:34:11.228+0000"
                },
                "testPlanName" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "TuistDependenciesAcceptanceTests"
                },
                "title" : {
                  "_type" : {
                    "_name" : "String"
                  },
                  "_value" : "Testing workspace Tuist with scheme TuistDependenciesAcceptanceTests"
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
                      "_value" : "file:\/\/\/Users\/builder\/clone\/Tests\/TuistDependenciesAcceptanceTests\/DependenciesAcceptanceTests.swift#EndingLineNumber=40&StartingLineNumber=40"
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
                    "_value" : "failed: caught error: \"The 'xcodebuild' command exited with error code 65 and message:\n2024-05-20 12:44:17.788570+0000 xcodebuild[14114:50965] [devicemanager] DeviceManager sending check-in request: F988FF5A-CDAC-42C9-9C3F-BE87134AD171\n2024-05-20 12:44:17.790440+0000 xcodebuild[14114:50965] [devicemanager] DeviceManager check-in (F988FF5A-CDAC-42C9-9C3F-BE87134AD171) completed successfully\n2024-05-20 12:44:17.793515+0000 xcodebuild[14114:50961] [All] MobileDevice.framework version: 1643.100.58\n2024-05-20 12:44:17.798111+0000 xcodebuild[14114:50961] [All] RemotePairing.framework version: 117.100.41\n2024-05-20 12:44:17.798690+0000 xcodebuild[14114:50961] [library] USBMuxListenerCreateFiltered:898 Created 0x600003581f40\n2024-05-20 12:44:17.798774+0000 xcodebuild[14114:50961] [All] Subscribed for device notifications from usbmuxd.\n2024-05-20 12:44:18.054503+0000 xcodebuild[14114:50949] [general] initializing workspace at path \/var\/folders\/w2\/rrf5p87d1bbfyphxc7jdnyvh0000gn\/T\/TemporaryDirectory.AMHRiB\/ios_app_with_spm_dependencies\/App.xcworkspace\n2024-05-20 12:44:18.055591+0000 xcodebuild[14114:50949] [general] setting up workspace \/var\/folders\/w2\/rrf5p87d1bbfyphxc7jdnyvh0000gn\/T\/TemporaryDirectory.AMHRiB\/ios_app_with_spm_dependencies\/App.xcworkspace\n2024-05-20 12:44:18.071588+0000 xcodebuild[14114:50949] [general] using plugin library at \/Applications\/Xcode-15.3.app\/Contents\/SharedFrameworks\/SwiftPM.framework\/SharedSupport\/PluginAPI\n2024-05-20 12:44:18.071680+0000 xcodebuild[14114:50949] [general] synchronizing contents of workspace at path \/var\/folders\/w2\/rrf5p87d1bbfyphxc7jdnyvh0000gn\/T\/TemporaryDirectory.AMHRiB\/ios_app_with_spm_dependencies\/App.xcworkspace\n2024-05-20 12:44:18.071698+0000 xcodebuild[14114:50949] [general] marking workspace as having finished initial package resolution\n--- xcodebuild: WARNING: Using the first of multiple matching destinations:\n{ platform:iOS Simulator, id:2B6F50E6-2782-405A-94DF-E659C9398717, OS:17.4, name:iPad Pro (12.9-inch) (6th generation) }\n{ platform:iOS Simulator, id:2B6F50E6-2782-405A-94DF-E659C9398717, OS:17.4, name:iPad Pro (12.9-inch) (6th generation) }\n2024-05-20 12:44:18.106264+0000 xcodebuild[14114:50949] [building] creating scheme operation preamble operations for build command Build\nTesting failed:\n\tCompiling for iOS 14.0, but module 'App' has a minimum deployment target of iOS 16.0: \/Users\/builder\/Library\/Developer\/Xcode\/DerivedData\/App-fzcodvpjdyxljhcxfidulaohhxre\/Build\/Products\/Debug-iphonesimulator\/App.swiftmodule\/arm64-apple-ios-simulator.swiftmodule\n\tTesting cancelled because the build failed.\n\n** TEST FAILED **\n\n\nThe following build commands failed:\n\tSwiftEmitModule normal arm64 Emitting\\ module\\ for\\ AppTests (in target 'AppTests' from project 'App')\n(1 failure)\n\""
                  },
                  "testCaseName" : {
                    "_type" : {
                      "_name" : "String"
                    },
                    "_value" : "DependenciesAcceptanceTestIosAppWithSPMDependencies.test_ios_app_spm_dependencies()"
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
              "_value" : "0~VbN52oFuHDTG0EcAOQetUdZLbKa9zYQrCBFDkKY7h3D2Xi29FsjOinUPBURI9WNvHK3-dvcDm8cZNYvXbsYCHw=="
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
              "_value" : "3"
            },
            "testsFailedCount" : {
              "_type" : {
                "_name" : "Int"
              },
              "_value" : "1"
            }
          }
        }

        """#
    }
}
