// .vitepress/config.mjs
import { defineConfig } from "file:///Users/pepicrft/src/github.com/tuist/tuist/node_modules/.pnpm/vitepress@1.6.3_@algolia+client-search@5.28.0_postcss@8.5.6_search-insights@2.17.3/node_modules/vitepress/dist/node/index.js";
import * as path4 from "node:path";
import * as fs3 from "node:fs/promises";

// .vitepress/icons.mjs
function playIcon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M5 4.98963C5 4.01847 5 3.53289 5.20249 3.26522C5.37889 3.03203 5.64852 2.88773 5.9404 2.8703C6.27544 2.8503 6.67946 3.11965 7.48752 3.65835L18.0031 10.6687C18.6708 11.1139 19.0046 11.3364 19.1209 11.6169C19.2227 11.8622 19.2227 12.1378 19.1209 12.3831C19.0046 12.6636 18.6708 12.8862 18.0031 13.3313L7.48752 20.3417C6.67946 20.8804 6.27544 21.1497 5.9404 21.1297C5.64852 21.1123 5.37889 20.968 5.20249 20.7348C5 20.4671 5 19.9815 5 19.0104V4.98963Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>
`;
}
function cube02Icon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M12 2.50008V12.0001M12 12.0001L20.5 7.27779M12 12.0001L3.5 7.27779M12 12.0001V21.5001M20.5 16.7223L12.777 12.4318C12.4934 12.2742 12.3516 12.1954 12.2015 12.1645C12.0685 12.1372 11.9315 12.1372 11.7986 12.1645C11.6484 12.1954 11.5066 12.2742 11.223 12.4318L3.5 16.7223M21 16.0586V7.94153C21 7.59889 21 7.42757 20.9495 7.27477C20.9049 7.13959 20.8318 7.01551 20.7354 6.91082C20.6263 6.79248 20.4766 6.70928 20.177 6.54288L12.777 2.43177C12.4934 2.27421 12.3516 2.19543 12.2015 2.16454C12.0685 2.13721 11.9315 2.13721 11.7986 2.16454C11.6484 2.19543 11.5066 2.27421 11.223 2.43177L3.82297 6.54288C3.52345 6.70928 3.37369 6.79248 3.26463 6.91082C3.16816 7.01551 3.09515 7.13959 3.05048 7.27477C3 7.42757 3 7.59889 3 7.94153V16.0586C3 16.4013 3 16.5726 3.05048 16.7254C3.09515 16.8606 3.16816 16.9847 3.26463 17.0893C3.37369 17.2077 3.52345 17.2909 3.82297 17.4573L11.223 21.5684C11.5066 21.726 11.6484 21.8047 11.7986 21.8356C11.9315 21.863 12.0685 21.863 12.2015 21.8356C12.3516 21.8047 12.4934 21.726 12.777 21.5684L20.177 17.4573C20.4766 17.2909 20.6263 17.2077 20.7354 17.0893C20.8318 16.9847 20.9049 16.8606 20.9495 16.7254C21 16.5726 21 16.4013 21 16.0586Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
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
import fg from "file:///Users/pepicrft/src/github.com/tuist/tuist/node_modules/.pnpm/fast-glob@3.3.3/node_modules/fast-glob/out/index.js";
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
import fg2 from "file:///Users/pepicrft/src/github.com/tuist/tuist/node_modules/.pnpm/fast-glob@3.3.3/node_modules/fast-glob/out/index.js";
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
        cli: {
          items: {
            logging: {
              text: "Logging"
            },
            "shell-completions": {
              text: "Shell completions"
            }
          }
        },
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
        },
        cli: {
          text: "CLI",
          items: {
            logging: {
              text: "Logging"
            }
          }
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
        tuist: {
          text: "Tuist",
          items: {
            about: {
              text: "About Tuist"
            }
          }
        },
        "quick-start": {
          text: "Quick start",
          items: {
            "install-tuist": {
              text: "Install Tuist"
            },
            "get-started": {
              text: "Get started"
            }
          }
        },
        features: {
          text: "Features"
        },
        develop: {
          text: "Develop",
          items: {
            "generated-projects": {
              text: "Generated projects",
              items: {
                adoption: {
                  text: "Adoption",
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
                inspect: {
                  text: "Inspect",
                  items: {
                    "implicit-imports": {
                      text: "Implicit imports"
                    }
                  }
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
            cache: {
              text: "Cache"
            },
            registry: {
              text: "Registry",
              items: {
                registry: {
                  text: "Registry"
                },
                "xcode-project": {
                  text: "Xcode project"
                },
                "generated-project": {
                  text: "Generated project"
                },
                "xcodeproj-integration": {
                  text: "XcodeProj-based integration"
                },
                "swift-package": {
                  text: "Swift package"
                },
                "continuous-integration": {
                  text: "Continuous integration"
                }
              }
            },
            "selective-testing": {
              text: "Selective testing",
              items: {
                "selective-testing": {
                  text: "Selective testing"
                },
                "xcode-project": {
                  text: "Xcode project"
                },
                "generated-project": {
                  text: "Generated project"
                }
              }
            },
            insights: {
              text: "Insights"
            },
            "bundle-size": {
              text: "Bundle size"
            }
          }
        },
        integrations: {
          text: "Integrations",
          items: {
            mcp: {
              text: "Model Context Protocol (MCP)"
            },
            "continuous-integration": {
              text: "Continuous integration"
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
        text: "\u041F\u0435\u0440\u0435\u0432\u043E\u0434 \u{1F30D}"
      },
      description: {
        text: "\u0412\u044B \u043C\u043E\u0436\u0435\u0442\u0435 \u043F\u0435\u0440\u0435\u0432\u0435\u0441\u0442\u0438 \u0438\u043B\u0438 \u0443\u043B\u0443\u0447\u0448\u0438\u0442\u044C \u043F\u0435\u0440\u0435\u0432\u043E\u0434 \u044D\u0442\u043E\u0439 \u0441\u0442\u0440\u0430\u043D\u0438\u0446\u044B."
      },
      cta: {
        text: "\u0412\u043D\u0435\u0441\u0442\u0438 \u0432\u043A\u043B\u0430\u0434"
      }
    }
  },
  search: {
    placeholder: "\u041F\u043E\u0438\u0441\u043A",
    translations: {
      button: {
        "button-text": "\u041F\u043E\u0438\u0441\u043A \u0434\u043E\u043A\u0443\u043C\u0435\u043D\u0442\u0430\u0446\u0438\u0438",
        "button-aria-label": "\u041F\u043E\u0438\u0441\u043A \u0434\u043E\u043A\u0443\u043C\u0435\u043D\u0442\u0430\u0446\u0438\u0438"
      },
      modal: {
        "search-box": {
          "reset-button-title": "\u041E\u0447\u0438\u0441\u0442\u0438\u0442\u044C \u0437\u0430\u043F\u0440\u043E\u0441",
          "reset-button-aria-label": "\u041E\u0447\u0438\u0441\u0442\u0438\u0442\u044C \u0437\u0430\u043F\u0440\u043E\u0441",
          "cancel-button-text": "\u041E\u0442\u043C\u0435\u043D\u0438\u0442\u044C",
          "cancel-button-aria-label": "\u041E\u0442\u043C\u0435\u043D\u0438\u0442\u044C"
        },
        "start-screen": {
          "recent-searches-title": "\u0418\u0441\u0442\u043E\u0440\u0438\u044F \u043F\u043E\u0438\u0441\u043A\u0430",
          "no-recent-searches-text": "\u041D\u0435\u0442 \u0438\u0441\u0442\u043E\u0440\u0438\u0438 \u043F\u043E\u0438\u0441\u043A\u0430",
          "save-recent-search-button-title": "\u0421\u043E\u0445\u0440\u0430\u043D\u0438\u0442\u044C \u0432 \u0438\u0441\u0442\u043E\u0440\u0438\u044E \u043F\u043E\u0438\u0441\u043A\u0430",
          "remove-recent-search-button-title": "\u0423\u0434\u0430\u043B\u0438\u0442\u044C \u0438\u0437 \u0438\u0441\u0442\u043E\u0440\u0438\u0438 \u043F\u043E\u0438\u0441\u043A\u0430",
          "favorite-searches-title": "\u0418\u0437\u0431\u0440\u0430\u043D\u043D\u043E\u0435",
          "remove-favorite-search-button-title": "\u0423\u0434\u0430\u043B\u0438\u0442\u044C \u0438\u0437 \u0438\u0437\u0431\u0440\u0430\u043D\u043D\u043E\u0433\u043E"
        },
        "error-screen": {
          "title-text": "\u041D\u0435 \u0443\u0434\u0430\u0435\u0442\u0441\u044F \u043F\u043E\u043B\u0443\u0447\u0438\u0442\u044C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u044B",
          "help-text": "\u0412\u043E\u0437\u043C\u043E\u0436\u043D\u043E, \u0432\u0430\u043C \u043D\u0435\u043E\u0431\u0445\u043E\u0434\u0438\u043C\u043E \u043F\u0440\u043E\u0432\u0435\u0440\u0438\u0442\u044C \u0441\u0435\u0442\u0435\u0432\u043E\u0435 \u043F\u043E\u0434\u043A\u043B\u044E\u0447\u0435\u043D\u0438\u0435"
        },
        footer: {
          "select-text": "\u0412\u044B\u0431\u0440\u0430\u0442\u044C",
          "navigate-text": "\u041F\u0435\u0440\u0435\u0439\u0442\u0438",
          "close-text": "\u0417\u0430\u043A\u0440\u044B\u0442\u044C",
          "search-by-text": "\u041F\u043E\u0438\u0441\u043A\u043E\u0432\u0430\u044F \u0441\u0438\u0441\u0442\u0435\u043C\u0430"
        },
        "no-results-screen": {
          "no-results-text": "\u0420\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u044B \u043D\u0435 \u043D\u0430\u0439\u0434\u0435\u043D\u044B",
          "suggested-query-text": "\u0412\u044B \u043C\u043E\u0436\u0435\u0442\u0435 \u043F\u043E\u043F\u0440\u043E\u0431\u043E\u0432\u0430\u0442\u044C \u0437\u0430\u043F\u0440\u043E\u0441\u0438\u0442\u044C",
          "report-missing-results-text": "\u0421\u0447\u0438\u0442\u0430\u0435\u0442\u0435, \u0447\u0442\u043E \u044D\u0442\u043E\u0442 \u0437\u0430\u043F\u0440\u043E\u0441 \u0434\u043E\u043B\u0436\u0435\u043D \u0438\u043C\u0435\u0442\u044C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u044B?",
          "report-missing-results-link-text": "\u041D\u0430\u0436\u043C\u0438\u0442\u0435, \u0447\u0442\u043E\u0431\u044B \u043E\u0441\u0442\u0430\u0432\u0438\u0442\u044C \u043E\u0442\u0437\u044B\u0432"
        }
      }
    }
  },
  navbar: {
    guides: {
      text: "\u0420\u0443\u043A\u043E\u0432\u043E\u0434\u0441\u0442\u0432\u0430"
    },
    cli: {
      text: "CLI"
    },
    server: {
      text: "\u0421\u0435\u0440\u0432\u0435\u0440"
    },
    resources: {
      text: "\u0420\u0435\u0441\u0443\u0440\u0441\u044B",
      items: {
        references: {
          text: "\u0421\u0441\u044B\u043B\u043A\u0438"
        },
        contributors: {
          text: "\u0421\u043E\u0443\u0447\u0430\u0441\u0442\u043D\u0438\u043A\u0438"
        },
        changelog: {
          text: "\u0418\u0441\u0442\u043E\u0440\u0438\u044F \u0438\u0437\u043C\u0435\u043D\u0435\u043D\u0438\u0439"
        }
      }
    }
  },
  sidebars: {
    cli: {
      text: "CLI",
      items: {
        cli: {
          items: {
            logging: {
              text: "\u041B\u043E\u0433\u0438\u0440\u043E\u0432\u0430\u043D\u0438\u0435"
            },
            "shell-completions": {
              text: "\u0410\u0432\u0442\u043E\u0437\u0430\u0432\u0435\u0440\u0448\u0435\u043D\u0438\u044F Shell"
            }
          }
        },
        commands: {
          text: "\u041A\u043E\u043C\u0430\u043D\u0434\u044B"
        }
      }
    },
    references: {
      text: "\u0421\u0441\u044B\u043B\u043A\u0438",
      items: {
        examples: {
          text: "\u041F\u0440\u0438\u043C\u0435\u0440\u044B"
        },
        migrations: {
          text: "Migrations",
          items: {
            "from-v3-to-v4": {
              text: "\u041E\u0442 v3 \u0434\u043E \u0432\u0435\u0440\u0441\u0438\u0438 v4"
            }
          }
        }
      }
    },
    contributors: {
      text: "\u0421\u043E\u0443\u0447\u0430\u0441\u0442\u043D\u0438\u043A\u0438",
      items: {
        "get-started": {
          text: "\u041D\u0430\u0447\u0430\u043B\u043E \u0440\u0430\u0431\u043E\u0442\u044B"
        },
        "issue-reporting": {
          text: "\u041E\u0442\u0447\u0435\u0442 \u043E\u0431 \u043E\u0448\u0438\u0431\u043A\u0430\u0445"
        },
        "code-reviews": {
          text: "\u041A\u043E\u0434 \u0440\u0435\u0432\u044C\u044E"
        },
        principles: {
          text: "\u041F\u0440\u0438\u043D\u0446\u0438\u043F\u044B"
        },
        translate: {
          text: "Translate"
        },
        cli: {
          text: "CLI",
          items: {
            logging: {
              text: "\u041B\u043E\u0433\u0438\u0440\u043E\u0432\u0430\u043D\u0438\u0435"
            }
          }
        }
      }
    },
    server: {
      items: {
        introduction: {
          text: "\u0412\u0432\u0435\u0434\u0435\u043D\u0438\u0435",
          items: {
            "why-server": {
              text: "\u0417\u0430\u0447\u0435\u043C \u0441\u0435\u0440\u0432\u0435\u0440?"
            },
            "accounts-and-projects": {
              text: "\u0410\u043A\u043A\u0430\u0443\u043D\u0442\u044B \u0438 \u043F\u0440\u043E\u0435\u043A\u0442\u044B"
            },
            authentication: {
              text: "\u0410\u0432\u0442\u043E\u0440\u0438\u0437\u0430\u0446\u0438\u044F"
            },
            integrations: {
              text: "\u0418\u043D\u0442\u0435\u0433\u0440\u0430\u0446\u0438\u044F"
            }
          }
        },
        "on-premise": {
          text: "\u041B\u043E\u043A\u0430\u043B\u044C\u043D\u044B\u0439 \u0445\u043E\u0441\u0442\u0438\u043D\u0433",
          items: {
            install: {
              text: "\u0423\u0441\u0442\u0430\u043D\u043E\u0432\u043A\u0430"
            },
            metrics: {
              text: "\u041C\u0435\u0442\u0440\u0438\u043A\u0438"
            }
          }
        },
        "api-documentation": {
          text: "API \u0434\u043E\u043A\u0443\u043C\u0435\u043D\u0442\u0430\u0446\u0438\u044F"
        },
        status: {
          text: "\u0421\u0442\u0430\u0442\u0443\u0441"
        },
        "metrics-dashboard": {
          text: "\u041F\u0430\u043D\u0435\u043B\u044C \u043F\u043E\u043A\u0430\u0437\u0430\u0442\u0435\u043B\u0435\u0439"
        }
      }
    },
    guides: {
      text: "\u0420\u0443\u043A\u043E\u0432\u043E\u0434\u0441\u0442\u0432\u0430",
      items: {
        tuist: {
          text: "Tuist",
          items: {
            about: {
              text: "\u041F\u0440\u043E Tuist"
            }
          }
        },
        "quick-start": {
          text: "\u0411\u044B\u0441\u0442\u0440\u044B\u0439 \u0441\u0442\u0430\u0440\u0442",
          items: {
            "install-tuist": {
              text: "\u0423\u0441\u0442\u0430\u043D\u043E\u0432\u043A\u0430 Tuist"
            },
            "get-started": {
              text: "\u041D\u0430\u0447\u0430\u043B\u043E \u0440\u0430\u0431\u043E\u0442\u044B"
            }
          }
        },
        features: {
          text: "\u0412\u043E\u0437\u043C\u043E\u0436\u043D\u043E\u0441\u0442\u0438"
        },
        develop: {
          text: "\u0420\u0430\u0437\u0440\u0430\u0431\u043E\u0442\u043A\u0430",
          items: {
            "generated-projects": {
              text: "\u0421\u0433\u0435\u043D\u0435\u0440\u0438\u0440\u043E\u0432\u0430\u043D\u043D\u044B\u0435 \u043F\u0440\u043E\u0435\u043A\u0442\u044B",
              items: {
                adoption: {
                  text: "\u0412\u044B\u0431\u043E\u0440",
                  items: {
                    "new-project": {
                      text: "\u0421\u043E\u0437\u0434\u0430\u043D\u0438\u0435 \u043D\u043E\u0432\u043E\u0433\u043E \u043F\u0440\u043E\u0435\u043A\u0442\u0430"
                    },
                    "swift-package": {
                      text: "\u041F\u043E\u043F\u0440\u043E\u0431\u0443\u0439\u0442\u0435 \u0441 Swift Package"
                    },
                    migrate: {
                      text: "\u041C\u0438\u0433\u0440\u0430\u0446\u0438\u044F",
                      items: {
                        "xcode-project": {
                          text: "\u041F\u0440\u043E\u0435\u043A\u0442 Xcode"
                        },
                        "swift-package": {
                          text: "\u041F\u0430\u043A\u0435\u0442 Swift"
                        },
                        "xcodegen-project": {
                          text: "\u041F\u0440\u043E\u0435\u043A\u0442 XcodeGen"
                        },
                        "bazel-project": {
                          text: "\u041F\u0440\u043E\u0435\u043A\u0442 Bazel"
                        }
                      }
                    }
                  }
                },
                manifests: {
                  text: "\u041C\u0430\u043D\u0438\u0444\u0435\u0441\u0442\u044B"
                },
                "directory-structure": {
                  text: "\u0421\u0442\u0440\u0443\u043A\u0442\u0443\u0440\u0430 \u0434\u0438\u0440\u0435\u043A\u0442\u043E\u0440\u0438\u0439"
                },
                editing: {
                  text: "\u0420\u0435\u0434\u0430\u043A\u0442\u0438\u0440\u043E\u0432\u0430\u043D\u0438\u0435"
                },
                dependencies: {
                  text: "\u0417\u0430\u0432\u0438\u0441\u0438\u043C\u043E\u0441\u0442\u0438"
                },
                "code-sharing": {
                  text: "\u0421\u043E\u0432\u043C\u0435\u0441\u0442\u043D\u043E\u0435 \u0438\u0441\u043F\u043E\u043B\u044C\u0437\u043E\u0432\u0430\u043D\u0438\u0435 \u043A\u043E\u0434\u0430"
                },
                "synthesized-files": {
                  text: "\u0421\u0438\u043D\u0442\u0435\u0437\u0438\u0440\u043E\u0432\u0430\u043D\u043D\u044B\u0435 \u0444\u0430\u0439\u043B\u044B"
                },
                "dynamic-configuration": {
                  text: "\u0414\u0438\u043D\u0430\u043C\u0438\u0447\u0435\u0441\u043A\u0430\u044F \u043A\u043E\u043D\u0444\u0438\u0433\u0443\u0440\u0430\u0446\u0438\u044F"
                },
                templates: {
                  text: "\u0428\u0430\u0431\u043B\u043E\u043D\u044B"
                },
                plugins: {
                  text: "\u041F\u043B\u0430\u0433\u0438\u043D\u044B"
                },
                hashing: {
                  text: "\u0425\u044D\u0448\u0438\u0440\u043E\u0432\u0430\u043D\u0438\u0435"
                },
                inspect: {
                  text: "\u0418\u0441\u0441\u043B\u0435\u0434\u043E\u0432\u0430\u0442\u044C",
                  items: {
                    "implicit-imports": {
                      text: "\u041D\u0435\u044F\u0432\u043D\u044B\u0435 \u0438\u043C\u043F\u043E\u0440\u0442\u044B"
                    }
                  }
                },
                "the-cost-of-convenience": {
                  text: "\u0421\u0442\u043E\u0438\u043C\u043E\u0441\u0442\u044C \u0443\u0434\u043E\u0431\u0441\u0442\u0432\u0430"
                },
                "tma-architecture": {
                  text: "\u041C\u043E\u0434\u0443\u043B\u044C\u043D\u0430\u044F \u0430\u0440\u0445\u0438\u0442\u0435\u043A\u0442\u0443\u0440\u0430"
                },
                "best-practices": {
                  text: "\u041B\u0443\u0447\u0448\u0438\u0435 \u043F\u0440\u0430\u043A\u0442\u0438\u043A\u0438"
                }
              }
            },
            cache: {
              text: "\u041A\u044D\u0448"
            },
            registry: {
              text: "\u0420\u0435\u0435\u0441\u0442\u0440",
              items: {
                registry: {
                  text: "\u0420\u0435\u0435\u0441\u0442\u0440"
                },
                "xcode-project": {
                  text: "\u041F\u0440\u043E\u0435\u043A\u0442 Xcode"
                },
                "generated-project": {
                  text: "\u0421\u0433\u0435\u043D\u0435\u0440\u0438\u0440\u043E\u0432\u0430\u043D\u043D\u044B\u0439 \u043F\u0440\u043E\u0435\u043A\u0442"
                },
                "xcodeproj-integration": {
                  text: "\u0418\u043D\u0442\u0435\u0433\u0440\u0430\u0446\u0438\u044F \u043D\u0430 \u043E\u0441\u043D\u043E\u0432\u0435 XcodeProj"
                },
                "swift-package": {
                  text: "\u041F\u0430\u043A\u0435\u0442 Swift"
                },
                "continuous-integration": {
                  text: "Continuous integration"
                }
              }
            },
            "selective-testing": {
              text: "\u0412\u044B\u0431\u043E\u0440\u043E\u0447\u043D\u043E\u0435 \u0442\u0435\u0441\u0442\u0438\u0440\u043E\u0432\u0430\u043D\u0438\u0435",
              items: {
                "selective-testing": {
                  text: "\u0412\u044B\u0431\u043E\u0440\u043E\u0447\u043D\u043E\u0435 \u0442\u0435\u0441\u0442\u0438\u0440\u043E\u0432\u0430\u043D\u0438\u0435"
                },
                "xcode-project": {
                  text: "Xcode project"
                },
                "generated-project": {
                  text: "\u0421\u0433\u0435\u043D\u0435\u0440\u0438\u0440\u043E\u0432\u0430\u043D\u043D\u044B\u0439 \u043F\u0440\u043E\u0435\u043A\u0442"
                }
              }
            },
            insights: {
              text: "\u0410\u043D\u0430\u043B\u0438\u0442\u0438\u043A\u0430"
            },
            "bundle-size": {
              text: "Bundle size"
            }
          }
        },
        integrations: {
          text: "Integrations",
          items: {
            mcp: {
              text: "\u041F\u0440\u043E\u0442\u043E\u043A\u043E\u043B \u043A\u043E\u043D\u0442\u0435\u043A\u0441\u0442\u0430 \u043C\u043E\u0434\u0435\u043B\u0438 (MCP)"
            },
            "continuous-integration": {
              text: "\u041D\u0435\u043F\u0440\u0435\u0440\u044B\u0432\u043D\u0430\u044F \u0438\u043D\u0442\u0435\u0433\u0440\u0430\u0446\u0438\u044F (CI)"
            }
          }
        },
        share: {
          text: "\u041F\u043E\u0434\u0435\u043B\u0438\u0442\u044C\u0441\u044F",
          items: {
            previews: {
              text: "\u041F\u0440\u0435\u0432\u044C\u044E"
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
        text: "Translation \u{1F30D}"
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
          "reset-button-title": "\uCFFC\uB9AC \uCD08\uAE30\uD654",
          "reset-button-aria-label": "\uCFFC\uB9AC \uCD08\uAE30\uD654",
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
        cli: {
          items: {
            logging: {
              text: "\uB85C\uAE45"
            },
            "shell-completions": {
              text: "Shell completions"
            }
          }
        },
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
        },
        cli: {
          text: "CLI",
          items: {
            logging: {
              text: "\uB85C\uAE45"
            }
          }
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
        tuist: {
          text: "Tuist",
          items: {
            about: {
              text: "About Tuist"
            }
          }
        },
        "quick-start": {
          text: "Quick start",
          items: {
            "install-tuist": {
              text: "Install Tuist"
            },
            "get-started": {
              text: "Get started"
            }
          }
        },
        features: {
          text: "\uAE30\uB2A5"
        },
        develop: {
          text: "Develop",
          items: {
            "generated-projects": {
              text: "Generated projects",
              items: {
                adoption: {
                  text: "Adoption",
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
                inspect: {
                  text: "Inspect",
                  items: {
                    "implicit-imports": {
                      text: "Implicit imports"
                    }
                  }
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
            cache: {
              text: "Cache"
            },
            registry: {
              text: "Registry",
              items: {
                registry: {
                  text: "Registry"
                },
                "xcode-project": {
                  text: "Xcode project"
                },
                "generated-project": {
                  text: "Generated project"
                },
                "xcodeproj-integration": {
                  text: "XcodeProj-based integration"
                },
                "swift-package": {
                  text: "Swift package"
                },
                "continuous-integration": {
                  text: "Continuous integration"
                }
              }
            },
            "selective-testing": {
              text: "Selective testing",
              items: {
                "selective-testing": {
                  text: "Selective testing"
                },
                "xcode-project": {
                  text: "Xcode project"
                },
                "generated-project": {
                  text: "Generated project"
                }
              }
            },
            insights: {
              text: "Insights"
            },
            "bundle-size": {
              text: "Bundle size"
            }
          }
        },
        integrations: {
          text: "Integrations",
          items: {
            mcp: {
              text: "Model Context Protocol (MCP)"
            },
            "continuous-integration": {
              text: "Continuous integration"
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
        cli: {
          items: {
            logging: {
              text: "\u30ED\u30AE\u30F3\u30B0"
            },
            "shell-completions": {
              text: "Shell completions"
            }
          }
        },
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
        },
        cli: {
          text: "CLI",
          items: {
            logging: {
              text: "\u30ED\u30AE\u30F3\u30B0"
            }
          }
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
        tuist: {
          text: "Tuist",
          items: {
            about: {
              text: "Tuist \u306B\u3064\u3044\u3066"
            }
          }
        },
        "quick-start": {
          text: "\u30AF\u30A4\u30C3\u30AF\u30B9\u30BF\u30FC\u30C8",
          items: {
            "install-tuist": {
              text: "Tuist\u306E\u30A4\u30F3\u30B9\u30C8\u30FC\u30EB"
            },
            "get-started": {
              text: "\u306F\u3058\u3081\u306B"
            }
          }
        },
        features: {
          text: "\u6A5F\u80FD"
        },
        develop: {
          text: "\u958B\u767A",
          items: {
            "generated-projects": {
              text: "\u30D7\u30ED\u30B8\u30A7\u30AF\u30C8",
              items: {
                adoption: {
                  text: "\u5C0E\u5165",
                  items: {
                    "new-project": {
                      text: "\u65B0\u898F\u30D7\u30ED\u30B8\u30A7\u30AF\u30C8\u306E\u4F5C\u6210"
                    },
                    "swift-package": {
                      text: "Swift \u30D1\u30C3\u30B1\u30FC\u30B8\u3068\u4F7F\u7528\u3059\u308B"
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
                inspect: {
                  text: "\u691C\u67FB",
                  items: {
                    "implicit-imports": {
                      text: "\u6697\u9ED9\u306E\u30A4\u30F3\u30DD\u30FC\u30C8"
                    }
                  }
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
            cache: {
              text: "\u30AD\u30E3\u30C3\u30B7\u30E5"
            },
            registry: {
              text: "\u30EC\u30B8\u30B9\u30C8\u30EA",
              items: {
                registry: {
                  text: "\u30EC\u30B8\u30B9\u30C8\u30EA"
                },
                "xcode-project": {
                  text: "Xcode \u30D7\u30ED\u30B8\u30A7\u30AF\u30C8"
                },
                "generated-project": {
                  text: "\u751F\u6210\u3055\u308C\u305F\u30D7\u30ED\u30B8\u30A7\u30AF\u30C8"
                },
                "xcodeproj-integration": {
                  text: "XcodeProj \u30D9\u30FC\u30B9\u306E\u7D71\u5408"
                },
                "swift-package": {
                  text: "Swift \u30D1\u30C3\u30B1\u30FC\u30B8"
                },
                "continuous-integration": {
                  text: "\u7D99\u7D9A\u7684\u30A4\u30F3\u30C6\u30B0\u30EC\u30FC\u30B7\u30E7\u30F3"
                }
              }
            },
            "selective-testing": {
              text: "\u9078\u629E\u7684\u30C6\u30B9\u30C8",
              items: {
                "selective-testing": {
                  text: "\u9078\u629E\u7684\u30C6\u30B9\u30C8"
                },
                "xcode-project": {
                  text: "Xcode project"
                },
                "generated-project": {
                  text: "\u751F\u6210\u3055\u308C\u305F\u30D7\u30ED\u30B8\u30A7\u30AF\u30C8"
                }
              }
            },
            insights: {
              text: "Insights"
            },
            "bundle-size": {
              text: "Bundle size"
            }
          }
        },
        integrations: {
          text: "Integrations",
          items: {
            mcp: {
              text: "\u30E2\u30C7\u30EB\u30B3\u30F3\u30C6\u30AD\u30B9\u30C8\u30D7\u30ED\u30C8\u30B3\u30EB(MCP)"
            },
            "continuous-integration": {
              text: "\u7D99\u7D9A\u7684\u30A4\u30F3\u30C6\u30B0\u30EC\u30FC\u30B7\u30E7\u30F3"
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
        cli: {
          items: {
            logging: {
              text: "Logging"
            },
            "shell-completions": {
              text: "Shell completions"
            }
          }
        },
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
        },
        cli: {
          text: "CLI",
          items: {
            logging: {
              text: "Logging"
            }
          }
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
        tuist: {
          text: "Tuist",
          items: {
            about: {
              text: "About Tuist"
            }
          }
        },
        "quick-start": {
          text: "Quick Start",
          items: {
            "install-tuist": {
              text: "Instala Tuist"
            },
            "get-started": {
              text: "Get started"
            }
          }
        },
        features: {
          text: "Caracter\xEDsticas"
        },
        develop: {
          text: "Desarrolla",
          items: {
            "generated-projects": {
              text: "Proyectos generados",
              items: {
                adoption: {
                  text: "Adoption",
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
                inspect: {
                  text: "Inspect",
                  items: {
                    "implicit-imports": {
                      text: "Implicit imports"
                    }
                  }
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
            cache: {
              text: "Cache"
            },
            registry: {
              text: "Registry",
              items: {
                registry: {
                  text: "Registry"
                },
                "xcode-project": {
                  text: "Xcode project"
                },
                "generated-project": {
                  text: "Generated project"
                },
                "xcodeproj-integration": {
                  text: "XcodeProj-based integration"
                },
                "swift-package": {
                  text: "Swift package"
                },
                "continuous-integration": {
                  text: "Continuous integration"
                }
              }
            },
            "selective-testing": {
              text: "Selective testing",
              items: {
                "selective-testing": {
                  text: "Selective testing"
                },
                "xcode-project": {
                  text: "Xcode project"
                },
                "generated-project": {
                  text: "Generated project"
                }
              }
            },
            insights: {
              text: "Insights"
            },
            "bundle-size": {
              text: "Bundle size"
            }
          }
        },
        integrations: {
          text: "Integrations",
          items: {
            mcp: {
              text: "Model Context Protocol (MCP)"
            },
            "continuous-integration": {
              text: "Continuous integration"
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
        cli: {
          items: {
            logging: {
              text: "Logging"
            },
            "shell-completions": {
              text: "Shell completions"
            }
          }
        },
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
        },
        cli: {
          text: "CLI",
          items: {
            logging: {
              text: "Logging"
            }
          }
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
        tuist: {
          text: "Tuist",
          items: {
            about: {
              text: "About Tuist"
            }
          }
        },
        "quick-start": {
          text: "Quick start",
          items: {
            "install-tuist": {
              text: "Install Tuist"
            },
            "get-started": {
              text: "Get started"
            }
          }
        },
        features: {
          text: "Recursos"
        },
        develop: {
          text: "Develop",
          items: {
            "generated-projects": {
              text: "Generated projects",
              items: {
                adoption: {
                  text: "Adoption",
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
                inspect: {
                  text: "Inspect",
                  items: {
                    "implicit-imports": {
                      text: "Implicit imports"
                    }
                  }
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
            cache: {
              text: "Cache"
            },
            registry: {
              text: "Registry",
              items: {
                registry: {
                  text: "Registry"
                },
                "xcode-project": {
                  text: "Xcode project"
                },
                "generated-project": {
                  text: "Generated project"
                },
                "xcodeproj-integration": {
                  text: "XcodeProj-based integration"
                },
                "swift-package": {
                  text: "Swift package"
                },
                "continuous-integration": {
                  text: "Continuous integration"
                }
              }
            },
            "selective-testing": {
              text: "Selective testing",
              items: {
                "selective-testing": {
                  text: "Selective testing"
                },
                "xcode-project": {
                  text: "Xcode project"
                },
                "generated-project": {
                  text: "Generated project"
                }
              }
            },
            insights: {
              text: "Insights"
            },
            "bundle-size": {
              text: "Bundle size"
            }
          }
        },
        integrations: {
          text: "Integrations",
          items: {
            mcp: {
              text: "Model Context Protocol (MCP)"
            },
            "continuous-integration": {
              text: "Continuous integration"
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
      link: `/${locale}/guides/tuist/about`
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
        },
        {
          text: localizedString(locale, "sidebars.contributors.items.cli.text"),
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.contributors.items.cli.items.logging.text"
              ),
              link: `/${locale}/contributors/cli/logging`
            }
          ]
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
      text: "Tuist",
      link: `/${locale}/`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.tuist.items.about.text"
          ),
          link: `/${locale}/guides/tuist/about`
        }
      ]
    },
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
            "sidebars.guides.items.quick-start.items.get-started.text"
          ),
          link: `/${locale}/guides/quick-start/get-started`
        }
      ]
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.guides.items.features.text"
      )} ${cube02Icon()}</span>`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.generated-projects.text"
          ),
          collapsed: true,
          link: `/${locale}/guides/features/projects`,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.adoption.text"
              ),
              collapsed: true,
              items: [
                {
                  text: localizedString(
                    locale,
                    "sidebars.guides.items.develop.items.generated-projects.items.adoption.items.new-project.text"
                  ),
                  link: `/${locale}/guides/features/projects/adoption/new-project`
                },
                {
                  text: localizedString(
                    locale,
                    "sidebars.guides.items.develop.items.generated-projects.items.adoption.items.swift-package.text"
                  ),
                  link: `/${locale}/guides/features/projects/adoption/swift-package`
                },
                {
                  text: localizedString(
                    locale,
                    "sidebars.guides.items.develop.items.generated-projects.items.adoption.items.migrate.text"
                  ),
                  collapsed: true,
                  items: [
                    {
                      text: localizedString(
                        locale,
                        "sidebars.guides.items.develop.items.generated-projects.items.adoption.items.migrate.items.xcode-project.text"
                      ),
                      link: `/${locale}/guides/features/projects/adoption/migrate/xcode-project`
                    },
                    {
                      text: localizedString(
                        locale,
                        "sidebars.guides.items.develop.items.generated-projects.items.adoption.items.migrate.items.swift-package.text"
                      ),
                      link: `/${locale}/guides/features/projects/adoption/migrate/swift-package`
                    },
                    {
                      text: localizedString(
                        locale,
                        "sidebars.guides.items.develop.items.generated-projects.items.adoption.items.migrate.items.xcodegen-project.text"
                      ),
                      link: `/${locale}/guides/features/projects/adoption/migrate/xcodegen-project`
                    },
                    {
                      text: localizedString(
                        locale,
                        "sidebars.guides.items.develop.items.generated-projects.items.adoption.items.migrate.items.bazel-project.text"
                      ),
                      link: `/${locale}/guides/features/projects/adoption/migrate/bazel-project`
                    }
                  ]
                }
              ]
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.manifests.text"
              ),
              link: `/${locale}/guides/features/projects/manifests`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.directory-structure.text"
              ),
              link: `/${locale}/guides/features/projects/directory-structure`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.editing.text"
              ),
              link: `/${locale}/guides/features/projects/editing`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.dependencies.text"
              ),
              link: `/${locale}/guides/features/projects/dependencies`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.code-sharing.text"
              ),
              link: `/${locale}/guides/features/projects/code-sharing`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.synthesized-files.text"
              ),
              link: `/${locale}/guides/features/projects/synthesized-files`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.dynamic-configuration.text"
              ),
              link: `/${locale}/guides/features/projects/dynamic-configuration`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.templates.text"
              ),
              link: `/${locale}/guides/features/projects/templates`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.plugins.text"
              ),
              link: `/${locale}/guides/features/projects/plugins`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.hashing.text"
              ),
              link: `/${locale}/guides/features/projects/hashing`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.inspect.text"
              ),
              collapsed: true,
              items: [
                {
                  text: localizedString(
                    locale,
                    "sidebars.guides.items.develop.items.generated-projects.items.inspect.items.implicit-imports.text"
                  ),
                  link: `/${locale}/guides/features/projects/inspect/implicit-dependencies`
                }
              ]
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.the-cost-of-convenience.text"
              ),
              link: `/${locale}/guides/features/projects/cost-of-convenience`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.tma-architecture.text"
              ),
              link: `/${locale}/guides/features/projects/tma-architecture`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.best-practices.text"
              ),
              link: `/${locale}/guides/features/projects/best-practices`
            }
          ]
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.cache.text"
          ),
          link: `/${locale}/guides/features/cache`
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.selective-testing.text"
          ),
          link: `/${locale}/guides/features/selective-testing`,
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.selective-testing.items.xcode-project.text"
              ),
              link: `/${locale}/guides/features/selective-testing/xcode-project`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.selective-testing.items.generated-project.text"
              ),
              link: `/${locale}/guides/features/selective-testing/generated-project`
            }
          ]
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.registry.text"
          ),
          link: `/${locale}/guides/features/registry`,
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.registry.items.xcode-project.text"
              ),
              link: `/${locale}/guides/features/registry/xcode-project`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.registry.items.generated-project.text"
              ),
              link: `/${locale}/guides/features/registry/generated-project`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.registry.items.xcodeproj-integration.text"
              ),
              link: `/${locale}/guides/features/registry/xcodeproj-integration`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.registry.items.swift-package.text"
              ),
              link: `/${locale}/guides/features/registry/swift-package`
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.registry.items.continuous-integration.text"
              ),
              link: `/${locale}/guides/features/registry/continuous-integration`
            }
          ]
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.insights.text"
          ),
          link: `/${locale}/guides/features/insights`
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.bundle-size.text"
          ),
          link: `/${locale}/guides/features/bundle-size`
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.share.items.previews.text"
          ),
          link: `/${locale}/guides/features/previews`
        }
      ]
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.guides.items.integrations.text"
      )} ${playIcon()}</span>`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.integrations.items.mcp.text"
          ),
          link: `/${locale}/guides/integrations/mcp`
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.integrations.items.continuous-integration.text"
          ),
          link: `/${locale}/guides/integrations/continuous-integration`
        }
      ]
    }
  ];
}

// .vitepress/data/cli.js
import { execa, $ } from "file:///Users/pepicrft/src/github.com/tuist/tuist/node_modules/.pnpm/execa@9.6.0/node_modules/execa/index.js";
import { temporaryDirectoryTask } from "file:///Users/pepicrft/src/github.com/tuist/tuist/node_modules/.pnpm/tempy@3.1.0/node_modules/tempy/index.js";
import * as path3 from "node:path";
import { fileURLToPath } from "node:url";
import ejs from "file:///Users/pepicrft/src/github.com/tuist/tuist/node_modules/.pnpm/ejs@3.1.10/node_modules/ejs/lib/ejs.js";
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
async function cliSidebar(locale) {
  const sidebar = await loadData3(locale);
  return {
    ...sidebar,
    items: [
      {
        text: "CLI",
        items: [
          {
            text: localizedString(
              locale,
              "sidebars.cli.items.cli.items.logging.text"
            ),
            link: `/${locale}/cli/logging`
          },
          {
            text: localizedString(
              locale,
              "sidebars.cli.items.cli.items.shell-completions.text"
            ),
            link: `/${locale}/cli/shell-completions`
          }
        ]
      },
      ...sidebar.items
    ]
  };
}
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
        collapsed: true,
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
import llmstxtPlugin from "file:///Users/pepicrft/src/github.com/tuist/tuist/node_modules/.pnpm/vitepress-plugin-llmstxt@0.1.0_vitepress@1.6.3_@algolia+client-search@5.28.0_postcss@8.5.6_search-insights@2.17.3_/node_modules/vitepress-plugin-llmstxt/dist/main.mjs";
var __vite_injected_original_dirname3 = "/Users/pepicrft/src/github.com/tuist/tuist/docs/.vitepress";
async function themeConfig(locale) {
  const sidebar = {};
  sidebar[`/${locale}/contributors`] = contributorsSidebar(locale);
  sidebar[`/${locale}/guides/`] = guidesSidebar(locale);
  sidebar[`/${locale}/server/`] = serverSidebar(locale);
  sidebar[`/${locale}/cli/`] = await cliSidebar(locale);
  sidebar[`/${locale}/references/`] = await referencesSidebar(locale);
  sidebar[`/${locale}/`] = guidesSidebar(locale);
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
  vite: {
    plugins: [llmstxtPlugin()]
  },
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
      "meta",
      {
        "http-equiv": "Content-Security-Policy",
        content: "frame-src 'self' https://videos.tuist.dev"
      },
      ``
    ],
    [
      "style",
      {},
      `
      @import url('https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300..700&family=Space+Mono:ital,wght@0,400;0,700;1,400;1,700&display=swap');
      `
    ],
    [
      "style",
      {},
      `
      @import url('https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300..700&display=swap');
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
    ],
    [
      "script",
      {},
      `
      (function(d, script) {
        script = d.createElement('script');
        script.async = false;
        script.onload = function(){
          Plain.init({
            appId: 'liveChatApp_01JSH1T6AJCSB6QZ1VQ60YC2KM',
          });
        };
        script.src = 'https://chat.cdn-plain.com/index.js';
        d.getElementsByTagName('head')[0].appendChild(script);
      }(document));
      `
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
/:locale/guides/start/new-project /:locale/guides/develop/projects/adoption/new-project 301
/:locale/guides/start/swift-package /:locale/guides/develop/projects/adoption/swift-package 301
/:locale/guides/start/migrate/xcode-project /:locale/guides/develop/projects/adoption/migrate/xcode-project 301
/:locale/guides/start/migrate/swift-package /:locale/guides/develop/projects/adoption/migrate/swift-package 301
/:locale/guides/start/migrate/xcodegen-project /:locale/guides/develop/projects/adoption/migrate/xcodegen-project 301
/:locale/guides/start/migrate/bazel-project /:locale/guides/develop/projects/adoption/migrate/bazel-project 301
/:locale/guides/develop/build/cache /:locale/guides/develop/cache 301
/:locale/guides/develop/build/registry /:locale/guides/develop/registry 301
/:locale/guides/develop/test/selective-testing /:locale/guides/develop/selective-testing 301
/:locale/guides/develop/inspect/implicit-dependencies /:locale/guides/develop/projects/inspect/implicit-dependencies 301
/:locale/guides/develop/automate/continuous-integration /:locale/guides/environments/continuous-integration 301
/:locale/guides/develop/automate/workflows /:locale/guides/environments/automate/continuous-integration 301
/:locale/guides/automate/workflows /:locale/guides/environments/automate/continuous-integration 301
/:locale/guides/automate/* /:locale/guides/environments/:splat 301
/:locale/guides/develop/* /:locale/guides/features/:splat 301
/documentation/tuist/* / 301
/:locale/guides/develop/build/registry /:locale/guides/develop/registry 301
/:locale/guides/develop/selective-testing/xcodebuild /:locale/guides/develop/selective-testing/xcode-project 301
/:locale/guides/features/mcp /:locale/guides/integrations/mcp 301
/:locale/guides/environments/continuous-integration /:locale/guides/integrations/continuous-integration 301
/:locale/guides/environments/automate/continuous-integration /:locale/guides/integrations/continuous-integration 301
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
//# sourceMappingURL=data:application/json;base64,ewogICJ2ZXJzaW9uIjogMywKICAic291cmNlcyI6IFsiLnZpdGVwcmVzcy9jb25maWcubWpzIiwgIi52aXRlcHJlc3MvaWNvbnMubWpzIiwgIi52aXRlcHJlc3MvZGF0YS9leGFtcGxlcy5qcyIsICIudml0ZXByZXNzL2RhdGEvcHJvamVjdC1kZXNjcmlwdGlvbi5qcyIsICIudml0ZXByZXNzL3N0cmluZ3MvZW4uanNvbiIsICIudml0ZXByZXNzL3N0cmluZ3MvcnUuanNvbiIsICIudml0ZXByZXNzL3N0cmluZ3Mva28uanNvbiIsICIudml0ZXByZXNzL3N0cmluZ3MvamEuanNvbiIsICIudml0ZXByZXNzL3N0cmluZ3MvZXMuanNvbiIsICIudml0ZXByZXNzL3N0cmluZ3MvcHQuanNvbiIsICIudml0ZXByZXNzL2kxOG4ubWpzIiwgIi52aXRlcHJlc3MvYmFycy5tanMiLCAiLnZpdGVwcmVzcy9kYXRhL2NsaS5qcyJdLAogICJzb3VyY2VzQ29udGVudCI6IFsiY29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3NcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZmlsZW5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvY29uZmlnLm1qc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9pbXBvcnRfbWV0YV91cmwgPSBcImZpbGU6Ly8vVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2NvbmZpZy5tanNcIjtpbXBvcnQgeyBkZWZpbmVDb25maWcgfSBmcm9tIFwidml0ZXByZXNzXCI7XG5pbXBvcnQgKiBhcyBwYXRoIGZyb20gXCJub2RlOnBhdGhcIjtcbmltcG9ydCAqIGFzIGZzIGZyb20gXCJub2RlOmZzL3Byb21pc2VzXCI7XG5pbXBvcnQge1xuICBndWlkZXNTaWRlYmFyLFxuICBjb250cmlidXRvcnNTaWRlYmFyLFxuICByZWZlcmVuY2VzU2lkZWJhcixcbiAgc2VydmVyU2lkZWJhcixcbiAgbmF2QmFyLFxufSBmcm9tIFwiLi9iYXJzLm1qc1wiO1xuaW1wb3J0IHsgY2xpU2lkZWJhciB9IGZyb20gXCIuL2RhdGEvY2xpXCI7XG5pbXBvcnQgeyBsb2NhbGl6ZWRTdHJpbmcgfSBmcm9tIFwiLi9pMThuLm1qc1wiO1xuaW1wb3J0IGxsbXN0eHRQbHVnaW4gZnJvbSBcInZpdGVwcmVzcy1wbHVnaW4tbGxtc3R4dFwiO1xuXG5hc3luYyBmdW5jdGlvbiB0aGVtZUNvbmZpZyhsb2NhbGUpIHtcbiAgY29uc3Qgc2lkZWJhciA9IHt9O1xuICBzaWRlYmFyW2AvJHtsb2NhbGV9L2NvbnRyaWJ1dG9yc2BdID0gY29udHJpYnV0b3JzU2lkZWJhcihsb2NhbGUpO1xuICBzaWRlYmFyW2AvJHtsb2NhbGV9L2d1aWRlcy9gXSA9IGd1aWRlc1NpZGViYXIobG9jYWxlKTtcbiAgc2lkZWJhcltgLyR7bG9jYWxlfS9zZXJ2ZXIvYF0gPSBzZXJ2ZXJTaWRlYmFyKGxvY2FsZSk7XG4gIHNpZGViYXJbYC8ke2xvY2FsZX0vY2xpL2BdID0gYXdhaXQgY2xpU2lkZWJhcihsb2NhbGUpO1xuICBzaWRlYmFyW2AvJHtsb2NhbGV9L3JlZmVyZW5jZXMvYF0gPSBhd2FpdCByZWZlcmVuY2VzU2lkZWJhcihsb2NhbGUpO1xuICBzaWRlYmFyW2AvJHtsb2NhbGV9L2BdID0gZ3VpZGVzU2lkZWJhcihsb2NhbGUpO1xuICByZXR1cm4ge1xuICAgIG5hdjogbmF2QmFyKGxvY2FsZSksXG4gICAgc2lkZWJhcixcbiAgfTtcbn1cblxuZnVuY3Rpb24gZ2V0U2VhcmNoT3B0aW9uc0ZvckxvY2FsZShsb2NhbGUpIHtcbiAgcmV0dXJuIHtcbiAgICBwbGFjZWhvbGRlcjogbG9jYWxpemVkU3RyaW5nKGxvY2FsZSwgXCJzZWFyY2gucGxhY2Vob2xkZXJcIiksXG4gICAgdHJhbnNsYXRpb25zOiB7XG4gICAgICBidXR0b246IHtcbiAgICAgICAgYnV0dG9uVGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMuYnV0dG9uLmJ1dHRvblRleHRcIixcbiAgICAgICAgKSxcbiAgICAgICAgYnV0dG9uQXJpYUxhYmVsOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5idXR0b24uYnV0dG9uQXJpYUxhYmVsXCIsXG4gICAgICAgICksXG4gICAgICB9LFxuICAgICAgbW9kYWw6IHtcbiAgICAgICAgc2VhcmNoQm94OiB7XG4gICAgICAgICAgcmVzZXRCdXR0b25UaXRsZTogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLnNlYXJjaC1ib3gucmVzZXQtYnV0dG9uLXRpdGxlXCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICByZXNldEJ1dHRvbkFyaWFMYWJlbDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLnNlYXJjaC1ib3gucmVzZXQtYnV0dG9uLWFyaWEtbGFiZWxcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGNhbmNlbEJ1dHRvblRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5zZWFyY2gtYm94LmNhbmNlbC1idXR0b24tdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgY2FuY2VsQnV0dG9uQXJpYUxhYmVsOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc2VhcmNoLWJveC5jYW5jZWwtYnV0dG9uLWFyaWEtbGFiZWxcIixcbiAgICAgICAgICApLFxuICAgICAgICB9LFxuICAgICAgICBzdGFydFNjcmVlbjoge1xuICAgICAgICAgIHJlY2VudFNlYXJjaGVzVGl0bGU6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5zdGFydC1zY3JlZW4ucmVjZW50LXNlYXJjaGVzLXRpdGxlXCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBub1JlY2VudFNlYXJjaGVzVGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLnN0YXJ0LXNjcmVlbi5uby1yZWNlbnQtc2VhcmNoZXMtdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgc2F2ZVJlY2VudFNlYXJjaEJ1dHRvblRpdGxlOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc3RhcnQtc2NyZWVuLnNhdmUtcmVjZW50LXNlYXJjaC1idXR0b24tdGl0bGVcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIHJlbW92ZVJlY2VudFNlYXJjaEJ1dHRvblRpdGxlOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc3RhcnQtc2NyZWVuLnJlbW92ZS1yZWNlbnQtc2VhcmNoLWJ1dHRvbi10aXRsZVwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgZmF2b3JpdGVTZWFyY2hlc1RpdGxlOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc3RhcnQtc2NyZWVuLmZhdm9yaXRlLXNlYXJjaGVzLXRpdGxlXCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICByZW1vdmVGYXZvcml0ZVNlYXJjaEJ1dHRvblRpdGxlOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc3RhcnQtc2NyZWVuLnJlbW92ZS1mYXZvcml0ZS1zZWFyY2gtYnV0dG9uLXRpdGxlXCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgfSxcbiAgICAgICAgZXJyb3JTY3JlZW46IHtcbiAgICAgICAgICB0aXRsZVRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5lcnJvci1zY3JlZW4udGl0bGUtdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgaGVscFRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5lcnJvci1zY3JlZW4uaGVscC10ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgfSxcbiAgICAgICAgZm9vdGVyOiB7XG4gICAgICAgICAgc2VsZWN0VGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLmZvb3Rlci5zZWxlY3QtdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbmF2aWdhdGVUZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuZm9vdGVyLm5hdmlnYXRlLXRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGNsb3NlVGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLmZvb3Rlci5jbG9zZS10ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBzZWFyY2hCeVRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5mb290ZXIuc2VhcmNoLWJ5LXRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICB9LFxuICAgICAgICBub1Jlc3VsdHNTY3JlZW46IHtcbiAgICAgICAgICBub1Jlc3VsdHNUZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwubm8tcmVzdWx0cy1zY3JlZW4ubm8tcmVzdWx0cy10ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBzdWdnZXN0ZWRRdWVyeVRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5uby1yZXN1bHRzLXNjcmVlbi5zdWdnZXN0ZWQtcXVlcnktdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgcmVwb3J0TWlzc2luZ1Jlc3VsdHNUZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwubm8tcmVzdWx0cy1zY3JlZW4ucmVwb3J0LW1pc3NpbmctcmVzdWx0cy10ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICByZXBvcnRNaXNzaW5nUmVzdWx0c0xpbmtUZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwubm8tcmVzdWx0cy1zY3JlZW4ucmVwb3J0LW1pc3NpbmctcmVzdWx0cy1saW5rLXRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICB9LFxuICAgICAgfSxcbiAgICB9LFxuICB9O1xufVxuXG5jb25zdCBzZWFyY2hPcHRpb25zTG9jYWxlcyA9IHtcbiAgZW46IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJlblwiKSxcbiAga286IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJrb1wiKSxcbiAgamE6IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJqYVwiKSxcbiAgcnU6IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJydVwiKSxcbiAgZXM6IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJlc1wiKSxcbn07XG5cbmV4cG9ydCBkZWZhdWx0IGRlZmluZUNvbmZpZyh7XG4gIHRpdGxlOiBcIlR1aXN0XCIsXG4gIHRpdGxlVGVtcGxhdGU6IFwiOnRpdGxlIHwgVHVpc3RcIixcbiAgZGVzY3JpcHRpb246IFwiU2NhbGUgeW91ciBYY29kZSBhcHAgZGV2ZWxvcG1lbnRcIixcbiAgc3JjRGlyOiBcImRvY3NcIixcbiAgbGFzdFVwZGF0ZWQ6IGZhbHNlLFxuICB2aXRlOiB7XG4gICAgcGx1Z2luczogW2xsbXN0eHRQbHVnaW4oKV0sXG4gIH0sXG4gIGxvY2FsZXM6IHtcbiAgICBlbjoge1xuICAgICAgbGFiZWw6IFwiRW5nbGlzaFwiLFxuICAgICAgbGFuZzogXCJlblwiLFxuICAgICAgdGhlbWVDb25maWc6IGF3YWl0IHRoZW1lQ29uZmlnKFwiZW5cIiksXG4gICAgfSxcbiAgICBrbzoge1xuICAgICAgbGFiZWw6IFwiXHVENTVDXHVBRDZEXHVDNUI0IChLb3JlYW4pXCIsXG4gICAgICBsYW5nOiBcImtvXCIsXG4gICAgICB0aGVtZUNvbmZpZzogYXdhaXQgdGhlbWVDb25maWcoXCJrb1wiKSxcbiAgICB9LFxuICAgIGphOiB7XG4gICAgICBsYWJlbDogXCJcdTY1RTVcdTY3MkNcdThBOUUgKEphcGFuZXNlKVwiLFxuICAgICAgbGFuZzogXCJqYVwiLFxuICAgICAgdGhlbWVDb25maWc6IGF3YWl0IHRoZW1lQ29uZmlnKFwiamFcIiksXG4gICAgfSxcbiAgICBydToge1xuICAgICAgbGFiZWw6IFwiXHUwNDIwXHUwNDQzXHUwNDQxXHUwNDQxXHUwNDNBXHUwNDM4XHUwNDM5IChSdXNzaWFuKVwiLFxuICAgICAgbGFuZzogXCJydVwiLFxuICAgICAgdGhlbWVDb25maWc6IGF3YWl0IHRoZW1lQ29uZmlnKFwicnVcIiksXG4gICAgfSxcbiAgICBlczoge1xuICAgICAgbGFiZWw6IFwiQ2FzdGVsbGFubyAoU3BhbmlzaClcIixcbiAgICAgIGxhbmc6IFwiZXNcIixcbiAgICAgIHRoZW1lQ29uZmlnOiBhd2FpdCB0aGVtZUNvbmZpZyhcImVzXCIpLFxuICAgIH0sXG4gICAgcHQ6IHtcbiAgICAgIGxhYmVsOiBcIlBvcnR1Z3VcdTAwRUFzIChQb3J0dWd1ZXNlKVwiLFxuICAgICAgbGFuZzogXCJwdFwiLFxuICAgICAgdGhlbWVDb25maWc6IGF3YWl0IHRoZW1lQ29uZmlnKFwicHRcIiksXG4gICAgfSxcbiAgfSxcbiAgY2xlYW5VcmxzOiB0cnVlLFxuICBoZWFkOiBbXG4gICAgW1xuICAgICAgXCJtZXRhXCIsXG4gICAgICB7XG4gICAgICAgIFwiaHR0cC1lcXVpdlwiOiBcIkNvbnRlbnQtU2VjdXJpdHktUG9saWN5XCIsXG4gICAgICAgIGNvbnRlbnQ6IFwiZnJhbWUtc3JjICdzZWxmJyBodHRwczovL3ZpZGVvcy50dWlzdC5kZXZcIixcbiAgICAgIH0sXG4gICAgICBgYCxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwic3R5bGVcIixcbiAgICAgIHt9LFxuICAgICAgYFxuICAgICAgQGltcG9ydCB1cmwoJ2h0dHBzOi8vZm9udHMuZ29vZ2xlYXBpcy5jb20vY3NzMj9mYW1pbHk9U3BhY2UrR3JvdGVzazp3Z2h0QDMwMC4uNzAwJmZhbWlseT1TcGFjZStNb25vOml0YWwsd2dodEAwLDQwMDswLDcwMDsxLDQwMDsxLDcwMCZkaXNwbGF5PXN3YXAnKTtcbiAgICAgIGAsXG4gICAgXSxcbiAgICBbXG4gICAgICBcInN0eWxlXCIsXG4gICAgICB7fSxcbiAgICAgIGBcbiAgICAgIEBpbXBvcnQgdXJsKCdodHRwczovL2ZvbnRzLmdvb2dsZWFwaXMuY29tL2NzczI/ZmFtaWx5PVNwYWNlK0dyb3Rlc2s6d2dodEAzMDAuLjcwMCZkaXNwbGF5PXN3YXAnKTtcbiAgICAgIGAsXG4gICAgXSxcbiAgICBbXCJtZXRhXCIsIHsgcHJvcGVydHk6IFwib2c6dXJsXCIsIGNvbnRlbnQ6IFwiaHR0cHM6Ly9kb2NzLnR1aXN0LmlvXCIgfSwgXCJcIl0sXG4gICAgW1wibWV0YVwiLCB7IHByb3BlcnR5OiBcIm9nOnR5cGVcIiwgY29udGVudDogXCJ3ZWJzaXRlXCIgfSwgXCJcIl0sXG4gICAgW1xuICAgICAgXCJtZXRhXCIsXG4gICAgICB7IHByb3BlcnR5OiBcIm9nOmltYWdlXCIsIGNvbnRlbnQ6IFwiaHR0cHM6Ly9kb2NzLnR1aXN0LmlvL2ltYWdlcy9vZy5qcGVnXCIgfSxcbiAgICAgIFwiXCIsXG4gICAgXSxcbiAgICBbXCJtZXRhXCIsIHsgbmFtZTogXCJ0d2l0dGVyOmNhcmRcIiwgY29udGVudDogXCJzdW1tYXJ5XCIgfSwgXCJcIl0sXG4gICAgW1wibWV0YVwiLCB7IHByb3BlcnR5OiBcInR3aXR0ZXI6ZG9tYWluXCIsIGNvbnRlbnQ6IFwiZG9jcy50dWlzdC5pb1wiIH0sIFwiXCJdLFxuICAgIFtcIm1ldGFcIiwgeyBwcm9wZXJ0eTogXCJ0d2l0dGVyOnVybFwiLCBjb250ZW50OiBcImh0dHBzOi8vZG9jcy50dWlzdC5pb1wiIH0sIFwiXCJdLFxuICAgIFtcbiAgICAgIFwibWV0YVwiLFxuICAgICAge1xuICAgICAgICBuYW1lOiBcInR3aXR0ZXI6aW1hZ2VcIixcbiAgICAgICAgY29udGVudDogXCJodHRwczovL2RvY3MudHVpc3QuaW8vaW1hZ2VzL29nLmpwZWdcIixcbiAgICAgIH0sXG4gICAgICBcIlwiLFxuICAgIF0sXG4gICAgW1xuICAgICAgXCJzY3JpcHRcIixcbiAgICAgIHt9LFxuICAgICAgYFxuICAgICAgKGZ1bmN0aW9uKGQsIHNjcmlwdCkge1xuICAgICAgICBzY3JpcHQgPSBkLmNyZWF0ZUVsZW1lbnQoJ3NjcmlwdCcpO1xuICAgICAgICBzY3JpcHQuYXN5bmMgPSBmYWxzZTtcbiAgICAgICAgc2NyaXB0Lm9ubG9hZCA9IGZ1bmN0aW9uKCl7XG4gICAgICAgICAgUGxhaW4uaW5pdCh7XG4gICAgICAgICAgICBhcHBJZDogJ2xpdmVDaGF0QXBwXzAxSlNIMVQ2QUpDU0I2UVoxVlE2MFlDMktNJyxcbiAgICAgICAgICB9KTtcbiAgICAgICAgfTtcbiAgICAgICAgc2NyaXB0LnNyYyA9ICdodHRwczovL2NoYXQuY2RuLXBsYWluLmNvbS9pbmRleC5qcyc7XG4gICAgICAgIGQuZ2V0RWxlbWVudHNCeVRhZ05hbWUoJ2hlYWQnKVswXS5hcHBlbmRDaGlsZChzY3JpcHQpO1xuICAgICAgfShkb2N1bWVudCkpO1xuICAgICAgYCxcbiAgICBdLFxuICBdLFxuICBzaXRlbWFwOiB7XG4gICAgaG9zdG5hbWU6IFwiaHR0cHM6Ly9kb2NzLnR1aXN0LmlvXCIsXG4gIH0sXG4gIGFzeW5jIGJ1aWxkRW5kKHsgb3V0RGlyIH0pIHtcbiAgICBjb25zdCByZWRpcmVjdHNQYXRoID0gcGF0aC5qb2luKG91dERpciwgXCJfcmVkaXJlY3RzXCIpO1xuICAgIGNvbnN0IHJlZGlyZWN0cyA9IGBcbi9kb2N1bWVudGF0aW9uL3R1aXN0L2luc3RhbGxhdGlvbiAvZ3VpZGUvaW50cm9kdWN0aW9uL2luc3RhbGxhdGlvbiAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3Byb2plY3Qtc3RydWN0dXJlIC9ndWlkZS9wcm9qZWN0L2RpcmVjdG9yeS1zdHJ1Y3R1cmUgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9jb21tYW5kLWxpbmUtaW50ZXJmYWNlIC9ndWlkZS9hdXRvbWF0aW9uL2dlbmVyYXRlIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvZGVwZW5kZW5jaWVzIC9ndWlkZS9wcm9qZWN0L2RlcGVuZGVuY2llcyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3NoYXJpbmctY29kZS1hY3Jvc3MtbWFuaWZlc3RzIC9ndWlkZS9wcm9qZWN0L2NvZGUtc2hhcmluZyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3N5bnRoZXNpemVkLWZpbGVzIC9ndWlkZS9wcm9qZWN0L3N5bnRoZXNpemVkLWZpbGVzIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvbWlncmF0aW9uLWd1aWRlbGluZXMgL2d1aWRlL2ludHJvZHVjdGlvbi9hZG9wdGluZy10dWlzdC9taWdyYXRlLWZyb20teGNvZGVwcm9qIDMwMVxuL3R1dG9yaWFscy90dWlzdC10dXRvcmlhbHMgL2d1aWRlL2ludHJvZHVjdGlvbi9hZG9wdGluZy10dWlzdC9uZXctcHJvamVjdCAzMDFcbi90dXRvcmlhbHMvdHVpc3QvaW5zdGFsbCAgL2d1aWRlL2ludHJvZHVjdGlvbi9hZG9wdGluZy10dWlzdC9uZXctcHJvamVjdCAzMDFcbi90dXRvcmlhbHMvdHVpc3QvY3JlYXRlLXByb2plY3QgIC9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3QvbmV3LXByb2plY3QgMzAxXG4vdHV0b3JpYWxzL3R1aXN0L2V4dGVybmFsLWRlcGVuZGVuY2llcyAvZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L25ldy1wcm9qZWN0IDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvZ2VuZXJhdGlvbi1lbnZpcm9ubWVudCAvZ3VpZGUvcHJvamVjdC9keW5hbWljLWNvbmZpZ3VyYXRpb24gMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC91c2luZy1wbHVnaW5zIC9ndWlkZS9wcm9qZWN0L3BsdWdpbnMgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9jcmVhdGluZy1wbHVnaW5zIC9ndWlkZS9wcm9qZWN0L3BsdWdpbnMgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC90YXNrIC9ndWlkZS9wcm9qZWN0L3BsdWdpbnMgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC90dWlzdC1jbG91ZCAvY2xvdWQvd2hhdC1pcy1jbG91ZCAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3R1aXN0LWNsb3VkLWdldC1zdGFydGVkIC9jbG91ZC9nZXQtc3RhcnRlZCAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L2JpbmFyeS1jYWNoaW5nIC9jbG91ZC9iaW5hcnktY2FjaGluZyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3NlbGVjdGl2ZS10ZXN0aW5nIC9jbG91ZC9zZWxlY3RpdmUtdGVzdGluZyAzMDFcbi90dXRvcmlhbHMvdHVpc3QtY2xvdWQtdHV0b3JpYWxzIC9jbG91ZC9vbi1wcmVtaXNlIDMwMVxuL3R1dG9yaWFscy90dWlzdC9lbnRlcnByaXNlLWluZnJhc3RydWN0dXJlLXJlcXVpcmVtZW50cyAvY2xvdWQvb24tcHJlbWlzZSAzMDFcbi90dXRvcmlhbHMvdHVpc3QvZW50ZXJwcmlzZS1lbnZpcm9ubWVudCAvY2xvdWQvb24tcHJlbWlzZSAzMDFcbi90dXRvcmlhbHMvdHVpc3QvZW50ZXJwcmlzZS1kZXBsb3ltZW50IC9jbG91ZC9vbi1wcmVtaXNlIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvZ2V0LXN0YXJ0ZWQtYXMtY29udHJpYnV0b3IgL2NvbnRyaWJ1dG9ycy9nZXQtc3RhcnRlZCAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L21hbmlmZXN0byAvY29udHJpYnV0b3JzL3ByaW5jaXBsZXMgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9jb2RlLXJldmlld3MgL2NvbnRyaWJ1dG9ycy9jb2RlLXJldmlld3MgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9yZXBvcnRpbmctYnVncyAvY29udHJpYnV0b3JzL2lzc3VlLXJlcG9ydGluZyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L2NoYW1waW9uaW5nLXByb2plY3RzIC9jb250cmlidXRvcnMvZ2V0LXN0YXJ0ZWQgMzAxXG4vZ3VpZGUvc2NhbGUvdWZlYXR1cmVzLWFyY2hpdGVjdHVyZS5odG1sIC9ndWlkZS9zY2FsZS90bWEtYXJjaGl0ZWN0dXJlLmh0bWwgMzAxXG4vZ3VpZGUvc2NhbGUvdWZlYXR1cmVzLWFyY2hpdGVjdHVyZSAvZ3VpZGUvc2NhbGUvdG1hLWFyY2hpdGVjdHVyZSAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vY29zdC1vZi1jb252ZW5pZW5jZSAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvY29zdC1vZi1jb252ZW5pZW5jZSAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vaW5zdGFsbGF0aW9uIC9ndWlkZXMvcXVpY2stc3RhcnQvaW5zdGFsbC10dWlzdCAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3QvbmV3LXByb2plY3QgL2d1aWRlcy9zdGFydC9uZXctcHJvamVjdCAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3Qvc3dpZnQtcGFja2FnZSAvZ3VpZGVzL3N0YXJ0L3N3aWZ0LXBhY2thZ2UgMzAxXG4vZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L21pZ3JhdGUtZnJvbS14Y29kZXByb2ogL2d1aWRlcy9zdGFydC9taWdyYXRlL3hjb2RlLXByb2plY3QgMzAxXG4vZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L21pZ3JhdGUtbG9jYWwtc3dpZnQtcGFja2FnZXMgL2d1aWRlcy9zdGFydC9taWdyYXRlL3N3aWZ0LXBhY2thZ2UgMzAxXG4vZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L21pZ3JhdGUtZnJvbS14Y29kZWdlbiAvZ3VpZGVzL3N0YXJ0L21pZ3JhdGUveGNvZGVnZW4tcHJvamVjdCAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3QvbWlncmF0ZS1mcm9tLWJhemVsIC9ndWlkZXMvc3RhcnQvbWlncmF0ZS9iYXplbC1wcm9qZWN0IDMwMVxuL2d1aWRlL2ludHJvZHVjdGlvbi9mcm9tLXYzLXRvLXY0IC9yZWZlcmVuY2VzL21pZ3JhdGlvbnMvZnJvbS12My10by12NCAzMDFcbi9ndWlkZS9wcm9qZWN0L21hbmlmZXN0cyAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvbWFuaWZlc3RzIDMwMVxuL2d1aWRlL3Byb2plY3QvZGlyZWN0b3J5LXN0cnVjdHVyZSAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvZGlyZWN0b3J5LXN0cnVjdHVyZSAzMDFcbi9ndWlkZS9wcm9qZWN0L2VkaXRpbmcgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2VkaXRpbmcgMzAxXG4vZ3VpZGUvcHJvamVjdC9kZXBlbmRlbmNpZXMgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2RlcGVuZGVuY2llcyAzMDFcbi9ndWlkZS9wcm9qZWN0L2NvZGUtc2hhcmluZyAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvY29kZS1zaGFyaW5nIDMwMVxuL2d1aWRlL3Byb2plY3Qvc3ludGhlc2l6ZWQtZmlsZXMgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL3N5bnRoZXNpemVkLWZpbGVzIDMwMVxuL2d1aWRlL3Byb2plY3QvZHluYW1pYy1jb25maWd1cmF0aW9uIC9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9keW5hbWljLWNvbmZpZ3VyYXRpb24gMzAxXG4vZ3VpZGUvcHJvamVjdC90ZW1wbGF0ZXMgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL3RlbXBsYXRlcyAzMDFcbi9ndWlkZS9wcm9qZWN0L3BsdWdpbnMgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL3BsdWdpbnMgMzAxXG4vZ3VpZGUvYXV0b21hdGlvbi9nZW5lcmF0ZSAvIDMwMVxuL2d1aWRlL2F1dG9tYXRpb24vYnVpbGQgL2d1aWRlcy9kZXZlbG9wL2J1aWxkIDMwMVxuL2d1aWRlL2F1dG9tYXRpb24vdGVzdCAvZ3VpZGVzL2RldmVsb3AvdGVzdCAzMDFcbi9ndWlkZS9hdXRvbWF0aW9uL3J1biAvIDMwMVxuL2d1aWRlL2F1dG9tYXRpb24vZ3JhcGggLyAzMDFcbi9ndWlkZS9hdXRvbWF0aW9uL2NsZWFuIC8gMzAxXG4vZ3VpZGUvc2NhbGUvdG1hLWFyY2hpdGVjdHVyZSAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvdG1hLWFyY2hpdGVjdHVyZSAzMDFcbi9jbG91ZC93aGF0LWlzLWNsb3VkIC8gMzAxXG4vY2xvdWQvZ2V0LXN0YXJ0ZWQgLyAzMDFcbi9jbG91ZC9iaW5hcnktY2FjaGluZyAvZ3VpZGVzL2RldmVsb3AvYnVpbGQvY2FjaGUgMzAxXG4vY2xvdWQvc2VsZWN0aXZlLXRlc3RpbmcgL2d1aWRlcy9kZXZlbG9wL3Rlc3Qvc21hcnQtcnVubmVyIDMwMVxuL2Nsb3VkL2hhc2hpbmcgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2hhc2hpbmcgMzAxXG4vY2xvdWQvb24tcHJlbWlzZSAvZ3VpZGVzL2Rhc2hib2FyZC9vbi1wcmVtaXNlL2luc3RhbGwgMzAxXG4vY2xvdWQvb24tcHJlbWlzZS9tZXRyaWNzIC9ndWlkZXMvZGFzaGJvYXJkL29uLXByZW1pc2UvbWV0cmljcyAzMDFcbi9yZWZlcmVuY2UvcHJvamVjdC1kZXNjcmlwdGlvbi8qIC9yZWZlcmVuY2VzL3Byb2plY3QtZGVzY3JpcHRpb24vOnNwbGF0IDMwMVxuL3JlZmVyZW5jZS9leGFtcGxlcy8qIC9yZWZlcmVuY2VzL2V4YW1wbGVzLzpzcGxhdCAzMDFcbi9ndWlkZXMvZGV2ZWxvcC93b3JrZmxvd3MgL2d1aWRlcy9kZXZlbG9wL2NvbnRpbnVvdXMtaW50ZWdyYXRpb24vd29ya2Zsb3dzIDMwMVxuL2d1aWRlcy9kYXNoYm9hcmQvb24tcHJlbWlzZS9pbnN0YWxsIC9zZXJ2ZXIvb24tcHJlbWlzZS9pbnN0YWxsIDMwMVxuL2d1aWRlcy9kYXNoYm9hcmQvb24tcHJlbWlzZS9tZXRyaWNzIC9zZXJ2ZXIvb24tcHJlbWlzZS9tZXRyaWNzIDMwMVxuLzpsb2NhbGUvcmVmZXJlbmNlcy9wcm9qZWN0LWRlc2NyaXB0aW9uL3N0cnVjdHMvY29uZmlnIC86bG9jYWxlL3JlZmVyZW5jZXMvcHJvamVjdC1kZXNjcmlwdGlvbi9zdHJ1Y3RzL3R1aXN0ICAzMDFcbi86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL3Rlc3Qvc21hcnQtcnVubmVyIC86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL3Rlc3Qvc2VsZWN0aXZlLXRlc3RpbmcgMzAxXG4vOmxvY2FsZS9ndWlkZXMvc3RhcnQvbmV3LXByb2plY3QgLzpsb2NhbGUvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvYWRvcHRpb24vbmV3LXByb2plY3QgMzAxXG4vOmxvY2FsZS9ndWlkZXMvc3RhcnQvc3dpZnQtcGFja2FnZSAvOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9hZG9wdGlvbi9zd2lmdC1wYWNrYWdlIDMwMVxuLzpsb2NhbGUvZ3VpZGVzL3N0YXJ0L21pZ3JhdGUveGNvZGUtcHJvamVjdCAvOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9hZG9wdGlvbi9taWdyYXRlL3hjb2RlLXByb2plY3QgMzAxXG4vOmxvY2FsZS9ndWlkZXMvc3RhcnQvbWlncmF0ZS9zd2lmdC1wYWNrYWdlIC86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2Fkb3B0aW9uL21pZ3JhdGUvc3dpZnQtcGFja2FnZSAzMDFcbi86bG9jYWxlL2d1aWRlcy9zdGFydC9taWdyYXRlL3hjb2RlZ2VuLXByb2plY3QgLzpsb2NhbGUvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvYWRvcHRpb24vbWlncmF0ZS94Y29kZWdlbi1wcm9qZWN0IDMwMVxuLzpsb2NhbGUvZ3VpZGVzL3N0YXJ0L21pZ3JhdGUvYmF6ZWwtcHJvamVjdCAvOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9hZG9wdGlvbi9taWdyYXRlL2JhemVsLXByb2plY3QgMzAxXG4vOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9idWlsZC9jYWNoZSAvOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9jYWNoZSAzMDFcbi86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL2J1aWxkL3JlZ2lzdHJ5IC86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL3JlZ2lzdHJ5IDMwMVxuLzpsb2NhbGUvZ3VpZGVzL2RldmVsb3AvdGVzdC9zZWxlY3RpdmUtdGVzdGluZyAvOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9zZWxlY3RpdmUtdGVzdGluZyAzMDFcbi86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL2luc3BlY3QvaW1wbGljaXQtZGVwZW5kZW5jaWVzIC86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2luc3BlY3QvaW1wbGljaXQtZGVwZW5kZW5jaWVzIDMwMVxuLzpsb2NhbGUvZ3VpZGVzL2RldmVsb3AvYXV0b21hdGUvY29udGludW91cy1pbnRlZ3JhdGlvbiAvOmxvY2FsZS9ndWlkZXMvZW52aXJvbm1lbnRzL2NvbnRpbnVvdXMtaW50ZWdyYXRpb24gMzAxXG4vOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9hdXRvbWF0ZS93b3JrZmxvd3MgLzpsb2NhbGUvZ3VpZGVzL2Vudmlyb25tZW50cy9hdXRvbWF0ZS9jb250aW51b3VzLWludGVncmF0aW9uIDMwMVxuLzpsb2NhbGUvZ3VpZGVzL2F1dG9tYXRlL3dvcmtmbG93cyAvOmxvY2FsZS9ndWlkZXMvZW52aXJvbm1lbnRzL2F1dG9tYXRlL2NvbnRpbnVvdXMtaW50ZWdyYXRpb24gMzAxXG4vOmxvY2FsZS9ndWlkZXMvYXV0b21hdGUvKiAvOmxvY2FsZS9ndWlkZXMvZW52aXJvbm1lbnRzLzpzcGxhdCAzMDFcbi86bG9jYWxlL2d1aWRlcy9kZXZlbG9wLyogLzpsb2NhbGUvZ3VpZGVzL2ZlYXR1cmVzLzpzcGxhdCAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0LyogLyAzMDFcbi86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL2J1aWxkL3JlZ2lzdHJ5IC86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL3JlZ2lzdHJ5IDMwMVxuLzpsb2NhbGUvZ3VpZGVzL2RldmVsb3Avc2VsZWN0aXZlLXRlc3RpbmcveGNvZGVidWlsZCAvOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9zZWxlY3RpdmUtdGVzdGluZy94Y29kZS1wcm9qZWN0IDMwMVxuLzpsb2NhbGUvZ3VpZGVzL2ZlYXR1cmVzL21jcCAvOmxvY2FsZS9ndWlkZXMvaW50ZWdyYXRpb25zL21jcCAzMDFcbi86bG9jYWxlL2d1aWRlcy9lbnZpcm9ubWVudHMvY29udGludW91cy1pbnRlZ3JhdGlvbiAvOmxvY2FsZS9ndWlkZXMvaW50ZWdyYXRpb25zL2NvbnRpbnVvdXMtaW50ZWdyYXRpb24gMzAxXG4vOmxvY2FsZS9ndWlkZXMvZW52aXJvbm1lbnRzL2F1dG9tYXRlL2NvbnRpbnVvdXMtaW50ZWdyYXRpb24gLzpsb2NhbGUvZ3VpZGVzL2ludGVncmF0aW9ucy9jb250aW51b3VzLWludGVncmF0aW9uIDMwMVxuJHthd2FpdCBmcy5yZWFkRmlsZShwYXRoLmpvaW4oaW1wb3J0Lm1ldGEuZGlybmFtZSwgXCJsb2NhbGUtcmVkaXJlY3RzLnR4dFwiKSwge1xuICBlbmNvZGluZzogXCJ1dGYtOFwiLFxufSl9XG4gICAgYDtcbiAgICBmcy53cml0ZUZpbGUocmVkaXJlY3RzUGF0aCwgcmVkaXJlY3RzKTtcbiAgfSxcbiAgdGhlbWVDb25maWc6IHtcbiAgICBsb2dvOiBcIi9sb2dvLnBuZ1wiLFxuICAgIHNlYXJjaDoge1xuICAgICAgcHJvdmlkZXI6IFwiYWxnb2xpYVwiLFxuICAgICAgb3B0aW9uczoge1xuICAgICAgICBhcHBJZDogXCI1QTNMOUhJOVZRXCIsXG4gICAgICAgIGFwaUtleTogXCJjZDQ1ZjUxNWZiMWZiYjcyMGQ2MzNjYjBmMTI1N2U3YVwiLFxuICAgICAgICBpbmRleE5hbWU6IFwidHVpc3RcIixcbiAgICAgICAgbG9jYWxlczogc2VhcmNoT3B0aW9uc0xvY2FsZXMsXG4gICAgICAgIHN0YXJ0VXJsczogW1wiaHR0cHM6Ly90dWlzdC5kZXYvXCJdLFxuICAgICAgICByZW5kZXJKYXZhU2NyaXB0OiBmYWxzZSxcbiAgICAgICAgc2l0ZW1hcHM6IFtdLFxuICAgICAgICBleGNsdXNpb25QYXR0ZXJuczogW10sXG4gICAgICAgIGlnbm9yZUNhbm9uaWNhbFRvOiBmYWxzZSxcbiAgICAgICAgZGlzY292ZXJ5UGF0dGVybnM6IFtcImh0dHBzOi8vdHVpc3QuZGV2LyoqXCJdLFxuICAgICAgICBzY2hlZHVsZTogXCJhdCAwNToxMCBvbiBTYXR1cmRheVwiLFxuICAgICAgICBhY3Rpb25zOiBbXG4gICAgICAgICAge1xuICAgICAgICAgICAgaW5kZXhOYW1lOiBcInR1aXN0XCIsXG4gICAgICAgICAgICBwYXRoc1RvTWF0Y2g6IFtcImh0dHBzOi8vdHVpc3QuZGV2LyoqXCJdLFxuICAgICAgICAgICAgcmVjb3JkRXh0cmFjdG9yOiAoeyAkLCBoZWxwZXJzIH0pID0+IHtcbiAgICAgICAgICAgICAgcmV0dXJuIGhlbHBlcnMuZG9jc2VhcmNoKHtcbiAgICAgICAgICAgICAgICByZWNvcmRQcm9wczoge1xuICAgICAgICAgICAgICAgICAgbHZsMTogXCIuY29udGVudCBoMVwiLFxuICAgICAgICAgICAgICAgICAgY29udGVudDogXCIuY29udGVudCBwLCAuY29udGVudCBsaVwiLFxuICAgICAgICAgICAgICAgICAgbHZsMDoge1xuICAgICAgICAgICAgICAgICAgICBzZWxlY3RvcnM6IFwic2VjdGlvbi5oYXMtYWN0aXZlIGRpdiBoMlwiLFxuICAgICAgICAgICAgICAgICAgICBkZWZhdWx0VmFsdWU6IFwiRG9jdW1lbnRhdGlvblwiLFxuICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgIGx2bDI6IFwiLmNvbnRlbnQgaDJcIixcbiAgICAgICAgICAgICAgICAgIGx2bDM6IFwiLmNvbnRlbnQgaDNcIixcbiAgICAgICAgICAgICAgICAgIGx2bDQ6IFwiLmNvbnRlbnQgaDRcIixcbiAgICAgICAgICAgICAgICAgIGx2bDU6IFwiLmNvbnRlbnQgaDVcIixcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIGluZGV4SGVhZGluZ3M6IHRydWUsXG4gICAgICAgICAgICAgIH0pO1xuICAgICAgICAgICAgfSxcbiAgICAgICAgICB9LFxuICAgICAgICBdLFxuICAgICAgICBpbml0aWFsSW5kZXhTZXR0aW5nczoge1xuICAgICAgICAgIHZpdGVwcmVzczoge1xuICAgICAgICAgICAgYXR0cmlidXRlc0ZvckZhY2V0aW5nOiBbXCJ0eXBlXCIsIFwibGFuZ1wiXSxcbiAgICAgICAgICAgIGF0dHJpYnV0ZXNUb1JldHJpZXZlOiBbXCJoaWVyYXJjaHlcIiwgXCJjb250ZW50XCIsIFwiYW5jaG9yXCIsIFwidXJsXCJdLFxuICAgICAgICAgICAgYXR0cmlidXRlc1RvSGlnaGxpZ2h0OiBbXCJoaWVyYXJjaHlcIiwgXCJoaWVyYXJjaHlfY2FtZWxcIiwgXCJjb250ZW50XCJdLFxuICAgICAgICAgICAgYXR0cmlidXRlc1RvU25pcHBldDogW1wiY29udGVudDoxMFwiXSxcbiAgICAgICAgICAgIGNhbWVsQ2FzZUF0dHJpYnV0ZXM6IFtcImhpZXJhcmNoeVwiLCBcImhpZXJhcmNoeV9yYWRpb1wiLCBcImNvbnRlbnRcIl0sXG4gICAgICAgICAgICBzZWFyY2hhYmxlQXR0cmlidXRlczogW1xuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW9fY2FtZWwubHZsMClcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X3JhZGlvLmx2bDApXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9yYWRpb19jYW1lbC5sdmwxKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW8ubHZsMSlcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X3JhZGlvX2NhbWVsLmx2bDIpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9yYWRpby5sdmwyKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW9fY2FtZWwubHZsMylcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X3JhZGlvLmx2bDMpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9yYWRpb19jYW1lbC5sdmw0KVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW8ubHZsNClcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X3JhZGlvX2NhbWVsLmx2bDUpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9yYWRpby5sdmw1KVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW9fY2FtZWwubHZsNilcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X3JhZGlvLmx2bDYpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9jYW1lbC5sdmwwKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHkubHZsMClcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X2NhbWVsLmx2bDEpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeS5sdmwxKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfY2FtZWwubHZsMilcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5Lmx2bDIpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9jYW1lbC5sdmwzKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHkubHZsMylcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X2NhbWVsLmx2bDQpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeS5sdmw0KVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfY2FtZWwubHZsNSlcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5Lmx2bDUpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9jYW1lbC5sdmw2KVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHkubHZsNilcIixcbiAgICAgICAgICAgICAgXCJjb250ZW50XCIsXG4gICAgICAgICAgICBdLFxuICAgICAgICAgICAgZGlzdGluY3Q6IHRydWUsXG4gICAgICAgICAgICBhdHRyaWJ1dGVGb3JEaXN0aW5jdDogXCJ1cmxcIixcbiAgICAgICAgICAgIGN1c3RvbVJhbmtpbmc6IFtcbiAgICAgICAgICAgICAgXCJkZXNjKHdlaWdodC5wYWdlUmFuaylcIixcbiAgICAgICAgICAgICAgXCJkZXNjKHdlaWdodC5sZXZlbClcIixcbiAgICAgICAgICAgICAgXCJhc2Mod2VpZ2h0LnBvc2l0aW9uKVwiLFxuICAgICAgICAgICAgXSxcbiAgICAgICAgICAgIHJhbmtpbmc6IFtcbiAgICAgICAgICAgICAgXCJ3b3Jkc1wiLFxuICAgICAgICAgICAgICBcImZpbHRlcnNcIixcbiAgICAgICAgICAgICAgXCJ0eXBvXCIsXG4gICAgICAgICAgICAgIFwiYXR0cmlidXRlXCIsXG4gICAgICAgICAgICAgIFwicHJveGltaXR5XCIsXG4gICAgICAgICAgICAgIFwiZXhhY3RcIixcbiAgICAgICAgICAgICAgXCJjdXN0b21cIixcbiAgICAgICAgICAgIF0sXG4gICAgICAgICAgICBoaWdobGlnaHRQcmVUYWc6XG4gICAgICAgICAgICAgICc8c3BhbiBjbGFzcz1cImFsZ29saWEtZG9jc2VhcmNoLXN1Z2dlc3Rpb24tLWhpZ2hsaWdodFwiPicsXG4gICAgICAgICAgICBoaWdobGlnaHRQb3N0VGFnOiBcIjwvc3Bhbj5cIixcbiAgICAgICAgICAgIG1pbldvcmRTaXplZm9yMVR5cG86IDMsXG4gICAgICAgICAgICBtaW5Xb3JkU2l6ZWZvcjJUeXBvczogNyxcbiAgICAgICAgICAgIGFsbG93VHlwb3NPbk51bWVyaWNUb2tlbnM6IGZhbHNlLFxuICAgICAgICAgICAgbWluUHJveGltaXR5OiAxLFxuICAgICAgICAgICAgaWdub3JlUGx1cmFsczogdHJ1ZSxcbiAgICAgICAgICAgIGFkdmFuY2VkU3ludGF4OiB0cnVlLFxuICAgICAgICAgICAgYXR0cmlidXRlQ3JpdGVyaWFDb21wdXRlZEJ5TWluUHJveGltaXR5OiB0cnVlLFxuICAgICAgICAgICAgcmVtb3ZlV29yZHNJZk5vUmVzdWx0czogXCJhbGxPcHRpb25hbFwiLFxuICAgICAgICAgIH0sXG4gICAgICAgIH0sXG4gICAgICB9LFxuICAgIH0sXG4gICAgZWRpdExpbms6IHtcbiAgICAgIHBhdHRlcm46IFwiaHR0cHM6Ly9naXRodWIuY29tL3R1aXN0L3R1aXN0L2VkaXQvbWFpbi9kb2NzL2RvY3MvOnBhdGhcIixcbiAgICB9LFxuICAgIHNvY2lhbExpbmtzOiBbXG4gICAgICB7IGljb246IFwiZ2l0aHViXCIsIGxpbms6IFwiaHR0cHM6Ly9naXRodWIuY29tL3R1aXN0L3R1aXN0XCIgfSxcbiAgICAgIHsgaWNvbjogXCJtYXN0b2RvblwiLCBsaW5rOiBcImh0dHBzOi8vZm9zc3RvZG9uLm9yZy9AdHVpc3RcIiB9LFxuICAgICAgeyBpY29uOiBcImJsdWVza3lcIiwgbGluazogXCJodHRwczovL2Jza3kuYXBwL3Byb2ZpbGUvdHVpc3QuZGV2XCIgfSxcbiAgICAgIHtcbiAgICAgICAgaWNvbjogXCJzbGFja1wiLFxuICAgICAgICBsaW5rOiBcImh0dHBzOi8vam9pbi5zbGFjay5jb20vdC90dWlzdGFwcC9zaGFyZWRfaW52aXRlL3p0LTF5NjY3bWpiay1zMkxUUlgxWUJ5YjlFSUlUamRMY0x3XCIsXG4gICAgICB9LFxuICAgIF0sXG4gICAgZm9vdGVyOiB7XG4gICAgICBtZXNzYWdlOiBcIlJlbGVhc2VkIHVuZGVyIHRoZSBNSVQgTGljZW5zZS5cIixcbiAgICAgIGNvcHlyaWdodDogXCJDb3B5cmlnaHQgXHUwMEE5IDIwMjQtcHJlc2VudCBUdWlzdCBHbWJIXCIsXG4gICAgfSxcbiAgfSxcbn0pO1xuIiwgImNvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ZpbGVuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2ljb25zLm1qc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9pbXBvcnRfbWV0YV91cmwgPSBcImZpbGU6Ly8vVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2ljb25zLm1qc1wiO2V4cG9ydCBmdW5jdGlvbiBwbGF5SWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG4gIDxwYXRoIGQ9XCJNNSA0Ljk4OTYzQzUgNC4wMTg0NyA1IDMuNTMyODkgNS4yMDI0OSAzLjI2NTIyQzUuMzc4ODkgMy4wMzIwMyA1LjY0ODUyIDIuODg3NzMgNS45NDA0IDIuODcwM0M2LjI3NTQ0IDIuODUwMyA2LjY3OTQ2IDMuMTE5NjUgNy40ODc1MiAzLjY1ODM1TDE4LjAwMzEgMTAuNjY4N0MxOC42NzA4IDExLjExMzkgMTkuMDA0NiAxMS4zMzY0IDE5LjEyMDkgMTEuNjE2OUMxOS4yMjI3IDExLjg2MjIgMTkuMjIyNyAxMi4xMzc4IDE5LjEyMDkgMTIuMzgzMUMxOS4wMDQ2IDEyLjY2MzYgMTguNjcwOCAxMi44ODYyIDE4LjAwMzEgMTMuMzMxM0w3LjQ4NzUyIDIwLjM0MTdDNi42Nzk0NiAyMC44ODA0IDYuMjc1NDQgMjEuMTQ5NyA1Ljk0MDQgMjEuMTI5N0M1LjY0ODUyIDIxLjExMjMgNS4zNzg4OSAyMC45NjggNS4yMDI0OSAyMC43MzQ4QzUgMjAuNDY3MSA1IDE5Ljk4MTUgNSAxOS4wMTA0VjQuOTg5NjNaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbiAgPC9zdmc+XG5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY3ViZU91dGxpbmVJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNOS43NSAyMC43NTAxTDExLjIyMyAyMS41Njg0QzExLjUwNjYgMjEuNzI2IDExLjY0ODQgMjEuODA0NyAxMS43OTg2IDIxLjgzNTZDMTEuOTMxNSAyMS44NjMgMTIuMDY4NSAyMS44NjMgMTIuMjAxNSAyMS44MzU2QzEyLjM1MTYgMjEuODA0NyAxMi40OTM0IDIxLjcyNiAxMi43NzcgMjEuNTY4NEwxNC4yNSAyMC43NTAxTTUuMjUgMTguMjUwMUwzLjgyMjk3IDE3LjQ1NzNDMy41MjM0NiAxNy4yOTA5IDMuMzczNjggMTcuMjA3NyAzLjI2NDYzIDE3LjA4OTNDMy4xNjgxNiAxNi45ODQ3IDMuMDk1MTUgMTYuODYwNiAzLjA1MDQ4IDE2LjcyNTRDMyAxNi41NzI2IDMgMTYuNDAxMyAzIDE2LjA1ODZWMTQuNTAwMU0zIDkuNTAwMDlWNy45NDE1M0MzIDcuNTk4ODkgMyA3LjQyNzU3IDMuMDUwNDggNy4yNzQ3N0MzLjA5NTE1IDcuMTM5NTkgMy4xNjgxNiA3LjAxNTUxIDMuMjY0NjMgNi45MTA4MkMzLjM3MzY4IDYuNzkyNDggMy41MjM0NSA2LjcwOTI4IDMuODIyOTcgNi41NDI4OEw1LjI1IDUuNzUwMDlNOS43NSAzLjI1MDA4TDExLjIyMyAyLjQzMTc3QzExLjUwNjYgMi4yNzQyMSAxMS42NDg0IDIuMTk1NDMgMTEuNzk4NiAyLjE2NDU0QzExLjkzMTUgMi4xMzcyMSAxMi4wNjg1IDIuMTM3MjEgMTIuMjAxNSAyLjE2NDU0QzEyLjM1MTYgMi4xOTU0MyAxMi40OTM0IDIuMjc0MjEgMTIuNzc3IDIuNDMxNzdMMTQuMjUgMy4yNTAwOE0xOC43NSA1Ljc1MDA4TDIwLjE3NyA2LjU0Mjg4QzIwLjQ3NjYgNi43MDkyOCAyMC42MjYzIDYuNzkyNDggMjAuNzM1NCA2LjkxMDgyQzIwLjgzMTggNy4wMTU1MSAyMC45MDQ5IDcuMTM5NTkgMjAuOTQ5NSA3LjI3NDc3QzIxIDcuNDI3NTcgMjEgNy41OTg4OSAyMSA3Ljk0MTUzVjkuNTAwMDhNMjEgMTQuNTAwMVYxNi4wNTg2QzIxIDE2LjQwMTMgMjEgMTYuNTcyNiAyMC45NDk1IDE2LjcyNTRDMjAuOTA0OSAxNi44NjA2IDIwLjgzMTggMTYuOTg0NyAyMC43MzU0IDE3LjA4OTNDMjAuNjI2MyAxNy4yMDc3IDIwLjQ3NjYgMTcuMjkwOSAyMC4xNzcgMTcuNDU3M0wxOC43NSAxOC4yNTAxTTkuNzUgMTAuNzUwMUwxMiAxMi4wMDAxTTEyIDEyLjAwMDFMMTQuMjUgMTAuNzUwMU0xMiAxMi4wMDAxVjE0LjUwMDFNMyA3LjAwMDA4TDUuMjUgOC4yNTAwOE0xOC43NSA4LjI1MDA4TDIxIDcuMDAwMDhNMTIgMTkuNTAwMVYyMi4wMDAxXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIHN0YXIwNkljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuICA8cGF0aCBkPVwiTTQuNSAyMlYxN000LjUgN1YyTTIgNC41SDdNMiAxOS41SDdNMTMgM0wxMS4yNjU4IDcuNTA4ODZDMTAuOTgzOCA4LjI0MjA5IDEwLjg0MjggOC42MDg3MSAxMC42MjM1IDguOTE3MDlDMTAuNDI5MiA5LjE5MDQgMTAuMTkwNCA5LjQyOTE5IDkuOTE3MDkgOS42MjM1M0M5LjYwODcxIDkuODQyODEgOS4yNDIwOSA5Ljk4MzgxIDguNTA4ODYgMTAuMjY1OEw0IDEyTDguNTA4ODYgMTMuNzM0MkM5LjI0MjA5IDE0LjAxNjIgOS42MDg3MSAxNC4xNTcyIDkuOTE3MDkgMTQuMzc2NUMxMC4xOTA0IDE0LjU3MDggMTAuNDI5MiAxNC44MDk2IDEwLjYyMzUgMTUuMDgyOUMxMC44NDI4IDE1LjM5MTMgMTAuOTgzOCAxNS43NTc5IDExLjI2NTggMTYuNDkxMUwxMyAyMUwxNC43MzQyIDE2LjQ5MTFDMTUuMDE2MiAxNS43NTc5IDE1LjE1NzIgMTUuMzkxMyAxNS4zNzY1IDE1LjA4MjlDMTUuNTcwOCAxNC44MDk2IDE1LjgwOTYgMTQuNTcwOCAxNi4wODI5IDE0LjM3NjVDMTYuMzkxMyAxNC4xNTcyIDE2Ljc1NzkgMTQuMDE2MiAxNy40OTExIDEzLjczNDJMMjIgMTJMMTcuNDkxMSAxMC4yNjU4QzE2Ljc1NzkgOS45ODM4MSAxNi4zOTEzIDkuODQyOCAxNi4wODI5IDkuNjIzNTNDMTUuODA5NiA5LjQyOTE5IDE1LjU3MDggOS4xOTA0IDE1LjM3NjUgOC45MTcwOUMxNS4xNTcyIDguNjA4NzEgMTUuMDE2MiA4LjI0MjA5IDE0LjczNDIgNy41MDg4NkwxMyAzWlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG4gIDwvc3ZnPlxuXG5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY3ViZTAySWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTEyIDIuNTAwMDhWMTIuMDAwMU0xMiAxMi4wMDAxTDIwLjUgNy4yNzc3OU0xMiAxMi4wMDAxTDMuNSA3LjI3Nzc5TTEyIDEyLjAwMDFWMjEuNTAwMU0yMC41IDE2LjcyMjNMMTIuNzc3IDEyLjQzMThDMTIuNDkzNCAxMi4yNzQyIDEyLjM1MTYgMTIuMTk1NCAxMi4yMDE1IDEyLjE2NDVDMTIuMDY4NSAxMi4xMzcyIDExLjkzMTUgMTIuMTM3MiAxMS43OTg2IDEyLjE2NDVDMTEuNjQ4NCAxMi4xOTU0IDExLjUwNjYgMTIuMjc0MiAxMS4yMjMgMTIuNDMxOEwzLjUgMTYuNzIyM00yMSAxNi4wNTg2VjcuOTQxNTNDMjEgNy41OTg4OSAyMSA3LjQyNzU3IDIwLjk0OTUgNy4yNzQ3N0MyMC45MDQ5IDcuMTM5NTkgMjAuODMxOCA3LjAxNTUxIDIwLjczNTQgNi45MTA4MkMyMC42MjYzIDYuNzkyNDggMjAuNDc2NiA2LjcwOTI4IDIwLjE3NyA2LjU0Mjg4TDEyLjc3NyAyLjQzMTc3QzEyLjQ5MzQgMi4yNzQyMSAxMi4zNTE2IDIuMTk1NDMgMTIuMjAxNSAyLjE2NDU0QzEyLjA2ODUgMi4xMzcyMSAxMS45MzE1IDIuMTM3MjEgMTEuNzk4NiAyLjE2NDU0QzExLjY0ODQgMi4xOTU0MyAxMS41MDY2IDIuMjc0MjEgMTEuMjIzIDIuNDMxNzdMMy44MjI5NyA2LjU0Mjg4QzMuNTIzNDUgNi43MDkyOCAzLjM3MzY5IDYuNzkyNDggMy4yNjQ2MyA2LjkxMDgyQzMuMTY4MTYgNy4wMTU1MSAzLjA5NTE1IDcuMTM5NTkgMy4wNTA0OCA3LjI3NDc3QzMgNy40Mjc1NyAzIDcuNTk4ODkgMyA3Ljk0MTUzVjE2LjA1ODZDMyAxNi40MDEzIDMgMTYuNTcyNiAzLjA1MDQ4IDE2LjcyNTRDMy4wOTUxNSAxNi44NjA2IDMuMTY4MTYgMTYuOTg0NyAzLjI2NDYzIDE3LjA4OTNDMy4zNzM2OSAxNy4yMDc3IDMuNTIzNDUgMTcuMjkwOSAzLjgyMjk3IDE3LjQ1NzNMMTEuMjIzIDIxLjU2ODRDMTEuNTA2NiAyMS43MjYgMTEuNjQ4NCAyMS44MDQ3IDExLjc5ODYgMjEuODM1NkMxMS45MzE1IDIxLjg2MyAxMi4wNjg1IDIxLjg2MyAxMi4yMDE1IDIxLjgzNTZDMTIuMzUxNiAyMS44MDQ3IDEyLjQ5MzQgMjEuNzI2IDEyLjc3NyAyMS41Njg0TDIwLjE3NyAxNy40NTczQzIwLjQ3NjYgMTcuMjkwOSAyMC42MjYzIDE3LjIwNzcgMjAuNzM1NCAxNy4wODkzQzIwLjgzMTggMTYuOTg0NyAyMC45MDQ5IDE2Ljg2MDYgMjAuOTQ5NSAxNi43MjU0QzIxIDE2LjU3MjYgMjEgMTYuNDAxMyAyMSAxNi4wNTg2WlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5cbmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBjdWJlMDFJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNMjAuNSA3LjI3NzgzTDEyIDEyLjAwMDFNMTIgMTIuMDAwMUwzLjQ5OTk3IDcuMjc3ODNNMTIgMTIuMDAwMUwxMiAyMS41MDAxTTIxIDE2LjA1ODZWNy45NDE1M0MyMSA3LjU5ODg5IDIxIDcuNDI3NTcgMjAuOTQ5NSA3LjI3NDc3QzIwLjkwNDkgNy4xMzk1OSAyMC44MzE4IDcuMDE1NTEgMjAuNzM1NCA2LjkxMDgyQzIwLjYyNjMgNi43OTI0OCAyMC40NzY2IDYuNzA5MjggMjAuMTc3IDYuNTQyODhMMTIuNzc3IDIuNDMxNzdDMTIuNDkzNCAyLjI3NDIxIDEyLjM1MTYgMi4xOTU0MyAxMi4yMDE1IDIuMTY0NTRDMTIuMDY4NSAyLjEzNzIxIDExLjkzMTUgMi4xMzcyMSAxMS43OTg2IDIuMTY0NTRDMTEuNjQ4NCAyLjE5NTQzIDExLjUwNjYgMi4yNzQyMSAxMS4yMjMgMi40MzE3N0wzLjgyMjk3IDYuNTQyODhDMy41MjM0NSA2LjcwOTI4IDMuMzczNjkgNi43OTI0OCAzLjI2NDYzIDYuOTEwODJDMy4xNjgxNiA3LjAxNTUxIDMuMDk1MTUgNy4xMzk1OSAzLjA1MDQ4IDcuMjc0NzdDMyA3LjQyNzU3IDMgNy41OTg4OSAzIDcuOTQxNTNWMTYuMDU4NkMzIDE2LjQwMTMgMyAxNi41NzI2IDMuMDUwNDggMTYuNzI1NEMzLjA5NTE1IDE2Ljg2MDYgMy4xNjgxNiAxNi45ODQ3IDMuMjY0NjMgMTcuMDg5M0MzLjM3MzY5IDE3LjIwNzcgMy41MjM0NSAxNy4yOTA5IDMuODIyOTcgMTcuNDU3M0wxMS4yMjMgMjEuNTY4NEMxMS41MDY2IDIxLjcyNiAxMS42NDg0IDIxLjgwNDcgMTEuNzk4NiAyMS44MzU2QzExLjkzMTUgMjEuODYzIDEyLjA2ODUgMjEuODYzIDEyLjIwMTUgMjEuODM1NkMxMi4zNTE2IDIxLjgwNDcgMTIuNDkzNCAyMS43MjYgMTIuNzc3IDIxLjU2ODRMMjAuMTc3IDE3LjQ1NzNDMjAuNDc2NiAxNy4yOTA5IDIwLjYyNjMgMTcuMjA3NyAyMC43MzU0IDE3LjA4OTNDMjAuODMxOCAxNi45ODQ3IDIwLjkwNDkgMTYuODYwNiAyMC45NDk1IDE2LjcyNTRDMjEgMTYuNTcyNiAyMSAxNi40MDEzIDIxIDE2LjA1ODZaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPlxuXG4gIGA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBiYXJDaGFydFNxdWFyZTAySWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTggMTVWMTdNMTIgMTFWMTdNMTYgN1YxN003LjggMjFIMTYuMkMxNy44ODAyIDIxIDE4LjcyMDIgMjEgMTkuMzYyIDIwLjY3M0MxOS45MjY1IDIwLjM4NTQgMjAuMzg1NCAxOS45MjY1IDIwLjY3MyAxOS4zNjJDMjEgMTguNzIwMiAyMSAxNy44ODAyIDIxIDE2LjJWNy44QzIxIDYuMTE5ODQgMjEgNS4yNzk3NiAyMC42NzMgNC42MzgwM0MyMC4zODU0IDQuMDczNTQgMTkuOTI2NSAzLjYxNDYgMTkuMzYyIDMuMzI2OThDMTguNzIwMiAzIDE3Ljg4MDIgMyAxNi4yIDNINy44QzYuMTE5ODQgMyA1LjI3OTc2IDMgNC42MzgwMyAzLjMyNjk4QzQuMDczNTQgMy42MTQ2IDMuNjE0NiA0LjA3MzU0IDMuMzI2OTggNC42MzgwM0MzIDUuMjc5NzYgMyA2LjExOTg0IDMgNy44VjE2LjJDMyAxNy44ODAyIDMgMTguNzIwMiAzLjMyNjk4IDE5LjM2MkMzLjYxNDYgMTkuOTI2NSA0LjA3MzU0IDIwLjM4NTQgNC42MzgwMyAyMC42NzNDNS4yNzk3NiAyMSA2LjExOTg0IDIxIDcuOCAyMVpcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuPC9zdmc+XG4gICAgYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGNvZGUwMkljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuPHBhdGggZD1cIk0xNyAxN0wyMiAxMkwxNyA3TTcgN0wyIDEyTDcgMTdNMTQgM0wxMCAyMVwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5cbmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBkYXRhSWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTIxLjIgMjJDMjEuNDggMjIgMjEuNjIgMjIgMjEuNzI3IDIxLjk0NTVDMjEuODIxMSAyMS44OTc2IDIxLjg5NzYgMjEuODIxMSAyMS45NDU1IDIxLjcyN0MyMiAyMS42MiAyMiAyMS40OCAyMiAyMS4yVjEwLjhDMjIgMTAuNTIgMjIgMTAuMzggMjEuOTQ1NSAxMC4yNzNDMjEuODk3NiAxMC4xNzg5IDIxLjgyMTEgMTAuMTAyNCAyMS43MjcgMTAuMDU0NUMyMS42MiAxMCAyMS40OCAxMCAyMS4yIDEwTDE4LjggMTBDMTguNTIgMTAgMTguMzggMTAgMTguMjczIDEwLjA1NDVDMTguMTc4OSAxMC4xMDI0IDE4LjEwMjQgMTAuMTc4OSAxOC4wNTQ1IDEwLjI3M0MxOCAxMC4zOCAxOCAxMC41MiAxOCAxMC44VjEzLjJDMTggMTMuNDggMTggMTMuNjIgMTcuOTQ1NSAxMy43MjdDMTcuODk3NiAxMy44MjExIDE3LjgyMTEgMTMuODk3NiAxNy43MjcgMTMuOTQ1NUMxNy42MiAxNCAxNy40OCAxNCAxNy4yIDE0SDE0LjhDMTQuNTIgMTQgMTQuMzggMTQgMTQuMjczIDE0LjA1NDVDMTQuMTc4OSAxNC4xMDI0IDE0LjEwMjQgMTQuMTc4OSAxNC4wNTQ1IDE0LjI3M0MxNCAxNC4zOCAxNCAxNC41MiAxNCAxNC44VjE3LjJDMTQgMTcuNDggMTQgMTcuNjIgMTMuOTQ1NSAxNy43MjdDMTMuODk3NiAxNy44MjExIDEzLjgyMTEgMTcuODk3NiAxMy43MjcgMTcuOTQ1NUMxMy42MiAxOCAxMy40OCAxOCAxMy4yIDE4SDEwLjhDMTAuNTIgMTggMTAuMzggMTggMTAuMjczIDE4LjA1NDVDMTAuMTc4OSAxOC4xMDI0IDEwLjEwMjQgMTguMTc4OSAxMC4wNTQ1IDE4LjI3M0MxMCAxOC4zOCAxMCAxOC41MiAxMCAxOC44VjIxLjJDMTAgMjEuNDggMTAgMjEuNjIgMTAuMDU0NSAyMS43MjdDMTAuMTAyNCAyMS44MjExIDEwLjE3ODkgMjEuODk3NiAxMC4yNzMgMjEuOTQ1NUMxMC4zOCAyMiAxMC41MiAyMiAxMC44IDIyTDIxLjIgMjJaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjxwYXRoIGQ9XCJNMTAgNi44QzEwIDYuNTE5OTcgMTAgNi4zNzk5NiAxMC4wNTQ1IDYuMjczQzEwLjEwMjQgNi4xNzg5MiAxMC4xNzg5IDYuMTAyNDMgMTAuMjczIDYuMDU0NUMxMC4zOCA2IDEwLjUyIDYgMTAuOCA2SDEzLjJDMTMuNDggNiAxMy42MiA2IDEzLjcyNyA2LjA1NDVDMTMuODIxMSA2LjEwMjQzIDEzLjg5NzYgNi4xNzg5MiAxMy45NDU1IDYuMjczQzE0IDYuMzc5OTYgMTQgNi41MTk5NyAxNCA2LjhWOS4yQzE0IDkuNDgwMDMgMTQgOS42MjAwNCAxMy45NDU1IDkuNzI3QzEzLjg5NzYgOS44MjEwOCAxMy44MjExIDkuODk3NTcgMTMuNzI3IDkuOTQ1NUMxMy42MiAxMCAxMy40OCAxMCAxMy4yIDEwSDEwLjhDMTAuNTIgMTAgMTAuMzggMTAgMTAuMjczIDkuOTQ1NUMxMC4xNzg5IDkuODk3NTcgMTAuMTAyNCA5LjgyMTA4IDEwLjA1NDUgOS43MjdDMTAgOS42MjAwNCAxMCA5LjQ4MDAzIDEwIDkuMlY2LjhaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjxwYXRoIGQ9XCJNMyAxMi44QzMgMTIuNTIgMyAxMi4zOCAzLjA1NDUgMTIuMjczQzMuMTAyNDMgMTIuMTc4OSAzLjE3ODkyIDEyLjEwMjQgMy4yNzMgMTIuMDU0NUMzLjM3OTk2IDEyIDMuNTE5OTcgMTIgMy44IDEySDYuMkM2LjQ4MDAzIDEyIDYuNjIwMDQgMTIgNi43MjcgMTIuMDU0NUM2LjgyMTA4IDEyLjEwMjQgNi44OTc1NyAxMi4xNzg5IDYuOTQ1NSAxMi4yNzNDNyAxMi4zOCA3IDEyLjUyIDcgMTIuOFYxNS4yQzcgMTUuNDggNyAxNS42MiA2Ljk0NTUgMTUuNzI3QzYuODk3NTcgMTUuODIxMSA2LjgyMTA4IDE1Ljg5NzYgNi43MjcgMTUuOTQ1NUM2LjYyMDA0IDE2IDYuNDgwMDMgMTYgNi4yIDE2SDMuOEMzLjUxOTk3IDE2IDMuMzc5OTYgMTYgMy4yNzMgMTUuOTQ1NUMzLjE3ODkyIDE1Ljg5NzYgMy4xMDI0MyAxNS44MjExIDMuMDU0NSAxNS43MjdDMyAxNS42MiAzIDE1LjQ4IDMgMTUuMlYxMi44WlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48cGF0aCBkPVwiTTIgMi44QzIgMi41MTk5NyAyIDIuMzc5OTYgMi4wNTQ1IDIuMjczQzIuMTAyNDMgMi4xNzg5MiAyLjE3ODkyIDIuMTAyNDMgMi4yNzMgMi4wNTQ1QzIuMzc5OTYgMiAyLjUxOTk3IDIgMi44IDJINS4yQzUuNDgwMDMgMiA1LjYyMDA0IDIgNS43MjcgMi4wNTQ1QzUuODIxMDggMi4xMDI0MyA1Ljg5NzU3IDIuMTc4OTIgNS45NDU1IDIuMjczQzYgMi4zNzk5NiA2IDIuNTE5OTcgNiAyLjhWNS4yQzYgNS40ODAwMyA2IDUuNjIwMDQgNS45NDU1IDUuNzI3QzUuODk3NTcgNS44MjEwOCA1LjgyMTA4IDUuODk3NTcgNS43MjcgNS45NDU1QzUuNjIwMDQgNiA1LjQ4MDAzIDYgNS4yIDZIMi44QzIuNTE5OTcgNiAyLjM3OTk2IDYgMi4yNzMgNS45NDU1QzIuMTc4OTIgNS44OTc1NyAyLjEwMjQzIDUuODIxMDggMi4wNTQ1IDUuNzI3QzIgNS42MjAwNCAyIDUuNDgwMDMgMiA1LjJWMi44WlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY2hlY2tDaXJjbGVJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIkezE1fVwiIGhlaWdodD1cIiR7MTV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuPHBhdGggZD1cIk03LjUgMTJMMTAuNSAxNUwxNi41IDlNMjIgMTJDMjIgMTcuNTIyOCAxNy41MjI4IDIyIDEyIDIyQzYuNDc3MTUgMjIgMiAxNy41MjI4IDIgMTJDMiA2LjQ3NzE1IDYuNDc3MTUgMiAxMiAyQzE3LjUyMjggMiAyMiA2LjQ3NzE1IDIyIDEyWlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5cbmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiB0dWlzdEljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuPHBhdGggZD1cIk0yMSAxNlY3LjJDMjEgNi4wNzk5IDIxIDUuNTE5ODQgMjAuNzgyIDUuMDkyMDJDMjAuNTkwMyA0LjcxNTY5IDIwLjI4NDMgNC40MDk3MyAxOS45MDggNC4yMTc5OUMxOS40ODAyIDQgMTguOTIwMSA0IDE3LjggNEg2LjJDNS4wNzk4OSA0IDQuNTE5ODQgNCA0LjA5MjAyIDQuMjE3OTlDMy43MTU2OSA0LjQwOTczIDMuNDA5NzMgNC43MTU2OSAzLjIxNzk5IDUuMDkyMDJDMyA1LjUxOTg0IDMgNi4wNzk5IDMgNy4yVjE2TTQuNjY2NjcgMjBIMTkuMzMzM0MxOS45NTMzIDIwIDIwLjI2MzMgMjAgMjAuNTE3NiAxOS45MzE5QzIxLjIwNzggMTkuNzQ2OSAyMS43NDY5IDE5LjIwNzggMjEuOTMxOSAxOC41MTc2QzIyIDE4LjI2MzMgMjIgMTcuOTUzMyAyMiAxNy4zMzMzQzIyIDE3LjAyMzMgMjIgMTYuODY4MyAyMS45NjU5IDE2Ljc0MTJDMjEuODczNSAxNi4zOTYxIDIxLjYwMzkgMTYuMTI2NSAyMS4yNTg4IDE2LjAzNDFDMjEuMTMxNyAxNiAyMC45NzY3IDE2IDIwLjY2NjcgMTZIMy4zMzMzM0MzLjAyMzM0IDE2IDIuODY4MzUgMTYgMi43NDExOCAxNi4wMzQxQzIuMzk2MDkgMTYuMTI2NSAyLjEyNjU0IDE2LjM5NjEgMi4wMzQwNyAxNi43NDEyQzIgMTYuODY4MyAyIDE3LjAyMzMgMiAxNy4zMzMzQzIgMTcuOTUzMyAyIDE4LjI2MzMgMi4wNjgxNSAxOC41MTc2QzIuMjUzMDggMTkuMjA3OCAyLjc5MjE4IDE5Ljc0NjkgMy40ODIzNiAxOS45MzE5QzMuNzM2NjkgMjAgNC4wNDY2OSAyMCA0LjY2NjY3IDIwWlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY2xvdWRCbGFuazAySWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTkuNSAxOUM1LjM1Nzg2IDE5IDIgMTUuNjQyMSAyIDExLjVDMiA3LjM1Nzg2IDUuMzU3ODYgNCA5LjUgNEMxMi4zODI3IDQgMTQuODg1NSA1LjYyNjM0IDE2LjE0MSA4LjAxMTUzQzE2LjI1OTcgOC4wMDM4OCAxNi4zNzk0IDggMTYuNSA4QzE5LjUzNzYgOCAyMiAxMC40NjI0IDIyIDEzLjVDMjIgMTYuNTM3NiAxOS41Mzc2IDE5IDE2LjUgMTlDMTMuOTQ4NSAxOSAxMi4xMjI0IDE5IDkuNSAxOVpcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuPC9zdmc+XG5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gc2VydmVyMDRJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNMjIgMTAuNUwyMS41MjU2IDYuNzA0NjNDMjEuMzM5NSA1LjIxNjAyIDIxLjI0NjUgNC40NzE2OSAyMC44OTYxIDMuOTEwOEMyMC41ODc1IDMuNDE2NjIgMjAuMTQxNiAzLjAyMzAxIDE5LjYxMyAyLjc3ODA0QzE5LjAxMyAyLjUgMTguMjYyOSAyLjUgMTYuNzYyNiAyLjVINy4yMzczNUM1LjczNzE0IDIuNSA0Ljk4NzA0IDIuNSA0LjM4NzAyIDIuNzc4MDRDMy44NTgzOCAzLjAyMzAxIDMuNDEyNSAzLjQxNjYyIDMuMTAzODYgMy45MTA4QzIuNzUzNTQgNC40NzE2OSAyLjY2MDUgNS4yMTYwMSAyLjQ3NDQyIDYuNzA0NjNMMiAxMC41TTUuNSAxNC41SDE4LjVNNS41IDE0LjVDMy41NjcgMTQuNSAyIDEyLjkzMyAyIDExQzIgOS4wNjcgMy41NjcgNy41IDUuNSA3LjVIMTguNUMyMC40MzMgNy41IDIyIDkuMDY3IDIyIDExQzIyIDEyLjkzMyAyMC40MzMgMTQuNSAxOC41IDE0LjVNNS41IDE0LjVDMy41NjcgMTQuNSAyIDE2LjA2NyAyIDE4QzIgMTkuOTMzIDMuNTY3IDIxLjUgNS41IDIxLjVIMTguNUMyMC40MzMgMjEuNSAyMiAxOS45MzMgMjIgMThDMjIgMTYuMDY3IDIwLjQzMyAxNC41IDE4LjUgMTQuNU02IDExSDYuMDFNNiAxOEg2LjAxTTEyIDExSDE4TTEyIDE4SDE4XCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIG1pY3Jvc2NvcGVJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNMyAyMkgxMk0xMSA2LjI1MjA0QzExLjYzOTIgNi4wODc1MSAxMi4zMDk0IDYgMTMgNkMxNy40MTgzIDYgMjEgOS41ODE3MiAyMSAxNEMyMSAxNy4zNTc0IDE4LjkzMTggMjAuMjMxNyAxNiAyMS40MTg1TTUuNSAxM0g5LjVDOS45NjQ2NiAxMyAxMC4xOTcgMTMgMTAuMzkwMiAxMy4wMzg0QzExLjE4MzYgMTMuMTk2MiAxMS44MDM4IDEzLjgxNjQgMTEuOTYxNiAxNC42MDk4QzEyIDE0LjgwMyAxMiAxNS4wMzUzIDEyIDE1LjVDMTIgMTUuOTY0NyAxMiAxNi4xOTcgMTEuOTYxNiAxNi4zOTAyQzExLjgwMzggMTcuMTgzNiAxMS4xODM2IDE3LjgwMzggMTAuMzkwMiAxNy45NjE2QzEwLjE5NyAxOCA5Ljk2NDY2IDE4IDkuNSAxOEg1LjVDNS4wMzUzNCAxOCA0LjgwMzAyIDE4IDQuNjA5ODIgMTcuOTYxNkMzLjgxNjQ0IDE3LjgwMzggMy4xOTYyNCAxNy4xODM2IDMuMDM4NDMgMTYuMzkwMkMzIDE2LjE5NyAzIDE1Ljk2NDcgMyAxNS41QzMgMTUuMDM1MyAzIDE0LjgwMyAzLjAzODQzIDE0LjYwOThDMy4xOTYyNCAxMy44MTY0IDMuODE2NDQgMTMuMTk2MiA0LjYwOTgyIDEzLjAzODRDNC44MDMwMiAxMyA1LjAzNTM0IDEzIDUuNSAxM1pNNCA1LjVWMTNIMTFWNS41QzExIDMuNTY3IDkuNDMzIDIgNy41IDJDNS41NjcgMiA0IDMuNTY3IDQgNS41WlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5cbmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBidWlsZGluZzA3SWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG4gIDxwYXRoIGQ9XCJNNy41IDExSDQuNkM0LjAzOTk1IDExIDMuNzU5OTIgMTEgMy41NDYwMSAxMS4xMDlDMy4zNTc4NSAxMS4yMDQ5IDMuMjA0ODcgMTEuMzU3OCAzLjEwODk5IDExLjU0NkMzIDExLjc1OTkgMyAxMi4wMzk5IDMgMTIuNlYyMU0xNi41IDExSDE5LjRDMTkuOTYwMSAxMSAyMC4yNDAxIDExIDIwLjQ1NCAxMS4xMDlDMjAuNjQyMiAxMS4yMDQ5IDIwLjc5NTEgMTEuMzU3OCAyMC44OTEgMTEuNTQ2QzIxIDExLjc1OTkgMjEgMTIuMDM5OSAyMSAxMi42VjIxTTE2LjUgMjFWNi4yQzE2LjUgNS4wNzk5IDE2LjUgNC41MTk4NCAxNi4yODIgNC4wOTIwMkMxNi4wOTAzIDMuNzE1NjkgMTUuNzg0MyAzLjQwOTczIDE1LjQwOCAzLjIxNzk5QzE0Ljk4MDIgMyAxNC40MjAxIDMgMTMuMyAzSDEwLjdDOS41Nzk4OSAzIDkuMDE5ODQgMyA4LjU5MjAyIDMuMjE3OTlDOC4yMTU2OSAzLjQwOTczIDcuOTA5NzMgMy43MTU2OSA3LjcxNzk5IDQuMDkyMDJDNy41IDQuNTE5ODQgNy41IDUuMDc5OSA3LjUgNi4yVjIxTTIyIDIxSDJNMTEgN0gxM00xMSAxMUgxM00xMSAxNUgxM1wiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG4gIDwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGJvb2tPcGVuMDFJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbiAgPHBhdGggZD1cIk0xMiAyMUwxMS44OTk5IDIwLjg0OTlDMTEuMjA1MyAxOS44MDggMTAuODU4IDE5LjI4NyAxMC4zOTkxIDE4LjkwOThDOS45OTI4NiAxOC41NzU5IDkuNTI0NzYgMTguMzI1NCA5LjAyMTYxIDE4LjE3MjZDOC40NTMyNSAxOCA3LjgyNzExIDE4IDYuNTc0ODIgMThINS4yQzQuMDc5ODkgMTggMy41MTk4NCAxOCAzLjA5MjAyIDE3Ljc4MkMyLjcxNTY5IDE3LjU5MDMgMi40MDk3MyAxNy4yODQzIDIuMjE3OTkgMTYuOTA4QzIgMTYuNDgwMiAyIDE1LjkyMDEgMiAxNC44VjYuMkMyIDUuMDc5ODkgMiA0LjUxOTg0IDIuMjE3OTkgNC4wOTIwMkMyLjQwOTczIDMuNzE1NjkgMi43MTU2OSAzLjQwOTczIDMuMDkyMDIgMy4yMTc5OUMzLjUxOTg0IDMgNC4wNzk4OSAzIDUuMiAzSDUuNkM3Ljg0MDIxIDMgOC45NjAzMSAzIDkuODE1OTYgMy40MzU5N0MxMC41Njg2IDMuODE5NDcgMTEuMTgwNSA0LjQzMTM5IDExLjU2NCA1LjE4NDA0QzEyIDYuMDM5NjggMTIgNy4xNTk3OSAxMiA5LjRNMTIgMjFWOS40TTEyIDIxTDEyLjEwMDEgMjAuODQ5OUMxMi43OTQ3IDE5LjgwOCAxMy4xNDIgMTkuMjg3IDEzLjYwMDkgMTguOTA5OEMxNC4wMDcxIDE4LjU3NTkgMTQuNDc1MiAxOC4zMjU0IDE0Ljk3ODQgMTguMTcyNkMxNS41NDY3IDE4IDE2LjE3MjkgMTggMTcuNDI1MiAxOEgxOC44QzE5LjkyMDEgMTggMjAuNDgwMiAxOCAyMC45MDggMTcuNzgyQzIxLjI4NDMgMTcuNTkwMyAyMS41OTAzIDE3LjI4NDMgMjEuNzgyIDE2LjkwOEMyMiAxNi40ODAyIDIyIDE1LjkyMDEgMjIgMTQuOFY2LjJDMjIgNS4wNzk4OSAyMiA0LjUxOTg0IDIxLjc4MiA0LjA5MjAyQzIxLjU5MDMgMy43MTU2OSAyMS4yODQzIDMuNDA5NzMgMjAuOTA4IDMuMjE3OTlDMjAuNDgwMiAzIDE5LjkyMDEgMyAxOC44IDNIMTguNEMxNi4xNTk4IDMgMTUuMDM5NyAzIDE0LjE4NCAzLjQzNTk3QzEzLjQzMTQgMy44MTk0NyAxMi44MTk1IDQuNDMxMzkgMTIuNDM2IDUuMTg0MDRDMTIgNi4wMzk2OCAxMiA3LjE1OTc5IDEyIDkuNFwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG4gIDwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGNvZGVCcm93c2VySWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG4gIDxwYXRoIGQ9XCJNMjIgOUgyTTE0IDE3LjVMMTYuNSAxNUwxNCAxMi41TTEwIDEyLjVMNy41IDE1TDEwIDE3LjVNMiA3LjhMMiAxNi4yQzIgMTcuODgwMiAyIDE4LjcyMDIgMi4zMjY5OCAxOS4zNjJDMi42MTQ2IDE5LjkyNjUgMy4wNzM1NCAyMC4zODU0IDMuNjM4MDMgMjAuNjczQzQuMjc5NzYgMjEgNS4xMTk4NCAyMSA2LjggMjFIMTcuMkMxOC44ODAyIDIxIDE5LjcyMDIgMjEgMjAuMzYyIDIwLjY3M0MyMC45MjY1IDIwLjM4NTQgMjEuMzg1NCAxOS45MjY1IDIxLjY3MyAxOS4zNjJDMjIgMTguNzIwMiAyMiAxNy44ODAyIDIyIDE2LjJWNy44QzIyIDYuMTE5ODQgMjIgNS4yNzk3NyAyMS42NzMgNC42MzgwM0MyMS4zODU0IDQuMDczNTQgMjAuOTI2NSAzLjYxNDYgMjAuMzYyIDMuMzI2OThDMTkuNzIwMiAzIDE4Ljg4MDIgMyAxNy4yIDNMNi44IDNDNS4xMTk4NCAzIDQuMjc5NzYgMyAzLjYzODAzIDMuMzI2OThDMy4wNzM1NCAzLjYxNDYgMi42MTQ2IDQuMDczNTQgMi4zMjY5OCA0LjYzODAzQzIgNS4yNzk3NiAyIDYuMTE5ODQgMiA3LjhaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbiAgPC9zdmc+XG5gO1xufVxuIiwgImNvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2RhdGFcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZmlsZW5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvZGF0YS9leGFtcGxlcy5qc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9pbXBvcnRfbWV0YV91cmwgPSBcImZpbGU6Ly8vVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2RhdGEvZXhhbXBsZXMuanNcIjtpbXBvcnQgKiBhcyBwYXRoIGZyb20gXCJub2RlOnBhdGhcIjtcbmltcG9ydCBmZyBmcm9tIFwiZmFzdC1nbG9iXCI7XG5pbXBvcnQgZnMgZnJvbSBcIm5vZGU6ZnNcIjtcblxuY29uc3QgZ2xvYiA9IHBhdGguam9pbihpbXBvcnQubWV0YS5kaXJuYW1lLCBcIi4uLy4uLy4uL2ZpeHR1cmVzLyovUkVBRE1FLm1kXCIpO1xuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gbG9hZERhdGEoZmlsZXMpIHtcbiAgaWYgKCFmaWxlcykge1xuICAgIGZpbGVzID0gZmdcbiAgICAgIC5zeW5jKGdsb2IsIHtcbiAgICAgICAgYWJzb2x1dGU6IHRydWUsXG4gICAgICB9KVxuICAgICAgLnNvcnQoKTtcbiAgfVxuICByZXR1cm4gZmlsZXMubWFwKChmaWxlKSA9PiB7XG4gICAgY29uc3QgY29udGVudCA9IGZzLnJlYWRGaWxlU3luYyhmaWxlLCBcInV0Zi04XCIpO1xuICAgIGNvbnN0IHRpdGxlUmVnZXggPSAvXiNcXHMqKC4rKS9tO1xuICAgIGNvbnN0IHRpdGxlTWF0Y2ggPSBjb250ZW50Lm1hdGNoKHRpdGxlUmVnZXgpO1xuICAgIHJldHVybiB7XG4gICAgICB0aXRsZTogdGl0bGVNYXRjaFsxXSxcbiAgICAgIG5hbWU6IHBhdGguYmFzZW5hbWUocGF0aC5kaXJuYW1lKGZpbGUpKS50b0xvd2VyQ2FzZSgpLFxuICAgICAgY29udGVudDogY29udGVudCxcbiAgICAgIHVybDogYGh0dHBzOi8vZ2l0aHViLmNvbS90dWlzdC90dWlzdC90cmVlL21haW4vZml4dHVyZXMvJHtwYXRoLmJhc2VuYW1lKFxuICAgICAgICBwYXRoLmRpcm5hbWUoZmlsZSksXG4gICAgICApfWAsXG4gICAgfTtcbiAgfSk7XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiBwYXRocygpIHtcbiAgcmV0dXJuIChhd2FpdCBsb2FkRGF0YSgpKS5tYXAoKGl0ZW0pID0+IHtcbiAgICByZXR1cm4ge1xuICAgICAgcGFyYW1zOiB7XG4gICAgICAgIGV4YW1wbGU6IGl0ZW0ubmFtZSxcbiAgICAgICAgdGl0bGU6IGl0ZW0udGl0bGUsXG4gICAgICAgIGRlc2NyaXB0aW9uOiBpdGVtLmRlc2NyaXB0aW9uLFxuICAgICAgICB1cmw6IGl0ZW0udXJsLFxuICAgICAgfSxcbiAgICAgIGNvbnRlbnQ6IGl0ZW0uY29udGVudCxcbiAgICB9O1xuICB9KTtcbn1cbiIsICJjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9kYXRhXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ZpbGVuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2RhdGEvcHJvamVjdC1kZXNjcmlwdGlvbi5qc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9pbXBvcnRfbWV0YV91cmwgPSBcImZpbGU6Ly8vVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2RhdGEvcHJvamVjdC1kZXNjcmlwdGlvbi5qc1wiO2ltcG9ydCAqIGFzIHBhdGggZnJvbSBcIm5vZGU6cGF0aFwiO1xuaW1wb3J0IGZnIGZyb20gXCJmYXN0LWdsb2JcIjtcbmltcG9ydCBmcyBmcm9tIFwibm9kZTpmc1wiO1xuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gcGF0aHMobG9jYWxlKSB7XG4gIHJldHVybiAoYXdhaXQgbG9hZERhdGEoKSkubWFwKChpdGVtKSA9PiB7XG4gICAgcmV0dXJuIHtcbiAgICAgIHBhcmFtczoge1xuICAgICAgICB0eXBlOiBpdGVtLm5hbWUsXG4gICAgICAgIHRpdGxlOiBpdGVtLnRpdGxlLFxuICAgICAgICBkZXNjcmlwdGlvbjogaXRlbS5kZXNjcmlwdGlvbixcbiAgICAgICAgaWRlbnRpZmllcjogaXRlbS5pZGVudGlmaWVyLFxuICAgICAgfSxcbiAgICAgIGNvbnRlbnQ6IGl0ZW0uY29udGVudCxcbiAgICB9O1xuICB9KTtcbn1cblxuZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIGxvYWREYXRhKGxvY2FsZSkge1xuICBjb25zdCBnZW5lcmF0ZWREaXJlY3RvcnkgPSBwYXRoLmpvaW4oXG4gICAgaW1wb3J0Lm1ldGEuZGlybmFtZSxcbiAgICBcIi4uLy4uL2RvY3MvZ2VuZXJhdGVkL21hbmlmZXN0XCIsXG4gICk7XG4gIGNvbnN0IGZpbGVzID0gZmdcbiAgICAuc3luYyhcIioqLyoubWRcIiwge1xuICAgICAgY3dkOiBnZW5lcmF0ZWREaXJlY3RvcnksXG4gICAgICBhYnNvbHV0ZTogdHJ1ZSxcbiAgICAgIGlnbm9yZTogW1wiKiovUkVBRE1FLm1kXCJdLFxuICAgIH0pXG4gICAgLnNvcnQoKTtcbiAgcmV0dXJuIGZpbGVzLm1hcCgoZmlsZSkgPT4ge1xuICAgIGNvbnN0IGNhdGVnb3J5ID0gcGF0aC5iYXNlbmFtZShwYXRoLmRpcm5hbWUoZmlsZSkpO1xuICAgIGNvbnN0IGZpbGVOYW1lID0gcGF0aC5iYXNlbmFtZShmaWxlKS5yZXBsYWNlKFwiLm1kXCIsIFwiXCIpO1xuICAgIHJldHVybiB7XG4gICAgICBjYXRlZ29yeTogY2F0ZWdvcnksXG4gICAgICB0aXRsZTogZmlsZU5hbWUsXG4gICAgICBuYW1lOiBmaWxlTmFtZS50b0xvd2VyQ2FzZSgpLFxuICAgICAgaWRlbnRpZmllcjogY2F0ZWdvcnkgKyBcIi9cIiArIGZpbGVOYW1lLnRvTG93ZXJDYXNlKCksXG4gICAgICBkZXNjcmlwdGlvbjogXCJcIixcbiAgICAgIGNvbnRlbnQ6IGZzLnJlYWRGaWxlU3luYyhmaWxlLCBcInV0Zi04XCIpLFxuICAgIH07XG4gIH0pO1xufVxuIiwgIntcbiAgXCJhc2lkZVwiOiB7XG4gICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgXCJ0aXRsZVwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlRyYW5zbGF0aW9uIFx1RDgzQ1x1REYwRFwiXG4gICAgICB9LFxuICAgICAgXCJkZXNjcmlwdGlvblwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIllvdSBjYW4gdHJhbnNsYXRlIG9yIGltcHJvdmUgdGhlIHRyYW5zbGF0aW9uIG9mIHRoaXMgcGFnZS5cIlxuICAgICAgfSxcbiAgICAgIFwiY3RhXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiQ29udHJpYnV0ZVwiXG4gICAgICB9XG4gICAgfVxuICB9LFxuICBcInNlYXJjaFwiOiB7XG4gICAgXCJwbGFjZWhvbGRlclwiOiBcIlNlYXJjaFwiLFxuICAgIFwidHJhbnNsYXRpb25zXCI6IHtcbiAgICAgIFwiYnV0dG9uXCI6IHtcbiAgICAgICAgXCJidXR0b24tdGV4dFwiOiBcIlNlYXJjaCBkb2N1bWVudGF0aW9uXCIsXG4gICAgICAgIFwiYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJTZWFyY2ggZG9jdW1lbnRhdGlvblwiXG4gICAgICB9LFxuICAgICAgXCJtb2RhbFwiOiB7XG4gICAgICAgIFwic2VhcmNoLWJveFwiOiB7XG4gICAgICAgICAgXCJyZXNldC1idXR0b24tdGl0bGVcIjogXCJDbGVhciBxdWVyeVwiLFxuICAgICAgICAgIFwicmVzZXQtYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJDbGVhciBxdWVyeVwiLFxuICAgICAgICAgIFwiY2FuY2VsLWJ1dHRvbi10ZXh0XCI6IFwiQ2FuY2VsXCIsXG4gICAgICAgICAgXCJjYW5jZWwtYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJDYW5jZWxcIlxuICAgICAgICB9LFxuICAgICAgICBcInN0YXJ0LXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJyZWNlbnQtc2VhcmNoZXMtdGl0bGVcIjogXCJTZWFyY2ggaGlzdG9yeVwiLFxuICAgICAgICAgIFwibm8tcmVjZW50LXNlYXJjaGVzLXRleHRcIjogXCJObyBzZWFyY2ggaGlzdG9yeVwiLFxuICAgICAgICAgIFwic2F2ZS1yZWNlbnQtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlNhdmUgdG8gc2VhcmNoIGhpc3RvcnlcIixcbiAgICAgICAgICBcInJlbW92ZS1yZWNlbnQtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlJlbW92ZSBmcm9tIHNlYXJjaCBoaXN0b3J5XCIsXG4gICAgICAgICAgXCJmYXZvcml0ZS1zZWFyY2hlcy10aXRsZVwiOiBcIkZhdm9yaXRlc1wiLFxuICAgICAgICAgIFwicmVtb3ZlLWZhdm9yaXRlLXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJSZW1vdmUgZnJvbSBmYXZvcml0ZXNcIlxuICAgICAgICB9LFxuICAgICAgICBcImVycm9yLXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJ0aXRsZS10ZXh0XCI6IFwiVW5hYmxlIHRvIHJldHJpZXZlIHJlc3VsdHNcIixcbiAgICAgICAgICBcImhlbHAtdGV4dFwiOiBcIllvdSBtYXkgbmVlZCB0byBjaGVjayB5b3VyIG5ldHdvcmsgY29ubmVjdGlvblwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiZm9vdGVyXCI6IHtcbiAgICAgICAgICBcInNlbGVjdC10ZXh0XCI6IFwiU2VsZWN0XCIsXG4gICAgICAgICAgXCJuYXZpZ2F0ZS10ZXh0XCI6IFwiTmF2aWdhdGVcIixcbiAgICAgICAgICBcImNsb3NlLXRleHRcIjogXCJDbG9zZVwiLFxuICAgICAgICAgIFwic2VhcmNoLWJ5LXRleHRcIjogXCJTZWFyY2ggcHJvdmlkZXJcIlxuICAgICAgICB9LFxuICAgICAgICBcIm5vLXJlc3VsdHMtc2NyZWVuXCI6IHtcbiAgICAgICAgICBcIm5vLXJlc3VsdHMtdGV4dFwiOiBcIk5vIHJlbGV2YW50IHJlc3VsdHMgZm91bmRcIixcbiAgICAgICAgICBcInN1Z2dlc3RlZC1xdWVyeS10ZXh0XCI6IFwiWW91IG1pZ2h0IHRyeSBxdWVyeWluZ1wiLFxuICAgICAgICAgIFwicmVwb3J0LW1pc3NpbmctcmVzdWx0cy10ZXh0XCI6IFwiRG8geW91IHRoaW5rIHRoaXMgcXVlcnkgc2hvdWxkIGhhdmUgcmVzdWx0cz9cIixcbiAgICAgICAgICBcInJlcG9ydC1taXNzaW5nLXJlc3VsdHMtbGluay10ZXh0XCI6IFwiQ2xpY2sgdG8gZ2l2ZSBmZWVkYmFja1wiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwibmF2YmFyXCI6IHtcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJHdWlkZXNcIlxuICAgIH0sXG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCJcbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlNlcnZlclwiXG4gICAgfSxcbiAgICBcInJlc291cmNlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJSZXNvdXJjZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInJlZmVyZW5jZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlJlZmVyZW5jZXNcIlxuICAgICAgICB9LFxuICAgICAgICBcImNvbnRyaWJ1dG9yc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29udHJpYnV0b3JzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjaGFuZ2Vsb2dcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNoYW5nZWxvZ1wiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwic2lkZWJhcnNcIjoge1xuICAgIFwiY2xpXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNMSVwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiY2xpXCI6IHtcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibG9nZ2luZ1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkxvZ2dpbmdcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwic2hlbGwtY29tcGxldGlvbnNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJTaGVsbCBjb21wbGV0aW9uc1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImNvbW1hbmRzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDb21tYW5kc1wiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwicmVmZXJlbmNlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJSZWZlcmVuY2VzXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJleGFtcGxlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiRXhhbXBsZXNcIlxuICAgICAgICB9LFxuICAgICAgICBcIm1pZ3JhdGlvbnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIk1pZ3JhdGlvbnNcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiZnJvbS12My10by12NFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkZyb20gdjMgdG8gdjRcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJjb250cmlidXRvcnNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ29udHJpYnV0b3JzXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJnZXQtc3RhcnRlZFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiR2V0IHN0YXJ0ZWRcIlxuICAgICAgICB9LFxuICAgICAgICBcImlzc3VlLXJlcG9ydGluZ1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiSXNzdWUgcmVwb3J0aW5nXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjb2RlLXJldmlld3NcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNvZGUgcmV2aWV3c1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwicHJpbmNpcGxlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiUHJpbmNpcGxlc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwidHJhbnNsYXRlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJUcmFuc2xhdGVcIlxuICAgICAgICB9LFxuICAgICAgICBcImNsaVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImxvZ2dpbmdcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJMb2dnaW5nXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImludHJvZHVjdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiSW50cm9kdWN0aW9uXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIndoeS1zZXJ2ZXJcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJXaHkgYSBzZXJ2ZXI/XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImFjY291bnRzLWFuZC1wcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFjY291bnRzIGFuZCBwcm9qZWN0c1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJhdXRoZW50aWNhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkF1dGhlbnRpY2F0aW9uXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImludGVncmF0aW9uc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkludGVncmF0aW9uc1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcIm9uLXByZW1pc2VcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIk9uLXByZW1pc2VcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiaW5zdGFsbFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3RhbGxcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwibWV0cmljc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1ldHJpY3NcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJhcGktZG9jdW1lbnRhdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQVBJIGRvY3VtZW50YXRpb25cIlxuICAgICAgICB9LFxuICAgICAgICBcInN0YXR1c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiU3RhdHVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJtZXRyaWNzLWRhc2hib2FyZFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiTWV0cmljcyBkYXNoYm9hcmRcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJHdWlkZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInR1aXN0XCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJUdWlzdFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJhYm91dFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFib3V0IFR1aXN0XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwicXVpY2stc3RhcnRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlF1aWNrIHN0YXJ0XCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImluc3RhbGwtdHVpc3RcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnN0YWxsIFR1aXN0XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImdldC1zdGFydGVkXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiR2V0IHN0YXJ0ZWRcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJmZWF0dXJlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiRmVhdHVyZXNcIlxuICAgICAgICB9LFxuICAgICAgICBcImRldmVsb3BcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkRldmVsb3BcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiZ2VuZXJhdGVkLXByb2plY3RzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiR2VuZXJhdGVkIHByb2plY3RzXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwiYWRvcHRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQWRvcHRpb25cIixcbiAgICAgICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgICAgICBcIm5ldy1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJDcmVhdGUgYSBuZXcgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVHJ5IHdpdGggYSBTd2lmdCBQYWNrYWdlXCJcbiAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgXCJtaWdyYXRlXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJNaWdyYXRlXCIsXG4gICAgICAgICAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBbiBYY29kZSBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBIFN3aWZ0IHBhY2thZ2VcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwieGNvZGVnZW4tcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFuIFhjb2RlR2VuIHByb2plY3RcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwiYmF6ZWwtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkEgQmF6ZWwgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcIm1hbmlmZXN0c1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJNYW5pZmVzdHNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkaXJlY3Rvcnktc3RydWN0dXJlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkRpcmVjdG9yeSBzdHJ1Y3R1cmVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJlZGl0aW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkVkaXRpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkZXBlbmRlbmNpZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRGVwZW5kZW5jaWVzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiY29kZS1zaGFyaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvZGUgc2hhcmluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInN5bnRoZXNpemVkLWZpbGVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlN5bnRoZXNpemVkIGZpbGVzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZHluYW1pYy1jb25maWd1cmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkR5bmFtaWMgY29uZmlndXJhdGlvblwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRlbXBsYXRlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJUZW1wbGF0ZXNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJwbHVnaW5zXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlBsdWdpbnNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJoYXNoaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkhhc2hpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJpbnNwZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3BlY3RcIixcbiAgICAgICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgICAgICBcImltcGxpY2l0LWltcG9ydHNcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkltcGxpY2l0IGltcG9ydHNcIlxuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRoZS1jb3N0LW9mLWNvbnZlbmllbmNlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlRoZSBjb3N0IG9mIGNvbnZlbmllbmNlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidG1hLWFyY2hpdGVjdHVyZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJNb2R1bGFyIGFyY2hpdGVjdHVyZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImJlc3QtcHJhY3RpY2VzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkJlc3QgcHJhY3RpY2VzXCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImNhY2hlXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ2FjaGVcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwicmVnaXN0cnlcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJSZWdpc3RyeVwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcInJlZ2lzdHJ5XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlJlZ2lzdHJ5XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwieGNvZGUtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJYY29kZSBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZ2VuZXJhdGVkLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiR2VuZXJhdGVkIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZXByb2otaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGVQcm9qLWJhc2VkIGludGVncmF0aW9uXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTd2lmdCBwYWNrYWdlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiY29udGludW91cy1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJDb250aW51b3VzIGludGVncmF0aW9uXCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInNlbGVjdGl2ZS10ZXN0aW5nXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU2VsZWN0aXZlIHRlc3RpbmdcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJzZWxlY3RpdmUtdGVzdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTZWxlY3RpdmUgdGVzdGluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGUgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImdlbmVyYXRlZC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkdlbmVyYXRlZCBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImluc2lnaHRzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zaWdodHNcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYnVuZGxlLXNpemVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJCdW5kbGUgc2l6ZVwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImludGVncmF0aW9uc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiSW50ZWdyYXRpb25zXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIm1jcFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1vZGVsIENvbnRleHQgUHJvdG9jb2wgKE1DUClcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiY29udGludW91cy1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvbnRpbnVvdXMgaW50ZWdyYXRpb25cIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJzaGFyZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiU2hhcmVcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwicHJldmlld3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJQcmV2aWV3c1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9XG59XG4iLCAie1xuICBcImFzaWRlXCI6IHtcbiAgICBcInRyYW5zbGF0ZVwiOiB7XG4gICAgICBcInRpdGxlXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFGXHUwNDM1XHUwNDQwXHUwNDM1XHUwNDMyXHUwNDNFXHUwNDM0IFx1RDgzQ1x1REYwRFwiXG4gICAgICB9LFxuICAgICAgXCJkZXNjcmlwdGlvblwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlx1MDQxMlx1MDQ0QiBcdTA0M0NcdTA0M0VcdTA0MzZcdTA0MzVcdTA0NDJcdTA0MzUgXHUwNDNGXHUwNDM1XHUwNDQwXHUwNDM1XHUwNDMyXHUwNDM1XHUwNDQxXHUwNDQyXHUwNDM4IFx1MDQzOFx1MDQzQlx1MDQzOCBcdTA0NDNcdTA0M0JcdTA0NDNcdTA0NDdcdTA0NDhcdTA0MzhcdTA0NDJcdTA0NEMgXHUwNDNGXHUwNDM1XHUwNDQwXHUwNDM1XHUwNDMyXHUwNDNFXHUwNDM0IFx1MDQ0RFx1MDQ0Mlx1MDQzRVx1MDQzOSBcdTA0NDFcdTA0NDJcdTA0NDBcdTA0MzBcdTA0M0RcdTA0MzhcdTA0NDZcdTA0NEIuXCJcbiAgICAgIH0sXG4gICAgICBcImN0YVwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlx1MDQxMlx1MDQzRFx1MDQzNVx1MDQ0MVx1MDQ0Mlx1MDQzOCBcdTA0MzJcdTA0M0FcdTA0M0JcdTA0MzBcdTA0MzRcIlxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzZWFyY2hcIjoge1xuICAgIFwicGxhY2Vob2xkZXJcIjogXCJcdTA0MUZcdTA0M0VcdTA0MzhcdTA0NDFcdTA0M0FcIixcbiAgICBcInRyYW5zbGF0aW9uc1wiOiB7XG4gICAgICBcImJ1dHRvblwiOiB7XG4gICAgICAgIFwiYnV0dG9uLXRleHRcIjogXCJcdTA0MUZcdTA0M0VcdTA0MzhcdTA0NDFcdTA0M0EgXHUwNDM0XHUwNDNFXHUwNDNBXHUwNDQzXHUwNDNDXHUwNDM1XHUwNDNEXHUwNDQyXHUwNDMwXHUwNDQ2XHUwNDM4XHUwNDM4XCIsXG4gICAgICAgIFwiYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJcdTA0MUZcdTA0M0VcdTA0MzhcdTA0NDFcdTA0M0EgXHUwNDM0XHUwNDNFXHUwNDNBXHUwNDQzXHUwNDNDXHUwNDM1XHUwNDNEXHUwNDQyXHUwNDMwXHUwNDQ2XHUwNDM4XHUwNDM4XCJcbiAgICAgIH0sXG4gICAgICBcIm1vZGFsXCI6IHtcbiAgICAgICAgXCJzZWFyY2gtYm94XCI6IHtcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi10aXRsZVwiOiBcIlx1MDQxRVx1MDQ0N1x1MDQzOFx1MDQ0MVx1MDQ0Mlx1MDQzOFx1MDQ0Mlx1MDQ0QyBcdTA0MzdcdTA0MzBcdTA0M0ZcdTA0NDBcdTA0M0VcdTA0NDFcIixcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiXHUwNDFFXHUwNDQ3XHUwNDM4XHUwNDQxXHUwNDQyXHUwNDM4XHUwNDQyXHUwNDRDIFx1MDQzN1x1MDQzMFx1MDQzRlx1MDQ0MFx1MDQzRVx1MDQ0MVwiLFxuICAgICAgICAgIFwiY2FuY2VsLWJ1dHRvbi10ZXh0XCI6IFwiXHUwNDFFXHUwNDQyXHUwNDNDXHUwNDM1XHUwNDNEXHUwNDM4XHUwNDQyXHUwNDRDXCIsXG4gICAgICAgICAgXCJjYW5jZWwtYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJcdTA0MUVcdTA0NDJcdTA0M0NcdTA0MzVcdTA0M0RcdTA0MzhcdTA0NDJcdTA0NENcIlxuICAgICAgICB9LFxuICAgICAgICBcInN0YXJ0LXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJyZWNlbnQtc2VhcmNoZXMtdGl0bGVcIjogXCJcdTA0MThcdTA0NDFcdTA0NDJcdTA0M0VcdTA0NDBcdTA0MzhcdTA0NEYgXHUwNDNGXHUwNDNFXHUwNDM4XHUwNDQxXHUwNDNBXHUwNDMwXCIsXG4gICAgICAgICAgXCJuby1yZWNlbnQtc2VhcmNoZXMtdGV4dFwiOiBcIlx1MDQxRFx1MDQzNVx1MDQ0MiBcdTA0MzhcdTA0NDFcdTA0NDJcdTA0M0VcdTA0NDBcdTA0MzhcdTA0MzggXHUwNDNGXHUwNDNFXHUwNDM4XHUwNDQxXHUwNDNBXHUwNDMwXCIsXG4gICAgICAgICAgXCJzYXZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiXHUwNDIxXHUwNDNFXHUwNDQ1XHUwNDQwXHUwNDMwXHUwNDNEXHUwNDM4XHUwNDQyXHUwNDRDIFx1MDQzMiBcdTA0MzhcdTA0NDFcdTA0NDJcdTA0M0VcdTA0NDBcdTA0MzhcdTA0NEUgXHUwNDNGXHUwNDNFXHUwNDM4XHUwNDQxXHUwNDNBXHUwNDMwXCIsXG4gICAgICAgICAgXCJyZW1vdmUtcmVjZW50LXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJcdTA0MjNcdTA0MzRcdTA0MzBcdTA0M0JcdTA0MzhcdTA0NDJcdTA0NEMgXHUwNDM4XHUwNDM3IFx1MDQzOFx1MDQ0MVx1MDQ0Mlx1MDQzRVx1MDQ0MFx1MDQzOFx1MDQzOCBcdTA0M0ZcdTA0M0VcdTA0MzhcdTA0NDFcdTA0M0FcdTA0MzBcIixcbiAgICAgICAgICBcImZhdm9yaXRlLXNlYXJjaGVzLXRpdGxlXCI6IFwiXHUwNDE4XHUwNDM3XHUwNDMxXHUwNDQwXHUwNDMwXHUwNDNEXHUwNDNEXHUwNDNFXHUwNDM1XCIsXG4gICAgICAgICAgXCJyZW1vdmUtZmF2b3JpdGUtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlx1MDQyM1x1MDQzNFx1MDQzMFx1MDQzQlx1MDQzOFx1MDQ0Mlx1MDQ0QyBcdTA0MzhcdTA0MzcgXHUwNDM4XHUwNDM3XHUwNDMxXHUwNDQwXHUwNDMwXHUwNDNEXHUwNDNEXHUwNDNFXHUwNDMzXHUwNDNFXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJlcnJvci1zY3JlZW5cIjoge1xuICAgICAgICAgIFwidGl0bGUtdGV4dFwiOiBcIlx1MDQxRFx1MDQzNSBcdTA0NDNcdTA0MzRcdTA0MzBcdTA0MzVcdTA0NDJcdTA0NDFcdTA0NEYgXHUwNDNGXHUwNDNFXHUwNDNCXHUwNDQzXHUwNDQ3XHUwNDM4XHUwNDQyXHUwNDRDIFx1MDQ0MFx1MDQzNVx1MDQzN1x1MDQ0M1x1MDQzQlx1MDQ0Q1x1MDQ0Mlx1MDQzMFx1MDQ0Mlx1MDQ0QlwiLFxuICAgICAgICAgIFwiaGVscC10ZXh0XCI6IFwiXHUwNDEyXHUwNDNFXHUwNDM3XHUwNDNDXHUwNDNFXHUwNDM2XHUwNDNEXHUwNDNFLCBcdTA0MzJcdTA0MzBcdTA0M0MgXHUwNDNEXHUwNDM1XHUwNDNFXHUwNDMxXHUwNDQ1XHUwNDNFXHUwNDM0XHUwNDM4XHUwNDNDXHUwNDNFIFx1MDQzRlx1MDQ0MFx1MDQzRVx1MDQzMlx1MDQzNVx1MDQ0MFx1MDQzOFx1MDQ0Mlx1MDQ0QyBcdTA0NDFcdTA0MzVcdTA0NDJcdTA0MzVcdTA0MzJcdTA0M0VcdTA0MzUgXHUwNDNGXHUwNDNFXHUwNDM0XHUwNDNBXHUwNDNCXHUwNDRFXHUwNDQ3XHUwNDM1XHUwNDNEXHUwNDM4XHUwNDM1XCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJmb290ZXJcIjoge1xuICAgICAgICAgIFwic2VsZWN0LXRleHRcIjogXCJcdTA0MTJcdTA0NEJcdTA0MzFcdTA0NDBcdTA0MzBcdTA0NDJcdTA0NENcIixcbiAgICAgICAgICBcIm5hdmlnYXRlLXRleHRcIjogXCJcdTA0MUZcdTA0MzVcdTA0NDBcdTA0MzVcdTA0MzlcdTA0NDJcdTA0MzhcIixcbiAgICAgICAgICBcImNsb3NlLXRleHRcIjogXCJcdTA0MTdcdTA0MzBcdTA0M0FcdTA0NDBcdTA0NEJcdTA0NDJcdTA0NENcIixcbiAgICAgICAgICBcInNlYXJjaC1ieS10ZXh0XCI6IFwiXHUwNDFGXHUwNDNFXHUwNDM4XHUwNDQxXHUwNDNBXHUwNDNFXHUwNDMyXHUwNDMwXHUwNDRGIFx1MDQ0MVx1MDQzOFx1MDQ0MVx1MDQ0Mlx1MDQzNVx1MDQzQ1x1MDQzMFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwibm8tcmVzdWx0cy1zY3JlZW5cIjoge1xuICAgICAgICAgIFwibm8tcmVzdWx0cy10ZXh0XCI6IFwiXHUwNDIwXHUwNDM1XHUwNDM3XHUwNDQzXHUwNDNCXHUwNDRDXHUwNDQyXHUwNDMwXHUwNDQyXHUwNDRCIFx1MDQzRFx1MDQzNSBcdTA0M0RcdTA0MzBcdTA0MzlcdTA0MzRcdTA0MzVcdTA0M0RcdTA0NEJcIixcbiAgICAgICAgICBcInN1Z2dlc3RlZC1xdWVyeS10ZXh0XCI6IFwiXHUwNDEyXHUwNDRCIFx1MDQzQ1x1MDQzRVx1MDQzNlx1MDQzNVx1MDQ0Mlx1MDQzNSBcdTA0M0ZcdTA0M0VcdTA0M0ZcdTA0NDBcdTA0M0VcdTA0MzFcdTA0M0VcdTA0MzJcdTA0MzBcdTA0NDJcdTA0NEMgXHUwNDM3XHUwNDMwXHUwNDNGXHUwNDQwXHUwNDNFXHUwNDQxXHUwNDM4XHUwNDQyXHUwNDRDXCIsXG4gICAgICAgICAgXCJyZXBvcnQtbWlzc2luZy1yZXN1bHRzLXRleHRcIjogXCJcdTA0MjFcdTA0NDdcdTA0MzhcdTA0NDJcdTA0MzBcdTA0MzVcdTA0NDJcdTA0MzUsIFx1MDQ0N1x1MDQ0Mlx1MDQzRSBcdTA0NERcdTA0NDJcdTA0M0VcdTA0NDIgXHUwNDM3XHUwNDMwXHUwNDNGXHUwNDQwXHUwNDNFXHUwNDQxIFx1MDQzNFx1MDQzRVx1MDQzQlx1MDQzNlx1MDQzNVx1MDQzRCBcdTA0MzhcdTA0M0NcdTA0MzVcdTA0NDJcdTA0NEMgXHUwNDQwXHUwNDM1XHUwNDM3XHUwNDQzXHUwNDNCXHUwNDRDXHUwNDQyXHUwNDMwXHUwNDQyXHUwNDRCP1wiLFxuICAgICAgICAgIFwicmVwb3J0LW1pc3NpbmctcmVzdWx0cy1saW5rLXRleHRcIjogXCJcdTA0MURcdTA0MzBcdTA0MzZcdTA0M0NcdTA0MzhcdTA0NDJcdTA0MzUsIFx1MDQ0N1x1MDQ0Mlx1MDQzRVx1MDQzMVx1MDQ0QiBcdTA0M0VcdTA0NDFcdTA0NDJcdTA0MzBcdTA0MzJcdTA0MzhcdTA0NDJcdTA0NEMgXHUwNDNFXHUwNDQyXHUwNDM3XHUwNDRCXHUwNDMyXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJuYXZiYXJcIjoge1xuICAgIFwiZ3VpZGVzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1MDQyMFx1MDQ0M1x1MDQzQVx1MDQzRVx1MDQzMlx1MDQzRVx1MDQzNFx1MDQ0MVx1MDQ0Mlx1MDQzMlx1MDQzMFwiXG4gICAgfSxcbiAgICBcImNsaVwiOiB7XG4gICAgICBcInRleHRcIjogXCJDTElcIlxuICAgIH0sXG4gICAgXCJzZXJ2ZXJcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIxXHUwNDM1XHUwNDQwXHUwNDMyXHUwNDM1XHUwNDQwXCJcbiAgICB9LFxuICAgIFwicmVzb3VyY2VzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1MDQyMFx1MDQzNVx1MDQ0MVx1MDQ0M1x1MDQ0MFx1MDQ0MVx1MDQ0QlwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwicmVmZXJlbmNlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIxXHUwNDQxXHUwNDRCXHUwNDNCXHUwNDNBXHUwNDM4XCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjb250cmlidXRvcnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQyMVx1MDQzRVx1MDQ0M1x1MDQ0N1x1MDQzMFx1MDQ0MVx1MDQ0Mlx1MDQzRFx1MDQzOFx1MDQzQVx1MDQzOFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY2hhbmdlbG9nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTA0MThcdTA0NDFcdTA0NDJcdTA0M0VcdTA0NDBcdTA0MzhcdTA0NEYgXHUwNDM4XHUwNDM3XHUwNDNDXHUwNDM1XHUwNDNEXHUwNDM1XHUwNDNEXHUwNDM4XHUwNDM5XCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzaWRlYmFyc1wiOiB7XG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJjbGlcIjoge1xuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJsb2dnaW5nXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFCXHUwNDNFXHUwNDMzXHUwNDM4XHUwNDQwXHUwNDNFXHUwNDMyXHUwNDMwXHUwNDNEXHUwNDM4XHUwNDM1XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInNoZWxsLWNvbXBsZXRpb25zXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDEwXHUwNDMyXHUwNDQyXHUwNDNFXHUwNDM3XHUwNDMwXHUwNDMyXHUwNDM1XHUwNDQwXHUwNDQ4XHUwNDM1XHUwNDNEXHUwNDM4XHUwNDRGIFNoZWxsXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiY29tbWFuZHNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxQVx1MDQzRVx1MDQzQ1x1MDQzMFx1MDQzRFx1MDQzNFx1MDQ0QlwiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwicmVmZXJlbmNlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJcdTA0MjFcdTA0NDFcdTA0NEJcdTA0M0JcdTA0M0FcdTA0MzhcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImV4YW1wbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUZcdTA0NDBcdTA0MzhcdTA0M0NcdTA0MzVcdTA0NDBcdTA0NEJcIlxuICAgICAgICB9LFxuICAgICAgICBcIm1pZ3JhdGlvbnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIk1pZ3JhdGlvbnNcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiZnJvbS12My10by12NFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxRVx1MDQ0MiB2MyBcdTA0MzRcdTA0M0UgXHUwNDMyXHUwNDM1XHUwNDQwXHUwNDQxXHUwNDM4XHUwNDM4IHY0XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1MDQyMVx1MDQzRVx1MDQ0M1x1MDQ0N1x1MDQzMFx1MDQ0MVx1MDQ0Mlx1MDQzRFx1MDQzOFx1MDQzQVx1MDQzOFwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiZ2V0LXN0YXJ0ZWRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxRFx1MDQzMFx1MDQ0N1x1MDQzMFx1MDQzQlx1MDQzRSBcdTA0NDBcdTA0MzBcdTA0MzFcdTA0M0VcdTA0NDJcdTA0NEJcIlxuICAgICAgICB9LFxuICAgICAgICBcImlzc3VlLXJlcG9ydGluZ1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFFXHUwNDQyXHUwNDQ3XHUwNDM1XHUwNDQyIFx1MDQzRVx1MDQzMSBcdTA0M0VcdTA0NDhcdTA0MzhcdTA0MzFcdTA0M0FcdTA0MzBcdTA0NDVcIlxuICAgICAgICB9LFxuICAgICAgICBcImNvZGUtcmV2aWV3c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFBXHUwNDNFXHUwNDM0IFx1MDQ0MFx1MDQzNVx1MDQzMlx1MDQ0Q1x1MDQ0RVwiXG4gICAgICAgIH0sXG4gICAgICAgIFwicHJpbmNpcGxlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFGXHUwNDQwXHUwNDM4XHUwNDNEXHUwNDQ2XHUwNDM4XHUwNDNGXHUwNDRCXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlRyYW5zbGF0ZVwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY2xpXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDTElcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibG9nZ2luZ1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxQlx1MDQzRVx1MDQzM1x1MDQzOFx1MDQ0MFx1MDQzRVx1MDQzMlx1MDQzMFx1MDQzRFx1MDQzOFx1MDQzNVwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcInNlcnZlclwiOiB7XG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJpbnRyb2R1Y3Rpb25cIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxMlx1MDQzMlx1MDQzNVx1MDQzNFx1MDQzNVx1MDQzRFx1MDQzOFx1MDQzNVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJ3aHktc2VydmVyXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDE3XHUwNDMwXHUwNDQ3XHUwNDM1XHUwNDNDIFx1MDQ0MVx1MDQzNVx1MDQ0MFx1MDQzMlx1MDQzNVx1MDQ0MD9cIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYWNjb3VudHMtYW5kLXByb2plY3RzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDEwXHUwNDNBXHUwNDNBXHUwNDMwXHUwNDQzXHUwNDNEXHUwNDQyXHUwNDRCIFx1MDQzOCBcdTA0M0ZcdTA0NDBcdTA0M0VcdTA0MzVcdTA0M0FcdTA0NDJcdTA0NEJcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYXV0aGVudGljYXRpb25cIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MTBcdTA0MzJcdTA0NDJcdTA0M0VcdTA0NDBcdTA0MzhcdTA0MzdcdTA0MzBcdTA0NDZcdTA0MzhcdTA0NEZcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiaW50ZWdyYXRpb25zXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDE4XHUwNDNEXHUwNDQyXHUwNDM1XHUwNDMzXHUwNDQwXHUwNDMwXHUwNDQ2XHUwNDM4XHUwNDRGXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwib24tcHJlbWlzZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFCXHUwNDNFXHUwNDNBXHUwNDMwXHUwNDNCXHUwNDRDXHUwNDNEXHUwNDRCXHUwNDM5IFx1MDQ0NVx1MDQzRVx1MDQ0MVx1MDQ0Mlx1MDQzOFx1MDQzRFx1MDQzM1wiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIzXHUwNDQxXHUwNDQyXHUwNDMwXHUwNDNEXHUwNDNFXHUwNDMyXHUwNDNBXHUwNDMwXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcIm1ldHJpY3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUNcdTA0MzVcdTA0NDJcdTA0NDBcdTA0MzhcdTA0M0FcdTA0MzhcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJhcGktZG9jdW1lbnRhdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQVBJIFx1MDQzNFx1MDQzRVx1MDQzQVx1MDQ0M1x1MDQzQ1x1MDQzNVx1MDQzRFx1MDQ0Mlx1MDQzMFx1MDQ0Nlx1MDQzOFx1MDQ0RlwiXG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhdHVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTA0MjFcdTA0NDJcdTA0MzBcdTA0NDJcdTA0NDNcdTA0NDFcIlxuICAgICAgICB9LFxuICAgICAgICBcIm1ldHJpY3MtZGFzaGJvYXJkXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUZcdTA0MzBcdTA0M0RcdTA0MzVcdTA0M0JcdTA0NEMgXHUwNDNGXHUwNDNFXHUwNDNBXHUwNDMwXHUwNDM3XHUwNDMwXHUwNDQyXHUwNDM1XHUwNDNCXHUwNDM1XHUwNDM5XCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJndWlkZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIwXHUwNDQzXHUwNDNBXHUwNDNFXHUwNDMyXHUwNDNFXHUwNDM0XHUwNDQxXHUwNDQyXHUwNDMyXHUwNDMwXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJ0dWlzdFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiVHVpc3RcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiYWJvdXRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUZcdTA0NDBcdTA0M0UgVHVpc3RcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJxdWljay1zdGFydFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDExXHUwNDRCXHUwNDQxXHUwNDQyXHUwNDQwXHUwNDRCXHUwNDM5IFx1MDQ0MVx1MDQ0Mlx1MDQzMFx1MDQ0MFx1MDQ0MlwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsLXR1aXN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIzXHUwNDQxXHUwNDQyXHUwNDMwXHUwNDNEXHUwNDNFXHUwNDMyXHUwNDNBXHUwNDMwIFR1aXN0XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImdldC1zdGFydGVkXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFEXHUwNDMwXHUwNDQ3XHUwNDMwXHUwNDNCXHUwNDNFIFx1MDQ0MFx1MDQzMFx1MDQzMVx1MDQzRVx1MDQ0Mlx1MDQ0QlwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImZlYXR1cmVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTA0MTJcdTA0M0VcdTA0MzdcdTA0M0NcdTA0M0VcdTA0MzZcdTA0M0RcdTA0M0VcdTA0NDFcdTA0NDJcdTA0MzhcIlxuICAgICAgICB9LFxuICAgICAgICBcImRldmVsb3BcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQyMFx1MDQzMFx1MDQzN1x1MDQ0MFx1MDQzMFx1MDQzMVx1MDQzRVx1MDQ0Mlx1MDQzQVx1MDQzMFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJnZW5lcmF0ZWQtcHJvamVjdHNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MjFcdTA0MzNcdTA0MzVcdTA0M0RcdTA0MzVcdTA0NDBcdTA0MzhcdTA0NDBcdTA0M0VcdTA0MzJcdTA0MzBcdTA0M0RcdTA0M0RcdTA0NEJcdTA0MzUgXHUwNDNGXHUwNDQwXHUwNDNFXHUwNDM1XHUwNDNBXHUwNDQyXHUwNDRCXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwiYWRvcHRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDEyXHUwNDRCXHUwNDMxXHUwNDNFXHUwNDQwXCIsXG4gICAgICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgXCJuZXctcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIxXHUwNDNFXHUwNDM3XHUwNDM0XHUwNDMwXHUwNDNEXHUwNDM4XHUwNDM1IFx1MDQzRFx1MDQzRVx1MDQzMlx1MDQzRVx1MDQzM1x1MDQzRSBcdTA0M0ZcdTA0NDBcdTA0M0VcdTA0MzVcdTA0M0FcdTA0NDJcdTA0MzBcIlxuICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxRlx1MDQzRVx1MDQzRlx1MDQ0MFx1MDQzRVx1MDQzMVx1MDQ0M1x1MDQzOVx1MDQ0Mlx1MDQzNSBcdTA0NDEgU3dpZnQgUGFja2FnZVwiXG4gICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgIFwibWlncmF0ZVwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFDXHUwNDM4XHUwNDMzXHUwNDQwXHUwNDMwXHUwNDQ2XHUwNDM4XHUwNDRGXCIsXG4gICAgICAgICAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUZcdTA0NDBcdTA0M0VcdTA0MzVcdTA0M0FcdTA0NDIgWGNvZGVcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxRlx1MDQzMFx1MDQzQVx1MDQzNVx1MDQ0MiBTd2lmdFwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICAgICAgXCJ4Y29kZWdlbi1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFGXHUwNDQwXHUwNDNFXHUwNDM1XHUwNDNBXHUwNDQyIFhjb2RlR2VuXCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICBcImJhemVsLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUZcdTA0NDBcdTA0M0VcdTA0MzVcdTA0M0FcdTA0NDIgQmF6ZWxcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJtYW5pZmVzdHNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFDXHUwNDMwXHUwNDNEXHUwNDM4XHUwNDQ0XHUwNDM1XHUwNDQxXHUwNDQyXHUwNDRCXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZGlyZWN0b3J5LXN0cnVjdHVyZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MjFcdTA0NDJcdTA0NDBcdTA0NDNcdTA0M0FcdTA0NDJcdTA0NDNcdTA0NDBcdTA0MzAgXHUwNDM0XHUwNDM4XHUwNDQwXHUwNDM1XHUwNDNBXHUwNDQyXHUwNDNFXHUwNDQwXHUwNDM4XHUwNDM5XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZWRpdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MjBcdTA0MzVcdTA0MzRcdTA0MzBcdTA0M0FcdTA0NDJcdTA0MzhcdTA0NDBcdTA0M0VcdTA0MzJcdTA0MzBcdTA0M0RcdTA0MzhcdTA0MzVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkZXBlbmRlbmNpZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDE3XHUwNDMwXHUwNDMyXHUwNDM4XHUwNDQxXHUwNDM4XHUwNDNDXHUwNDNFXHUwNDQxXHUwNDQyXHUwNDM4XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiY29kZS1zaGFyaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQyMVx1MDQzRVx1MDQzMlx1MDQzQ1x1MDQzNVx1MDQ0MVx1MDQ0Mlx1MDQzRFx1MDQzRVx1MDQzNSBcdTA0MzhcdTA0NDFcdTA0M0ZcdTA0M0VcdTA0M0JcdTA0NENcdTA0MzdcdTA0M0VcdTA0MzJcdTA0MzBcdTA0M0RcdTA0MzhcdTA0MzUgXHUwNDNBXHUwNDNFXHUwNDM0XHUwNDMwXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwic3ludGhlc2l6ZWQtZmlsZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIxXHUwNDM4XHUwNDNEXHUwNDQyXHUwNDM1XHUwNDM3XHUwNDM4XHUwNDQwXHUwNDNFXHUwNDMyXHUwNDMwXHUwNDNEXHUwNDNEXHUwNDRCXHUwNDM1IFx1MDQ0NFx1MDQzMFx1MDQzOVx1MDQzQlx1MDQ0QlwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImR5bmFtaWMtY29uZmlndXJhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MTRcdTA0MzhcdTA0M0RcdTA0MzBcdTA0M0NcdTA0MzhcdTA0NDdcdTA0MzVcdTA0NDFcdTA0M0FcdTA0MzBcdTA0NEYgXHUwNDNBXHUwNDNFXHUwNDNEXHUwNDQ0XHUwNDM4XHUwNDMzXHUwNDQzXHUwNDQwXHUwNDMwXHUwNDQ2XHUwNDM4XHUwNDRGXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidGVtcGxhdGVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQyOFx1MDQzMFx1MDQzMVx1MDQzQlx1MDQzRVx1MDQzRFx1MDQ0QlwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInBsdWdpbnNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFGXHUwNDNCXHUwNDMwXHUwNDMzXHUwNDM4XHUwNDNEXHUwNDRCXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiaGFzaGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MjVcdTA0NERcdTA0NDhcdTA0MzhcdTA0NDBcdTA0M0VcdTA0MzJcdTA0MzBcdTA0M0RcdTA0MzhcdTA0MzVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJpbnNwZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxOFx1MDQ0MVx1MDQ0MVx1MDQzQlx1MDQzNVx1MDQzNFx1MDQzRVx1MDQzMlx1MDQzMFx1MDQ0Mlx1MDQ0Q1wiLFxuICAgICAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgICAgIFwiaW1wbGljaXQtaW1wb3J0c1wiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFEXHUwNDM1XHUwNDRGXHUwNDMyXHUwNDNEXHUwNDRCXHUwNDM1IFx1MDQzOFx1MDQzQ1x1MDQzRlx1MDQzRVx1MDQ0MFx1MDQ0Mlx1MDQ0QlwiXG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidGhlLWNvc3Qtb2YtY29udmVuaWVuY2VcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIxXHUwNDQyXHUwNDNFXHUwNDM4XHUwNDNDXHUwNDNFXHUwNDQxXHUwNDQyXHUwNDRDIFx1MDQ0M1x1MDQzNFx1MDQzRVx1MDQzMVx1MDQ0MVx1MDQ0Mlx1MDQzMlx1MDQzMFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRtYS1hcmNoaXRlY3R1cmVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFDXHUwNDNFXHUwNDM0XHUwNDQzXHUwNDNCXHUwNDRDXHUwNDNEXHUwNDMwXHUwNDRGIFx1MDQzMFx1MDQ0MFx1MDQ0NVx1MDQzOFx1MDQ0Mlx1MDQzNVx1MDQzQVx1MDQ0Mlx1MDQ0M1x1MDQ0MFx1MDQzMFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImJlc3QtcHJhY3RpY2VzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxQlx1MDQ0M1x1MDQ0N1x1MDQ0OFx1MDQzOFx1MDQzNSBcdTA0M0ZcdTA0NDBcdTA0MzBcdTA0M0FcdTA0NDJcdTA0MzhcdTA0M0FcdTA0MzhcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiY2FjaGVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUFcdTA0NERcdTA0NDhcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwicmVnaXN0cnlcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MjBcdTA0MzVcdTA0MzVcdTA0NDFcdTA0NDJcdTA0NDBcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJyZWdpc3RyeVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MjBcdTA0MzVcdTA0MzVcdTA0NDFcdTA0NDJcdTA0NDBcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxRlx1MDQ0MFx1MDQzRVx1MDQzNVx1MDQzQVx1MDQ0MiBYY29kZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImdlbmVyYXRlZC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQyMVx1MDQzM1x1MDQzNVx1MDQzRFx1MDQzNVx1MDQ0MFx1MDQzOFx1MDQ0MFx1MDQzRVx1MDQzMlx1MDQzMFx1MDQzRFx1MDQzRFx1MDQ0Qlx1MDQzOSBcdTA0M0ZcdTA0NDBcdTA0M0VcdTA0MzVcdTA0M0FcdTA0NDJcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZXByb2otaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDE4XHUwNDNEXHUwNDQyXHUwNDM1XHUwNDMzXHUwNDQwXHUwNDMwXHUwNDQ2XHUwNDM4XHUwNDRGIFx1MDQzRFx1MDQzMCBcdTA0M0VcdTA0NDFcdTA0M0RcdTA0M0VcdTA0MzJcdTA0MzUgWGNvZGVQcm9qXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUZcdTA0MzBcdTA0M0FcdTA0MzVcdTA0NDIgU3dpZnRcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJjb250aW51b3VzLWludGVncmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvbnRpbnVvdXMgaW50ZWdyYXRpb25cIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwic2VsZWN0aXZlLXRlc3RpbmdcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MTJcdTA0NEJcdTA0MzFcdTA0M0VcdTA0NDBcdTA0M0VcdTA0NDdcdTA0M0RcdTA0M0VcdTA0MzUgXHUwNDQyXHUwNDM1XHUwNDQxXHUwNDQyXHUwNDM4XHUwNDQwXHUwNDNFXHUwNDMyXHUwNDMwXHUwNDNEXHUwNDM4XHUwNDM1XCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwic2VsZWN0aXZlLXRlc3RpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDEyXHUwNDRCXHUwNDMxXHUwNDNFXHUwNDQwXHUwNDNFXHUwNDQ3XHUwNDNEXHUwNDNFXHUwNDM1IFx1MDQ0Mlx1MDQzNVx1MDQ0MVx1MDQ0Mlx1MDQzOFx1MDQ0MFx1MDQzRVx1MDQzMlx1MDQzMFx1MDQzRFx1MDQzOFx1MDQzNVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGUgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImdlbmVyYXRlZC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQyMVx1MDQzM1x1MDQzNVx1MDQzRFx1MDQzNVx1MDQ0MFx1MDQzOFx1MDQ0MFx1MDQzRVx1MDQzMlx1MDQzMFx1MDQzRFx1MDQzRFx1MDQ0Qlx1MDQzOSBcdTA0M0ZcdTA0NDBcdTA0M0VcdTA0MzVcdTA0M0FcdTA0NDJcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiaW5zaWdodHNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MTBcdTA0M0RcdTA0MzBcdTA0M0JcdTA0MzhcdTA0NDJcdTA0MzhcdTA0M0FcdTA0MzBcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYnVuZGxlLXNpemVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJCdW5kbGUgc2l6ZVwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImludGVncmF0aW9uc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiSW50ZWdyYXRpb25zXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIm1jcFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxRlx1MDQ0MFx1MDQzRVx1MDQ0Mlx1MDQzRVx1MDQzQVx1MDQzRVx1MDQzQiBcdTA0M0FcdTA0M0VcdTA0M0RcdTA0NDJcdTA0MzVcdTA0M0FcdTA0NDFcdTA0NDJcdTA0MzAgXHUwNDNDXHUwNDNFXHUwNDM0XHUwNDM1XHUwNDNCXHUwNDM4IChNQ1ApXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImNvbnRpbnVvdXMtaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MURcdTA0MzVcdTA0M0ZcdTA0NDBcdTA0MzVcdTA0NDBcdTA0NEJcdTA0MzJcdTA0M0RcdTA0MzBcdTA0NEYgXHUwNDM4XHUwNDNEXHUwNDQyXHUwNDM1XHUwNDMzXHUwNDQwXHUwNDMwXHUwNDQ2XHUwNDM4XHUwNDRGIChDSSlcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJzaGFyZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFGXHUwNDNFXHUwNDM0XHUwNDM1XHUwNDNCXHUwNDM4XHUwNDQyXHUwNDRDXHUwNDQxXHUwNDRGXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcInByZXZpZXdzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFGXHUwNDQwXHUwNDM1XHUwNDMyXHUwNDRDXHUwNDRFXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH1cbn1cbiIsICJ7XG4gIFwiYXNpZGVcIjoge1xuICAgIFwidHJhbnNsYXRlXCI6IHtcbiAgICAgIFwidGl0bGVcIjoge1xuICAgICAgICBcInRleHRcIjogXCJUcmFuc2xhdGlvbiBcdUQ4M0NcdURGMERcIlxuICAgICAgfSxcbiAgICAgIFwiZGVzY3JpcHRpb25cIjoge1xuICAgICAgICBcInRleHRcIjogXCJcdUM3NzQgXHVEMzk4XHVDNzc0XHVDOUMwXHVCOTdDIFx1QkM4OFx1QzVFRFx1RDU1OFx1QUM3MFx1QjA5OCBcdUFFMzBcdUM4NzQgXHVCQzg4XHVDNUVEXHVDNzQ0IFx1QUMxQ1x1QzEyMFx1RDU2MCBcdUMyMTggXHVDNzg4XHVDMkI1XHVCMkM4XHVCMkU0LlwiXG4gICAgICB9LFxuICAgICAgXCJjdGFcIjoge1xuICAgICAgICBcInRleHRcIjogXCJcdUFFMzBcdUM1RUNcIlxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzZWFyY2hcIjoge1xuICAgIFwicGxhY2Vob2xkZXJcIjogXCJcdUFDODBcdUMwQzlcIixcbiAgICBcInRyYW5zbGF0aW9uc1wiOiB7XG4gICAgICBcImJ1dHRvblwiOiB7XG4gICAgICAgIFwiYnV0dG9uLXRleHRcIjogXCJcdUJCMzhcdUMxMUMgXHVBQzgwXHVDMEM5XCIsXG4gICAgICAgIFwiYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJcdUJCMzhcdUMxMUMgXHVBQzgwXHVDMEM5XCJcbiAgICAgIH0sXG4gICAgICBcIm1vZGFsXCI6IHtcbiAgICAgICAgXCJzZWFyY2gtYm94XCI6IHtcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi10aXRsZVwiOiBcIlx1Q0ZGQ1x1QjlBQyBcdUNEMDhcdUFFMzBcdUQ2NTRcIixcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiXHVDRkZDXHVCOUFDIFx1Q0QwOFx1QUUzMFx1RDY1NFwiLFxuICAgICAgICAgIFwiY2FuY2VsLWJ1dHRvbi10ZXh0XCI6IFwiXHVDREU4XHVDMThDXCIsXG4gICAgICAgICAgXCJjYW5jZWwtYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJcdUNERThcdUMxOENcIlxuICAgICAgICB9LFxuICAgICAgICBcInN0YXJ0LXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJyZWNlbnQtc2VhcmNoZXMtdGl0bGVcIjogXCJcdUFDODBcdUMwQzkgXHVDNzc0XHVCODI1XCIsXG4gICAgICAgICAgXCJuby1yZWNlbnQtc2VhcmNoZXMtdGV4dFwiOiBcIlx1QUM4MFx1QzBDOSBcdUM3NzRcdUI4MjVcdUM3NzQgXHVDNUM2XHVDNzRDXCIsXG4gICAgICAgICAgXCJzYXZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiXHVBQzgwXHVDMEM5IFx1Qzc3NFx1QjgyNSBcdUM4MDBcdUM3QTVcIixcbiAgICAgICAgICBcInJlbW92ZS1yZWNlbnQtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlx1QUM4MFx1QzBDOSBcdUM3NzRcdUI4MjUgXHVDMEFEXHVDODFDXCIsXG4gICAgICAgICAgXCJmYXZvcml0ZS1zZWFyY2hlcy10aXRsZVwiOiBcIlx1Qzk5MFx1QUNBOFx1Q0MzRVx1QUUzMFwiLFxuICAgICAgICAgIFwicmVtb3ZlLWZhdm9yaXRlLXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJcdUM5OTBcdUFDQThcdUNDM0VcdUFFMzAgXHVDMEFEXHVDODFDXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJlcnJvci1zY3JlZW5cIjoge1xuICAgICAgICAgIFwidGl0bGUtdGV4dFwiOiBcIlx1QUNCMFx1QUNGQ1x1Qjk3QyBcdUJDMUJcdUM3NDQgXHVDMjE4IFx1QzVDNlx1Qzc0Q1wiLFxuICAgICAgICAgIFwiaGVscC10ZXh0XCI6IFwiXHVCMTI0XHVEMkI4XHVDNkNDXHVEMDZDIFx1QzVGMFx1QUNCMFx1Qzc0NCBcdUQ2NTVcdUM3NzhcdUQ1NzRcdUM4RkNcdUMxMzhcdUM2OTRcIlxuICAgICAgICB9LFxuICAgICAgICBcImZvb3RlclwiOiB7XG4gICAgICAgICAgXCJzZWxlY3QtdGV4dFwiOiBcIlx1QzEyMFx1RDBERFwiLFxuICAgICAgICAgIFwibmF2aWdhdGUtdGV4dFwiOiBcIlx1RDBEMFx1QzBDOVwiLFxuICAgICAgICAgIFwiY2xvc2UtdGV4dFwiOiBcIlx1QjJFQlx1QUUzMFwiLFxuICAgICAgICAgIFwic2VhcmNoLWJ5LXRleHRcIjogXCJcdUFDODBcdUMwQzkgXHVDODFDXHVBQ0Y1XHVDNzkwXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJuby1yZXN1bHRzLXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJuby1yZXN1bHRzLXRleHRcIjogXCJcdUFEMDBcdUI4MjhcdUI0MUMgXHVBQ0IwXHVBQ0ZDXHVCOTdDIFx1Q0MzRVx1Qzc0NCBcdUMyMTggXHVDNUM2XHVDNzRDXCIsXG4gICAgICAgICAgXCJzdWdnZXN0ZWQtcXVlcnktdGV4dFwiOiBcIlx1QjJFNFx1Qjk3OCBcdUFDODBcdUMwQzlcdUM1QjRcdUI5N0MgXHVDNzg1XHVCODI1XHVENTc0XHVCQ0Y0XHVDMTM4XHVDNjk0XCIsXG4gICAgICAgICAgXCJyZXBvcnQtbWlzc2luZy1yZXN1bHRzLXRleHRcIjogXCJcdUFDODBcdUMwQzkgXHVBQ0IwXHVBQ0ZDXHVBQzAwIFx1Qzc4OFx1QzVCNFx1QzU3QyBcdUQ1NUNcdUIyRTRcdUFDRTAgXHVDMEREXHVBQzAxXHVENTU4XHVCMDk4XHVDNjk0P1wiLFxuICAgICAgICAgIFwicmVwb3J0LW1pc3NpbmctcmVzdWx0cy1saW5rLXRleHRcIjogXCJcdUQ1M0NcdUI0RENcdUJDMzFcdUQ1NThcdUFFMzBcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9LFxuICBcIm5hdmJhclwiOiB7XG4gICAgXCJndWlkZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiXHVDNTQ4XHVCMEI0XHVDMTFDXCJcbiAgICB9LFxuICAgIFwiY2xpXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNMSVwiXG4gICAgfSxcbiAgICBcInNlcnZlclwiOiB7XG4gICAgICBcInRleHRcIjogXCJcdUMxMUNcdUJDODRcIlxuICAgIH0sXG4gICAgXCJyZXNvdXJjZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiXHVCOUFDXHVDMThDXHVDMkE0XCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJyZWZlcmVuY2VzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdUNDMzhcdUFDRTBcdUM3OTBcdUI4Q0NcIlxuICAgICAgICB9LFxuICAgICAgICBcImNvbnRyaWJ1dG9yc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHVBRTMwXHVDNUVDXHVDNzkwXHVCNEU0XCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjaGFuZ2Vsb2dcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1QzIxOFx1QzgxNVx1QzBBQ1x1RDU2RFwiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwic2lkZWJhcnNcIjoge1xuICAgIFwiY2xpXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNMSVwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiY2xpXCI6IHtcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibG9nZ2luZ1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1Qjg1Q1x1QUU0NVwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJzaGVsbC1jb21wbGV0aW9uc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlNoZWxsIGNvbXBsZXRpb25zXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiY29tbWFuZHNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNvbW1hbmRzXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJyZWZlcmVuY2VzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlJlZmVyZW5jZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImV4YW1wbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJFeGFtcGxlc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwibWlncmF0aW9uc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiTWlncmF0aW9uc1wiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJmcm9tLXYzLXRvLXY0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRnJvbSB2MyB0byB2NFwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImNvbnRyaWJ1dG9yc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJDb250cmlidXRvcnNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImdldC1zdGFydGVkXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJHZXQgc3RhcnRlZFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiaXNzdWUtcmVwb3J0aW5nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJJc3N1ZSByZXBvcnRpbmdcIlxuICAgICAgICB9LFxuICAgICAgICBcImNvZGUtcmV2aWV3c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29kZSByZXZpZXdzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJwcmluY2lwbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJQcmluY2lwbGVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlRyYW5zbGF0ZVwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY2xpXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDTElcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibG9nZ2luZ1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1Qjg1Q1x1QUU0NVwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcInNlcnZlclwiOiB7XG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJpbnRyb2R1Y3Rpb25cIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkludHJvZHVjdGlvblwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJ3aHktc2VydmVyXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiV2h5IGEgc2VydmVyP1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJhY2NvdW50cy1hbmQtcHJvamVjdHNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJBY2NvdW50cyBhbmQgcHJvamVjdHNcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYXV0aGVudGljYXRpb25cIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJBdXRoZW50aWNhdGlvblwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJpbnRlZ3JhdGlvbnNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnRlZ3JhdGlvbnNcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJvbi1wcmVtaXNlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJPbi1wcmVtaXNlXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImluc3RhbGxcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnN0YWxsXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcIm1ldHJpY3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJNZXRyaWNzXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiYXBpLWRvY3VtZW50YXRpb25cIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkFQSSBkb2N1bWVudGF0aW9uXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJzdGF0dXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlN0YXR1c1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwibWV0cmljcy1kYXNoYm9hcmRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1RDFCNVx1QUNDNCBcdUQ2MDRcdUQ2NjlcdUQzMTBcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJcdUM1NDhcdUIwQjRcdUMxMUNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInR1aXN0XCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJUdWlzdFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJhYm91dFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFib3V0IFR1aXN0XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwicXVpY2stc3RhcnRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlF1aWNrIHN0YXJ0XCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImluc3RhbGwtdHVpc3RcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnN0YWxsIFR1aXN0XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImdldC1zdGFydGVkXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiR2V0IHN0YXJ0ZWRcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJmZWF0dXJlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHVBRTMwXHVCMkE1XCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJkZXZlbG9wXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJEZXZlbG9wXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImdlbmVyYXRlZC1wcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkdlbmVyYXRlZCBwcm9qZWN0c1wiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcImFkb3B0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFkb3B0aW9uXCIsXG4gICAgICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgXCJuZXctcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ3JlYXRlIGEgbmV3IHByb2plY3RcIlxuICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlRyeSB3aXRoIGEgU3dpZnQgUGFja2FnZVwiXG4gICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgIFwibWlncmF0ZVwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTWlncmF0ZVwiLFxuICAgICAgICAgICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgXCJ4Y29kZS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQW4gWGNvZGUgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICAgICAgXCJzd2lmdC1wYWNrYWdlXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQSBTd2lmdCBwYWNrYWdlXCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICBcInhjb2RlZ2VuLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBbiBYY29kZUdlbiBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICBcImJhemVsLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBIEJhemVsIHByb2plY3RcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJtYW5pZmVzdHNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTWFuaWZlc3RzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZGlyZWN0b3J5LXN0cnVjdHVyZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJEaXJlY3Rvcnkgc3RydWN0dXJlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZWRpdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJFZGl0aW5nXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZGVwZW5kZW5jaWVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkRlcGVuZGVuY2llc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImNvZGUtc2hhcmluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJDb2RlIHNoYXJpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJzeW50aGVzaXplZC1maWxlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTeW50aGVzaXplZCBmaWxlc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImR5bmFtaWMtY29uZmlndXJhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJEeW5hbWljIGNvbmZpZ3VyYXRpb25cIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0ZW1wbGF0ZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVGVtcGxhdGVzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwicGx1Z2luc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJQbHVnaW5zXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiaGFzaGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJIYXNoaW5nXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiaW5zcGVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnNwZWN0XCIsXG4gICAgICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgXCJpbXBsaWNpdC1pbXBvcnRzXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJJbXBsaWNpdCBpbXBvcnRzXCJcbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0aGUtY29zdC1vZi1jb252ZW5pZW5jZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJUaGUgY29zdCBvZiBjb252ZW5pZW5jZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRtYS1hcmNoaXRlY3R1cmVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTW9kdWxhciBhcmNoaXRlY3R1cmVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJiZXN0LXByYWN0aWNlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJCZXN0IHByYWN0aWNlc1wiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJjYWNoZVwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNhY2hlXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInJlZ2lzdHJ5XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUmVnaXN0cnlcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJyZWdpc3RyeVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJSZWdpc3RyeVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGUgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImdlbmVyYXRlZC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkdlbmVyYXRlZCBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwieGNvZGVwcm9qLWludGVncmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlhjb2RlUHJvai1iYXNlZCBpbnRlZ3JhdGlvblwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU3dpZnQgcGFja2FnZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImNvbnRpbnVvdXMtaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29udGludW91cyBpbnRlZ3JhdGlvblwiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJzZWxlY3RpdmUtdGVzdGluZ1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlNlbGVjdGl2ZSB0ZXN0aW5nXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwic2VsZWN0aXZlLXRlc3RpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU2VsZWN0aXZlIHRlc3RpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlhjb2RlIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJnZW5lcmF0ZWQtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJHZW5lcmF0ZWQgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJpbnNpZ2h0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc2lnaHRzXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImJ1bmRsZS1zaXplXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQnVuZGxlIHNpemVcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJpbnRlZ3JhdGlvbnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkludGVncmF0aW9uc1wiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJtY3BcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJNb2RlbCBDb250ZXh0IFByb3RvY29sIChNQ1ApXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImNvbnRpbnVvdXMtaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJDb250aW51b3VzIGludGVncmF0aW9uXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwic2hhcmVcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlNoYXJlXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcInByZXZpZXdzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUHJldmlld3NcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfVxufVxuIiwgIntcbiAgXCJhc2lkZVwiOiB7XG4gICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgXCJ0aXRsZVwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlx1N0ZGQlx1OEEzMyBcdUQ4M0NcdURGMERcIlxuICAgICAgfSxcbiAgICAgIFwiZGVzY3JpcHRpb25cIjoge1xuICAgICAgICBcInRleHRcIjogXCJcdTMwNTNcdTMwNkVcdTMwREFcdTMwRkNcdTMwQjhcdTMwNkVcdTdGRkJcdThBMzNcdTMwOTJcdTg4NENcdTMwNjNcdTMwNUZcdTMwOEFcdTMwMDFcdTY1MzlcdTU1ODRcdTMwNTdcdTMwNUZcdTMwOEFcdTMwNTlcdTMwOEJcdTMwNTNcdTMwNjhcdTMwNENcdTMwNjdcdTMwNERcdTMwN0VcdTMwNTlcdTMwMDJcIlxuICAgICAgfSxcbiAgICAgIFwiY3RhXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEIzXHUzMEYzXHUzMEM4XHUzMEVBXHUzMEQzXHUzMEU1XHUzMEZDXHUzMEM4XHUzMDU5XHUzMDhCXCJcbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwic2VhcmNoXCI6IHtcbiAgICBcInBsYWNlaG9sZGVyXCI6IFwiXHU2OTFDXHU3RDIyXCIsXG4gICAgXCJ0cmFuc2xhdGlvbnNcIjoge1xuICAgICAgXCJidXR0b25cIjoge1xuICAgICAgICBcImJ1dHRvbi10ZXh0XCI6IFwiXHUzMEM5XHUzMEFEXHUzMEU1XHUzMEUxXHUzMEYzXHUzMEM4XHUzMDkyXHU2OTFDXHU3RDIyXCIsXG4gICAgICAgIFwiYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJcdTMwQzlcdTMwQURcdTMwRTVcdTMwRTFcdTMwRjNcdTMwQzhcdTMwOTJcdTY5MUNcdTdEMjJcIlxuICAgICAgfSxcbiAgICAgIFwibW9kYWxcIjoge1xuICAgICAgICBcInNlYXJjaC1ib3hcIjoge1xuICAgICAgICAgIFwicmVzZXQtYnV0dG9uLXRpdGxlXCI6IFwiXHU2OTFDXHU3RDIyXHUzMEFEXHUzMEZDXHUzMEVGXHUzMEZDXHUzMEM5XHUzMDkyXHU1MjRBXHU5NjY0XCIsXG4gICAgICAgICAgXCJyZXNldC1idXR0b24tYXJpYS1sYWJlbFwiOiBcIlx1NjkxQ1x1N0QyMlx1MzBBRFx1MzBGQ1x1MzBFRlx1MzBGQ1x1MzBDOVx1MzA5Mlx1NTI0QVx1OTY2NFwiLFxuICAgICAgICAgIFwiY2FuY2VsLWJ1dHRvbi10ZXh0XCI6IFwiXHUzMEFEXHUzMEUzXHUzMEYzXHUzMEJCXHUzMEVCXCIsXG4gICAgICAgICAgXCJjYW5jZWwtYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJcdTMwQURcdTMwRTNcdTMwRjNcdTMwQkJcdTMwRUJcIlxuICAgICAgICB9LFxuICAgICAgICBcInN0YXJ0LXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJyZWNlbnQtc2VhcmNoZXMtdGl0bGVcIjogXCJcdTVDNjVcdTZCNzRcdTMwOTJcdTY5MUNcdTdEMjJcIixcbiAgICAgICAgICBcIm5vLXJlY2VudC1zZWFyY2hlcy10ZXh0XCI6IFwiXHU2OTFDXHU3RDIyXHU1QzY1XHU2Qjc0XHUzMDZGXHUzMDQyXHUzMDhBXHUzMDdFXHUzMDVCXHUzMDkzXCIsXG4gICAgICAgICAgXCJzYXZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiXHU2OTFDXHU3RDIyXHU1QzY1XHU2Qjc0XHUzMDZCXHU0RkREXHU1QjU4XCIsXG4gICAgICAgICAgXCJyZW1vdmUtcmVjZW50LXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJcdTY5MUNcdTdEMjJcdTVDNjVcdTZCNzRcdTMwNEJcdTMwODlcdTUyNEFcdTk2NjRcdTMwNTlcdTMwOEJcIixcbiAgICAgICAgICBcImZhdm9yaXRlLXNlYXJjaGVzLXRpdGxlXCI6IFwiXHUzMDRBXHU2QzE3XHUzMDZCXHU1MTY1XHUzMDhBXCIsXG4gICAgICAgICAgXCJyZW1vdmUtZmF2b3JpdGUtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlx1MzA0QVx1NkMxN1x1MzA2Qlx1NTE2NVx1MzA4QVx1MzA0Qlx1MzA4OVx1NTI0QVx1OTY2NFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiZXJyb3Itc2NyZWVuXCI6IHtcbiAgICAgICAgICBcInRpdGxlLXRleHRcIjogXCJcdTdENTBcdTY3OUNcdTMwOTJcdTUzRDZcdTVGOTdcdTMwNjdcdTMwNERcdTMwN0VcdTMwNUJcdTMwOTNcdTMwNjdcdTMwNTdcdTMwNUZcIixcbiAgICAgICAgICBcImhlbHAtdGV4dFwiOiBcIlx1MzBDRFx1MzBDM1x1MzBDOFx1MzBFRlx1MzBGQ1x1MzBBRlx1NjNBNVx1N0Q5QVx1MzA5Mlx1NzhCQVx1OEE4RFx1MzA1N1x1MzA2Nlx1MzA0Rlx1MzA2MFx1MzA1NVx1MzA0NFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiZm9vdGVyXCI6IHtcbiAgICAgICAgICBcInNlbGVjdC10ZXh0XCI6IFwiXHU5MDc4XHU2MjlFXCIsXG4gICAgICAgICAgXCJuYXZpZ2F0ZS10ZXh0XCI6IFwiXHU3OUZCXHU1MkQ1XCIsXG4gICAgICAgICAgXCJjbG9zZS10ZXh0XCI6IFwiXHU5NTg5XHUzMDU4XHUzMDhCXCIsXG4gICAgICAgICAgXCJzZWFyY2gtYnktdGV4dFwiOiBcIlx1NjkxQ1x1N0QyMlx1MzBEN1x1MzBFRFx1MzBEMFx1MzBBNFx1MzBDMFx1MzBGQ1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwibm8tcmVzdWx0cy1zY3JlZW5cIjoge1xuICAgICAgICAgIFwibm8tcmVzdWx0cy10ZXh0XCI6IFwiXHU5NUEyXHU5MDIzXHUzMDU5XHUzMDhCXHU3RDUwXHU2NzlDXHUzMDRDXHU4OThCXHUzMDY0XHUzMDRCXHUzMDhBXHUzMDdFXHUzMDVCXHUzMDkzXHUzMDY3XHUzMDU3XHUzMDVGXCIsXG4gICAgICAgICAgXCJzdWdnZXN0ZWQtcXVlcnktdGV4dFwiOiBcIlx1MzBBRlx1MzBBOFx1MzBFQVx1MzA5Mlx1OEE2Nlx1MzA1N1x1MzA2Nlx1MzA3Rlx1MzA4Qlx1MzA1M1x1MzA2OFx1MzA0Q1x1MzA2N1x1MzA0RFx1MzA3RVx1MzA1OVwiLFxuICAgICAgICAgIFwicmVwb3J0LW1pc3NpbmctcmVzdWx0cy10ZXh0XCI6IFwiXHUzMDUzXHUzMDZFXHUzMEFGXHUzMEE4XHUzMEVBXHUzMDZCXHUzMDZGXHU3RDUwXHU2NzlDXHUzMDRDXHUzMDQyXHUzMDhCXHUzMDY4XHU2MDFEXHUzMDQ0XHUzMDdFXHUzMDU5XHUzMDRCP1wiLFxuICAgICAgICAgIFwicmVwb3J0LW1pc3NpbmctcmVzdWx0cy1saW5rLXRleHRcIjogXCJcdTMwQUZcdTMwRUFcdTMwQzNcdTMwQUZcdTMwNTdcdTMwNjZcdTMwRDVcdTMwQTNcdTMwRkNcdTMwQzlcdTMwRDBcdTMwQzNcdTMwQUZcdTMwNTlcdTMwOEJcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9LFxuICBcIm5hdmJhclwiOiB7XG4gICAgXCJndWlkZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEFDXHUzMEE0XHUzMEM5XCJcbiAgICB9LFxuICAgIFwiY2xpXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNMSVwiXG4gICAgfSxcbiAgICBcInNlcnZlclwiOiB7XG4gICAgICBcInRleHRcIjogXCJcdTMwQjVcdTMwRkNcdTMwRDBcdTMwRkNcIlxuICAgIH0sXG4gICAgXCJyZXNvdXJjZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEVBXHUzMEJEXHUzMEZDXHUzMEI5XCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJyZWZlcmVuY2VzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwRUFcdTMwRDVcdTMwQTFcdTMwRUNcdTMwRjNcdTMwQjlcIlxuICAgICAgICB9LFxuICAgICAgICBcImNvbnRyaWJ1dG9yc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEIzXHUzMEYzXHUzMEM4XHUzMEVBXHUzMEQzXHUzMEU1XHUzMEZDXHUzMEJGXHUzMEZDXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjaGFuZ2Vsb2dcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1NTkwOVx1NjZGNFx1NUM2NVx1NkI3NFwiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwic2lkZWJhcnNcIjoge1xuICAgIFwiY2xpXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNMSVwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiY2xpXCI6IHtcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibG9nZ2luZ1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBFRFx1MzBBRVx1MzBGM1x1MzBCMFwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJzaGVsbC1jb21wbGV0aW9uc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlNoZWxsIGNvbXBsZXRpb25zXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiY29tbWFuZHNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBCM1x1MzBERVx1MzBGM1x1MzBDOVwiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwicmVmZXJlbmNlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJcdTMwRUFcdTMwRDVcdTMwQTFcdTMwRUNcdTMwRjNcdTMwQjlcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImV4YW1wbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwQjVcdTMwRjNcdTMwRDdcdTMwRUJcIlxuICAgICAgICB9LFxuICAgICAgICBcIm1pZ3JhdGlvbnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBERVx1MzBBNFx1MzBCMFx1MzBFQ1x1MzBGQ1x1MzBCN1x1MzBFN1x1MzBGM1wiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJmcm9tLXYzLXRvLXY0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwidjMgXHUzMDRCXHUzMDg5IHY0IFx1MzA3OFwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImNvbnRyaWJ1dG9yc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJcdTMwQjNcdTMwRjNcdTMwQzhcdTMwRUFcdTMwRDNcdTMwRTVcdTMwRkNcdTMwQkZcdTMwRkNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImdldC1zdGFydGVkXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTU5Q0JcdTMwODFcdTY1QjlcIlxuICAgICAgICB9LFxuICAgICAgICBcImlzc3VlLXJlcG9ydGluZ1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiSXNzdWVcdTU4MzFcdTU0NEFcIlxuICAgICAgICB9LFxuICAgICAgICBcImNvZGUtcmV2aWV3c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEIzXHUzMEZDXHUzMEM5XHUzMEVDXHUzMEQzXHUzMEU1XHUzMEZDXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJwcmluY2lwbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTUzOUZcdTUyNDdcIlxuICAgICAgICB9LFxuICAgICAgICBcInRyYW5zbGF0ZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU3RkZCXHU4QTMzXHUzMDU5XHUzMDhCXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjbGlcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNMSVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJsb2dnaW5nXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEVEXHUzMEFFXHUzMEYzXHUzMEIwXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImludHJvZHVjdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMDZGXHUzMDU4XHUzMDgxXHUzMDZCXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIndoeS1zZXJ2ZXJcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwNkFcdTMwNUNcdTMwQjVcdTMwRkNcdTMwRDBcdTMwRkNcdTMwNENcdTVGQzVcdTg5ODFcdTMwNkFcdTMwNkVcdTMwNEJcdUZGMUZcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYWNjb3VudHMtYW5kLXByb2plY3RzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEEyXHUzMEFCXHUzMEE2XHUzMEYzXHUzMEM4XHUzMDY4XHUzMEQ3XHUzMEVEXHUzMEI4XHUzMEE3XHUzMEFGXHUzMEM4XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImF1dGhlbnRpY2F0aW9uXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU4QThEXHU4QTNDXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImludGVncmF0aW9uc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBBNFx1MzBGM1x1MzBDNlx1MzBCMFx1MzBFQ1x1MzBGQ1x1MzBCN1x1MzBFN1x1MzBGM1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcIm9uLXByZW1pc2VcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBBQVx1MzBGM1x1MzBEN1x1MzBFQ1x1MzBERlx1MzBCOVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEE0XHUzMEYzXHUzMEI5XHUzMEM4XHUzMEZDXHUzMEVCXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcIm1ldHJpY3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwRTFcdTMwQzhcdTMwRUFcdTMwQUZcdTMwQjlcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJhcGktZG9jdW1lbnRhdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQVBJXHUzMEM5XHUzMEFEXHUzMEU1XHUzMEUxXHUzMEYzXHUzMEM4XCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJzdGF0dXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBCOVx1MzBDNlx1MzBGQ1x1MzBCRlx1MzBCOVwiXG4gICAgICAgIH0sXG4gICAgICAgIFwibWV0cmljcy1kYXNoYm9hcmRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBFMVx1MzBDOFx1MzBFQVx1MzBBRlx1MzBCOVx1MzBDMFx1MzBDM1x1MzBCN1x1MzBFNVx1MzBEQ1x1MzBGQ1x1MzBDOVwiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwiZ3VpZGVzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1MzBBQ1x1MzBBNFx1MzBDOVwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwidHVpc3RcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlR1aXN0XCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImFib3V0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVHVpc3QgXHUzMDZCXHUzMDY0XHUzMDQ0XHUzMDY2XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwicXVpY2stc3RhcnRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBBRlx1MzBBNFx1MzBDM1x1MzBBRlx1MzBCOVx1MzBCRlx1MzBGQ1x1MzBDOFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsLXR1aXN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVHVpc3RcdTMwNkVcdTMwQTRcdTMwRjNcdTMwQjlcdTMwQzhcdTMwRkNcdTMwRUJcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiZ2V0LXN0YXJ0ZWRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwNkZcdTMwNThcdTMwODFcdTMwNkJcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJmZWF0dXJlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU2QTVGXHU4MEZEXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJkZXZlbG9wXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTk1OEJcdTc2N0FcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiZ2VuZXJhdGVkLXByb2plY3RzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEQ3XHUzMEVEXHUzMEI4XHUzMEE3XHUzMEFGXHUzMEM4XCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwiYWRvcHRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU1QzBFXHU1MTY1XCIsXG4gICAgICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgXCJuZXctcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU2NUIwXHU4OThGXHUzMEQ3XHUzMEVEXHUzMEI4XHUzMEE3XHUzMEFGXHUzMEM4XHUzMDZFXHU0RjVDXHU2MjEwXCJcbiAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgXCJzd2lmdC1wYWNrYWdlXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTd2lmdCBcdTMwRDFcdTMwQzNcdTMwQjFcdTMwRkNcdTMwQjhcdTMwNjhcdTRGN0ZcdTc1MjhcdTMwNTlcdTMwOEJcIlxuICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICBcIm1pZ3JhdGVcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1NzlGQlx1ODg0Q1x1MzA1OVx1MzA4QlwiLFxuICAgICAgICAgICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgXCJ4Y29kZS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGUgXHUzMEQ3XHUzMEVEXHUzMEI4XHUzMEE3XHUzMEFGXHUzMEM4XCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTd2lmdCBcdTMwRDFcdTMwQzNcdTMwQjFcdTMwRkNcdTMwQjhcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwieGNvZGVnZW4tcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlhjb2RlR2VuIFx1MzBEN1x1MzBFRFx1MzBCOFx1MzBBN1x1MzBBRlx1MzBDOFwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICAgICAgXCJiYXplbC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQmF6ZWwgXHUzMEQ3XHUzMEVEXHUzMEI4XHUzMEE3XHUzMEFGXHUzMEM4XCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwibWFuaWZlc3RzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBERVx1MzBDQlx1MzBENVx1MzBBN1x1MzBCOVx1MzBDOFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImRpcmVjdG9yeS1zdHJ1Y3R1cmVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEM3XHUzMEEzXHUzMEVDXHUzMEFGXHUzMEM4XHUzMEVBXHU2OUNCXHU2MjEwXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZWRpdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTdERThcdTk2QzZcdTY1QjlcdTZDRDVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkZXBlbmRlbmNpZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU0RjlEXHU1QjU4XHU5NUEyXHU0RkMyXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiY29kZS1zaGFyaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBCM1x1MzBGQ1x1MzBDOVx1MzA2RVx1NTE3MVx1NjcwOVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInN5bnRoZXNpemVkLWZpbGVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1ODFFQVx1NTJENVx1NzUxRlx1NjIxMFx1MzBENVx1MzBBMVx1MzBBNFx1MzBFQlwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImR5bmFtaWMtY29uZmlndXJhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTUyRDVcdTc2ODRcdTMwQjNcdTMwRjNcdTMwRDVcdTMwQTNcdTMwQUVcdTMwRTVcdTMwRUNcdTMwRkNcdTMwQjdcdTMwRTdcdTMwRjNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0ZW1wbGF0ZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEM2XHUzMEYzXHUzMEQ3XHUzMEVDXHUzMEZDXHUzMEM4XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwicGx1Z2luc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwRDdcdTMwRTlcdTMwQjBcdTMwQTRcdTMwRjNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJoYXNoaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBDRlx1MzBDM1x1MzBCN1x1MzBFNVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImluc3BlY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU2OTFDXHU2N0ZCXCIsXG4gICAgICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgXCJpbXBsaWNpdC1pbXBvcnRzXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTY2OTdcdTlFRDlcdTMwNkVcdTMwQTRcdTMwRjNcdTMwRERcdTMwRkNcdTMwQzhcIlxuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRoZS1jb3N0LW9mLWNvbnZlbmllbmNlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1NTIyOVx1NEZCRlx1NjAyN1x1MzA2RVx1NEVFM1x1NTExRlwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRtYS1hcmNoaXRlY3R1cmVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEUyXHUzMEI4XHUzMEU1XHUzMEZDXHUzMEU5XHUzMEZDXHUzMEEyXHUzMEZDXHUzMEFEXHUzMEM2XHUzMEFGXHUzMEMxXHUzMEUzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiYmVzdC1wcmFjdGljZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEQ5XHUzMEI5XHUzMEM4XHUzMEQ3XHUzMEU5XHUzMEFGXHUzMEM2XHUzMEEzXHUzMEI5XCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImNhY2hlXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEFEXHUzMEUzXHUzMEMzXHUzMEI3XHUzMEU1XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInJlZ2lzdHJ5XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEVDXHUzMEI4XHUzMEI5XHUzMEM4XHUzMEVBXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwicmVnaXN0cnlcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEVDXHUzMEI4XHUzMEI5XHUzMEM4XHUzMEVBXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwieGNvZGUtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJYY29kZSBcdTMwRDdcdTMwRURcdTMwQjhcdTMwQTdcdTMwQUZcdTMwQzhcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJnZW5lcmF0ZWQtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTc1MUZcdTYyMTBcdTMwNTVcdTMwOENcdTMwNUZcdTMwRDdcdTMwRURcdTMwQjhcdTMwQTdcdTMwQUZcdTMwQzhcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZXByb2otaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGVQcm9qIFx1MzBEOVx1MzBGQ1x1MzBCOVx1MzA2RVx1N0Q3MVx1NTQwOFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU3dpZnQgXHUzMEQxXHUzMEMzXHUzMEIxXHUzMEZDXHUzMEI4XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiY29udGludW91cy1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTdEOTlcdTdEOUFcdTc2ODRcdTMwQTRcdTMwRjNcdTMwQzZcdTMwQjBcdTMwRUNcdTMwRkNcdTMwQjdcdTMwRTdcdTMwRjNcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwic2VsZWN0aXZlLXRlc3RpbmdcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTkwNzhcdTYyOUVcdTc2ODRcdTMwQzZcdTMwQjlcdTMwQzhcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJzZWxlY3RpdmUtdGVzdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTkwNzhcdTYyOUVcdTc2ODRcdTMwQzZcdTMwQjlcdTMwQzhcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlhjb2RlIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJnZW5lcmF0ZWQtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTc1MUZcdTYyMTBcdTMwNTVcdTMwOENcdTMwNUZcdTMwRDdcdTMwRURcdTMwQjhcdTMwQTdcdTMwQUZcdTMwQzhcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiaW5zaWdodHNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnNpZ2h0c1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJidW5kbGUtc2l6ZVwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkJ1bmRsZSBzaXplXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiaW50ZWdyYXRpb25zXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJJbnRlZ3JhdGlvbnNcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibWNwXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEUyXHUzMEM3XHUzMEVCXHUzMEIzXHUzMEYzXHUzMEM2XHUzMEFEXHUzMEI5XHUzMEM4XHUzMEQ3XHUzMEVEXHUzMEM4XHUzMEIzXHUzMEVCKE1DUClcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiY29udGludW91cy1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1N0Q5OVx1N0Q5QVx1NzY4NFx1MzBBNFx1MzBGM1x1MzBDNlx1MzBCMFx1MzBFQ1x1MzBGQ1x1MzBCN1x1MzBFN1x1MzBGM1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcInNoYXJlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTUxNzFcdTY3MDlcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwicHJldmlld3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwRDdcdTMwRUNcdTMwRDNcdTMwRTVcdTMwRkNcdTZBNUZcdTgwRkRcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfVxufVxuIiwgIntcbiAgXCJhc2lkZVwiOiB7XG4gICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgXCJ0aXRsZVwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlRyYWR1Y2NpXHUwMEYzbiBcdUQ4M0NcdURGMERcIlxuICAgICAgfSxcbiAgICAgIFwiZGVzY3JpcHRpb25cIjoge1xuICAgICAgICBcInRleHRcIjogXCJUcmFkdWNlIG8gbWVqb3JhIGxhIHRyYWR1Y2NpXHUwMEYzbiBkZSBlc3RhIHBcdTAwRTFnaW5hLlwiXG4gICAgICB9LFxuICAgICAgXCJjdGFcIjoge1xuICAgICAgICBcInRleHRcIjogXCJDb250cmlidXllXCJcbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwic2VhcmNoXCI6IHtcbiAgICBcInBsYWNlaG9sZGVyXCI6IFwiQnVzY2FcIixcbiAgICBcInRyYW5zbGF0aW9uc1wiOiB7XG4gICAgICBcImJ1dHRvblwiOiB7XG4gICAgICAgIFwiYnV0dG9uLXRleHRcIjogXCJCdXNjYSBlbiBsYSBkb2N1bWVudGFjaVx1MDBGM25cIixcbiAgICAgICAgXCJidXR0b24tYXJpYS1sYWJlbFwiOiBcIkJ1c2NhIGVuIGxhIGRvY3VtZW50YWNpXHUwMEYzblwiXG4gICAgICB9LFxuICAgICAgXCJtb2RhbFwiOiB7XG4gICAgICAgIFwic2VhcmNoLWJveFwiOiB7XG4gICAgICAgICAgXCJyZXNldC1idXR0b24tdGl0bGVcIjogXCJMaW1waWFyIHRcdTAwRTlybWlubyBkZSBiXHUwMEZBc3F1ZWRhXCIsXG4gICAgICAgICAgXCJyZXNldC1idXR0b24tYXJpYS1sYWJlbFwiOiBcIkxpbXBpYXIgdFx1MDBFOXJtaW5vIGRlIGJcdTAwRkFzcXVlZGFcIixcbiAgICAgICAgICBcImNhbmNlbC1idXR0b24tdGV4dFwiOiBcIkNhbmNlbGFyXCIsXG4gICAgICAgICAgXCJjYW5jZWwtYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJDYW5jZWxhclwiXG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhcnQtc2NyZWVuXCI6IHtcbiAgICAgICAgICBcInJlY2VudC1zZWFyY2hlcy10aXRsZVwiOiBcIkhpc3RvcmlhbCBkZSBiXHUwMEZBc3F1ZWRhXCIsXG4gICAgICAgICAgXCJuby1yZWNlbnQtc2VhcmNoZXMtdGV4dFwiOiBcIk5vIGhheSBoaXN0b3JpYWwgZGUgYlx1MDBGQXNxdWVkYVwiLFxuICAgICAgICAgIFwic2F2ZS1yZWNlbnQtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIkd1YXJkYXIgZW4gZWwgaGlzdG9yaWFsIGRlIGJcdTAwRkFzcXVlZGFcIixcbiAgICAgICAgICBcInJlbW92ZS1yZWNlbnQtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIkVsaW1pbmFyIGRlbCBoaXN0b3JpYWwgZGUgYlx1MDBGQXNxdWVkYVwiLFxuICAgICAgICAgIFwiZmF2b3JpdGUtc2VhcmNoZXMtdGl0bGVcIjogXCJGYXZvcml0b3NcIixcbiAgICAgICAgICBcInJlbW92ZS1mYXZvcml0ZS1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiRWxpbWluYXIgZGUgZmF2b3JpdG9zXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJlcnJvci1zY3JlZW5cIjoge1xuICAgICAgICAgIFwidGl0bGUtdGV4dFwiOiBcIkltcG9zaWJsZSBvYnRlbmVyIHJlc3VsdGFkb3NcIixcbiAgICAgICAgICBcImhlbHAtdGV4dFwiOiBcIkNvbXBydWViYSB0dSBjb25leGlcdTAwRjNuIGEgSW50ZXJuZXRcIlxuICAgICAgICB9LFxuICAgICAgICBcImZvb3RlclwiOiB7XG4gICAgICAgICAgXCJzZWxlY3QtdGV4dFwiOiBcIlNlbGVjY2lvbmFcIixcbiAgICAgICAgICBcIm5hdmlnYXRlLXRleHRcIjogXCJOYXZlZ2FyXCIsXG4gICAgICAgICAgXCJjbG9zZS10ZXh0XCI6IFwiQ2VycmFyXCIsXG4gICAgICAgICAgXCJzZWFyY2gtYnktdGV4dFwiOiBcIlByb3ZlZWRvciBkZSBiXHUwMEZBc3F1ZWRhXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJuby1yZXN1bHRzLXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJuby1yZXN1bHRzLXRleHRcIjogXCJObyBzZSBlbmNvbnRyYXJvbiByZXN1bHRhZG9zIHJlbGV2YW50ZXNcIixcbiAgICAgICAgICBcInN1Z2dlc3RlZC1xdWVyeS10ZXh0XCI6IFwiUG9kclx1MDBFRGFzIGludGVudGFyIGNvbnN1bHRhclwiLFxuICAgICAgICAgIFwicmVwb3J0LW1pc3NpbmctcmVzdWx0cy10ZXh0XCI6IFwiXHUwMEJGQ3JlZSBxdWUgZXN0YSBjb25zdWx0YSBkZWJlclx1MDBFRGEgdGVuZXIgcmVzdWx0YWRvcz9cIixcbiAgICAgICAgICBcInJlcG9ydC1taXNzaW5nLXJlc3VsdHMtbGluay10ZXh0XCI6IFwiSGF6IGNsaWMgcGFyYSBkYXIgdHUgb3BpbmlcdTAwRjNuXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJuYXZiYXJcIjoge1xuICAgIFwiZ3VpZGVzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkd1XHUwMEVEYXNcIlxuICAgIH0sXG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCJcbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlNlcnZpZG9yXCJcbiAgICB9LFxuICAgIFwicmVzb3VyY2VzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlJlY3Vyc29zXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJyZWZlcmVuY2VzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJSZWZlcmVuY2lhc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDb2xhYm9yYWRvcmVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjaGFuZ2Vsb2dcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNoYW5nZWxvZ1wiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwic2lkZWJhcnNcIjoge1xuICAgIFwiY2xpXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNMSVwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiY2xpXCI6IHtcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibG9nZ2luZ1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkxvZ2dpbmdcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwic2hlbGwtY29tcGxldGlvbnNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJTaGVsbCBjb21wbGV0aW9uc1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImNvbW1hbmRzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDb21hbmRvc1wiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwicmVmZXJlbmNlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJSZWZlcmVuY2lhc1wiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiZXhhbXBsZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkVqZW1wbG9zXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJtaWdyYXRpb25zXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJNaWdyYWNpb25lc1wiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJmcm9tLXYzLXRvLXY0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRGUgdjMgYSB2NFwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImNvbnRyaWJ1dG9yc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJDb2xhYm9yYWRvcmVzXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJnZXQtc3RhcnRlZFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29tZW56YXJcIlxuICAgICAgICB9LFxuICAgICAgICBcImlzc3VlLXJlcG9ydGluZ1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiUmVwb3J0ZSBkZSBJc3N1ZXNcIlxuICAgICAgICB9LFxuICAgICAgICBcImNvZGUtcmV2aWV3c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiUmV2aXNpXHUwMEYzbiBkZSBjXHUwMEYzZGlnb1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwicHJpbmNpcGxlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiUHJpbmNpcGlvc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwidHJhbnNsYXRlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJUcmFkdWNlXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjbGlcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNMSVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJsb2dnaW5nXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTG9nZ2luZ1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcInNlcnZlclwiOiB7XG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJpbnRyb2R1Y3Rpb25cIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkludHJvZHVjY2lcdTAwRjNuXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIndoeS1zZXJ2ZXJcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTAwQkZQb3IgcXVcdTAwRTkgdW4gc2Vydmlkb3I/XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImFjY291bnRzLWFuZC1wcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkN1ZW50YXMgeSBwcm95ZWN0b3NcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYXV0aGVudGljYXRpb25cIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJBdXRlbnRpZmljYWNpXHUwMEYzblwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJpbnRlZ3JhdGlvbnNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnRlZ3JhY2lvbmVzXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwib24tcHJlbWlzZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiT24tcHJlbWlzZVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zdGFsYVwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJtZXRyaWNzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTVx1MDBFOXRyaWNhc1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImFwaS1kb2N1bWVudGF0aW9uXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJEb2N1bWVudGFjaVx1MDBGM24gZGUgbGEgQVBJXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJzdGF0dXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkVzdGFkb1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwibWV0cmljcy1kYXNoYm9hcmRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlBhbmVsIGRlIG1cdTAwRTl0cmljYXNcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJHdVx1MDBFRGFzXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJ0dWlzdFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiVHVpc3RcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiYWJvdXRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJBYm91dCBUdWlzdFwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcInF1aWNrLXN0YXJ0XCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJRdWljayBTdGFydFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsLXR1aXN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zdGFsYSBUdWlzdFwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJnZXQtc3RhcnRlZFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkdldCBzdGFydGVkXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiZmVhdHVyZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNhcmFjdGVyXHUwMEVEc3RpY2FzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJkZXZlbG9wXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJEZXNhcnJvbGxhXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImdlbmVyYXRlZC1wcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlByb3llY3RvcyBnZW5lcmFkb3NcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJhZG9wdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBZG9wdGlvblwiLFxuICAgICAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgICAgIFwibmV3LXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNyZWF0ZSBhIG5ldyBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgXCJzd2lmdC1wYWNrYWdlXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJUcnkgd2l0aCBhIFN3aWZ0IFBhY2thZ2VcIlxuICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICBcIm1pZ3JhdGVcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1pZ3JhdGVcIixcbiAgICAgICAgICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgIFwieGNvZGUtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFuIFhjb2RlIHByb2plY3RcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkEgU3dpZnQgcGFja2FnZVwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICAgICAgXCJ4Y29kZWdlbi1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQW4gWGNvZGVHZW4gcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICAgICAgXCJiYXplbC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQSBCYXplbCBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwibWFuaWZlc3RzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkZpY2hlcm9zIG1hbmlmZXN0XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZGlyZWN0b3J5LXN0cnVjdHVyZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJFc3RydWN0dXJhIGRlIGRpcmVjdG9yaW9zXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZWRpdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJFZGljaVx1MDBGM25cIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkZXBlbmRlbmNpZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRGVwZW5kZW5jaWFzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiY29kZS1zaGFyaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvbXBhcnRpciBjXHUwMEYzZGlnb1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInN5bnRoZXNpemVkLWZpbGVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlNpbnRldGl6YWRvIGRlIGZpY2hlcm9zXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZHluYW1pYy1jb25maWd1cmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvbmZpZ3VyYWNpXHUwMEYzbiBkaW5cdTAwRTFtaWNhXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidGVtcGxhdGVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlBsYW50aWxsYXNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJwbHVnaW5zXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlBsdWdpbnNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJoYXNoaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkhhc2hlYWRvXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiaW5zcGVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnNwZWN0XCIsXG4gICAgICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgXCJpbXBsaWNpdC1pbXBvcnRzXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJJbXBsaWNpdCBpbXBvcnRzXCJcbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0aGUtY29zdC1vZi1jb252ZW5pZW5jZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJFbCBjb3N0ZSBkZSBsYSBjb252ZW5pZW5jaWFcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0bWEtYXJjaGl0ZWN0dXJlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFyY2hpdGVjdHVyYSBtb2R1bGFyXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiYmVzdC1wcmFjdGljZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQnVlbmFzIHByXHUwMEUxY3RpY2FzXCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImNhY2hlXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ2FjaGVcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwicmVnaXN0cnlcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJSZWdpc3RyeVwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcInJlZ2lzdHJ5XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlJlZ2lzdHJ5XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwieGNvZGUtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJYY29kZSBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZ2VuZXJhdGVkLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiR2VuZXJhdGVkIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZXByb2otaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGVQcm9qLWJhc2VkIGludGVncmF0aW9uXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTd2lmdCBwYWNrYWdlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiY29udGludW91cy1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJDb250aW51b3VzIGludGVncmF0aW9uXCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInNlbGVjdGl2ZS10ZXN0aW5nXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU2VsZWN0aXZlIHRlc3RpbmdcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJzZWxlY3RpdmUtdGVzdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTZWxlY3RpdmUgdGVzdGluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGUgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImdlbmVyYXRlZC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkdlbmVyYXRlZCBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImluc2lnaHRzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zaWdodHNcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYnVuZGxlLXNpemVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJCdW5kbGUgc2l6ZVwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImludGVncmF0aW9uc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiSW50ZWdyYXRpb25zXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIm1jcFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1vZGVsIENvbnRleHQgUHJvdG9jb2wgKE1DUClcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiY29udGludW91cy1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvbnRpbnVvdXMgaW50ZWdyYXRpb25cIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJzaGFyZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29tcGFydGVcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwicHJldmlld3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJQcmV2aWV3c1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9XG59XG4iLCAie1xuICBcImFzaWRlXCI6IHtcbiAgICBcInRyYW5zbGF0ZVwiOiB7XG4gICAgICBcInRpdGxlXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiVHJhbnNsYXRpb24gXHVEODNDXHVERjBEXCJcbiAgICAgIH0sXG4gICAgICBcImRlc2NyaXB0aW9uXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiWW91IGNhbiB0cmFuc2xhdGUgb3IgaW1wcm92ZSB0aGUgdHJhbnNsYXRpb24gb2YgdGhpcyBwYWdlLlwiXG4gICAgICB9LFxuICAgICAgXCJjdGFcIjoge1xuICAgICAgICBcInRleHRcIjogXCJDb250cmlidXRlXCJcbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwic2VhcmNoXCI6IHtcbiAgICBcInBsYWNlaG9sZGVyXCI6IFwiU2VhcmNoXCIsXG4gICAgXCJ0cmFuc2xhdGlvbnNcIjoge1xuICAgICAgXCJidXR0b25cIjoge1xuICAgICAgICBcImJ1dHRvbi10ZXh0XCI6IFwiU2VhcmNoIGRvY3VtZW50YXRpb25cIixcbiAgICAgICAgXCJidXR0b24tYXJpYS1sYWJlbFwiOiBcIlNlYXJjaCBkb2N1bWVudGF0aW9uXCJcbiAgICAgIH0sXG4gICAgICBcIm1vZGFsXCI6IHtcbiAgICAgICAgXCJzZWFyY2gtYm94XCI6IHtcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi10aXRsZVwiOiBcIkNsZWFyIHF1ZXJ5XCIsXG4gICAgICAgICAgXCJyZXNldC1idXR0b24tYXJpYS1sYWJlbFwiOiBcIkNsZWFyIHF1ZXJ5XCIsXG4gICAgICAgICAgXCJjYW5jZWwtYnV0dG9uLXRleHRcIjogXCJDYW5jZWxcIixcbiAgICAgICAgICBcImNhbmNlbC1idXR0b24tYXJpYS1sYWJlbFwiOiBcIkNhbmNlbFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhcnQtc2NyZWVuXCI6IHtcbiAgICAgICAgICBcInJlY2VudC1zZWFyY2hlcy10aXRsZVwiOiBcIlNlYXJjaCBoaXN0b3J5XCIsXG4gICAgICAgICAgXCJuby1yZWNlbnQtc2VhcmNoZXMtdGV4dFwiOiBcIk5vIHNlYXJjaCBoaXN0b3J5XCIsXG4gICAgICAgICAgXCJzYXZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiU2F2ZSB0byBzZWFyY2ggaGlzdG9yeVwiLFxuICAgICAgICAgIFwicmVtb3ZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiUmVtb3ZlIGZyb20gc2VhcmNoIGhpc3RvcnlcIixcbiAgICAgICAgICBcImZhdm9yaXRlLXNlYXJjaGVzLXRpdGxlXCI6IFwiRmF2b3JpdGVzXCIsXG4gICAgICAgICAgXCJyZW1vdmUtZmF2b3JpdGUtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlJlbW92ZSBmcm9tIGZhdm9yaXRlc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiZXJyb3Itc2NyZWVuXCI6IHtcbiAgICAgICAgICBcInRpdGxlLXRleHRcIjogXCJVbmFibGUgdG8gcmV0cmlldmUgcmVzdWx0c1wiLFxuICAgICAgICAgIFwiaGVscC10ZXh0XCI6IFwiWW91IG1heSBuZWVkIHRvIGNoZWNrIHlvdXIgbmV0d29yayBjb25uZWN0aW9uXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJmb290ZXJcIjoge1xuICAgICAgICAgIFwic2VsZWN0LXRleHRcIjogXCJTZWxlY3RcIixcbiAgICAgICAgICBcIm5hdmlnYXRlLXRleHRcIjogXCJOYXZpZ2F0ZVwiLFxuICAgICAgICAgIFwiY2xvc2UtdGV4dFwiOiBcIkNsb3NlXCIsXG4gICAgICAgICAgXCJzZWFyY2gtYnktdGV4dFwiOiBcIlNlYXJjaCBwcm92aWRlclwiXG4gICAgICAgIH0sXG4gICAgICAgIFwibm8tcmVzdWx0cy1zY3JlZW5cIjoge1xuICAgICAgICAgIFwibm8tcmVzdWx0cy10ZXh0XCI6IFwiTm8gcmVsZXZhbnQgcmVzdWx0cyBmb3VuZFwiLFxuICAgICAgICAgIFwic3VnZ2VzdGVkLXF1ZXJ5LXRleHRcIjogXCJZb3UgbWlnaHQgdHJ5IHF1ZXJ5aW5nXCIsXG4gICAgICAgICAgXCJyZXBvcnQtbWlzc2luZy1yZXN1bHRzLXRleHRcIjogXCJEbyB5b3UgdGhpbmsgdGhpcyBxdWVyeSBzaG91bGQgaGF2ZSByZXN1bHRzP1wiLFxuICAgICAgICAgIFwicmVwb3J0LW1pc3NpbmctcmVzdWx0cy1saW5rLXRleHRcIjogXCJDbGljayB0byBnaXZlIGZlZWRiYWNrXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJuYXZiYXJcIjoge1xuICAgIFwiZ3VpZGVzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkd1aWRlc1wiXG4gICAgfSxcbiAgICBcImNsaVwiOiB7XG4gICAgICBcInRleHRcIjogXCJDTElcIlxuICAgIH0sXG4gICAgXCJzZXJ2ZXJcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiU2VydmVyXCJcbiAgICB9LFxuICAgIFwicmVzb3VyY2VzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlJlc291cmNlc1wiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwicmVmZXJlbmNlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiUmVmZXJlbmNlc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDb250cmlidXRvcnNcIlxuICAgICAgICB9LFxuICAgICAgICBcImNoYW5nZWxvZ1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ2hhbmdlbG9nXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzaWRlYmFyc1wiOiB7XG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJjbGlcIjoge1xuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJsb2dnaW5nXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTG9nZ2luZ1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJzaGVsbC1jb21wbGV0aW9uc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlNoZWxsIGNvbXBsZXRpb25zXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiY29tbWFuZHNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNvbW1hbmRzXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJyZWZlcmVuY2VzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlJlZmVyZW5jZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImV4YW1wbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJFeGFtcGxlc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwibWlncmF0aW9uc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiTWlncmF0aW9uc1wiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJmcm9tLXYzLXRvLXY0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRnJvbSB2MyB0byB2NFwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImNvbnRyaWJ1dG9yc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJDb250cmlidXRvcnNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImdldC1zdGFydGVkXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJHZXQgc3RhcnRlZFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiaXNzdWUtcmVwb3J0aW5nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJJc3N1ZSByZXBvcnRpbmdcIlxuICAgICAgICB9LFxuICAgICAgICBcImNvZGUtcmV2aWV3c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29kZSByZXZpZXdzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJwcmluY2lwbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJQcmluY2lwbGVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlRyYW5zbGF0ZVwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY2xpXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDTElcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibG9nZ2luZ1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkxvZ2dpbmdcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJzZXJ2ZXJcIjoge1xuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiaW50cm9kdWN0aW9uXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJJbnRyb2R1Y3Rpb25cIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwid2h5LXNlcnZlclwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIldoeSBhIHNlcnZlcj9cIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYWNjb3VudHMtYW5kLXByb2plY3RzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQWNjb3VudHMgYW5kIHByb2plY3RzXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImF1dGhlbnRpY2F0aW9uXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQXV0aGVudGljYXRpb25cIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiaW50ZWdyYXRpb25zXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW50ZWdyYXRpb25zXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwib24tcHJlbWlzZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiT24tcHJlbWlzZVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zdGFsbFwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJtZXRyaWNzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTWV0cmljc1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImFwaS1kb2N1bWVudGF0aW9uXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJBUEkgZG9jdW1lbnRhdGlvblwiXG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhdHVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJTdGF0dXNcIlxuICAgICAgICB9LFxuICAgICAgICBcIm1ldHJpY3MtZGFzaGJvYXJkXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJNZXRyaWNzIGRhc2hib2FyZFwiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwiZ3VpZGVzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkd1aWRlc1wiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwidHVpc3RcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlR1aXN0XCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImFib3V0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQWJvdXQgVHVpc3RcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJxdWljay1zdGFydFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiUXVpY2sgc3RhcnRcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiaW5zdGFsbC10dWlzdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3RhbGwgVHVpc3RcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiZ2V0LXN0YXJ0ZWRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJHZXQgc3RhcnRlZFwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImZlYXR1cmVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJSZWN1cnNvc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiZGV2ZWxvcFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiRGV2ZWxvcFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJnZW5lcmF0ZWQtcHJvamVjdHNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJHZW5lcmF0ZWQgcHJvamVjdHNcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJhZG9wdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBZG9wdGlvblwiLFxuICAgICAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgICAgIFwibmV3LXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNyZWF0ZSBhIG5ldyBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgXCJzd2lmdC1wYWNrYWdlXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJUcnkgd2l0aCBhIFN3aWZ0IFBhY2thZ2VcIlxuICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICBcIm1pZ3JhdGVcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1pZ3JhdGVcIixcbiAgICAgICAgICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgIFwieGNvZGUtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFuIFhjb2RlIHByb2plY3RcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkEgU3dpZnQgcGFja2FnZVwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICAgICAgXCJ4Y29kZWdlbi1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQW4gWGNvZGVHZW4gcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICAgICAgXCJiYXplbC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQSBCYXplbCBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwibWFuaWZlc3RzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1hbmlmZXN0c1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImRpcmVjdG9yeS1zdHJ1Y3R1cmVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRGlyZWN0b3J5IHN0cnVjdHVyZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImVkaXRpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRWRpdGluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImRlcGVuZGVuY2llc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJEZXBlbmRlbmNpZXNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJjb2RlLXNoYXJpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29kZSBzaGFyaW5nXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwic3ludGhlc2l6ZWQtZmlsZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU3ludGhlc2l6ZWQgZmlsZXNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkeW5hbWljLWNvbmZpZ3VyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRHluYW1pYyBjb25maWd1cmF0aW9uXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidGVtcGxhdGVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlRlbXBsYXRlc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInBsdWdpbnNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUGx1Z2luc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImhhc2hpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSGFzaGluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImluc3BlY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zcGVjdFwiLFxuICAgICAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgICAgIFwiaW1wbGljaXQtaW1wb3J0c1wiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW1wbGljaXQgaW1wb3J0c1wiXG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidGhlLWNvc3Qtb2YtY29udmVuaWVuY2VcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVGhlIGNvc3Qgb2YgY29udmVuaWVuY2VcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0bWEtYXJjaGl0ZWN0dXJlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1vZHVsYXIgYXJjaGl0ZWN0dXJlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiYmVzdC1wcmFjdGljZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQmVzdCBwcmFjdGljZXNcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiY2FjaGVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJDYWNoZVwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJyZWdpc3RyeVwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlJlZ2lzdHJ5XCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwicmVnaXN0cnlcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUmVnaXN0cnlcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlhjb2RlIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJnZW5lcmF0ZWQtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJHZW5lcmF0ZWQgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInhjb2RlcHJvai1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJYY29kZVByb2otYmFzZWQgaW50ZWdyYXRpb25cIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJzd2lmdC1wYWNrYWdlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlN3aWZ0IHBhY2thZ2VcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJjb250aW51b3VzLWludGVncmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvbnRpbnVvdXMgaW50ZWdyYXRpb25cIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwic2VsZWN0aXZlLXRlc3RpbmdcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJTZWxlY3RpdmUgdGVzdGluZ1wiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcInNlbGVjdGl2ZS10ZXN0aW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlNlbGVjdGl2ZSB0ZXN0aW5nXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwieGNvZGUtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJYY29kZSBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZ2VuZXJhdGVkLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiR2VuZXJhdGVkIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiaW5zaWdodHNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnNpZ2h0c1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJidW5kbGUtc2l6ZVwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkJ1bmRsZSBzaXplXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiaW50ZWdyYXRpb25zXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJJbnRlZ3JhdGlvbnNcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibWNwXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTW9kZWwgQ29udGV4dCBQcm90b2NvbCAoTUNQKVwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJjb250aW51b3VzLWludGVncmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29udGludW91cyBpbnRlZ3JhdGlvblwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcInNoYXJlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJTaGFyZVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJwcmV2aWV3c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlByZXZpZXdzXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH1cbn1cbiIsICJjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9maWxlbmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9pMThuLm1qc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9pbXBvcnRfbWV0YV91cmwgPSBcImZpbGU6Ly8vVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2kxOG4ubWpzXCI7aW1wb3J0IGVuU3RyaW5ncyBmcm9tIFwiLi9zdHJpbmdzL2VuLmpzb25cIjtcbmltcG9ydCBydVN0cmluZ3MgZnJvbSBcIi4vc3RyaW5ncy9ydS5qc29uXCI7XG5pbXBvcnQga29TdHJpbmdzIGZyb20gXCIuL3N0cmluZ3Mva28uanNvblwiO1xuaW1wb3J0IGphU3RyaW5ncyBmcm9tIFwiLi9zdHJpbmdzL2phLmpzb25cIjtcbmltcG9ydCBlc1N0cmluZ3MgZnJvbSBcIi4vc3RyaW5ncy9lcy5qc29uXCI7XG5pbXBvcnQgcHRTdHJpbmdzIGZyb20gXCIuL3N0cmluZ3MvcHQuanNvblwiO1xuXG5jb25zdCBzdHJpbmdzID0ge1xuICBlbjogZW5TdHJpbmdzLFxuICBydTogcnVTdHJpbmdzLFxuICBrbzoga29TdHJpbmdzLFxuICBqYTogamFTdHJpbmdzLFxuICBlczogZXNTdHJpbmdzLFxuICBwdDogcHRTdHJpbmdzLFxufTtcblxuZXhwb3J0IGZ1bmN0aW9uIGxvY2FsaXplZFN0cmluZyhsb2NhbGUsIGtleSkge1xuICBjb25zdCBnZXRTdHJpbmcgPSAobG9jYWxlU3RyaW5ncywga2V5KSA9PiB7XG4gICAgY29uc3Qga2V5cyA9IGtleS5zcGxpdChcIi5cIik7XG4gICAgbGV0IGN1cnJlbnQgPSBsb2NhbGVTdHJpbmdzO1xuXG4gICAgZm9yIChjb25zdCBrIG9mIGtleXMpIHtcbiAgICAgIGlmIChjdXJyZW50ICYmIGN1cnJlbnQuaGFzT3duUHJvcGVydHkoaykpIHtcbiAgICAgICAgY3VycmVudCA9IGN1cnJlbnRba107XG4gICAgICB9IGVsc2Uge1xuICAgICAgICByZXR1cm4gdW5kZWZpbmVkO1xuICAgICAgfVxuICAgIH1cbiAgICByZXR1cm4gY3VycmVudDtcbiAgfTtcblxuICBsZXQgbG9jYWxpemVkVmFsdWUgPSBnZXRTdHJpbmcoc3RyaW5nc1tsb2NhbGVdLCBrZXkpO1xuXG4gIGlmIChsb2NhbGl6ZWRWYWx1ZSA9PT0gdW5kZWZpbmVkICYmIGxvY2FsZSAhPT0gXCJlblwiKSB7XG4gICAgbG9jYWxpemVkVmFsdWUgPSBnZXRTdHJpbmcoc3RyaW5nc1tcImVuXCJdLCBrZXkpO1xuICB9XG5cbiAgcmV0dXJuIGxvY2FsaXplZFZhbHVlO1xufVxuIiwgImNvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ZpbGVuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2JhcnMubWpzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ltcG9ydF9tZXRhX3VybCA9IFwiZmlsZTovLy9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvYmFycy5tanNcIjtpbXBvcnQge1xuICBjdWJlMDJJY29uLFxuICBjdWJlMDFJY29uLFxuICB0dWlzdEljb24sXG4gIGJ1aWxkaW5nMDdJY29uLFxuICBzZXJ2ZXIwNEljb24sXG4gIGJvb2tPcGVuMDFJY29uLFxuICBjb2RlQnJvd3Nlckljb24sXG4gIHN0YXIwNkljb24sXG4gIHBsYXlJY29uLFxufSBmcm9tIFwiLi9pY29ucy5tanNcIjtcbmltcG9ydCB7IGxvYWREYXRhIGFzIGxvYWRFeGFtcGxlc0RhdGEgfSBmcm9tIFwiLi9kYXRhL2V4YW1wbGVzXCI7XG5pbXBvcnQgeyBsb2FkRGF0YSBhcyBsb2FkUHJvamVjdERlc2NyaXB0aW9uRGF0YSB9IGZyb20gXCIuL2RhdGEvcHJvamVjdC1kZXNjcmlwdGlvblwiO1xuaW1wb3J0IHsgbG9jYWxpemVkU3RyaW5nIH0gZnJvbSBcIi4vaTE4bi5tanNcIjtcblxuYXN5bmMgZnVuY3Rpb24gcHJvamVjdERlc2NyaXB0aW9uU2lkZWJhcihsb2NhbGUpIHtcbiAgY29uc3QgcHJvamVjdERlc2NyaXB0aW9uVHlwZXNEYXRhID0gYXdhaXQgbG9hZFByb2plY3REZXNjcmlwdGlvbkRhdGEoKTtcbiAgY29uc3QgcHJvamVjdERlc2NyaXB0aW9uU2lkZWJhciA9IHtcbiAgICB0ZXh0OiBcIlByb2plY3QgRGVzY3JpcHRpb25cIixcbiAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgaXRlbXM6IFtdLFxuICB9O1xuICBmdW5jdGlvbiBjYXBpdGFsaXplKHRleHQpIHtcbiAgICByZXR1cm4gdGV4dC5jaGFyQXQoMCkudG9VcHBlckNhc2UoKSArIHRleHQuc2xpY2UoMSkudG9Mb3dlckNhc2UoKTtcbiAgfVxuICBbXCJzdHJ1Y3RzXCIsIFwiZW51bXNcIiwgXCJleHRlbnNpb25zXCIsIFwidHlwZWFsaWFzZXNcIl0uZm9yRWFjaCgoY2F0ZWdvcnkpID0+IHtcbiAgICBpZiAoXG4gICAgICBwcm9qZWN0RGVzY3JpcHRpb25UeXBlc0RhdGEuZmluZCgoaXRlbSkgPT4gaXRlbS5jYXRlZ29yeSA9PT0gY2F0ZWdvcnkpXG4gICAgKSB7XG4gICAgICBwcm9qZWN0RGVzY3JpcHRpb25TaWRlYmFyLml0ZW1zLnB1c2goe1xuICAgICAgICB0ZXh0OiBjYXBpdGFsaXplKGNhdGVnb3J5KSxcbiAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICBpdGVtczogcHJvamVjdERlc2NyaXB0aW9uVHlwZXNEYXRhXG4gICAgICAgICAgLmZpbHRlcigoaXRlbSkgPT4gaXRlbS5jYXRlZ29yeSA9PT0gY2F0ZWdvcnkpXG4gICAgICAgICAgLm1hcCgoaXRlbSkgPT4gKHtcbiAgICAgICAgICAgIHRleHQ6IGl0ZW0udGl0bGUsXG4gICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9yZWZlcmVuY2VzL3Byb2plY3QtZGVzY3JpcHRpb24vJHtpdGVtLmlkZW50aWZpZXJ9YCxcbiAgICAgICAgICB9KSksXG4gICAgICB9KTtcbiAgICB9XG4gIH0pO1xuICByZXR1cm4gcHJvamVjdERlc2NyaXB0aW9uU2lkZWJhcjtcbn1cblxuZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIHJlZmVyZW5jZXNTaWRlYmFyKGxvY2FsZSkge1xuICByZXR1cm4gW1xuICAgIHtcbiAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhsb2NhbGUsIFwic2lkZWJhcnMucmVmZXJlbmNlcy50ZXh0XCIpLFxuICAgICAgaXRlbXM6IFtcbiAgICAgICAgYXdhaXQgcHJvamVjdERlc2NyaXB0aW9uU2lkZWJhcihsb2NhbGUpLFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5yZWZlcmVuY2VzLml0ZW1zLmV4YW1wbGVzLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGNvbGxhcHNlZDogdHJ1ZSxcbiAgICAgICAgICBpdGVtczogKGF3YWl0IGxvYWRFeGFtcGxlc0RhdGEoKSkubWFwKChpdGVtKSA9PiB7XG4gICAgICAgICAgICByZXR1cm4ge1xuICAgICAgICAgICAgICB0ZXh0OiBpdGVtLnRpdGxlLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9yZWZlcmVuY2VzL2V4YW1wbGVzLyR7aXRlbS5uYW1lfWAsXG4gICAgICAgICAgICB9O1xuICAgICAgICAgIH0pLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5yZWZlcmVuY2VzLml0ZW1zLm1pZ3JhdGlvbnMudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5yZWZlcmVuY2VzLml0ZW1zLm1pZ3JhdGlvbnMuaXRlbXMuZnJvbS12My10by12NC50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L3JlZmVyZW5jZXMvbWlncmF0aW9ucy9mcm9tLXYzLXRvLXY0YCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgXSxcbiAgICAgICAgfSxcbiAgICAgIF0sXG4gICAgfSxcbiAgXTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIG5hdkJhcihsb2NhbGUpIHtcbiAgcmV0dXJuIFtcbiAgICB7XG4gICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj4ke2xvY2FsaXplZFN0cmluZyhcbiAgICAgICAgbG9jYWxlLFxuICAgICAgICBcIm5hdmJhci5ndWlkZXMudGV4dFwiLFxuICAgICAgKX0gJHtib29rT3BlbjAxSWNvbigpfTwvc3Bhbj5gLFxuICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3R1aXN0L2Fib3V0YCxcbiAgICB9LFxuICAgIHtcbiAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7bG9jYWxpemVkU3RyaW5nKFxuICAgICAgICBsb2NhbGUsXG4gICAgICAgIFwibmF2YmFyLmNsaS50ZXh0XCIsXG4gICAgICApfSAke2NvZGVCcm93c2VySWNvbigpfTwvc3Bhbj5gLFxuICAgICAgbGluazogYC8ke2xvY2FsZX0vY2xpL2F1dGhgLFxuICAgIH0sXG4gICAge1xuICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+JHtsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgIGxvY2FsZSxcbiAgICAgICAgXCJuYXZiYXIuc2VydmVyLnRleHRcIixcbiAgICAgICl9ICR7c2VydmVyMDRJY29uKCl9PC9zcGFuPmAsXG4gICAgICBsaW5rOiBgLyR7bG9jYWxlfS9zZXJ2ZXIvaW50cm9kdWN0aW9uL3doeS1hLXNlcnZlcmAsXG4gICAgfSxcbiAgICB7XG4gICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcobG9jYWxlLCBcIm5hdmJhci5yZXNvdXJjZXMudGV4dFwiKSxcbiAgICAgIGl0ZW1zOiBbXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcIm5hdmJhci5yZXNvdXJjZXMuaXRlbXMucmVmZXJlbmNlcy50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9yZWZlcmVuY2VzL3Byb2plY3QtZGVzY3JpcHRpb24vc3RydWN0cy9wcm9qZWN0YCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwibmF2YmFyLnJlc291cmNlcy5pdGVtcy5jb250cmlidXRvcnMudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vY29udHJpYnV0b3JzL2dldC1zdGFydGVkYCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwibmF2YmFyLnJlc291cmNlcy5pdGVtcy5jaGFuZ2Vsb2cudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogXCJodHRwczovL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvcmVsZWFzZXNcIixcbiAgICAgICAgfSxcbiAgICAgIF0sXG4gICAgfSxcbiAgXTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGNvbnRyaWJ1dG9yc1NpZGViYXIobG9jYWxlKSB7XG4gIHJldHVybiBbXG4gICAge1xuICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKGxvY2FsZSwgXCJzaWRlYmFycy5jb250cmlidXRvcnMudGV4dFwiKSxcbiAgICAgIGl0ZW1zOiBbXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmNvbnRyaWJ1dG9ycy5pdGVtcy5nZXQtc3RhcnRlZC50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jb250cmlidXRvcnMvZ2V0LXN0YXJ0ZWRgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5jb250cmlidXRvcnMuaXRlbXMuaXNzdWUtcmVwb3J0aW5nLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2NvbnRyaWJ1dG9ycy9pc3N1ZS1yZXBvcnRpbmdgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5jb250cmlidXRvcnMuaXRlbXMuY29kZS1yZXZpZXdzLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2NvbnRyaWJ1dG9ycy9jb2RlLXJldmlld3NgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5jb250cmlidXRvcnMuaXRlbXMucHJpbmNpcGxlcy50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jb250cmlidXRvcnMvcHJpbmNpcGxlc2AsXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmNvbnRyaWJ1dG9ycy5pdGVtcy50cmFuc2xhdGUudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vY29udHJpYnV0b3JzL3RyYW5zbGF0ZWAsXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcobG9jYWxlLCBcInNpZGViYXJzLmNvbnRyaWJ1dG9ycy5pdGVtcy5jbGkudGV4dFwiKSxcbiAgICAgICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICAgICAgaXRlbXM6IFtcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmNvbnRyaWJ1dG9ycy5pdGVtcy5jbGkuaXRlbXMubG9nZ2luZy50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2NvbnRyaWJ1dG9ycy9jbGkvbG9nZ2luZ2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgIF0sXG4gICAgICAgIH0sXG4gICAgICBdLFxuICAgIH0sXG4gIF07XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBzZXJ2ZXJTaWRlYmFyKGxvY2FsZSkge1xuICByZXR1cm4gW1xuICAgIHtcbiAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7bG9jYWxpemVkU3RyaW5nKFxuICAgICAgICBsb2NhbGUsXG4gICAgICAgIFwic2lkZWJhcnMuc2VydmVyLml0ZW1zLmludHJvZHVjdGlvbi50ZXh0XCIsXG4gICAgICApfSAke3NlcnZlcjA0SWNvbigpfTwvc3Bhbj5gLFxuICAgICAgaXRlbXM6IFtcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuc2VydmVyLml0ZW1zLmludHJvZHVjdGlvbi5pdGVtcy53aHktc2VydmVyLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L3NlcnZlci9pbnRyb2R1Y3Rpb24vd2h5LWEtc2VydmVyYCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuc2VydmVyLml0ZW1zLmludHJvZHVjdGlvbi5pdGVtcy5hY2NvdW50cy1hbmQtcHJvamVjdHMudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vc2VydmVyL2ludHJvZHVjdGlvbi9hY2NvdW50cy1hbmQtcHJvamVjdHNgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMuaW50cm9kdWN0aW9uLml0ZW1zLmF1dGhlbnRpY2F0aW9uLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L3NlcnZlci9pbnRyb2R1Y3Rpb24vYXV0aGVudGljYXRpb25gLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMuaW50cm9kdWN0aW9uLml0ZW1zLmludGVncmF0aW9ucy50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9zZXJ2ZXIvaW50cm9kdWN0aW9uL2ludGVncmF0aW9uc2AsXG4gICAgICAgIH0sXG4gICAgICBdLFxuICAgIH0sXG4gICAge1xuICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+JHtsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgIGxvY2FsZSxcbiAgICAgICAgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMub24tcHJlbWlzZS50ZXh0XCIsXG4gICAgICApfSAke2J1aWxkaW5nMDdJY29uKCl9PC9zcGFuPmAsXG4gICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICBpdGVtczogW1xuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMub24tcHJlbWlzZS5pdGVtcy5pbnN0YWxsLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L3NlcnZlci9vbi1wcmVtaXNlL2luc3RhbGxgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMub24tcHJlbWlzZS5pdGVtcy5tZXRyaWNzLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L3NlcnZlci9vbi1wcmVtaXNlL21ldHJpY3NgLFxuICAgICAgICB9LFxuICAgICAgXSxcbiAgICB9LFxuICAgIHtcbiAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgbG9jYWxlLFxuICAgICAgICBcInNpZGViYXJzLnNlcnZlci5pdGVtcy5hcGktZG9jdW1lbnRhdGlvbi50ZXh0XCIsXG4gICAgICApLFxuICAgICAgbGluazogXCJodHRwczovL3R1aXN0LmRldi9hcGkvZG9jc1wiLFxuICAgIH0sXG4gICAge1xuICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKGxvY2FsZSwgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMuc3RhdHVzLnRleHRcIiksXG4gICAgICBsaW5rOiBcImh0dHBzOi8vc3RhdHVzLnR1aXN0LmlvXCIsXG4gICAgfSxcbiAgICB7XG4gICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgIGxvY2FsZSxcbiAgICAgICAgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMubWV0cmljcy1kYXNoYm9hcmQudGV4dFwiLFxuICAgICAgKSxcbiAgICAgIGxpbms6IFwiaHR0cHM6Ly90dWlzdC5ncmFmYW5hLm5ldC9wdWJsaWMtZGFzaGJvYXJkcy8xZjg1ZjFjMzg5NWU0OGZlYmQwMmNjNzM1MGFkZTJkOVwiLFxuICAgIH0sXG4gIF07XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBndWlkZXNTaWRlYmFyKGxvY2FsZSkge1xuICByZXR1cm4gW1xuICAgIHtcbiAgICAgIHRleHQ6IFwiVHVpc3RcIixcbiAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2AsXG4gICAgICBpdGVtczogW1xuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMudHVpc3QuaXRlbXMuYWJvdXQudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3R1aXN0L2Fib3V0YCxcbiAgICAgICAgfSxcbiAgICAgIF0sXG4gICAgfSxcbiAgICB7XG4gICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj4ke2xvY2FsaXplZFN0cmluZyhcbiAgICAgICAgbG9jYWxlLFxuICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5xdWljay1zdGFydC50ZXh0XCIsXG4gICAgICApfSAke3R1aXN0SWNvbigpfTwvc3Bhbj5gLFxuICAgICAgaXRlbXM6IFtcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLnF1aWNrLXN0YXJ0Lml0ZW1zLmluc3RhbGwtdHVpc3QudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3F1aWNrLXN0YXJ0L2luc3RhbGwtdHVpc3RgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMucXVpY2stc3RhcnQuaXRlbXMuZ2V0LXN0YXJ0ZWQudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3F1aWNrLXN0YXJ0L2dldC1zdGFydGVkYCxcbiAgICAgICAgfSxcbiAgICAgIF0sXG4gICAgfSxcbiAgICB7XG4gICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj4ke2xvY2FsaXplZFN0cmluZyhcbiAgICAgICAgbG9jYWxlLFxuICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5mZWF0dXJlcy50ZXh0XCIsXG4gICAgICApfSAke2N1YmUwMkljb24oKX08L3NwYW4+YCxcbiAgICAgIGl0ZW1zOiBbXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzYCxcbiAgICAgICAgICBpdGVtczogW1xuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLmFkb3B0aW9uLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgICAgICBpdGVtczogW1xuICAgICAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5hZG9wdGlvbi5pdGVtcy5uZXctcHJvamVjdC50ZXh0XCIsXG4gICAgICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL2Fkb3B0aW9uL25ldy1wcm9qZWN0YCxcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5hZG9wdGlvbi5pdGVtcy5zd2lmdC1wYWNrYWdlLnRleHRcIixcbiAgICAgICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvYWRvcHRpb24vc3dpZnQtcGFja2FnZWAsXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICB7XG4gICAgICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5nZW5lcmF0ZWQtcHJvamVjdHMuaXRlbXMuYWRvcHRpb24uaXRlbXMubWlncmF0ZS50ZXh0XCIsXG4gICAgICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgICAgICAgICAgaXRlbXM6IFtcbiAgICAgICAgICAgICAgICAgICAge1xuICAgICAgICAgICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLmFkb3B0aW9uLml0ZW1zLm1pZ3JhdGUuaXRlbXMueGNvZGUtcHJvamVjdC50ZXh0XCIsXG4gICAgICAgICAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvYWRvcHRpb24vbWlncmF0ZS94Y29kZS1wcm9qZWN0YCxcbiAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAge1xuICAgICAgICAgICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLmFkb3B0aW9uLml0ZW1zLm1pZ3JhdGUuaXRlbXMuc3dpZnQtcGFja2FnZS50ZXh0XCIsXG4gICAgICAgICAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvYWRvcHRpb24vbWlncmF0ZS9zd2lmdC1wYWNrYWdlYCxcbiAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAge1xuICAgICAgICAgICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLmFkb3B0aW9uLml0ZW1zLm1pZ3JhdGUuaXRlbXMueGNvZGVnZW4tcHJvamVjdC50ZXh0XCIsXG4gICAgICAgICAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvYWRvcHRpb24vbWlncmF0ZS94Y29kZWdlbi1wcm9qZWN0YCxcbiAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAge1xuICAgICAgICAgICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLmFkb3B0aW9uLml0ZW1zLm1pZ3JhdGUuaXRlbXMuYmF6ZWwtcHJvamVjdC50ZXh0XCIsXG4gICAgICAgICAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvYWRvcHRpb24vbWlncmF0ZS9iYXplbC1wcm9qZWN0YCxcbiAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgIF0sXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgXSxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5nZW5lcmF0ZWQtcHJvamVjdHMuaXRlbXMubWFuaWZlc3RzLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL21hbmlmZXN0c2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLmRpcmVjdG9yeS1zdHJ1Y3R1cmUudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvZGlyZWN0b3J5LXN0cnVjdHVyZWAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLmVkaXRpbmcudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvZWRpdGluZ2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLmRlcGVuZGVuY2llcy50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9wcm9qZWN0cy9kZXBlbmRlbmNpZXNgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5jb2RlLXNoYXJpbmcudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvY29kZS1zaGFyaW5nYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5nZW5lcmF0ZWQtcHJvamVjdHMuaXRlbXMuc3ludGhlc2l6ZWQtZmlsZXMudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvc3ludGhlc2l6ZWQtZmlsZXNgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5keW5hbWljLWNvbmZpZ3VyYXRpb24udGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvZHluYW1pYy1jb25maWd1cmF0aW9uYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5nZW5lcmF0ZWQtcHJvamVjdHMuaXRlbXMudGVtcGxhdGVzLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL3RlbXBsYXRlc2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLnBsdWdpbnMudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvcGx1Z2luc2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLmhhc2hpbmcudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvaGFzaGluZ2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLmluc3BlY3QudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICAgICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAgICAgICAge1xuICAgICAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLmluc3BlY3QuaXRlbXMuaW1wbGljaXQtaW1wb3J0cy50ZXh0XCIsXG4gICAgICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL2luc3BlY3QvaW1wbGljaXQtZGVwZW5kZW5jaWVzYCxcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICBdLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy50aGUtY29zdC1vZi1jb252ZW5pZW5jZS50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9wcm9qZWN0cy9jb3N0LW9mLWNvbnZlbmllbmNlYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5nZW5lcmF0ZWQtcHJvamVjdHMuaXRlbXMudG1hLWFyY2hpdGVjdHVyZS50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9wcm9qZWN0cy90bWEtYXJjaGl0ZWN0dXJlYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5nZW5lcmF0ZWQtcHJvamVjdHMuaXRlbXMuYmVzdC1wcmFjdGljZXMudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvYmVzdC1wcmFjdGljZXNgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICBdLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5jYWNoZS50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvY2FjaGVgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5zZWxlY3RpdmUtdGVzdGluZy50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvc2VsZWN0aXZlLXRlc3RpbmdgLFxuICAgICAgICAgIGNvbGxhcHNlZDogdHJ1ZSxcbiAgICAgICAgICBpdGVtczogW1xuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuc2VsZWN0aXZlLXRlc3RpbmcuaXRlbXMueGNvZGUtcHJvamVjdC50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9zZWxlY3RpdmUtdGVzdGluZy94Y29kZS1wcm9qZWN0YCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5zZWxlY3RpdmUtdGVzdGluZy5pdGVtcy5nZW5lcmF0ZWQtcHJvamVjdC50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9zZWxlY3RpdmUtdGVzdGluZy9nZW5lcmF0ZWQtcHJvamVjdGAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgIF0sXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLnJlZ2lzdHJ5LnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9yZWdpc3RyeWAsXG4gICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5yZWdpc3RyeS5pdGVtcy54Y29kZS1wcm9qZWN0LnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3JlZ2lzdHJ5L3hjb2RlLXByb2plY3RgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLnJlZ2lzdHJ5Lml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0LnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3JlZ2lzdHJ5L2dlbmVyYXRlZC1wcm9qZWN0YCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5yZWdpc3RyeS5pdGVtcy54Y29kZXByb2otaW50ZWdyYXRpb24udGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcmVnaXN0cnkveGNvZGVwcm9qLWludGVncmF0aW9uYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5yZWdpc3RyeS5pdGVtcy5zd2lmdC1wYWNrYWdlLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3JlZ2lzdHJ5L3N3aWZ0LXBhY2thZ2VgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLnJlZ2lzdHJ5Lml0ZW1zLmNvbnRpbnVvdXMtaW50ZWdyYXRpb24udGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcmVnaXN0cnkvY29udGludW91cy1pbnRlZ3JhdGlvbmAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgIF0sXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmluc2lnaHRzLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9pbnNpZ2h0c2AsXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmJ1bmRsZS1zaXplLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9idW5kbGUtc2l6ZWAsXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5zaGFyZS5pdGVtcy5wcmV2aWV3cy50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJldmlld3NgLFxuICAgICAgICB9LFxuICAgICAgXSxcbiAgICB9LFxuICAgIHtcbiAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7bG9jYWxpemVkU3RyaW5nKFxuICAgICAgICBsb2NhbGUsXG4gICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmludGVncmF0aW9ucy50ZXh0XCIsXG4gICAgICApfSAke3BsYXlJY29uKCl9PC9zcGFuPmAsXG4gICAgICBpdGVtczogW1xuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuaW50ZWdyYXRpb25zLml0ZW1zLm1jcC50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvaW50ZWdyYXRpb25zL21jcGAsXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5pbnRlZ3JhdGlvbnMuaXRlbXMuY29udGludW91cy1pbnRlZ3JhdGlvbi50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvaW50ZWdyYXRpb25zL2NvbnRpbnVvdXMtaW50ZWdyYXRpb25gLFxuICAgICAgICB9LFxuICAgICAgXSxcbiAgICB9LFxuICBdO1xufVxuIiwgImNvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2RhdGFcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZmlsZW5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvZGF0YS9jbGkuanNcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfaW1wb3J0X21ldGFfdXJsID0gXCJmaWxlOi8vL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9kYXRhL2NsaS5qc1wiO2ltcG9ydCB7IGV4ZWNhLCAkIH0gZnJvbSBcImV4ZWNhXCI7XG5pbXBvcnQgeyB0ZW1wb3JhcnlEaXJlY3RvcnlUYXNrIH0gZnJvbSBcInRlbXB5XCI7XG5pbXBvcnQgKiBhcyBwYXRoIGZyb20gXCJub2RlOnBhdGhcIjtcbmltcG9ydCB7IGZpbGVVUkxUb1BhdGggfSBmcm9tIFwibm9kZTp1cmxcIjtcbmltcG9ydCBlanMgZnJvbSBcImVqc1wiO1xuaW1wb3J0IHsgbG9jYWxpemVkU3RyaW5nIH0gZnJvbSBcIi4uL2kxOG4ubWpzXCI7XG5cbi8vIFJvb3QgZGlyZWN0b3J5XG5jb25zdCBfX2Rpcm5hbWUgPSBwYXRoLmRpcm5hbWUoZmlsZVVSTFRvUGF0aChpbXBvcnQubWV0YS51cmwpKTtcbmNvbnN0IHJvb3REaXJlY3RvcnkgPSBwYXRoLmpvaW4oX19kaXJuYW1lLCBcIi4uLy4uLy4uXCIpO1xuXG4vLyBTY2hlbWFcbmF3YWl0IGV4ZWNhKHtcbiAgc3RkaW86IFwiaW5oZXJpdFwiLFxufSlgc3dpZnQgYnVpbGQgLS1wcm9kdWN0IFByb2plY3REZXNjcmlwdGlvbiAtLWNvbmZpZ3VyYXRpb24gZGVidWcgLS1wYWNrYWdlLXBhdGggJHtyb290RGlyZWN0b3J5fWA7XG5hd2FpdCBleGVjYSh7XG4gIHN0ZGlvOiBcImluaGVyaXRcIixcbn0pYHN3aWZ0IGJ1aWxkIC0tcHJvZHVjdCB0dWlzdCAtLWNvbmZpZ3VyYXRpb24gZGVidWcgLS1wYWNrYWdlLXBhdGggJHtyb290RGlyZWN0b3J5fWA7XG52YXIgZHVtcGVkQ0xJU2NoZW1hO1xuYXdhaXQgdGVtcG9yYXJ5RGlyZWN0b3J5VGFzayhhc3luYyAodG1wRGlyKSA9PiB7XG4gIC8vIEknbSBwYXNzaW5nIC0tcGF0aCB0byBzYW5kYm94IHRoZSBleGVjdXRpb24gc2luY2Ugd2UgYXJlIG9ubHkgaW50ZXJlc3RlZCBpbiB0aGUgc2NoZW1hIGFuZCBub3RoaW5nIGVsc2UuXG4gIGR1bXBlZENMSVNjaGVtYSA9IGF3YWl0ICRgJHtwYXRoLmpvaW4oXG4gICAgcm9vdERpcmVjdG9yeSxcbiAgICBcIi5idWlsZC9kZWJ1Zy90dWlzdFwiLFxuICApfSAtLWV4cGVyaW1lbnRhbC1kdW1wLWhlbHAgLS1wYXRoICR7dG1wRGlyfWA7XG59KTtcbmNvbnN0IHsgc3Rkb3V0IH0gPSBkdW1wZWRDTElTY2hlbWE7XG5leHBvcnQgY29uc3Qgc2NoZW1hID0gSlNPTi5wYXJzZShzdGRvdXQpO1xuXG4vLyBQYXRoc1xuZnVuY3Rpb24gdHJhdmVyc2UoY29tbWFuZCwgcGF0aHMpIHtcbiAgcGF0aHMucHVzaCh7XG4gICAgcGFyYW1zOiB7IGNvbW1hbmQ6IGNvbW1hbmQubGluay5zcGxpdChcImNsaS9cIilbMV0gfSxcbiAgICBjb250ZW50OiBjb250ZW50KGNvbW1hbmQpLFxuICB9KTtcbiAgKGNvbW1hbmQuaXRlbXMgPz8gW10pLmZvckVhY2goKHN1YkNvbW1hbmQpID0+IHtcbiAgICB0cmF2ZXJzZShzdWJDb21tYW5kLCBwYXRocyk7XG4gIH0pO1xufVxuXG5jb25zdCB0ZW1wbGF0ZSA9IGVqcy5jb21waWxlKFxuICBgXG4jIDwlPSBjb21tYW5kLmZ1bGxDb21tYW5kICU+XG48JT0gY29tbWFuZC5zcGVjLmFic3RyYWN0ICU+XG48JSBpZiAoY29tbWFuZC5zcGVjLmFyZ3VtZW50cyAmJiBjb21tYW5kLnNwZWMuYXJndW1lbnRzLmxlbmd0aCA+IDApIHsgJT5cbiMjIEFyZ3VtZW50c1xuPCUgY29tbWFuZC5zcGVjLmFyZ3VtZW50cy5mb3JFYWNoKGZ1bmN0aW9uKGFyZykgeyAlPlxuIyMjIDwlLSBhcmcudmFsdWVOYW1lICU+IDwlLSAoYXJnLmlzT3B0aW9uYWwpID8gXCI8QmFkZ2UgdHlwZT0naW5mbycgdGV4dD0nT3B0aW9uYWwnIC8+XCIgOiBcIlwiICU+IDwlLSAoYXJnLmlzRGVwcmVjYXRlZCkgPyBcIjxCYWRnZSB0eXBlPSd3YXJuaW5nJyB0ZXh0PSdEZXByZWNhdGVkJyAvPlwiIDogXCJcIiAlPlxuPCUgaWYgKGFyZy5lbnZWYXIpIHsgJT5cbioqRW52aXJvbm1lbnQgdmFyaWFibGUqKiBcXGA8JS0gYXJnLmVudlZhciAlPlxcYFxuPCUgfSAlPlxuPCUtIGFyZy5hYnN0cmFjdCAlPlxuPCUgaWYgKGFyZy5raW5kID09PSBcInBvc2l0aW9uYWxcIikgeyAtJT5cblxcYFxcYFxcYGJhc2hcbjwlLSBjb21tYW5kLmZ1bGxDb21tYW5kICU+IFs8JS0gYXJnLnZhbHVlTmFtZSAlPl1cblxcYFxcYFxcYFxuPCUgfSBlbHNlIGlmIChhcmcua2luZCA9PT0gXCJmbGFnXCIpIHsgLSU+XG5cXGBcXGBcXGBiYXNoXG48JSBhcmcubmFtZXMuZm9yRWFjaChmdW5jdGlvbihuYW1lKSB7IC0lPlxuPCUgaWYgKG5hbWUua2luZCA9PT0gXCJsb25nXCIpIHsgLSU+XG48JS0gY29tbWFuZC5mdWxsQ29tbWFuZCAlPiAtLTwlLSBuYW1lLm5hbWUgJT5cbjwlIH0gZWxzZSB7IC0lPlxuPCUtIGNvbW1hbmQuZnVsbENvbW1hbmQgJT4gLTwlLSBuYW1lLm5hbWUgJT5cbjwlIH0gLSU+XG48JSB9KSAtJT5cblxcYFxcYFxcYFxuPCUgfSBlbHNlIGlmIChhcmcua2luZCA9PT0gXCJvcHRpb25cIikgeyAtJT5cblxcYFxcYFxcYGJhc2hcbjwlIGFyZy5uYW1lcy5mb3JFYWNoKGZ1bmN0aW9uKG5hbWUpIHsgLSU+XG48JSBpZiAobmFtZS5raW5kID09PSBcImxvbmdcIikgeyAtJT5cbjwlLSBjb21tYW5kLmZ1bGxDb21tYW5kICU+IC0tPCUtIG5hbWUubmFtZSAlPiBbPCUtIGFyZy52YWx1ZU5hbWUgJT5dXG48JSB9IGVsc2UgeyAtJT5cbjwlLSBjb21tYW5kLmZ1bGxDb21tYW5kICU+IC08JS0gbmFtZS5uYW1lICU+IFs8JS0gYXJnLnZhbHVlTmFtZSAlPl1cbjwlIH0gLSU+XG48JSB9KSAtJT5cblxcYFxcYFxcYFxuPCUgfSAtJT5cbjwlIH0pOyAtJT5cbjwlIH0gLSU+XG5gLFxuICB7fSxcbik7XG5cbmZ1bmN0aW9uIGNvbnRlbnQoY29tbWFuZCkge1xuICBjb25zdCBlbnZWYXJSZWdleCA9IC9cXChlbnY6XFxzKihbXildKylcXCkvO1xuICBjb25zdCBjb250ZW50ID0gdGVtcGxhdGUoe1xuICAgIGNvbW1hbmQ6IHtcbiAgICAgIC4uLmNvbW1hbmQsXG4gICAgICBzcGVjOiB7XG4gICAgICAgIC4uLmNvbW1hbmQuc3BlYyxcbiAgICAgICAgYXJndW1lbnRzOiBjb21tYW5kLnNwZWMuYXJndW1lbnRzLm1hcCgoYXJnKSA9PiB7XG4gICAgICAgICAgY29uc3QgZW52VmFyTWF0Y2ggPSBhcmcuYWJzdHJhY3QubWF0Y2goZW52VmFyUmVnZXgpO1xuICAgICAgICAgIHJldHVybiB7XG4gICAgICAgICAgICAuLi5hcmcsXG4gICAgICAgICAgICBlbnZWYXI6IGVudlZhck1hdGNoID8gZW52VmFyTWF0Y2hbMV0gOiB1bmRlZmluZWQsXG4gICAgICAgICAgICBpc0RlcHJlY2F0ZWQ6XG4gICAgICAgICAgICAgIGFyZy5hYnN0cmFjdC5pbmNsdWRlcyhcIltEZXByZWNhdGVkXVwiKSB8fFxuICAgICAgICAgICAgICBhcmcuYWJzdHJhY3QuaW5jbHVkZXMoXCJbZGVwcmVjYXRlZF1cIiksXG4gICAgICAgICAgICBhYnN0cmFjdDogYXJnLmFic3RyYWN0XG4gICAgICAgICAgICAgIC5yZXBsYWNlKGVudlZhclJlZ2V4LCBcIlwiKVxuICAgICAgICAgICAgICAucmVwbGFjZShcIltEZXByZWNhdGVkXVwiLCBcIlwiKVxuICAgICAgICAgICAgICAucmVwbGFjZShcIltkZXByZWNhdGVkXVwiLCBcIlwiKVxuICAgICAgICAgICAgICAudHJpbSgpXG4gICAgICAgICAgICAgIC5yZXBsYWNlKC88KFtePl0rKT4vZywgXCJcXFxcPCQxXFxcXD5cIiksXG4gICAgICAgICAgfTtcbiAgICAgICAgfSksXG4gICAgICB9LFxuICAgIH0sXG4gIH0pO1xuICByZXR1cm4gY29udGVudDtcbn1cblxuZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIHBhdGhzKGxvY2FsZSkge1xuICBsZXQgcGF0aHMgPSBbXTtcbiAgKGF3YWl0IGxvYWREYXRhKGxvY2FsZSkpLml0ZW1zWzBdLml0ZW1zLmZvckVhY2goKGNvbW1hbmQpID0+IHtcbiAgICB0cmF2ZXJzZShjb21tYW5kLCBwYXRocyk7XG4gIH0pO1xuICByZXR1cm4gcGF0aHM7XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiBjbGlTaWRlYmFyKGxvY2FsZSkge1xuICBjb25zdCBzaWRlYmFyID0gYXdhaXQgbG9hZERhdGEobG9jYWxlKTtcbiAgcmV0dXJuIHtcbiAgICAuLi5zaWRlYmFyLFxuICAgIGl0ZW1zOiBbXG4gICAgICB7XG4gICAgICAgIHRleHQ6IFwiQ0xJXCIsXG4gICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAge1xuICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgIFwic2lkZWJhcnMuY2xpLml0ZW1zLmNsaS5pdGVtcy5sb2dnaW5nLnRleHRcIixcbiAgICAgICAgICAgICksXG4gICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jbGkvbG9nZ2luZ2AsXG4gICAgICAgICAgfSxcbiAgICAgICAgICB7XG4gICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgXCJzaWRlYmFycy5jbGkuaXRlbXMuY2xpLml0ZW1zLnNoZWxsLWNvbXBsZXRpb25zLnRleHRcIixcbiAgICAgICAgICAgICksXG4gICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jbGkvc2hlbGwtY29tcGxldGlvbnNgLFxuICAgICAgICAgIH0sXG4gICAgICAgIF0sXG4gICAgICB9LFxuICAgICAgLi4uc2lkZWJhci5pdGVtcyxcbiAgICBdLFxuICB9O1xufVxuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gbG9hZERhdGEobG9jYWxlKSB7XG4gIGZ1bmN0aW9uIHBhcnNlQ29tbWFuZChcbiAgICBjb21tYW5kLFxuICAgIHBhcmVudENvbW1hbmQgPSBcInR1aXN0XCIsXG4gICAgcGFyZW50UGF0aCA9IGAvJHtsb2NhbGV9L2NsaS9gLFxuICApIHtcbiAgICBjb25zdCBvdXRwdXQgPSB7XG4gICAgICB0ZXh0OiBjb21tYW5kLmNvbW1hbmROYW1lLFxuICAgICAgZnVsbENvbW1hbmQ6IHBhcmVudENvbW1hbmQgKyBcIiBcIiArIGNvbW1hbmQuY29tbWFuZE5hbWUsXG4gICAgICBsaW5rOiBwYXRoLmpvaW4ocGFyZW50UGF0aCwgY29tbWFuZC5jb21tYW5kTmFtZSksXG4gICAgICBzcGVjOiBjb21tYW5kLFxuICAgIH07XG4gICAgaWYgKGNvbW1hbmQuc3ViY29tbWFuZHMgJiYgY29tbWFuZC5zdWJjb21tYW5kcy5sZW5ndGggIT09IDApIHtcbiAgICAgIG91dHB1dC5pdGVtcyA9IGNvbW1hbmQuc3ViY29tbWFuZHMubWFwKChzdWJjb21tYW5kKSA9PiB7XG4gICAgICAgIHJldHVybiBwYXJzZUNvbW1hbmQoXG4gICAgICAgICAgc3ViY29tbWFuZCxcbiAgICAgICAgICBwYXJlbnRDb21tYW5kICsgXCIgXCIgKyBjb21tYW5kLmNvbW1hbmROYW1lLFxuICAgICAgICAgIHBhdGguam9pbihwYXJlbnRQYXRoLCBjb21tYW5kLmNvbW1hbmROYW1lKSxcbiAgICAgICAgKTtcbiAgICAgIH0pO1xuICAgIH1cblxuICAgIHJldHVybiBvdXRwdXQ7XG4gIH1cblxuICBjb25zdCB7XG4gICAgY29tbWFuZDogeyBzdWJjb21tYW5kcyB9LFxuICB9ID0gc2NoZW1hO1xuXG4gIHJldHVybiB7XG4gICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKGxvY2FsZSwgXCJzaWRlYmFycy5jbGkudGV4dFwiKSxcbiAgICBpdGVtczogW1xuICAgICAge1xuICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcobG9jYWxlLCBcInNpZGViYXJzLmNsaS5pdGVtcy5jb21tYW5kcy50ZXh0XCIpLFxuICAgICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICAgIGl0ZW1zOiBzdWJjb21tYW5kc1xuICAgICAgICAgIC5tYXAoKGNvbW1hbmQpID0+IHtcbiAgICAgICAgICAgIHJldHVybiB7XG4gICAgICAgICAgICAgIC4uLnBhcnNlQ29tbWFuZChjb21tYW5kKSxcbiAgICAgICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgICAgfTtcbiAgICAgICAgICB9KVxuICAgICAgICAgIC5zb3J0KChhLCBiKSA9PiBhLnRleHQubG9jYWxlQ29tcGFyZShiLnRleHQpKSxcbiAgICAgIH0sXG4gICAgXSxcbiAgfTtcbn1cbiJdLAogICJtYXBwaW5ncyI6ICI7QUFBd1YsU0FBUyxvQkFBb0I7QUFDclgsWUFBWUEsV0FBVTtBQUN0QixZQUFZQyxTQUFROzs7QUNGeVUsU0FBUyxTQUFTLE9BQU8sSUFBSTtBQUN4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QUFBQSxjQUNBLE1BQU0sSUFBSSxNQUFNO0FBQUEsWUFDbEI7QUFBQSxZQUNBO0FBQUEsY0FDRSxNQUFNO0FBQUEsZ0JBQ0o7QUFBQSxnQkFDQTtBQUFBLGNBQ0Y7QUFBQSxjQUNBLE1BQU0sSUFBSSxNQUFNO0FBQUEsWUFDbEI7QUFBQSxZQUNBO0FBQUEsY0FDRSxNQUFNO0FBQUEsZ0JBQ0o7QUFBQSxnQkFDQTtBQUFBLGNBQ0Y7QUFBQSxjQUNBLE1BQU0sSUFBSSxNQUFNO0FBQUEsWUFDbEI7QUFBQSxZQUNBO0FBQUEsY0FDRSxNQUFNO0FBQUEsZ0JBQ0o7QUFBQSxnQkFDQTtBQUFBLGNBQ0Y7QUFBQSxjQUNBLE1BQU0sSUFBSSxNQUFNO0FBQUEsWUFDbEI7QUFBQSxZQUNBO0FBQUEsY0FDRSxNQUFNO0FBQUEsZ0JBQ0o7QUFBQSxnQkFDQTtBQUFBLGNBQ0Y7QUFBQSxjQUNBLE1BQU0sSUFBSSxNQUFNO0FBQUEsWUFDbEI7QUFBQSxZQUNBO0FBQUEsY0FDRSxNQUFNO0FBQUEsZ0JBQ0o7QUFBQSxnQkFDQTtBQUFBLGNBQ0Y7QUFBQSxjQUNBLE1BQU0sSUFBSSxNQUFNO0FBQUEsWUFDbEI7QUFBQSxZQUNBO0FBQUEsY0FDRSxNQUFNO0FBQUEsZ0JBQ0o7QUFBQSxnQkFDQTtBQUFBLGNBQ0Y7QUFBQSxjQUNBLE1BQU0sSUFBSSxNQUFNO0FBQUEsWUFDbEI7QUFBQSxZQUNBO0FBQUEsY0FDRSxNQUFNO0FBQUEsZ0JBQ0o7QUFBQSxnQkFDQTtBQUFBLGNBQ0Y7QUFBQSxjQUNBLE1BQU0sSUFBSSxNQUFNO0FBQUEsWUFDbEI7QUFBQSxZQUNBO0FBQUEsY0FDRSxNQUFNO0FBQUEsZ0JBQ0o7QUFBQSxnQkFDQTtBQUFBLGNBQ0Y7QUFBQSxjQUNBLE1BQU0sSUFBSSxNQUFNO0FBQUEsWUFDbEI7QUFBQSxZQUNBO0FBQUEsY0FDRSxNQUFNO0FBQUEsZ0JBQ0o7QUFBQSxnQkFDQTtBQUFBLGNBQ0Y7QUFBQSxjQUNBLE1BQU0sSUFBSSxNQUFNO0FBQUEsWUFDbEI7QUFBQSxZQUNBO0FBQUEsY0FDRSxNQUFNO0FB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QUEsY0FDQTtBQUFBLGNBQ0E7QUFBQSxjQUNBO0FBQUEsY0FDQTtBQUFBLGNBQ0E7QUFBQSxjQUNBO0FBQUEsY0FDQTtBQUFBLGNBQ0E7QUFBQSxjQUNBO0FBQUEsY0FDQTtBQUFBLGNBQ0E7QUFBQSxjQUNBO0FBQUEsY0FDQTtBQUFBLGNBQ0E7QUFBQSxjQUNBO0FBQUEsY0FDQTtBQUFBLGNBQ0E7QUFBQSxjQUNBO0FBQUEsY0FDQTtBQUFBLGNBQ0E7QUFBQSxjQUNBO0FBQUEsY0FDQTtBQUFBLGNBQ0E7QUFBQSxjQUNBO0FBQUEsY0FDQTtBQUFBLGNBQ0E7QUFBQSxjQUNBO0FBQUEsY0FDQTtBQUFBLFlBQ0Y7QUFBQSxZQUNBLFVBQVU7QUFBQSxZQUNWLHNCQUFzQjtBQUFBLFlBQ3RCLGVBQWU7QUFBQSxjQUNiO0FBQUEsY0FDQTtBQUFBLGNBQ0E7QUFBQSxZQUNGO0FBQUEsWUFDQSxTQUFTO0FBQUEsY0FDUDtBQUFBLGNBQ0E7QUFBQSxjQUNBO0FBQUEsY0FDQTtBQUFBLGNBQ0E7QUFBQSxjQUNBO0FBQUEsY0FDQTtBQUFBLFlBQ0Y7QUFBQSxZQUNBLGlCQUNFO0FBQUEsWUFDRixrQkFBa0I7QUFBQSxZQUNsQixxQkFBcUI7QUFBQSxZQUNyQixzQkFBc0I7QUFBQSxZQUN0QiwyQkFBMkI7QUFBQSxZQUMzQixjQUFjO0FBQUEsWUFDZCxlQUFlO0FBQUEsWUFDZixnQkFBZ0I7QUFBQSxZQUNoQix5Q0FBeUM7QUFBQSxZQUN6Qyx3QkFBd0I7QUFBQSxVQUMxQjtBQUFBLFFBQ0Y7QUFBQSxNQUNGO0FBQUEsSUFDRjtBQUFBLElBQ0EsVUFBVTtBQUFBLE1BQ1IsU0FBUztBQUFBLElBQ1g7QUFBQSxJQUNBLGFBQWE7QUFBQSxNQUNYLEVBQUUsTUFBTSxVQUFVLE1BQU0saUNBQWlDO0FBQUEsTUFDekQsRUFBRSxNQUFNLFlBQVksTUFBTSwrQkFBK0I7QUFBQSxNQUN6RCxFQUFFLE1BQU0sV0FBVyxNQUFNLHFDQUFxQztBQUFBLE1BQzlEO0FBQUEsUUFDRSxNQUFNO0FBQUEsUUFDTixNQUFNO0FBQUEsTUFDUjtBQUFBLElBQ0Y7QUFBQSxJQUNBLFFBQVE7QUFBQSxNQUNOLFNBQVM7QUFBQSxNQUNULFdBQVc7QUFBQSxJQUNiO0FBQUEsRUFDRjtBQUNGLENBQUM7IiwKICAibmFtZXMiOiBbInBhdGgiLCAiZnMiLCAicGF0aCIsICJmZyIsICJmcyIsICJfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSIsICJsb2FkRGF0YSIsICJfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSIsICJmZyIsICJmcyIsICJrZXkiLCAibG9hZERhdGEiLCAicHJvamVjdERlc2NyaXB0aW9uU2lkZWJhciIsICJwYXRoIiwgImxvYWREYXRhIiwgIl9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lIiwgIl9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lIiwgIiQiXQp9Cg==
