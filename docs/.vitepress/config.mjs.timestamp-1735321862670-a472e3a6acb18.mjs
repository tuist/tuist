// .vitepress/config.mjs
import { defineConfig } from "file:///Users/pepicrft/src/github.com/tuist/tuist/docs/node_modules/.pnpm/vitepress@1.5.0_@algolia+client-search@4.24.0_search-insights@2.15.0/node_modules/vitepress/dist/node/index.js";
import * as path4 from "node:path";
import * as fs3 from "node:fs/promises";

// .vitepress/strings/en.json
var en_default = {
  aside: {
    translate: {
      title: {
        text: "Translation \u{1F30D}"
      },
      description: {
        text: "You can translate or improve the translation of this page."
      },
      cta: {
        text: "Contribute"
      }
    }
  },
  search: {
    placeholder: "Search",
    translations: {
      button: {
        "button-text": "Search documentation",
        "button-aria-label": "Search documentation"
      },
      modal: {
        "search-box": {
          "reset-button-title": "Clear query",
          "reset-button-aria-label": "Clear query",
          "cancel-button-text": "Cancel",
          "cancel-button-aria-label": "Cancel"
        },
        "start-screen": {
          "recent-searches-title": "Search history",
          "no-recent-searches-text": "No search history",
          "save-recent-search-button-title": "Save to search history",
          "remove-recent-search-button-title": "Remove from search history",
          "favorite-searches-title": "Favorites",
          "remove-favorite-search-button-title": "Remove from favorites"
        },
        "error-screen": {
          "title-text": "Unable to retrieve results",
          "help-text": "You may need to check your network connection"
        },
        footer: {
          "select-text": "Select",
          "navigate-text": "Navigate",
          "close-text": "Close",
          "search-by-text": "Search provider"
        },
        "no-results-screen": {
          "no-results-text": "No relevant results found",
          "suggested-query-text": "You might try querying",
          "report-missing-results-text": "Do you think this query should have results?",
          "report-missing-results-link-text": "Click to give feedback"
        }
      }
    }
  },
  badges: {
    "coming-soon": "Coming soon",
    "xcodeproj-compatible": "XcodeProj-compatible"
  },
  navbar: {
    guides: {
      text: "Guides"
    },
    cli: {
      text: "CLI"
    },
    server: {
      text: "Server"
    },
    resources: {
      text: "Resources",
      items: {
        references: {
          text: "References"
        },
        contributors: {
          text: "Contributors"
        },
        changelog: {
          text: "Changelog"
        }
      }
    }
  },
  sidebars: {
    cli: {
      text: "CLI",
      items: {
        commands: {
          text: "Commands"
        }
      }
    },
    references: {
      text: "References",
      items: {
        examples: {
          text: "Examples"
        },
        migrations: {
          text: "Migrations",
          items: {
            "from-v3-to-v4": {
              text: "From v3 to v4"
            }
          }
        }
      }
    },
    contributors: {
      text: "Contributors",
      items: {
        "get-started": {
          text: "Get started"
        },
        "issue-reporting": {
          text: "Issue reporting"
        },
        "code-reviews": {
          text: "Code reviews"
        },
        principles: {
          text: "Principles"
        },
        translate: {
          text: "Translate"
        }
      }
    },
    server: {
      items: {
        introduction: {
          text: "Introduction",
          items: {
            "why-server": {
              text: "Why a server?"
            },
            "accounts-and-projects": {
              text: "Accounts and projects"
            },
            authentication: {
              text: "Authentication"
            },
            integrations: {
              text: "Integrations"
            }
          }
        },
        "on-premise": {
          text: "On-premise",
          items: {
            install: {
              text: "Install"
            },
            metrics: {
              text: "Metrics"
            }
          }
        },
        "api-documentation": {
          text: "API documentation"
        },
        status: {
          text: "Status"
        },
        "metrics-dashboard": {
          text: "Metrics dashboard"
        }
      }
    },
    guides: {
      text: "Guides",
      items: {
        "quick-start": {
          text: "Quick start",
          items: {
            "install-tuist": {
              text: "Install Tuist"
            },
            "create-a-project": {
              text: "Create a project"
            },
            "optimize-workflows": {
              text: "Optimize workflows"
            }
          }
        },
        start: {
          text: "Start",
          items: {
            "new-project": {
              text: "Create a new project"
            },
            "swift-package": {
              text: "Try with a Swift Package"
            },
            migrate: {
              text: "Migrate",
              items: {
                "xcode-project": {
                  text: "An Xcode project"
                },
                "swift-package": {
                  text: "A Swift package"
                },
                "xcodegen-project": {
                  text: "An XcodeGen project"
                },
                "bazel-project": {
                  text: "A Bazel project"
                }
              }
            }
          }
        },
        develop: {
          text: "Develop",
          items: {
            projects: {
              text: "Projects",
              items: {
                manifests: {
                  text: "Manifests"
                },
                "directory-structure": {
                  text: "Directory structure"
                },
                editing: {
                  text: "Editing"
                },
                dependencies: {
                  text: "Dependencies"
                },
                "code-sharing": {
                  text: "Code sharing"
                },
                "synthesized-files": {
                  text: "Synthesized files"
                },
                "dynamic-configuration": {
                  text: "Dynamic configuration"
                },
                templates: {
                  text: "Templates"
                },
                plugins: {
                  text: "Plugins"
                },
                hashing: {
                  text: "Hashing"
                },
                "the-cost-of-convenience": {
                  text: "The cost of convenience"
                },
                "tma-architecture": {
                  text: "Modular architecture"
                },
                "best-practices": {
                  text: "Best practices"
                }
              }
            },
            build: {
              text: "Build",
              items: {
                cache: {
                  text: "Cache"
                },
                registry: {
                  text: "Registry"
                }
              }
            },
            test: {
              text: "Test",
              items: {
                "selective-testing": {
                  text: "Selective testing"
                },
                flakiness: {
                  text: "Flakiness"
                }
              }
            },
            inspect: {
              text: "Inspect",
              items: {
                "implicit-imports": {
                  text: "Implicit imports"
                }
              }
            },
            automate: {
              text: "Automate",
              items: {
                "continuous-integration": {
                  text: "Continuous integration"
                },
                workflows: {
                  text: "Workflows"
                }
              }
            }
          }
        },
        share: {
          text: "Share",
          items: {
            previews: {
              text: "Previews"
            }
          }
        }
      }
    }
  }
};

// .vitepress/strings/ru.json
var ru_default = {
  aside: {
    translate: {
      title: {
        text: "Translation \u{1F30D}"
      },
      description: {
        text: "You can translate or improve the translation of this page."
      },
      cta: {
        text: "Contribute"
      }
    }
  },
  search: {
    placeholder: "Search",
    translations: {
      button: {
        "button-text": "Search documentation",
        "button-aria-label": "Search documentation"
      },
      modal: {
        "search-box": {
          "reset-button-title": "Clear query",
          "reset-button-aria-label": "Clear query",
          "cancel-button-text": "Cancel",
          "cancel-button-aria-label": "Cancel"
        },
        "start-screen": {
          "recent-searches-title": "Search history",
          "no-recent-searches-text": "No search history",
          "save-recent-search-button-title": "Save to search history",
          "remove-recent-search-button-title": "Remove from search history",
          "favorite-searches-title": "Favorites",
          "remove-favorite-search-button-title": "Remove from favorites"
        },
        "error-screen": {
          "title-text": "Unable to retrieve results",
          "help-text": "You may need to check your network connection"
        },
        footer: {
          "select-text": "Select",
          "navigate-text": "Navigate",
          "close-text": "Close",
          "search-by-text": "Search provider"
        },
        "no-results-screen": {
          "no-results-text": "No relevant results found",
          "suggested-query-text": "You might try querying",
          "report-missing-results-text": "Do you think this query should have results?",
          "report-missing-results-link-text": "Click to give feedback"
        }
      }
    }
  },
  badges: {
    "coming-soon": "Coming soon",
    "xcodeproj-compatible": "XcodeProj-compatible"
  },
  navbar: {
    guides: {
      text: "Guides"
    },
    cli: {
      text: "CLI"
    },
    server: {
      text: "Server"
    },
    resources: {
      text: "Resources",
      items: {
        references: {
          text: "References"
        },
        contributors: {
          text: "Contributors"
        },
        changelog: {
          text: "Changelog"
        }
      }
    }
  },
  sidebars: {
    cli: {
      text: "CLI",
      items: {
        commands: {
          text: "Commands"
        }
      }
    },
    references: {
      text: "References",
      items: {
        examples: {
          text: "Examples"
        },
        migrations: {
          text: "Migrations",
          items: {
            "from-v3-to-v4": {
              text: "From v3 to v4"
            }
          }
        }
      }
    },
    contributors: {
      text: "Contributors",
      items: {
        "get-started": {
          text: "Get started"
        },
        "issue-reporting": {
          text: "Issue reporting"
        },
        "code-reviews": {
          text: "\u041A\u043E\u0434 \u0440\u0435\u0432\u044C\u044E"
        },
        principles: {
          text: "Principles"
        },
        translate: {
          text: "Translate"
        }
      }
    },
    server: {
      items: {
        introduction: {
          text: "Introduction",
          items: {
            "why-server": {
              text: "Why a server?"
            },
            "accounts-and-projects": {
              text: "Accounts and projects"
            },
            authentication: {
              text: "Authentication"
            },
            integrations: {
              text: "Integrations"
            }
          }
        },
        "on-premise": {
          text: "On-premise",
          items: {
            install: {
              text: "Install"
            },
            metrics: {
              text: "Metrics"
            }
          }
        },
        "api-documentation": {
          text: "API documentation"
        },
        status: {
          text: "Status"
        },
        "metrics-dashboard": {
          text: "Metrics dashboard"
        }
      }
    },
    guides: {
      text: "Guides",
      items: {
        "quick-start": {
          text: "Quick start",
          items: {
            "install-tuist": {
              text: "\u0423\u0441\u0442\u0430\u043D\u043E\u0432\u043A\u0430 Tuist"
            },
            "create-a-project": {
              text: "Create a project"
            },
            "optimize-workflows": {
              text: "Optimize workflows"
            }
          }
        },
        start: {
          text: "Start",
          items: {
            "new-project": {
              text: "\u0421\u043E\u0437\u0434\u0430\u043D\u0438\u0435 \u043D\u043E\u0432\u043E\u0433\u043E \u043F\u0440\u043E\u0435\u043A\u0442\u0430"
            },
            "swift-package": {
              text: "Try with a Swift Package"
            },
            migrate: {
              text: "Migrate",
              items: {
                "xcode-project": {
                  text: "An Xcode project"
                },
                "swift-package": {
                  text: "A Swift package"
                },
                "xcodegen-project": {
                  text: "An XcodeGen project"
                },
                "bazel-project": {
                  text: "A Bazel project"
                }
              }
            }
          }
        },
        develop: {
          text: "Develop",
          items: {
            projects: {
              text: "Projects",
              items: {
                manifests: {
                  text: "Manifests"
                },
                "directory-structure": {
                  text: "Directory structure"
                },
                editing: {
                  text: "Editing"
                },
                dependencies: {
                  text: "\u0417\u0430\u0432\u0438\u0441\u0438\u043C\u043E\u0441\u0442\u0438"
                },
                "code-sharing": {
                  text: "Code sharing"
                },
                "synthesized-files": {
                  text: "Synthesized files"
                },
                "dynamic-configuration": {
                  text: "Dynamic configuration"
                },
                templates: {
                  text: "Templates"
                },
                plugins: {
                  text: "Plugins"
                },
                hashing: {
                  text: "Hashing"
                },
                "the-cost-of-convenience": {
                  text: "The cost of convenience"
                },
                "tma-architecture": {
                  text: "Modular architecture"
                },
                "best-practices": {
                  text: "\u041B\u0443\u0447\u0448\u0438\u0435 \u043F\u0440\u0430\u043A\u0442\u0438\u043A\u0438"
                }
              }
            },
            build: {
              text: "Build",
              items: {
                cache: {
                  text: "Cache"
                },
                registry: {
                  text: "Registry"
                }
              }
            },
            test: {
              text: "Test",
              items: {
                "selective-testing": {
                  text: "Selective testing"
                },
                flakiness: {
                  text: "Flakiness"
                }
              }
            },
            inspect: {
              text: "Inspect",
              items: {
                "implicit-imports": {
                  text: "\u041D\u0435\u044F\u0432\u043D\u044B\u0435 \u0438\u043C\u043F\u043E\u0440\u0442\u044B"
                }
              }
            },
            automate: {
              text: "Automate",
              items: {
                "continuous-integration": {
                  text: "Continuous integration"
                },
                workflows: {
                  text: "Workflows"
                }
              }
            }
          }
        },
        share: {
          text: "Share",
          items: {
            previews: {
              text: "Previews"
            }
          }
        }
      }
    }
  }
};

// .vitepress/strings/ko.json
var ko_default = {
  aside: {
    translate: {
      title: {
        text: "\uBC88\uC5ED"
      },
      description: {
        text: "\uC774 \uD398\uC774\uC9C0\uB97C \uBC88\uC5ED\uD558\uAC70\uB098 \uAE30\uC874 \uBC88\uC5ED\uC744 \uAC1C\uC120\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4."
      },
      cta: {
        text: "\uAE30\uC5EC"
      }
    }
  },
  search: {
    placeholder: "\uAC80\uC0C9",
    translations: {
      button: {
        "button-text": "\uBB38\uC11C \uAC80\uC0C9",
        "button-aria-label": "\uBB38\uC11C \uAC80\uC0C9"
      },
      modal: {
        "search-box": {
          "reset-button-title": "\uAC80\uC0C9\uC5B4 \uCD08\uAE30\uD654",
          "reset-button-aria-label": "\uAC80\uC0C9\uC5B4 \uCD08\uAE30\uD654",
          "cancel-button-text": "\uCDE8\uC18C",
          "cancel-button-aria-label": "\uCDE8\uC18C"
        },
        "start-screen": {
          "recent-searches-title": "\uAC80\uC0C9 \uC774\uB825",
          "no-recent-searches-text": "\uAC80\uC0C9 \uC774\uB825\uC774 \uC5C6\uC74C",
          "save-recent-search-button-title": "\uAC80\uC0C9 \uC774\uB825 \uC800\uC7A5",
          "remove-recent-search-button-title": "\uAC80\uC0C9 \uC774\uB825 \uC0AD\uC81C",
          "favorite-searches-title": "\uC990\uACA8\uCC3E\uAE30",
          "remove-favorite-search-button-title": "\uC990\uACA8\uCC3E\uAE30 \uC0AD\uC81C"
        },
        "error-screen": {
          "title-text": "\uACB0\uACFC\uB97C \uBC1B\uC744 \uC218 \uC5C6\uC74C",
          "help-text": "\uB124\uD2B8\uC6CC\uD06C \uC5F0\uACB0\uC744 \uD655\uC778\uD574\uC8FC\uC138\uC694"
        },
        footer: {
          "select-text": "\uC120\uD0DD",
          "navigate-text": "\uD0D0\uC0C9",
          "close-text": "\uB2EB\uAE30",
          "search-by-text": "\uAC80\uC0C9 \uC81C\uACF5\uC790"
        },
        "no-results-screen": {
          "no-results-text": "\uAD00\uB828\uB41C \uACB0\uACFC\uB97C \uCC3E\uC744 \uC218 \uC5C6\uC74C",
          "suggested-query-text": "\uB2E4\uB978 \uAC80\uC0C9\uC5B4\uB97C \uC785\uB825\uD574\uBCF4\uC138\uC694",
          "report-missing-results-text": "\uAC80\uC0C9 \uACB0\uACFC\uAC00 \uC788\uC5B4\uC57C \uD55C\uB2E4\uACE0 \uC0DD\uAC01\uD558\uB098\uC694?",
          "report-missing-results-link-text": "\uD53C\uB4DC\uBC31\uD558\uAE30"
        }
      }
    }
  },
  badges: {
    "coming-soon": "Coming soon",
    "xcodeproj-compatible": "XcodeProj-compatible"
  },
  navbar: {
    guides: {
      text: "\uC548\uB0B4\uC11C"
    },
    cli: {
      text: "CLI"
    },
    server: {
      text: "\uC11C\uBC84"
    },
    resources: {
      text: "\uB9AC\uC18C\uC2A4",
      items: {
        references: {
          text: "\uCC38\uACE0\uC790\uB8CC"
        },
        contributors: {
          text: "\uAE30\uC5EC\uC790\uB4E4"
        },
        changelog: {
          text: "\uC218\uC815\uC0AC\uD56D"
        }
      }
    }
  },
  sidebars: {
    cli: {
      text: "CLI",
      items: {
        commands: {
          text: "Commands"
        }
      }
    },
    references: {
      text: "References",
      items: {
        examples: {
          text: "Examples"
        },
        migrations: {
          text: "Migrations",
          items: {
            "from-v3-to-v4": {
              text: "From v3 to v4"
            }
          }
        }
      }
    },
    contributors: {
      text: "Contributors",
      items: {
        "get-started": {
          text: "Get started"
        },
        "issue-reporting": {
          text: "Issue reporting"
        },
        "code-reviews": {
          text: "Code reviews"
        },
        principles: {
          text: "Principles"
        },
        translate: {
          text: "Translate"
        }
      }
    },
    server: {
      items: {
        introduction: {
          text: "Introduction",
          items: {
            "why-server": {
              text: "Why a server?"
            },
            "accounts-and-projects": {
              text: "Accounts and projects"
            },
            authentication: {
              text: "Authentication"
            },
            integrations: {
              text: "Integrations"
            }
          }
        },
        "on-premise": {
          text: "On-premise",
          items: {
            install: {
              text: "Install"
            },
            metrics: {
              text: "Metrics"
            }
          }
        },
        "api-documentation": {
          text: "API documentation"
        },
        status: {
          text: "Status"
        },
        "metrics-dashboard": {
          text: "\uD1B5\uACC4 \uD604\uD669\uD310"
        }
      }
    },
    guides: {
      text: "\uC548\uB0B4\uC11C",
      items: {
        "quick-start": {
          text: "Quick start",
          items: {
            "install-tuist": {
              text: "Install Tuist"
            },
            "create-a-project": {
              text: "Create a project"
            },
            "optimize-workflows": {
              text: "Optimize workflows"
            }
          }
        },
        start: {
          text: "Start",
          items: {
            "new-project": {
              text: "Create a new project"
            },
            "swift-package": {
              text: "Try with a Swift Package"
            },
            migrate: {
              text: "Migrate",
              items: {
                "xcode-project": {
                  text: "An Xcode project"
                },
                "swift-package": {
                  text: "A Swift package"
                },
                "xcodegen-project": {
                  text: "An XcodeGen project"
                },
                "bazel-project": {
                  text: "A Bazel project"
                }
              }
            }
          }
        },
        develop: {
          text: "Develop",
          items: {
            projects: {
              text: "Projects",
              items: {
                manifests: {
                  text: "Manifests"
                },
                "directory-structure": {
                  text: "Directory structure"
                },
                editing: {
                  text: "Editing"
                },
                dependencies: {
                  text: "Dependencies"
                },
                "code-sharing": {
                  text: "Code sharing"
                },
                "synthesized-files": {
                  text: "Synthesized files"
                },
                "dynamic-configuration": {
                  text: "Dynamic configuration"
                },
                templates: {
                  text: "Templates"
                },
                plugins: {
                  text: "Plugins"
                },
                hashing: {
                  text: "Hashing"
                },
                "the-cost-of-convenience": {
                  text: "The cost of convenience"
                },
                "tma-architecture": {
                  text: "Modular architecture"
                },
                "best-practices": {
                  text: "Best practices"
                }
              }
            },
            build: {
              text: "Build",
              items: {
                cache: {
                  text: "Cache"
                },
                registry: {
                  text: "Registry"
                }
              }
            },
            test: {
              text: "Test",
              items: {
                "selective-testing": {
                  text: "Selective testing"
                },
                flakiness: {
                  text: "Flakiness"
                }
              }
            },
            inspect: {
              text: "Inspect",
              items: {
                "implicit-imports": {
                  text: "Implicit imports"
                }
              }
            },
            automate: {
              text: "Automate",
              items: {
                "continuous-integration": {
                  text: "Continuous integration"
                },
                workflows: {
                  text: "Workflows"
                }
              }
            }
          }
        },
        share: {
          text: "Share",
          items: {
            previews: {
              text: "Previews"
            }
          }
        }
      }
    }
  }
};

// .vitepress/strings/ja.json
var ja_default = {
  aside: {
    translate: {
      title: {
        text: "\u7FFB\u8A33 \u{1F30D}"
      },
      description: {
        text: "\u3053\u306E\u30DA\u30FC\u30B8\u306E\u7FFB\u8A33\u3092\u884C\u3063\u305F\u308A\u3001\u6539\u5584\u3057\u305F\u308A\u3059\u308B\u3053\u3068\u304C\u3067\u304D\u307E\u3059\u3002"
      },
      cta: {
        text: "\u30B3\u30F3\u30C8\u30EA\u30D3\u30E5\u30FC\u30C8\u3059\u308B"
      }
    }
  },
  search: {
    placeholder: "\u691C\u7D22",
    translations: {
      button: {
        "button-text": "\u30C9\u30AD\u30E5\u30E1\u30F3\u30C8\u3092\u691C\u7D22",
        "button-aria-label": "\u30C9\u30AD\u30E5\u30E1\u30F3\u30C8\u3092\u691C\u7D22"
      },
      modal: {
        "search-box": {
          "reset-button-title": "\u691C\u7D22\u30AD\u30FC\u30EF\u30FC\u30C9\u3092\u524A\u9664",
          "reset-button-aria-label": "\u691C\u7D22\u30AD\u30FC\u30EF\u30FC\u30C9\u3092\u524A\u9664",
          "cancel-button-text": "\u30AD\u30E3\u30F3\u30BB\u30EB",
          "cancel-button-aria-label": "\u30AD\u30E3\u30F3\u30BB\u30EB"
        },
        "start-screen": {
          "recent-searches-title": "\u5C65\u6B74\u3092\u691C\u7D22",
          "no-recent-searches-text": "\u691C\u7D22\u5C65\u6B74\u306F\u3042\u308A\u307E\u305B\u3093",
          "save-recent-search-button-title": "\u691C\u7D22\u5C65\u6B74\u306B\u4FDD\u5B58",
          "remove-recent-search-button-title": "\u691C\u7D22\u5C65\u6B74\u304B\u3089\u524A\u9664\u3059\u308B",
          "favorite-searches-title": "\u304A\u6C17\u306B\u5165\u308A",
          "remove-favorite-search-button-title": "\u304A\u6C17\u306B\u5165\u308A\u304B\u3089\u524A\u9664"
        },
        "error-screen": {
          "title-text": "\u7D50\u679C\u3092\u53D6\u5F97\u3067\u304D\u307E\u305B\u3093\u3067\u3057\u305F",
          "help-text": "\u30CD\u30C3\u30C8\u30EF\u30FC\u30AF\u63A5\u7D9A\u3092\u78BA\u8A8D\u3057\u3066\u304F\u3060\u3055\u3044"
        },
        footer: {
          "select-text": "\u9078\u629E",
          "navigate-text": "\u79FB\u52D5",
          "close-text": "\u9589\u3058\u308B",
          "search-by-text": "\u691C\u7D22\u30D7\u30ED\u30D0\u30A4\u30C0\u30FC"
        },
        "no-results-screen": {
          "no-results-text": "\u95A2\u9023\u3059\u308B\u7D50\u679C\u304C\u898B\u3064\u304B\u308A\u307E\u305B\u3093\u3067\u3057\u305F",
          "suggested-query-text": "\u30AF\u30A8\u30EA\u3092\u8A66\u3057\u3066\u307F\u308B\u3053\u3068\u304C\u3067\u304D\u307E\u3059",
          "report-missing-results-text": "\u3053\u306E\u30AF\u30A8\u30EA\u306B\u306F\u7D50\u679C\u304C\u3042\u308B\u3068\u601D\u3044\u307E\u3059\u304B?",
          "report-missing-results-link-text": "\u30AF\u30EA\u30C3\u30AF\u3057\u3066\u30D5\u30A3\u30FC\u30C9\u30D0\u30C3\u30AF\u3059\u308B"
        }
      }
    }
  },
  badges: {
    "coming-soon": "\u8FD1\u65E5\u516C\u958B",
    "xcodeproj-compatible": "XcodeProj\u4E92\u63DB"
  },
  navbar: {
    guides: {
      text: "\u30AC\u30A4\u30C9"
    },
    cli: {
      text: "CLI"
    },
    server: {
      text: "\u30B5\u30FC\u30D0\u30FC"
    },
    resources: {
      text: "\u30EA\u30BD\u30FC\u30B9",
      items: {
        references: {
          text: "\u30EA\u30D5\u30A1\u30EC\u30F3\u30B9"
        },
        contributors: {
          text: "\u30B3\u30F3\u30C8\u30EA\u30D3\u30E5\u30FC\u30BF\u30FC"
        },
        changelog: {
          text: "\u5909\u66F4\u5C65\u6B74"
        }
      }
    }
  },
  sidebars: {
    cli: {
      text: "CLI",
      items: {
        commands: {
          text: "\u30B3\u30DE\u30F3\u30C9"
        }
      }
    },
    references: {
      text: "\u30EA\u30D5\u30A1\u30EC\u30F3\u30B9",
      items: {
        examples: {
          text: "\u30B5\u30F3\u30D7\u30EB"
        },
        migrations: {
          text: "\u30DE\u30A4\u30B0\u30EC\u30FC\u30B7\u30E7\u30F3",
          items: {
            "from-v3-to-v4": {
              text: "v3 \u304B\u3089 v4 \u3078"
            }
          }
        }
      }
    },
    contributors: {
      text: "\u30B3\u30F3\u30C8\u30EA\u30D3\u30E5\u30FC\u30BF\u30FC",
      items: {
        "get-started": {
          text: "\u59CB\u3081\u65B9"
        },
        "issue-reporting": {
          text: "Issue\u5831\u544A"
        },
        "code-reviews": {
          text: "\u30B3\u30FC\u30C9\u30EC\u30D3\u30E5\u30FC"
        },
        principles: {
          text: "\u539F\u5247"
        },
        translate: {
          text: "\u7FFB\u8A33\u3059\u308B"
        }
      }
    },
    server: {
      items: {
        introduction: {
          text: "\u306F\u3058\u3081\u306B",
          items: {
            "why-server": {
              text: "\u306A\u305C\u30B5\u30FC\u30D0\u30FC\u304C\u5FC5\u8981\u306A\u306E\u304B\uFF1F"
            },
            "accounts-and-projects": {
              text: "\u30A2\u30AB\u30A6\u30F3\u30C8\u3068\u30D7\u30ED\u30B8\u30A7\u30AF\u30C8"
            },
            authentication: {
              text: "\u8A8D\u8A3C"
            },
            integrations: {
              text: "\u30A4\u30F3\u30C6\u30B0\u30EC\u30FC\u30B7\u30E7\u30F3"
            }
          }
        },
        "on-premise": {
          text: "\u30AA\u30F3\u30D7\u30EC\u30DF\u30B9",
          items: {
            install: {
              text: "\u30A4\u30F3\u30B9\u30C8\u30FC\u30EB"
            },
            metrics: {
              text: "\u30E1\u30C8\u30EA\u30AF\u30B9"
            }
          }
        },
        "api-documentation": {
          text: "API\u30C9\u30AD\u30E5\u30E1\u30F3\u30C8"
        },
        status: {
          text: "\u30B9\u30C6\u30FC\u30BF\u30B9"
        },
        "metrics-dashboard": {
          text: "\u30E1\u30C8\u30EA\u30AF\u30B9\u30C0\u30C3\u30B7\u30E5\u30DC\u30FC\u30C9"
        }
      }
    },
    guides: {
      text: "\u30AC\u30A4\u30C9",
      items: {
        "quick-start": {
          text: "\u30AF\u30A4\u30C3\u30AF\u30B9\u30BF\u30FC\u30C8",
          items: {
            "install-tuist": {
              text: "Tuist\u306E\u30A4\u30F3\u30B9\u30C8\u30FC\u30EB"
            },
            "create-a-project": {
              text: "\u30D7\u30ED\u30B8\u30A7\u30AF\u30C8\u306E\u4F5C\u6210"
            },
            "optimize-workflows": {
              text: "\u30EF\u30FC\u30AF\u30D5\u30ED\u30FC\u306E\u6700\u9069\u5316"
            }
          }
        },
        start: {
          text: "\u306F\u3058\u3081\u304B\u305F",
          items: {
            "new-project": {
              text: "\u65B0\u898F\u30D7\u30ED\u30B8\u30A7\u30AF\u30C8\u306E\u4F5C\u6210"
            },
            "swift-package": {
              text: "Swift \u30D1\u30C3\u30B1\u30FC\u30B8\u3067\u8A66\u3059"
            },
            migrate: {
              text: "\u79FB\u884C\u3059\u308B",
              items: {
                "xcode-project": {
                  text: "Xcode \u30D7\u30ED\u30B8\u30A7\u30AF\u30C8"
                },
                "swift-package": {
                  text: "Swift \u30D1\u30C3\u30B1\u30FC\u30B8"
                },
                "xcodegen-project": {
                  text: "XcodeGen \u30D7\u30ED\u30B8\u30A7\u30AF\u30C8"
                },
                "bazel-project": {
                  text: "Bazel \u30D7\u30ED\u30B8\u30A7\u30AF\u30C8"
                }
              }
            }
          }
        },
        develop: {
          text: "\u958B\u767A",
          items: {
            projects: {
              text: "\u30D7\u30ED\u30B8\u30A7\u30AF\u30C8",
              items: {
                manifests: {
                  text: "\u30DE\u30CB\u30D5\u30A7\u30B9\u30C8"
                },
                "directory-structure": {
                  text: "\u30C7\u30A3\u30EC\u30AF\u30C8\u30EA\u69CB\u6210"
                },
                editing: {
                  text: "\u7DE8\u96C6\u65B9\u6CD5"
                },
                dependencies: {
                  text: "\u4F9D\u5B58\u95A2\u4FC2"
                },
                "code-sharing": {
                  text: "\u30B3\u30FC\u30C9\u306E\u5171\u6709"
                },
                "synthesized-files": {
                  text: "\u81EA\u52D5\u751F\u6210\u30D5\u30A1\u30A4\u30EB"
                },
                "dynamic-configuration": {
                  text: "\u52D5\u7684\u30B3\u30F3\u30D5\u30A3\u30AE\u30E5\u30EC\u30FC\u30B7\u30E7\u30F3"
                },
                templates: {
                  text: "\u30C6\u30F3\u30D7\u30EC\u30FC\u30C8"
                },
                plugins: {
                  text: "\u30D7\u30E9\u30B0\u30A4\u30F3"
                },
                hashing: {
                  text: "\u30CF\u30C3\u30B7\u30E5"
                },
                "the-cost-of-convenience": {
                  text: "\u5229\u4FBF\u6027\u306E\u4EE3\u511F"
                },
                "tma-architecture": {
                  text: "\u30E2\u30B8\u30E5\u30FC\u30E9\u30FC\u30A2\u30FC\u30AD\u30C6\u30AF\u30C1\u30E3"
                },
                "best-practices": {
                  text: "\u30D9\u30B9\u30C8\u30D7\u30E9\u30AF\u30C6\u30A3\u30B9"
                }
              }
            },
            build: {
              text: "\u30D3\u30EB\u30C9",
              items: {
                cache: {
                  text: "\u30AD\u30E3\u30C3\u30B7\u30E5"
                },
                registry: {
                  text: "Registry"
                }
              }
            },
            test: {
              text: "\u30C6\u30B9\u30C8",
              items: {
                "selective-testing": {
                  text: "Selective testing"
                },
                flakiness: {
                  text: "Flaky \u306A\u30C6\u30B9\u30C8"
                }
              }
            },
            inspect: {
              text: "\u691C\u67FB",
              items: {
                "implicit-imports": {
                  text: "\u6697\u9ED9\u306E\u30A4\u30F3\u30DD\u30FC\u30C8"
                }
              }
            },
            automate: {
              text: "\u81EA\u52D5\u5316",
              items: {
                "continuous-integration": {
                  text: "\u7D99\u7D9A\u7684\u30A4\u30F3\u30C6\u30B0\u30EC\u30FC\u30B7\u30E7\u30F3"
                },
                workflows: {
                  text: "\u30EF\u30FC\u30AF\u30D5\u30ED\u30FC"
                }
              }
            }
          }
        },
        share: {
          text: "\u5171\u6709",
          items: {
            previews: {
              text: "\u30D7\u30EC\u30D3\u30E5\u30FC\u6A5F\u80FD"
            }
          }
        }
      }
    }
  }
};

// .vitepress/strings/es.json
var es_default = {
  aside: {
    translate: {
      title: {
        text: "Traducci\xF3n \u{1F30D}"
      },
      description: {
        text: "Traduce o mejora la traducci\xF3n de esta p\xE1gina."
      },
      cta: {
        text: "Contribuye"
      }
    }
  },
  search: {
    placeholder: "Busca",
    translations: {
      button: {
        "button-text": "Busca en la documentaci\xF3n",
        "button-aria-label": "Busca en la documentaci\xF3n"
      },
      modal: {
        "search-box": {
          "reset-button-title": "Limpiar t\xE9rmino de b\xFAsqueda",
          "reset-button-aria-label": "Limpiar t\xE9rmino de b\xFAsqueda",
          "cancel-button-text": "Cancelar",
          "cancel-button-aria-label": "Cancelar"
        },
        "start-screen": {
          "recent-searches-title": "Historial de b\xFAsqueda",
          "no-recent-searches-text": "No hay historial de b\xFAsqueda",
          "save-recent-search-button-title": "Guardar en el historial de b\xFAsqueda",
          "remove-recent-search-button-title": "Eliminar del historial de b\xFAsqueda",
          "favorite-searches-title": "Favoritos",
          "remove-favorite-search-button-title": "Eliminar de favoritos"
        },
        "error-screen": {
          "title-text": "Imposible obtener resultados",
          "help-text": "Comprueba tu conexi\xF3n a Internet"
        },
        footer: {
          "select-text": "Selecciona",
          "navigate-text": "Navegar",
          "close-text": "Cerrar",
          "search-by-text": "Proveedor de b\xFAsqueda"
        },
        "no-results-screen": {
          "no-results-text": "No se encontraron resultados relevantes",
          "suggested-query-text": "Podr\xEDas intentar consultar",
          "report-missing-results-text": "\xBFCree que esta consulta deber\xEDa tener resultados?",
          "report-missing-results-link-text": "Haz clic para dar tu opini\xF3n"
        }
      }
    }
  },
  badges: {
    "coming-soon": "Disponible pr\xF3ximamente",
    "xcodeproj-compatible": "Compatible con XcodeProj"
  },
  navbar: {
    guides: {
      text: "Gu\xEDas"
    },
    cli: {
      text: "CLI"
    },
    server: {
      text: "Servidor"
    },
    resources: {
      text: "Recursos",
      items: {
        references: {
          text: "Referencias"
        },
        contributors: {
          text: "Colaboradores"
        },
        changelog: {
          text: "Changelog"
        }
      }
    }
  },
  sidebars: {
    cli: {
      text: "CLI",
      items: {
        commands: {
          text: "Comandos"
        }
      }
    },
    references: {
      text: "Referencias",
      items: {
        examples: {
          text: "Ejemplos"
        },
        migrations: {
          text: "Migraciones",
          items: {
            "from-v3-to-v4": {
              text: "De v3 a v4"
            }
          }
        }
      }
    },
    contributors: {
      text: "Colaboradores",
      items: {
        "get-started": {
          text: "Comenzar"
        },
        "issue-reporting": {
          text: "Reporte de Issues"
        },
        "code-reviews": {
          text: "Revisi\xF3n de c\xF3digo"
        },
        principles: {
          text: "Principios"
        },
        translate: {
          text: "Traduce"
        }
      }
    },
    server: {
      items: {
        introduction: {
          text: "Introducci\xF3n",
          items: {
            "why-server": {
              text: "\xBFPor qu\xE9 un servidor?"
            },
            "accounts-and-projects": {
              text: "Cuentas y proyectos"
            },
            authentication: {
              text: "Autentificaci\xF3n"
            },
            integrations: {
              text: "Integraciones"
            }
          }
        },
        "on-premise": {
          text: "On-premise",
          items: {
            install: {
              text: "Instala"
            },
            metrics: {
              text: "M\xE9tricas"
            }
          }
        },
        "api-documentation": {
          text: "Documentaci\xF3n de la API"
        },
        status: {
          text: "Estado"
        },
        "metrics-dashboard": {
          text: "Panel de m\xE9tricas"
        }
      }
    },
    guides: {
      text: "Gu\xEDas",
      items: {
        "quick-start": {
          text: "Quick Start",
          items: {
            "install-tuist": {
              text: "Instala Tuist"
            },
            "create-a-project": {
              text: "Crea un proyecto"
            },
            "optimize-workflows": {
              text: "Optimiza workflows"
            }
          }
        },
        start: {
          text: "Empieza",
          items: {
            "new-project": {
              text: "Crea un nuevo proyecto"
            },
            "swift-package": {
              text: "Prueba con un paquete de Swift"
            },
            migrate: {
              text: "Migra",
              items: {
                "xcode-project": {
                  text: "Un proyecto de Xcode"
                },
                "swift-package": {
                  text: "Un paquete de Swift"
                },
                "xcodegen-project": {
                  text: "Un proyecto XcodeGen"
                },
                "bazel-project": {
                  text: "Un proyecto Bazel"
                }
              }
            }
          }
        },
        develop: {
          text: "Desarrolla",
          items: {
            projects: {
              text: "Proyectos",
              items: {
                manifests: {
                  text: "Ficheros manifest"
                },
                "directory-structure": {
                  text: "Estructura de directorios"
                },
                editing: {
                  text: "Edici\xF3n"
                },
                dependencies: {
                  text: "Dependencias"
                },
                "code-sharing": {
                  text: "Compartir c\xF3digo"
                },
                "synthesized-files": {
                  text: "Sintetizado de ficheros"
                },
                "dynamic-configuration": {
                  text: "Configuraci\xF3n din\xE1mica"
                },
                templates: {
                  text: "Plantillas"
                },
                plugins: {
                  text: "Plugins"
                },
                hashing: {
                  text: "Hasheado"
                },
                "the-cost-of-convenience": {
                  text: "El coste de la conveniencia"
                },
                "tma-architecture": {
                  text: "Architectura modular"
                },
                "best-practices": {
                  text: "Buenas pr\xE1cticas"
                }
              }
            },
            build: {
              text: "Compila",
              items: {
                cache: {
                  text: "Cachea"
                },
                registry: {
                  text: "Registry"
                }
              }
            },
            test: {
              text: "Testea",
              items: {
                "selective-testing": {
                  text: "Selective testing"
                },
                flakiness: {
                  text: "Flakiness"
                }
              }
            },
            inspect: {
              text: "Inspecciona",
              items: {
                "implicit-imports": {
                  text: "Imports impl\xEDcitos"
                }
              }
            },
            automate: {
              text: "Automatiza",
              items: {
                "continuous-integration": {
                  text: "Integraci\xF3n continua"
                },
                workflows: {
                  text: "Workflows"
                }
              }
            }
          }
        },
        share: {
          text: "Comparte",
          items: {
            previews: {
              text: "Previews"
            }
          }
        }
      }
    }
  }
};

// .vitepress/strings/pt.json
var pt_default = {
  aside: {
    translate: {
      title: {
        text: "Translation \u{1F30D}"
      },
      description: {
        text: "You can translate or improve the translation of this page."
      },
      cta: {
        text: "Contribute"
      }
    }
  },
  search: {
    placeholder: "Search",
    translations: {
      button: {
        "button-text": "Search documentation",
        "button-aria-label": "Search documentation"
      },
      modal: {
        "search-box": {
          "reset-button-title": "Clear query",
          "reset-button-aria-label": "Clear query",
          "cancel-button-text": "Cancel",
          "cancel-button-aria-label": "Cancel"
        },
        "start-screen": {
          "recent-searches-title": "Search history",
          "no-recent-searches-text": "No search history",
          "save-recent-search-button-title": "Save to search history",
          "remove-recent-search-button-title": "Remove from search history",
          "favorite-searches-title": "Favorites",
          "remove-favorite-search-button-title": "Remove from favorites"
        },
        "error-screen": {
          "title-text": "Unable to retrieve results",
          "help-text": "You may need to check your network connection"
        },
        footer: {
          "select-text": "Select",
          "navigate-text": "Navigate",
          "close-text": "Close",
          "search-by-text": "Search provider"
        },
        "no-results-screen": {
          "no-results-text": "No relevant results found",
          "suggested-query-text": "You might try querying",
          "report-missing-results-text": "Do you think this query should have results?",
          "report-missing-results-link-text": "Click to give feedback"
        }
      }
    }
  },
  badges: {
    "coming-soon": "Coming soon",
    "xcodeproj-compatible": "XcodeProj-compatible"
  },
  navbar: {
    guides: {
      text: "Guides"
    },
    cli: {
      text: "CLI"
    },
    server: {
      text: "Server"
    },
    resources: {
      text: "Resources",
      items: {
        references: {
          text: "References"
        },
        contributors: {
          text: "Contributors"
        },
        changelog: {
          text: "Changelog"
        }
      }
    }
  },
  sidebars: {
    cli: {
      text: "CLI",
      items: {
        commands: {
          text: "Commands"
        }
      }
    },
    references: {
      text: "References",
      items: {
        examples: {
          text: "Examples"
        },
        migrations: {
          text: "Migrations",
          items: {
            "from-v3-to-v4": {
              text: "From v3 to v4"
            }
          }
        }
      }
    },
    contributors: {
      text: "Contributors",
      items: {
        "get-started": {
          text: "Get started"
        },
        "issue-reporting": {
          text: "Issue reporting"
        },
        "code-reviews": {
          text: "Code reviews"
        },
        principles: {
          text: "Principles"
        },
        translate: {
          text: "Translate"
        }
      }
    },
    server: {
      items: {
        introduction: {
          text: "Introduction",
          items: {
            "why-server": {
              text: "Why a server?"
            },
            "accounts-and-projects": {
              text: "Accounts and projects"
            },
            authentication: {
              text: "Authentication"
            },
            integrations: {
              text: "Integrations"
            }
          }
        },
        "on-premise": {
          text: "On-premise",
          items: {
            install: {
              text: "Install"
            },
            metrics: {
              text: "Metrics"
            }
          }
        },
        "api-documentation": {
          text: "API documentation"
        },
        status: {
          text: "Status"
        },
        "metrics-dashboard": {
          text: "Metrics dashboard"
        }
      }
    },
    guides: {
      text: "Guides",
      items: {
        "quick-start": {
          text: "Quick start",
          items: {
            "install-tuist": {
              text: "Install Tuist"
            },
            "create-a-project": {
              text: "Create a project"
            },
            "optimize-workflows": {
              text: "Optimize workflows"
            }
          }
        },
        start: {
          text: "Start",
          items: {
            "new-project": {
              text: "Create a new project"
            },
            "swift-package": {
              text: "Try with a Swift Package"
            },
            migrate: {
              text: "Migrate",
              items: {
                "xcode-project": {
                  text: "An Xcode project"
                },
                "swift-package": {
                  text: "A Swift package"
                },
                "xcodegen-project": {
                  text: "An XcodeGen project"
                },
                "bazel-project": {
                  text: "A Bazel project"
                }
              }
            }
          }
        },
        develop: {
          text: "Develop",
          items: {
            projects: {
              text: "Projects",
              items: {
                manifests: {
                  text: "Manifests"
                },
                "directory-structure": {
                  text: "Directory structure"
                },
                editing: {
                  text: "Editing"
                },
                dependencies: {
                  text: "Dependencies"
                },
                "code-sharing": {
                  text: "Code sharing"
                },
                "synthesized-files": {
                  text: "Synthesized files"
                },
                "dynamic-configuration": {
                  text: "Dynamic configuration"
                },
                templates: {
                  text: "Templates"
                },
                plugins: {
                  text: "Plugins"
                },
                hashing: {
                  text: "Hashing"
                },
                "the-cost-of-convenience": {
                  text: "The cost of convenience"
                },
                "tma-architecture": {
                  text: "Modular architecture"
                },
                "best-practices": {
                  text: "Best practices"
                }
              }
            },
            build: {
              text: "Build",
              items: {
                cache: {
                  text: "Cache"
                },
                registry: {
                  text: "Registry"
                }
              }
            },
            test: {
              text: "Test",
              items: {
                "selective-testing": {
                  text: "Selective testing"
                },
                flakiness: {
                  text: "Flakiness"
                }
              }
            },
            inspect: {
              text: "Inspect",
              items: {
                "implicit-imports": {
                  text: "Implicit imports"
                }
              }
            },
            automate: {
              text: "Automate",
              items: {
                "continuous-integration": {
                  text: "Continuous integration"
                },
                workflows: {
                  text: "Workflows"
                }
              }
            }
          }
        },
        share: {
          text: "Share",
          items: {
            previews: {
              text: "Previews"
            }
          }
        }
      }
    }
  }
};

// .vitepress/i18n.mjs
var strings = {
  en: en_default,
  ru: ru_default,
  ko: ko_default,
  ja: ja_default,
  es: es_default,
  pt: pt_default
};
function localizedString(locale, key) {
  const getString = (localeStrings, key2) => {
    const keys = key2.split(".");
    let current = localeStrings;
    for (const k of keys) {
      if (current && current.hasOwnProperty(k)) {
        current = current[k];
      } else {
        return void 0;
      }
    }
    return current;
  };
  let localizedValue = getString(strings[locale], key);
  if (localizedValue === void 0 && locale !== "en") {
    localizedValue = getString(strings["en"], key);
  }
  return localizedValue;
}

// .vitepress/badges.mjs
function xcodeProjCompatibleBadge(locale) {
  return `<span style="background: var(--vp-badge-warning-bg); color: var(--vp-badge-warning-text); font-size: 11px; display: inline-block; padding-left: 5px; padding-right: 5px; border-radius: 10%;">${localizedString(
    locale,
    "badges.xcodeproj-compatible"
  )}</span>`;
}

// .vitepress/icons.mjs
function cubeOutlineIcon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M9.75 20.7501L11.223 21.5684C11.5066 21.726 11.6484 21.8047 11.7986 21.8356C11.9315 21.863 12.0685 21.863 12.2015 21.8356C12.3516 21.8047 12.4934 21.726 12.777 21.5684L14.25 20.7501M5.25 18.2501L3.82297 17.4573C3.52346 17.2909 3.37368 17.2077 3.26463 17.0893C3.16816 16.9847 3.09515 16.8606 3.05048 16.7254C3 16.5726 3 16.4013 3 16.0586V14.5001M3 9.50009V7.94153C3 7.59889 3 7.42757 3.05048 7.27477C3.09515 7.13959 3.16816 7.01551 3.26463 6.91082C3.37368 6.79248 3.52345 6.70928 3.82297 6.54288L5.25 5.75009M9.75 3.25008L11.223 2.43177C11.5066 2.27421 11.6484 2.19543 11.7986 2.16454C11.9315 2.13721 12.0685 2.13721 12.2015 2.16454C12.3516 2.19543 12.4934 2.27421 12.777 2.43177L14.25 3.25008M18.75 5.75008L20.177 6.54288C20.4766 6.70928 20.6263 6.79248 20.7354 6.91082C20.8318 7.01551 20.9049 7.13959 20.9495 7.27477C21 7.42757 21 7.59889 21 7.94153V9.50008M21 14.5001V16.0586C21 16.4013 21 16.5726 20.9495 16.7254C20.9049 16.8606 20.8318 16.9847 20.7354 17.0893C20.6263 17.2077 20.4766 17.2909 20.177 17.4573L18.75 18.2501M9.75 10.7501L12 12.0001M12 12.0001L14.25 10.7501M12 12.0001V14.5001M3 7.00008L5.25 8.25008M18.75 8.25008L21 7.00008M12 19.5001V22.0001" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
`;
}
function cube02Icon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M12 2.50008V12.0001M12 12.0001L20.5 7.27779M12 12.0001L3.5 7.27779M12 12.0001V21.5001M20.5 16.7223L12.777 12.4318C12.4934 12.2742 12.3516 12.1954 12.2015 12.1645C12.0685 12.1372 11.9315 12.1372 11.7986 12.1645C11.6484 12.1954 11.5066 12.2742 11.223 12.4318L3.5 16.7223M21 16.0586V7.94153C21 7.59889 21 7.42757 20.9495 7.27477C20.9049 7.13959 20.8318 7.01551 20.7354 6.91082C20.6263 6.79248 20.4766 6.70928 20.177 6.54288L12.777 2.43177C12.4934 2.27421 12.3516 2.19543 12.2015 2.16454C12.0685 2.13721 11.9315 2.13721 11.7986 2.16454C11.6484 2.19543 11.5066 2.27421 11.223 2.43177L3.82297 6.54288C3.52345 6.70928 3.37369 6.79248 3.26463 6.91082C3.16816 7.01551 3.09515 7.13959 3.05048 7.27477C3 7.42757 3 7.59889 3 7.94153V16.0586C3 16.4013 3 16.5726 3.05048 16.7254C3.09515 16.8606 3.16816 16.9847 3.26463 17.0893C3.37369 17.2077 3.52345 17.2909 3.82297 17.4573L11.223 21.5684C11.5066 21.726 11.6484 21.8047 11.7986 21.8356C11.9315 21.863 12.0685 21.863 12.2015 21.8356C12.3516 21.8047 12.4934 21.726 12.777 21.5684L20.177 17.4573C20.4766 17.2909 20.6263 17.2077 20.7354 17.0893C20.8318 16.9847 20.9049 16.8606 20.9495 16.7254C21 16.5726 21 16.4013 21 16.0586Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
`;
}
function cube01Icon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M20.5 7.27783L12 12.0001M12 12.0001L3.49997 7.27783M12 12.0001L12 21.5001M21 16.0586V7.94153C21 7.59889 21 7.42757 20.9495 7.27477C20.9049 7.13959 20.8318 7.01551 20.7354 6.91082C20.6263 6.79248 20.4766 6.70928 20.177 6.54288L12.777 2.43177C12.4934 2.27421 12.3516 2.19543 12.2015 2.16454C12.0685 2.13721 11.9315 2.13721 11.7986 2.16454C11.6484 2.19543 11.5066 2.27421 11.223 2.43177L3.82297 6.54288C3.52345 6.70928 3.37369 6.79248 3.26463 6.91082C3.16816 7.01551 3.09515 7.13959 3.05048 7.27477C3 7.42757 3 7.59889 3 7.94153V16.0586C3 16.4013 3 16.5726 3.05048 16.7254C3.09515 16.8606 3.16816 16.9847 3.26463 17.0893C3.37369 17.2077 3.52345 17.2909 3.82297 17.4573L11.223 21.5684C11.5066 21.726 11.6484 21.8047 11.7986 21.8356C11.9315 21.863 12.0685 21.863 12.2015 21.8356C12.3516 21.8047 12.4934 21.726 12.777 21.5684L20.177 17.4573C20.4766 17.2909 20.6263 17.2077 20.7354 17.0893C20.8318 16.9847 20.9049 16.8606 20.9495 16.7254C21 16.5726 21 16.4013 21 16.0586Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>

  `;
}
function tuistIcon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M21 16V7.2C21 6.0799 21 5.51984 20.782 5.09202C20.5903 4.71569 20.2843 4.40973 19.908 4.21799C19.4802 4 18.9201 4 17.8 4H6.2C5.07989 4 4.51984 4 4.09202 4.21799C3.71569 4.40973 3.40973 4.71569 3.21799 5.09202C3 5.51984 3 6.0799 3 7.2V16M4.66667 20H19.3333C19.9533 20 20.2633 20 20.5176 19.9319C21.2078 19.7469 21.7469 19.2078 21.9319 18.5176C22 18.2633 22 17.9533 22 17.3333C22 17.0233 22 16.8683 21.9659 16.7412C21.8735 16.3961 21.6039 16.1265 21.2588 16.0341C21.1317 16 20.9767 16 20.6667 16H3.33333C3.02334 16 2.86835 16 2.74118 16.0341C2.39609 16.1265 2.12654 16.3961 2.03407 16.7412C2 16.8683 2 17.0233 2 17.3333C2 17.9533 2 18.2633 2.06815 18.5176C2.25308 19.2078 2.79218 19.7469 3.48236 19.9319C3.73669 20 4.04669 20 4.66667 20Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;
}
function server04Icon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M22 10.5L21.5256 6.70463C21.3395 5.21602 21.2465 4.47169 20.8961 3.9108C20.5875 3.41662 20.1416 3.02301 19.613 2.77804C19.013 2.5 18.2629 2.5 16.7626 2.5H7.23735C5.73714 2.5 4.98704 2.5 4.38702 2.77804C3.85838 3.02301 3.4125 3.41662 3.10386 3.9108C2.75354 4.47169 2.6605 5.21601 2.47442 6.70463L2 10.5M5.5 14.5H18.5M5.5 14.5C3.567 14.5 2 12.933 2 11C2 9.067 3.567 7.5 5.5 7.5H18.5C20.433 7.5 22 9.067 22 11C22 12.933 20.433 14.5 18.5 14.5M5.5 14.5C3.567 14.5 2 16.067 2 18C2 19.933 3.567 21.5 5.5 21.5H18.5C20.433 21.5 22 19.933 22 18C22 16.067 20.433 14.5 18.5 14.5M6 11H6.01M6 18H6.01M12 11H18M12 18H18" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
`;
}
function building07Icon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M7.5 11H4.6C4.03995 11 3.75992 11 3.54601 11.109C3.35785 11.2049 3.20487 11.3578 3.10899 11.546C3 11.7599 3 12.0399 3 12.6V21M16.5 11H19.4C19.9601 11 20.2401 11 20.454 11.109C20.6422 11.2049 20.7951 11.3578 20.891 11.546C21 11.7599 21 12.0399 21 12.6V21M16.5 21V6.2C16.5 5.0799 16.5 4.51984 16.282 4.09202C16.0903 3.71569 15.7843 3.40973 15.408 3.21799C14.9802 3 14.4201 3 13.3 3H10.7C9.57989 3 9.01984 3 8.59202 3.21799C8.21569 3.40973 7.90973 3.71569 7.71799 4.09202C7.5 4.51984 7.5 5.0799 7.5 6.2V21M22 21H2M11 7H13M11 11H13M11 15H13" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>
`;
}
function bookOpen01Icon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M12 21L11.8999 20.8499C11.2053 19.808 10.858 19.287 10.3991 18.9098C9.99286 18.5759 9.52476 18.3254 9.02161 18.1726C8.45325 18 7.82711 18 6.57482 18H5.2C4.07989 18 3.51984 18 3.09202 17.782C2.71569 17.5903 2.40973 17.2843 2.21799 16.908C2 16.4802 2 15.9201 2 14.8V6.2C2 5.07989 2 4.51984 2.21799 4.09202C2.40973 3.71569 2.71569 3.40973 3.09202 3.21799C3.51984 3 4.07989 3 5.2 3H5.6C7.84021 3 8.96031 3 9.81596 3.43597C10.5686 3.81947 11.1805 4.43139 11.564 5.18404C12 6.03968 12 7.15979 12 9.4M12 21V9.4M12 21L12.1001 20.8499C12.7947 19.808 13.142 19.287 13.6009 18.9098C14.0071 18.5759 14.4752 18.3254 14.9784 18.1726C15.5467 18 16.1729 18 17.4252 18H18.8C19.9201 18 20.4802 18 20.908 17.782C21.2843 17.5903 21.5903 17.2843 21.782 16.908C22 16.4802 22 15.9201 22 14.8V6.2C22 5.07989 22 4.51984 21.782 4.09202C21.5903 3.71569 21.2843 3.40973 20.908 3.21799C20.4802 3 19.9201 3 18.8 3H18.4C16.1598 3 15.0397 3 14.184 3.43597C13.4314 3.81947 12.8195 4.43139 12.436 5.18404C12 6.03968 12 7.15979 12 9.4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>
`;
}
function codeBrowserIcon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M22 9H2M14 17.5L16.5 15L14 12.5M10 12.5L7.5 15L10 17.5M2 7.8L2 16.2C2 17.8802 2 18.7202 2.32698 19.362C2.6146 19.9265 3.07354 20.3854 3.63803 20.673C4.27976 21 5.11984 21 6.8 21H17.2C18.8802 21 19.7202 21 20.362 20.673C20.9265 20.3854 21.3854 19.9265 21.673 19.362C22 18.7202 22 17.8802 22 16.2V7.8C22 6.11984 22 5.27977 21.673 4.63803C21.3854 4.07354 20.9265 3.6146 20.362 3.32698C19.7202 3 18.8802 3 17.2 3L6.8 3C5.11984 3 4.27976 3 3.63803 3.32698C3.07354 3.6146 2.6146 4.07354 2.32698 4.63803C2 5.27976 2 6.11984 2 7.8Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>
`;
}

// .vitepress/data/examples.js
import * as path from "node:path";
import fg from "file:///Users/pepicrft/src/github.com/tuist/tuist/docs/node_modules/.pnpm/fast-glob@3.3.2/node_modules/fast-glob/out/index.js";
import fs from "node:fs";
var __vite_injected_original_dirname = "/Users/pepicrft/src/github.com/tuist/tuist/docs/.vitepress/data";
var glob = path.join(__vite_injected_original_dirname, "../../../fixtures/*/README.md");
async function loadData(files) {
  if (!files) {
    files = fg.sync(glob, {
      absolute: true
    }).sort();
  }
  return files.map((file) => {
    const content = fs.readFileSync(file, "utf-8");
    const titleRegex = /^#\s*(.+)/m;
    const titleMatch = content.match(titleRegex);
    return {
      title: titleMatch[1],
      name: path.basename(path.dirname(file)).toLowerCase(),
      content,
      url: `https://github.com/tuist/tuist/tree/main/fixtures/${path.basename(
        path.dirname(file)
      )}`
    };
  });
}

// .vitepress/data/project-description.js
import * as path2 from "node:path";
import fg2 from "file:///Users/pepicrft/src/github.com/tuist/tuist/docs/node_modules/.pnpm/fast-glob@3.3.2/node_modules/fast-glob/out/index.js";
import fs2 from "node:fs";
var __vite_injected_original_dirname2 = "/Users/pepicrft/src/github.com/tuist/tuist/docs/.vitepress/data";
async function loadData2(locale) {
  const generatedDirectory = path2.join(
    __vite_injected_original_dirname2,
    "../../docs/generated/manifest"
  );
  const files = fg2.sync("**/*.md", {
    cwd: generatedDirectory,
    absolute: true,
    ignore: ["**/README.md"]
  }).sort();
  return files.map((file) => {
    const category = path2.basename(path2.dirname(file));
    const fileName = path2.basename(file).replace(".md", "");
    return {
      category,
      title: fileName,
      name: fileName.toLowerCase(),
      identifier: category + "/" + fileName.toLowerCase(),
      description: "",
      content: fs2.readFileSync(file, "utf-8")
    };
  });
}

// .vitepress/bars.mjs
async function projectDescriptionSidebar(locale) {
  const projectDescriptionTypesData = await loadData2();
  const projectDescriptionSidebar2 = {
    text: "Project Description",
    collapsed: true,
    items: []
  };
  function capitalize(text) {
    return text.charAt(0).toUpperCase() + text.slice(1).toLowerCase();
  }
  ["structs", "enums", "extensions", "typealiases"].forEach((category) => {
    if (projectDescriptionTypesData.find((item) => item.category === category)) {
      projectDescriptionSidebar2.items.push({
        text: capitalize(category),
        collapsed: true,
        items: projectDescriptionTypesData.filter((item) => item.category === category).map((item) => ({
          text: item.title,
          link: `/${locale}/references/project-description/${item.identifier}`
        }))
      });
    }
  });
  return projectDescriptionSidebar2;
}
async function referencesSidebar(locale) {
  return [
    {
      text: localizedString(locale, "sidebars.references.text"),
      items: [
        await projectDescriptionSidebar(locale),
        {
          text: localizedString(
            locale,
            "sidebars.references.items.examples.text"
          ),
          collapsed: true,
          items: (await loadData()).map((item) => {
            return {
              text: item.title,
              link: `/${locale}/references/examples/${item.name}`
            };
          })
        },
        {
          text: localizedString(
            locale,
            "sidebars.references.items.migrations.text"
          ),
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.references.items.migrations.items.from-v3-to-v4.text"
              ),
              link: `/${locale}/references/migrations/from-v3-to-v4`
            }
          ]
        }
      ]
    }
  ];
}
function navBar(locale) {
  return [
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "navbar.guides.text"
      )} ${bookOpen01Icon()}</span>`,
      link: `/${locale}/`
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "navbar.cli.text"
      )} ${codeBrowserIcon()}</span>`,
      link: `/${locale}/cli/auth`
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "navbar.server.text"
      )} ${server04Icon()}</span>`,
      link: `/${locale}/server/introduction/why-a-server`
    },
    {
      text: localizedString(locale, "navbar.resources.text"),
      items: [
        {
          text: localizedString(
            locale,
            "navbar.resources.items.references.text"
          ),
          link: `/${locale}/references/project-description/structs/project`
        },
        {
          text: localizedString(
            locale,
            "navbar.resources.items.contributors.text"
          ),
          link: `/${locale}/contributors/get-started`
        },
        {
          text: localizedString(
            locale,
            "navbar.resources.items.changelog.text"
          ),
          link: "https://github.com/tuist/tuist/releases"
        }
      ]
    }
  ];
}
function contributorsSidebar(locale) {
  return [
    {
      text: localizedString(locale, "sidebars.contributors.text"),
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.contributors.items.get-started.text"
          ),
          link: `/${locale}/contributors/get-started`
        },
        {
          text: localizedString(
            locale,
            "sidebars.contributors.items.issue-reporting.text"
          ),
          link: `/${locale}/contributors/issue-reporting`
        },
        {
          text: localizedString(
            locale,
            "sidebars.contributors.items.code-reviews.text"
          ),
          link: `/${locale}/contributors/code-reviews`
        },
        {
          text: localizedString(
            locale,
            "sidebars.contributors.items.principles.text"
          ),
          link: `/${locale}/contributors/principles`
        },
        {
          text: localizedString(
            locale,
            "sidebars.contributors.items.translate.text"
          ),
          link: `/${locale}/contributors/translate`
        }
      ]
    }
  ];
}
function serverSidebar(locale) {
  return [
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.server.items.introduction.text"
      )} ${server04Icon()}</span>`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.server.items.introduction.items.why-server.text"
          ),
          link: `/${locale}/server/introduction/why-a-server`
        },
        {
          text: localizedString(
            locale,
            "sidebars.server.items.introduction.items.accounts-and-projects.text"
          ),
          link: `/${locale}/server/introduction/accounts-and-projects`
        },
        {
          text: localizedString(
            locale,
            "sidebars.server.items.introduction.items.authentication.text"
          ),
          link: `/${locale}/server/introduction/authentication`
        },
        {
          text: localizedString(
            locale,
            "sidebars.server.items.introduction.items.integrations.text"
          ),
          link: `/${locale}/server/introduction/integrations`
        }
      ]
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.server.items.on-premise.text"
      )} ${building07Icon()}</span>`,
      collapsed: true,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.server.items.on-premise.items.install.text"
          ),
          link: `/${locale}/server/on-premise/install`
        },
        {
          text: localizedString(
            locale,
            "sidebars.server.items.on-premise.items.metrics.text"
          ),
          link: `/${locale}/server/on-premise/metrics`
        }
      ]
    },
    {
      text: localizedString(
        locale,
        "sidebars.server.items.api-documentation.text"
      ),
      link: "https://tuist.dev/api/docs"
    },
    {
      text: localizedString(locale, "sidebars.server.items.status.text"),
      link: "https://status.tuist.io"
    },
    {
      text: localizedString(
        locale,
        "sidebars.server.items.metrics-dashboard.text"
      ),
      link: "https://tuist.grafana.net/public-dashboards/1f85f1c3895e48febd02cc7350ade2d9"
    }
  ];
}
function guidesSidebar(locale) {
  return [
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.guides.items.quick-start.text"
      )} ${tuistIcon()}</span>`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.quick-start.items.install-tuist.text"
          ),
          link: `/${locale}/guides/quick-start/install-tuist`
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.quick-start.items.create-a-project.text"
          ),
          link: `/${locale}/guides/quick-start/create-a-project`
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.quick-start.items.add-dependencies.text"
          ),
          link: `/${locale}/guides/quick-start/add-dependencies`
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.quick-start.items.gather-insights.text"
          ),
          link: `/${locale}/guides/quick-start/gather-insights`
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.quick-start.items.optimize-workflows.text"
          ),
          link: `/${locale}/guides/quick-start/optimize-workflows`
        }
      ]
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.guides.items.start.text"
      )} ${cubeOutlineIcon()}</span>`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.start.items.new-project.text"
          ),
          link: `/${locale}/guides/start/new-project`
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.start.items.swift-package.text"
          ),
          link: `/${locale}/guides/start/swift-package`
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.start.items.migrate.text"
          ),
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.start.items.migrate.items.xcode-project.text"
              ),
              link: `/${locale}/guides/start/migrate/xcode-project`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.start.items.migrate.items.swift-package.text"
              ),
              link: `/${locale}/guides/start/migrate/swift-package`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.start.items.migrate.items.xcodegen-project.text"
              ),
              link: `/${locale}/guides/start/migrate/xcodegen-project`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.start.items.migrate.items.bazel-project.text"
              ),
              link: `/${locale}/guides/start/migrate/bazel-project`
            }
          ]
        }
      ]
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.guides.items.develop.text"
      )} ${cube02Icon()}</span>`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.projects.text"
          ),
          collapsed: true,
          link: `/${locale}/guides/develop/projects`,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.manifests.text"
              ),
              link: `/${locale}/guides/develop/projects/manifests`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.directory-structure.text"
              ),
              link: `/${locale}/guides/develop/projects/directory-structure`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.editing.text"
              ),
              link: `/${locale}/guides/develop/projects/editing`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.dependencies.text"
              ),
              link: `/${locale}/guides/develop/projects/dependencies`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.code-sharing.text"
              ),
              link: `/${locale}/guides/develop/projects/code-sharing`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.synthesized-files.text"
              ),
              link: `/${locale}/guides/develop/projects/synthesized-files`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.dynamic-configuration.text"
              ),
              link: `/${locale}/guides/develop/projects/dynamic-configuration`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.templates.text"
              ),
              link: `/${locale}/guides/develop/projects/templates`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.plugins.text"
              ),
              link: `/${locale}/guides/develop/projects/plugins`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.hashing.text"
              ),
              link: `/${locale}/guides/develop/projects/hashing`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.the-cost-of-convenience.text"
              ),
              link: `/${locale}/guides/develop/projects/cost-of-convenience`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.tma-architecture.text"
              ),
              link: `/${locale}/guides/develop/projects/tma-architecture`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.best-practices.text"
              ),
              link: `/${locale}/guides/develop/projects/best-practices`
            }
          ]
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.build.text"
          ),
          link: `/${locale}/guides/develop/build`,
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.build.items.cache.text"
              ),
              link: `/${locale}/guides/develop/build/cache`
            },
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
                locale,
                "sidebars.guides.items.develop.items.build.items.registry.text"
              )} ${xcodeProjCompatibleBadge(locale)}</span>`,
              link: `/${locale}/guides/develop/build/registry`
            }
          ]
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.test.text"
          ),
          link: `/${locale}/guides/develop/test`,
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.test.items.selective-testing.text"
              ),
              link: `/${locale}/guides/develop/test/selective-testing`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.test.items.flakiness.text"
              ),
              link: `/${locale}/guides/develop/test/flakiness`
            }
          ]
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.inspect.text"
          ),
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.inspect.items.implicit-imports.text"
              ),
              link: `/${locale}/guides/develop/inspect/implicit-dependencies`
            }
          ]
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.automate.text"
          ),
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.automate.items.continuous-integration.text"
              ),
              link: `/${locale}/guides/develop/automate/continuous-integration`
            },
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
                locale,
                "sidebars.guides.items.develop.items.automate.items.workflows.text"
              )}</span>`,
              link: `/${locale}/guides/develop/automate/workflows`
            }
          ]
        }
      ]
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.guides.items.share.text"
      )} ${cube01Icon()}</span>`,
      items: [
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
            locale,
            "sidebars.guides.items.share.items.previews.text"
          )} ${xcodeProjCompatibleBadge(locale)}</span>`,
          link: `/${locale}/guides/share/previews`
        }
      ]
    }
  ];
}

// .vitepress/data/cli.js
import { execa, $ } from "file:///Users/pepicrft/src/github.com/tuist/tuist/docs/node_modules/.pnpm/execa@9.3.1/node_modules/execa/index.js";
import { temporaryDirectoryTask } from "file:///Users/pepicrft/src/github.com/tuist/tuist/docs/node_modules/.pnpm/tempy@3.1.0/node_modules/tempy/index.js";
import * as path3 from "node:path";
import { fileURLToPath } from "node:url";
import ejs from "file:///Users/pepicrft/src/github.com/tuist/tuist/docs/node_modules/.pnpm/ejs@3.1.10/node_modules/ejs/lib/ejs.js";
var __vite_injected_original_import_meta_url = "file:///Users/pepicrft/src/github.com/tuist/tuist/docs/.vitepress/data/cli.js";
var __dirname = path3.dirname(fileURLToPath(__vite_injected_original_import_meta_url));
var rootDirectory = path3.join(__dirname, "../../..");
await execa({
  stdio: "inherit"
})`swift build --product ProjectDescription --configuration debug --package-path ${rootDirectory}`;
await execa({
  stdio: "inherit"
})`swift build --product tuist --configuration debug --package-path ${rootDirectory}`;
var dumpedCLISchema;
await temporaryDirectoryTask(async (tmpDir) => {
  dumpedCLISchema = await $`${path3.join(
    rootDirectory,
    ".build/debug/tuist"
  )} --experimental-dump-help --path ${tmpDir}`;
});
var { stdout } = dumpedCLISchema;
var schema = JSON.parse(stdout);
var template = ejs.compile(
  `
# <%= command.fullCommand %>
<%= command.spec.abstract %>
<% if (command.spec.arguments && command.spec.arguments.length > 0) { %>
## Arguments
<% command.spec.arguments.forEach(function(arg) { %>
### <%- arg.valueName %> <%- (arg.isOptional) ? "<Badge type='info' text='Optional' />" : "" %> <%- (arg.isDeprecated) ? "<Badge type='warning' text='Deprecated' />" : "" %>
<% if (arg.envVar) { %>
**Environment variable** \`<%- arg.envVar %>\`
<% } %>
<%- arg.abstract %>
<% if (arg.kind === "positional") { -%>
\`\`\`bash
<%- command.fullCommand %> [<%- arg.valueName %>]
\`\`\`
<% } else if (arg.kind === "flag") { -%>
\`\`\`bash
<% arg.names.forEach(function(name) { -%>
<% if (name.kind === "long") { -%>
<%- command.fullCommand %> --<%- name.name %>
<% } else { -%>
<%- command.fullCommand %> -<%- name.name %>
<% } -%>
<% }) -%>
\`\`\`
<% } else if (arg.kind === "option") { -%>
\`\`\`bash
<% arg.names.forEach(function(name) { -%>
<% if (name.kind === "long") { -%>
<%- command.fullCommand %> --<%- name.name %> [<%- arg.valueName %>]
<% } else { -%>
<%- command.fullCommand %> -<%- name.name %> [<%- arg.valueName %>]
<% } -%>
<% }) -%>
\`\`\`
<% } -%>
<% }); -%>
<% } -%>
`,
  {}
);
async function loadData3(locale) {
  function parseCommand(command, parentCommand = "tuist", parentPath = `/${locale}/cli/`) {
    const output = {
      text: command.commandName,
      fullCommand: parentCommand + " " + command.commandName,
      link: path3.join(parentPath, command.commandName),
      spec: command
    };
    if (command.subcommands && command.subcommands.length !== 0) {
      output.items = command.subcommands.map((subcommand) => {
        return parseCommand(
          subcommand,
          parentCommand + " " + command.commandName,
          path3.join(parentPath, command.commandName)
        );
      });
    }
    return output;
  }
  const {
    command: { subcommands }
  } = schema;
  return {
    text: localizedString(locale, "sidebars.cli.text"),
    items: [
      {
        text: localizedString(locale, "sidebars.cli.items.commands.text"),
        items: subcommands.map((command) => {
          return {
            ...parseCommand(command),
            collapsed: true
          };
        }).sort((a, b) => a.text.localeCompare(b.text))
      }
    ]
  };
}

// .vitepress/config.mjs
var __vite_injected_original_dirname3 = "/Users/pepicrft/src/github.com/tuist/tuist/docs/.vitepress";
async function themeConfig(locale) {
  const sidebar = {};
  sidebar[`/${locale}/contributors`] = contributorsSidebar(locale);
  sidebar[`/${locale}/guides/`] = guidesSidebar(locale);
  sidebar[`/${locale}/server/`] = serverSidebar(locale);
  sidebar[`/${locale}/`] = guidesSidebar(locale);
  sidebar[`/${locale}/cli/`] = await loadData3(locale);
  sidebar[`/${locale}/references/`] = await referencesSidebar(locale);
  return {
    nav: navBar(locale),
    sidebar
  };
}
function getSearchOptionsForLocale(locale) {
  return {
    placeholder: localizedString(locale, "search.placeholder"),
    translations: {
      button: {
        buttonText: localizedString(
          locale,
          "search.translations.button.buttonText"
        ),
        buttonAriaLabel: localizedString(
          locale,
          "search.translations.button.buttonAriaLabel"
        )
      },
      modal: {
        searchBox: {
          resetButtonTitle: localizedString(
            locale,
            "search.translations.modal.search-box.reset-button-title"
          ),
          resetButtonAriaLabel: localizedString(
            locale,
            "search.translations.modal.search-box.reset-button-aria-label"
          ),
          cancelButtonText: localizedString(
            locale,
            "search.translations.modal.search-box.cancel-button-text"
          ),
          cancelButtonAriaLabel: localizedString(
            locale,
            "search.translations.modal.search-box.cancel-button-aria-label"
          )
        },
        startScreen: {
          recentSearchesTitle: localizedString(
            locale,
            "search.translations.modal.start-screen.recent-searches-title"
          ),
          noRecentSearchesText: localizedString(
            locale,
            "search.translations.modal.start-screen.no-recent-searches-text"
          ),
          saveRecentSearchButtonTitle: localizedString(
            locale,
            "search.translations.modal.start-screen.save-recent-search-button-title"
          ),
          removeRecentSearchButtonTitle: localizedString(
            locale,
            "search.translations.modal.start-screen.remove-recent-search-button-title"
          ),
          favoriteSearchesTitle: localizedString(
            locale,
            "search.translations.modal.start-screen.favorite-searches-title"
          ),
          removeFavoriteSearchButtonTitle: localizedString(
            locale,
            "search.translations.modal.start-screen.remove-favorite-search-button-title"
          )
        },
        errorScreen: {
          titleText: localizedString(
            locale,
            "search.translations.modal.error-screen.title-text"
          ),
          helpText: localizedString(
            locale,
            "search.translations.modal.error-screen.help-text"
          )
        },
        footer: {
          selectText: localizedString(
            locale,
            "search.translations.modal.footer.select-text"
          ),
          navigateText: localizedString(
            locale,
            "search.translations.modal.footer.navigate-text"
          ),
          closeText: localizedString(
            locale,
            "search.translations.modal.footer.close-text"
          ),
          searchByText: localizedString(
            locale,
            "search.translations.modal.footer.search-by-text"
          )
        },
        noResultsScreen: {
          noResultsText: localizedString(
            locale,
            "search.translations.modal.no-results-screen.no-results-text"
          ),
          suggestedQueryText: localizedString(
            locale,
            "search.translations.modal.no-results-screen.suggested-query-text"
          ),
          reportMissingResultsText: localizedString(
            locale,
            "search.translations.modal.no-results-screen.report-missing-results-text"
          ),
          reportMissingResultsLinkText: localizedString(
            locale,
            "search.translations.modal.no-results-screen.report-missing-results-link-text"
          )
        }
      }
    }
  };
}
var searchOptionsLocales = {
  en: getSearchOptionsForLocale("en"),
  ko: getSearchOptionsForLocale("ko"),
  ja: getSearchOptionsForLocale("ja"),
  ru: getSearchOptionsForLocale("ru"),
  es: getSearchOptionsForLocale("es")
};
var config_default = defineConfig({
  title: "Tuist",
  titleTemplate: ":title | Tuist",
  description: "Scale your Xcode app development",
  srcDir: "docs",
  lastUpdated: false,
  locales: {
    en: {
      label: "English",
      lang: "en",
      themeConfig: await themeConfig("en")
    },
    ko: {
      label: "\uD55C\uAD6D\uC5B4 (Korean)",
      lang: "ko",
      themeConfig: await themeConfig("ko")
    },
    ja: {
      label: "\u65E5\u672C\u8A9E (Japanese)",
      lang: "ja",
      themeConfig: await themeConfig("ja")
    },
    ru: {
      label: "\u0420\u0443\u0441\u0441\u043A\u0438\u0439 (Russian)",
      lang: "ru",
      themeConfig: await themeConfig("ru")
    },
    es: {
      label: "Castellano (Spanish)",
      lang: "es",
      themeConfig: await themeConfig("es")
    },
    pt: {
      label: "Portugu\xEAs (Portuguese)",
      lang: "pt",
      themeConfig: await themeConfig("pt")
    }
  },
  cleanUrls: true,
  head: [
    [
      "script",
      {},
      `
      !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="capture identify alias people.set people.set_once set_config register register_once unregister opt_out_capturing has_opted_out_capturing opt_in_capturing reset isFeatureEnabled onFeatureFlags getFeatureFlag getFeatureFlagPayload reloadFeatureFlags group updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures getActiveMatchingSurveys getSurveys onSessionId".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
      posthog.init('phc_stva6NJi8LG6EmR6RA6uQcRdrmfTQcAVLoO3vGgWmNZ',{api_host:'https://eu.i.posthog.com'})
    `
    ],
    [
      "script",
      {},
      `
      !function(t){if(window.ko)return;window.ko=[],["identify","track","removeListeners","open","on","off","qualify","ready"].forEach(function(t){ko[t]=function(){var n=[].slice.call(arguments);return n.unshift(t),ko.push(n),ko}});var n=document.createElement("script");n.async=!0,n.setAttribute("src","https://cdn.getkoala.com/v1/pk_3f80a3529ec2914b714a3f740d10b12642b9/sdk.js"),(document.body || document.head).appendChild(n)}();
    `
    ],
    ["meta", { property: "og:url", content: "https://docs.tuist.io" }, ""],
    ["meta", { property: "og:type", content: "website" }, ""],
    [
      "meta",
      { property: "og:image", content: "https://docs.tuist.io/images/og.jpeg" },
      ""
    ],
    ["meta", { name: "twitter:card", content: "summary" }, ""],
    ["meta", { property: "twitter:domain", content: "docs.tuist.io" }, ""],
    ["meta", { property: "twitter:url", content: "https://docs.tuist.io" }, ""],
    [
      "meta",
      {
        name: "twitter:image",
        content: "https://docs.tuist.io/images/og.jpeg"
      },
      ""
    ]
  ],
  sitemap: {
    hostname: "https://docs.tuist.io"
  },
  async buildEnd({ outDir }) {
    const redirectsPath = path4.join(outDir, "_redirects");
    const redirects = `
/documentation/tuist/installation /guide/introduction/installation 301
/documentation/tuist/project-structure /guide/project/directory-structure 301
/documentation/tuist/command-line-interface /guide/automation/generate 301
/documentation/tuist/dependencies /guide/project/dependencies 301
/documentation/tuist/sharing-code-across-manifests /guide/project/code-sharing 301
/documentation/tuist/synthesized-files /guide/project/synthesized-files 301
/documentation/tuist/migration-guidelines /guide/introduction/adopting-tuist/migrate-from-xcodeproj 301
/tutorials/tuist-tutorials /guide/introduction/adopting-tuist/new-project 301
/tutorials/tuist/install  /guide/introduction/adopting-tuist/new-project 301
/tutorials/tuist/create-project  /guide/introduction/adopting-tuist/new-project 301
/tutorials/tuist/external-dependencies /guide/introduction/adopting-tuist/new-project 301
/documentation/tuist/generation-environment /guide/project/dynamic-configuration 301
/documentation/tuist/using-plugins /guide/project/plugins 301
/documentation/tuist/creating-plugins /guide/project/plugins 301
/documentation/tuist/task /guide/project/plugins 301
/documentation/tuist/tuist-cloud /cloud/what-is-cloud 301
/documentation/tuist/tuist-cloud-get-started /cloud/get-started 301
/documentation/tuist/binary-caching /cloud/binary-caching 301
/documentation/tuist/selective-testing /cloud/selective-testing 301
/tutorials/tuist-cloud-tutorials /cloud/on-premise 301
/tutorials/tuist/enterprise-infrastructure-requirements /cloud/on-premise 301
/tutorials/tuist/enterprise-environment /cloud/on-premise 301
/tutorials/tuist/enterprise-deployment /cloud/on-premise 301
/documentation/tuist/get-started-as-contributor /contributors/get-started 301
/documentation/tuist/manifesto /contributors/principles 301
/documentation/tuist/code-reviews /contributors/code-reviews 301
/documentation/tuist/reporting-bugs /contributors/issue-reporting 301
/documentation/tuist/championing-projects /contributors/get-started 301
/guide/scale/ufeatures-architecture.html /guide/scale/tma-architecture.html 301
/guide/scale/ufeatures-architecture /guide/scale/tma-architecture 301
/guide/introduction/cost-of-convenience /guides/develop/projects/cost-of-convenience 301
/guide/introduction/installation /guides/quick-start/install-tuist 301
/guide/introduction/adopting-tuist/new-project /guides/start/new-project 301
/guide/introduction/adopting-tuist/swift-package /guides/start/swift-package 301
/guide/introduction/adopting-tuist/migrate-from-xcodeproj /guides/start/migrate/xcode-project 301
/guide/introduction/adopting-tuist/migrate-local-swift-packages /guides/start/migrate/swift-package 301
/guide/introduction/adopting-tuist/migrate-from-xcodegen /guides/start/migrate/xcodegen-project 301
/guide/introduction/adopting-tuist/migrate-from-bazel /guides/start/migrate/bazel-project 301
/guide/introduction/from-v3-to-v4 /references/migrations/from-v3-to-v4 301
/guide/project/manifests /guides/develop/projects/manifests 301
/guide/project/directory-structure /guides/develop/projects/directory-structure 301
/guide/project/editing /guides/develop/projects/editing 301
/guide/project/dependencies /guides/develop/projects/dependencies 301
/guide/project/code-sharing /guides/develop/projects/code-sharing 301
/guide/project/synthesized-files /guides/develop/projects/synthesized-files 301
/guide/project/dynamic-configuration /guides/develop/projects/dynamic-configuration 301
/guide/project/templates /guides/develop/projects/templates 301
/guide/project/plugins /guides/develop/projects/plugins 301
/guide/automation/generate / 301
/guide/automation/build /guides/develop/build 301
/guide/automation/test /guides/develop/test 301
/guide/automation/run / 301
/guide/automation/graph / 301
/guide/automation/clean / 301
/guide/scale/tma-architecture /guides/develop/projects/tma-architecture 301
/cloud/what-is-cloud / 301
/cloud/get-started / 301
/cloud/binary-caching /guides/develop/build/cache 301
/cloud/selective-testing /guides/develop/test/smart-runner 301
/cloud/hashing /guides/develop/projects/hashing 301
/cloud/on-premise /guides/dashboard/on-premise/install 301
/cloud/on-premise/metrics /guides/dashboard/on-premise/metrics 301
/reference/project-description/* /references/project-description/:splat 301
/reference/examples/* /references/examples/:splat 301
/guides/develop/workflows /guides/develop/continuous-integration/workflows 301
/guides/dashboard/on-premise/install /server/on-premise/install 301
/guides/dashboard/on-premise/metrics /server/on-premise/metrics 301
/:locale/references/project-description/structs/config /:locale/references/project-description/structs/tuist  301
/:locale/guides/develop/test/smart-runner /:locale/guides/develop/test/selective-testing 301
/documentation/tuist/* / 301
${await fs3.readFile(path4.join(__vite_injected_original_dirname3, "locale-redirects.txt"), {
      encoding: "utf-8"
    })}
    `;
    fs3.writeFile(redirectsPath, redirects);
  },
  themeConfig: {
    logo: "/logo.png",
    search: {
      provider: "algolia",
      options: {
        appId: "5A3L9HI9VQ",
        apiKey: "cd45f515fb1fbb720d633cb0f1257e7a",
        indexName: "tuist",
        locales: searchOptionsLocales,
        startUrls: ["https://tuist.dev/"],
        renderJavaScript: false,
        sitemaps: [],
        exclusionPatterns: [],
        ignoreCanonicalTo: false,
        discoveryPatterns: ["https://tuist.dev/**"],
        schedule: "at 05:10 on Saturday",
        actions: [
          {
            indexName: "tuist",
            pathsToMatch: ["https://tuist.dev/**"],
            recordExtractor: ({ $: $2, helpers }) => {
              return helpers.docsearch({
                recordProps: {
                  lvl1: ".content h1",
                  content: ".content p, .content li",
                  lvl0: {
                    selectors: "section.has-active div h2",
                    defaultValue: "Documentation"
                  },
                  lvl2: ".content h2",
                  lvl3: ".content h3",
                  lvl4: ".content h4",
                  lvl5: ".content h5"
                },
                indexHeadings: true
              });
            }
          }
        ],
        initialIndexSettings: {
          vitepress: {
            attributesForFaceting: ["type", "lang"],
            attributesToRetrieve: ["hierarchy", "content", "anchor", "url"],
            attributesToHighlight: ["hierarchy", "hierarchy_camel", "content"],
            attributesToSnippet: ["content:10"],
            camelCaseAttributes: ["hierarchy", "hierarchy_radio", "content"],
            searchableAttributes: [
              "unordered(hierarchy_radio_camel.lvl0)",
              "unordered(hierarchy_radio.lvl0)",
              "unordered(hierarchy_radio_camel.lvl1)",
              "unordered(hierarchy_radio.lvl1)",
              "unordered(hierarchy_radio_camel.lvl2)",
              "unordered(hierarchy_radio.lvl2)",
              "unordered(hierarchy_radio_camel.lvl3)",
              "unordered(hierarchy_radio.lvl3)",
              "unordered(hierarchy_radio_camel.lvl4)",
              "unordered(hierarchy_radio.lvl4)",
              "unordered(hierarchy_radio_camel.lvl5)",
              "unordered(hierarchy_radio.lvl5)",
              "unordered(hierarchy_radio_camel.lvl6)",
              "unordered(hierarchy_radio.lvl6)",
              "unordered(hierarchy_camel.lvl0)",
              "unordered(hierarchy.lvl0)",
              "unordered(hierarchy_camel.lvl1)",
              "unordered(hierarchy.lvl1)",
              "unordered(hierarchy_camel.lvl2)",
              "unordered(hierarchy.lvl2)",
              "unordered(hierarchy_camel.lvl3)",
              "unordered(hierarchy.lvl3)",
              "unordered(hierarchy_camel.lvl4)",
              "unordered(hierarchy.lvl4)",
              "unordered(hierarchy_camel.lvl5)",
              "unordered(hierarchy.lvl5)",
              "unordered(hierarchy_camel.lvl6)",
              "unordered(hierarchy.lvl6)",
              "content"
            ],
            distinct: true,
            attributeForDistinct: "url",
            customRanking: [
              "desc(weight.pageRank)",
              "desc(weight.level)",
              "asc(weight.position)"
            ],
            ranking: [
              "words",
              "filters",
              "typo",
              "attribute",
              "proximity",
              "exact",
              "custom"
            ],
            highlightPreTag: '<span class="algolia-docsearch-suggestion--highlight">',
            highlightPostTag: "</span>",
            minWordSizefor1Typo: 3,
            minWordSizefor2Typos: 7,
            allowTyposOnNumericTokens: false,
            minProximity: 1,
            ignorePlurals: true,
            advancedSyntax: true,
            attributeCriteriaComputedByMinProximity: true,
            removeWordsIfNoResults: "allOptional"
          }
        }
      }
    },
    editLink: {
      pattern: "https://github.com/tuist/tuist/edit/main/docs/docs/:path"
    },
    socialLinks: [
      { icon: "github", link: "https://github.com/tuist/tuist" },
      { icon: "mastodon", link: "https://fosstodon.org/@tuist" },
      { icon: "bluesky", link: "https://bsky.app/profile/tuist.dev" },
      {
        icon: "slack",
        link: "https://join.slack.com/t/tuistapp/shared_invite/zt-1y667mjbk-s2LTRX1YByb9EIITjdLcLw"
      }
    ],
    footer: {
      message: "Released under the MIT License.",
      copyright: "Copyright \xA9 2024-present Tuist GmbH"
    }
  }
});
export {
  config_default as default
};
//# sourceMappingURL=data:application/json;base64,ewogICJ2ZXJzaW9uIjogMywKICAic291cmNlcyI6IFsiLnZpdGVwcmVzcy9jb25maWcubWpzIiwgIi52aXRlcHJlc3Mvc3RyaW5ncy9lbi5qc29uIiwgIi52aXRlcHJlc3Mvc3RyaW5ncy9ydS5qc29uIiwgIi52aXRlcHJlc3Mvc3RyaW5ncy9rby5qc29uIiwgIi52aXRlcHJlc3Mvc3RyaW5ncy9qYS5qc29uIiwgIi52aXRlcHJlc3Mvc3RyaW5ncy9lcy5qc29uIiwgIi52aXRlcHJlc3Mvc3RyaW5ncy9wdC5qc29uIiwgIi52aXRlcHJlc3MvaTE4bi5tanMiLCAiLnZpdGVwcmVzcy9iYWRnZXMubWpzIiwgIi52aXRlcHJlc3MvaWNvbnMubWpzIiwgIi52aXRlcHJlc3MvZGF0YS9leGFtcGxlcy5qcyIsICIudml0ZXByZXNzL2RhdGEvcHJvamVjdC1kZXNjcmlwdGlvbi5qcyIsICIudml0ZXByZXNzL2JhcnMubWpzIiwgIi52aXRlcHJlc3MvZGF0YS9jbGkuanMiXSwKICAic291cmNlc0NvbnRlbnQiOiBbImNvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ZpbGVuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2NvbmZpZy5tanNcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfaW1wb3J0X21ldGFfdXJsID0gXCJmaWxlOi8vL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9jb25maWcubWpzXCI7aW1wb3J0IHsgZGVmaW5lQ29uZmlnIH0gZnJvbSBcInZpdGVwcmVzc1wiO1xuaW1wb3J0ICogYXMgcGF0aCBmcm9tIFwibm9kZTpwYXRoXCI7XG5pbXBvcnQgKiBhcyBmcyBmcm9tIFwibm9kZTpmcy9wcm9taXNlc1wiO1xuaW1wb3J0IHtcbiAgZ3VpZGVzU2lkZWJhcixcbiAgY29udHJpYnV0b3JzU2lkZWJhcixcbiAgcmVmZXJlbmNlc1NpZGViYXIsXG4gIHNlcnZlclNpZGViYXIsXG4gIG5hdkJhcixcbn0gZnJvbSBcIi4vYmFycy5tanNcIjtcbmltcG9ydCB7IGxvYWREYXRhIGFzIGxvYWRDTElEYXRhIH0gZnJvbSBcIi4vZGF0YS9jbGlcIjtcbmltcG9ydCB7IGxvY2FsaXplZFN0cmluZyB9IGZyb20gXCIuL2kxOG4ubWpzXCI7XG5cbmFzeW5jIGZ1bmN0aW9uIHRoZW1lQ29uZmlnKGxvY2FsZSkge1xuICBjb25zdCBzaWRlYmFyID0ge307XG4gIHNpZGViYXJbYC8ke2xvY2FsZX0vY29udHJpYnV0b3JzYF0gPSBjb250cmlidXRvcnNTaWRlYmFyKGxvY2FsZSk7XG4gIHNpZGViYXJbYC8ke2xvY2FsZX0vZ3VpZGVzL2BdID0gZ3VpZGVzU2lkZWJhcihsb2NhbGUpO1xuICBzaWRlYmFyW2AvJHtsb2NhbGV9L3NlcnZlci9gXSA9IHNlcnZlclNpZGViYXIobG9jYWxlKTtcbiAgc2lkZWJhcltgLyR7bG9jYWxlfS9gXSA9IGd1aWRlc1NpZGViYXIobG9jYWxlKTtcbiAgc2lkZWJhcltgLyR7bG9jYWxlfS9jbGkvYF0gPSBhd2FpdCBsb2FkQ0xJRGF0YShsb2NhbGUpO1xuICBzaWRlYmFyW2AvJHtsb2NhbGV9L3JlZmVyZW5jZXMvYF0gPSBhd2FpdCByZWZlcmVuY2VzU2lkZWJhcihsb2NhbGUpO1xuICByZXR1cm4ge1xuICAgIG5hdjogbmF2QmFyKGxvY2FsZSksXG4gICAgc2lkZWJhcixcbiAgfTtcbn1cblxuZnVuY3Rpb24gZ2V0U2VhcmNoT3B0aW9uc0ZvckxvY2FsZShsb2NhbGUpIHtcbiAgcmV0dXJuIHtcbiAgICBwbGFjZWhvbGRlcjogbG9jYWxpemVkU3RyaW5nKGxvY2FsZSwgXCJzZWFyY2gucGxhY2Vob2xkZXJcIiksXG4gICAgdHJhbnNsYXRpb25zOiB7XG4gICAgICBidXR0b246IHtcbiAgICAgICAgYnV0dG9uVGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMuYnV0dG9uLmJ1dHRvblRleHRcIixcbiAgICAgICAgKSxcbiAgICAgICAgYnV0dG9uQXJpYUxhYmVsOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5idXR0b24uYnV0dG9uQXJpYUxhYmVsXCIsXG4gICAgICAgICksXG4gICAgICB9LFxuICAgICAgbW9kYWw6IHtcbiAgICAgICAgc2VhcmNoQm94OiB7XG4gICAgICAgICAgcmVzZXRCdXR0b25UaXRsZTogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLnNlYXJjaC1ib3gucmVzZXQtYnV0dG9uLXRpdGxlXCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICByZXNldEJ1dHRvbkFyaWFMYWJlbDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLnNlYXJjaC1ib3gucmVzZXQtYnV0dG9uLWFyaWEtbGFiZWxcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGNhbmNlbEJ1dHRvblRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5zZWFyY2gtYm94LmNhbmNlbC1idXR0b24tdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgY2FuY2VsQnV0dG9uQXJpYUxhYmVsOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc2VhcmNoLWJveC5jYW5jZWwtYnV0dG9uLWFyaWEtbGFiZWxcIixcbiAgICAgICAgICApLFxuICAgICAgICB9LFxuICAgICAgICBzdGFydFNjcmVlbjoge1xuICAgICAgICAgIHJlY2VudFNlYXJjaGVzVGl0bGU6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5zdGFydC1zY3JlZW4ucmVjZW50LXNlYXJjaGVzLXRpdGxlXCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBub1JlY2VudFNlYXJjaGVzVGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLnN0YXJ0LXNjcmVlbi5uby1yZWNlbnQtc2VhcmNoZXMtdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgc2F2ZVJlY2VudFNlYXJjaEJ1dHRvblRpdGxlOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc3RhcnQtc2NyZWVuLnNhdmUtcmVjZW50LXNlYXJjaC1idXR0b24tdGl0bGVcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIHJlbW92ZVJlY2VudFNlYXJjaEJ1dHRvblRpdGxlOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc3RhcnQtc2NyZWVuLnJlbW92ZS1yZWNlbnQtc2VhcmNoLWJ1dHRvbi10aXRsZVwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgZmF2b3JpdGVTZWFyY2hlc1RpdGxlOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc3RhcnQtc2NyZWVuLmZhdm9yaXRlLXNlYXJjaGVzLXRpdGxlXCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICByZW1vdmVGYXZvcml0ZVNlYXJjaEJ1dHRvblRpdGxlOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc3RhcnQtc2NyZWVuLnJlbW92ZS1mYXZvcml0ZS1zZWFyY2gtYnV0dG9uLXRpdGxlXCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgfSxcbiAgICAgICAgZXJyb3JTY3JlZW46IHtcbiAgICAgICAgICB0aXRsZVRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5lcnJvci1zY3JlZW4udGl0bGUtdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgaGVscFRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5lcnJvci1zY3JlZW4uaGVscC10ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgfSxcbiAgICAgICAgZm9vdGVyOiB7XG4gICAgICAgICAgc2VsZWN0VGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLmZvb3Rlci5zZWxlY3QtdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbmF2aWdhdGVUZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuZm9vdGVyLm5hdmlnYXRlLXRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGNsb3NlVGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLmZvb3Rlci5jbG9zZS10ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBzZWFyY2hCeVRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5mb290ZXIuc2VhcmNoLWJ5LXRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICB9LFxuICAgICAgICBub1Jlc3VsdHNTY3JlZW46IHtcbiAgICAgICAgICBub1Jlc3VsdHNUZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwubm8tcmVzdWx0cy1zY3JlZW4ubm8tcmVzdWx0cy10ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBzdWdnZXN0ZWRRdWVyeVRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5uby1yZXN1bHRzLXNjcmVlbi5zdWdnZXN0ZWQtcXVlcnktdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgcmVwb3J0TWlzc2luZ1Jlc3VsdHNUZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwubm8tcmVzdWx0cy1zY3JlZW4ucmVwb3J0LW1pc3NpbmctcmVzdWx0cy10ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICByZXBvcnRNaXNzaW5nUmVzdWx0c0xpbmtUZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwubm8tcmVzdWx0cy1zY3JlZW4ucmVwb3J0LW1pc3NpbmctcmVzdWx0cy1saW5rLXRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICB9LFxuICAgICAgfSxcbiAgICB9LFxuICB9O1xufVxuXG5jb25zdCBzZWFyY2hPcHRpb25zTG9jYWxlcyA9IHtcbiAgZW46IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJlblwiKSxcbiAga286IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJrb1wiKSxcbiAgamE6IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJqYVwiKSxcbiAgcnU6IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJydVwiKSxcbiAgZXM6IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJlc1wiKSxcbn07XG5cbmV4cG9ydCBkZWZhdWx0IGRlZmluZUNvbmZpZyh7XG4gIHRpdGxlOiBcIlR1aXN0XCIsXG4gIHRpdGxlVGVtcGxhdGU6IFwiOnRpdGxlIHwgVHVpc3RcIixcbiAgZGVzY3JpcHRpb246IFwiU2NhbGUgeW91ciBYY29kZSBhcHAgZGV2ZWxvcG1lbnRcIixcbiAgc3JjRGlyOiBcImRvY3NcIixcbiAgbGFzdFVwZGF0ZWQ6IGZhbHNlLFxuICBsb2NhbGVzOiB7XG4gICAgZW46IHtcbiAgICAgIGxhYmVsOiBcIkVuZ2xpc2hcIixcbiAgICAgIGxhbmc6IFwiZW5cIixcbiAgICAgIHRoZW1lQ29uZmlnOiBhd2FpdCB0aGVtZUNvbmZpZyhcImVuXCIpLFxuICAgIH0sXG4gICAga286IHtcbiAgICAgIGxhYmVsOiBcIlx1RDU1Q1x1QUQ2RFx1QzVCNCAoS29yZWFuKVwiLFxuICAgICAgbGFuZzogXCJrb1wiLFxuICAgICAgdGhlbWVDb25maWc6IGF3YWl0IHRoZW1lQ29uZmlnKFwia29cIiksXG4gICAgfSxcbiAgICBqYToge1xuICAgICAgbGFiZWw6IFwiXHU2NUU1XHU2NzJDXHU4QTlFIChKYXBhbmVzZSlcIixcbiAgICAgIGxhbmc6IFwiamFcIixcbiAgICAgIHRoZW1lQ29uZmlnOiBhd2FpdCB0aGVtZUNvbmZpZyhcImphXCIpLFxuICAgIH0sXG4gICAgcnU6IHtcbiAgICAgIGxhYmVsOiBcIlx1MDQyMFx1MDQ0M1x1MDQ0MVx1MDQ0MVx1MDQzQVx1MDQzOFx1MDQzOSAoUnVzc2lhbilcIixcbiAgICAgIGxhbmc6IFwicnVcIixcbiAgICAgIHRoZW1lQ29uZmlnOiBhd2FpdCB0aGVtZUNvbmZpZyhcInJ1XCIpLFxuICAgIH0sXG4gICAgZXM6IHtcbiAgICAgIGxhYmVsOiBcIkNhc3RlbGxhbm8gKFNwYW5pc2gpXCIsXG4gICAgICBsYW5nOiBcImVzXCIsXG4gICAgICB0aGVtZUNvbmZpZzogYXdhaXQgdGhlbWVDb25maWcoXCJlc1wiKSxcbiAgICB9LFxuICAgIHB0OiB7XG4gICAgICBsYWJlbDogXCJQb3J0dWd1XHUwMEVBcyAoUG9ydHVndWVzZSlcIixcbiAgICAgIGxhbmc6IFwicHRcIixcbiAgICAgIHRoZW1lQ29uZmlnOiBhd2FpdCB0aGVtZUNvbmZpZyhcInB0XCIpLFxuICAgIH0sXG4gIH0sXG4gIGNsZWFuVXJsczogdHJ1ZSxcbiAgaGVhZDogW1xuICAgIFtcbiAgICAgIFwic2NyaXB0XCIsXG4gICAgICB7fSxcbiAgICAgIGBcbiAgICAgICFmdW5jdGlvbih0LGUpe3ZhciBvLG4scCxyO2UuX19TVnx8KHdpbmRvdy5wb3N0aG9nPWUsZS5faT1bXSxlLmluaXQ9ZnVuY3Rpb24oaSxzLGEpe2Z1bmN0aW9uIGcodCxlKXt2YXIgbz1lLnNwbGl0KFwiLlwiKTsyPT1vLmxlbmd0aCYmKHQ9dFtvWzBdXSxlPW9bMV0pLHRbZV09ZnVuY3Rpb24oKXt0LnB1c2goW2VdLmNvbmNhdChBcnJheS5wcm90b3R5cGUuc2xpY2UuY2FsbChhcmd1bWVudHMsMCkpKX19KHA9dC5jcmVhdGVFbGVtZW50KFwic2NyaXB0XCIpKS50eXBlPVwidGV4dC9qYXZhc2NyaXB0XCIscC5hc3luYz0hMCxwLnNyYz1zLmFwaV9ob3N0LnJlcGxhY2UoXCIuaS5wb3N0aG9nLmNvbVwiLFwiLWFzc2V0cy5pLnBvc3Rob2cuY29tXCIpK1wiL3N0YXRpYy9hcnJheS5qc1wiLChyPXQuZ2V0RWxlbWVudHNCeVRhZ05hbWUoXCJzY3JpcHRcIilbMF0pLnBhcmVudE5vZGUuaW5zZXJ0QmVmb3JlKHAscik7dmFyIHU9ZTtmb3Iodm9pZCAwIT09YT91PWVbYV09W106YT1cInBvc3Rob2dcIix1LnBlb3BsZT11LnBlb3BsZXx8W10sdS50b1N0cmluZz1mdW5jdGlvbih0KXt2YXIgZT1cInBvc3Rob2dcIjtyZXR1cm5cInBvc3Rob2dcIiE9PWEmJihlKz1cIi5cIithKSx0fHwoZSs9XCIgKHN0dWIpXCIpLGV9LHUucGVvcGxlLnRvU3RyaW5nPWZ1bmN0aW9uKCl7cmV0dXJuIHUudG9TdHJpbmcoMSkrXCIucGVvcGxlIChzdHViKVwifSxvPVwiY2FwdHVyZSBpZGVudGlmeSBhbGlhcyBwZW9wbGUuc2V0IHBlb3BsZS5zZXRfb25jZSBzZXRfY29uZmlnIHJlZ2lzdGVyIHJlZ2lzdGVyX29uY2UgdW5yZWdpc3RlciBvcHRfb3V0X2NhcHR1cmluZyBoYXNfb3B0ZWRfb3V0X2NhcHR1cmluZyBvcHRfaW5fY2FwdHVyaW5nIHJlc2V0IGlzRmVhdHVyZUVuYWJsZWQgb25GZWF0dXJlRmxhZ3MgZ2V0RmVhdHVyZUZsYWcgZ2V0RmVhdHVyZUZsYWdQYXlsb2FkIHJlbG9hZEZlYXR1cmVGbGFncyBncm91cCB1cGRhdGVFYXJseUFjY2Vzc0ZlYXR1cmVFbnJvbGxtZW50IGdldEVhcmx5QWNjZXNzRmVhdHVyZXMgZ2V0QWN0aXZlTWF0Y2hpbmdTdXJ2ZXlzIGdldFN1cnZleXMgb25TZXNzaW9uSWRcIi5zcGxpdChcIiBcIiksbj0wO248by5sZW5ndGg7bisrKWcodSxvW25dKTtlLl9pLnB1c2goW2kscyxhXSl9LGUuX19TVj0xKX0oZG9jdW1lbnQsd2luZG93LnBvc3Rob2d8fFtdKTtcbiAgICAgIHBvc3Rob2cuaW5pdCgncGhjX3N0dmE2TkppOExHNkVtUjZSQTZ1UWNSZHJtZlRRY0FWTG9PM3ZHZ1dtTlonLHthcGlfaG9zdDonaHR0cHM6Ly9ldS5pLnBvc3Rob2cuY29tJ30pXG4gICAgYCxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwic2NyaXB0XCIsXG4gICAgICB7fSxcbiAgICAgIGBcbiAgICAgICFmdW5jdGlvbih0KXtpZih3aW5kb3cua28pcmV0dXJuO3dpbmRvdy5rbz1bXSxbXCJpZGVudGlmeVwiLFwidHJhY2tcIixcInJlbW92ZUxpc3RlbmVyc1wiLFwib3BlblwiLFwib25cIixcIm9mZlwiLFwicXVhbGlmeVwiLFwicmVhZHlcIl0uZm9yRWFjaChmdW5jdGlvbih0KXtrb1t0XT1mdW5jdGlvbigpe3ZhciBuPVtdLnNsaWNlLmNhbGwoYXJndW1lbnRzKTtyZXR1cm4gbi51bnNoaWZ0KHQpLGtvLnB1c2gobiksa299fSk7dmFyIG49ZG9jdW1lbnQuY3JlYXRlRWxlbWVudChcInNjcmlwdFwiKTtuLmFzeW5jPSEwLG4uc2V0QXR0cmlidXRlKFwic3JjXCIsXCJodHRwczovL2Nkbi5nZXRrb2FsYS5jb20vdjEvcGtfM2Y4MGEzNTI5ZWMyOTE0YjcxNGEzZjc0MGQxMGIxMjY0MmI5L3Nkay5qc1wiKSwoZG9jdW1lbnQuYm9keSB8fCBkb2N1bWVudC5oZWFkKS5hcHBlbmRDaGlsZChuKX0oKTtcbiAgICBgLFxuICAgIF0sXG4gICAgW1wibWV0YVwiLCB7IHByb3BlcnR5OiBcIm9nOnVybFwiLCBjb250ZW50OiBcImh0dHBzOi8vZG9jcy50dWlzdC5pb1wiIH0sIFwiXCJdLFxuICAgIFtcIm1ldGFcIiwgeyBwcm9wZXJ0eTogXCJvZzp0eXBlXCIsIGNvbnRlbnQ6IFwid2Vic2l0ZVwiIH0sIFwiXCJdLFxuICAgIFtcbiAgICAgIFwibWV0YVwiLFxuICAgICAgeyBwcm9wZXJ0eTogXCJvZzppbWFnZVwiLCBjb250ZW50OiBcImh0dHBzOi8vZG9jcy50dWlzdC5pby9pbWFnZXMvb2cuanBlZ1wiIH0sXG4gICAgICBcIlwiLFxuICAgIF0sXG4gICAgW1wibWV0YVwiLCB7IG5hbWU6IFwidHdpdHRlcjpjYXJkXCIsIGNvbnRlbnQ6IFwic3VtbWFyeVwiIH0sIFwiXCJdLFxuICAgIFtcIm1ldGFcIiwgeyBwcm9wZXJ0eTogXCJ0d2l0dGVyOmRvbWFpblwiLCBjb250ZW50OiBcImRvY3MudHVpc3QuaW9cIiB9LCBcIlwiXSxcbiAgICBbXCJtZXRhXCIsIHsgcHJvcGVydHk6IFwidHdpdHRlcjp1cmxcIiwgY29udGVudDogXCJodHRwczovL2RvY3MudHVpc3QuaW9cIiB9LCBcIlwiXSxcbiAgICBbXG4gICAgICBcIm1ldGFcIixcbiAgICAgIHtcbiAgICAgICAgbmFtZTogXCJ0d2l0dGVyOmltYWdlXCIsXG4gICAgICAgIGNvbnRlbnQ6IFwiaHR0cHM6Ly9kb2NzLnR1aXN0LmlvL2ltYWdlcy9vZy5qcGVnXCIsXG4gICAgICB9LFxuICAgICAgXCJcIixcbiAgICBdLFxuICBdLFxuICBzaXRlbWFwOiB7XG4gICAgaG9zdG5hbWU6IFwiaHR0cHM6Ly9kb2NzLnR1aXN0LmlvXCIsXG4gIH0sXG4gIGFzeW5jIGJ1aWxkRW5kKHsgb3V0RGlyIH0pIHtcbiAgICBjb25zdCByZWRpcmVjdHNQYXRoID0gcGF0aC5qb2luKG91dERpciwgXCJfcmVkaXJlY3RzXCIpO1xuICAgIGNvbnN0IHJlZGlyZWN0cyA9IGBcbi9kb2N1bWVudGF0aW9uL3R1aXN0L2luc3RhbGxhdGlvbiAvZ3VpZGUvaW50cm9kdWN0aW9uL2luc3RhbGxhdGlvbiAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3Byb2plY3Qtc3RydWN0dXJlIC9ndWlkZS9wcm9qZWN0L2RpcmVjdG9yeS1zdHJ1Y3R1cmUgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9jb21tYW5kLWxpbmUtaW50ZXJmYWNlIC9ndWlkZS9hdXRvbWF0aW9uL2dlbmVyYXRlIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvZGVwZW5kZW5jaWVzIC9ndWlkZS9wcm9qZWN0L2RlcGVuZGVuY2llcyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3NoYXJpbmctY29kZS1hY3Jvc3MtbWFuaWZlc3RzIC9ndWlkZS9wcm9qZWN0L2NvZGUtc2hhcmluZyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3N5bnRoZXNpemVkLWZpbGVzIC9ndWlkZS9wcm9qZWN0L3N5bnRoZXNpemVkLWZpbGVzIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvbWlncmF0aW9uLWd1aWRlbGluZXMgL2d1aWRlL2ludHJvZHVjdGlvbi9hZG9wdGluZy10dWlzdC9taWdyYXRlLWZyb20teGNvZGVwcm9qIDMwMVxuL3R1dG9yaWFscy90dWlzdC10dXRvcmlhbHMgL2d1aWRlL2ludHJvZHVjdGlvbi9hZG9wdGluZy10dWlzdC9uZXctcHJvamVjdCAzMDFcbi90dXRvcmlhbHMvdHVpc3QvaW5zdGFsbCAgL2d1aWRlL2ludHJvZHVjdGlvbi9hZG9wdGluZy10dWlzdC9uZXctcHJvamVjdCAzMDFcbi90dXRvcmlhbHMvdHVpc3QvY3JlYXRlLXByb2plY3QgIC9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3QvbmV3LXByb2plY3QgMzAxXG4vdHV0b3JpYWxzL3R1aXN0L2V4dGVybmFsLWRlcGVuZGVuY2llcyAvZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L25ldy1wcm9qZWN0IDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvZ2VuZXJhdGlvbi1lbnZpcm9ubWVudCAvZ3VpZGUvcHJvamVjdC9keW5hbWljLWNvbmZpZ3VyYXRpb24gMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC91c2luZy1wbHVnaW5zIC9ndWlkZS9wcm9qZWN0L3BsdWdpbnMgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9jcmVhdGluZy1wbHVnaW5zIC9ndWlkZS9wcm9qZWN0L3BsdWdpbnMgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC90YXNrIC9ndWlkZS9wcm9qZWN0L3BsdWdpbnMgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC90dWlzdC1jbG91ZCAvY2xvdWQvd2hhdC1pcy1jbG91ZCAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3R1aXN0LWNsb3VkLWdldC1zdGFydGVkIC9jbG91ZC9nZXQtc3RhcnRlZCAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L2JpbmFyeS1jYWNoaW5nIC9jbG91ZC9iaW5hcnktY2FjaGluZyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3NlbGVjdGl2ZS10ZXN0aW5nIC9jbG91ZC9zZWxlY3RpdmUtdGVzdGluZyAzMDFcbi90dXRvcmlhbHMvdHVpc3QtY2xvdWQtdHV0b3JpYWxzIC9jbG91ZC9vbi1wcmVtaXNlIDMwMVxuL3R1dG9yaWFscy90dWlzdC9lbnRlcnByaXNlLWluZnJhc3RydWN0dXJlLXJlcXVpcmVtZW50cyAvY2xvdWQvb24tcHJlbWlzZSAzMDFcbi90dXRvcmlhbHMvdHVpc3QvZW50ZXJwcmlzZS1lbnZpcm9ubWVudCAvY2xvdWQvb24tcHJlbWlzZSAzMDFcbi90dXRvcmlhbHMvdHVpc3QvZW50ZXJwcmlzZS1kZXBsb3ltZW50IC9jbG91ZC9vbi1wcmVtaXNlIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvZ2V0LXN0YXJ0ZWQtYXMtY29udHJpYnV0b3IgL2NvbnRyaWJ1dG9ycy9nZXQtc3RhcnRlZCAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L21hbmlmZXN0byAvY29udHJpYnV0b3JzL3ByaW5jaXBsZXMgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9jb2RlLXJldmlld3MgL2NvbnRyaWJ1dG9ycy9jb2RlLXJldmlld3MgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9yZXBvcnRpbmctYnVncyAvY29udHJpYnV0b3JzL2lzc3VlLXJlcG9ydGluZyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L2NoYW1waW9uaW5nLXByb2plY3RzIC9jb250cmlidXRvcnMvZ2V0LXN0YXJ0ZWQgMzAxXG4vZ3VpZGUvc2NhbGUvdWZlYXR1cmVzLWFyY2hpdGVjdHVyZS5odG1sIC9ndWlkZS9zY2FsZS90bWEtYXJjaGl0ZWN0dXJlLmh0bWwgMzAxXG4vZ3VpZGUvc2NhbGUvdWZlYXR1cmVzLWFyY2hpdGVjdHVyZSAvZ3VpZGUvc2NhbGUvdG1hLWFyY2hpdGVjdHVyZSAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vY29zdC1vZi1jb252ZW5pZW5jZSAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvY29zdC1vZi1jb252ZW5pZW5jZSAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vaW5zdGFsbGF0aW9uIC9ndWlkZXMvcXVpY2stc3RhcnQvaW5zdGFsbC10dWlzdCAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3QvbmV3LXByb2plY3QgL2d1aWRlcy9zdGFydC9uZXctcHJvamVjdCAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3Qvc3dpZnQtcGFja2FnZSAvZ3VpZGVzL3N0YXJ0L3N3aWZ0LXBhY2thZ2UgMzAxXG4vZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L21pZ3JhdGUtZnJvbS14Y29kZXByb2ogL2d1aWRlcy9zdGFydC9taWdyYXRlL3hjb2RlLXByb2plY3QgMzAxXG4vZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L21pZ3JhdGUtbG9jYWwtc3dpZnQtcGFja2FnZXMgL2d1aWRlcy9zdGFydC9taWdyYXRlL3N3aWZ0LXBhY2thZ2UgMzAxXG4vZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L21pZ3JhdGUtZnJvbS14Y29kZWdlbiAvZ3VpZGVzL3N0YXJ0L21pZ3JhdGUveGNvZGVnZW4tcHJvamVjdCAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3QvbWlncmF0ZS1mcm9tLWJhemVsIC9ndWlkZXMvc3RhcnQvbWlncmF0ZS9iYXplbC1wcm9qZWN0IDMwMVxuL2d1aWRlL2ludHJvZHVjdGlvbi9mcm9tLXYzLXRvLXY0IC9yZWZlcmVuY2VzL21pZ3JhdGlvbnMvZnJvbS12My10by12NCAzMDFcbi9ndWlkZS9wcm9qZWN0L21hbmlmZXN0cyAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvbWFuaWZlc3RzIDMwMVxuL2d1aWRlL3Byb2plY3QvZGlyZWN0b3J5LXN0cnVjdHVyZSAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvZGlyZWN0b3J5LXN0cnVjdHVyZSAzMDFcbi9ndWlkZS9wcm9qZWN0L2VkaXRpbmcgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2VkaXRpbmcgMzAxXG4vZ3VpZGUvcHJvamVjdC9kZXBlbmRlbmNpZXMgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2RlcGVuZGVuY2llcyAzMDFcbi9ndWlkZS9wcm9qZWN0L2NvZGUtc2hhcmluZyAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvY29kZS1zaGFyaW5nIDMwMVxuL2d1aWRlL3Byb2plY3Qvc3ludGhlc2l6ZWQtZmlsZXMgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL3N5bnRoZXNpemVkLWZpbGVzIDMwMVxuL2d1aWRlL3Byb2plY3QvZHluYW1pYy1jb25maWd1cmF0aW9uIC9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9keW5hbWljLWNvbmZpZ3VyYXRpb24gMzAxXG4vZ3VpZGUvcHJvamVjdC90ZW1wbGF0ZXMgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL3RlbXBsYXRlcyAzMDFcbi9ndWlkZS9wcm9qZWN0L3BsdWdpbnMgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL3BsdWdpbnMgMzAxXG4vZ3VpZGUvYXV0b21hdGlvbi9nZW5lcmF0ZSAvIDMwMVxuL2d1aWRlL2F1dG9tYXRpb24vYnVpbGQgL2d1aWRlcy9kZXZlbG9wL2J1aWxkIDMwMVxuL2d1aWRlL2F1dG9tYXRpb24vdGVzdCAvZ3VpZGVzL2RldmVsb3AvdGVzdCAzMDFcbi9ndWlkZS9hdXRvbWF0aW9uL3J1biAvIDMwMVxuL2d1aWRlL2F1dG9tYXRpb24vZ3JhcGggLyAzMDFcbi9ndWlkZS9hdXRvbWF0aW9uL2NsZWFuIC8gMzAxXG4vZ3VpZGUvc2NhbGUvdG1hLWFyY2hpdGVjdHVyZSAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvdG1hLWFyY2hpdGVjdHVyZSAzMDFcbi9jbG91ZC93aGF0LWlzLWNsb3VkIC8gMzAxXG4vY2xvdWQvZ2V0LXN0YXJ0ZWQgLyAzMDFcbi9jbG91ZC9iaW5hcnktY2FjaGluZyAvZ3VpZGVzL2RldmVsb3AvYnVpbGQvY2FjaGUgMzAxXG4vY2xvdWQvc2VsZWN0aXZlLXRlc3RpbmcgL2d1aWRlcy9kZXZlbG9wL3Rlc3Qvc21hcnQtcnVubmVyIDMwMVxuL2Nsb3VkL2hhc2hpbmcgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2hhc2hpbmcgMzAxXG4vY2xvdWQvb24tcHJlbWlzZSAvZ3VpZGVzL2Rhc2hib2FyZC9vbi1wcmVtaXNlL2luc3RhbGwgMzAxXG4vY2xvdWQvb24tcHJlbWlzZS9tZXRyaWNzIC9ndWlkZXMvZGFzaGJvYXJkL29uLXByZW1pc2UvbWV0cmljcyAzMDFcbi9yZWZlcmVuY2UvcHJvamVjdC1kZXNjcmlwdGlvbi8qIC9yZWZlcmVuY2VzL3Byb2plY3QtZGVzY3JpcHRpb24vOnNwbGF0IDMwMVxuL3JlZmVyZW5jZS9leGFtcGxlcy8qIC9yZWZlcmVuY2VzL2V4YW1wbGVzLzpzcGxhdCAzMDFcbi9ndWlkZXMvZGV2ZWxvcC93b3JrZmxvd3MgL2d1aWRlcy9kZXZlbG9wL2NvbnRpbnVvdXMtaW50ZWdyYXRpb24vd29ya2Zsb3dzIDMwMVxuL2d1aWRlcy9kYXNoYm9hcmQvb24tcHJlbWlzZS9pbnN0YWxsIC9zZXJ2ZXIvb24tcHJlbWlzZS9pbnN0YWxsIDMwMVxuL2d1aWRlcy9kYXNoYm9hcmQvb24tcHJlbWlzZS9tZXRyaWNzIC9zZXJ2ZXIvb24tcHJlbWlzZS9tZXRyaWNzIDMwMVxuLzpsb2NhbGUvcmVmZXJlbmNlcy9wcm9qZWN0LWRlc2NyaXB0aW9uL3N0cnVjdHMvY29uZmlnIC86bG9jYWxlL3JlZmVyZW5jZXMvcHJvamVjdC1kZXNjcmlwdGlvbi9zdHJ1Y3RzL3R1aXN0ICAzMDFcbi86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL3Rlc3Qvc21hcnQtcnVubmVyIC86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL3Rlc3Qvc2VsZWN0aXZlLXRlc3RpbmcgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC8qIC8gMzAxXG4ke2F3YWl0IGZzLnJlYWRGaWxlKHBhdGguam9pbihpbXBvcnQubWV0YS5kaXJuYW1lLCBcImxvY2FsZS1yZWRpcmVjdHMudHh0XCIpLCB7XG4gIGVuY29kaW5nOiBcInV0Zi04XCIsXG59KX1cbiAgICBgO1xuICAgIGZzLndyaXRlRmlsZShyZWRpcmVjdHNQYXRoLCByZWRpcmVjdHMpO1xuICB9LFxuICB0aGVtZUNvbmZpZzoge1xuICAgIGxvZ286IFwiL2xvZ28ucG5nXCIsXG4gICAgc2VhcmNoOiB7XG4gICAgICBwcm92aWRlcjogXCJhbGdvbGlhXCIsXG4gICAgICBvcHRpb25zOiB7XG4gICAgICAgIGFwcElkOiBcIjVBM0w5SEk5VlFcIixcbiAgICAgICAgYXBpS2V5OiBcImNkNDVmNTE1ZmIxZmJiNzIwZDYzM2NiMGYxMjU3ZTdhXCIsXG4gICAgICAgIGluZGV4TmFtZTogXCJ0dWlzdFwiLFxuICAgICAgICBsb2NhbGVzOiBzZWFyY2hPcHRpb25zTG9jYWxlcyxcbiAgICAgICAgc3RhcnRVcmxzOiBbXCJodHRwczovL3R1aXN0LmRldi9cIl0sXG4gICAgICAgIHJlbmRlckphdmFTY3JpcHQ6IGZhbHNlLFxuICAgICAgICBzaXRlbWFwczogW10sXG4gICAgICAgIGV4Y2x1c2lvblBhdHRlcm5zOiBbXSxcbiAgICAgICAgaWdub3JlQ2Fub25pY2FsVG86IGZhbHNlLFxuICAgICAgICBkaXNjb3ZlcnlQYXR0ZXJuczogW1wiaHR0cHM6Ly90dWlzdC5kZXYvKipcIl0sXG4gICAgICAgIHNjaGVkdWxlOiBcImF0IDA1OjEwIG9uIFNhdHVyZGF5XCIsXG4gICAgICAgIGFjdGlvbnM6IFtcbiAgICAgICAgICB7XG4gICAgICAgICAgICBpbmRleE5hbWU6IFwidHVpc3RcIixcbiAgICAgICAgICAgIHBhdGhzVG9NYXRjaDogW1wiaHR0cHM6Ly90dWlzdC5kZXYvKipcIl0sXG4gICAgICAgICAgICByZWNvcmRFeHRyYWN0b3I6ICh7ICQsIGhlbHBlcnMgfSkgPT4ge1xuICAgICAgICAgICAgICByZXR1cm4gaGVscGVycy5kb2NzZWFyY2goe1xuICAgICAgICAgICAgICAgIHJlY29yZFByb3BzOiB7XG4gICAgICAgICAgICAgICAgICBsdmwxOiBcIi5jb250ZW50IGgxXCIsXG4gICAgICAgICAgICAgICAgICBjb250ZW50OiBcIi5jb250ZW50IHAsIC5jb250ZW50IGxpXCIsXG4gICAgICAgICAgICAgICAgICBsdmwwOiB7XG4gICAgICAgICAgICAgICAgICAgIHNlbGVjdG9yczogXCJzZWN0aW9uLmhhcy1hY3RpdmUgZGl2IGgyXCIsXG4gICAgICAgICAgICAgICAgICAgIGRlZmF1bHRWYWx1ZTogXCJEb2N1bWVudGF0aW9uXCIsXG4gICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgbHZsMjogXCIuY29udGVudCBoMlwiLFxuICAgICAgICAgICAgICAgICAgbHZsMzogXCIuY29udGVudCBoM1wiLFxuICAgICAgICAgICAgICAgICAgbHZsNDogXCIuY29udGVudCBoNFwiLFxuICAgICAgICAgICAgICAgICAgbHZsNTogXCIuY29udGVudCBoNVwiLFxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgaW5kZXhIZWFkaW5nczogdHJ1ZSxcbiAgICAgICAgICAgICAgfSk7XG4gICAgICAgICAgICB9LFxuICAgICAgICAgIH0sXG4gICAgICAgIF0sXG4gICAgICAgIGluaXRpYWxJbmRleFNldHRpbmdzOiB7XG4gICAgICAgICAgdml0ZXByZXNzOiB7XG4gICAgICAgICAgICBhdHRyaWJ1dGVzRm9yRmFjZXRpbmc6IFtcInR5cGVcIiwgXCJsYW5nXCJdLFxuICAgICAgICAgICAgYXR0cmlidXRlc1RvUmV0cmlldmU6IFtcImhpZXJhcmNoeVwiLCBcImNvbnRlbnRcIiwgXCJhbmNob3JcIiwgXCJ1cmxcIl0sXG4gICAgICAgICAgICBhdHRyaWJ1dGVzVG9IaWdobGlnaHQ6IFtcImhpZXJhcmNoeVwiLCBcImhpZXJhcmNoeV9jYW1lbFwiLCBcImNvbnRlbnRcIl0sXG4gICAgICAgICAgICBhdHRyaWJ1dGVzVG9TbmlwcGV0OiBbXCJjb250ZW50OjEwXCJdLFxuICAgICAgICAgICAgY2FtZWxDYXNlQXR0cmlidXRlczogW1wiaGllcmFyY2h5XCIsIFwiaGllcmFyY2h5X3JhZGlvXCIsIFwiY29udGVudFwiXSxcbiAgICAgICAgICAgIHNlYXJjaGFibGVBdHRyaWJ1dGVzOiBbXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9yYWRpb19jYW1lbC5sdmwwKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW8ubHZsMClcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X3JhZGlvX2NhbWVsLmx2bDEpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9yYWRpby5sdmwxKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW9fY2FtZWwubHZsMilcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X3JhZGlvLmx2bDIpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9yYWRpb19jYW1lbC5sdmwzKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW8ubHZsMylcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X3JhZGlvX2NhbWVsLmx2bDQpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9yYWRpby5sdmw0KVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW9fY2FtZWwubHZsNSlcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X3JhZGlvLmx2bDUpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9yYWRpb19jYW1lbC5sdmw2KVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW8ubHZsNilcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X2NhbWVsLmx2bDApXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeS5sdmwwKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfY2FtZWwubHZsMSlcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5Lmx2bDEpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9jYW1lbC5sdmwyKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHkubHZsMilcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X2NhbWVsLmx2bDMpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeS5sdmwzKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfY2FtZWwubHZsNClcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5Lmx2bDQpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9jYW1lbC5sdmw1KVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHkubHZsNSlcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X2NhbWVsLmx2bDYpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeS5sdmw2KVwiLFxuICAgICAgICAgICAgICBcImNvbnRlbnRcIixcbiAgICAgICAgICAgIF0sXG4gICAgICAgICAgICBkaXN0aW5jdDogdHJ1ZSxcbiAgICAgICAgICAgIGF0dHJpYnV0ZUZvckRpc3RpbmN0OiBcInVybFwiLFxuICAgICAgICAgICAgY3VzdG9tUmFua2luZzogW1xuICAgICAgICAgICAgICBcImRlc2Mod2VpZ2h0LnBhZ2VSYW5rKVwiLFxuICAgICAgICAgICAgICBcImRlc2Mod2VpZ2h0LmxldmVsKVwiLFxuICAgICAgICAgICAgICBcImFzYyh3ZWlnaHQucG9zaXRpb24pXCIsXG4gICAgICAgICAgICBdLFxuICAgICAgICAgICAgcmFua2luZzogW1xuICAgICAgICAgICAgICBcIndvcmRzXCIsXG4gICAgICAgICAgICAgIFwiZmlsdGVyc1wiLFxuICAgICAgICAgICAgICBcInR5cG9cIixcbiAgICAgICAgICAgICAgXCJhdHRyaWJ1dGVcIixcbiAgICAgICAgICAgICAgXCJwcm94aW1pdHlcIixcbiAgICAgICAgICAgICAgXCJleGFjdFwiLFxuICAgICAgICAgICAgICBcImN1c3RvbVwiLFxuICAgICAgICAgICAgXSxcbiAgICAgICAgICAgIGhpZ2hsaWdodFByZVRhZzpcbiAgICAgICAgICAgICAgJzxzcGFuIGNsYXNzPVwiYWxnb2xpYS1kb2NzZWFyY2gtc3VnZ2VzdGlvbi0taGlnaGxpZ2h0XCI+JyxcbiAgICAgICAgICAgIGhpZ2hsaWdodFBvc3RUYWc6IFwiPC9zcGFuPlwiLFxuICAgICAgICAgICAgbWluV29yZFNpemVmb3IxVHlwbzogMyxcbiAgICAgICAgICAgIG1pbldvcmRTaXplZm9yMlR5cG9zOiA3LFxuICAgICAgICAgICAgYWxsb3dUeXBvc09uTnVtZXJpY1Rva2VuczogZmFsc2UsXG4gICAgICAgICAgICBtaW5Qcm94aW1pdHk6IDEsXG4gICAgICAgICAgICBpZ25vcmVQbHVyYWxzOiB0cnVlLFxuICAgICAgICAgICAgYWR2YW5jZWRTeW50YXg6IHRydWUsXG4gICAgICAgICAgICBhdHRyaWJ1dGVDcml0ZXJpYUNvbXB1dGVkQnlNaW5Qcm94aW1pdHk6IHRydWUsXG4gICAgICAgICAgICByZW1vdmVXb3Jkc0lmTm9SZXN1bHRzOiBcImFsbE9wdGlvbmFsXCIsXG4gICAgICAgICAgfSxcbiAgICAgICAgfSxcbiAgICAgIH0sXG4gICAgfSxcbiAgICBlZGl0TGluazoge1xuICAgICAgcGF0dGVybjogXCJodHRwczovL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZWRpdC9tYWluL2RvY3MvZG9jcy86cGF0aFwiLFxuICAgIH0sXG4gICAgc29jaWFsTGlua3M6IFtcbiAgICAgIHsgaWNvbjogXCJnaXRodWJcIiwgbGluazogXCJodHRwczovL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3RcIiB9LFxuICAgICAgeyBpY29uOiBcIm1hc3RvZG9uXCIsIGxpbms6IFwiaHR0cHM6Ly9mb3NzdG9kb24ub3JnL0B0dWlzdFwiIH0sXG4gICAgICB7IGljb246IFwiYmx1ZXNreVwiLCBsaW5rOiBcImh0dHBzOi8vYnNreS5hcHAvcHJvZmlsZS90dWlzdC5kZXZcIiB9LFxuICAgICAge1xuICAgICAgICBpY29uOiBcInNsYWNrXCIsXG4gICAgICAgIGxpbms6IFwiaHR0cHM6Ly9qb2luLnNsYWNrLmNvbS90L3R1aXN0YXBwL3NoYXJlZF9pbnZpdGUvenQtMXk2NjdtamJrLXMyTFRSWDFZQnliOUVJSVRqZExjTHdcIixcbiAgICAgIH0sXG4gICAgXSxcbiAgICBmb290ZXI6IHtcbiAgICAgIG1lc3NhZ2U6IFwiUmVsZWFzZWQgdW5kZXIgdGhlIE1JVCBMaWNlbnNlLlwiLFxuICAgICAgY29weXJpZ2h0OiBcIkNvcHlyaWdodCBcdTAwQTkgMjAyNC1wcmVzZW50IFR1aXN0IEdtYkhcIixcbiAgICB9LFxuICB9LFxufSk7XG4iLCAie1xuICBcImFzaWRlXCI6IHtcbiAgICBcInRyYW5zbGF0ZVwiOiB7XG4gICAgICBcInRpdGxlXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiVHJhbnNsYXRpb24gXHVEODNDXHVERjBEXCJcbiAgICAgIH0sXG4gICAgICBcImRlc2NyaXB0aW9uXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiWW91IGNhbiB0cmFuc2xhdGUgb3IgaW1wcm92ZSB0aGUgdHJhbnNsYXRpb24gb2YgdGhpcyBwYWdlLlwiXG4gICAgICB9LFxuICAgICAgXCJjdGFcIjoge1xuICAgICAgICBcInRleHRcIjogXCJDb250cmlidXRlXCJcbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwic2VhcmNoXCI6IHtcbiAgICBcInBsYWNlaG9sZGVyXCI6IFwiU2VhcmNoXCIsXG4gICAgXCJ0cmFuc2xhdGlvbnNcIjoge1xuICAgICAgXCJidXR0b25cIjoge1xuICAgICAgICBcImJ1dHRvbi10ZXh0XCI6IFwiU2VhcmNoIGRvY3VtZW50YXRpb25cIixcbiAgICAgICAgXCJidXR0b24tYXJpYS1sYWJlbFwiOiBcIlNlYXJjaCBkb2N1bWVudGF0aW9uXCJcbiAgICAgIH0sXG4gICAgICBcIm1vZGFsXCI6IHtcbiAgICAgICAgXCJzZWFyY2gtYm94XCI6IHtcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi10aXRsZVwiOiBcIkNsZWFyIHF1ZXJ5XCIsXG4gICAgICAgICAgXCJyZXNldC1idXR0b24tYXJpYS1sYWJlbFwiOiBcIkNsZWFyIHF1ZXJ5XCIsXG4gICAgICAgICAgXCJjYW5jZWwtYnV0dG9uLXRleHRcIjogXCJDYW5jZWxcIixcbiAgICAgICAgICBcImNhbmNlbC1idXR0b24tYXJpYS1sYWJlbFwiOiBcIkNhbmNlbFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhcnQtc2NyZWVuXCI6IHtcbiAgICAgICAgICBcInJlY2VudC1zZWFyY2hlcy10aXRsZVwiOiBcIlNlYXJjaCBoaXN0b3J5XCIsXG4gICAgICAgICAgXCJuby1yZWNlbnQtc2VhcmNoZXMtdGV4dFwiOiBcIk5vIHNlYXJjaCBoaXN0b3J5XCIsXG4gICAgICAgICAgXCJzYXZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiU2F2ZSB0byBzZWFyY2ggaGlzdG9yeVwiLFxuICAgICAgICAgIFwicmVtb3ZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiUmVtb3ZlIGZyb20gc2VhcmNoIGhpc3RvcnlcIixcbiAgICAgICAgICBcImZhdm9yaXRlLXNlYXJjaGVzLXRpdGxlXCI6IFwiRmF2b3JpdGVzXCIsXG4gICAgICAgICAgXCJyZW1vdmUtZmF2b3JpdGUtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlJlbW92ZSBmcm9tIGZhdm9yaXRlc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiZXJyb3Itc2NyZWVuXCI6IHtcbiAgICAgICAgICBcInRpdGxlLXRleHRcIjogXCJVbmFibGUgdG8gcmV0cmlldmUgcmVzdWx0c1wiLFxuICAgICAgICAgIFwiaGVscC10ZXh0XCI6IFwiWW91IG1heSBuZWVkIHRvIGNoZWNrIHlvdXIgbmV0d29yayBjb25uZWN0aW9uXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJmb290ZXJcIjoge1xuICAgICAgICAgIFwic2VsZWN0LXRleHRcIjogXCJTZWxlY3RcIixcbiAgICAgICAgICBcIm5hdmlnYXRlLXRleHRcIjogXCJOYXZpZ2F0ZVwiLFxuICAgICAgICAgIFwiY2xvc2UtdGV4dFwiOiBcIkNsb3NlXCIsXG4gICAgICAgICAgXCJzZWFyY2gtYnktdGV4dFwiOiBcIlNlYXJjaCBwcm92aWRlclwiXG4gICAgICAgIH0sXG4gICAgICAgIFwibm8tcmVzdWx0cy1zY3JlZW5cIjoge1xuICAgICAgICAgIFwibm8tcmVzdWx0cy10ZXh0XCI6IFwiTm8gcmVsZXZhbnQgcmVzdWx0cyBmb3VuZFwiLFxuICAgICAgICAgIFwic3VnZ2VzdGVkLXF1ZXJ5LXRleHRcIjogXCJZb3UgbWlnaHQgdHJ5IHF1ZXJ5aW5nXCIsXG4gICAgICAgICAgXCJyZXBvcnQtbWlzc2luZy1yZXN1bHRzLXRleHRcIjogXCJEbyB5b3UgdGhpbmsgdGhpcyBxdWVyeSBzaG91bGQgaGF2ZSByZXN1bHRzP1wiLFxuICAgICAgICAgIFwicmVwb3J0LW1pc3NpbmctcmVzdWx0cy1saW5rLXRleHRcIjogXCJDbGljayB0byBnaXZlIGZlZWRiYWNrXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJiYWRnZXNcIjoge1xuICAgIFwiY29taW5nLXNvb25cIjogXCJDb21pbmcgc29vblwiLFxuICAgIFwieGNvZGVwcm9qLWNvbXBhdGlibGVcIjogXCJYY29kZVByb2otY29tcGF0aWJsZVwiXG4gIH0sXG4gIFwibmF2YmFyXCI6IHtcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJHdWlkZXNcIlxuICAgIH0sXG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCJcbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlNlcnZlclwiXG4gICAgfSxcbiAgICBcInJlc291cmNlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJSZXNvdXJjZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInJlZmVyZW5jZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlJlZmVyZW5jZXNcIlxuICAgICAgICB9LFxuICAgICAgICBcImNvbnRyaWJ1dG9yc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29udHJpYnV0b3JzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjaGFuZ2Vsb2dcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNoYW5nZWxvZ1wiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwic2lkZWJhcnNcIjoge1xuICAgIFwiY2xpXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNMSVwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiY29tbWFuZHNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNvbW1hbmRzXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJyZWZlcmVuY2VzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlJlZmVyZW5jZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImV4YW1wbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJFeGFtcGxlc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwibWlncmF0aW9uc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiTWlncmF0aW9uc1wiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJmcm9tLXYzLXRvLXY0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRnJvbSB2MyB0byB2NFwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImNvbnRyaWJ1dG9yc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJDb250cmlidXRvcnNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImdldC1zdGFydGVkXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJHZXQgc3RhcnRlZFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiaXNzdWUtcmVwb3J0aW5nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJJc3N1ZSByZXBvcnRpbmdcIlxuICAgICAgICB9LFxuICAgICAgICBcImNvZGUtcmV2aWV3c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29kZSByZXZpZXdzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJwcmluY2lwbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJQcmluY2lwbGVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlRyYW5zbGF0ZVwiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImludHJvZHVjdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiSW50cm9kdWN0aW9uXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIndoeS1zZXJ2ZXJcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJXaHkgYSBzZXJ2ZXI/XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImFjY291bnRzLWFuZC1wcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFjY291bnRzIGFuZCBwcm9qZWN0c1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJhdXRoZW50aWNhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkF1dGhlbnRpY2F0aW9uXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImludGVncmF0aW9uc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkludGVncmF0aW9uc1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcIm9uLXByZW1pc2VcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIk9uLXByZW1pc2VcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiaW5zdGFsbFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3RhbGxcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwibWV0cmljc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1ldHJpY3NcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJhcGktZG9jdW1lbnRhdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQVBJIGRvY3VtZW50YXRpb25cIlxuICAgICAgICB9LFxuICAgICAgICBcInN0YXR1c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiU3RhdHVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJtZXRyaWNzLWRhc2hib2FyZFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiTWV0cmljcyBkYXNoYm9hcmRcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJHdWlkZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInF1aWNrLXN0YXJ0XCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJRdWljayBzdGFydFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsLXR1aXN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zdGFsbCBUdWlzdFwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJjcmVhdGUtYS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ3JlYXRlIGEgcHJvamVjdFwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJvcHRpbWl6ZS13b3JrZmxvd3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJPcHRpbWl6ZSB3b3JrZmxvd3NcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJzdGFydFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiU3RhcnRcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibmV3LXByb2plY3RcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJDcmVhdGUgYSBuZXcgcHJvamVjdFwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJzd2lmdC1wYWNrYWdlXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVHJ5IHdpdGggYSBTd2lmdCBQYWNrYWdlXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcIm1pZ3JhdGVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJNaWdyYXRlXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwieGNvZGUtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBbiBYY29kZSBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBIFN3aWZ0IHBhY2thZ2VcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZWdlbi1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFuIFhjb2RlR2VuIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJiYXplbC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkEgQmF6ZWwgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImRldmVsb3BcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkRldmVsb3BcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwicHJvamVjdHNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJQcm9qZWN0c1wiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcIm1hbmlmZXN0c1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJNYW5pZmVzdHNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkaXJlY3Rvcnktc3RydWN0dXJlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkRpcmVjdG9yeSBzdHJ1Y3R1cmVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJlZGl0aW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkVkaXRpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkZXBlbmRlbmNpZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRGVwZW5kZW5jaWVzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiY29kZS1zaGFyaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvZGUgc2hhcmluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInN5bnRoZXNpemVkLWZpbGVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlN5bnRoZXNpemVkIGZpbGVzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZHluYW1pYy1jb25maWd1cmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkR5bmFtaWMgY29uZmlndXJhdGlvblwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRlbXBsYXRlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJUZW1wbGF0ZXNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJwbHVnaW5zXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlBsdWdpbnNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJoYXNoaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkhhc2hpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0aGUtY29zdC1vZi1jb252ZW5pZW5jZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJUaGUgY29zdCBvZiBjb252ZW5pZW5jZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRtYS1hcmNoaXRlY3R1cmVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTW9kdWxhciBhcmNoaXRlY3R1cmVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJiZXN0LXByYWN0aWNlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJCZXN0IHByYWN0aWNlc1wiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJidWlsZFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkJ1aWxkXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwiY2FjaGVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ2FjaGVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJyZWdpc3RyeVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJSZWdpc3RyeVwiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJ0ZXN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVGVzdFwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcInNlbGVjdGl2ZS10ZXN0aW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlNlbGVjdGl2ZSB0ZXN0aW5nXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZmxha2luZXNzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkZsYWtpbmVzc1wiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJpbnNwZWN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zcGVjdFwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcImltcGxpY2l0LWltcG9ydHNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW1wbGljaXQgaW1wb3J0c1wiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJhdXRvbWF0ZVwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkF1dG9tYXRlXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwiY29udGludW91cy1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJDb250aW51b3VzIGludGVncmF0aW9uXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwid29ya2Zsb3dzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIldvcmtmbG93c1wiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcInNoYXJlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJTaGFyZVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJwcmV2aWV3c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlByZXZpZXdzXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH1cbn1cbiIsICJ7XG4gIFwiYXNpZGVcIjoge1xuICAgIFwidHJhbnNsYXRlXCI6IHtcbiAgICAgIFwidGl0bGVcIjoge1xuICAgICAgICBcInRleHRcIjogXCJUcmFuc2xhdGlvbiBcdUQ4M0NcdURGMERcIlxuICAgICAgfSxcbiAgICAgIFwiZGVzY3JpcHRpb25cIjoge1xuICAgICAgICBcInRleHRcIjogXCJZb3UgY2FuIHRyYW5zbGF0ZSBvciBpbXByb3ZlIHRoZSB0cmFuc2xhdGlvbiBvZiB0aGlzIHBhZ2UuXCJcbiAgICAgIH0sXG4gICAgICBcImN0YVwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIkNvbnRyaWJ1dGVcIlxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzZWFyY2hcIjoge1xuICAgIFwicGxhY2Vob2xkZXJcIjogXCJTZWFyY2hcIixcbiAgICBcInRyYW5zbGF0aW9uc1wiOiB7XG4gICAgICBcImJ1dHRvblwiOiB7XG4gICAgICAgIFwiYnV0dG9uLXRleHRcIjogXCJTZWFyY2ggZG9jdW1lbnRhdGlvblwiLFxuICAgICAgICBcImJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiU2VhcmNoIGRvY3VtZW50YXRpb25cIlxuICAgICAgfSxcbiAgICAgIFwibW9kYWxcIjoge1xuICAgICAgICBcInNlYXJjaC1ib3hcIjoge1xuICAgICAgICAgIFwicmVzZXQtYnV0dG9uLXRpdGxlXCI6IFwiQ2xlYXIgcXVlcnlcIixcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiQ2xlYXIgcXVlcnlcIixcbiAgICAgICAgICBcImNhbmNlbC1idXR0b24tdGV4dFwiOiBcIkNhbmNlbFwiLFxuICAgICAgICAgIFwiY2FuY2VsLWJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiQ2FuY2VsXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJzdGFydC1zY3JlZW5cIjoge1xuICAgICAgICAgIFwicmVjZW50LXNlYXJjaGVzLXRpdGxlXCI6IFwiU2VhcmNoIGhpc3RvcnlcIixcbiAgICAgICAgICBcIm5vLXJlY2VudC1zZWFyY2hlcy10ZXh0XCI6IFwiTm8gc2VhcmNoIGhpc3RvcnlcIixcbiAgICAgICAgICBcInNhdmUtcmVjZW50LXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJTYXZlIHRvIHNlYXJjaCBoaXN0b3J5XCIsXG4gICAgICAgICAgXCJyZW1vdmUtcmVjZW50LXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJSZW1vdmUgZnJvbSBzZWFyY2ggaGlzdG9yeVwiLFxuICAgICAgICAgIFwiZmF2b3JpdGUtc2VhcmNoZXMtdGl0bGVcIjogXCJGYXZvcml0ZXNcIixcbiAgICAgICAgICBcInJlbW92ZS1mYXZvcml0ZS1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiUmVtb3ZlIGZyb20gZmF2b3JpdGVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJlcnJvci1zY3JlZW5cIjoge1xuICAgICAgICAgIFwidGl0bGUtdGV4dFwiOiBcIlVuYWJsZSB0byByZXRyaWV2ZSByZXN1bHRzXCIsXG4gICAgICAgICAgXCJoZWxwLXRleHRcIjogXCJZb3UgbWF5IG5lZWQgdG8gY2hlY2sgeW91ciBuZXR3b3JrIGNvbm5lY3Rpb25cIlxuICAgICAgICB9LFxuICAgICAgICBcImZvb3RlclwiOiB7XG4gICAgICAgICAgXCJzZWxlY3QtdGV4dFwiOiBcIlNlbGVjdFwiLFxuICAgICAgICAgIFwibmF2aWdhdGUtdGV4dFwiOiBcIk5hdmlnYXRlXCIsXG4gICAgICAgICAgXCJjbG9zZS10ZXh0XCI6IFwiQ2xvc2VcIixcbiAgICAgICAgICBcInNlYXJjaC1ieS10ZXh0XCI6IFwiU2VhcmNoIHByb3ZpZGVyXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJuby1yZXN1bHRzLXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJuby1yZXN1bHRzLXRleHRcIjogXCJObyByZWxldmFudCByZXN1bHRzIGZvdW5kXCIsXG4gICAgICAgICAgXCJzdWdnZXN0ZWQtcXVlcnktdGV4dFwiOiBcIllvdSBtaWdodCB0cnkgcXVlcnlpbmdcIixcbiAgICAgICAgICBcInJlcG9ydC1taXNzaW5nLXJlc3VsdHMtdGV4dFwiOiBcIkRvIHlvdSB0aGluayB0aGlzIHF1ZXJ5IHNob3VsZCBoYXZlIHJlc3VsdHM/XCIsXG4gICAgICAgICAgXCJyZXBvcnQtbWlzc2luZy1yZXN1bHRzLWxpbmstdGV4dFwiOiBcIkNsaWNrIHRvIGdpdmUgZmVlZGJhY2tcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9LFxuICBcImJhZGdlc1wiOiB7XG4gICAgXCJjb21pbmctc29vblwiOiBcIkNvbWluZyBzb29uXCIsXG4gICAgXCJ4Y29kZXByb2otY29tcGF0aWJsZVwiOiBcIlhjb2RlUHJvai1jb21wYXRpYmxlXCJcbiAgfSxcbiAgXCJuYXZiYXJcIjoge1xuICAgIFwiZ3VpZGVzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkd1aWRlc1wiXG4gICAgfSxcbiAgICBcImNsaVwiOiB7XG4gICAgICBcInRleHRcIjogXCJDTElcIlxuICAgIH0sXG4gICAgXCJzZXJ2ZXJcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiU2VydmVyXCJcbiAgICB9LFxuICAgIFwicmVzb3VyY2VzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlJlc291cmNlc1wiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwicmVmZXJlbmNlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiUmVmZXJlbmNlc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDb250cmlidXRvcnNcIlxuICAgICAgICB9LFxuICAgICAgICBcImNoYW5nZWxvZ1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ2hhbmdlbG9nXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzaWRlYmFyc1wiOiB7XG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJjb21tYW5kc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29tbWFuZHNcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcInJlZmVyZW5jZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiUmVmZXJlbmNlc1wiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiZXhhbXBsZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkV4YW1wbGVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJtaWdyYXRpb25zXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJNaWdyYXRpb25zXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImZyb20tdjMtdG8tdjRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJGcm9tIHYzIHRvIHY0XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNvbnRyaWJ1dG9yc1wiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiZ2V0LXN0YXJ0ZWRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkdldCBzdGFydGVkXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJpc3N1ZS1yZXBvcnRpbmdcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIklzc3VlIHJlcG9ydGluZ1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY29kZS1yZXZpZXdzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUFcdTA0M0VcdTA0MzQgXHUwNDQwXHUwNDM1XHUwNDMyXHUwNDRDXHUwNDRFXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJwcmluY2lwbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJQcmluY2lwbGVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlRyYW5zbGF0ZVwiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImludHJvZHVjdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiSW50cm9kdWN0aW9uXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIndoeS1zZXJ2ZXJcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJXaHkgYSBzZXJ2ZXI/XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImFjY291bnRzLWFuZC1wcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFjY291bnRzIGFuZCBwcm9qZWN0c1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJhdXRoZW50aWNhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkF1dGhlbnRpY2F0aW9uXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImludGVncmF0aW9uc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkludGVncmF0aW9uc1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcIm9uLXByZW1pc2VcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIk9uLXByZW1pc2VcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiaW5zdGFsbFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3RhbGxcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwibWV0cmljc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1ldHJpY3NcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJhcGktZG9jdW1lbnRhdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQVBJIGRvY3VtZW50YXRpb25cIlxuICAgICAgICB9LFxuICAgICAgICBcInN0YXR1c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiU3RhdHVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJtZXRyaWNzLWRhc2hib2FyZFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiTWV0cmljcyBkYXNoYm9hcmRcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJHdWlkZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInF1aWNrLXN0YXJ0XCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJRdWljayBzdGFydFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsLXR1aXN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIzXHUwNDQxXHUwNDQyXHUwNDMwXHUwNDNEXHUwNDNFXHUwNDMyXHUwNDNBXHUwNDMwIFR1aXN0XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImNyZWF0ZS1hLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJDcmVhdGUgYSBwcm9qZWN0XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcIm9wdGltaXplLXdvcmtmbG93c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIk9wdGltaXplIHdvcmtmbG93c1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcInN0YXJ0XCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJTdGFydFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJuZXctcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQyMVx1MDQzRVx1MDQzN1x1MDQzNFx1MDQzMFx1MDQzRFx1MDQzOFx1MDQzNSBcdTA0M0RcdTA0M0VcdTA0MzJcdTA0M0VcdTA0MzNcdTA0M0UgXHUwNDNGXHUwNDQwXHUwNDNFXHUwNDM1XHUwNDNBXHUwNDQyXHUwNDMwXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJUcnkgd2l0aCBhIFN3aWZ0IFBhY2thZ2VcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwibWlncmF0ZVwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1pZ3JhdGVcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJ4Y29kZS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFuIFhjb2RlIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJzd2lmdC1wYWNrYWdlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkEgU3dpZnQgcGFja2FnZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInhjb2RlZ2VuLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQW4gWGNvZGVHZW4gcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImJhemVsLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQSBCYXplbCBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiZGV2ZWxvcFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiRGV2ZWxvcFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJwcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlByb2plY3RzXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwibWFuaWZlc3RzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1hbmlmZXN0c1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImRpcmVjdG9yeS1zdHJ1Y3R1cmVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRGlyZWN0b3J5IHN0cnVjdHVyZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImVkaXRpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRWRpdGluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImRlcGVuZGVuY2llc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MTdcdTA0MzBcdTA0MzJcdTA0MzhcdTA0NDFcdTA0MzhcdTA0M0NcdTA0M0VcdTA0NDFcdTA0NDJcdTA0MzhcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJjb2RlLXNoYXJpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29kZSBzaGFyaW5nXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwic3ludGhlc2l6ZWQtZmlsZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU3ludGhlc2l6ZWQgZmlsZXNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkeW5hbWljLWNvbmZpZ3VyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRHluYW1pYyBjb25maWd1cmF0aW9uXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidGVtcGxhdGVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlRlbXBsYXRlc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInBsdWdpbnNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUGx1Z2luc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImhhc2hpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSGFzaGluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRoZS1jb3N0LW9mLWNvbnZlbmllbmNlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlRoZSBjb3N0IG9mIGNvbnZlbmllbmNlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidG1hLWFyY2hpdGVjdHVyZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJNb2R1bGFyIGFyY2hpdGVjdHVyZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImJlc3QtcHJhY3RpY2VzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxQlx1MDQ0M1x1MDQ0N1x1MDQ0OFx1MDQzOFx1MDQzNSBcdTA0M0ZcdTA0NDBcdTA0MzBcdTA0M0FcdTA0NDJcdTA0MzhcdTA0M0FcdTA0MzhcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYnVpbGRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJCdWlsZFwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcImNhY2hlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNhY2hlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwicmVnaXN0cnlcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUmVnaXN0cnlcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwidGVzdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlRlc3RcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJzZWxlY3RpdmUtdGVzdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTZWxlY3RpdmUgdGVzdGluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImZsYWtpbmVzc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJGbGFraW5lc3NcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiaW5zcGVjdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3BlY3RcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJpbXBsaWNpdC1pbXBvcnRzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxRFx1MDQzNVx1MDQ0Rlx1MDQzMlx1MDQzRFx1MDQ0Qlx1MDQzNSBcdTA0MzhcdTA0M0NcdTA0M0ZcdTA0M0VcdTA0NDBcdTA0NDJcdTA0NEJcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYXV0b21hdGVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJBdXRvbWF0ZVwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcImNvbnRpbnVvdXMtaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29udGludW91cyBpbnRlZ3JhdGlvblwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcIndvcmtmbG93c1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJXb3JrZmxvd3NcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJzaGFyZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiU2hhcmVcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwicHJldmlld3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJQcmV2aWV3c1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9XG59XG4iLCAie1xuICBcImFzaWRlXCI6IHtcbiAgICBcInRyYW5zbGF0ZVwiOiB7XG4gICAgICBcInRpdGxlXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiXHVCQzg4XHVDNUVEXCJcbiAgICAgIH0sXG4gICAgICBcImRlc2NyaXB0aW9uXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiXHVDNzc0IFx1RDM5OFx1Qzc3NFx1QzlDMFx1Qjk3QyBcdUJDODhcdUM1RURcdUQ1NThcdUFDNzBcdUIwOTggXHVBRTMwXHVDODc0IFx1QkM4OFx1QzVFRFx1Qzc0NCBcdUFDMUNcdUMxMjBcdUQ1NjAgXHVDMjE4IFx1Qzc4OFx1QzJCNVx1QjJDOFx1QjJFNC5cIlxuICAgICAgfSxcbiAgICAgIFwiY3RhXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiXHVBRTMwXHVDNUVDXCJcbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwic2VhcmNoXCI6IHtcbiAgICBcInBsYWNlaG9sZGVyXCI6IFwiXHVBQzgwXHVDMEM5XCIsXG4gICAgXCJ0cmFuc2xhdGlvbnNcIjoge1xuICAgICAgXCJidXR0b25cIjoge1xuICAgICAgICBcImJ1dHRvbi10ZXh0XCI6IFwiXHVCQjM4XHVDMTFDIFx1QUM4MFx1QzBDOVwiLFxuICAgICAgICBcImJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiXHVCQjM4XHVDMTFDIFx1QUM4MFx1QzBDOVwiXG4gICAgICB9LFxuICAgICAgXCJtb2RhbFwiOiB7XG4gICAgICAgIFwic2VhcmNoLWJveFwiOiB7XG4gICAgICAgICAgXCJyZXNldC1idXR0b24tdGl0bGVcIjogXCJcdUFDODBcdUMwQzlcdUM1QjQgXHVDRDA4XHVBRTMwXHVENjU0XCIsXG4gICAgICAgICAgXCJyZXNldC1idXR0b24tYXJpYS1sYWJlbFwiOiBcIlx1QUM4MFx1QzBDOVx1QzVCNCBcdUNEMDhcdUFFMzBcdUQ2NTRcIixcbiAgICAgICAgICBcImNhbmNlbC1idXR0b24tdGV4dFwiOiBcIlx1Q0RFOFx1QzE4Q1wiLFxuICAgICAgICAgIFwiY2FuY2VsLWJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiXHVDREU4XHVDMThDXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJzdGFydC1zY3JlZW5cIjoge1xuICAgICAgICAgIFwicmVjZW50LXNlYXJjaGVzLXRpdGxlXCI6IFwiXHVBQzgwXHVDMEM5IFx1Qzc3NFx1QjgyNVwiLFxuICAgICAgICAgIFwibm8tcmVjZW50LXNlYXJjaGVzLXRleHRcIjogXCJcdUFDODBcdUMwQzkgXHVDNzc0XHVCODI1XHVDNzc0IFx1QzVDNlx1Qzc0Q1wiLFxuICAgICAgICAgIFwic2F2ZS1yZWNlbnQtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlx1QUM4MFx1QzBDOSBcdUM3NzRcdUI4MjUgXHVDODAwXHVDN0E1XCIsXG4gICAgICAgICAgXCJyZW1vdmUtcmVjZW50LXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJcdUFDODBcdUMwQzkgXHVDNzc0XHVCODI1IFx1QzBBRFx1QzgxQ1wiLFxuICAgICAgICAgIFwiZmF2b3JpdGUtc2VhcmNoZXMtdGl0bGVcIjogXCJcdUM5OTBcdUFDQThcdUNDM0VcdUFFMzBcIixcbiAgICAgICAgICBcInJlbW92ZS1mYXZvcml0ZS1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiXHVDOTkwXHVBQ0E4XHVDQzNFXHVBRTMwIFx1QzBBRFx1QzgxQ1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiZXJyb3Itc2NyZWVuXCI6IHtcbiAgICAgICAgICBcInRpdGxlLXRleHRcIjogXCJcdUFDQjBcdUFDRkNcdUI5N0MgXHVCQzFCXHVDNzQ0IFx1QzIxOCBcdUM1QzZcdUM3NENcIixcbiAgICAgICAgICBcImhlbHAtdGV4dFwiOiBcIlx1QjEyNFx1RDJCOFx1QzZDQ1x1RDA2QyBcdUM1RjBcdUFDQjBcdUM3NDQgXHVENjU1XHVDNzc4XHVENTc0XHVDOEZDXHVDMTM4XHVDNjk0XCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJmb290ZXJcIjoge1xuICAgICAgICAgIFwic2VsZWN0LXRleHRcIjogXCJcdUMxMjBcdUQwRERcIixcbiAgICAgICAgICBcIm5hdmlnYXRlLXRleHRcIjogXCJcdUQwRDBcdUMwQzlcIixcbiAgICAgICAgICBcImNsb3NlLXRleHRcIjogXCJcdUIyRUJcdUFFMzBcIixcbiAgICAgICAgICBcInNlYXJjaC1ieS10ZXh0XCI6IFwiXHVBQzgwXHVDMEM5IFx1QzgxQ1x1QUNGNVx1Qzc5MFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwibm8tcmVzdWx0cy1zY3JlZW5cIjoge1xuICAgICAgICAgIFwibm8tcmVzdWx0cy10ZXh0XCI6IFwiXHVBRDAwXHVCODI4XHVCNDFDIFx1QUNCMFx1QUNGQ1x1Qjk3QyBcdUNDM0VcdUM3NDQgXHVDMjE4IFx1QzVDNlx1Qzc0Q1wiLFxuICAgICAgICAgIFwic3VnZ2VzdGVkLXF1ZXJ5LXRleHRcIjogXCJcdUIyRTRcdUI5NzggXHVBQzgwXHVDMEM5XHVDNUI0XHVCOTdDIFx1Qzc4NVx1QjgyNVx1RDU3NFx1QkNGNFx1QzEzOFx1QzY5NFwiLFxuICAgICAgICAgIFwicmVwb3J0LW1pc3NpbmctcmVzdWx0cy10ZXh0XCI6IFwiXHVBQzgwXHVDMEM5IFx1QUNCMFx1QUNGQ1x1QUMwMCBcdUM3ODhcdUM1QjRcdUM1N0MgXHVENTVDXHVCMkU0XHVBQ0UwIFx1QzBERFx1QUMwMVx1RDU1OFx1QjA5OFx1QzY5ND9cIixcbiAgICAgICAgICBcInJlcG9ydC1taXNzaW5nLXJlc3VsdHMtbGluay10ZXh0XCI6IFwiXHVENTNDXHVCNERDXHVCQzMxXHVENTU4XHVBRTMwXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJiYWRnZXNcIjoge1xuICAgIFwiY29taW5nLXNvb25cIjogXCJDb21pbmcgc29vblwiLFxuICAgIFwieGNvZGVwcm9qLWNvbXBhdGlibGVcIjogXCJYY29kZVByb2otY29tcGF0aWJsZVwiXG4gIH0sXG4gIFwibmF2YmFyXCI6IHtcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJcdUM1NDhcdUIwQjRcdUMxMUNcIlxuICAgIH0sXG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCJcbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1QzExQ1x1QkM4NFwiXG4gICAgfSxcbiAgICBcInJlc291cmNlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJcdUI5QUNcdUMxOENcdUMyQTRcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInJlZmVyZW5jZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1Q0MzOFx1QUNFMFx1Qzc5MFx1QjhDQ1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdUFFMzBcdUM1RUNcdUM3OTBcdUI0RTRcIlxuICAgICAgICB9LFxuICAgICAgICBcImNoYW5nZWxvZ1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHVDMjE4XHVDODE1XHVDMEFDXHVENTZEXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzaWRlYmFyc1wiOiB7XG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJjb21tYW5kc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29tbWFuZHNcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcInJlZmVyZW5jZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiUmVmZXJlbmNlc1wiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiZXhhbXBsZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkV4YW1wbGVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJtaWdyYXRpb25zXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJNaWdyYXRpb25zXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImZyb20tdjMtdG8tdjRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJGcm9tIHYzIHRvIHY0XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNvbnRyaWJ1dG9yc1wiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiZ2V0LXN0YXJ0ZWRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkdldCBzdGFydGVkXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJpc3N1ZS1yZXBvcnRpbmdcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIklzc3VlIHJlcG9ydGluZ1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY29kZS1yZXZpZXdzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDb2RlIHJldmlld3NcIlxuICAgICAgICB9LFxuICAgICAgICBcInByaW5jaXBsZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlByaW5jaXBsZXNcIlxuICAgICAgICB9LFxuICAgICAgICBcInRyYW5zbGF0ZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiVHJhbnNsYXRlXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJzZXJ2ZXJcIjoge1xuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiaW50cm9kdWN0aW9uXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJJbnRyb2R1Y3Rpb25cIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwid2h5LXNlcnZlclwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIldoeSBhIHNlcnZlcj9cIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYWNjb3VudHMtYW5kLXByb2plY3RzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQWNjb3VudHMgYW5kIHByb2plY3RzXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImF1dGhlbnRpY2F0aW9uXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQXV0aGVudGljYXRpb25cIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiaW50ZWdyYXRpb25zXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW50ZWdyYXRpb25zXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwib24tcHJlbWlzZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiT24tcHJlbWlzZVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zdGFsbFwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJtZXRyaWNzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTWV0cmljc1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImFwaS1kb2N1bWVudGF0aW9uXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJBUEkgZG9jdW1lbnRhdGlvblwiXG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhdHVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJTdGF0dXNcIlxuICAgICAgICB9LFxuICAgICAgICBcIm1ldHJpY3MtZGFzaGJvYXJkXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdUQxQjVcdUFDQzQgXHVENjA0XHVENjY5XHVEMzEwXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJndWlkZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiXHVDNTQ4XHVCMEI0XHVDMTFDXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJxdWljay1zdGFydFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiUXVpY2sgc3RhcnRcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiaW5zdGFsbC10dWlzdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3RhbGwgVHVpc3RcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiY3JlYXRlLWEtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNyZWF0ZSBhIHByb2plY3RcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwib3B0aW1pemUtd29ya2Zsb3dzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiT3B0aW1pemUgd29ya2Zsb3dzXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhcnRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlN0YXJ0XCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIm5ldy1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ3JlYXRlIGEgbmV3IHByb2plY3RcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlRyeSB3aXRoIGEgU3dpZnQgUGFja2FnZVwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJtaWdyYXRlXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTWlncmF0ZVwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQW4gWGNvZGUgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQSBTd2lmdCBwYWNrYWdlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwieGNvZGVnZW4tcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBbiBYY29kZUdlbiBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiYmF6ZWwtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBIEJhemVsIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJkZXZlbG9wXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJEZXZlbG9wXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcInByb2plY3RzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUHJvamVjdHNcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJtYW5pZmVzdHNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTWFuaWZlc3RzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZGlyZWN0b3J5LXN0cnVjdHVyZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJEaXJlY3Rvcnkgc3RydWN0dXJlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZWRpdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJFZGl0aW5nXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZGVwZW5kZW5jaWVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkRlcGVuZGVuY2llc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImNvZGUtc2hhcmluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJDb2RlIHNoYXJpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJzeW50aGVzaXplZC1maWxlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTeW50aGVzaXplZCBmaWxlc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImR5bmFtaWMtY29uZmlndXJhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJEeW5hbWljIGNvbmZpZ3VyYXRpb25cIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0ZW1wbGF0ZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVGVtcGxhdGVzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwicGx1Z2luc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJQbHVnaW5zXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiaGFzaGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJIYXNoaW5nXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidGhlLWNvc3Qtb2YtY29udmVuaWVuY2VcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVGhlIGNvc3Qgb2YgY29udmVuaWVuY2VcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0bWEtYXJjaGl0ZWN0dXJlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1vZHVsYXIgYXJjaGl0ZWN0dXJlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiYmVzdC1wcmFjdGljZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQmVzdCBwcmFjdGljZXNcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYnVpbGRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJCdWlsZFwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcImNhY2hlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNhY2hlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwicmVnaXN0cnlcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUmVnaXN0cnlcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwidGVzdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlRlc3RcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJzZWxlY3RpdmUtdGVzdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTZWxlY3RpdmUgdGVzdGluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImZsYWtpbmVzc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJGbGFraW5lc3NcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiaW5zcGVjdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3BlY3RcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJpbXBsaWNpdC1pbXBvcnRzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkltcGxpY2l0IGltcG9ydHNcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYXV0b21hdGVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJBdXRvbWF0ZVwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcImNvbnRpbnVvdXMtaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29udGludW91cyBpbnRlZ3JhdGlvblwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcIndvcmtmbG93c1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJXb3JrZmxvd3NcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJzaGFyZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiU2hhcmVcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwicHJldmlld3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJQcmV2aWV3c1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9XG59XG4iLCAie1xuICBcImFzaWRlXCI6IHtcbiAgICBcInRyYW5zbGF0ZVwiOiB7XG4gICAgICBcInRpdGxlXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiXHU3RkZCXHU4QTMzIFx1RDgzQ1x1REYwRFwiXG4gICAgICB9LFxuICAgICAgXCJkZXNjcmlwdGlvblwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlx1MzA1M1x1MzA2RVx1MzBEQVx1MzBGQ1x1MzBCOFx1MzA2RVx1N0ZGQlx1OEEzM1x1MzA5Mlx1ODg0Q1x1MzA2M1x1MzA1Rlx1MzA4QVx1MzAwMVx1NjUzOVx1NTU4NFx1MzA1N1x1MzA1Rlx1MzA4QVx1MzA1OVx1MzA4Qlx1MzA1M1x1MzA2OFx1MzA0Q1x1MzA2N1x1MzA0RFx1MzA3RVx1MzA1OVx1MzAwMlwiXG4gICAgICB9LFxuICAgICAgXCJjdGFcIjoge1xuICAgICAgICBcInRleHRcIjogXCJcdTMwQjNcdTMwRjNcdTMwQzhcdTMwRUFcdTMwRDNcdTMwRTVcdTMwRkNcdTMwQzhcdTMwNTlcdTMwOEJcIlxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzZWFyY2hcIjoge1xuICAgIFwicGxhY2Vob2xkZXJcIjogXCJcdTY5MUNcdTdEMjJcIixcbiAgICBcInRyYW5zbGF0aW9uc1wiOiB7XG4gICAgICBcImJ1dHRvblwiOiB7XG4gICAgICAgIFwiYnV0dG9uLXRleHRcIjogXCJcdTMwQzlcdTMwQURcdTMwRTVcdTMwRTFcdTMwRjNcdTMwQzhcdTMwOTJcdTY5MUNcdTdEMjJcIixcbiAgICAgICAgXCJidXR0b24tYXJpYS1sYWJlbFwiOiBcIlx1MzBDOVx1MzBBRFx1MzBFNVx1MzBFMVx1MzBGM1x1MzBDOFx1MzA5Mlx1NjkxQ1x1N0QyMlwiXG4gICAgICB9LFxuICAgICAgXCJtb2RhbFwiOiB7XG4gICAgICAgIFwic2VhcmNoLWJveFwiOiB7XG4gICAgICAgICAgXCJyZXNldC1idXR0b24tdGl0bGVcIjogXCJcdTY5MUNcdTdEMjJcdTMwQURcdTMwRkNcdTMwRUZcdTMwRkNcdTMwQzlcdTMwOTJcdTUyNEFcdTk2NjRcIixcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiXHU2OTFDXHU3RDIyXHUzMEFEXHUzMEZDXHUzMEVGXHUzMEZDXHUzMEM5XHUzMDkyXHU1MjRBXHU5NjY0XCIsXG4gICAgICAgICAgXCJjYW5jZWwtYnV0dG9uLXRleHRcIjogXCJcdTMwQURcdTMwRTNcdTMwRjNcdTMwQkJcdTMwRUJcIixcbiAgICAgICAgICBcImNhbmNlbC1idXR0b24tYXJpYS1sYWJlbFwiOiBcIlx1MzBBRFx1MzBFM1x1MzBGM1x1MzBCQlx1MzBFQlwiXG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhcnQtc2NyZWVuXCI6IHtcbiAgICAgICAgICBcInJlY2VudC1zZWFyY2hlcy10aXRsZVwiOiBcIlx1NUM2NVx1NkI3NFx1MzA5Mlx1NjkxQ1x1N0QyMlwiLFxuICAgICAgICAgIFwibm8tcmVjZW50LXNlYXJjaGVzLXRleHRcIjogXCJcdTY5MUNcdTdEMjJcdTVDNjVcdTZCNzRcdTMwNkZcdTMwNDJcdTMwOEFcdTMwN0VcdTMwNUJcdTMwOTNcIixcbiAgICAgICAgICBcInNhdmUtcmVjZW50LXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJcdTY5MUNcdTdEMjJcdTVDNjVcdTZCNzRcdTMwNkJcdTRGRERcdTVCNThcIixcbiAgICAgICAgICBcInJlbW92ZS1yZWNlbnQtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlx1NjkxQ1x1N0QyMlx1NUM2NVx1NkI3NFx1MzA0Qlx1MzA4OVx1NTI0QVx1OTY2NFx1MzA1OVx1MzA4QlwiLFxuICAgICAgICAgIFwiZmF2b3JpdGUtc2VhcmNoZXMtdGl0bGVcIjogXCJcdTMwNEFcdTZDMTdcdTMwNkJcdTUxNjVcdTMwOEFcIixcbiAgICAgICAgICBcInJlbW92ZS1mYXZvcml0ZS1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiXHUzMDRBXHU2QzE3XHUzMDZCXHU1MTY1XHUzMDhBXHUzMDRCXHUzMDg5XHU1MjRBXHU5NjY0XCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJlcnJvci1zY3JlZW5cIjoge1xuICAgICAgICAgIFwidGl0bGUtdGV4dFwiOiBcIlx1N0Q1MFx1Njc5Q1x1MzA5Mlx1NTNENlx1NUY5N1x1MzA2N1x1MzA0RFx1MzA3RVx1MzA1Qlx1MzA5M1x1MzA2N1x1MzA1N1x1MzA1RlwiLFxuICAgICAgICAgIFwiaGVscC10ZXh0XCI6IFwiXHUzMENEXHUzMEMzXHUzMEM4XHUzMEVGXHUzMEZDXHUzMEFGXHU2M0E1XHU3RDlBXHUzMDkyXHU3OEJBXHU4QThEXHUzMDU3XHUzMDY2XHUzMDRGXHUzMDYwXHUzMDU1XHUzMDQ0XCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJmb290ZXJcIjoge1xuICAgICAgICAgIFwic2VsZWN0LXRleHRcIjogXCJcdTkwNzhcdTYyOUVcIixcbiAgICAgICAgICBcIm5hdmlnYXRlLXRleHRcIjogXCJcdTc5RkJcdTUyRDVcIixcbiAgICAgICAgICBcImNsb3NlLXRleHRcIjogXCJcdTk1ODlcdTMwNThcdTMwOEJcIixcbiAgICAgICAgICBcInNlYXJjaC1ieS10ZXh0XCI6IFwiXHU2OTFDXHU3RDIyXHUzMEQ3XHUzMEVEXHUzMEQwXHUzMEE0XHUzMEMwXHUzMEZDXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJuby1yZXN1bHRzLXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJuby1yZXN1bHRzLXRleHRcIjogXCJcdTk1QTJcdTkwMjNcdTMwNTlcdTMwOEJcdTdENTBcdTY3OUNcdTMwNENcdTg5OEJcdTMwNjRcdTMwNEJcdTMwOEFcdTMwN0VcdTMwNUJcdTMwOTNcdTMwNjdcdTMwNTdcdTMwNUZcIixcbiAgICAgICAgICBcInN1Z2dlc3RlZC1xdWVyeS10ZXh0XCI6IFwiXHUzMEFGXHUzMEE4XHUzMEVBXHUzMDkyXHU4QTY2XHUzMDU3XHUzMDY2XHUzMDdGXHUzMDhCXHUzMDUzXHUzMDY4XHUzMDRDXHUzMDY3XHUzMDREXHUzMDdFXHUzMDU5XCIsXG4gICAgICAgICAgXCJyZXBvcnQtbWlzc2luZy1yZXN1bHRzLXRleHRcIjogXCJcdTMwNTNcdTMwNkVcdTMwQUZcdTMwQThcdTMwRUFcdTMwNkJcdTMwNkZcdTdENTBcdTY3OUNcdTMwNENcdTMwNDJcdTMwOEJcdTMwNjhcdTYwMURcdTMwNDRcdTMwN0VcdTMwNTlcdTMwNEI/XCIsXG4gICAgICAgICAgXCJyZXBvcnQtbWlzc2luZy1yZXN1bHRzLWxpbmstdGV4dFwiOiBcIlx1MzBBRlx1MzBFQVx1MzBDM1x1MzBBRlx1MzA1N1x1MzA2Nlx1MzBENVx1MzBBM1x1MzBGQ1x1MzBDOVx1MzBEMFx1MzBDM1x1MzBBRlx1MzA1OVx1MzA4QlwiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwiYmFkZ2VzXCI6IHtcbiAgICBcImNvbWluZy1zb29uXCI6IFwiXHU4RkQxXHU2NUU1XHU1MTZDXHU5NThCXCIsXG4gICAgXCJ4Y29kZXByb2otY29tcGF0aWJsZVwiOiBcIlhjb2RlUHJvalx1NEU5Mlx1NjNEQlwiXG4gIH0sXG4gIFwibmF2YmFyXCI6IHtcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJcdTMwQUNcdTMwQTRcdTMwQzlcIlxuICAgIH0sXG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCJcbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1MzBCNVx1MzBGQ1x1MzBEMFx1MzBGQ1wiXG4gICAgfSxcbiAgICBcInJlc291cmNlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJcdTMwRUFcdTMwQkRcdTMwRkNcdTMwQjlcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInJlZmVyZW5jZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBFQVx1MzBENVx1MzBBMVx1MzBFQ1x1MzBGM1x1MzBCOVwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwQjNcdTMwRjNcdTMwQzhcdTMwRUFcdTMwRDNcdTMwRTVcdTMwRkNcdTMwQkZcdTMwRkNcIlxuICAgICAgICB9LFxuICAgICAgICBcImNoYW5nZWxvZ1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU1OTA5XHU2NkY0XHU1QzY1XHU2Qjc0XCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzaWRlYmFyc1wiOiB7XG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJjb21tYW5kc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEIzXHUzMERFXHUzMEYzXHUzMEM5XCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJyZWZlcmVuY2VzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1MzBFQVx1MzBENVx1MzBBMVx1MzBFQ1x1MzBGM1x1MzBCOVwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiZXhhbXBsZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBCNVx1MzBGM1x1MzBEN1x1MzBFQlwiXG4gICAgICAgIH0sXG4gICAgICAgIFwibWlncmF0aW9uc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMERFXHUzMEE0XHUzMEIwXHUzMEVDXHUzMEZDXHUzMEI3XHUzMEU3XHUzMEYzXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImZyb20tdjMtdG8tdjRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJ2MyBcdTMwNEJcdTMwODkgdjQgXHUzMDc4XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1MzBCM1x1MzBGM1x1MzBDOFx1MzBFQVx1MzBEM1x1MzBFNVx1MzBGQ1x1MzBCRlx1MzBGQ1wiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiZ2V0LXN0YXJ0ZWRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1NTlDQlx1MzA4MVx1NjVCOVwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiaXNzdWUtcmVwb3J0aW5nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJJc3N1ZVx1NTgzMVx1NTQ0QVwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY29kZS1yZXZpZXdzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwQjNcdTMwRkNcdTMwQzlcdTMwRUNcdTMwRDNcdTMwRTVcdTMwRkNcIlxuICAgICAgICB9LFxuICAgICAgICBcInByaW5jaXBsZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1NTM5Rlx1NTI0N1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwidHJhbnNsYXRlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTdGRkJcdThBMzNcdTMwNTlcdTMwOEJcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcInNlcnZlclwiOiB7XG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJpbnRyb2R1Y3Rpb25cIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzA2Rlx1MzA1OFx1MzA4MVx1MzA2QlwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJ3aHktc2VydmVyXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMDZBXHUzMDVDXHUzMEI1XHUzMEZDXHUzMEQwXHUzMEZDXHUzMDRDXHU1RkM1XHU4OTgxXHUzMDZBXHUzMDZFXHUzMDRCXHVGRjFGXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImFjY291bnRzLWFuZC1wcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBBMlx1MzBBQlx1MzBBNlx1MzBGM1x1MzBDOFx1MzA2OFx1MzBEN1x1MzBFRFx1MzBCOFx1MzBBN1x1MzBBRlx1MzBDOFwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJhdXRoZW50aWNhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1OEE4RFx1OEEzQ1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJpbnRlZ3JhdGlvbnNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwQTRcdTMwRjNcdTMwQzZcdTMwQjBcdTMwRUNcdTMwRkNcdTMwQjdcdTMwRTdcdTMwRjNcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJvbi1wcmVtaXNlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwQUFcdTMwRjNcdTMwRDdcdTMwRUNcdTMwREZcdTMwQjlcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiaW5zdGFsbFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBBNFx1MzBGM1x1MzBCOVx1MzBDOFx1MzBGQ1x1MzBFQlwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJtZXRyaWNzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEUxXHUzMEM4XHUzMEVBXHUzMEFGXHUzMEI5XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiYXBpLWRvY3VtZW50YXRpb25cIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkFQSVx1MzBDOVx1MzBBRFx1MzBFNVx1MzBFMVx1MzBGM1x1MzBDOFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhdHVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwQjlcdTMwQzZcdTMwRkNcdTMwQkZcdTMwQjlcIlxuICAgICAgICB9LFxuICAgICAgICBcIm1ldHJpY3MtZGFzaGJvYXJkXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwRTFcdTMwQzhcdTMwRUFcdTMwQUZcdTMwQjlcdTMwQzBcdTMwQzNcdTMwQjdcdTMwRTVcdTMwRENcdTMwRkNcdTMwQzlcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJcdTMwQUNcdTMwQTRcdTMwQzlcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInF1aWNrLXN0YXJ0XCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwQUZcdTMwQTRcdTMwQzNcdTMwQUZcdTMwQjlcdTMwQkZcdTMwRkNcdTMwQzhcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiaW5zdGFsbC10dWlzdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlR1aXN0XHUzMDZFXHUzMEE0XHUzMEYzXHUzMEI5XHUzMEM4XHUzMEZDXHUzMEVCXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImNyZWF0ZS1hLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwRDdcdTMwRURcdTMwQjhcdTMwQTdcdTMwQUZcdTMwQzhcdTMwNkVcdTRGNUNcdTYyMTBcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwib3B0aW1pemUtd29ya2Zsb3dzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEVGXHUzMEZDXHUzMEFGXHUzMEQ1XHUzMEVEXHUzMEZDXHUzMDZFXHU2NzAwXHU5MDY5XHU1MzE2XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhcnRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzA2Rlx1MzA1OFx1MzA4MVx1MzA0Qlx1MzA1RlwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJuZXctcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1NjVCMFx1ODk4Rlx1MzBEN1x1MzBFRFx1MzBCOFx1MzBBN1x1MzBBRlx1MzBDOFx1MzA2RVx1NEY1Q1x1NjIxMFwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJzd2lmdC1wYWNrYWdlXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU3dpZnQgXHUzMEQxXHUzMEMzXHUzMEIxXHUzMEZDXHUzMEI4XHUzMDY3XHU4QTY2XHUzMDU5XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcIm1pZ3JhdGVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTc5RkJcdTg4NENcdTMwNTlcdTMwOEJcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJ4Y29kZS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlhjb2RlIFx1MzBEN1x1MzBFRFx1MzBCOFx1MzBBN1x1MzBBRlx1MzBDOFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU3dpZnQgXHUzMEQxXHUzMEMzXHUzMEIxXHUzMEZDXHUzMEI4XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwieGNvZGVnZW4tcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJYY29kZUdlbiBcdTMwRDdcdTMwRURcdTMwQjhcdTMwQTdcdTMwQUZcdTMwQzhcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJiYXplbC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkJhemVsIFx1MzBEN1x1MzBFRFx1MzBCOFx1MzBBN1x1MzBBRlx1MzBDOFwiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImRldmVsb3BcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1OTU4Qlx1NzY3QVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJwcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBEN1x1MzBFRFx1MzBCOFx1MzBBN1x1MzBBRlx1MzBDOFwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcIm1hbmlmZXN0c1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwREVcdTMwQ0JcdTMwRDVcdTMwQTdcdTMwQjlcdTMwQzhcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkaXJlY3Rvcnktc3RydWN0dXJlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBDN1x1MzBBM1x1MzBFQ1x1MzBBRlx1MzBDOFx1MzBFQVx1NjlDQlx1NjIxMFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImVkaXRpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU3REU4XHU5NkM2XHU2NUI5XHU2Q0Q1XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZGVwZW5kZW5jaWVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1NEY5RFx1NUI1OFx1OTVBMlx1NEZDMlwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImNvZGUtc2hhcmluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwQjNcdTMwRkNcdTMwQzlcdTMwNkVcdTUxNzFcdTY3MDlcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJzeW50aGVzaXplZC1maWxlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTgxRUFcdTUyRDVcdTc1MUZcdTYyMTBcdTMwRDVcdTMwQTFcdTMwQTRcdTMwRUJcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkeW5hbWljLWNvbmZpZ3VyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU1MkQ1XHU3Njg0XHUzMEIzXHUzMEYzXHUzMEQ1XHUzMEEzXHUzMEFFXHUzMEU1XHUzMEVDXHUzMEZDXHUzMEI3XHUzMEU3XHUzMEYzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidGVtcGxhdGVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBDNlx1MzBGM1x1MzBEN1x1MzBFQ1x1MzBGQ1x1MzBDOFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInBsdWdpbnNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEQ3XHUzMEU5XHUzMEIwXHUzMEE0XHUzMEYzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiaGFzaGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwQ0ZcdTMwQzNcdTMwQjdcdTMwRTVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0aGUtY29zdC1vZi1jb252ZW5pZW5jZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTUyMjlcdTRGQkZcdTYwMjdcdTMwNkVcdTRFRTNcdTUxMUZcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0bWEtYXJjaGl0ZWN0dXJlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBFMlx1MzBCOFx1MzBFNVx1MzBGQ1x1MzBFOVx1MzBGQ1x1MzBBMlx1MzBGQ1x1MzBBRFx1MzBDNlx1MzBBRlx1MzBDMVx1MzBFM1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImJlc3QtcHJhY3RpY2VzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBEOVx1MzBCOVx1MzBDOFx1MzBEN1x1MzBFOVx1MzBBRlx1MzBDNlx1MzBBM1x1MzBCOVwiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJidWlsZFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBEM1x1MzBFQlx1MzBDOVwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcImNhY2hlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBBRFx1MzBFM1x1MzBDM1x1MzBCN1x1MzBFNVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInJlZ2lzdHJ5XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlJlZ2lzdHJ5XCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInRlc3RcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwQzZcdTMwQjlcdTMwQzhcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJzZWxlY3RpdmUtdGVzdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTZWxlY3RpdmUgdGVzdGluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImZsYWtpbmVzc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJGbGFreSBcdTMwNkFcdTMwQzZcdTMwQjlcdTMwQzhcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiaW5zcGVjdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1NjkxQ1x1NjdGQlwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcImltcGxpY2l0LWltcG9ydHNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU2Njk3XHU5RUQ5XHUzMDZFXHUzMEE0XHUzMEYzXHUzMEREXHUzMEZDXHUzMEM4XCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImF1dG9tYXRlXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU4MUVBXHU1MkQ1XHU1MzE2XCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwiY29udGludW91cy1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTdEOTlcdTdEOUFcdTc2ODRcdTMwQTRcdTMwRjNcdTMwQzZcdTMwQjBcdTMwRUNcdTMwRkNcdTMwQjdcdTMwRTdcdTMwRjNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ3b3JrZmxvd3NcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEVGXHUzMEZDXHUzMEFGXHUzMEQ1XHUzMEVEXHUzMEZDXCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwic2hhcmVcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1NTE3MVx1NjcwOVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJwcmV2aWV3c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBEN1x1MzBFQ1x1MzBEM1x1MzBFNVx1MzBGQ1x1NkE1Rlx1ODBGRFwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9XG59XG4iLCAie1xuICBcImFzaWRlXCI6IHtcbiAgICBcInRyYW5zbGF0ZVwiOiB7XG4gICAgICBcInRpdGxlXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiVHJhZHVjY2lcdTAwRjNuIFx1RDgzQ1x1REYwRFwiXG4gICAgICB9LFxuICAgICAgXCJkZXNjcmlwdGlvblwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlRyYWR1Y2UgbyBtZWpvcmEgbGEgdHJhZHVjY2lcdTAwRjNuIGRlIGVzdGEgcFx1MDBFMWdpbmEuXCJcbiAgICAgIH0sXG4gICAgICBcImN0YVwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIkNvbnRyaWJ1eWVcIlxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzZWFyY2hcIjoge1xuICAgIFwicGxhY2Vob2xkZXJcIjogXCJCdXNjYVwiLFxuICAgIFwidHJhbnNsYXRpb25zXCI6IHtcbiAgICAgIFwiYnV0dG9uXCI6IHtcbiAgICAgICAgXCJidXR0b24tdGV4dFwiOiBcIkJ1c2NhIGVuIGxhIGRvY3VtZW50YWNpXHUwMEYzblwiLFxuICAgICAgICBcImJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiQnVzY2EgZW4gbGEgZG9jdW1lbnRhY2lcdTAwRjNuXCJcbiAgICAgIH0sXG4gICAgICBcIm1vZGFsXCI6IHtcbiAgICAgICAgXCJzZWFyY2gtYm94XCI6IHtcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi10aXRsZVwiOiBcIkxpbXBpYXIgdFx1MDBFOXJtaW5vIGRlIGJcdTAwRkFzcXVlZGFcIixcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiTGltcGlhciB0XHUwMEU5cm1pbm8gZGUgYlx1MDBGQXNxdWVkYVwiLFxuICAgICAgICAgIFwiY2FuY2VsLWJ1dHRvbi10ZXh0XCI6IFwiQ2FuY2VsYXJcIixcbiAgICAgICAgICBcImNhbmNlbC1idXR0b24tYXJpYS1sYWJlbFwiOiBcIkNhbmNlbGFyXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJzdGFydC1zY3JlZW5cIjoge1xuICAgICAgICAgIFwicmVjZW50LXNlYXJjaGVzLXRpdGxlXCI6IFwiSGlzdG9yaWFsIGRlIGJcdTAwRkFzcXVlZGFcIixcbiAgICAgICAgICBcIm5vLXJlY2VudC1zZWFyY2hlcy10ZXh0XCI6IFwiTm8gaGF5IGhpc3RvcmlhbCBkZSBiXHUwMEZBc3F1ZWRhXCIsXG4gICAgICAgICAgXCJzYXZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiR3VhcmRhciBlbiBlbCBoaXN0b3JpYWwgZGUgYlx1MDBGQXNxdWVkYVwiLFxuICAgICAgICAgIFwicmVtb3ZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiRWxpbWluYXIgZGVsIGhpc3RvcmlhbCBkZSBiXHUwMEZBc3F1ZWRhXCIsXG4gICAgICAgICAgXCJmYXZvcml0ZS1zZWFyY2hlcy10aXRsZVwiOiBcIkZhdm9yaXRvc1wiLFxuICAgICAgICAgIFwicmVtb3ZlLWZhdm9yaXRlLXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJFbGltaW5hciBkZSBmYXZvcml0b3NcIlxuICAgICAgICB9LFxuICAgICAgICBcImVycm9yLXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJ0aXRsZS10ZXh0XCI6IFwiSW1wb3NpYmxlIG9idGVuZXIgcmVzdWx0YWRvc1wiLFxuICAgICAgICAgIFwiaGVscC10ZXh0XCI6IFwiQ29tcHJ1ZWJhIHR1IGNvbmV4aVx1MDBGM24gYSBJbnRlcm5ldFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiZm9vdGVyXCI6IHtcbiAgICAgICAgICBcInNlbGVjdC10ZXh0XCI6IFwiU2VsZWNjaW9uYVwiLFxuICAgICAgICAgIFwibmF2aWdhdGUtdGV4dFwiOiBcIk5hdmVnYXJcIixcbiAgICAgICAgICBcImNsb3NlLXRleHRcIjogXCJDZXJyYXJcIixcbiAgICAgICAgICBcInNlYXJjaC1ieS10ZXh0XCI6IFwiUHJvdmVlZG9yIGRlIGJcdTAwRkFzcXVlZGFcIlxuICAgICAgICB9LFxuICAgICAgICBcIm5vLXJlc3VsdHMtc2NyZWVuXCI6IHtcbiAgICAgICAgICBcIm5vLXJlc3VsdHMtdGV4dFwiOiBcIk5vIHNlIGVuY29udHJhcm9uIHJlc3VsdGFkb3MgcmVsZXZhbnRlc1wiLFxuICAgICAgICAgIFwic3VnZ2VzdGVkLXF1ZXJ5LXRleHRcIjogXCJQb2RyXHUwMEVEYXMgaW50ZW50YXIgY29uc3VsdGFyXCIsXG4gICAgICAgICAgXCJyZXBvcnQtbWlzc2luZy1yZXN1bHRzLXRleHRcIjogXCJcdTAwQkZDcmVlIHF1ZSBlc3RhIGNvbnN1bHRhIGRlYmVyXHUwMEVEYSB0ZW5lciByZXN1bHRhZG9zP1wiLFxuICAgICAgICAgIFwicmVwb3J0LW1pc3NpbmctcmVzdWx0cy1saW5rLXRleHRcIjogXCJIYXogY2xpYyBwYXJhIGRhciB0dSBvcGluaVx1MDBGM25cIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9LFxuICBcImJhZGdlc1wiOiB7XG4gICAgXCJjb21pbmctc29vblwiOiBcIkRpc3BvbmlibGUgcHJcdTAwRjN4aW1hbWVudGVcIixcbiAgICBcInhjb2RlcHJvai1jb21wYXRpYmxlXCI6IFwiQ29tcGF0aWJsZSBjb24gWGNvZGVQcm9qXCJcbiAgfSxcbiAgXCJuYXZiYXJcIjoge1xuICAgIFwiZ3VpZGVzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkd1XHUwMEVEYXNcIlxuICAgIH0sXG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCJcbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlNlcnZpZG9yXCJcbiAgICB9LFxuICAgIFwicmVzb3VyY2VzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlJlY3Vyc29zXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJyZWZlcmVuY2VzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJSZWZlcmVuY2lhc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDb2xhYm9yYWRvcmVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjaGFuZ2Vsb2dcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNoYW5nZWxvZ1wiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwic2lkZWJhcnNcIjoge1xuICAgIFwiY2xpXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNMSVwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiY29tbWFuZHNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNvbWFuZG9zXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJyZWZlcmVuY2VzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlJlZmVyZW5jaWFzXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJleGFtcGxlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiRWplbXBsb3NcIlxuICAgICAgICB9LFxuICAgICAgICBcIm1pZ3JhdGlvbnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIk1pZ3JhY2lvbmVzXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImZyb20tdjMtdG8tdjRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJEZSB2MyBhIHY0XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNvbGFib3JhZG9yZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImdldC1zdGFydGVkXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDb21lbnphclwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiaXNzdWUtcmVwb3J0aW5nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJSZXBvcnRlIGRlIElzc3Vlc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY29kZS1yZXZpZXdzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJSZXZpc2lcdTAwRjNuIGRlIGNcdTAwRjNkaWdvXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJwcmluY2lwbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJQcmluY2lwaW9zXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlRyYWR1Y2VcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcInNlcnZlclwiOiB7XG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJpbnRyb2R1Y3Rpb25cIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkludHJvZHVjY2lcdTAwRjNuXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIndoeS1zZXJ2ZXJcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTAwQkZQb3IgcXVcdTAwRTkgdW4gc2Vydmlkb3I/XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImFjY291bnRzLWFuZC1wcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkN1ZW50YXMgeSBwcm95ZWN0b3NcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYXV0aGVudGljYXRpb25cIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJBdXRlbnRpZmljYWNpXHUwMEYzblwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJpbnRlZ3JhdGlvbnNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnRlZ3JhY2lvbmVzXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwib24tcHJlbWlzZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiT24tcHJlbWlzZVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zdGFsYVwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJtZXRyaWNzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTVx1MDBFOXRyaWNhc1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImFwaS1kb2N1bWVudGF0aW9uXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJEb2N1bWVudGFjaVx1MDBGM24gZGUgbGEgQVBJXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJzdGF0dXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkVzdGFkb1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwibWV0cmljcy1kYXNoYm9hcmRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlBhbmVsIGRlIG1cdTAwRTl0cmljYXNcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJHdVx1MDBFRGFzXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJxdWljay1zdGFydFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiUXVpY2sgU3RhcnRcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiaW5zdGFsbC10dWlzdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3RhbGEgVHVpc3RcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiY3JlYXRlLWEtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNyZWEgdW4gcHJveWVjdG9cIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwib3B0aW1pemUtd29ya2Zsb3dzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiT3B0aW1pemEgd29ya2Zsb3dzXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhcnRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkVtcGllemFcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibmV3LXByb2plY3RcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJDcmVhIHVuIG51ZXZvIHByb3llY3RvXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJQcnVlYmEgY29uIHVuIHBhcXVldGUgZGUgU3dpZnRcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwibWlncmF0ZVwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1pZ3JhXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwieGNvZGUtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJVbiBwcm95ZWN0byBkZSBYY29kZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVW4gcGFxdWV0ZSBkZSBTd2lmdFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInhjb2RlZ2VuLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVW4gcHJveWVjdG8gWGNvZGVHZW5cIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJiYXplbC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlVuIHByb3llY3RvIEJhemVsXCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiZGV2ZWxvcFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiRGVzYXJyb2xsYVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJwcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlByb3llY3Rvc1wiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcIm1hbmlmZXN0c1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJGaWNoZXJvcyBtYW5pZmVzdFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImRpcmVjdG9yeS1zdHJ1Y3R1cmVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRXN0cnVjdHVyYSBkZSBkaXJlY3Rvcmlvc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImVkaXRpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRWRpY2lcdTAwRjNuXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZGVwZW5kZW5jaWVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkRlcGVuZGVuY2lhc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImNvZGUtc2hhcmluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJDb21wYXJ0aXIgY1x1MDBGM2RpZ29cIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJzeW50aGVzaXplZC1maWxlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTaW50ZXRpemFkbyBkZSBmaWNoZXJvc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImR5bmFtaWMtY29uZmlndXJhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJDb25maWd1cmFjaVx1MDBGM24gZGluXHUwMEUxbWljYVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRlbXBsYXRlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJQbGFudGlsbGFzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwicGx1Z2luc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJQbHVnaW5zXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiaGFzaGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJIYXNoZWFkb1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRoZS1jb3N0LW9mLWNvbnZlbmllbmNlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkVsIGNvc3RlIGRlIGxhIGNvbnZlbmllbmNpYVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRtYS1hcmNoaXRlY3R1cmVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQXJjaGl0ZWN0dXJhIG1vZHVsYXJcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJiZXN0LXByYWN0aWNlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJCdWVuYXMgcHJcdTAwRTFjdGljYXNcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYnVpbGRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJDb21waWxhXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwiY2FjaGVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ2FjaGVhXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwicmVnaXN0cnlcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUmVnaXN0cnlcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwidGVzdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlRlc3RlYVwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcInNlbGVjdGl2ZS10ZXN0aW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlNlbGVjdGl2ZSB0ZXN0aW5nXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZmxha2luZXNzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkZsYWtpbmVzc1wiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJpbnNwZWN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zcGVjY2lvbmFcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJpbXBsaWNpdC1pbXBvcnRzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkltcG9ydHMgaW1wbFx1MDBFRGNpdG9zXCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImF1dG9tYXRlXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQXV0b21hdGl6YVwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcImNvbnRpbnVvdXMtaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW50ZWdyYWNpXHUwMEYzbiBjb250aW51YVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcIndvcmtmbG93c1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJXb3JrZmxvd3NcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJzaGFyZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29tcGFydGVcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwicHJldmlld3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJQcmV2aWV3c1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9XG59XG4iLCAie1xuICBcImFzaWRlXCI6IHtcbiAgICBcInRyYW5zbGF0ZVwiOiB7XG4gICAgICBcInRpdGxlXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiVHJhbnNsYXRpb24gXHVEODNDXHVERjBEXCJcbiAgICAgIH0sXG4gICAgICBcImRlc2NyaXB0aW9uXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiWW91IGNhbiB0cmFuc2xhdGUgb3IgaW1wcm92ZSB0aGUgdHJhbnNsYXRpb24gb2YgdGhpcyBwYWdlLlwiXG4gICAgICB9LFxuICAgICAgXCJjdGFcIjoge1xuICAgICAgICBcInRleHRcIjogXCJDb250cmlidXRlXCJcbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwic2VhcmNoXCI6IHtcbiAgICBcInBsYWNlaG9sZGVyXCI6IFwiU2VhcmNoXCIsXG4gICAgXCJ0cmFuc2xhdGlvbnNcIjoge1xuICAgICAgXCJidXR0b25cIjoge1xuICAgICAgICBcImJ1dHRvbi10ZXh0XCI6IFwiU2VhcmNoIGRvY3VtZW50YXRpb25cIixcbiAgICAgICAgXCJidXR0b24tYXJpYS1sYWJlbFwiOiBcIlNlYXJjaCBkb2N1bWVudGF0aW9uXCJcbiAgICAgIH0sXG4gICAgICBcIm1vZGFsXCI6IHtcbiAgICAgICAgXCJzZWFyY2gtYm94XCI6IHtcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi10aXRsZVwiOiBcIkNsZWFyIHF1ZXJ5XCIsXG4gICAgICAgICAgXCJyZXNldC1idXR0b24tYXJpYS1sYWJlbFwiOiBcIkNsZWFyIHF1ZXJ5XCIsXG4gICAgICAgICAgXCJjYW5jZWwtYnV0dG9uLXRleHRcIjogXCJDYW5jZWxcIixcbiAgICAgICAgICBcImNhbmNlbC1idXR0b24tYXJpYS1sYWJlbFwiOiBcIkNhbmNlbFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhcnQtc2NyZWVuXCI6IHtcbiAgICAgICAgICBcInJlY2VudC1zZWFyY2hlcy10aXRsZVwiOiBcIlNlYXJjaCBoaXN0b3J5XCIsXG4gICAgICAgICAgXCJuby1yZWNlbnQtc2VhcmNoZXMtdGV4dFwiOiBcIk5vIHNlYXJjaCBoaXN0b3J5XCIsXG4gICAgICAgICAgXCJzYXZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiU2F2ZSB0byBzZWFyY2ggaGlzdG9yeVwiLFxuICAgICAgICAgIFwicmVtb3ZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiUmVtb3ZlIGZyb20gc2VhcmNoIGhpc3RvcnlcIixcbiAgICAgICAgICBcImZhdm9yaXRlLXNlYXJjaGVzLXRpdGxlXCI6IFwiRmF2b3JpdGVzXCIsXG4gICAgICAgICAgXCJyZW1vdmUtZmF2b3JpdGUtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlJlbW92ZSBmcm9tIGZhdm9yaXRlc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiZXJyb3Itc2NyZWVuXCI6IHtcbiAgICAgICAgICBcInRpdGxlLXRleHRcIjogXCJVbmFibGUgdG8gcmV0cmlldmUgcmVzdWx0c1wiLFxuICAgICAgICAgIFwiaGVscC10ZXh0XCI6IFwiWW91IG1heSBuZWVkIHRvIGNoZWNrIHlvdXIgbmV0d29yayBjb25uZWN0aW9uXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJmb290ZXJcIjoge1xuICAgICAgICAgIFwic2VsZWN0LXRleHRcIjogXCJTZWxlY3RcIixcbiAgICAgICAgICBcIm5hdmlnYXRlLXRleHRcIjogXCJOYXZpZ2F0ZVwiLFxuICAgICAgICAgIFwiY2xvc2UtdGV4dFwiOiBcIkNsb3NlXCIsXG4gICAgICAgICAgXCJzZWFyY2gtYnktdGV4dFwiOiBcIlNlYXJjaCBwcm92aWRlclwiXG4gICAgICAgIH0sXG4gICAgICAgIFwibm8tcmVzdWx0cy1zY3JlZW5cIjoge1xuICAgICAgICAgIFwibm8tcmVzdWx0cy10ZXh0XCI6IFwiTm8gcmVsZXZhbnQgcmVzdWx0cyBmb3VuZFwiLFxuICAgICAgICAgIFwic3VnZ2VzdGVkLXF1ZXJ5LXRleHRcIjogXCJZb3UgbWlnaHQgdHJ5IHF1ZXJ5aW5nXCIsXG4gICAgICAgICAgXCJyZXBvcnQtbWlzc2luZy1yZXN1bHRzLXRleHRcIjogXCJEbyB5b3UgdGhpbmsgdGhpcyBxdWVyeSBzaG91bGQgaGF2ZSByZXN1bHRzP1wiLFxuICAgICAgICAgIFwicmVwb3J0LW1pc3NpbmctcmVzdWx0cy1saW5rLXRleHRcIjogXCJDbGljayB0byBnaXZlIGZlZWRiYWNrXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJiYWRnZXNcIjoge1xuICAgIFwiY29taW5nLXNvb25cIjogXCJDb21pbmcgc29vblwiLFxuICAgIFwieGNvZGVwcm9qLWNvbXBhdGlibGVcIjogXCJYY29kZVByb2otY29tcGF0aWJsZVwiXG4gIH0sXG4gIFwibmF2YmFyXCI6IHtcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJHdWlkZXNcIlxuICAgIH0sXG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCJcbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlNlcnZlclwiXG4gICAgfSxcbiAgICBcInJlc291cmNlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJSZXNvdXJjZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInJlZmVyZW5jZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlJlZmVyZW5jZXNcIlxuICAgICAgICB9LFxuICAgICAgICBcImNvbnRyaWJ1dG9yc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29udHJpYnV0b3JzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjaGFuZ2Vsb2dcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNoYW5nZWxvZ1wiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwic2lkZWJhcnNcIjoge1xuICAgIFwiY2xpXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNMSVwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiY29tbWFuZHNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNvbW1hbmRzXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJyZWZlcmVuY2VzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlJlZmVyZW5jZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImV4YW1wbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJFeGFtcGxlc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwibWlncmF0aW9uc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiTWlncmF0aW9uc1wiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJmcm9tLXYzLXRvLXY0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRnJvbSB2MyB0byB2NFwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImNvbnRyaWJ1dG9yc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJDb250cmlidXRvcnNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImdldC1zdGFydGVkXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJHZXQgc3RhcnRlZFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiaXNzdWUtcmVwb3J0aW5nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJJc3N1ZSByZXBvcnRpbmdcIlxuICAgICAgICB9LFxuICAgICAgICBcImNvZGUtcmV2aWV3c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29kZSByZXZpZXdzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJwcmluY2lwbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJQcmluY2lwbGVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlRyYW5zbGF0ZVwiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImludHJvZHVjdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiSW50cm9kdWN0aW9uXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIndoeS1zZXJ2ZXJcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJXaHkgYSBzZXJ2ZXI/XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImFjY291bnRzLWFuZC1wcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFjY291bnRzIGFuZCBwcm9qZWN0c1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJhdXRoZW50aWNhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkF1dGhlbnRpY2F0aW9uXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImludGVncmF0aW9uc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkludGVncmF0aW9uc1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcIm9uLXByZW1pc2VcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIk9uLXByZW1pc2VcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiaW5zdGFsbFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3RhbGxcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwibWV0cmljc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1ldHJpY3NcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJhcGktZG9jdW1lbnRhdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQVBJIGRvY3VtZW50YXRpb25cIlxuICAgICAgICB9LFxuICAgICAgICBcInN0YXR1c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiU3RhdHVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJtZXRyaWNzLWRhc2hib2FyZFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiTWV0cmljcyBkYXNoYm9hcmRcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJHdWlkZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInF1aWNrLXN0YXJ0XCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJRdWljayBzdGFydFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsLXR1aXN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zdGFsbCBUdWlzdFwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJjcmVhdGUtYS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ3JlYXRlIGEgcHJvamVjdFwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJvcHRpbWl6ZS13b3JrZmxvd3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJPcHRpbWl6ZSB3b3JrZmxvd3NcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJzdGFydFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiU3RhcnRcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibmV3LXByb2plY3RcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJDcmVhdGUgYSBuZXcgcHJvamVjdFwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJzd2lmdC1wYWNrYWdlXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVHJ5IHdpdGggYSBTd2lmdCBQYWNrYWdlXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcIm1pZ3JhdGVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJNaWdyYXRlXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwieGNvZGUtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBbiBYY29kZSBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBIFN3aWZ0IHBhY2thZ2VcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZWdlbi1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFuIFhjb2RlR2VuIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJiYXplbC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkEgQmF6ZWwgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImRldmVsb3BcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkRldmVsb3BcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwicHJvamVjdHNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJQcm9qZWN0c1wiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcIm1hbmlmZXN0c1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJNYW5pZmVzdHNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkaXJlY3Rvcnktc3RydWN0dXJlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkRpcmVjdG9yeSBzdHJ1Y3R1cmVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJlZGl0aW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkVkaXRpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkZXBlbmRlbmNpZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRGVwZW5kZW5jaWVzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiY29kZS1zaGFyaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvZGUgc2hhcmluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInN5bnRoZXNpemVkLWZpbGVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlN5bnRoZXNpemVkIGZpbGVzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZHluYW1pYy1jb25maWd1cmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkR5bmFtaWMgY29uZmlndXJhdGlvblwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRlbXBsYXRlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJUZW1wbGF0ZXNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJwbHVnaW5zXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlBsdWdpbnNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJoYXNoaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkhhc2hpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0aGUtY29zdC1vZi1jb252ZW5pZW5jZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJUaGUgY29zdCBvZiBjb252ZW5pZW5jZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRtYS1hcmNoaXRlY3R1cmVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTW9kdWxhciBhcmNoaXRlY3R1cmVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJiZXN0LXByYWN0aWNlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJCZXN0IHByYWN0aWNlc1wiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJidWlsZFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkJ1aWxkXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwiY2FjaGVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ2FjaGVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJyZWdpc3RyeVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJSZWdpc3RyeVwiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJ0ZXN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVGVzdFwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcInNlbGVjdGl2ZS10ZXN0aW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlNlbGVjdGl2ZSB0ZXN0aW5nXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZmxha2luZXNzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkZsYWtpbmVzc1wiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJpbnNwZWN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zcGVjdFwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcImltcGxpY2l0LWltcG9ydHNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW1wbGljaXQgaW1wb3J0c1wiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJhdXRvbWF0ZVwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkF1dG9tYXRlXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwiY29udGludW91cy1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJDb250aW51b3VzIGludGVncmF0aW9uXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwid29ya2Zsb3dzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIldvcmtmbG93c1wiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcInNoYXJlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJTaGFyZVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJwcmV2aWV3c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlByZXZpZXdzXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH1cbn1cbiIsICJjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9maWxlbmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9pMThuLm1qc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9pbXBvcnRfbWV0YV91cmwgPSBcImZpbGU6Ly8vVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2kxOG4ubWpzXCI7aW1wb3J0IGVuU3RyaW5ncyBmcm9tIFwiLi9zdHJpbmdzL2VuLmpzb25cIjtcbmltcG9ydCBydVN0cmluZ3MgZnJvbSBcIi4vc3RyaW5ncy9ydS5qc29uXCI7XG5pbXBvcnQga29TdHJpbmdzIGZyb20gXCIuL3N0cmluZ3Mva28uanNvblwiO1xuaW1wb3J0IGphU3RyaW5ncyBmcm9tIFwiLi9zdHJpbmdzL2phLmpzb25cIjtcbmltcG9ydCBlc1N0cmluZ3MgZnJvbSBcIi4vc3RyaW5ncy9lcy5qc29uXCI7XG5pbXBvcnQgcHRTdHJpbmdzIGZyb20gXCIuL3N0cmluZ3MvcHQuanNvblwiO1xuXG5jb25zdCBzdHJpbmdzID0ge1xuICBlbjogZW5TdHJpbmdzLFxuICBydTogcnVTdHJpbmdzLFxuICBrbzoga29TdHJpbmdzLFxuICBqYTogamFTdHJpbmdzLFxuICBlczogZXNTdHJpbmdzLFxuICBwdDogcHRTdHJpbmdzLFxufTtcblxuZXhwb3J0IGZ1bmN0aW9uIGxvY2FsaXplZFN0cmluZyhsb2NhbGUsIGtleSkge1xuICBjb25zdCBnZXRTdHJpbmcgPSAobG9jYWxlU3RyaW5ncywga2V5KSA9PiB7XG4gICAgY29uc3Qga2V5cyA9IGtleS5zcGxpdChcIi5cIik7XG4gICAgbGV0IGN1cnJlbnQgPSBsb2NhbGVTdHJpbmdzO1xuXG4gICAgZm9yIChjb25zdCBrIG9mIGtleXMpIHtcbiAgICAgIGlmIChjdXJyZW50ICYmIGN1cnJlbnQuaGFzT3duUHJvcGVydHkoaykpIHtcbiAgICAgICAgY3VycmVudCA9IGN1cnJlbnRba107XG4gICAgICB9IGVsc2Uge1xuICAgICAgICByZXR1cm4gdW5kZWZpbmVkO1xuICAgICAgfVxuICAgIH1cbiAgICByZXR1cm4gY3VycmVudDtcbiAgfTtcblxuICBsZXQgbG9jYWxpemVkVmFsdWUgPSBnZXRTdHJpbmcoc3RyaW5nc1tsb2NhbGVdLCBrZXkpO1xuXG4gIGlmIChsb2NhbGl6ZWRWYWx1ZSA9PT0gdW5kZWZpbmVkICYmIGxvY2FsZSAhPT0gXCJlblwiKSB7XG4gICAgbG9jYWxpemVkVmFsdWUgPSBnZXRTdHJpbmcoc3RyaW5nc1tcImVuXCJdLCBrZXkpO1xuICB9XG5cbiAgcmV0dXJuIGxvY2FsaXplZFZhbHVlO1xufVxuIiwgImNvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ZpbGVuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2JhZGdlcy5tanNcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfaW1wb3J0X21ldGFfdXJsID0gXCJmaWxlOi8vL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9iYWRnZXMubWpzXCI7aW1wb3J0IHsgbG9jYWxpemVkU3RyaW5nIH0gZnJvbSBcIi4vaTE4bi5tanNcIjtcbmV4cG9ydCBmdW5jdGlvbiBjb21pbmdTb29uQmFkZ2UobG9jYWxlKSB7XG4gIHJldHVybiBgPHNwYW4gc3R5bGU9XCJiYWNrZ3JvdW5kOiB2YXIoLS12cC1jdXN0b20tYmxvY2stdGlwLWNvZGUtYmcpOyBjb2xvcjogdmFyKC0tdnAtYy10aXAtMSk7IGZvbnQtc2l6ZTogMTFweDsgZGlzcGxheTogaW5saW5lLWJsb2NrOyBwYWRkaW5nLWxlZnQ6IDVweDsgcGFkZGluZy1yaWdodDogNXB4OyBib3JkZXItcmFkaXVzOiAxMCU7XCI+JHtsb2NhbGl6ZWRTdHJpbmcoXG4gICAgbG9jYWxlLFxuICAgIFwiYmFkZ2VzLmNvbWluZy1zb29uXCJcbiAgKX08L3NwYW4+YDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIHhjb2RlUHJvakNvbXBhdGlibGVCYWRnZShsb2NhbGUpIHtcbiAgcmV0dXJuIGA8c3BhbiBzdHlsZT1cImJhY2tncm91bmQ6IHZhcigtLXZwLWJhZGdlLXdhcm5pbmctYmcpOyBjb2xvcjogdmFyKC0tdnAtYmFkZ2Utd2FybmluZy10ZXh0KTsgZm9udC1zaXplOiAxMXB4OyBkaXNwbGF5OiBpbmxpbmUtYmxvY2s7IHBhZGRpbmctbGVmdDogNXB4OyBwYWRkaW5nLXJpZ2h0OiA1cHg7IGJvcmRlci1yYWRpdXM6IDEwJTtcIj4ke2xvY2FsaXplZFN0cmluZyhcbiAgICBsb2NhbGUsXG4gICAgXCJiYWRnZXMueGNvZGVwcm9qLWNvbXBhdGlibGVcIlxuICApfTwvc3Bhbj5gO1xufVxuIiwgImNvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ZpbGVuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2ljb25zLm1qc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9pbXBvcnRfbWV0YV91cmwgPSBcImZpbGU6Ly8vVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2ljb25zLm1qc1wiO2V4cG9ydCBmdW5jdGlvbiBjdWJlT3V0bGluZUljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuPHBhdGggZD1cIk05Ljc1IDIwLjc1MDFMMTEuMjIzIDIxLjU2ODRDMTEuNTA2NiAyMS43MjYgMTEuNjQ4NCAyMS44MDQ3IDExLjc5ODYgMjEuODM1NkMxMS45MzE1IDIxLjg2MyAxMi4wNjg1IDIxLjg2MyAxMi4yMDE1IDIxLjgzNTZDMTIuMzUxNiAyMS44MDQ3IDEyLjQ5MzQgMjEuNzI2IDEyLjc3NyAyMS41Njg0TDE0LjI1IDIwLjc1MDFNNS4yNSAxOC4yNTAxTDMuODIyOTcgMTcuNDU3M0MzLjUyMzQ2IDE3LjI5MDkgMy4zNzM2OCAxNy4yMDc3IDMuMjY0NjMgMTcuMDg5M0MzLjE2ODE2IDE2Ljk4NDcgMy4wOTUxNSAxNi44NjA2IDMuMDUwNDggMTYuNzI1NEMzIDE2LjU3MjYgMyAxNi40MDEzIDMgMTYuMDU4NlYxNC41MDAxTTMgOS41MDAwOVY3Ljk0MTUzQzMgNy41OTg4OSAzIDcuNDI3NTcgMy4wNTA0OCA3LjI3NDc3QzMuMDk1MTUgNy4xMzk1OSAzLjE2ODE2IDcuMDE1NTEgMy4yNjQ2MyA2LjkxMDgyQzMuMzczNjggNi43OTI0OCAzLjUyMzQ1IDYuNzA5MjggMy44MjI5NyA2LjU0Mjg4TDUuMjUgNS43NTAwOU05Ljc1IDMuMjUwMDhMMTEuMjIzIDIuNDMxNzdDMTEuNTA2NiAyLjI3NDIxIDExLjY0ODQgMi4xOTU0MyAxMS43OTg2IDIuMTY0NTRDMTEuOTMxNSAyLjEzNzIxIDEyLjA2ODUgMi4xMzcyMSAxMi4yMDE1IDIuMTY0NTRDMTIuMzUxNiAyLjE5NTQzIDEyLjQ5MzQgMi4yNzQyMSAxMi43NzcgMi40MzE3N0wxNC4yNSAzLjI1MDA4TTE4Ljc1IDUuNzUwMDhMMjAuMTc3IDYuNTQyODhDMjAuNDc2NiA2LjcwOTI4IDIwLjYyNjMgNi43OTI0OCAyMC43MzU0IDYuOTEwODJDMjAuODMxOCA3LjAxNTUxIDIwLjkwNDkgNy4xMzk1OSAyMC45NDk1IDcuMjc0NzdDMjEgNy40Mjc1NyAyMSA3LjU5ODg5IDIxIDcuOTQxNTNWOS41MDAwOE0yMSAxNC41MDAxVjE2LjA1ODZDMjEgMTYuNDAxMyAyMSAxNi41NzI2IDIwLjk0OTUgMTYuNzI1NEMyMC45MDQ5IDE2Ljg2MDYgMjAuODMxOCAxNi45ODQ3IDIwLjczNTQgMTcuMDg5M0MyMC42MjYzIDE3LjIwNzcgMjAuNDc2NiAxNy4yOTA5IDIwLjE3NyAxNy40NTczTDE4Ljc1IDE4LjI1MDFNOS43NSAxMC43NTAxTDEyIDEyLjAwMDFNMTIgMTIuMDAwMUwxNC4yNSAxMC43NTAxTTEyIDEyLjAwMDFWMTQuNTAwMU0zIDcuMDAwMDhMNS4yNSA4LjI1MDA4TTE4Ljc1IDguMjUwMDhMMjEgNy4wMDAwOE0xMiAxOS41MDAxVjIyLjAwMDFcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuPC9zdmc+XG5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY3ViZTAySWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTEyIDIuNTAwMDhWMTIuMDAwMU0xMiAxMi4wMDAxTDIwLjUgNy4yNzc3OU0xMiAxMi4wMDAxTDMuNSA3LjI3Nzc5TTEyIDEyLjAwMDFWMjEuNTAwMU0yMC41IDE2LjcyMjNMMTIuNzc3IDEyLjQzMThDMTIuNDkzNCAxMi4yNzQyIDEyLjM1MTYgMTIuMTk1NCAxMi4yMDE1IDEyLjE2NDVDMTIuMDY4NSAxMi4xMzcyIDExLjkzMTUgMTIuMTM3MiAxMS43OTg2IDEyLjE2NDVDMTEuNjQ4NCAxMi4xOTU0IDExLjUwNjYgMTIuMjc0MiAxMS4yMjMgMTIuNDMxOEwzLjUgMTYuNzIyM00yMSAxNi4wNTg2VjcuOTQxNTNDMjEgNy41OTg4OSAyMSA3LjQyNzU3IDIwLjk0OTUgNy4yNzQ3N0MyMC45MDQ5IDcuMTM5NTkgMjAuODMxOCA3LjAxNTUxIDIwLjczNTQgNi45MTA4MkMyMC42MjYzIDYuNzkyNDggMjAuNDc2NiA2LjcwOTI4IDIwLjE3NyA2LjU0Mjg4TDEyLjc3NyAyLjQzMTc3QzEyLjQ5MzQgMi4yNzQyMSAxMi4zNTE2IDIuMTk1NDMgMTIuMjAxNSAyLjE2NDU0QzEyLjA2ODUgMi4xMzcyMSAxMS45MzE1IDIuMTM3MjEgMTEuNzk4NiAyLjE2NDU0QzExLjY0ODQgMi4xOTU0MyAxMS41MDY2IDIuMjc0MjEgMTEuMjIzIDIuNDMxNzdMMy44MjI5NyA2LjU0Mjg4QzMuNTIzNDUgNi43MDkyOCAzLjM3MzY5IDYuNzkyNDggMy4yNjQ2MyA2LjkxMDgyQzMuMTY4MTYgNy4wMTU1MSAzLjA5NTE1IDcuMTM5NTkgMy4wNTA0OCA3LjI3NDc3QzMgNy40Mjc1NyAzIDcuNTk4ODkgMyA3Ljk0MTUzVjE2LjA1ODZDMyAxNi40MDEzIDMgMTYuNTcyNiAzLjA1MDQ4IDE2LjcyNTRDMy4wOTUxNSAxNi44NjA2IDMuMTY4MTYgMTYuOTg0NyAzLjI2NDYzIDE3LjA4OTNDMy4zNzM2OSAxNy4yMDc3IDMuNTIzNDUgMTcuMjkwOSAzLjgyMjk3IDE3LjQ1NzNMMTEuMjIzIDIxLjU2ODRDMTEuNTA2NiAyMS43MjYgMTEuNjQ4NCAyMS44MDQ3IDExLjc5ODYgMjEuODM1NkMxMS45MzE1IDIxLjg2MyAxMi4wNjg1IDIxLjg2MyAxMi4yMDE1IDIxLjgzNTZDMTIuMzUxNiAyMS44MDQ3IDEyLjQ5MzQgMjEuNzI2IDEyLjc3NyAyMS41Njg0TDIwLjE3NyAxNy40NTczQzIwLjQ3NjYgMTcuMjkwOSAyMC42MjYzIDE3LjIwNzcgMjAuNzM1NCAxNy4wODkzQzIwLjgzMTggMTYuOTg0NyAyMC45MDQ5IDE2Ljg2MDYgMjAuOTQ5NSAxNi43MjU0QzIxIDE2LjU3MjYgMjEgMTYuNDAxMyAyMSAxNi4wNTg2WlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5cbmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBjdWJlMDFJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNMjAuNSA3LjI3NzgzTDEyIDEyLjAwMDFNMTIgMTIuMDAwMUwzLjQ5OTk3IDcuMjc3ODNNMTIgMTIuMDAwMUwxMiAyMS41MDAxTTIxIDE2LjA1ODZWNy45NDE1M0MyMSA3LjU5ODg5IDIxIDcuNDI3NTcgMjAuOTQ5NSA3LjI3NDc3QzIwLjkwNDkgNy4xMzk1OSAyMC44MzE4IDcuMDE1NTEgMjAuNzM1NCA2LjkxMDgyQzIwLjYyNjMgNi43OTI0OCAyMC40NzY2IDYuNzA5MjggMjAuMTc3IDYuNTQyODhMMTIuNzc3IDIuNDMxNzdDMTIuNDkzNCAyLjI3NDIxIDEyLjM1MTYgMi4xOTU0MyAxMi4yMDE1IDIuMTY0NTRDMTIuMDY4NSAyLjEzNzIxIDExLjkzMTUgMi4xMzcyMSAxMS43OTg2IDIuMTY0NTRDMTEuNjQ4NCAyLjE5NTQzIDExLjUwNjYgMi4yNzQyMSAxMS4yMjMgMi40MzE3N0wzLjgyMjk3IDYuNTQyODhDMy41MjM0NSA2LjcwOTI4IDMuMzczNjkgNi43OTI0OCAzLjI2NDYzIDYuOTEwODJDMy4xNjgxNiA3LjAxNTUxIDMuMDk1MTUgNy4xMzk1OSAzLjA1MDQ4IDcuMjc0NzdDMyA3LjQyNzU3IDMgNy41OTg4OSAzIDcuOTQxNTNWMTYuMDU4NkMzIDE2LjQwMTMgMyAxNi41NzI2IDMuMDUwNDggMTYuNzI1NEMzLjA5NTE1IDE2Ljg2MDYgMy4xNjgxNiAxNi45ODQ3IDMuMjY0NjMgMTcuMDg5M0MzLjM3MzY5IDE3LjIwNzcgMy41MjM0NSAxNy4yOTA5IDMuODIyOTcgMTcuNDU3M0wxMS4yMjMgMjEuNTY4NEMxMS41MDY2IDIxLjcyNiAxMS42NDg0IDIxLjgwNDcgMTEuNzk4NiAyMS44MzU2QzExLjkzMTUgMjEuODYzIDEyLjA2ODUgMjEuODYzIDEyLjIwMTUgMjEuODM1NkMxMi4zNTE2IDIxLjgwNDcgMTIuNDkzNCAyMS43MjYgMTIuNzc3IDIxLjU2ODRMMjAuMTc3IDE3LjQ1NzNDMjAuNDc2NiAxNy4yOTA5IDIwLjYyNjMgMTcuMjA3NyAyMC43MzU0IDE3LjA4OTNDMjAuODMxOCAxNi45ODQ3IDIwLjkwNDkgMTYuODYwNiAyMC45NDk1IDE2LjcyNTRDMjEgMTYuNTcyNiAyMSAxNi40MDEzIDIxIDE2LjA1ODZaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPlxuXG4gIGA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBiYXJDaGFydFNxdWFyZTAySWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTggMTVWMTdNMTIgMTFWMTdNMTYgN1YxN003LjggMjFIMTYuMkMxNy44ODAyIDIxIDE4LjcyMDIgMjEgMTkuMzYyIDIwLjY3M0MxOS45MjY1IDIwLjM4NTQgMjAuMzg1NCAxOS45MjY1IDIwLjY3MyAxOS4zNjJDMjEgMTguNzIwMiAyMSAxNy44ODAyIDIxIDE2LjJWNy44QzIxIDYuMTE5ODQgMjEgNS4yNzk3NiAyMC42NzMgNC42MzgwM0MyMC4zODU0IDQuMDczNTQgMTkuOTI2NSAzLjYxNDYgMTkuMzYyIDMuMzI2OThDMTguNzIwMiAzIDE3Ljg4MDIgMyAxNi4yIDNINy44QzYuMTE5ODQgMyA1LjI3OTc2IDMgNC42MzgwMyAzLjMyNjk4QzQuMDczNTQgMy42MTQ2IDMuNjE0NiA0LjA3MzU0IDMuMzI2OTggNC42MzgwM0MzIDUuMjc5NzYgMyA2LjExOTg0IDMgNy44VjE2LjJDMyAxNy44ODAyIDMgMTguNzIwMiAzLjMyNjk4IDE5LjM2MkMzLjYxNDYgMTkuOTI2NSA0LjA3MzU0IDIwLjM4NTQgNC42MzgwMyAyMC42NzNDNS4yNzk3NiAyMSA2LjExOTg0IDIxIDcuOCAyMVpcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuPC9zdmc+XG4gICAgYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGNvZGUwMkljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuPHBhdGggZD1cIk0xNyAxN0wyMiAxMkwxNyA3TTcgN0wyIDEyTDcgMTdNMTQgM0wxMCAyMVwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5cbmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBkYXRhSWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTIxLjIgMjJDMjEuNDggMjIgMjEuNjIgMjIgMjEuNzI3IDIxLjk0NTVDMjEuODIxMSAyMS44OTc2IDIxLjg5NzYgMjEuODIxMSAyMS45NDU1IDIxLjcyN0MyMiAyMS42MiAyMiAyMS40OCAyMiAyMS4yVjEwLjhDMjIgMTAuNTIgMjIgMTAuMzggMjEuOTQ1NSAxMC4yNzNDMjEuODk3NiAxMC4xNzg5IDIxLjgyMTEgMTAuMTAyNCAyMS43MjcgMTAuMDU0NUMyMS42MiAxMCAyMS40OCAxMCAyMS4yIDEwTDE4LjggMTBDMTguNTIgMTAgMTguMzggMTAgMTguMjczIDEwLjA1NDVDMTguMTc4OSAxMC4xMDI0IDE4LjEwMjQgMTAuMTc4OSAxOC4wNTQ1IDEwLjI3M0MxOCAxMC4zOCAxOCAxMC41MiAxOCAxMC44VjEzLjJDMTggMTMuNDggMTggMTMuNjIgMTcuOTQ1NSAxMy43MjdDMTcuODk3NiAxMy44MjExIDE3LjgyMTEgMTMuODk3NiAxNy43MjcgMTMuOTQ1NUMxNy42MiAxNCAxNy40OCAxNCAxNy4yIDE0SDE0LjhDMTQuNTIgMTQgMTQuMzggMTQgMTQuMjczIDE0LjA1NDVDMTQuMTc4OSAxNC4xMDI0IDE0LjEwMjQgMTQuMTc4OSAxNC4wNTQ1IDE0LjI3M0MxNCAxNC4zOCAxNCAxNC41MiAxNCAxNC44VjE3LjJDMTQgMTcuNDggMTQgMTcuNjIgMTMuOTQ1NSAxNy43MjdDMTMuODk3NiAxNy44MjExIDEzLjgyMTEgMTcuODk3NiAxMy43MjcgMTcuOTQ1NUMxMy42MiAxOCAxMy40OCAxOCAxMy4yIDE4SDEwLjhDMTAuNTIgMTggMTAuMzggMTggMTAuMjczIDE4LjA1NDVDMTAuMTc4OSAxOC4xMDI0IDEwLjEwMjQgMTguMTc4OSAxMC4wNTQ1IDE4LjI3M0MxMCAxOC4zOCAxMCAxOC41MiAxMCAxOC44VjIxLjJDMTAgMjEuNDggMTAgMjEuNjIgMTAuMDU0NSAyMS43MjdDMTAuMTAyNCAyMS44MjExIDEwLjE3ODkgMjEuODk3NiAxMC4yNzMgMjEuOTQ1NUMxMC4zOCAyMiAxMC41MiAyMiAxMC44IDIyTDIxLjIgMjJaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjxwYXRoIGQ9XCJNMTAgNi44QzEwIDYuNTE5OTcgMTAgNi4zNzk5NiAxMC4wNTQ1IDYuMjczQzEwLjEwMjQgNi4xNzg5MiAxMC4xNzg5IDYuMTAyNDMgMTAuMjczIDYuMDU0NUMxMC4zOCA2IDEwLjUyIDYgMTAuOCA2SDEzLjJDMTMuNDggNiAxMy42MiA2IDEzLjcyNyA2LjA1NDVDMTMuODIxMSA2LjEwMjQzIDEzLjg5NzYgNi4xNzg5MiAxMy45NDU1IDYuMjczQzE0IDYuMzc5OTYgMTQgNi41MTk5NyAxNCA2LjhWOS4yQzE0IDkuNDgwMDMgMTQgOS42MjAwNCAxMy45NDU1IDkuNzI3QzEzLjg5NzYgOS44MjEwOCAxMy44MjExIDkuODk3NTcgMTMuNzI3IDkuOTQ1NUMxMy42MiAxMCAxMy40OCAxMCAxMy4yIDEwSDEwLjhDMTAuNTIgMTAgMTAuMzggMTAgMTAuMjczIDkuOTQ1NUMxMC4xNzg5IDkuODk3NTcgMTAuMTAyNCA5LjgyMTA4IDEwLjA1NDUgOS43MjdDMTAgOS42MjAwNCAxMCA5LjQ4MDAzIDEwIDkuMlY2LjhaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjxwYXRoIGQ9XCJNMyAxMi44QzMgMTIuNTIgMyAxMi4zOCAzLjA1NDUgMTIuMjczQzMuMTAyNDMgMTIuMTc4OSAzLjE3ODkyIDEyLjEwMjQgMy4yNzMgMTIuMDU0NUMzLjM3OTk2IDEyIDMuNTE5OTcgMTIgMy44IDEySDYuMkM2LjQ4MDAzIDEyIDYuNjIwMDQgMTIgNi43MjcgMTIuMDU0NUM2LjgyMTA4IDEyLjEwMjQgNi44OTc1NyAxMi4xNzg5IDYuOTQ1NSAxMi4yNzNDNyAxMi4zOCA3IDEyLjUyIDcgMTIuOFYxNS4yQzcgMTUuNDggNyAxNS42MiA2Ljk0NTUgMTUuNzI3QzYuODk3NTcgMTUuODIxMSA2LjgyMTA4IDE1Ljg5NzYgNi43MjcgMTUuOTQ1NUM2LjYyMDA0IDE2IDYuNDgwMDMgMTYgNi4yIDE2SDMuOEMzLjUxOTk3IDE2IDMuMzc5OTYgMTYgMy4yNzMgMTUuOTQ1NUMzLjE3ODkyIDE1Ljg5NzYgMy4xMDI0MyAxNS44MjExIDMuMDU0NSAxNS43MjdDMyAxNS42MiAzIDE1LjQ4IDMgMTUuMlYxMi44WlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48cGF0aCBkPVwiTTIgMi44QzIgMi41MTk5NyAyIDIuMzc5OTYgMi4wNTQ1IDIuMjczQzIuMTAyNDMgMi4xNzg5MiAyLjE3ODkyIDIuMTAyNDMgMi4yNzMgMi4wNTQ1QzIuMzc5OTYgMiAyLjUxOTk3IDIgMi44IDJINS4yQzUuNDgwMDMgMiA1LjYyMDA0IDIgNS43MjcgMi4wNTQ1QzUuODIxMDggMi4xMDI0MyA1Ljg5NzU3IDIuMTc4OTIgNS45NDU1IDIuMjczQzYgMi4zNzk5NiA2IDIuNTE5OTcgNiAyLjhWNS4yQzYgNS40ODAwMyA2IDUuNjIwMDQgNS45NDU1IDUuNzI3QzUuODk3NTcgNS44MjEwOCA1LjgyMTA4IDUuODk3NTcgNS43MjcgNS45NDU1QzUuNjIwMDQgNiA1LjQ4MDAzIDYgNS4yIDZIMi44QzIuNTE5OTcgNiAyLjM3OTk2IDYgMi4yNzMgNS45NDU1QzIuMTc4OTIgNS44OTc1NyAyLjEwMjQzIDUuODIxMDggMi4wNTQ1IDUuNzI3QzIgNS42MjAwNCAyIDUuNDgwMDMgMiA1LjJWMi44WlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY2hlY2tDaXJjbGVJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIkezE1fVwiIGhlaWdodD1cIiR7MTV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuPHBhdGggZD1cIk03LjUgMTJMMTAuNSAxNUwxNi41IDlNMjIgMTJDMjIgMTcuNTIyOCAxNy41MjI4IDIyIDEyIDIyQzYuNDc3MTUgMjIgMiAxNy41MjI4IDIgMTJDMiA2LjQ3NzE1IDYuNDc3MTUgMiAxMiAyQzE3LjUyMjggMiAyMiA2LjQ3NzE1IDIyIDEyWlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5cbmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiB0dWlzdEljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuPHBhdGggZD1cIk0yMSAxNlY3LjJDMjEgNi4wNzk5IDIxIDUuNTE5ODQgMjAuNzgyIDUuMDkyMDJDMjAuNTkwMyA0LjcxNTY5IDIwLjI4NDMgNC40MDk3MyAxOS45MDggNC4yMTc5OUMxOS40ODAyIDQgMTguOTIwMSA0IDE3LjggNEg2LjJDNS4wNzk4OSA0IDQuNTE5ODQgNCA0LjA5MjAyIDQuMjE3OTlDMy43MTU2OSA0LjQwOTczIDMuNDA5NzMgNC43MTU2OSAzLjIxNzk5IDUuMDkyMDJDMyA1LjUxOTg0IDMgNi4wNzk5IDMgNy4yVjE2TTQuNjY2NjcgMjBIMTkuMzMzM0MxOS45NTMzIDIwIDIwLjI2MzMgMjAgMjAuNTE3NiAxOS45MzE5QzIxLjIwNzggMTkuNzQ2OSAyMS43NDY5IDE5LjIwNzggMjEuOTMxOSAxOC41MTc2QzIyIDE4LjI2MzMgMjIgMTcuOTUzMyAyMiAxNy4zMzMzQzIyIDE3LjAyMzMgMjIgMTYuODY4MyAyMS45NjU5IDE2Ljc0MTJDMjEuODczNSAxNi4zOTYxIDIxLjYwMzkgMTYuMTI2NSAyMS4yNTg4IDE2LjAzNDFDMjEuMTMxNyAxNiAyMC45NzY3IDE2IDIwLjY2NjcgMTZIMy4zMzMzM0MzLjAyMzM0IDE2IDIuODY4MzUgMTYgMi43NDExOCAxNi4wMzQxQzIuMzk2MDkgMTYuMTI2NSAyLjEyNjU0IDE2LjM5NjEgMi4wMzQwNyAxNi43NDEyQzIgMTYuODY4MyAyIDE3LjAyMzMgMiAxNy4zMzMzQzIgMTcuOTUzMyAyIDE4LjI2MzMgMi4wNjgxNSAxOC41MTc2QzIuMjUzMDggMTkuMjA3OCAyLjc5MjE4IDE5Ljc0NjkgMy40ODIzNiAxOS45MzE5QzMuNzM2NjkgMjAgNC4wNDY2OSAyMCA0LjY2NjY3IDIwWlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY2xvdWRCbGFuazAySWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTkuNSAxOUM1LjM1Nzg2IDE5IDIgMTUuNjQyMSAyIDExLjVDMiA3LjM1Nzg2IDUuMzU3ODYgNCA5LjUgNEMxMi4zODI3IDQgMTQuODg1NSA1LjYyNjM0IDE2LjE0MSA4LjAxMTUzQzE2LjI1OTcgOC4wMDM4OCAxNi4zNzk0IDggMTYuNSA4QzE5LjUzNzYgOCAyMiAxMC40NjI0IDIyIDEzLjVDMjIgMTYuNTM3NiAxOS41Mzc2IDE5IDE2LjUgMTlDMTMuOTQ4NSAxOSAxMi4xMjI0IDE5IDkuNSAxOVpcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuPC9zdmc+XG5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gc2VydmVyMDRJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNMjIgMTAuNUwyMS41MjU2IDYuNzA0NjNDMjEuMzM5NSA1LjIxNjAyIDIxLjI0NjUgNC40NzE2OSAyMC44OTYxIDMuOTEwOEMyMC41ODc1IDMuNDE2NjIgMjAuMTQxNiAzLjAyMzAxIDE5LjYxMyAyLjc3ODA0QzE5LjAxMyAyLjUgMTguMjYyOSAyLjUgMTYuNzYyNiAyLjVINy4yMzczNUM1LjczNzE0IDIuNSA0Ljk4NzA0IDIuNSA0LjM4NzAyIDIuNzc4MDRDMy44NTgzOCAzLjAyMzAxIDMuNDEyNSAzLjQxNjYyIDMuMTAzODYgMy45MTA4QzIuNzUzNTQgNC40NzE2OSAyLjY2MDUgNS4yMTYwMSAyLjQ3NDQyIDYuNzA0NjNMMiAxMC41TTUuNSAxNC41SDE4LjVNNS41IDE0LjVDMy41NjcgMTQuNSAyIDEyLjkzMyAyIDExQzIgOS4wNjcgMy41NjcgNy41IDUuNSA3LjVIMTguNUMyMC40MzMgNy41IDIyIDkuMDY3IDIyIDExQzIyIDEyLjkzMyAyMC40MzMgMTQuNSAxOC41IDE0LjVNNS41IDE0LjVDMy41NjcgMTQuNSAyIDE2LjA2NyAyIDE4QzIgMTkuOTMzIDMuNTY3IDIxLjUgNS41IDIxLjVIMTguNUMyMC40MzMgMjEuNSAyMiAxOS45MzMgMjIgMThDMjIgMTYuMDY3IDIwLjQzMyAxNC41IDE4LjUgMTQuNU02IDExSDYuMDFNNiAxOEg2LjAxTTEyIDExSDE4TTEyIDE4SDE4XCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIG1pY3Jvc2NvcGVJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNMyAyMkgxMk0xMSA2LjI1MjA0QzExLjYzOTIgNi4wODc1MSAxMi4zMDk0IDYgMTMgNkMxNy40MTgzIDYgMjEgOS41ODE3MiAyMSAxNEMyMSAxNy4zNTc0IDE4LjkzMTggMjAuMjMxNyAxNiAyMS40MTg1TTUuNSAxM0g5LjVDOS45NjQ2NiAxMyAxMC4xOTcgMTMgMTAuMzkwMiAxMy4wMzg0QzExLjE4MzYgMTMuMTk2MiAxMS44MDM4IDEzLjgxNjQgMTEuOTYxNiAxNC42MDk4QzEyIDE0LjgwMyAxMiAxNS4wMzUzIDEyIDE1LjVDMTIgMTUuOTY0NyAxMiAxNi4xOTcgMTEuOTYxNiAxNi4zOTAyQzExLjgwMzggMTcuMTgzNiAxMS4xODM2IDE3LjgwMzggMTAuMzkwMiAxNy45NjE2QzEwLjE5NyAxOCA5Ljk2NDY2IDE4IDkuNSAxOEg1LjVDNS4wMzUzNCAxOCA0LjgwMzAyIDE4IDQuNjA5ODIgMTcuOTYxNkMzLjgxNjQ0IDE3LjgwMzggMy4xOTYyNCAxNy4xODM2IDMuMDM4NDMgMTYuMzkwMkMzIDE2LjE5NyAzIDE1Ljk2NDcgMyAxNS41QzMgMTUuMDM1MyAzIDE0LjgwMyAzLjAzODQzIDE0LjYwOThDMy4xOTYyNCAxMy44MTY0IDMuODE2NDQgMTMuMTk2MiA0LjYwOTgyIDEzLjAzODRDNC44MDMwMiAxMyA1LjAzNTM0IDEzIDUuNSAxM1pNNCA1LjVWMTNIMTFWNS41QzExIDMuNTY3IDkuNDMzIDIgNy41IDJDNS41NjcgMiA0IDMuNTY3IDQgNS41WlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5cbmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBidWlsZGluZzA3SWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG4gIDxwYXRoIGQ9XCJNNy41IDExSDQuNkM0LjAzOTk1IDExIDMuNzU5OTIgMTEgMy41NDYwMSAxMS4xMDlDMy4zNTc4NSAxMS4yMDQ5IDMuMjA0ODcgMTEuMzU3OCAzLjEwODk5IDExLjU0NkMzIDExLjc1OTkgMyAxMi4wMzk5IDMgMTIuNlYyMU0xNi41IDExSDE5LjRDMTkuOTYwMSAxMSAyMC4yNDAxIDExIDIwLjQ1NCAxMS4xMDlDMjAuNjQyMiAxMS4yMDQ5IDIwLjc5NTEgMTEuMzU3OCAyMC44OTEgMTEuNTQ2QzIxIDExLjc1OTkgMjEgMTIuMDM5OSAyMSAxMi42VjIxTTE2LjUgMjFWNi4yQzE2LjUgNS4wNzk5IDE2LjUgNC41MTk4NCAxNi4yODIgNC4wOTIwMkMxNi4wOTAzIDMuNzE1NjkgMTUuNzg0MyAzLjQwOTczIDE1LjQwOCAzLjIxNzk5QzE0Ljk4MDIgMyAxNC40MjAxIDMgMTMuMyAzSDEwLjdDOS41Nzk4OSAzIDkuMDE5ODQgMyA4LjU5MjAyIDMuMjE3OTlDOC4yMTU2OSAzLjQwOTczIDcuOTA5NzMgMy43MTU2OSA3LjcxNzk5IDQuMDkyMDJDNy41IDQuNTE5ODQgNy41IDUuMDc5OSA3LjUgNi4yVjIxTTIyIDIxSDJNMTEgN0gxM00xMSAxMUgxM00xMSAxNUgxM1wiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG4gIDwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGJvb2tPcGVuMDFJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbiAgPHBhdGggZD1cIk0xMiAyMUwxMS44OTk5IDIwLjg0OTlDMTEuMjA1MyAxOS44MDggMTAuODU4IDE5LjI4NyAxMC4zOTkxIDE4LjkwOThDOS45OTI4NiAxOC41NzU5IDkuNTI0NzYgMTguMzI1NCA5LjAyMTYxIDE4LjE3MjZDOC40NTMyNSAxOCA3LjgyNzExIDE4IDYuNTc0ODIgMThINS4yQzQuMDc5ODkgMTggMy41MTk4NCAxOCAzLjA5MjAyIDE3Ljc4MkMyLjcxNTY5IDE3LjU5MDMgMi40MDk3MyAxNy4yODQzIDIuMjE3OTkgMTYuOTA4QzIgMTYuNDgwMiAyIDE1LjkyMDEgMiAxNC44VjYuMkMyIDUuMDc5ODkgMiA0LjUxOTg0IDIuMjE3OTkgNC4wOTIwMkMyLjQwOTczIDMuNzE1NjkgMi43MTU2OSAzLjQwOTczIDMuMDkyMDIgMy4yMTc5OUMzLjUxOTg0IDMgNC4wNzk4OSAzIDUuMiAzSDUuNkM3Ljg0MDIxIDMgOC45NjAzMSAzIDkuODE1OTYgMy40MzU5N0MxMC41Njg2IDMuODE5NDcgMTEuMTgwNSA0LjQzMTM5IDExLjU2NCA1LjE4NDA0QzEyIDYuMDM5NjggMTIgNy4xNTk3OSAxMiA5LjRNMTIgMjFWOS40TTEyIDIxTDEyLjEwMDEgMjAuODQ5OUMxMi43OTQ3IDE5LjgwOCAxMy4xNDIgMTkuMjg3IDEzLjYwMDkgMTguOTA5OEMxNC4wMDcxIDE4LjU3NTkgMTQuNDc1MiAxOC4zMjU0IDE0Ljk3ODQgMTguMTcyNkMxNS41NDY3IDE4IDE2LjE3MjkgMTggMTcuNDI1MiAxOEgxOC44QzE5LjkyMDEgMTggMjAuNDgwMiAxOCAyMC45MDggMTcuNzgyQzIxLjI4NDMgMTcuNTkwMyAyMS41OTAzIDE3LjI4NDMgMjEuNzgyIDE2LjkwOEMyMiAxNi40ODAyIDIyIDE1LjkyMDEgMjIgMTQuOFY2LjJDMjIgNS4wNzk4OSAyMiA0LjUxOTg0IDIxLjc4MiA0LjA5MjAyQzIxLjU5MDMgMy43MTU2OSAyMS4yODQzIDMuNDA5NzMgMjAuOTA4IDMuMjE3OTlDMjAuNDgwMiAzIDE5LjkyMDEgMyAxOC44IDNIMTguNEMxNi4xNTk4IDMgMTUuMDM5NyAzIDE0LjE4NCAzLjQzNTk3QzEzLjQzMTQgMy44MTk0NyAxMi44MTk1IDQuNDMxMzkgMTIuNDM2IDUuMTg0MDRDMTIgNi4wMzk2OCAxMiA3LjE1OTc5IDEyIDkuNFwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG4gIDwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGNvZGVCcm93c2VySWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG4gIDxwYXRoIGQ9XCJNMjIgOUgyTTE0IDE3LjVMMTYuNSAxNUwxNCAxMi41TTEwIDEyLjVMNy41IDE1TDEwIDE3LjVNMiA3LjhMMiAxNi4yQzIgMTcuODgwMiAyIDE4LjcyMDIgMi4zMjY5OCAxOS4zNjJDMi42MTQ2IDE5LjkyNjUgMy4wNzM1NCAyMC4zODU0IDMuNjM4MDMgMjAuNjczQzQuMjc5NzYgMjEgNS4xMTk4NCAyMSA2LjggMjFIMTcuMkMxOC44ODAyIDIxIDE5LjcyMDIgMjEgMjAuMzYyIDIwLjY3M0MyMC45MjY1IDIwLjM4NTQgMjEuMzg1NCAxOS45MjY1IDIxLjY3MyAxOS4zNjJDMjIgMTguNzIwMiAyMiAxNy44ODAyIDIyIDE2LjJWNy44QzIyIDYuMTE5ODQgMjIgNS4yNzk3NyAyMS42NzMgNC42MzgwM0MyMS4zODU0IDQuMDczNTQgMjAuOTI2NSAzLjYxNDYgMjAuMzYyIDMuMzI2OThDMTkuNzIwMiAzIDE4Ljg4MDIgMyAxNy4yIDNMNi44IDNDNS4xMTk4NCAzIDQuMjc5NzYgMyAzLjYzODAzIDMuMzI2OThDMy4wNzM1NCAzLjYxNDYgMi42MTQ2IDQuMDczNTQgMi4zMjY5OCA0LjYzODAzQzIgNS4yNzk3NiAyIDYuMTE5ODQgMiA3LjhaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbiAgPC9zdmc+XG5gO1xufVxuIiwgImNvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2RhdGFcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZmlsZW5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvZGF0YS9leGFtcGxlcy5qc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9pbXBvcnRfbWV0YV91cmwgPSBcImZpbGU6Ly8vVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2RhdGEvZXhhbXBsZXMuanNcIjtpbXBvcnQgKiBhcyBwYXRoIGZyb20gXCJub2RlOnBhdGhcIjtcbmltcG9ydCBmZyBmcm9tIFwiZmFzdC1nbG9iXCI7XG5pbXBvcnQgZnMgZnJvbSBcIm5vZGU6ZnNcIjtcblxuY29uc3QgZ2xvYiA9IHBhdGguam9pbihpbXBvcnQubWV0YS5kaXJuYW1lLCBcIi4uLy4uLy4uL2ZpeHR1cmVzLyovUkVBRE1FLm1kXCIpO1xuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gbG9hZERhdGEoZmlsZXMpIHtcbiAgaWYgKCFmaWxlcykge1xuICAgIGZpbGVzID0gZmdcbiAgICAgIC5zeW5jKGdsb2IsIHtcbiAgICAgICAgYWJzb2x1dGU6IHRydWUsXG4gICAgICB9KVxuICAgICAgLnNvcnQoKTtcbiAgfVxuICByZXR1cm4gZmlsZXMubWFwKChmaWxlKSA9PiB7XG4gICAgY29uc3QgY29udGVudCA9IGZzLnJlYWRGaWxlU3luYyhmaWxlLCBcInV0Zi04XCIpO1xuICAgIGNvbnN0IHRpdGxlUmVnZXggPSAvXiNcXHMqKC4rKS9tO1xuICAgIGNvbnN0IHRpdGxlTWF0Y2ggPSBjb250ZW50Lm1hdGNoKHRpdGxlUmVnZXgpO1xuICAgIHJldHVybiB7XG4gICAgICB0aXRsZTogdGl0bGVNYXRjaFsxXSxcbiAgICAgIG5hbWU6IHBhdGguYmFzZW5hbWUocGF0aC5kaXJuYW1lKGZpbGUpKS50b0xvd2VyQ2FzZSgpLFxuICAgICAgY29udGVudDogY29udGVudCxcbiAgICAgIHVybDogYGh0dHBzOi8vZ2l0aHViLmNvbS90dWlzdC90dWlzdC90cmVlL21haW4vZml4dHVyZXMvJHtwYXRoLmJhc2VuYW1lKFxuICAgICAgICBwYXRoLmRpcm5hbWUoZmlsZSksXG4gICAgICApfWAsXG4gICAgfTtcbiAgfSk7XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiBwYXRocygpIHtcbiAgcmV0dXJuIChhd2FpdCBsb2FkRGF0YSgpKS5tYXAoKGl0ZW0pID0+IHtcbiAgICByZXR1cm4ge1xuICAgICAgcGFyYW1zOiB7XG4gICAgICAgIGV4YW1wbGU6IGl0ZW0ubmFtZSxcbiAgICAgICAgdGl0bGU6IGl0ZW0udGl0bGUsXG4gICAgICAgIGRlc2NyaXB0aW9uOiBpdGVtLmRlc2NyaXB0aW9uLFxuICAgICAgICB1cmw6IGl0ZW0udXJsLFxuICAgICAgfSxcbiAgICAgIGNvbnRlbnQ6IGl0ZW0uY29udGVudCxcbiAgICB9O1xuICB9KTtcbn1cbiIsICJjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9kYXRhXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ZpbGVuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2RhdGEvcHJvamVjdC1kZXNjcmlwdGlvbi5qc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9pbXBvcnRfbWV0YV91cmwgPSBcImZpbGU6Ly8vVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2RhdGEvcHJvamVjdC1kZXNjcmlwdGlvbi5qc1wiO2ltcG9ydCAqIGFzIHBhdGggZnJvbSBcIm5vZGU6cGF0aFwiO1xuaW1wb3J0IGZnIGZyb20gXCJmYXN0LWdsb2JcIjtcbmltcG9ydCBmcyBmcm9tIFwibm9kZTpmc1wiO1xuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gcGF0aHMobG9jYWxlKSB7XG4gIHJldHVybiAoYXdhaXQgbG9hZERhdGEoKSkubWFwKChpdGVtKSA9PiB7XG4gICAgcmV0dXJuIHtcbiAgICAgIHBhcmFtczoge1xuICAgICAgICB0eXBlOiBpdGVtLm5hbWUsXG4gICAgICAgIHRpdGxlOiBpdGVtLnRpdGxlLFxuICAgICAgICBkZXNjcmlwdGlvbjogaXRlbS5kZXNjcmlwdGlvbixcbiAgICAgICAgaWRlbnRpZmllcjogaXRlbS5pZGVudGlmaWVyLFxuICAgICAgfSxcbiAgICAgIGNvbnRlbnQ6IGl0ZW0uY29udGVudCxcbiAgICB9O1xuICB9KTtcbn1cblxuZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIGxvYWREYXRhKGxvY2FsZSkge1xuICBjb25zdCBnZW5lcmF0ZWREaXJlY3RvcnkgPSBwYXRoLmpvaW4oXG4gICAgaW1wb3J0Lm1ldGEuZGlybmFtZSxcbiAgICBcIi4uLy4uL2RvY3MvZ2VuZXJhdGVkL21hbmlmZXN0XCIsXG4gICk7XG4gIGNvbnN0IGZpbGVzID0gZmdcbiAgICAuc3luYyhcIioqLyoubWRcIiwge1xuICAgICAgY3dkOiBnZW5lcmF0ZWREaXJlY3RvcnksXG4gICAgICBhYnNvbHV0ZTogdHJ1ZSxcbiAgICAgIGlnbm9yZTogW1wiKiovUkVBRE1FLm1kXCJdLFxuICAgIH0pXG4gICAgLnNvcnQoKTtcbiAgcmV0dXJuIGZpbGVzLm1hcCgoZmlsZSkgPT4ge1xuICAgIGNvbnN0IGNhdGVnb3J5ID0gcGF0aC5iYXNlbmFtZShwYXRoLmRpcm5hbWUoZmlsZSkpO1xuICAgIGNvbnN0IGZpbGVOYW1lID0gcGF0aC5iYXNlbmFtZShmaWxlKS5yZXBsYWNlKFwiLm1kXCIsIFwiXCIpO1xuICAgIHJldHVybiB7XG4gICAgICBjYXRlZ29yeTogY2F0ZWdvcnksXG4gICAgICB0aXRsZTogZmlsZU5hbWUsXG4gICAgICBuYW1lOiBmaWxlTmFtZS50b0xvd2VyQ2FzZSgpLFxuICAgICAgaWRlbnRpZmllcjogY2F0ZWdvcnkgKyBcIi9cIiArIGZpbGVOYW1lLnRvTG93ZXJDYXNlKCksXG4gICAgICBkZXNjcmlwdGlvbjogXCJcIixcbiAgICAgIGNvbnRlbnQ6IGZzLnJlYWRGaWxlU3luYyhmaWxlLCBcInV0Zi04XCIpLFxuICAgIH07XG4gIH0pO1xufVxuIiwgImNvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ZpbGVuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2JhcnMubWpzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ltcG9ydF9tZXRhX3VybCA9IFwiZmlsZTovLy9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvYmFycy5tanNcIjtpbXBvcnQgeyBjb21pbmdTb29uQmFkZ2UsIHhjb2RlUHJvakNvbXBhdGlibGVCYWRnZSB9IGZyb20gXCIuL2JhZGdlcy5tanNcIjtcbmltcG9ydCB7XG4gIGN1YmVPdXRsaW5lSWNvbixcbiAgY3ViZTAySWNvbixcbiAgY3ViZTAxSWNvbixcbiAgdHVpc3RJY29uLFxuICBidWlsZGluZzA3SWNvbixcbiAgc2VydmVyMDRJY29uLFxuICBib29rT3BlbjAxSWNvbixcbiAgY29kZUJyb3dzZXJJY29uLFxufSBmcm9tIFwiLi9pY29ucy5tanNcIjtcbmltcG9ydCB7IGxvYWREYXRhIGFzIGxvYWRFeGFtcGxlc0RhdGEgfSBmcm9tIFwiLi9kYXRhL2V4YW1wbGVzXCI7XG5pbXBvcnQgeyBsb2FkRGF0YSBhcyBsb2FkUHJvamVjdERlc2NyaXB0aW9uRGF0YSB9IGZyb20gXCIuL2RhdGEvcHJvamVjdC1kZXNjcmlwdGlvblwiO1xuaW1wb3J0IHsgbG9jYWxpemVkU3RyaW5nIH0gZnJvbSBcIi4vaTE4bi5tanNcIjtcblxuYXN5bmMgZnVuY3Rpb24gcHJvamVjdERlc2NyaXB0aW9uU2lkZWJhcihsb2NhbGUpIHtcbiAgY29uc3QgcHJvamVjdERlc2NyaXB0aW9uVHlwZXNEYXRhID0gYXdhaXQgbG9hZFByb2plY3REZXNjcmlwdGlvbkRhdGEoKTtcbiAgY29uc3QgcHJvamVjdERlc2NyaXB0aW9uU2lkZWJhciA9IHtcbiAgICB0ZXh0OiBcIlByb2plY3QgRGVzY3JpcHRpb25cIixcbiAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgaXRlbXM6IFtdLFxuICB9O1xuICBmdW5jdGlvbiBjYXBpdGFsaXplKHRleHQpIHtcbiAgICByZXR1cm4gdGV4dC5jaGFyQXQoMCkudG9VcHBlckNhc2UoKSArIHRleHQuc2xpY2UoMSkudG9Mb3dlckNhc2UoKTtcbiAgfVxuICBbXCJzdHJ1Y3RzXCIsIFwiZW51bXNcIiwgXCJleHRlbnNpb25zXCIsIFwidHlwZWFsaWFzZXNcIl0uZm9yRWFjaCgoY2F0ZWdvcnkpID0+IHtcbiAgICBpZiAoXG4gICAgICBwcm9qZWN0RGVzY3JpcHRpb25UeXBlc0RhdGEuZmluZCgoaXRlbSkgPT4gaXRlbS5jYXRlZ29yeSA9PT0gY2F0ZWdvcnkpXG4gICAgKSB7XG4gICAgICBwcm9qZWN0RGVzY3JpcHRpb25TaWRlYmFyLml0ZW1zLnB1c2goe1xuICAgICAgICB0ZXh0OiBjYXBpdGFsaXplKGNhdGVnb3J5KSxcbiAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICBpdGVtczogcHJvamVjdERlc2NyaXB0aW9uVHlwZXNEYXRhXG4gICAgICAgICAgLmZpbHRlcigoaXRlbSkgPT4gaXRlbS5jYXRlZ29yeSA9PT0gY2F0ZWdvcnkpXG4gICAgICAgICAgLm1hcCgoaXRlbSkgPT4gKHtcbiAgICAgICAgICAgIHRleHQ6IGl0ZW0udGl0bGUsXG4gICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9yZWZlcmVuY2VzL3Byb2plY3QtZGVzY3JpcHRpb24vJHtpdGVtLmlkZW50aWZpZXJ9YCxcbiAgICAgICAgICB9KSksXG4gICAgICB9KTtcbiAgICB9XG4gIH0pO1xuICByZXR1cm4gcHJvamVjdERlc2NyaXB0aW9uU2lkZWJhcjtcbn1cblxuZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIHJlZmVyZW5jZXNTaWRlYmFyKGxvY2FsZSkge1xuICByZXR1cm4gW1xuICAgIHtcbiAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhsb2NhbGUsIFwic2lkZWJhcnMucmVmZXJlbmNlcy50ZXh0XCIpLFxuICAgICAgaXRlbXM6IFtcbiAgICAgICAgYXdhaXQgcHJvamVjdERlc2NyaXB0aW9uU2lkZWJhcihsb2NhbGUpLFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5yZWZlcmVuY2VzLml0ZW1zLmV4YW1wbGVzLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGNvbGxhcHNlZDogdHJ1ZSxcbiAgICAgICAgICBpdGVtczogKGF3YWl0IGxvYWRFeGFtcGxlc0RhdGEoKSkubWFwKChpdGVtKSA9PiB7XG4gICAgICAgICAgICByZXR1cm4ge1xuICAgICAgICAgICAgICB0ZXh0OiBpdGVtLnRpdGxlLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9yZWZlcmVuY2VzL2V4YW1wbGVzLyR7aXRlbS5uYW1lfWAsXG4gICAgICAgICAgICB9O1xuICAgICAgICAgIH0pLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5yZWZlcmVuY2VzLml0ZW1zLm1pZ3JhdGlvbnMudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5yZWZlcmVuY2VzLml0ZW1zLm1pZ3JhdGlvbnMuaXRlbXMuZnJvbS12My10by12NC50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L3JlZmVyZW5jZXMvbWlncmF0aW9ucy9mcm9tLXYzLXRvLXY0YCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgXSxcbiAgICAgICAgfSxcbiAgICAgIF0sXG4gICAgfSxcbiAgXTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIG5hdkJhcihsb2NhbGUpIHtcbiAgcmV0dXJuIFtcbiAgICB7XG4gICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj4ke2xvY2FsaXplZFN0cmluZyhcbiAgICAgICAgbG9jYWxlLFxuICAgICAgICBcIm5hdmJhci5ndWlkZXMudGV4dFwiLFxuICAgICAgKX0gJHtib29rT3BlbjAxSWNvbigpfTwvc3Bhbj5gLFxuICAgICAgbGluazogYC8ke2xvY2FsZX0vYCxcbiAgICB9LFxuICAgIHtcbiAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7bG9jYWxpemVkU3RyaW5nKFxuICAgICAgICBsb2NhbGUsXG4gICAgICAgIFwibmF2YmFyLmNsaS50ZXh0XCIsXG4gICAgICApfSAke2NvZGVCcm93c2VySWNvbigpfTwvc3Bhbj5gLFxuICAgICAgbGluazogYC8ke2xvY2FsZX0vY2xpL2F1dGhgLFxuICAgIH0sXG4gICAge1xuICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+JHtsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgIGxvY2FsZSxcbiAgICAgICAgXCJuYXZiYXIuc2VydmVyLnRleHRcIixcbiAgICAgICl9ICR7c2VydmVyMDRJY29uKCl9PC9zcGFuPmAsXG4gICAgICBsaW5rOiBgLyR7bG9jYWxlfS9zZXJ2ZXIvaW50cm9kdWN0aW9uL3doeS1hLXNlcnZlcmAsXG4gICAgfSxcbiAgICB7XG4gICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcobG9jYWxlLCBcIm5hdmJhci5yZXNvdXJjZXMudGV4dFwiKSxcbiAgICAgIGl0ZW1zOiBbXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcIm5hdmJhci5yZXNvdXJjZXMuaXRlbXMucmVmZXJlbmNlcy50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9yZWZlcmVuY2VzL3Byb2plY3QtZGVzY3JpcHRpb24vc3RydWN0cy9wcm9qZWN0YCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwibmF2YmFyLnJlc291cmNlcy5pdGVtcy5jb250cmlidXRvcnMudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vY29udHJpYnV0b3JzL2dldC1zdGFydGVkYCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwibmF2YmFyLnJlc291cmNlcy5pdGVtcy5jaGFuZ2Vsb2cudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogXCJodHRwczovL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvcmVsZWFzZXNcIixcbiAgICAgICAgfSxcbiAgICAgIF0sXG4gICAgfSxcbiAgXTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGNvbnRyaWJ1dG9yc1NpZGViYXIobG9jYWxlKSB7XG4gIHJldHVybiBbXG4gICAge1xuICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKGxvY2FsZSwgXCJzaWRlYmFycy5jb250cmlidXRvcnMudGV4dFwiKSxcbiAgICAgIGl0ZW1zOiBbXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmNvbnRyaWJ1dG9ycy5pdGVtcy5nZXQtc3RhcnRlZC50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jb250cmlidXRvcnMvZ2V0LXN0YXJ0ZWRgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5jb250cmlidXRvcnMuaXRlbXMuaXNzdWUtcmVwb3J0aW5nLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2NvbnRyaWJ1dG9ycy9pc3N1ZS1yZXBvcnRpbmdgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5jb250cmlidXRvcnMuaXRlbXMuY29kZS1yZXZpZXdzLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2NvbnRyaWJ1dG9ycy9jb2RlLXJldmlld3NgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5jb250cmlidXRvcnMuaXRlbXMucHJpbmNpcGxlcy50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jb250cmlidXRvcnMvcHJpbmNpcGxlc2AsXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmNvbnRyaWJ1dG9ycy5pdGVtcy50cmFuc2xhdGUudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vY29udHJpYnV0b3JzL3RyYW5zbGF0ZWAsXG4gICAgICAgIH0sXG4gICAgICBdLFxuICAgIH0sXG4gIF07XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBzZXJ2ZXJTaWRlYmFyKGxvY2FsZSkge1xuICByZXR1cm4gW1xuICAgIHtcbiAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7bG9jYWxpemVkU3RyaW5nKFxuICAgICAgICBsb2NhbGUsXG4gICAgICAgIFwic2lkZWJhcnMuc2VydmVyLml0ZW1zLmludHJvZHVjdGlvbi50ZXh0XCIsXG4gICAgICApfSAke3NlcnZlcjA0SWNvbigpfTwvc3Bhbj5gLFxuICAgICAgaXRlbXM6IFtcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuc2VydmVyLml0ZW1zLmludHJvZHVjdGlvbi5pdGVtcy53aHktc2VydmVyLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L3NlcnZlci9pbnRyb2R1Y3Rpb24vd2h5LWEtc2VydmVyYCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuc2VydmVyLml0ZW1zLmludHJvZHVjdGlvbi5pdGVtcy5hY2NvdW50cy1hbmQtcHJvamVjdHMudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vc2VydmVyL2ludHJvZHVjdGlvbi9hY2NvdW50cy1hbmQtcHJvamVjdHNgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMuaW50cm9kdWN0aW9uLml0ZW1zLmF1dGhlbnRpY2F0aW9uLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L3NlcnZlci9pbnRyb2R1Y3Rpb24vYXV0aGVudGljYXRpb25gLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMuaW50cm9kdWN0aW9uLml0ZW1zLmludGVncmF0aW9ucy50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9zZXJ2ZXIvaW50cm9kdWN0aW9uL2ludGVncmF0aW9uc2AsXG4gICAgICAgIH0sXG4gICAgICBdLFxuICAgIH0sXG4gICAge1xuICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+JHtsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgIGxvY2FsZSxcbiAgICAgICAgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMub24tcHJlbWlzZS50ZXh0XCIsXG4gICAgICApfSAke2J1aWxkaW5nMDdJY29uKCl9PC9zcGFuPmAsXG4gICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICBpdGVtczogW1xuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMub24tcHJlbWlzZS5pdGVtcy5pbnN0YWxsLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L3NlcnZlci9vbi1wcmVtaXNlL2luc3RhbGxgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMub24tcHJlbWlzZS5pdGVtcy5tZXRyaWNzLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L3NlcnZlci9vbi1wcmVtaXNlL21ldHJpY3NgLFxuICAgICAgICB9LFxuICAgICAgXSxcbiAgICB9LFxuICAgIHtcbiAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgbG9jYWxlLFxuICAgICAgICBcInNpZGViYXJzLnNlcnZlci5pdGVtcy5hcGktZG9jdW1lbnRhdGlvbi50ZXh0XCIsXG4gICAgICApLFxuICAgICAgbGluazogXCJodHRwczovL3R1aXN0LmRldi9hcGkvZG9jc1wiLFxuICAgIH0sXG4gICAge1xuICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKGxvY2FsZSwgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMuc3RhdHVzLnRleHRcIiksXG4gICAgICBsaW5rOiBcImh0dHBzOi8vc3RhdHVzLnR1aXN0LmlvXCIsXG4gICAgfSxcbiAgICB7XG4gICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgIGxvY2FsZSxcbiAgICAgICAgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMubWV0cmljcy1kYXNoYm9hcmQudGV4dFwiLFxuICAgICAgKSxcbiAgICAgIGxpbms6IFwiaHR0cHM6Ly90dWlzdC5ncmFmYW5hLm5ldC9wdWJsaWMtZGFzaGJvYXJkcy8xZjg1ZjFjMzg5NWU0OGZlYmQwMmNjNzM1MGFkZTJkOVwiLFxuICAgIH0sXG4gIF07XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBndWlkZXNTaWRlYmFyKGxvY2FsZSkge1xuICByZXR1cm4gW1xuICAgIHtcbiAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7bG9jYWxpemVkU3RyaW5nKFxuICAgICAgICBsb2NhbGUsXG4gICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLnF1aWNrLXN0YXJ0LnRleHRcIixcbiAgICAgICl9ICR7dHVpc3RJY29uKCl9PC9zcGFuPmAsXG4gICAgICBpdGVtczogW1xuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMucXVpY2stc3RhcnQuaXRlbXMuaW5zdGFsbC10dWlzdC50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvcXVpY2stc3RhcnQvaW5zdGFsbC10dWlzdGAsXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5xdWljay1zdGFydC5pdGVtcy5jcmVhdGUtYS1wcm9qZWN0LnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9xdWljay1zdGFydC9jcmVhdGUtYS1wcm9qZWN0YCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLnF1aWNrLXN0YXJ0Lml0ZW1zLmFkZC1kZXBlbmRlbmNpZXMudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3F1aWNrLXN0YXJ0L2FkZC1kZXBlbmRlbmNpZXNgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMucXVpY2stc3RhcnQuaXRlbXMuZ2F0aGVyLWluc2lnaHRzLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9xdWljay1zdGFydC9nYXRoZXItaW5zaWdodHNgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMucXVpY2stc3RhcnQuaXRlbXMub3B0aW1pemUtd29ya2Zsb3dzLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9xdWljay1zdGFydC9vcHRpbWl6ZS13b3JrZmxvd3NgLFxuICAgICAgICB9LFxuICAgICAgXSxcbiAgICB9LFxuICAgIHtcbiAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7bG9jYWxpemVkU3RyaW5nKFxuICAgICAgICBsb2NhbGUsXG4gICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLnN0YXJ0LnRleHRcIixcbiAgICAgICl9ICR7Y3ViZU91dGxpbmVJY29uKCl9PC9zcGFuPmAsXG4gICAgICBpdGVtczogW1xuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuc3RhcnQuaXRlbXMubmV3LXByb2plY3QudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3N0YXJ0L25ldy1wcm9qZWN0YCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLnN0YXJ0Lml0ZW1zLnN3aWZ0LXBhY2thZ2UudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3N0YXJ0L3N3aWZ0LXBhY2thZ2VgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuc3RhcnQuaXRlbXMubWlncmF0ZS50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICAgICAgaXRlbXM6IFtcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5zdGFydC5pdGVtcy5taWdyYXRlLml0ZW1zLnhjb2RlLXByb2plY3QudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvc3RhcnQvbWlncmF0ZS94Y29kZS1wcm9qZWN0YCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuc3RhcnQuaXRlbXMubWlncmF0ZS5pdGVtcy5zd2lmdC1wYWNrYWdlLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3N0YXJ0L21pZ3JhdGUvc3dpZnQtcGFja2FnZWAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLnN0YXJ0Lml0ZW1zLm1pZ3JhdGUuaXRlbXMueGNvZGVnZW4tcHJvamVjdC50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9zdGFydC9taWdyYXRlL3hjb2RlZ2VuLXByb2plY3RgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5zdGFydC5pdGVtcy5taWdyYXRlLml0ZW1zLmJhemVsLXByb2plY3QudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvc3RhcnQvbWlncmF0ZS9iYXplbC1wcm9qZWN0YCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgXSxcbiAgICAgICAgfSxcbiAgICAgIF0sXG4gICAgfSxcbiAgICB7XG4gICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj4ke2xvY2FsaXplZFN0cmluZyhcbiAgICAgICAgbG9jYWxlLFxuICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLnRleHRcIixcbiAgICAgICl9ICR7Y3ViZTAySWNvbigpfTwvc3Bhbj5gLFxuICAgICAgaXRlbXM6IFtcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMucHJvamVjdHMudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzYCxcbiAgICAgICAgICBpdGVtczogW1xuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMucHJvamVjdHMuaXRlbXMubWFuaWZlc3RzLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvbWFuaWZlc3RzYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5wcm9qZWN0cy5pdGVtcy5kaXJlY3Rvcnktc3RydWN0dXJlLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvZGlyZWN0b3J5LXN0cnVjdHVyZWAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMucHJvamVjdHMuaXRlbXMuZWRpdGluZy50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2VkaXRpbmdgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLnByb2plY3RzLml0ZW1zLmRlcGVuZGVuY2llcy50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2RlcGVuZGVuY2llc2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMucHJvamVjdHMuaXRlbXMuY29kZS1zaGFyaW5nLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvY29kZS1zaGFyaW5nYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5wcm9qZWN0cy5pdGVtcy5zeW50aGVzaXplZC1maWxlcy50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL3N5bnRoZXNpemVkLWZpbGVzYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5wcm9qZWN0cy5pdGVtcy5keW5hbWljLWNvbmZpZ3VyYXRpb24udGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9keW5hbWljLWNvbmZpZ3VyYXRpb25gLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLnByb2plY3RzLml0ZW1zLnRlbXBsYXRlcy50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL3RlbXBsYXRlc2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMucHJvamVjdHMuaXRlbXMucGx1Z2lucy50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL3BsdWdpbnNgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLnByb2plY3RzLml0ZW1zLmhhc2hpbmcudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9oYXNoaW5nYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5wcm9qZWN0cy5pdGVtcy50aGUtY29zdC1vZi1jb252ZW5pZW5jZS50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2Nvc3Qtb2YtY29udmVuaWVuY2VgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLnByb2plY3RzLml0ZW1zLnRtYS1hcmNoaXRlY3R1cmUudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy90bWEtYXJjaGl0ZWN0dXJlYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5wcm9qZWN0cy5pdGVtcy5iZXN0LXByYWN0aWNlcy50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2Jlc3QtcHJhY3RpY2VzYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgXSxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuYnVpbGQudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvYnVpbGRgLFxuICAgICAgICAgIGNvbGxhcHNlZDogdHJ1ZSxcbiAgICAgICAgICBpdGVtczogW1xuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuYnVpbGQuaXRlbXMuY2FjaGUudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZGV2ZWxvcC9idWlsZC9jYWNoZWAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj4ke2xvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5idWlsZC5pdGVtcy5yZWdpc3RyeS50ZXh0XCIsXG4gICAgICAgICAgICAgICl9ICR7eGNvZGVQcm9qQ29tcGF0aWJsZUJhZGdlKGxvY2FsZSl9PC9zcGFuPmAsXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL2J1aWxkL3JlZ2lzdHJ5YCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgXSxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMudGVzdC50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZGV2ZWxvcC90ZXN0YCxcbiAgICAgICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICAgICAgaXRlbXM6IFtcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLnRlc3QuaXRlbXMuc2VsZWN0aXZlLXRlc3RpbmcudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZGV2ZWxvcC90ZXN0L3NlbGVjdGl2ZS10ZXN0aW5nYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy50ZXN0Lml0ZW1zLmZsYWtpbmVzcy50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL3Rlc3QvZmxha2luZXNzYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgXSxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuaW5zcGVjdC50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICAgICAgaXRlbXM6IFtcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmluc3BlY3QuaXRlbXMuaW1wbGljaXQtaW1wb3J0cy50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL2luc3BlY3QvaW1wbGljaXQtZGVwZW5kZW5jaWVzYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgXSxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuYXV0b21hdGUudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5hdXRvbWF0ZS5pdGVtcy5jb250aW51b3VzLWludGVncmF0aW9uLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvYXV0b21hdGUvY29udGludW91cy1pbnRlZ3JhdGlvbmAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj4ke2xvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5hdXRvbWF0ZS5pdGVtcy53b3JrZmxvd3MudGV4dFwiLFxuICAgICAgICAgICAgICApfTwvc3Bhbj5gLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZGV2ZWxvcC9hdXRvbWF0ZS93b3JrZmxvd3NgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICBdLFxuICAgICAgICB9LFxuICAgICAgXSxcbiAgICB9LFxuICAgIHtcbiAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7bG9jYWxpemVkU3RyaW5nKFxuICAgICAgICBsb2NhbGUsXG4gICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLnNoYXJlLnRleHRcIixcbiAgICAgICl9ICR7Y3ViZTAxSWNvbigpfTwvc3Bhbj5gLFxuICAgICAgaXRlbXM6IFtcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7bG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuc2hhcmUuaXRlbXMucHJldmlld3MudGV4dFwiLFxuICAgICAgICAgICl9ICR7eGNvZGVQcm9qQ29tcGF0aWJsZUJhZGdlKGxvY2FsZSl9PC9zcGFuPmAsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3NoYXJlL3ByZXZpZXdzYCxcbiAgICAgICAgfSxcbiAgICAgIF0sXG4gICAgfSxcbiAgXTtcbn1cbiIsICJjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9kYXRhXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ZpbGVuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2RhdGEvY2xpLmpzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ltcG9ydF9tZXRhX3VybCA9IFwiZmlsZTovLy9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvZGF0YS9jbGkuanNcIjtpbXBvcnQgeyBleGVjYSwgJCB9IGZyb20gXCJleGVjYVwiO1xuaW1wb3J0IHsgdGVtcG9yYXJ5RGlyZWN0b3J5VGFzayB9IGZyb20gXCJ0ZW1weVwiO1xuaW1wb3J0ICogYXMgcGF0aCBmcm9tIFwibm9kZTpwYXRoXCI7XG5pbXBvcnQgeyBmaWxlVVJMVG9QYXRoIH0gZnJvbSBcIm5vZGU6dXJsXCI7XG5pbXBvcnQgZWpzIGZyb20gXCJlanNcIjtcbmltcG9ydCB7IGxvY2FsaXplZFN0cmluZyB9IGZyb20gXCIuLi9pMThuLm1qc1wiO1xuXG4vLyBSb290IGRpcmVjdG9yeVxuY29uc3QgX19kaXJuYW1lID0gcGF0aC5kaXJuYW1lKGZpbGVVUkxUb1BhdGgoaW1wb3J0Lm1ldGEudXJsKSk7XG5jb25zdCByb290RGlyZWN0b3J5ID0gcGF0aC5qb2luKF9fZGlybmFtZSwgXCIuLi8uLi8uLlwiKTtcblxuLy8gU2NoZW1hXG5hd2FpdCBleGVjYSh7XG4gIHN0ZGlvOiBcImluaGVyaXRcIixcbn0pYHN3aWZ0IGJ1aWxkIC0tcHJvZHVjdCBQcm9qZWN0RGVzY3JpcHRpb24gLS1jb25maWd1cmF0aW9uIGRlYnVnIC0tcGFja2FnZS1wYXRoICR7cm9vdERpcmVjdG9yeX1gO1xuYXdhaXQgZXhlY2Eoe1xuICBzdGRpbzogXCJpbmhlcml0XCIsXG59KWBzd2lmdCBidWlsZCAtLXByb2R1Y3QgdHVpc3QgLS1jb25maWd1cmF0aW9uIGRlYnVnIC0tcGFja2FnZS1wYXRoICR7cm9vdERpcmVjdG9yeX1gO1xudmFyIGR1bXBlZENMSVNjaGVtYTtcbmF3YWl0IHRlbXBvcmFyeURpcmVjdG9yeVRhc2soYXN5bmMgKHRtcERpcikgPT4ge1xuICAvLyBJJ20gcGFzc2luZyAtLXBhdGggdG8gc2FuZGJveCB0aGUgZXhlY3V0aW9uIHNpbmNlIHdlIGFyZSBvbmx5IGludGVyZXN0ZWQgaW4gdGhlIHNjaGVtYSBhbmQgbm90aGluZyBlbHNlLlxuICBkdW1wZWRDTElTY2hlbWEgPSBhd2FpdCAkYCR7cGF0aC5qb2luKFxuICAgIHJvb3REaXJlY3RvcnksXG4gICAgXCIuYnVpbGQvZGVidWcvdHVpc3RcIixcbiAgKX0gLS1leHBlcmltZW50YWwtZHVtcC1oZWxwIC0tcGF0aCAke3RtcERpcn1gO1xufSk7XG5jb25zdCB7IHN0ZG91dCB9ID0gZHVtcGVkQ0xJU2NoZW1hO1xuZXhwb3J0IGNvbnN0IHNjaGVtYSA9IEpTT04ucGFyc2Uoc3Rkb3V0KTtcblxuLy8gUGF0aHNcbmZ1bmN0aW9uIHRyYXZlcnNlKGNvbW1hbmQsIHBhdGhzKSB7XG4gIHBhdGhzLnB1c2goe1xuICAgIHBhcmFtczogeyBjb21tYW5kOiBjb21tYW5kLmxpbmsuc3BsaXQoXCJjbGkvXCIpWzFdIH0sXG4gICAgY29udGVudDogY29udGVudChjb21tYW5kKSxcbiAgfSk7XG4gIChjb21tYW5kLml0ZW1zID8/IFtdKS5mb3JFYWNoKChzdWJDb21tYW5kKSA9PiB7XG4gICAgdHJhdmVyc2Uoc3ViQ29tbWFuZCwgcGF0aHMpO1xuICB9KTtcbn1cblxuY29uc3QgdGVtcGxhdGUgPSBlanMuY29tcGlsZShcbiAgYFxuIyA8JT0gY29tbWFuZC5mdWxsQ29tbWFuZCAlPlxuPCU9IGNvbW1hbmQuc3BlYy5hYnN0cmFjdCAlPlxuPCUgaWYgKGNvbW1hbmQuc3BlYy5hcmd1bWVudHMgJiYgY29tbWFuZC5zcGVjLmFyZ3VtZW50cy5sZW5ndGggPiAwKSB7ICU+XG4jIyBBcmd1bWVudHNcbjwlIGNvbW1hbmQuc3BlYy5hcmd1bWVudHMuZm9yRWFjaChmdW5jdGlvbihhcmcpIHsgJT5cbiMjIyA8JS0gYXJnLnZhbHVlTmFtZSAlPiA8JS0gKGFyZy5pc09wdGlvbmFsKSA/IFwiPEJhZGdlIHR5cGU9J2luZm8nIHRleHQ9J09wdGlvbmFsJyAvPlwiIDogXCJcIiAlPiA8JS0gKGFyZy5pc0RlcHJlY2F0ZWQpID8gXCI8QmFkZ2UgdHlwZT0nd2FybmluZycgdGV4dD0nRGVwcmVjYXRlZCcgLz5cIiA6IFwiXCIgJT5cbjwlIGlmIChhcmcuZW52VmFyKSB7ICU+XG4qKkVudmlyb25tZW50IHZhcmlhYmxlKiogXFxgPCUtIGFyZy5lbnZWYXIgJT5cXGBcbjwlIH0gJT5cbjwlLSBhcmcuYWJzdHJhY3QgJT5cbjwlIGlmIChhcmcua2luZCA9PT0gXCJwb3NpdGlvbmFsXCIpIHsgLSU+XG5cXGBcXGBcXGBiYXNoXG48JS0gY29tbWFuZC5mdWxsQ29tbWFuZCAlPiBbPCUtIGFyZy52YWx1ZU5hbWUgJT5dXG5cXGBcXGBcXGBcbjwlIH0gZWxzZSBpZiAoYXJnLmtpbmQgPT09IFwiZmxhZ1wiKSB7IC0lPlxuXFxgXFxgXFxgYmFzaFxuPCUgYXJnLm5hbWVzLmZvckVhY2goZnVuY3Rpb24obmFtZSkgeyAtJT5cbjwlIGlmIChuYW1lLmtpbmQgPT09IFwibG9uZ1wiKSB7IC0lPlxuPCUtIGNvbW1hbmQuZnVsbENvbW1hbmQgJT4gLS08JS0gbmFtZS5uYW1lICU+XG48JSB9IGVsc2UgeyAtJT5cbjwlLSBjb21tYW5kLmZ1bGxDb21tYW5kICU+IC08JS0gbmFtZS5uYW1lICU+XG48JSB9IC0lPlxuPCUgfSkgLSU+XG5cXGBcXGBcXGBcbjwlIH0gZWxzZSBpZiAoYXJnLmtpbmQgPT09IFwib3B0aW9uXCIpIHsgLSU+XG5cXGBcXGBcXGBiYXNoXG48JSBhcmcubmFtZXMuZm9yRWFjaChmdW5jdGlvbihuYW1lKSB7IC0lPlxuPCUgaWYgKG5hbWUua2luZCA9PT0gXCJsb25nXCIpIHsgLSU+XG48JS0gY29tbWFuZC5mdWxsQ29tbWFuZCAlPiAtLTwlLSBuYW1lLm5hbWUgJT4gWzwlLSBhcmcudmFsdWVOYW1lICU+XVxuPCUgfSBlbHNlIHsgLSU+XG48JS0gY29tbWFuZC5mdWxsQ29tbWFuZCAlPiAtPCUtIG5hbWUubmFtZSAlPiBbPCUtIGFyZy52YWx1ZU5hbWUgJT5dXG48JSB9IC0lPlxuPCUgfSkgLSU+XG5cXGBcXGBcXGBcbjwlIH0gLSU+XG48JSB9KTsgLSU+XG48JSB9IC0lPlxuYCxcbiAge30sXG4pO1xuXG5mdW5jdGlvbiBjb250ZW50KGNvbW1hbmQpIHtcbiAgY29uc3QgZW52VmFyUmVnZXggPSAvXFwoZW52OlxccyooW14pXSspXFwpLztcbiAgY29uc3QgY29udGVudCA9IHRlbXBsYXRlKHtcbiAgICBjb21tYW5kOiB7XG4gICAgICAuLi5jb21tYW5kLFxuICAgICAgc3BlYzoge1xuICAgICAgICAuLi5jb21tYW5kLnNwZWMsXG4gICAgICAgIGFyZ3VtZW50czogY29tbWFuZC5zcGVjLmFyZ3VtZW50cy5tYXAoKGFyZykgPT4ge1xuICAgICAgICAgIGNvbnN0IGVudlZhck1hdGNoID0gYXJnLmFic3RyYWN0Lm1hdGNoKGVudlZhclJlZ2V4KTtcbiAgICAgICAgICByZXR1cm4ge1xuICAgICAgICAgICAgLi4uYXJnLFxuICAgICAgICAgICAgZW52VmFyOiBlbnZWYXJNYXRjaCA/IGVudlZhck1hdGNoWzFdIDogdW5kZWZpbmVkLFxuICAgICAgICAgICAgaXNEZXByZWNhdGVkOlxuICAgICAgICAgICAgICBhcmcuYWJzdHJhY3QuaW5jbHVkZXMoXCJbRGVwcmVjYXRlZF1cIikgfHxcbiAgICAgICAgICAgICAgYXJnLmFic3RyYWN0LmluY2x1ZGVzKFwiW2RlcHJlY2F0ZWRdXCIpLFxuICAgICAgICAgICAgYWJzdHJhY3Q6IGFyZy5hYnN0cmFjdFxuICAgICAgICAgICAgICAucmVwbGFjZShlbnZWYXJSZWdleCwgXCJcIilcbiAgICAgICAgICAgICAgLnJlcGxhY2UoXCJbRGVwcmVjYXRlZF1cIiwgXCJcIilcbiAgICAgICAgICAgICAgLnJlcGxhY2UoXCJbZGVwcmVjYXRlZF1cIiwgXCJcIilcbiAgICAgICAgICAgICAgLnRyaW0oKVxuICAgICAgICAgICAgICAucmVwbGFjZSgvPChbXj5dKyk+L2csIFwiXFxcXDwkMVxcXFw+XCIpLFxuICAgICAgICAgIH07XG4gICAgICAgIH0pLFxuICAgICAgfSxcbiAgICB9LFxuICB9KTtcbiAgcmV0dXJuIGNvbnRlbnQ7XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiBwYXRocyhsb2NhbGUpIHtcbiAgbGV0IHBhdGhzID0gW107XG4gIChhd2FpdCBsb2FkRGF0YShsb2NhbGUpKS5pdGVtc1swXS5pdGVtcy5mb3JFYWNoKChjb21tYW5kKSA9PiB7XG4gICAgdHJhdmVyc2UoY29tbWFuZCwgcGF0aHMpO1xuICB9KTtcbiAgcmV0dXJuIHBhdGhzO1xufVxuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gbG9hZERhdGEobG9jYWxlKSB7XG4gIGZ1bmN0aW9uIHBhcnNlQ29tbWFuZChcbiAgICBjb21tYW5kLFxuICAgIHBhcmVudENvbW1hbmQgPSBcInR1aXN0XCIsXG4gICAgcGFyZW50UGF0aCA9IGAvJHtsb2NhbGV9L2NsaS9gLFxuICApIHtcbiAgICBjb25zdCBvdXRwdXQgPSB7XG4gICAgICB0ZXh0OiBjb21tYW5kLmNvbW1hbmROYW1lLFxuICAgICAgZnVsbENvbW1hbmQ6IHBhcmVudENvbW1hbmQgKyBcIiBcIiArIGNvbW1hbmQuY29tbWFuZE5hbWUsXG4gICAgICBsaW5rOiBwYXRoLmpvaW4ocGFyZW50UGF0aCwgY29tbWFuZC5jb21tYW5kTmFtZSksXG4gICAgICBzcGVjOiBjb21tYW5kLFxuICAgIH07XG4gICAgaWYgKGNvbW1hbmQuc3ViY29tbWFuZHMgJiYgY29tbWFuZC5zdWJjb21tYW5kcy5sZW5ndGggIT09IDApIHtcbiAgICAgIG91dHB1dC5pdGVtcyA9IGNvbW1hbmQuc3ViY29tbWFuZHMubWFwKChzdWJjb21tYW5kKSA9PiB7XG4gICAgICAgIHJldHVybiBwYXJzZUNvbW1hbmQoXG4gICAgICAgICAgc3ViY29tbWFuZCxcbiAgICAgICAgICBwYXJlbnRDb21tYW5kICsgXCIgXCIgKyBjb21tYW5kLmNvbW1hbmROYW1lLFxuICAgICAgICAgIHBhdGguam9pbihwYXJlbnRQYXRoLCBjb21tYW5kLmNvbW1hbmROYW1lKSxcbiAgICAgICAgKTtcbiAgICAgIH0pO1xuICAgIH1cblxuICAgIHJldHVybiBvdXRwdXQ7XG4gIH1cblxuICBjb25zdCB7XG4gICAgY29tbWFuZDogeyBzdWJjb21tYW5kcyB9LFxuICB9ID0gc2NoZW1hO1xuXG4gIHJldHVybiB7XG4gICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKGxvY2FsZSwgXCJzaWRlYmFycy5jbGkudGV4dFwiKSxcbiAgICBpdGVtczogW1xuICAgICAge1xuICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcobG9jYWxlLCBcInNpZGViYXJzLmNsaS5pdGVtcy5jb21tYW5kcy50ZXh0XCIpLFxuICAgICAgICBpdGVtczogc3ViY29tbWFuZHNcbiAgICAgICAgICAubWFwKChjb21tYW5kKSA9PiB7XG4gICAgICAgICAgICByZXR1cm4ge1xuICAgICAgICAgICAgICAuLi5wYXJzZUNvbW1hbmQoY29tbWFuZCksXG4gICAgICAgICAgICAgIGNvbGxhcHNlZDogdHJ1ZSxcbiAgICAgICAgICAgIH07XG4gICAgICAgICAgfSlcbiAgICAgICAgICAuc29ydCgoYSwgYikgPT4gYS50ZXh0LmxvY2FsZUNvbXBhcmUoYi50ZXh0KSksXG4gICAgICB9LFxuICAgIF0sXG4gIH07XG59XG4iXSwKICAibWFwcGluZ3MiOiAiO0FBQXdWLFNBQVMsb0JBQW9CO0FBQ3JYLFlBQVlBLFdBQVU7QUFDdEIsWUFBWUMsU0FBUTs7O0FDRnBCO0FBQUEsRUFDRSxPQUFTO0FBQUEsSUFDUCxXQUFhO0FBQUEsTUFDWCxPQUFTO0FBQUEsUUFDUCxNQUFRO0FBQUEsTUFDVjtBQUFBLE1BQ0EsYUFBZTtBQUFBLFFBQ2IsTUFBUTtBQUFBLE1BQ1Y7QUFBQSxNQUNBLEtBQU87QUFBQSxRQUNMLE1BQVE7QUFBQSxNQUNWO0FBQUEsSUFDRjtBQUFBLEVBQ0Y7QUFBQSxFQUNBLFFBQVU7QUFBQSxJQUNSLGFBQWU7QUFBQSxJQUNmLGNBQWdCO0FBQUEsTUFDZCxRQUFVO0FBQUEsUUFDUixlQUFlO0FBQUEsUUFDZixxQkFBcUI7QUFBQSxN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QU07QUFBQSxnQkFDSjtBQUFBLGdCQUNBO0FBQUEsY0FDRjtBQUFBLGNBQ0EsTUFBTSxJQUFJLE1BQU07QUFBQSxZQUNsQjtBQUFBLFlBQ0E7QUFBQSxjQUNFLE1BQU07QUFBQSxnQkFDSjtBQUFBLGdCQUNBO0FBQUEsY0FDRjtBQUFBLGNBQ0EsTUFBTSxJQUFJLE1BQU07QUFBQSxZQUNsQjtBQUFBLFlBQ0E7QUFBQSxjQUNFLE1BQU07QUFBQSxnQkFDSjtBQUFBLGdCQUNBO0FBQUEsY0FDRjtBQUFBLGNBQ0EsTUFBTSxJQUFJLE1BQU07QUFBQSxZQUNsQjtBQUFBLFlBQ0E7QUFBQSxjQUNFLE1BQU07QUFBQSxnQkFDSjtBQUFBLGdCQUNBO0FBQUEsY0FDRjtBQUFBLGNBQ0EsTUFBTSxJQUFJLE1BQU07QUFBQSxZQUNsQjtBQUFBLFlBQ0E7QUFBQSxjQUNFLE1BQU07QUFBQSxnQkFDSjtBQUFBLGdCQUNBO0FBQUEsY0FDRjtBQUFBLGNBQ0EsTUFBTSxJQUFJLE1BQU07QUFBQSxZQUNsQjtBQUFBLFlBQ0E7QUFBQSxjQUNFLE1BQU07QUFBQSxnQkFDSjtBQUFBLGdCQUNBO0FBQUEsY0FDRjtBQUFBLGNBQ0EsTUFBTSxJQUFJLE1BQU07QUFBQSxZQUNsQjtBQUFBLFlBQ0E7QUFBQSxjQUNFLE1BQU07QUFBQSxnQkFDSjtBQUFBLGdCQUNBO0FBQUEsY0FDRjtBQUFBLGNBQ0EsTUFBTSxJQUFJLE1BQU07QUFBQSxZQUNsQjtBQUFBLFVBQ0Y7QUFBQSxRQUNGO0FBQUEsUUFDQTtBQUFBLFVBQ0UsTUFBTTtBQUFBLFlBQ0o7QUFBQSxZQUNBO0FBQUEsVUFDRjtBQUFBLFVBQ0EsTUFBTSxJQUFJLE1BQU07QUFBQSxVQUNoQixXQUFXO0FBQUEsVUFDWCxPQUFPO0FBQUEsWUFDTDtBQUFBLGNBQ0UsTUFBTTtBQUFBLGdCQUNKO0FBQUEsZ0JBQ0E7QUFBQSxjQUNGO0FBQUEsY0FDQSxNQUFNLElBQUksTUFBTTtBQUFBLFlBQ2xCO0FBQUEsWUFDQTtBQUFBLGNBQ0UsTUFBTSxvRkFBb0Y7QUFBQSxnQkFDeEY7QUFB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TSxVQUFVLE1BQU0saUNBQWlDO0FBQUEsTUFDekQsRUFBRSxNQUFNLFlBQVksTUFBTSwrQkFBK0I7QUFBQSxNQUN6RCxFQUFFLE1BQU0sV0FBVyxNQUFNLHFDQUFxQztBQUFBLE1BQzlEO0FBQUEsUUFDRSxNQUFNO0FBQUEsUUFDTixNQUFNO0FBQUEsTUFDUjtBQUFBLElBQ0Y7QUFBQSxJQUNBLFFBQVE7QUFBQSxNQUNOLFNBQVM7QUFBQSxNQUNULFdBQVc7QUFBQSxJQUNiO0FBQUEsRUFDRjtBQUNGLENBQUM7IiwKICAibmFtZXMiOiBbInBhdGgiLCAiZnMiLCAia2V5IiwgInBhdGgiLCAiZmciLCAiZnMiLCAiX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUiLCAibG9hZERhdGEiLCAiX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUiLCAiZmciLCAiZnMiLCAibG9hZERhdGEiLCAicHJvamVjdERlc2NyaXB0aW9uU2lkZWJhciIsICJwYXRoIiwgImxvYWREYXRhIiwgIl9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lIiwgImxvYWREYXRhIiwgIl9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lIiwgIiQiXQp9Cg==
