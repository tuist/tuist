// .vitepress/config.mjs
import { defineConfig } from "file:///Users/pepicrft/src/github.com/tuist/tuist/node_modules/.pnpm/vitepress@1.6.3_@algolia+client-search@5.28.0_postcss@8.5.6_search-insights@2.17.3/node_modules/vitepress/dist/node/index.js";
import * as path5 from "node:path";
import * as fs4 from "node:fs/promises";

// .vitepress/icons.mjs
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
function cacheIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-database"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="m3 5 0 14c0 1.66 4.03 3 9 3s9-1.34 9-3V5"/><path d="M3 12c0 1.66 4.03 3 9 3s9-1.34 9-3"/></svg>`;
}
function testIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-check-circle"><path d="M12 22c5.523 0 10-4.477 10-10S17.523 2 12 2 2 6.477 2 12s4.477 10 10 10z"/><path d="m9 12 2 2 4-4"/></svg>`;
}
function registryIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-package"><path d="m7.5 4.27 9 5.15"/><path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/></svg>`;
}
function insightsIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-bar-chart-3"><path d="M3 3v18h18"/><path d="m19 9-5 5-4-4-3 3"/></svg>`;
}
function bundleSizeIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-scale"><path d="m16 16 3-8 3 8c-.87.65-1.92 1-3 1s-2.13-.35-3-1Z"/><path d="m2 16 3-8 3 8c-.87.65-1.92 1-3 1s-2.13-.35-3-1Z"/><path d="M7 21h10"/><path d="M12 3v18"/><path d="M3 7h2c2 0 5-1 7-2 2 1 5 2 7 2h2"/></svg>`;
}
function previewsIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-eye"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/></svg>`;
}
function projectsIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-folder-tree"><path d="M20 10a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1h-2.5a1 1 0 0 1-.8-.4l-.9-1.2A1 1 0 0 0 15 3h-2a1 1 0 0 0-1 1v5a1 1 0 0 0 1 1Z"/><path d="M20 21a1 1 0 0 0 1-1v-3a1 1 0 0 0-1-1h-2.5a1 1 0 0 1-.8-.4l-.9-1.2a1 1 0 0 0-.8-.4H13a1 1 0 0 0-1 1v5a1 1 0 0 0 1 1Z"/><path d="M3 5a2 2 0 0 0 2 2h3"/><path d="M3 3v13a2 2 0 0 0 2 2h3"/></svg>`;
}
function mcpIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-plug"><path d="M12 22v-5"/><path d="M9 8V2"/><path d="M15 8V2"/><path d="M18 8v5a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V8Z"/></svg>`;
}
function ciIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-workflow"><rect width="8" height="8" x="3" y="3" rx="2"/><path d="M7 11v4a2 2 0 0 0 2 2h4"/><rect width="8" height="8" x="13" y="13" rx="2"/></svg>`;
}
function githubIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-git-branch"><line x1="6" x2="6" y1="3" y2="15"/><circle cx="18" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="m18 9a9 9 0 0 1-9 9"/></svg>`;
}
function ssoIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-shield-check"><path d="M20 13c0 5-3.5 7.5-8 10.5C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.5-2.5a1 1 0 0 1 1 0C14.5 3.8 17 5 19 5a1 1 0 0 1 1 1Z"/><path d="m9 12 2 2 4-4"/></svg>`;
}
function accountsIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-users"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>`;
}
function authIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-key"><path d="m15.5 7.5 2.3 2.3a1 1 0 0 0 1.4 0l2.1-2.1a1 1 0 0 0 0-1.4L19 4"/><path d="m21 2-9.6 9.6"/><circle cx="7.5" cy="15.5" r="5.5"/></svg>`;
}
function installIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-download"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7,10 12,15 17,10"/><line x1="12" x2="12" y1="15" y2="3"/></svg>`;
}
function telemetryIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-activity"><path d="m22 12-4-4-4 4-4-4-4 4"/><path d="M16 8l2-2 2 2"/></svg>`;
}
function gitForgesIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-git-merge"><circle cx="18" cy="18" r="3"/><circle cx="6" cy="6" r="3"/><path d="M6 21V9a9 9 0 0 0 9 9"/></svg>`;
}
function selfHostingIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-server"><rect width="20" height="8" x="2" y="2"/><rect width="20" height="8" x="2" y="14"/><line x1="6" x2="6.01" y1="6" y2="6"/><line x1="6" x2="6.01" y1="18" y2="18"/></svg>`;
}
function installTuistIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-download-cloud"><path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242"/><path d="M12 12v9"/><path d="m8 17 4 4 4-4"/></svg>`;
}
function getStartedIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-rocket"><path d="M4.5 16.5c-1.5 1.26-2 5-2 5s3.74-.5 5-2c.71-.84.7-2.13-.09-2.91a2.18 2.18 0 0 0-2.91-.09z"/><path d="m12 15-3-3a22 22 0 0 1 2-3.95A12.88 12.88 0 0 1 22 2c0 2.72-.78 7.5-6 11a22.35 22.35 0 0 1-4 2z"/><path d="M9 12H4s.55-3.03 2-4c1.62-1.08 5 0 5 0"/><path d="M12 15v5s3.03-.55 4-2c1.08-1.62 0-5 0-5"/></svg>`;
}
function agenticBuildingIcon() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-cpu"><rect width="16" height="16" x="4" y="4" rx="2"/><rect width="6" height="6" x="9" y="9" rx="1"/><path d="m15 2 0 4"/><path d="m15 18 0 4"/><path d="m2 15 4 0"/><path d="m18 15 4 0"/><path d="m9 2 0 4"/><path d="m9 18 0 4"/><path d="m2 9 4 0"/><path d="m18 9 4 0"/></svg>`;
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
        "agentic-coding": {
          text: "Agentic Coding",
          items: {
            mcp: {
              text: "MCP"
            }
          }
        },
        integrations: {
          text: "Integrations",
          items: {
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
        "agentic-coding": {
          text: "\u0410\u0433\u0435\u043D\u0442\u043D\u043E\u0435 \u041A\u043E\u0434\u0438\u0440\u043E\u0432\u0430\u043D\u0438\u0435",
          items: {
            mcp: {
              text: "\u041F\u0440\u043E\u0442\u043E\u043A\u043E\u043B \u043A\u043E\u043D\u0442\u0435\u043A\u0441\u0442\u0430 \u043C\u043E\u0434\u0435\u043B\u0438 (MCP)"
            }
          }
        },
        integrations: {
          text: "Integrations",
          items: {
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
        "agentic-coding": {
          text: "\uC5D0\uC774\uC804\uD2F1 \uCF54\uB529",
          items: {
            mcp: {
              text: "Model Context Protocol (MCP)"
            }
          }
        },
        integrations: {
          text: "Integrations",
          items: {
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
        "agentic-coding": {
          text: "\u30A8\u30FC\u30B8\u30A7\u30F3\u30C6\u30A3\u30C3\u30AF\u30FB\u30B3\u30FC\u30C7\u30A3\u30F3\u30B0",
          items: {
            mcp: {
              text: "\u30E2\u30C7\u30EB\u30B3\u30F3\u30C6\u30AD\u30B9\u30C8\u30D7\u30ED\u30C8\u30B3\u30EB(MCP)"
            }
          }
        },
        integrations: {
          text: "Integrations",
          items: {
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
        "agentic-coding": {
          text: "Codificaci\xF3n Ag\xE9ntica",
          items: {
            mcp: {
              text: "Model Context Protocol (MCP)"
            }
          }
        },
        integrations: {
          text: "Integrations",
          items: {
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
        "agentic-coding": {
          text: "Codifica\xE7\xE3o Ag\xEAntica",
          items: {
            mcp: {
              text: "Model Context Protocol (MCP)"
            }
          }
        },
        integrations: {
          text: "Integrations",
          items: {
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
      text: localizedString(
        locale,
        "sidebars.guides.items.quick-start.text"
      ),
      items: [
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${installTuistIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.quick-start.items.install-tuist.text"
          )}</span>`,
          link: `/${locale}/guides/quick-start/install-tuist`
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${getStartedIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.quick-start.items.get-started.text"
          )}</span>`,
          link: `/${locale}/guides/quick-start/get-started`
        }
      ]
    },
    {
      text: localizedString(
        locale,
        "sidebars.guides.items.features.text"
      ),
      items: [
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${projectsIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.develop.items.generated-projects.text"
          )}</span>`,
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
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${cacheIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.develop.items.cache.text"
          )}</span>`,
          link: `/${locale}/guides/features/cache`
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${testIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.develop.items.selective-testing.text"
          )}</span>`,
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
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${registryIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.develop.items.registry.text"
          )}</span>`,
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
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${insightsIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.develop.items.insights.text"
          )}</span>`,
          link: `/${locale}/guides/features/insights`
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${bundleSizeIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.develop.items.bundle-size.text"
          )}</span>`,
          link: `/${locale}/guides/features/bundle-size`
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${previewsIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.share.items.previews.text"
          )}</span>`,
          link: `/${locale}/guides/features/previews`
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${agenticBuildingIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.agentic-coding.text"
          )}</span>`,
          collapsed: true,
          items: [
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${mcpIcon()} ${localizedString(
                locale,
                "sidebars.guides.items.agentic-coding.items.mcp.text"
              )}</span>`,
              link: `/${locale}/guides/features/agentic-coding/mcp`
            }
          ]
        }
      ]
    },
    {
      text: localizedString(
        locale,
        "sidebars.guides.items.integrations.text"
      ),
      items: [
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${ciIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.integrations.items.continuous-integration.text"
          )}</span>`,
          link: `/${locale}/guides/integrations/continuous-integration`
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${ssoIcon()} SSO</span>`,
          link: `/${locale}/guides/integrations/sso`
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${gitForgesIcon()} Git forges</span>`,
          collapsed: true,
          items: [
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${githubIcon()} GitHub</span>`,
              link: `/${locale}/guides/integrations/gitforge/github`
            }
          ]
        }
      ]
    },
    {
      text: "Server",
      items: [
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${accountsIcon()} Accounts and projects</span>`,
          link: `/${locale}/guides/server/accounts-and-projects`
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${authIcon()} Authentication</span>`,
          link: `/${locale}/guides/server/authentication`
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${selfHostingIcon()} Self-hosting</span>`,
          collapsed: true,
          items: [
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${installIcon()} Installation</span>`,
              link: `/${locale}/guides/server/self-host/install`
            },
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${telemetryIcon()} Telemetry</span>`,
              link: `/${locale}/guides/server/self-host/telemetry`
            }
          ]
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

// .vitepress/linkValidator.mjs
import * as fs3 from "node:fs";
import * as path4 from "node:path";
var SUPPORTED_LANGUAGES = ["en", "es", "ja", "ko", "pt", "ru"];
var LocalizedLinkValidator = class {
  constructor(srcDir) {
    this.srcDir = srcDir;
    this.linkRegistry = /* @__PURE__ */ new Map();
    this.brokenLinks = [];
    this.validatedLinks = /* @__PURE__ */ new Set();
  }
  /**
   * Scans all markdown files and extracts LocalizedLink href values
   */
  async scanFiles() {
    console.log("\u{1F50D} Scanning files for LocalizedLink components...");
    for (const lang of SUPPORTED_LANGUAGES) {
      const langDir = path4.join(this.srcDir, lang);
      if (fs3.existsSync(langDir)) {
        await this.scanDirectory(langDir, lang);
      }
    }
    console.log(`\u{1F4CA} Found ${this.linkRegistry.size} unique LocalizedLink references`);
  }
  /**
   * Recursively scans a directory for markdown files
   */
  async scanDirectory(dir, lang) {
    const entries = fs3.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path4.join(dir, entry.name);
      if (entry.isDirectory()) {
        await this.scanDirectory(fullPath, lang);
      } else if (entry.isFile() && entry.name.endsWith(".md")) {
        await this.scanFile(fullPath, lang);
      }
    }
  }
  /**
   * Scans a markdown file for LocalizedLink components
   */
  async scanFile(filePath, lang) {
    const content = fs3.readFileSync(filePath, "utf8");
    const localizedLinkRegex = /<LocalizedLink\s+href="([^"]+)"/g;
    let match;
    while ((match = localizedLinkRegex.exec(content)) !== null) {
      const href = match[1];
      if (!this.linkRegistry.has(href)) {
        this.linkRegistry.set(href, []);
      }
      this.linkRegistry.get(href).push({
        file: filePath,
        lang
      });
    }
  }
  /**
   * Validates all collected links
   */
  async validateLinks() {
    console.log("\u2705 Validating LocalizedLink href values...");
    for (const [href, occurrences] of this.linkRegistry) {
      const isValid = await this.validateLink(href);
      if (!isValid) {
        this.brokenLinks.push({
          href,
          occurrences
        });
      }
    }
    if (this.brokenLinks.length > 0) {
      console.error(`\u274C Found ${this.brokenLinks.length} broken LocalizedLink references:`);
      for (const { href, occurrences } of this.brokenLinks) {
        console.error(`
\u{1F517} Broken link: ${href}`);
        console.error(`   Used in ${occurrences.length} file(s):`);
        for (const { file, lang } of occurrences) {
          const relativePath = path4.relative(this.srcDir, file);
          console.error(`   - [${lang}] ${relativePath}`);
        }
        const suggestion = this.suggestCorrection(href);
        if (suggestion) {
          console.error(`   \u{1F4A1} Suggested fix: ${suggestion}`);
        }
      }
      throw new Error(`Build failed: ${this.brokenLinks.length} broken LocalizedLink references found`);
    } else {
      console.log("\u2705 All LocalizedLink references are valid!");
    }
  }
  /**
   * Validates a single link href
   */
  async validateLink(href) {
    if (this.validatedLinks.has(href)) {
      return true;
    }
    const [pathPart] = href.split("#");
    if (this.isDynamicRoute(pathPart)) {
      return this.validateDynamicRoute(pathPart);
    }
    for (const lang of SUPPORTED_LANGUAGES) {
      const fullPath = path4.join(this.srcDir, lang, pathPart);
      const mdPath = fullPath.endsWith(".md") ? fullPath : `${fullPath}.md`;
      if (fs3.existsSync(mdPath)) {
        this.validatedLinks.add(href);
        return true;
      }
      const indexPath = path4.join(fullPath, "index.md");
      if (fs3.existsSync(indexPath)) {
        this.validatedLinks.add(href);
        return true;
      }
    }
    return false;
  }
  /**
   * Checks if a path is a dynamic route
   */
  isDynamicRoute(pathPart) {
    return pathPart.includes("[") && pathPart.includes("]");
  }
  /**
   * Validates dynamic routes by checking if the pattern exists
   */
  validateDynamicRoute(pathPart) {
    const dynamicPattern = pathPart.replace(/\[.*?\]/g, "[*]");
    for (const lang of SUPPORTED_LANGUAGES) {
      const langDir = path4.join(this.srcDir, lang);
      if (this.findDynamicPattern(langDir, pathPart)) {
        return true;
      }
    }
    return false;
  }
  /**
   * Recursively searches for dynamic route patterns
   */
  findDynamicPattern(dir, pattern) {
    if (!fs3.existsSync(dir)) return false;
    const parts = pattern.split("/").filter(Boolean);
    let currentDir = dir;
    for (const part of parts) {
      if (part.startsWith("[") && part.endsWith("]")) {
        const entries = fs3.readdirSync(currentDir, { withFileTypes: true });
        const found = entries.find(
          (entry) => entry.name.startsWith("[") && entry.name.includes("]")
        );
        if (!found) return false;
        currentDir = path4.join(currentDir, found.name);
      } else {
        currentDir = path4.join(currentDir, part);
        if (!fs3.existsSync(currentDir)) return false;
      }
    }
    return true;
  }
  /**
   * Suggests corrections for broken links
   */
  suggestCorrection(href) {
    const corrections = /* @__PURE__ */ new Map([
      ["/server/introduction/accounts-and-projects", "/guides/server/accounts-and-projects"],
      ["/server/introduction/integrations#git-platforms", "/guides/server/authentication"],
      ["/server/introduction/why-a-server", "/guides/tuist/about"],
      ["/guides/automate/continuous-integration", "/guides/integrations/continuous-integration"],
      ["/guides/features/automate/continuous-integration", "/guides/integrations/continuous-integration"],
      ["/guides/features/build/cache", "/guides/features/cache"],
      ["/guides/features/cache.html#supported-products", "/guides/features/cache#supported-products"],
      ["/guides/features/inspect/implicit-dependencies", "/guides/features/projects/inspect/implicit-dependencies"],
      ["/guides/start/new-project", "/guides/features/projects/adoption/new-project"],
      ["/guides/features/test", "/guides/features/selective-testing"],
      ["/guides/features/test/selective-testing", "/guides/features/selective-testing"],
      ["/guides/features/selective-testing/xcodebuild", "/guides/features/selective-testing/xcode-project"],
      ["/contributors/principles.html#default-to-conventions", "/contributors/principles#default-to-conventions"]
    ]);
    return corrections.get(href) || null;
  }
};

// .vitepress/config.mjs
var __vite_injected_original_dirname3 = "/Users/pepicrft/src/github.com/tuist/tuist/docs/.vitepress";
async function themeConfig(locale) {
  const sidebar = {};
  sidebar[`/${locale}/contributors`] = contributorsSidebar(locale);
  sidebar[`/${locale}/guides/`] = guidesSidebar(locale);
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
    const redirectsPath = path5.join(outDir, "_redirects");
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
/:locale/guides/features/mcp /:locale/guides/features/agentic-coding/mcp 301
/:locale/guides/features/agentic-building/mcp /:locale/guides/features/agentic-coding/mcp 301
/:locale/guides/environments/continuous-integration /:locale/guides/integrations/continuous-integration 301
/:locale/guides/environments/automate/continuous-integration /:locale/guides/integrations/continuous-integration 301
/:locale/server/introduction/accounts-and-projects /:locale/guides/server/accounts-and-projects 301
/:locale/server/introduction/authentication /:locale/guides/server/authentication 301
/:locale/server/introduction/integrations /:locale/guides/integrations/gitforge/github 301
/:locale/server/on-premise/install /:locale/guides/server/self-host/install 301
/:locale/server/on-premise/metrics /:locale/guides/server/self-host/telemetry 301
/:locale/guides/server/install /:locale/guides/server/self-host/install 301
/:locale/guides/server/metrics /:locale/guides/server/self-host/telemetry 301
/:locale/server /:locale/guides/server/accounts-and-projects 301
${await fs4.readFile(path5.join(__vite_injected_original_dirname3, "locale-redirects.txt"), {
      encoding: "utf-8"
    })}
    `;
    fs4.writeFile(redirectsPath, redirects);
    console.log("\u{1F50D} Validating LocalizedLink components...");
    const srcDir = path5.join(path5.dirname(outDir), "docs");
    const validator = new LocalizedLinkValidator(srcDir);
    await validator.scanFiles();
    await validator.validateLinks();
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
//# sourceMappingURL=data:application/json;base64,ewogICJ2ZXJzaW9uIjogMywKICAic291cmNlcyI6IFsiLnZpdGVwcmVzcy9jb25maWcubWpzIiwgIi52aXRlcHJlc3MvaWNvbnMubWpzIiwgIi52aXRlcHJlc3MvZGF0YS9leGFtcGxlcy5qcyIsICIudml0ZXByZXNzL2RhdGEvcHJvamVjdC1kZXNjcmlwdGlvbi5qcyIsICIudml0ZXByZXNzL3N0cmluZ3MvZW4uanNvbiIsICIudml0ZXByZXNzL3N0cmluZ3MvcnUuanNvbiIsICIudml0ZXByZXNzL3N0cmluZ3Mva28uanNvbiIsICIudml0ZXByZXNzL3N0cmluZ3MvamEuanNvbiIsICIudml0ZXByZXNzL3N0cmluZ3MvZXMuanNvbiIsICIudml0ZXByZXNzL3N0cmluZ3MvcHQuanNvbiIsICIudml0ZXByZXNzL2kxOG4ubWpzIiwgIi52aXRlcHJlc3MvYmFycy5tanMiLCAiLnZpdGVwcmVzcy9kYXRhL2NsaS5qcyIsICIudml0ZXByZXNzL2xpbmtWYWxpZGF0b3IubWpzIl0sCiAgInNvdXJjZXNDb250ZW50IjogWyJjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9maWxlbmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9jb25maWcubWpzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ltcG9ydF9tZXRhX3VybCA9IFwiZmlsZTovLy9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvY29uZmlnLm1qc1wiO2ltcG9ydCB7IGRlZmluZUNvbmZpZyB9IGZyb20gXCJ2aXRlcHJlc3NcIjtcbmltcG9ydCAqIGFzIHBhdGggZnJvbSBcIm5vZGU6cGF0aFwiO1xuaW1wb3J0ICogYXMgZnMgZnJvbSBcIm5vZGU6ZnMvcHJvbWlzZXNcIjtcbmltcG9ydCB7XG4gIGd1aWRlc1NpZGViYXIsXG4gIGNvbnRyaWJ1dG9yc1NpZGViYXIsXG4gIHJlZmVyZW5jZXNTaWRlYmFyLFxuICBuYXZCYXIsXG59IGZyb20gXCIuL2JhcnMubWpzXCI7XG5pbXBvcnQgeyBjbGlTaWRlYmFyIH0gZnJvbSBcIi4vZGF0YS9jbGlcIjtcbmltcG9ydCB7IGxvY2FsaXplZFN0cmluZyB9IGZyb20gXCIuL2kxOG4ubWpzXCI7XG5pbXBvcnQgbGxtc3R4dFBsdWdpbiBmcm9tIFwidml0ZXByZXNzLXBsdWdpbi1sbG1zdHh0XCI7XG5pbXBvcnQgeyBMb2NhbGl6ZWRMaW5rVmFsaWRhdG9yIH0gZnJvbSBcIi4vbGlua1ZhbGlkYXRvci5tanNcIjtcblxuYXN5bmMgZnVuY3Rpb24gdGhlbWVDb25maWcobG9jYWxlKSB7XG4gIGNvbnN0IHNpZGViYXIgPSB7fTtcbiAgc2lkZWJhcltgLyR7bG9jYWxlfS9jb250cmlidXRvcnNgXSA9IGNvbnRyaWJ1dG9yc1NpZGViYXIobG9jYWxlKTtcbiAgc2lkZWJhcltgLyR7bG9jYWxlfS9ndWlkZXMvYF0gPSBndWlkZXNTaWRlYmFyKGxvY2FsZSk7XG4gIHNpZGViYXJbYC8ke2xvY2FsZX0vY2xpL2BdID0gYXdhaXQgY2xpU2lkZWJhcihsb2NhbGUpO1xuICBzaWRlYmFyW2AvJHtsb2NhbGV9L3JlZmVyZW5jZXMvYF0gPSBhd2FpdCByZWZlcmVuY2VzU2lkZWJhcihsb2NhbGUpO1xuICBzaWRlYmFyW2AvJHtsb2NhbGV9L2BdID0gZ3VpZGVzU2lkZWJhcihsb2NhbGUpO1xuICByZXR1cm4ge1xuICAgIG5hdjogbmF2QmFyKGxvY2FsZSksXG4gICAgc2lkZWJhcixcbiAgfTtcbn1cblxuZnVuY3Rpb24gZ2V0U2VhcmNoT3B0aW9uc0ZvckxvY2FsZShsb2NhbGUpIHtcbiAgcmV0dXJuIHtcbiAgICBwbGFjZWhvbGRlcjogbG9jYWxpemVkU3RyaW5nKGxvY2FsZSwgXCJzZWFyY2gucGxhY2Vob2xkZXJcIiksXG4gICAgdHJhbnNsYXRpb25zOiB7XG4gICAgICBidXR0b246IHtcbiAgICAgICAgYnV0dG9uVGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMuYnV0dG9uLmJ1dHRvblRleHRcIixcbiAgICAgICAgKSxcbiAgICAgICAgYnV0dG9uQXJpYUxhYmVsOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5idXR0b24uYnV0dG9uQXJpYUxhYmVsXCIsXG4gICAgICAgICksXG4gICAgICB9LFxuICAgICAgbW9kYWw6IHtcbiAgICAgICAgc2VhcmNoQm94OiB7XG4gICAgICAgICAgcmVzZXRCdXR0b25UaXRsZTogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLnNlYXJjaC1ib3gucmVzZXQtYnV0dG9uLXRpdGxlXCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICByZXNldEJ1dHRvbkFyaWFMYWJlbDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLnNlYXJjaC1ib3gucmVzZXQtYnV0dG9uLWFyaWEtbGFiZWxcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGNhbmNlbEJ1dHRvblRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5zZWFyY2gtYm94LmNhbmNlbC1idXR0b24tdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgY2FuY2VsQnV0dG9uQXJpYUxhYmVsOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc2VhcmNoLWJveC5jYW5jZWwtYnV0dG9uLWFyaWEtbGFiZWxcIixcbiAgICAgICAgICApLFxuICAgICAgICB9LFxuICAgICAgICBzdGFydFNjcmVlbjoge1xuICAgICAgICAgIHJlY2VudFNlYXJjaGVzVGl0bGU6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5zdGFydC1zY3JlZW4ucmVjZW50LXNlYXJjaGVzLXRpdGxlXCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBub1JlY2VudFNlYXJjaGVzVGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLnN0YXJ0LXNjcmVlbi5uby1yZWNlbnQtc2VhcmNoZXMtdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgc2F2ZVJlY2VudFNlYXJjaEJ1dHRvblRpdGxlOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc3RhcnQtc2NyZWVuLnNhdmUtcmVjZW50LXNlYXJjaC1idXR0b24tdGl0bGVcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIHJlbW92ZVJlY2VudFNlYXJjaEJ1dHRvblRpdGxlOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc3RhcnQtc2NyZWVuLnJlbW92ZS1yZWNlbnQtc2VhcmNoLWJ1dHRvbi10aXRsZVwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgZmF2b3JpdGVTZWFyY2hlc1RpdGxlOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc3RhcnQtc2NyZWVuLmZhdm9yaXRlLXNlYXJjaGVzLXRpdGxlXCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICByZW1vdmVGYXZvcml0ZVNlYXJjaEJ1dHRvblRpdGxlOiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuc3RhcnQtc2NyZWVuLnJlbW92ZS1mYXZvcml0ZS1zZWFyY2gtYnV0dG9uLXRpdGxlXCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgfSxcbiAgICAgICAgZXJyb3JTY3JlZW46IHtcbiAgICAgICAgICB0aXRsZVRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5lcnJvci1zY3JlZW4udGl0bGUtdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgaGVscFRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5lcnJvci1zY3JlZW4uaGVscC10ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgfSxcbiAgICAgICAgZm9vdGVyOiB7XG4gICAgICAgICAgc2VsZWN0VGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLmZvb3Rlci5zZWxlY3QtdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbmF2aWdhdGVUZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwuZm9vdGVyLm5hdmlnYXRlLXRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGNsb3NlVGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzZWFyY2gudHJhbnNsYXRpb25zLm1vZGFsLmZvb3Rlci5jbG9zZS10ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBzZWFyY2hCeVRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5mb290ZXIuc2VhcmNoLWJ5LXRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICB9LFxuICAgICAgICBub1Jlc3VsdHNTY3JlZW46IHtcbiAgICAgICAgICBub1Jlc3VsdHNUZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwubm8tcmVzdWx0cy1zY3JlZW4ubm8tcmVzdWx0cy10ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBzdWdnZXN0ZWRRdWVyeVRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2VhcmNoLnRyYW5zbGF0aW9ucy5tb2RhbC5uby1yZXN1bHRzLXNjcmVlbi5zdWdnZXN0ZWQtcXVlcnktdGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgcmVwb3J0TWlzc2luZ1Jlc3VsdHNUZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwubm8tcmVzdWx0cy1zY3JlZW4ucmVwb3J0LW1pc3NpbmctcmVzdWx0cy10ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICByZXBvcnRNaXNzaW5nUmVzdWx0c0xpbmtUZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNlYXJjaC50cmFuc2xhdGlvbnMubW9kYWwubm8tcmVzdWx0cy1zY3JlZW4ucmVwb3J0LW1pc3NpbmctcmVzdWx0cy1saW5rLXRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICB9LFxuICAgICAgfSxcbiAgICB9LFxuICB9O1xufVxuXG5jb25zdCBzZWFyY2hPcHRpb25zTG9jYWxlcyA9IHtcbiAgZW46IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJlblwiKSxcbiAga286IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJrb1wiKSxcbiAgamE6IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJqYVwiKSxcbiAgcnU6IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJydVwiKSxcbiAgZXM6IGdldFNlYXJjaE9wdGlvbnNGb3JMb2NhbGUoXCJlc1wiKSxcbn07XG5cbmV4cG9ydCBkZWZhdWx0IGRlZmluZUNvbmZpZyh7XG4gIHRpdGxlOiBcIlR1aXN0XCIsXG4gIHRpdGxlVGVtcGxhdGU6IFwiOnRpdGxlIHwgVHVpc3RcIixcbiAgZGVzY3JpcHRpb246IFwiU2NhbGUgeW91ciBYY29kZSBhcHAgZGV2ZWxvcG1lbnRcIixcbiAgc3JjRGlyOiBcImRvY3NcIixcbiAgbGFzdFVwZGF0ZWQ6IGZhbHNlLFxuICB2aXRlOiB7XG4gICAgcGx1Z2luczogW2xsbXN0eHRQbHVnaW4oKV0sXG4gIH0sXG4gIGxvY2FsZXM6IHtcbiAgICBlbjoge1xuICAgICAgbGFiZWw6IFwiRW5nbGlzaFwiLFxuICAgICAgbGFuZzogXCJlblwiLFxuICAgICAgdGhlbWVDb25maWc6IGF3YWl0IHRoZW1lQ29uZmlnKFwiZW5cIiksXG4gICAgfSxcbiAgICBrbzoge1xuICAgICAgbGFiZWw6IFwiXHVENTVDXHVBRDZEXHVDNUI0IChLb3JlYW4pXCIsXG4gICAgICBsYW5nOiBcImtvXCIsXG4gICAgICB0aGVtZUNvbmZpZzogYXdhaXQgdGhlbWVDb25maWcoXCJrb1wiKSxcbiAgICB9LFxuICAgIGphOiB7XG4gICAgICBsYWJlbDogXCJcdTY1RTVcdTY3MkNcdThBOUUgKEphcGFuZXNlKVwiLFxuICAgICAgbGFuZzogXCJqYVwiLFxuICAgICAgdGhlbWVDb25maWc6IGF3YWl0IHRoZW1lQ29uZmlnKFwiamFcIiksXG4gICAgfSxcbiAgICBydToge1xuICAgICAgbGFiZWw6IFwiXHUwNDIwXHUwNDQzXHUwNDQxXHUwNDQxXHUwNDNBXHUwNDM4XHUwNDM5IChSdXNzaWFuKVwiLFxuICAgICAgbGFuZzogXCJydVwiLFxuICAgICAgdGhlbWVDb25maWc6IGF3YWl0IHRoZW1lQ29uZmlnKFwicnVcIiksXG4gICAgfSxcbiAgICBlczoge1xuICAgICAgbGFiZWw6IFwiQ2FzdGVsbGFubyAoU3BhbmlzaClcIixcbiAgICAgIGxhbmc6IFwiZXNcIixcbiAgICAgIHRoZW1lQ29uZmlnOiBhd2FpdCB0aGVtZUNvbmZpZyhcImVzXCIpLFxuICAgIH0sXG4gICAgcHQ6IHtcbiAgICAgIGxhYmVsOiBcIlBvcnR1Z3VcdTAwRUFzIChQb3J0dWd1ZXNlKVwiLFxuICAgICAgbGFuZzogXCJwdFwiLFxuICAgICAgdGhlbWVDb25maWc6IGF3YWl0IHRoZW1lQ29uZmlnKFwicHRcIiksXG4gICAgfSxcbiAgfSxcbiAgY2xlYW5VcmxzOiB0cnVlLFxuICBoZWFkOiBbXG4gICAgW1xuICAgICAgXCJtZXRhXCIsXG4gICAgICB7XG4gICAgICAgIFwiaHR0cC1lcXVpdlwiOiBcIkNvbnRlbnQtU2VjdXJpdHktUG9saWN5XCIsXG4gICAgICAgIGNvbnRlbnQ6IFwiZnJhbWUtc3JjICdzZWxmJyBodHRwczovL3ZpZGVvcy50dWlzdC5kZXZcIixcbiAgICAgIH0sXG4gICAgICBgYCxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwic3R5bGVcIixcbiAgICAgIHt9LFxuICAgICAgYFxuICAgICAgQGltcG9ydCB1cmwoJ2h0dHBzOi8vZm9udHMuZ29vZ2xlYXBpcy5jb20vY3NzMj9mYW1pbHk9U3BhY2UrR3JvdGVzazp3Z2h0QDMwMC4uNzAwJmZhbWlseT1TcGFjZStNb25vOml0YWwsd2dodEAwLDQwMDswLDcwMDsxLDQwMDsxLDcwMCZkaXNwbGF5PXN3YXAnKTtcbiAgICAgIGAsXG4gICAgXSxcbiAgICBbXG4gICAgICBcInN0eWxlXCIsXG4gICAgICB7fSxcbiAgICAgIGBcbiAgICAgIEBpbXBvcnQgdXJsKCdodHRwczovL2ZvbnRzLmdvb2dsZWFwaXMuY29tL2NzczI/ZmFtaWx5PVNwYWNlK0dyb3Rlc2s6d2dodEAzMDAuLjcwMCZkaXNwbGF5PXN3YXAnKTtcbiAgICAgIGAsXG4gICAgXSxcbiAgICBbXCJtZXRhXCIsIHsgcHJvcGVydHk6IFwib2c6dXJsXCIsIGNvbnRlbnQ6IFwiaHR0cHM6Ly9kb2NzLnR1aXN0LmlvXCIgfSwgXCJcIl0sXG4gICAgW1wibWV0YVwiLCB7IHByb3BlcnR5OiBcIm9nOnR5cGVcIiwgY29udGVudDogXCJ3ZWJzaXRlXCIgfSwgXCJcIl0sXG4gICAgW1xuICAgICAgXCJtZXRhXCIsXG4gICAgICB7IHByb3BlcnR5OiBcIm9nOmltYWdlXCIsIGNvbnRlbnQ6IFwiaHR0cHM6Ly9kb2NzLnR1aXN0LmlvL2ltYWdlcy9vZy5qcGVnXCIgfSxcbiAgICAgIFwiXCIsXG4gICAgXSxcbiAgICBbXCJtZXRhXCIsIHsgbmFtZTogXCJ0d2l0dGVyOmNhcmRcIiwgY29udGVudDogXCJzdW1tYXJ5XCIgfSwgXCJcIl0sXG4gICAgW1wibWV0YVwiLCB7IHByb3BlcnR5OiBcInR3aXR0ZXI6ZG9tYWluXCIsIGNvbnRlbnQ6IFwiZG9jcy50dWlzdC5pb1wiIH0sIFwiXCJdLFxuICAgIFtcIm1ldGFcIiwgeyBwcm9wZXJ0eTogXCJ0d2l0dGVyOnVybFwiLCBjb250ZW50OiBcImh0dHBzOi8vZG9jcy50dWlzdC5pb1wiIH0sIFwiXCJdLFxuICAgIFtcbiAgICAgIFwibWV0YVwiLFxuICAgICAge1xuICAgICAgICBuYW1lOiBcInR3aXR0ZXI6aW1hZ2VcIixcbiAgICAgICAgY29udGVudDogXCJodHRwczovL2RvY3MudHVpc3QuaW8vaW1hZ2VzL29nLmpwZWdcIixcbiAgICAgIH0sXG4gICAgICBcIlwiLFxuICAgIF0sXG4gICAgW1xuICAgICAgXCJzY3JpcHRcIixcbiAgICAgIHt9LFxuICAgICAgYFxuICAgICAgKGZ1bmN0aW9uKGQsIHNjcmlwdCkge1xuICAgICAgICBzY3JpcHQgPSBkLmNyZWF0ZUVsZW1lbnQoJ3NjcmlwdCcpO1xuICAgICAgICBzY3JpcHQuYXN5bmMgPSBmYWxzZTtcbiAgICAgICAgc2NyaXB0Lm9ubG9hZCA9IGZ1bmN0aW9uKCl7XG4gICAgICAgICAgUGxhaW4uaW5pdCh7XG4gICAgICAgICAgICBhcHBJZDogJ2xpdmVDaGF0QXBwXzAxSlNIMVQ2QUpDU0I2UVoxVlE2MFlDMktNJyxcbiAgICAgICAgICB9KTtcbiAgICAgICAgfTtcbiAgICAgICAgc2NyaXB0LnNyYyA9ICdodHRwczovL2NoYXQuY2RuLXBsYWluLmNvbS9pbmRleC5qcyc7XG4gICAgICAgIGQuZ2V0RWxlbWVudHNCeVRhZ05hbWUoJ2hlYWQnKVswXS5hcHBlbmRDaGlsZChzY3JpcHQpO1xuICAgICAgfShkb2N1bWVudCkpO1xuICAgICAgYCxcbiAgICBdLFxuICBdLFxuICBzaXRlbWFwOiB7XG4gICAgaG9zdG5hbWU6IFwiaHR0cHM6Ly9kb2NzLnR1aXN0LmlvXCIsXG4gIH0sXG4gIGFzeW5jIGJ1aWxkRW5kKHsgb3V0RGlyIH0pIHtcbiAgICBjb25zdCByZWRpcmVjdHNQYXRoID0gcGF0aC5qb2luKG91dERpciwgXCJfcmVkaXJlY3RzXCIpO1xuICAgIGNvbnN0IHJlZGlyZWN0cyA9IGBcbi9kb2N1bWVudGF0aW9uL3R1aXN0L2luc3RhbGxhdGlvbiAvZ3VpZGUvaW50cm9kdWN0aW9uL2luc3RhbGxhdGlvbiAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3Byb2plY3Qtc3RydWN0dXJlIC9ndWlkZS9wcm9qZWN0L2RpcmVjdG9yeS1zdHJ1Y3R1cmUgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9jb21tYW5kLWxpbmUtaW50ZXJmYWNlIC9ndWlkZS9hdXRvbWF0aW9uL2dlbmVyYXRlIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvZGVwZW5kZW5jaWVzIC9ndWlkZS9wcm9qZWN0L2RlcGVuZGVuY2llcyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3NoYXJpbmctY29kZS1hY3Jvc3MtbWFuaWZlc3RzIC9ndWlkZS9wcm9qZWN0L2NvZGUtc2hhcmluZyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3N5bnRoZXNpemVkLWZpbGVzIC9ndWlkZS9wcm9qZWN0L3N5bnRoZXNpemVkLWZpbGVzIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvbWlncmF0aW9uLWd1aWRlbGluZXMgL2d1aWRlL2ludHJvZHVjdGlvbi9hZG9wdGluZy10dWlzdC9taWdyYXRlLWZyb20teGNvZGVwcm9qIDMwMVxuL3R1dG9yaWFscy90dWlzdC10dXRvcmlhbHMgL2d1aWRlL2ludHJvZHVjdGlvbi9hZG9wdGluZy10dWlzdC9uZXctcHJvamVjdCAzMDFcbi90dXRvcmlhbHMvdHVpc3QvaW5zdGFsbCAgL2d1aWRlL2ludHJvZHVjdGlvbi9hZG9wdGluZy10dWlzdC9uZXctcHJvamVjdCAzMDFcbi90dXRvcmlhbHMvdHVpc3QvY3JlYXRlLXByb2plY3QgIC9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3QvbmV3LXByb2plY3QgMzAxXG4vdHV0b3JpYWxzL3R1aXN0L2V4dGVybmFsLWRlcGVuZGVuY2llcyAvZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L25ldy1wcm9qZWN0IDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvZ2VuZXJhdGlvbi1lbnZpcm9ubWVudCAvZ3VpZGUvcHJvamVjdC9keW5hbWljLWNvbmZpZ3VyYXRpb24gMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC91c2luZy1wbHVnaW5zIC9ndWlkZS9wcm9qZWN0L3BsdWdpbnMgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9jcmVhdGluZy1wbHVnaW5zIC9ndWlkZS9wcm9qZWN0L3BsdWdpbnMgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC90YXNrIC9ndWlkZS9wcm9qZWN0L3BsdWdpbnMgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC90dWlzdC1jbG91ZCAvY2xvdWQvd2hhdC1pcy1jbG91ZCAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3R1aXN0LWNsb3VkLWdldC1zdGFydGVkIC9jbG91ZC9nZXQtc3RhcnRlZCAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L2JpbmFyeS1jYWNoaW5nIC9jbG91ZC9iaW5hcnktY2FjaGluZyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3NlbGVjdGl2ZS10ZXN0aW5nIC9jbG91ZC9zZWxlY3RpdmUtdGVzdGluZyAzMDFcbi90dXRvcmlhbHMvdHVpc3QtY2xvdWQtdHV0b3JpYWxzIC9jbG91ZC9vbi1wcmVtaXNlIDMwMVxuL3R1dG9yaWFscy90dWlzdC9lbnRlcnByaXNlLWluZnJhc3RydWN0dXJlLXJlcXVpcmVtZW50cyAvY2xvdWQvb24tcHJlbWlzZSAzMDFcbi90dXRvcmlhbHMvdHVpc3QvZW50ZXJwcmlzZS1lbnZpcm9ubWVudCAvY2xvdWQvb24tcHJlbWlzZSAzMDFcbi90dXRvcmlhbHMvdHVpc3QvZW50ZXJwcmlzZS1kZXBsb3ltZW50IC9jbG91ZC9vbi1wcmVtaXNlIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvZ2V0LXN0YXJ0ZWQtYXMtY29udHJpYnV0b3IgL2NvbnRyaWJ1dG9ycy9nZXQtc3RhcnRlZCAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L21hbmlmZXN0byAvY29udHJpYnV0b3JzL3ByaW5jaXBsZXMgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9jb2RlLXJldmlld3MgL2NvbnRyaWJ1dG9ycy9jb2RlLXJldmlld3MgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9yZXBvcnRpbmctYnVncyAvY29udHJpYnV0b3JzL2lzc3VlLXJlcG9ydGluZyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L2NoYW1waW9uaW5nLXByb2plY3RzIC9jb250cmlidXRvcnMvZ2V0LXN0YXJ0ZWQgMzAxXG4vZ3VpZGUvc2NhbGUvdWZlYXR1cmVzLWFyY2hpdGVjdHVyZS5odG1sIC9ndWlkZS9zY2FsZS90bWEtYXJjaGl0ZWN0dXJlLmh0bWwgMzAxXG4vZ3VpZGUvc2NhbGUvdWZlYXR1cmVzLWFyY2hpdGVjdHVyZSAvZ3VpZGUvc2NhbGUvdG1hLWFyY2hpdGVjdHVyZSAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vY29zdC1vZi1jb252ZW5pZW5jZSAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvY29zdC1vZi1jb252ZW5pZW5jZSAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vaW5zdGFsbGF0aW9uIC9ndWlkZXMvcXVpY2stc3RhcnQvaW5zdGFsbC10dWlzdCAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3QvbmV3LXByb2plY3QgL2d1aWRlcy9zdGFydC9uZXctcHJvamVjdCAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3Qvc3dpZnQtcGFja2FnZSAvZ3VpZGVzL3N0YXJ0L3N3aWZ0LXBhY2thZ2UgMzAxXG4vZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L21pZ3JhdGUtZnJvbS14Y29kZXByb2ogL2d1aWRlcy9zdGFydC9taWdyYXRlL3hjb2RlLXByb2plY3QgMzAxXG4vZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L21pZ3JhdGUtbG9jYWwtc3dpZnQtcGFja2FnZXMgL2d1aWRlcy9zdGFydC9taWdyYXRlL3N3aWZ0LXBhY2thZ2UgMzAxXG4vZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L21pZ3JhdGUtZnJvbS14Y29kZWdlbiAvZ3VpZGVzL3N0YXJ0L21pZ3JhdGUveGNvZGVnZW4tcHJvamVjdCAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3QvbWlncmF0ZS1mcm9tLWJhemVsIC9ndWlkZXMvc3RhcnQvbWlncmF0ZS9iYXplbC1wcm9qZWN0IDMwMVxuL2d1aWRlL2ludHJvZHVjdGlvbi9mcm9tLXYzLXRvLXY0IC9yZWZlcmVuY2VzL21pZ3JhdGlvbnMvZnJvbS12My10by12NCAzMDFcbi9ndWlkZS9wcm9qZWN0L21hbmlmZXN0cyAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvbWFuaWZlc3RzIDMwMVxuL2d1aWRlL3Byb2plY3QvZGlyZWN0b3J5LXN0cnVjdHVyZSAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvZGlyZWN0b3J5LXN0cnVjdHVyZSAzMDFcbi9ndWlkZS9wcm9qZWN0L2VkaXRpbmcgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2VkaXRpbmcgMzAxXG4vZ3VpZGUvcHJvamVjdC9kZXBlbmRlbmNpZXMgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2RlcGVuZGVuY2llcyAzMDFcbi9ndWlkZS9wcm9qZWN0L2NvZGUtc2hhcmluZyAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvY29kZS1zaGFyaW5nIDMwMVxuL2d1aWRlL3Byb2plY3Qvc3ludGhlc2l6ZWQtZmlsZXMgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL3N5bnRoZXNpemVkLWZpbGVzIDMwMVxuL2d1aWRlL3Byb2plY3QvZHluYW1pYy1jb25maWd1cmF0aW9uIC9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9keW5hbWljLWNvbmZpZ3VyYXRpb24gMzAxXG4vZ3VpZGUvcHJvamVjdC90ZW1wbGF0ZXMgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL3RlbXBsYXRlcyAzMDFcbi9ndWlkZS9wcm9qZWN0L3BsdWdpbnMgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL3BsdWdpbnMgMzAxXG4vZ3VpZGUvYXV0b21hdGlvbi9nZW5lcmF0ZSAvIDMwMVxuL2d1aWRlL2F1dG9tYXRpb24vYnVpbGQgL2d1aWRlcy9kZXZlbG9wL2J1aWxkIDMwMVxuL2d1aWRlL2F1dG9tYXRpb24vdGVzdCAvZ3VpZGVzL2RldmVsb3AvdGVzdCAzMDFcbi9ndWlkZS9hdXRvbWF0aW9uL3J1biAvIDMwMVxuL2d1aWRlL2F1dG9tYXRpb24vZ3JhcGggLyAzMDFcbi9ndWlkZS9hdXRvbWF0aW9uL2NsZWFuIC8gMzAxXG4vZ3VpZGUvc2NhbGUvdG1hLWFyY2hpdGVjdHVyZSAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvdG1hLWFyY2hpdGVjdHVyZSAzMDFcbi9jbG91ZC93aGF0LWlzLWNsb3VkIC8gMzAxXG4vY2xvdWQvZ2V0LXN0YXJ0ZWQgLyAzMDFcbi9jbG91ZC9iaW5hcnktY2FjaGluZyAvZ3VpZGVzL2RldmVsb3AvYnVpbGQvY2FjaGUgMzAxXG4vY2xvdWQvc2VsZWN0aXZlLXRlc3RpbmcgL2d1aWRlcy9kZXZlbG9wL3Rlc3Qvc21hcnQtcnVubmVyIDMwMVxuL2Nsb3VkL2hhc2hpbmcgL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2hhc2hpbmcgMzAxXG4vY2xvdWQvb24tcHJlbWlzZSAvZ3VpZGVzL2Rhc2hib2FyZC9vbi1wcmVtaXNlL2luc3RhbGwgMzAxXG4vY2xvdWQvb24tcHJlbWlzZS9tZXRyaWNzIC9ndWlkZXMvZGFzaGJvYXJkL29uLXByZW1pc2UvbWV0cmljcyAzMDFcbi9yZWZlcmVuY2UvcHJvamVjdC1kZXNjcmlwdGlvbi8qIC9yZWZlcmVuY2VzL3Byb2plY3QtZGVzY3JpcHRpb24vOnNwbGF0IDMwMVxuL3JlZmVyZW5jZS9leGFtcGxlcy8qIC9yZWZlcmVuY2VzL2V4YW1wbGVzLzpzcGxhdCAzMDFcbi9ndWlkZXMvZGV2ZWxvcC93b3JrZmxvd3MgL2d1aWRlcy9kZXZlbG9wL2NvbnRpbnVvdXMtaW50ZWdyYXRpb24vd29ya2Zsb3dzIDMwMVxuL2d1aWRlcy9kYXNoYm9hcmQvb24tcHJlbWlzZS9pbnN0YWxsIC9zZXJ2ZXIvb24tcHJlbWlzZS9pbnN0YWxsIDMwMVxuL2d1aWRlcy9kYXNoYm9hcmQvb24tcHJlbWlzZS9tZXRyaWNzIC9zZXJ2ZXIvb24tcHJlbWlzZS9tZXRyaWNzIDMwMVxuLzpsb2NhbGUvcmVmZXJlbmNlcy9wcm9qZWN0LWRlc2NyaXB0aW9uL3N0cnVjdHMvY29uZmlnIC86bG9jYWxlL3JlZmVyZW5jZXMvcHJvamVjdC1kZXNjcmlwdGlvbi9zdHJ1Y3RzL3R1aXN0ICAzMDFcbi86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL3Rlc3Qvc21hcnQtcnVubmVyIC86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL3Rlc3Qvc2VsZWN0aXZlLXRlc3RpbmcgMzAxXG4vOmxvY2FsZS9ndWlkZXMvc3RhcnQvbmV3LXByb2plY3QgLzpsb2NhbGUvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvYWRvcHRpb24vbmV3LXByb2plY3QgMzAxXG4vOmxvY2FsZS9ndWlkZXMvc3RhcnQvc3dpZnQtcGFja2FnZSAvOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9hZG9wdGlvbi9zd2lmdC1wYWNrYWdlIDMwMVxuLzpsb2NhbGUvZ3VpZGVzL3N0YXJ0L21pZ3JhdGUveGNvZGUtcHJvamVjdCAvOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9hZG9wdGlvbi9taWdyYXRlL3hjb2RlLXByb2plY3QgMzAxXG4vOmxvY2FsZS9ndWlkZXMvc3RhcnQvbWlncmF0ZS9zd2lmdC1wYWNrYWdlIC86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2Fkb3B0aW9uL21pZ3JhdGUvc3dpZnQtcGFja2FnZSAzMDFcbi86bG9jYWxlL2d1aWRlcy9zdGFydC9taWdyYXRlL3hjb2RlZ2VuLXByb2plY3QgLzpsb2NhbGUvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvYWRvcHRpb24vbWlncmF0ZS94Y29kZWdlbi1wcm9qZWN0IDMwMVxuLzpsb2NhbGUvZ3VpZGVzL3N0YXJ0L21pZ3JhdGUvYmF6ZWwtcHJvamVjdCAvOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9hZG9wdGlvbi9taWdyYXRlL2JhemVsLXByb2plY3QgMzAxXG4vOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9idWlsZC9jYWNoZSAvOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9jYWNoZSAzMDFcbi86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL2J1aWxkL3JlZ2lzdHJ5IC86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL3JlZ2lzdHJ5IDMwMVxuLzpsb2NhbGUvZ3VpZGVzL2RldmVsb3AvdGVzdC9zZWxlY3RpdmUtdGVzdGluZyAvOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9zZWxlY3RpdmUtdGVzdGluZyAzMDFcbi86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL2luc3BlY3QvaW1wbGljaXQtZGVwZW5kZW5jaWVzIC86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2luc3BlY3QvaW1wbGljaXQtZGVwZW5kZW5jaWVzIDMwMVxuLzpsb2NhbGUvZ3VpZGVzL2RldmVsb3AvYXV0b21hdGUvY29udGludW91cy1pbnRlZ3JhdGlvbiAvOmxvY2FsZS9ndWlkZXMvZW52aXJvbm1lbnRzL2NvbnRpbnVvdXMtaW50ZWdyYXRpb24gMzAxXG4vOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9hdXRvbWF0ZS93b3JrZmxvd3MgLzpsb2NhbGUvZ3VpZGVzL2Vudmlyb25tZW50cy9hdXRvbWF0ZS9jb250aW51b3VzLWludGVncmF0aW9uIDMwMVxuLzpsb2NhbGUvZ3VpZGVzL2F1dG9tYXRlL3dvcmtmbG93cyAvOmxvY2FsZS9ndWlkZXMvZW52aXJvbm1lbnRzL2F1dG9tYXRlL2NvbnRpbnVvdXMtaW50ZWdyYXRpb24gMzAxXG4vOmxvY2FsZS9ndWlkZXMvYXV0b21hdGUvKiAvOmxvY2FsZS9ndWlkZXMvZW52aXJvbm1lbnRzLzpzcGxhdCAzMDFcbi86bG9jYWxlL2d1aWRlcy9kZXZlbG9wLyogLzpsb2NhbGUvZ3VpZGVzL2ZlYXR1cmVzLzpzcGxhdCAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0LyogLyAzMDFcbi86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL2J1aWxkL3JlZ2lzdHJ5IC86bG9jYWxlL2d1aWRlcy9kZXZlbG9wL3JlZ2lzdHJ5IDMwMVxuLzpsb2NhbGUvZ3VpZGVzL2RldmVsb3Avc2VsZWN0aXZlLXRlc3RpbmcveGNvZGVidWlsZCAvOmxvY2FsZS9ndWlkZXMvZGV2ZWxvcC9zZWxlY3RpdmUtdGVzdGluZy94Y29kZS1wcm9qZWN0IDMwMVxuLzpsb2NhbGUvZ3VpZGVzL2ZlYXR1cmVzL21jcCAvOmxvY2FsZS9ndWlkZXMvZmVhdHVyZXMvYWdlbnRpYy1jb2RpbmcvbWNwIDMwMVxuLzpsb2NhbGUvZ3VpZGVzL2ZlYXR1cmVzL2FnZW50aWMtYnVpbGRpbmcvbWNwIC86bG9jYWxlL2d1aWRlcy9mZWF0dXJlcy9hZ2VudGljLWNvZGluZy9tY3AgMzAxXG4vOmxvY2FsZS9ndWlkZXMvZW52aXJvbm1lbnRzL2NvbnRpbnVvdXMtaW50ZWdyYXRpb24gLzpsb2NhbGUvZ3VpZGVzL2ludGVncmF0aW9ucy9jb250aW51b3VzLWludGVncmF0aW9uIDMwMVxuLzpsb2NhbGUvZ3VpZGVzL2Vudmlyb25tZW50cy9hdXRvbWF0ZS9jb250aW51b3VzLWludGVncmF0aW9uIC86bG9jYWxlL2d1aWRlcy9pbnRlZ3JhdGlvbnMvY29udGludW91cy1pbnRlZ3JhdGlvbiAzMDFcbi86bG9jYWxlL3NlcnZlci9pbnRyb2R1Y3Rpb24vYWNjb3VudHMtYW5kLXByb2plY3RzIC86bG9jYWxlL2d1aWRlcy9zZXJ2ZXIvYWNjb3VudHMtYW5kLXByb2plY3RzIDMwMVxuLzpsb2NhbGUvc2VydmVyL2ludHJvZHVjdGlvbi9hdXRoZW50aWNhdGlvbiAvOmxvY2FsZS9ndWlkZXMvc2VydmVyL2F1dGhlbnRpY2F0aW9uIDMwMVxuLzpsb2NhbGUvc2VydmVyL2ludHJvZHVjdGlvbi9pbnRlZ3JhdGlvbnMgLzpsb2NhbGUvZ3VpZGVzL2ludGVncmF0aW9ucy9naXRmb3JnZS9naXRodWIgMzAxXG4vOmxvY2FsZS9zZXJ2ZXIvb24tcHJlbWlzZS9pbnN0YWxsIC86bG9jYWxlL2d1aWRlcy9zZXJ2ZXIvc2VsZi1ob3N0L2luc3RhbGwgMzAxXG4vOmxvY2FsZS9zZXJ2ZXIvb24tcHJlbWlzZS9tZXRyaWNzIC86bG9jYWxlL2d1aWRlcy9zZXJ2ZXIvc2VsZi1ob3N0L3RlbGVtZXRyeSAzMDFcbi86bG9jYWxlL2d1aWRlcy9zZXJ2ZXIvaW5zdGFsbCAvOmxvY2FsZS9ndWlkZXMvc2VydmVyL3NlbGYtaG9zdC9pbnN0YWxsIDMwMVxuLzpsb2NhbGUvZ3VpZGVzL3NlcnZlci9tZXRyaWNzIC86bG9jYWxlL2d1aWRlcy9zZXJ2ZXIvc2VsZi1ob3N0L3RlbGVtZXRyeSAzMDFcbi86bG9jYWxlL3NlcnZlciAvOmxvY2FsZS9ndWlkZXMvc2VydmVyL2FjY291bnRzLWFuZC1wcm9qZWN0cyAzMDFcbiR7YXdhaXQgZnMucmVhZEZpbGUocGF0aC5qb2luKGltcG9ydC5tZXRhLmRpcm5hbWUsIFwibG9jYWxlLXJlZGlyZWN0cy50eHRcIiksIHtcbiAgZW5jb2Rpbmc6IFwidXRmLThcIixcbn0pfVxuICAgIGA7XG4gICAgZnMud3JpdGVGaWxlKHJlZGlyZWN0c1BhdGgsIHJlZGlyZWN0cyk7XG4gICAgXG4gICAgLy8gVmFsaWRhdGUgTG9jYWxpemVkTGluayBjb21wb25lbnRzXG4gICAgY29uc29sZS5sb2coJ1x1RDgzRFx1REQwRCBWYWxpZGF0aW5nIExvY2FsaXplZExpbmsgY29tcG9uZW50cy4uLicpO1xuICAgIGNvbnN0IHNyY0RpciA9IHBhdGguam9pbihwYXRoLmRpcm5hbWUob3V0RGlyKSwgJ2RvY3MnKTtcbiAgICBjb25zdCB2YWxpZGF0b3IgPSBuZXcgTG9jYWxpemVkTGlua1ZhbGlkYXRvcihzcmNEaXIpO1xuICAgIFxuICAgIGF3YWl0IHZhbGlkYXRvci5zY2FuRmlsZXMoKTtcbiAgICBhd2FpdCB2YWxpZGF0b3IudmFsaWRhdGVMaW5rcygpO1xuICB9LFxuICB0aGVtZUNvbmZpZzoge1xuICAgIGxvZ286IFwiL2xvZ28ucG5nXCIsXG4gICAgc2VhcmNoOiB7XG4gICAgICBwcm92aWRlcjogXCJhbGdvbGlhXCIsXG4gICAgICBvcHRpb25zOiB7XG4gICAgICAgIGFwcElkOiBcIjVBM0w5SEk5VlFcIixcbiAgICAgICAgYXBpS2V5OiBcImNkNDVmNTE1ZmIxZmJiNzIwZDYzM2NiMGYxMjU3ZTdhXCIsXG4gICAgICAgIGluZGV4TmFtZTogXCJ0dWlzdFwiLFxuICAgICAgICBsb2NhbGVzOiBzZWFyY2hPcHRpb25zTG9jYWxlcyxcbiAgICAgICAgc3RhcnRVcmxzOiBbXCJodHRwczovL3R1aXN0LmRldi9cIl0sXG4gICAgICAgIHJlbmRlckphdmFTY3JpcHQ6IGZhbHNlLFxuICAgICAgICBzaXRlbWFwczogW10sXG4gICAgICAgIGV4Y2x1c2lvblBhdHRlcm5zOiBbXSxcbiAgICAgICAgaWdub3JlQ2Fub25pY2FsVG86IGZhbHNlLFxuICAgICAgICBkaXNjb3ZlcnlQYXR0ZXJuczogW1wiaHR0cHM6Ly90dWlzdC5kZXYvKipcIl0sXG4gICAgICAgIHNjaGVkdWxlOiBcImF0IDA1OjEwIG9uIFNhdHVyZGF5XCIsXG4gICAgICAgIGFjdGlvbnM6IFtcbiAgICAgICAgICB7XG4gICAgICAgICAgICBpbmRleE5hbWU6IFwidHVpc3RcIixcbiAgICAgICAgICAgIHBhdGhzVG9NYXRjaDogW1wiaHR0cHM6Ly90dWlzdC5kZXYvKipcIl0sXG4gICAgICAgICAgICByZWNvcmRFeHRyYWN0b3I6ICh7ICQsIGhlbHBlcnMgfSkgPT4ge1xuICAgICAgICAgICAgICByZXR1cm4gaGVscGVycy5kb2NzZWFyY2goe1xuICAgICAgICAgICAgICAgIHJlY29yZFByb3BzOiB7XG4gICAgICAgICAgICAgICAgICBsdmwxOiBcIi5jb250ZW50IGgxXCIsXG4gICAgICAgICAgICAgICAgICBjb250ZW50OiBcIi5jb250ZW50IHAsIC5jb250ZW50IGxpXCIsXG4gICAgICAgICAgICAgICAgICBsdmwwOiB7XG4gICAgICAgICAgICAgICAgICAgIHNlbGVjdG9yczogXCJzZWN0aW9uLmhhcy1hY3RpdmUgZGl2IGgyXCIsXG4gICAgICAgICAgICAgICAgICAgIGRlZmF1bHRWYWx1ZTogXCJEb2N1bWVudGF0aW9uXCIsXG4gICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgbHZsMjogXCIuY29udGVudCBoMlwiLFxuICAgICAgICAgICAgICAgICAgbHZsMzogXCIuY29udGVudCBoM1wiLFxuICAgICAgICAgICAgICAgICAgbHZsNDogXCIuY29udGVudCBoNFwiLFxuICAgICAgICAgICAgICAgICAgbHZsNTogXCIuY29udGVudCBoNVwiLFxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgaW5kZXhIZWFkaW5nczogdHJ1ZSxcbiAgICAgICAgICAgICAgfSk7XG4gICAgICAgICAgICB9LFxuICAgICAgICAgIH0sXG4gICAgICAgIF0sXG4gICAgICAgIGluaXRpYWxJbmRleFNldHRpbmdzOiB7XG4gICAgICAgICAgdml0ZXByZXNzOiB7XG4gICAgICAgICAgICBhdHRyaWJ1dGVzRm9yRmFjZXRpbmc6IFtcInR5cGVcIiwgXCJsYW5nXCJdLFxuICAgICAgICAgICAgYXR0cmlidXRlc1RvUmV0cmlldmU6IFtcImhpZXJhcmNoeVwiLCBcImNvbnRlbnRcIiwgXCJhbmNob3JcIiwgXCJ1cmxcIl0sXG4gICAgICAgICAgICBhdHRyaWJ1dGVzVG9IaWdobGlnaHQ6IFtcImhpZXJhcmNoeVwiLCBcImhpZXJhcmNoeV9jYW1lbFwiLCBcImNvbnRlbnRcIl0sXG4gICAgICAgICAgICBhdHRyaWJ1dGVzVG9TbmlwcGV0OiBbXCJjb250ZW50OjEwXCJdLFxuICAgICAgICAgICAgY2FtZWxDYXNlQXR0cmlidXRlczogW1wiaGllcmFyY2h5XCIsIFwiaGllcmFyY2h5X3JhZGlvXCIsIFwiY29udGVudFwiXSxcbiAgICAgICAgICAgIHNlYXJjaGFibGVBdHRyaWJ1dGVzOiBbXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9yYWRpb19jYW1lbC5sdmwwKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW8ubHZsMClcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X3JhZGlvX2NhbWVsLmx2bDEpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9yYWRpby5sdmwxKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW9fY2FtZWwubHZsMilcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X3JhZGlvLmx2bDIpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9yYWRpb19jYW1lbC5sdmwzKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW8ubHZsMylcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X3JhZGlvX2NhbWVsLmx2bDQpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9yYWRpby5sdmw0KVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW9fY2FtZWwubHZsNSlcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X3JhZGlvLmx2bDUpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9yYWRpb19jYW1lbC5sdmw2KVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfcmFkaW8ubHZsNilcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X2NhbWVsLmx2bDApXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeS5sdmwwKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfY2FtZWwubHZsMSlcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5Lmx2bDEpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9jYW1lbC5sdmwyKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHkubHZsMilcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X2NhbWVsLmx2bDMpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeS5sdmwzKVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHlfY2FtZWwubHZsNClcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5Lmx2bDQpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeV9jYW1lbC5sdmw1KVwiLFxuICAgICAgICAgICAgICBcInVub3JkZXJlZChoaWVyYXJjaHkubHZsNSlcIixcbiAgICAgICAgICAgICAgXCJ1bm9yZGVyZWQoaGllcmFyY2h5X2NhbWVsLmx2bDYpXCIsXG4gICAgICAgICAgICAgIFwidW5vcmRlcmVkKGhpZXJhcmNoeS5sdmw2KVwiLFxuICAgICAgICAgICAgICBcImNvbnRlbnRcIixcbiAgICAgICAgICAgIF0sXG4gICAgICAgICAgICBkaXN0aW5jdDogdHJ1ZSxcbiAgICAgICAgICAgIGF0dHJpYnV0ZUZvckRpc3RpbmN0OiBcInVybFwiLFxuICAgICAgICAgICAgY3VzdG9tUmFua2luZzogW1xuICAgICAgICAgICAgICBcImRlc2Mod2VpZ2h0LnBhZ2VSYW5rKVwiLFxuICAgICAgICAgICAgICBcImRlc2Mod2VpZ2h0LmxldmVsKVwiLFxuICAgICAgICAgICAgICBcImFzYyh3ZWlnaHQucG9zaXRpb24pXCIsXG4gICAgICAgICAgICBdLFxuICAgICAgICAgICAgcmFua2luZzogW1xuICAgICAgICAgICAgICBcIndvcmRzXCIsXG4gICAgICAgICAgICAgIFwiZmlsdGVyc1wiLFxuICAgICAgICAgICAgICBcInR5cG9cIixcbiAgICAgICAgICAgICAgXCJhdHRyaWJ1dGVcIixcbiAgICAgICAgICAgICAgXCJwcm94aW1pdHlcIixcbiAgICAgICAgICAgICAgXCJleGFjdFwiLFxuICAgICAgICAgICAgICBcImN1c3RvbVwiLFxuICAgICAgICAgICAgXSxcbiAgICAgICAgICAgIGhpZ2hsaWdodFByZVRhZzpcbiAgICAgICAgICAgICAgJzxzcGFuIGNsYXNzPVwiYWxnb2xpYS1kb2NzZWFyY2gtc3VnZ2VzdGlvbi0taGlnaGxpZ2h0XCI+JyxcbiAgICAgICAgICAgIGhpZ2hsaWdodFBvc3RUYWc6IFwiPC9zcGFuPlwiLFxuICAgICAgICAgICAgbWluV29yZFNpemVmb3IxVHlwbzogMyxcbiAgICAgICAgICAgIG1pbldvcmRTaXplZm9yMlR5cG9zOiA3LFxuICAgICAgICAgICAgYWxsb3dUeXBvc09uTnVtZXJpY1Rva2VuczogZmFsc2UsXG4gICAgICAgICAgICBtaW5Qcm94aW1pdHk6IDEsXG4gICAgICAgICAgICBpZ25vcmVQbHVyYWxzOiB0cnVlLFxuICAgICAgICAgICAgYWR2YW5jZWRTeW50YXg6IHRydWUsXG4gICAgICAgICAgICBhdHRyaWJ1dGVDcml0ZXJpYUNvbXB1dGVkQnlNaW5Qcm94aW1pdHk6IHRydWUsXG4gICAgICAgICAgICByZW1vdmVXb3Jkc0lmTm9SZXN1bHRzOiBcImFsbE9wdGlvbmFsXCIsXG4gICAgICAgICAgfSxcbiAgICAgICAgfSxcbiAgICAgIH0sXG4gICAgfSxcbiAgICBlZGl0TGluazoge1xuICAgICAgcGF0dGVybjogXCJodHRwczovL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZWRpdC9tYWluL2RvY3MvZG9jcy86cGF0aFwiLFxuICAgIH0sXG4gICAgc29jaWFsTGlua3M6IFtcbiAgICAgIHsgaWNvbjogXCJnaXRodWJcIiwgbGluazogXCJodHRwczovL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3RcIiB9LFxuICAgICAgeyBpY29uOiBcIm1hc3RvZG9uXCIsIGxpbms6IFwiaHR0cHM6Ly9mb3NzdG9kb24ub3JnL0B0dWlzdFwiIH0sXG4gICAgICB7IGljb246IFwiYmx1ZXNreVwiLCBsaW5rOiBcImh0dHBzOi8vYnNreS5hcHAvcHJvZmlsZS90dWlzdC5kZXZcIiB9LFxuICAgICAge1xuICAgICAgICBpY29uOiBcInNsYWNrXCIsXG4gICAgICAgIGxpbms6IFwiaHR0cHM6Ly9qb2luLnNsYWNrLmNvbS90L3R1aXN0YXBwL3NoYXJlZF9pbnZpdGUvenQtMXk2NjdtamJrLXMyTFRSWDFZQnliOUVJSVRqZExjTHdcIixcbiAgICAgIH0sXG4gICAgXSxcbiAgICBmb290ZXI6IHtcbiAgICAgIG1lc3NhZ2U6IFwiUmVsZWFzZWQgdW5kZXIgdGhlIE1JVCBMaWNlbnNlLlwiLFxuICAgICAgY29weXJpZ2h0OiBcIkNvcHlyaWdodCBcdTAwQTkgMjAyNC1wcmVzZW50IFR1aXN0IEdtYkhcIixcbiAgICB9LFxuICB9LFxufSk7XG4iLCAiY29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3NcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZmlsZW5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvaWNvbnMubWpzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ltcG9ydF9tZXRhX3VybCA9IFwiZmlsZTovLy9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvaWNvbnMubWpzXCI7ZXhwb3J0IGZ1bmN0aW9uIHBsYXlJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbiAgPHBhdGggZD1cIk01IDQuOTg5NjNDNSA0LjAxODQ3IDUgMy41MzI4OSA1LjIwMjQ5IDMuMjY1MjJDNS4zNzg4OSAzLjAzMjAzIDUuNjQ4NTIgMi44ODc3MyA1Ljk0MDQgMi44NzAzQzYuMjc1NDQgMi44NTAzIDYuNjc5NDYgMy4xMTk2NSA3LjQ4NzUyIDMuNjU4MzVMMTguMDAzMSAxMC42Njg3QzE4LjY3MDggMTEuMTEzOSAxOS4wMDQ2IDExLjMzNjQgMTkuMTIwOSAxMS42MTY5QzE5LjIyMjcgMTEuODYyMiAxOS4yMjI3IDEyLjEzNzggMTkuMTIwOSAxMi4zODMxQzE5LjAwNDYgMTIuNjYzNiAxOC42NzA4IDEyLjg4NjIgMTguMDAzMSAxMy4zMzEzTDcuNDg3NTIgMjAuMzQxN0M2LjY3OTQ2IDIwLjg4MDQgNi4yNzU0NCAyMS4xNDk3IDUuOTQwNCAyMS4xMjk3QzUuNjQ4NTIgMjEuMTEyMyA1LjM3ODg5IDIwLjk2OCA1LjIwMjQ5IDIwLjczNDhDNSAyMC40NjcxIDUgMTkuOTgxNSA1IDE5LjAxMDRWNC45ODk2M1pcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuICA8L3N2Zz5cbmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBjdWJlT3V0bGluZUljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuPHBhdGggZD1cIk05Ljc1IDIwLjc1MDFMMTEuMjIzIDIxLjU2ODRDMTEuNTA2NiAyMS43MjYgMTEuNjQ4NCAyMS44MDQ3IDExLjc5ODYgMjEuODM1NkMxMS45MzE1IDIxLjg2MyAxMi4wNjg1IDIxLjg2MyAxMi4yMDE1IDIxLjgzNTZDMTIuMzUxNiAyMS44MDQ3IDEyLjQ5MzQgMjEuNzI2IDEyLjc3NyAyMS41Njg0TDE0LjI1IDIwLjc1MDFNNS4yNSAxOC4yNTAxTDMuODIyOTcgMTcuNDU3M0MzLjUyMzQ2IDE3LjI5MDkgMy4zNzM2OCAxNy4yMDc3IDMuMjY0NjMgMTcuMDg5M0MzLjE2ODE2IDE2Ljk4NDcgMy4wOTUxNSAxNi44NjA2IDMuMDUwNDggMTYuNzI1NEMzIDE2LjU3MjYgMyAxNi40MDEzIDMgMTYuMDU4NlYxNC41MDAxTTMgOS41MDAwOVY3Ljk0MTUzQzMgNy41OTg4OSAzIDcuNDI3NTcgMy4wNTA0OCA3LjI3NDc3QzMuMDk1MTUgNy4xMzk1OSAzLjE2ODE2IDcuMDE1NTEgMy4yNjQ2MyA2LjkxMDgyQzMuMzczNjggNi43OTI0OCAzLjUyMzQ1IDYuNzA5MjggMy44MjI5NyA2LjU0Mjg4TDUuMjUgNS43NTAwOU05Ljc1IDMuMjUwMDhMMTEuMjIzIDIuNDMxNzdDMTEuNTA2NiAyLjI3NDIxIDExLjY0ODQgMi4xOTU0MyAxMS43OTg2IDIuMTY0NTRDMTEuOTMxNSAyLjEzNzIxIDEyLjA2ODUgMi4xMzcyMSAxMi4yMDE1IDIuMTY0NTRDMTIuMzUxNiAyLjE5NTQzIDEyLjQ5MzQgMi4yNzQyMSAxMi43NzcgMi40MzE3N0wxNC4yNSAzLjI1MDA4TTE4Ljc1IDUuNzUwMDhMMjAuMTc3IDYuNTQyODhDMjAuNDc2NiA2LjcwOTI4IDIwLjYyNjMgNi43OTI0OCAyMC43MzU0IDYuOTEwODJDMjAuODMxOCA3LjAxNTUxIDIwLjkwNDkgNy4xMzk1OSAyMC45NDk1IDcuMjc0NzdDMjEgNy40Mjc1NyAyMSA3LjU5ODg5IDIxIDcuOTQxNTNWOS41MDAwOE0yMSAxNC41MDAxVjE2LjA1ODZDMjEgMTYuNDAxMyAyMSAxNi41NzI2IDIwLjk0OTUgMTYuNzI1NEMyMC45MDQ5IDE2Ljg2MDYgMjAuODMxOCAxNi45ODQ3IDIwLjczNTQgMTcuMDg5M0MyMC42MjYzIDE3LjIwNzcgMjAuNDc2NiAxNy4yOTA5IDIwLjE3NyAxNy40NTczTDE4Ljc1IDE4LjI1MDFNOS43NSAxMC43NTAxTDEyIDEyLjAwMDFNMTIgMTIuMDAwMUwxNC4yNSAxMC43NTAxTTEyIDEyLjAwMDFWMTQuNTAwMU0zIDcuMDAwMDhMNS4yNSA4LjI1MDA4TTE4Ljc1IDguMjUwMDhMMjEgNy4wMDAwOE0xMiAxOS41MDAxVjIyLjAwMDFcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuPC9zdmc+XG5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gc3RhcjA2SWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG4gIDxwYXRoIGQ9XCJNNC41IDIyVjE3TTQuNSA3VjJNMiA0LjVIN00yIDE5LjVIN00xMyAzTDExLjI2NTggNy41MDg4NkMxMC45ODM4IDguMjQyMDkgMTAuODQyOCA4LjYwODcxIDEwLjYyMzUgOC45MTcwOUMxMC40MjkyIDkuMTkwNCAxMC4xOTA0IDkuNDI5MTkgOS45MTcwOSA5LjYyMzUzQzkuNjA4NzEgOS44NDI4MSA5LjI0MjA5IDkuOTgzODEgOC41MDg4NiAxMC4yNjU4TDQgMTJMOC41MDg4NiAxMy43MzQyQzkuMjQyMDkgMTQuMDE2MiA5LjYwODcxIDE0LjE1NzIgOS45MTcwOSAxNC4zNzY1QzEwLjE5MDQgMTQuNTcwOCAxMC40MjkyIDE0LjgwOTYgMTAuNjIzNSAxNS4wODI5QzEwLjg0MjggMTUuMzkxMyAxMC45ODM4IDE1Ljc1NzkgMTEuMjY1OCAxNi40OTExTDEzIDIxTDE0LjczNDIgMTYuNDkxMUMxNS4wMTYyIDE1Ljc1NzkgMTUuMTU3MiAxNS4zOTEzIDE1LjM3NjUgMTUuMDgyOUMxNS41NzA4IDE0LjgwOTYgMTUuODA5NiAxNC41NzA4IDE2LjA4MjkgMTQuMzc2NUMxNi4zOTEzIDE0LjE1NzIgMTYuNzU3OSAxNC4wMTYyIDE3LjQ5MTEgMTMuNzM0MkwyMiAxMkwxNy40OTExIDEwLjI2NThDMTYuNzU3OSA5Ljk4MzgxIDE2LjM5MTMgOS44NDI4IDE2LjA4MjkgOS42MjM1M0MxNS44MDk2IDkuNDI5MTkgMTUuNTcwOCA5LjE5MDQgMTUuMzc2NSA4LjkxNzA5QzE1LjE1NzIgOC42MDg3MSAxNS4wMTYyIDguMjQyMDkgMTQuNzM0MiA3LjUwODg2TDEzIDNaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbiAgPC9zdmc+XG5cbmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBjdWJlMDJJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNMTIgMi41MDAwOFYxMi4wMDAxTTEyIDEyLjAwMDFMMjAuNSA3LjI3Nzc5TTEyIDEyLjAwMDFMMy41IDcuMjc3NzlNMTIgMTIuMDAwMVYyMS41MDAxTTIwLjUgMTYuNzIyM0wxMi43NzcgMTIuNDMxOEMxMi40OTM0IDEyLjI3NDIgMTIuMzUxNiAxMi4xOTU0IDEyLjIwMTUgMTIuMTY0NUMxMi4wNjg1IDEyLjEzNzIgMTEuOTMxNSAxMi4xMzcyIDExLjc5ODYgMTIuMTY0NUMxMS42NDg0IDEyLjE5NTQgMTEuNTA2NiAxMi4yNzQyIDExLjIyMyAxMi40MzE4TDMuNSAxNi43MjIzTTIxIDE2LjA1ODZWNy45NDE1M0MyMSA3LjU5ODg5IDIxIDcuNDI3NTcgMjAuOTQ5NSA3LjI3NDc3QzIwLjkwNDkgNy4xMzk1OSAyMC44MzE4IDcuMDE1NTEgMjAuNzM1NCA2LjkxMDgyQzIwLjYyNjMgNi43OTI0OCAyMC40NzY2IDYuNzA5MjggMjAuMTc3IDYuNTQyODhMMTIuNzc3IDIuNDMxNzdDMTIuNDkzNCAyLjI3NDIxIDEyLjM1MTYgMi4xOTU0MyAxMi4yMDE1IDIuMTY0NTRDMTIuMDY4NSAyLjEzNzIxIDExLjkzMTUgMi4xMzcyMSAxMS43OTg2IDIuMTY0NTRDMTEuNjQ4NCAyLjE5NTQzIDExLjUwNjYgMi4yNzQyMSAxMS4yMjMgMi40MzE3N0wzLjgyMjk3IDYuNTQyODhDMy41MjM0NSA2LjcwOTI4IDMuMzczNjkgNi43OTI0OCAzLjI2NDYzIDYuOTEwODJDMy4xNjgxNiA3LjAxNTUxIDMuMDk1MTUgNy4xMzk1OSAzLjA1MDQ4IDcuMjc0NzdDMyA3LjQyNzU3IDMgNy41OTg4OSAzIDcuOTQxNTNWMTYuMDU4NkMzIDE2LjQwMTMgMyAxNi41NzI2IDMuMDUwNDggMTYuNzI1NEMzLjA5NTE1IDE2Ljg2MDYgMy4xNjgxNiAxNi45ODQ3IDMuMjY0NjMgMTcuMDg5M0MzLjM3MzY5IDE3LjIwNzcgMy41MjM0NSAxNy4yOTA5IDMuODIyOTcgMTcuNDU3M0wxMS4yMjMgMjEuNTY4NEMxMS41MDY2IDIxLjcyNiAxMS42NDg0IDIxLjgwNDcgMTEuNzk4NiAyMS44MzU2QzExLjkzMTUgMjEuODYzIDEyLjA2ODUgMjEuODYzIDEyLjIwMTUgMjEuODM1NkMxMi4zNTE2IDIxLjgwNDcgMTIuNDkzNCAyMS43MjYgMTIuNzc3IDIxLjU2ODRMMjAuMTc3IDE3LjQ1NzNDMjAuNDc2NiAxNy4yOTA5IDIwLjYyNjMgMTcuMjA3NyAyMC43MzU0IDE3LjA4OTNDMjAuODMxOCAxNi45ODQ3IDIwLjkwNDkgMTYuODYwNiAyMC45NDk1IDE2LjcyNTRDMjEgMTYuNTcyNiAyMSAxNi40MDEzIDIxIDE2LjA1ODZaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGN1YmUwMUljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuPHBhdGggZD1cIk0yMC41IDcuMjc3ODNMMTIgMTIuMDAwMU0xMiAxMi4wMDAxTDMuNDk5OTcgNy4yNzc4M00xMiAxMi4wMDAxTDEyIDIxLjUwMDFNMjEgMTYuMDU4NlY3Ljk0MTUzQzIxIDcuNTk4ODkgMjEgNy40Mjc1NyAyMC45NDk1IDcuMjc0NzdDMjAuOTA0OSA3LjEzOTU5IDIwLjgzMTggNy4wMTU1MSAyMC43MzU0IDYuOTEwODJDMjAuNjI2MyA2Ljc5MjQ4IDIwLjQ3NjYgNi43MDkyOCAyMC4xNzcgNi41NDI4OEwxMi43NzcgMi40MzE3N0MxMi40OTM0IDIuMjc0MjEgMTIuMzUxNiAyLjE5NTQzIDEyLjIwMTUgMi4xNjQ1NEMxMi4wNjg1IDIuMTM3MjEgMTEuOTMxNSAyLjEzNzIxIDExLjc5ODYgMi4xNjQ1NEMxMS42NDg0IDIuMTk1NDMgMTEuNTA2NiAyLjI3NDIxIDExLjIyMyAyLjQzMTc3TDMuODIyOTcgNi41NDI4OEMzLjUyMzQ1IDYuNzA5MjggMy4zNzM2OSA2Ljc5MjQ4IDMuMjY0NjMgNi45MTA4MkMzLjE2ODE2IDcuMDE1NTEgMy4wOTUxNSA3LjEzOTU5IDMuMDUwNDggNy4yNzQ3N0MzIDcuNDI3NTcgMyA3LjU5ODg5IDMgNy45NDE1M1YxNi4wNTg2QzMgMTYuNDAxMyAzIDE2LjU3MjYgMy4wNTA0OCAxNi43MjU0QzMuMDk1MTUgMTYuODYwNiAzLjE2ODE2IDE2Ljk4NDcgMy4yNjQ2MyAxNy4wODkzQzMuMzczNjkgMTcuMjA3NyAzLjUyMzQ1IDE3LjI5MDkgMy44MjI5NyAxNy40NTczTDExLjIyMyAyMS41Njg0QzExLjUwNjYgMjEuNzI2IDExLjY0ODQgMjEuODA0NyAxMS43OTg2IDIxLjgzNTZDMTEuOTMxNSAyMS44NjMgMTIuMDY4NSAyMS44NjMgMTIuMjAxNSAyMS44MzU2QzEyLjM1MTYgMjEuODA0NyAxMi40OTM0IDIxLjcyNiAxMi43NzcgMjEuNTY4NEwyMC4xNzcgMTcuNDU3M0MyMC40NzY2IDE3LjI5MDkgMjAuNjI2MyAxNy4yMDc3IDIwLjczNTQgMTcuMDg5M0MyMC44MzE4IDE2Ljk4NDcgMjAuOTA0OSAxNi44NjA2IDIwLjk0OTUgMTYuNzI1NEMyMSAxNi41NzI2IDIxIDE2LjQwMTMgMjEgMTYuMDU4NlpcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuPC9zdmc+XG5cbiAgYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGJhckNoYXJ0U3F1YXJlMDJJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNOCAxNVYxN00xMiAxMVYxN00xNiA3VjE3TTcuOCAyMUgxNi4yQzE3Ljg4MDIgMjEgMTguNzIwMiAyMSAxOS4zNjIgMjAuNjczQzE5LjkyNjUgMjAuMzg1NCAyMC4zODU0IDE5LjkyNjUgMjAuNjczIDE5LjM2MkMyMSAxOC43MjAyIDIxIDE3Ljg4MDIgMjEgMTYuMlY3LjhDMjEgNi4xMTk4NCAyMSA1LjI3OTc2IDIwLjY3MyA0LjYzODAzQzIwLjM4NTQgNC4wNzM1NCAxOS45MjY1IDMuNjE0NiAxOS4zNjIgMy4zMjY5OEMxOC43MjAyIDMgMTcuODgwMiAzIDE2LjIgM0g3LjhDNi4xMTk4NCAzIDUuMjc5NzYgMyA0LjYzODAzIDMuMzI2OThDNC4wNzM1NCAzLjYxNDYgMy42MTQ2IDQuMDczNTQgMy4zMjY5OCA0LjYzODAzQzMgNS4yNzk3NiAzIDYuMTE5ODQgMyA3LjhWMTYuMkMzIDE3Ljg4MDIgMyAxOC43MjAyIDMuMzI2OTggMTkuMzYyQzMuNjE0NiAxOS45MjY1IDQuMDczNTQgMjAuMzg1NCA0LjYzODAzIDIwLjY3M0M1LjI3OTc2IDIxIDYuMTE5ODQgMjEgNy44IDIxWlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5cbiAgICBgO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY29kZTAySWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTE3IDE3TDIyIDEyTDE3IDdNNyA3TDIgMTJMNyAxN00xNCAzTDEwIDIxXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGRhdGFJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNMjEuMiAyMkMyMS40OCAyMiAyMS42MiAyMiAyMS43MjcgMjEuOTQ1NUMyMS44MjExIDIxLjg5NzYgMjEuODk3NiAyMS44MjExIDIxLjk0NTUgMjEuNzI3QzIyIDIxLjYyIDIyIDIxLjQ4IDIyIDIxLjJWMTAuOEMyMiAxMC41MiAyMiAxMC4zOCAyMS45NDU1IDEwLjI3M0MyMS44OTc2IDEwLjE3ODkgMjEuODIxMSAxMC4xMDI0IDIxLjcyNyAxMC4wNTQ1QzIxLjYyIDEwIDIxLjQ4IDEwIDIxLjIgMTBMMTguOCAxMEMxOC41MiAxMCAxOC4zOCAxMCAxOC4yNzMgMTAuMDU0NUMxOC4xNzg5IDEwLjEwMjQgMTguMTAyNCAxMC4xNzg5IDE4LjA1NDUgMTAuMjczQzE4IDEwLjM4IDE4IDEwLjUyIDE4IDEwLjhWMTMuMkMxOCAxMy40OCAxOCAxMy42MiAxNy45NDU1IDEzLjcyN0MxNy44OTc2IDE3LjgyMTEgMTcuODIxMSAxMy44OTc2IDE3LjcyNyAxMy45NDU1QzE3LjYyIDE0IDE3LjQ4IDE0IDE3LjIgMTRIMTQuOEMxNC41MiAxNCAxNC4zOCAxNCAxNC4yNzMgMTQuMDU0NUMxNC4xNzg5IDE0LjEwMjQgMTQuMTAyNCAxNC4xNzg5IDE0LjA1NDUgMTQuMjczQzE0IDE0LjM4IDE0IDE0LjUyIDE0IDE0LjhWMTcuMkMxNCAxNy40OCAxNCAxNy42MiAxMy45NDU1IDE3LjcyN0MxMy44OTc2IDE3LjgyMTEgMTMuODIxMSAxNy44OTc2IDEzLjcyNyAxNy45NDU1QzEzLjYyIDE4IDEzLjQ4IDE4IDEzLjIgMThIMTAuOEMxMC41MiAxOCAxMC4zOCAxOCAxMC4yNzMgMTguMDU0NUMxMC4xNzg5IDE4LjEwMjQgMTAuMTAyNCAxOC4xNzg5IDEwLjA1NDUgMTguMjczQzEwIDE4LjM4IDEwIDE4LjUyIDEwIDE4LjhWMjEuMkMxMCAyMS40OCAxMCAyMS42MiAxMC4wNTQ1IDIxLjcyN0MxMC4xMDI0IDIxLjgyMTEgMTAuMTc4OSAyMS44OTc2IDEwLjI3MyAyMS45NDU1QzEwLjM4IDIyIDEwLjUyIDIyIDEwLjggMjJMMjEuMiAyMlpcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuPHBhdGggZD1cIk0xMCA2LjhDMTAgNi41MTk5NyAxMCA2LjM3OTk2IDEwLjA1NDUgNi4yNzNDMTAuMTAyNCA2LjE3ODkyIDEwLjE3ODkgNi4xMDI0MyAxMC4yNzMgNi4wNTQ1QzEwLjM4IDYgMTAuNTIgNiAxMC44IDZIMTMuMkMxMy40OCA2IDEzLjYyIDYgMTMuNzI3IDYuMDU0NUMxMy44MjExIDYuMTAyNDMgMTMuODk3NiA2LjE3ODkyIDEzLjk0NTUgNi4yNzNDMTQgNi4zNzk5NiAxNCA2LjUxOTk3IDE0IDYuOFY5LjJDMTQgOS40ODAwMyAxNCA5LjYyMDA0IDEzLjk0NTUgOS43MjdDMTMuODk3NiA5LjgyMTA4IDEzLjgyMTEgOS44OTc1NyAxMy43MjcgOS45NDU1QzEzLjYyIDEwIDEzLjQ4IDEwIDEzLjIgMTBIMTAuOEMxMC41MiAxMCAxMC4zOCAxMCAxMC4yNzMgOS45NDU1QzEwLjE3ODkgOS44OTc1NyAxMC4xMDI0IDkuODIxMDggMTAuMDU0NSA5LjcyN0MxMCA5LjYyMDA0IDEwIDkuNDgwMDMgMTAgOS4yVjYuOFpcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuPHBhdGggZD1cIk0zIDEyLjhDMyAxMi41MiAzIDEyLjM4IDMuMDU0NSAxMi4yNzNDMy4xMDI0MyAxMi4xNzg5IDMuMTc4OTIgMTIuMTAyNCAzLjI3MyAxMi4wNTQ1QzMuMzc5OTYgMTIgMy41MTk5NyAxMiAzLjggMTJINi4yQzYuNDgwMDMgMTIgNi42MjAwNCAxMiA2LjcyNyAxMi4wNTQ1QzYuODIxMDggMTIuMTAyNCA2Ljg5NzU3IDEyLjE3ODkgNi45NDU1IDEyLjI3M0M3IDEyLjM4IDcgMTIuNTIgNyAxMi44VjE1LjJDNyAxNS40OCA3IDE1LjYyIDYuOTQ1NSAxNS43MjdDNi44OTc1NyAxNS44MjExIDYuODIxMDggMTUuODk3NiA2LjcyNyAxNS45NDU1QzYuNjIwMDQgMTYgNi40ODAwMyAxNiA2LjIgMTZIMy44QzMuNTE5OTcgMTYgMy4zNzk5NiAxNiAzLjI3MyAxNS45NDU1QzMuMTc4OTIgMTUuODk3NiAzLjEwMjQzIDE1LjgyMTEgMy4wNTQ1IDE1LjcyN0MzIDE1LjYyIDMgMTUuNDggMyAxNS4yVjEyLjhaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjxwYXRoIGQ9XCJNMiAyLjhDMiAyLjUxOTk3IDIgMi4zNzk5NiAyLjA1NDUgMi4yNzNDMi4xMDI0MyAyLjE3ODkyIDIuMTc4OTIgMi4xMDI0MyAyLjI3MyAyLjA1NDVDMi4zNzk5NiAyIDIuNTE5OTcgMiAyLjggMkg1LjJDNS40ODAwMyAyIDUuNjIwMDQgMiA1LjcyNyAyLjA1NDVDNS44MjEwOCAyLjEwMjQzIDUuODk3NTcgMi4xNzg5MiA1Ljk0NTUgMi4yNzNDNiAyLjM3OTk2IDYgMi41MTk5NyA2IDIuOFY1LjJDNiA1LjQ4MDAzIDYgNS42MjAwNCA1Ljk0NTUgNS43MjdDNS44OTc1NyA1LjgyMTA4IDUuODIxMDggNS44OTc1NyA1LjcyNyA1Ljk0NTVDNS42MjAwNCA2IDUuNDgwMDMgNiA1LjIgNkgyLjhDMi41MTk5NyA2IDIuMzc5OTYgNiAyLjI3MyA1Ljk0NTVDMi4xNzg5MiA1Ljg5NzU3IDIuMTAyNDMgNS44MjEwOCAyLjA1NDUgNS43MjdDMiA1LjYyMDA0IDIgNS40ODAwMyAyIDUuMlYyLjhaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBjaGVja0NpcmNsZUljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7MTV9XCIgaGVpZ2h0PVwiJHsxNX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTcuNSAxMkwxMC41IDE1TDE2LjUgOU0yMiAxMkMyMiAxNy41MjI4IDE3LjUyMjggMjIgMTIgMjJDNi40NzcxNSAyMiAyIDE3LjUyMjggMiAxMkMyIDYuNDc3MTUgNi40NzcxNSAyIDEyIDJDMTcuNTIyOCAyIDIyIDYuNDc3MTUgMjIgMTJaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIHR1aXN0SWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTIxIDE2VjcuMkMyMSA2LjA3OTkgMjEgNS41MTk4NCAyMC43ODIgNS4wOTIwMkMyMC41OTAzIDQuNzE1NjkgMjAuMjg0MyA0LjQwOTczIDE5LjkwOCA0LjIxNzk5QzE5LjQ4MDIgNCAxOC45MjAxIDQgMTcuOCA0SDYuMkM1LjA3OTg5IDQgNC41MTk4NCA0IDQuMDkyMDIgNC4yMTc5OUMzLjcxNTY5IDQuNDA5NzMgMy40MDk3MyA0LjcxNTY5IDMuMjE3OTkgNS4wOTIwMkMzIDUuNTE5ODQgMyA2LjA3OTkgMyA3LjJWMTZNNC42NjY2NyAyMEgxOS4zMzMzQzE5Ljk1MzMgMjAgMjAuMjYzMyAyMCAyMC41MTc2IDE5LjkzMTlDMjEuMjA3OCAxOS43NDY5IDIxLjc0NjkgMTkuMjA3OCAyMS45MzE5IDE4LjUxNzZDMjIgMTguMjYzMyAyMiAxNy45NTMzIDIyIDE3LjMzMzNDMjIgMTcuMDIzMyAyMiAxNi44NjgzIDIxLjk2NTkgMTYuNzQxMkMyMS44NzM1IDE2LjM5NjEgMjEuNjAzOSAxNi4xMjY1IDIxLjI1ODggMTYuMDM0MUMyMS4xMzE3IDE2IDIwLjk3NjcgMTYgMjAuNjY2NyAxNkgzLjMzMzMzQzMuMDIzMzQgMTYgMi44NjgzNSAxNiAyLjc0MTE4IDE2LjAzNDFDMi4zOTYwOSAxNi4xMjY1IDIuMTI2NTQgMTYuMzk2MSAyLjAzNDA3IDE2Ljc0MTJDMiAxNi44NjgzIDIgMTcuMDIzMyAyIDE3LjMzMzNDMiAxNy45NTMzIDIgMTguMjYzMyAyLjA2ODE1IDE4LjUxNzZDMi4yNTMwOCAxOS4yMDc4IDIuNzkyMTggMTkuNzQ2OSAzLjQ4MjM2IDE5LjkzMTlDMy43MzY2OSAyMCA0LjA0NjY5IDIwIDQuNjY2NjcgMjBaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBjbG91ZEJsYW5rMDJJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNOS41IDE5QzUuMzU3ODYgMTkgMiAxNS42NDIxIDIgMTEuNUMyIDcuMzU3ODYgNS4zNTc4NiA0IDkuNSA0QzEyLjM4MjcgNCAxNC44ODU1IDUuNjI2MzQgMTYuMTQxIDguMDExNTNDMTYuMjU5NyA4LjAwMzg4IDE2LjM3OTQgOCAxNi41IDhDMTkuNTM3NiA4IDIyIDEwLjQ2MjQgMjIgMTMuNUMyMiAxNi41Mzc2IDE5LjUzNzYgMTkgMTYuNSAxOUMxMy45NDg1IDE5IDEyLjEyMjQgMTkgOS41IDE5WlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5cbmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBzZXJ2ZXIwNEljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuPHBhdGggZD1cIk0yMiAxMC41TDIxLjUyNTYgNi43MDQ2M0MyMS4zMzk1IDUuMjE2MDIgMjEuMjQ2NSA0LjQ3MTY5IDIwLjg5NjEgMy45MTA4QzIwLjU4NzUgMy40MTY2MiAyMC4xNDE2IDMuMDIzMDEgMTkuNjEzIDIuNzc4MDRDMTkuMDEzIDIuNSAxOC4yNjI5IDIuNSAxNi43NjI2IDIuNUg3LjIzNzM1QzUuNzM3MTQgMi41IDQuOTg3MDQgMi41IDQuMzg3MDIgMi43NzgwNEMzLjg1ODM4IDMuMDIzMDEgMy40MTI1IDMuNDE2NjIgMy4xMDM4NiAzLjkxMDhDMi43NTM1NCA0LjQ3MTY5IDIuNjYwNSA1LjIxNjAxIDIuNDc0NDIgNi43MDQ2M0wyIDEwLjVNNS41IDE0LjVIMTguNU01LjUgMTQuNUMzLjU2NyAxNC41IDIgMTIuOTMzIDIgMTFDMiA5LjA2NyAzLjU2NyA3LjUgNS41IDcuNUgxOC41QzIwLjQzMyA3LjUgMjIgOS4wNjcgMjIgMTFDMjIgMTIuOTMzIDIwLjQzMyAxNC41IDE4LjUgMTQuNU01LjUgMTQuNUMzLjU2NyAxNC41IDIgMTYuMDY3IDIgMThDMiAxOS45MzMgMy41NjcgMjEuNSA1LjUgMjEuNUgxOC41QzIwLjQzMyAyMS41IDIyIDE5LjkzMyAyMiAxOEMyMiAxNi4wNjcgMjAuNDMzIDE0LjUgMTguNSAxNC41TTYgMTFINi4wMU02IDE4SDYuMDFNMTIgMTFIMThNMTIgMThIMThcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuPC9zdmc+XG5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gbWljcm9zY29wZUljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuPHBhdGggZD1cIk0zIDIySDEyTTExIDYuMjUyMDRDMTEuNjM5MiA2LjA4NzUxIDEyLjMwOTQgNiAxMyA2QzE3LjQxODMgNiAyMSA5LjU4MTcyIDIxIDE0QzIxIDE3LjM1NzQgMTguOTMxOCAyMC4yMzE3IDE2IDIxLjQxODVNNS41IDEzSDkuNUM5Ljk2NDY2IDEzIDEwLjE5NyAxMyAxMC4zOTAyIDEzLjAzODRDMTEuMTgzNiAxMy4xOTYyIDExLjgwMzggMTMuODE2NCAxMS45NjE2IDE0LjYwOThDMTIgMTQuODAzIDEyIDE1LjAzNTMgMTIgMTUuNUMxMiAxNS45NjQ3IDEyIDE2LjE5NyAxMS45NjE2IDE2LjM5MDJDMTEuODAzOCAxNy4xODM2IDExLjE4MzYgMTcuODAzOCAxMC4zOTAyIDE3Ljk2MTZDMTAuMTk3IDE4IDkuOTY0NjYgMTggOS41IDE4SDUuNUM1LjAzNTM0IDE4IDQuODAzMDIgMTggNC42MDk4MiAxNy45NjE2QzMuODE2NDQgMTcuODAzOCAzLjE5NjI0IDE3LjE4MzYgMy4wMzg0MyAxNi4zOTAyQzMgMTYuMTk3IDMgMTUuOTY0NyAzIDE1LjVDMyAxNS4wMzUzIDMgMTQuODAzIDMuMDM4NDMgMTQuNjA5OEMzLjE5NjI0IDEzLjgxNjQgMy44MTY0NCAxMy4xOTYyIDQuNjA5ODIgMTMuMDM4NEM0LjgwMzAyIDEzIDUuMDM1MzQgMTMgNS41IDEzWk00IDUuNVYxM0gxMVY1LjVDMTEgMy41NjcgOS40MzMgMiA3LjUgMkM1LjU2NyAyIDQgMy41NjcgNCA1LjVaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGJ1aWxkaW5nMDdJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbiAgPHBhdGggZD1cIk03LjUgMTFINC42QzQuMDM5OTUgMTEgMy43NTk5MiAxMSAzLjU0NjAxIDExLjEwOUMzLjM1Nzg1IDExLjIwNDkgMy4yMDQ4NyAxMS4zNTc4IDMuMTA4OTkgMTEuNTQ2QzMgMTEuNzU5OSAzIDEyLjAzOTkgMyAxMi42VjIxTTE2LjUgMTFIMTkuNEMxOS45NjAxIDExIDIwLjI0MDEgMTEgMjAuNDU0IDExLjEwOUMyMC42NDIyIDExLjIwNDkgMjAuNzk1MSAxMS4zNTc4IDIwLjg5MSAxMS41NDZDMjEgMTEuNzU5OSAyMSAxMi4wMzk5IDIxIDEyLjZWMjFNMTYuNSAyMVY2LjJDMTYuNSA1LjA3OTkgMTYuNSA0LjUxOTg0IDE2LjI4MiA0LjA5MjAyQzE2LjA5MDMgMy43MTU2OSAxNS43ODQzIDMuNDA5NzMgMTUuNDA4IDMuMjE3OTlDMTQuOTgwMiAzIDE0LjQyMDEgMyAxMy4zIDNIMTAuN0M5LjU3OTg5IDMgOS4wMTk4NCAzIDguNTkyMDIgMy4yMTc5OUM4LjIxNTY5IDMuNDA5NzMgNy45MDk3MyAzLjcxNTY5IDcuNzE3OTkgNC4wOTIwMkM3LjUgNC41MTk4NCA3LjUgNS4wNzk5IDcuNSA2LjJWMjFNMjIgMjFIMk0xMSA3SDEzTTExIDExSDEzTTExIDE1SDEzXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbiAgPC9zdmc+XG5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gYm9va09wZW4wMUljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuICA8cGF0aCBkPVwiTTEyIDIxTDExLjg5OTkgMjAuODQ5OUMxMS4yMDUzIDE5LjgwOCAxMC44NTggMTkuMjg3IDEwLjM5OTEgMTguOTA5OEM5Ljk5Mjg2IDE4LjU3NTkgOS41MjQ3NiAxOC4zMjU0IDkuMDIxNjEgMTguMTcyNkM4LjQ1MzI1IDE4IDcuODI3MTEgMTggNi41NzQ4MiAxOEg1LjJDNC4wNzk4OSAxOCAzLjUxOTg0IDE4IDMuMDkyMDIgMTcuNzgyQzIuNzE1NjkgMTcuNTkwMyAyLjQwOTczIDE3LjI4NDMgMi4yMTc5OSAxNi45MDhDMiAxNi40ODAyIDIgMTUuOTIwMSAyIDE0LjhWNi4yQzIgNS4wNzk4OSAyIDQuNTE5ODQgMi4yMTc5OSA0LjA5MjAyQzIuNDA5NzMgMy43MTU2OSAyLjcxNTY5IDMuNDA5NzMgMy4wOTIwMiAzLjIxNzk5QzMuNTE5ODQgMyA0LjA3OTg5IDMgNS4yIDNINS42QzcuODQwMjEgMyA4Ljk2MDMxIDMgOS44MTU5NiAzLjQzNTk3QzEwLjU2ODYgMy44MTk0NyAxMS4xODA1IDQuNDMxMzkgMTEuNTY0IDUuMTg0MDRDMTIgNi4wMzk2OCAxMiA3LjE1OTc5IDEyIDkuNE0xMiAyMVY5LjRNMTIgMjFMMTIuMTAwMSAyMC44NDk5QzEyLjc5NDcgMTkuODA4IDEzLjE0MiAxOS4yODcgMTMuNjAwOSAxOC45MDk4QzE0LjAwNzEgMTguNTc1OSAxNC40NzUyIDE4LjMyNTQgMTQuOTc4NCAxOC4xNzI2QzE1LjU0NjcgMTggMTYuMTcyOSAxOCAxNy40MjUyIDE4SDE4LjhDMTkuOTIwMSAxOCAyMC40ODAyIDE4IDIwLjkwOCAxNy43ODJDMjEuMjg0MyAxNy41OTAzIDIxLjU5MDMgMTcuMjg0MyAyMS43ODIgMTYuOTA4QzIyIDE2LjQ4MDIgMjIgMTUuOTIwMSAyMiAxNC44VjYuMkMyMiA1LjA3OTg5IDIyIDQuNTE5ODQgMjEuNzgyIDQuMDkyMDJDMjEuNTkwMyAzLjcxNTY5IDIxLjI4NDMgMy40MDk3MyAyMC45MDggMy4yMTc5OUMyMC40ODAyIDMgMTkuOTIwMSAzIDE4LjggM0gxOC40QzE2LjE1OTggMyAxNS4wMzk3IDMgMTQuMTg0IDMuNDM1OTdDMTMuNDMxNCAzLjgxOTQ3IDEyLjgxOTUgNC40MzEzOSAxMi40MzYgNS4xODQwNEMxMiA2LjAzOTY4IDEyIDcuMTU5NzkgMTIgOS40XCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbiAgPC9zdmc+XG5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY29kZUJyb3dzZXJJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbiAgPHBhdGggZD1cIk0yMiA5SDJNMTQgMTcuNUwxNi41IDE1TDE0IDEyLjVNMTAgMTIuNUw3LjUgMTVMMTAgMTcuNU0yIDcuOEwyIDE2LjJDMiAxNy44ODAyIDIgMTguNzIwMiAyLjMyNjk4IDE5LjM2MkMyLjYxNDYgMTkuOTI2NSAzLjA3MzU0IDIwLjM4NTQgMy42MzgwMyAyMC42NzNDNC4yNzk3NiAyMSA1LjExOTg0IDIxIDYuOCAyMUgxNy4yQzE4Ljg4MDIgMjEgMTkuNzIwMiAyMSAyMC4zNjIgMjAuNjczQzIwLjkyNjUgMjAuMzg1NCAyMS4zODU0IDE5LjkyNjUgMjEuNjczIDE5LjM2MkMyMiAxOC43MjAyIDIyIDE3Ljg4MDIgMjIgMTYuMlY3LjhDMjIgNi4xMTk4NCAyMiA1LjI3OTc3IDIxLjY3MyA0LjYzODAzQzIxLjM4NTQgNC4wNzM1NCAyMC45MjY1IDMuNjE0NiAyMC4zNjIgMy4zMjY5OEMxOS43MjAyIDMgMTguODgwMiAzIDE3LjIgM0w2LjggM0M1LjExOTg0IDMgNC4yNzk3NiAzIDMuNjM4MDMgMy4zMjY5OEMzLjA3MzU0IDMuNjE0NiAyLjYxNDYgNC4wNzM1NCAyLjMyNjk4IDQuNjM4MDNDMiA1LjI3OTc2IDIgNi4xMTk4NCAyIDcuOFpcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuICA8L3N2Zz5cbmA7XG59XG5cbi8vIENhY2hlIGljb24gLSBkYXRhYmFzZS9zdG9yYWdlXG5leHBvcnQgZnVuY3Rpb24gY2FjaGVJY29uKCkge1xuICByZXR1cm4gYDxzdmcgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiIHdpZHRoPVwiMTZcIiBoZWlnaHQ9XCIxNlwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIiBjbGFzcz1cImx1Y2lkZSBsdWNpZGUtZGF0YWJhc2VcIj48ZWxsaXBzZSBjeD1cIjEyXCIgY3k9XCI1XCIgcng9XCI5XCIgcnk9XCIzXCIvPjxwYXRoIGQ9XCJtMyA1IDAgMTRjMCAxLjY2IDQuMDMgMyA5IDNzOS0xLjM0IDktM1Y1XCIvPjxwYXRoIGQ9XCJNMyAxMmMwIDEuNjYgNC4wMyAzIDkgM3M5LTEuMzQgOS0zXCIvPjwvc3ZnPmA7XG59XG5cbi8vIFRlc3RpbmcgaWNvbiAtIGNoZWNrL3Rlc3RcbmV4cG9ydCBmdW5jdGlvbiB0ZXN0SWNvbigpIHtcbiAgcmV0dXJuIGA8c3ZnIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIiB3aWR0aD1cIjE2XCIgaGVpZ2h0PVwiMTZcIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIgY2xhc3M9XCJsdWNpZGUgbHVjaWRlLWNoZWNrLWNpcmNsZVwiPjxwYXRoIGQ9XCJNMTIgMjJjNS41MjMgMCAxMC00LjQ3NyAxMC0xMFMxNy41MjMgMiAxMiAyIDIgNi40NzcgMiAxMnM0LjQ3NyAxMCAxMCAxMHpcIi8+PHBhdGggZD1cIm05IDEyIDIgMiA0LTRcIi8+PC9zdmc+YDtcbn1cblxuLy8gUmVnaXN0cnkgaWNvbiAtIHBhY2thZ2VcbmV4cG9ydCBmdW5jdGlvbiByZWdpc3RyeUljb24oKSB7XG4gIHJldHVybiBgPHN2ZyB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCIgd2lkdGg9XCIxNlwiIGhlaWdodD1cIjE2XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiIGNsYXNzPVwibHVjaWRlIGx1Y2lkZS1wYWNrYWdlXCI+PHBhdGggZD1cIm03LjUgNC4yNyA5IDUuMTVcIi8+PHBhdGggZD1cIk0yMSA4YTIgMiAwIDAgMC0xLTEuNzNsLTctNGEyIDIgMCAwIDAtMiAwbC03IDRBMiAyIDAgMCAwIDMgOHY4YTIgMiAwIDAgMCAxIDEuNzNsNyA0YTIgMiAwIDAgMCAyIDBsNy00QTIgMiAwIDAgMCAyMSAxNlpcIi8+PHBhdGggZD1cIm0zLjMgNyA4LjcgNSA4LjctNVwiLz48cGF0aCBkPVwiTTEyIDIyVjEyXCIvPjwvc3ZnPmA7XG59XG5cbi8vIEluc2lnaHRzIGljb24gLSBjaGFydC9hbmFseXRpY3NcbmV4cG9ydCBmdW5jdGlvbiBpbnNpZ2h0c0ljb24oKSB7XG4gIHJldHVybiBgPHN2ZyB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCIgd2lkdGg9XCIxNlwiIGhlaWdodD1cIjE2XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiIGNsYXNzPVwibHVjaWRlIGx1Y2lkZS1iYXItY2hhcnQtM1wiPjxwYXRoIGQ9XCJNMyAzdjE4aDE4XCIvPjxwYXRoIGQ9XCJtMTkgOS01IDUtNC00LTMgM1wiLz48L3N2Zz5gO1xufVxuXG4vLyBCdW5kbGUgc2l6ZSBpY29uIC0gd2VpZ2h0L3NjYWxlXG5leHBvcnQgZnVuY3Rpb24gYnVuZGxlU2l6ZUljb24oKSB7XG4gIHJldHVybiBgPHN2ZyB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCIgd2lkdGg9XCIxNlwiIGhlaWdodD1cIjE2XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiIGNsYXNzPVwibHVjaWRlIGx1Y2lkZS1zY2FsZVwiPjxwYXRoIGQ9XCJtMTYgMTYgMy04IDMgOGMtLjg3LjY1LTEuOTIgMS0zIDFzLTIuMTMtLjM1LTMtMVpcIi8+PHBhdGggZD1cIm0yIDE2IDMtOCAzIDhjLS44Ny42NS0xLjkyIDEtMyAxcy0yLjEzLS4zNS0zLTFaXCIvPjxwYXRoIGQ9XCJNNyAyMWgxMFwiLz48cGF0aCBkPVwiTTEyIDN2MThcIi8+PHBhdGggZD1cIk0zIDdoMmMyIDAgNS0xIDctMiAyIDEgNSAyIDcgMmgyXCIvPjwvc3ZnPmA7XG59XG5cbi8vIFByZXZpZXdzIGljb24gLSBleWUvcHJldmlld1xuZXhwb3J0IGZ1bmN0aW9uIHByZXZpZXdzSWNvbigpIHtcbiAgcmV0dXJuIGA8c3ZnIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIiB3aWR0aD1cIjE2XCIgaGVpZ2h0PVwiMTZcIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIgY2xhc3M9XCJsdWNpZGUgbHVjaWRlLWV5ZVwiPjxwYXRoIGQ9XCJNMiAxMnMzLTcgMTAtNyAxMCA3IDEwIDctMyA3LTEwIDctMTAtNy0xMC03WlwiLz48Y2lyY2xlIGN4PVwiMTJcIiBjeT1cIjEyXCIgcj1cIjNcIi8+PC9zdmc+YDtcbn1cblxuLy8gUHJvamVjdHMgaWNvbiAtIGZvbGRlciBzdHJ1Y3R1cmVcbmV4cG9ydCBmdW5jdGlvbiBwcm9qZWN0c0ljb24oKSB7XG4gIHJldHVybiBgPHN2ZyB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCIgd2lkdGg9XCIxNlwiIGhlaWdodD1cIjE2XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiIGNsYXNzPVwibHVjaWRlIGx1Y2lkZS1mb2xkZXItdHJlZVwiPjxwYXRoIGQ9XCJNMjAgMTBhMSAxIDAgMCAwIDEtMVY2YTEgMSAwIDAgMC0xLTFoLTIuNWExIDEgMCAwIDEtLjgtLjRsLS45LTEuMkExIDEgMCAwIDAgMTUgM2gtMmExIDEgMCAwIDAtMSAxdjVhMSAxIDAgMCAwIDEgMVpcIi8+PHBhdGggZD1cIk0yMCAyMWExIDEgMCAwIDAgMS0xdi0zYTEgMSAwIDAgMC0xLTFoLTIuNWExIDEgMCAwIDEtLjgtLjRsLS45LTEuMmExIDEgMCAwIDAtLjgtLjRIMTNhMSAxIDAgMCAwLTEgMXY1YTEgMSAwIDAgMCAxIDFaXCIvPjxwYXRoIGQ9XCJNMyA1YTIgMiAwIDAgMCAyIDJoM1wiLz48cGF0aCBkPVwiTTMgM3YxM2EyIDIgMCAwIDAgMiAyaDNcIi8+PC9zdmc+YDtcbn1cblxuLy8gTUNQIGljb24gLSBwbHVnaW4vY29ubmVjdGlvblxuZXhwb3J0IGZ1bmN0aW9uIG1jcEljb24oKSB7XG4gIHJldHVybiBgPHN2ZyB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCIgd2lkdGg9XCIxNlwiIGhlaWdodD1cIjE2XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiIGNsYXNzPVwibHVjaWRlIGx1Y2lkZS1wbHVnXCI+PHBhdGggZD1cIk0xMiAyMnYtNVwiLz48cGF0aCBkPVwiTTkgOFYyXCIvPjxwYXRoIGQ9XCJNMTUgOFYyXCIvPjxwYXRoIGQ9XCJNMTggOHY1YTQgNCAwIDAgMS00IDRoLTRhNCA0IDAgMCAxLTQtNFY4WlwiLz48L3N2Zz5gO1xufVxuXG4vLyBDSSBpY29uIC0gd29ya2Zsb3cvYXV0b21hdGlvblxuZXhwb3J0IGZ1bmN0aW9uIGNpSWNvbigpIHtcbiAgcmV0dXJuIGA8c3ZnIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIiB3aWR0aD1cIjE2XCIgaGVpZ2h0PVwiMTZcIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIgY2xhc3M9XCJsdWNpZGUgbHVjaWRlLXdvcmtmbG93XCI+PHJlY3Qgd2lkdGg9XCI4XCIgaGVpZ2h0PVwiOFwiIHg9XCIzXCIgeT1cIjNcIiByeD1cIjJcIi8+PHBhdGggZD1cIk03IDExdjRhMiAyIDAgMCAwIDIgMmg0XCIvPjxyZWN0IHdpZHRoPVwiOFwiIGhlaWdodD1cIjhcIiB4PVwiMTNcIiB5PVwiMTNcIiByeD1cIjJcIi8+PC9zdmc+YDtcbn1cblxuLy8gR2l0SHViIGljb24gLSBnaXQvdmVyc2lvbiBjb250cm9sXG5leHBvcnQgZnVuY3Rpb24gZ2l0aHViSWNvbigpIHtcbiAgcmV0dXJuIGA8c3ZnIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIiB3aWR0aD1cIjE2XCIgaGVpZ2h0PVwiMTZcIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIgY2xhc3M9XCJsdWNpZGUgbHVjaWRlLWdpdC1icmFuY2hcIj48bGluZSB4MT1cIjZcIiB4Mj1cIjZcIiB5MT1cIjNcIiB5Mj1cIjE1XCIvPjxjaXJjbGUgY3g9XCIxOFwiIGN5PVwiNlwiIHI9XCIzXCIvPjxjaXJjbGUgY3g9XCI2XCIgY3k9XCIxOFwiIHI9XCIzXCIvPjxwYXRoIGQ9XCJtMTggOWE5IDkgMCAwIDEtOSA5XCIvPjwvc3ZnPmA7XG59XG5cbi8vIFNTTyBpY29uIC0gc2hpZWxkL3NlY3VyaXR5XG5leHBvcnQgZnVuY3Rpb24gc3NvSWNvbigpIHtcbiAgcmV0dXJuIGA8c3ZnIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIiB3aWR0aD1cIjE2XCIgaGVpZ2h0PVwiMTZcIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIgY2xhc3M9XCJsdWNpZGUgbHVjaWRlLXNoaWVsZC1jaGVja1wiPjxwYXRoIGQ9XCJNMjAgMTNjMCA1LTMuNSA3LjUtOCAxMC41QzcuNSAyMC41IDQgMTggNCAxM1Y2YTEgMSAwIDAgMSAxLTFjMiAwIDQuNS0xLjIgNi41LTIuNWExIDEgMCAwIDEgMSAwQzE0LjUgMy44IDE3IDUgMTkgNWExIDEgMCAwIDEgMSAxWlwiLz48cGF0aCBkPVwibTkgMTIgMiAyIDQtNFwiLz48L3N2Zz5gO1xufVxuXG4vLyBBY2NvdW50cyBpY29uIC0gdXNlcnNcbmV4cG9ydCBmdW5jdGlvbiBhY2NvdW50c0ljb24oKSB7XG4gIHJldHVybiBgPHN2ZyB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCIgd2lkdGg9XCIxNlwiIGhlaWdodD1cIjE2XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiIGNsYXNzPVwibHVjaWRlIGx1Y2lkZS11c2Vyc1wiPjxwYXRoIGQ9XCJNMTYgMjF2LTJhNCA0IDAgMCAwLTQtNEg2YTQgNCAwIDAgMC00IDR2MlwiLz48Y2lyY2xlIGN4PVwiOVwiIGN5PVwiN1wiIHI9XCI0XCIvPjxwYXRoIGQ9XCJNMjIgMjF2LTJhNCA0IDAgMCAwLTMtMy44N1wiLz48cGF0aCBkPVwiTTE2IDMuMTNhNCA0IDAgMCAxIDAgNy43NVwiLz48L3N2Zz5gO1xufVxuXG4vLyBBdXRoZW50aWNhdGlvbiBpY29uIC0ga2V5L2xvY2tcbmV4cG9ydCBmdW5jdGlvbiBhdXRoSWNvbigpIHtcbiAgcmV0dXJuIGA8c3ZnIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIiB3aWR0aD1cIjE2XCIgaGVpZ2h0PVwiMTZcIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIgY2xhc3M9XCJsdWNpZGUgbHVjaWRlLWtleVwiPjxwYXRoIGQ9XCJtMTUuNSA3LjUgMi4zIDIuM2ExIDEgMCAwIDAgMS40IDBsMi4xLTIuMWExIDEgMCAwIDAgMC0xLjRMMTkgNFwiLz48cGF0aCBkPVwibTIxIDItOS42IDkuNlwiLz48Y2lyY2xlIGN4PVwiNy41XCIgY3k9XCIxNS41XCIgcj1cIjUuNVwiLz48L3N2Zz5gO1xufVxuXG4vLyBJbnN0YWxsYXRpb24gaWNvbiAtIGRvd25sb2FkL3NldHVwXG5leHBvcnQgZnVuY3Rpb24gaW5zdGFsbEljb24oKSB7XG4gIHJldHVybiBgPHN2ZyB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCIgd2lkdGg9XCIxNlwiIGhlaWdodD1cIjE2XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiIGNsYXNzPVwibHVjaWRlIGx1Y2lkZS1kb3dubG9hZFwiPjxwYXRoIGQ9XCJNMjEgMTV2NGEyIDIgMCAwIDEtMiAySDVhMiAyIDAgMCAxLTItMnYtNFwiLz48cG9seWxpbmUgcG9pbnRzPVwiNywxMCAxMiwxNSAxNywxMFwiLz48bGluZSB4MT1cIjEyXCIgeDI9XCIxMlwiIHkxPVwiMTVcIiB5Mj1cIjNcIi8+PC9zdmc+YDtcbn1cblxuLy8gVGVsZW1ldHJ5IGljb24gLSBhY3Rpdml0eS9tb25pdG9yaW5nXG5leHBvcnQgZnVuY3Rpb24gdGVsZW1ldHJ5SWNvbigpIHtcbiAgcmV0dXJuIGA8c3ZnIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIiB3aWR0aD1cIjE2XCIgaGVpZ2h0PVwiMTZcIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIgY2xhc3M9XCJsdWNpZGUgbHVjaWRlLWFjdGl2aXR5XCI+PHBhdGggZD1cIm0yMiAxMi00LTQtNCA0LTQtNC00IDRcIi8+PHBhdGggZD1cIk0xNiA4bDItMiAyIDJcIi8+PC9zdmc+YDtcbn1cblxuLy8gR2l0IGZvcmdlcyBpY29uIC0gZ2l0IG5ldHdvcmtcbmV4cG9ydCBmdW5jdGlvbiBnaXRGb3JnZXNJY29uKCkge1xuICByZXR1cm4gYDxzdmcgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiIHdpZHRoPVwiMTZcIiBoZWlnaHQ9XCIxNlwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIiBjbGFzcz1cImx1Y2lkZSBsdWNpZGUtZ2l0LW1lcmdlXCI+PGNpcmNsZSBjeD1cIjE4XCIgY3k9XCIxOFwiIHI9XCIzXCIvPjxjaXJjbGUgY3g9XCI2XCIgY3k9XCI2XCIgcj1cIjNcIi8+PHBhdGggZD1cIk02IDIxVjlhOSA5IDAgMCAwIDkgOVwiLz48L3N2Zz5gO1xufVxuXG4vLyBTZWxmLWhvc3RpbmcgaWNvbiAtIHNlcnZlci9ob3N0aW5nXG5leHBvcnQgZnVuY3Rpb24gc2VsZkhvc3RpbmdJY29uKCkge1xuICByZXR1cm4gYDxzdmcgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiIHdpZHRoPVwiMTZcIiBoZWlnaHQ9XCIxNlwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIiBjbGFzcz1cImx1Y2lkZSBsdWNpZGUtc2VydmVyXCI+PHJlY3Qgd2lkdGg9XCIyMFwiIGhlaWdodD1cIjhcIiB4PVwiMlwiIHk9XCIyXCIvPjxyZWN0IHdpZHRoPVwiMjBcIiBoZWlnaHQ9XCI4XCIgeD1cIjJcIiB5PVwiMTRcIi8+PGxpbmUgeDE9XCI2XCIgeDI9XCI2LjAxXCIgeTE9XCI2XCIgeTI9XCI2XCIvPjxsaW5lIHgxPVwiNlwiIHgyPVwiNi4wMVwiIHkxPVwiMThcIiB5Mj1cIjE4XCIvPjwvc3ZnPmA7XG59XG5cbi8vIEluc3RhbGwgVHVpc3QgaWNvbiAtIGRvd25sb2FkL3NldHVwXG5leHBvcnQgZnVuY3Rpb24gaW5zdGFsbFR1aXN0SWNvbigpIHtcbiAgcmV0dXJuIGA8c3ZnIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIiB3aWR0aD1cIjE2XCIgaGVpZ2h0PVwiMTZcIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIgY2xhc3M9XCJsdWNpZGUgbHVjaWRlLWRvd25sb2FkLWNsb3VkXCI+PHBhdGggZD1cIk00IDE0Ljg5OUE3IDcgMCAxIDEgMTUuNzEgOGgxLjc5YTQuNSA0LjUgMCAwIDEgMi41IDguMjQyXCIvPjxwYXRoIGQ9XCJNMTIgMTJ2OVwiLz48cGF0aCBkPVwibTggMTcgNCA0IDQtNFwiLz48L3N2Zz5gO1xufVxuXG4vLyBHZXQgc3RhcnRlZCBpY29uIC0gcm9ja2V0L2xhdW5jaFxuZXhwb3J0IGZ1bmN0aW9uIGdldFN0YXJ0ZWRJY29uKCkge1xuICByZXR1cm4gYDxzdmcgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiIHdpZHRoPVwiMTZcIiBoZWlnaHQ9XCIxNlwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIiBjbGFzcz1cImx1Y2lkZSBsdWNpZGUtcm9ja2V0XCI+PHBhdGggZD1cIk00LjUgMTYuNWMtMS41IDEuMjYtMiA1LTIgNXMzLjc0LS41IDUtMmMuNzEtLjg0LjctMi4xMy0uMDktMi45MWEyLjE4IDIuMTggMCAwIDAtMi45MS0uMDl6XCIvPjxwYXRoIGQ9XCJtMTIgMTUtMy0zYTIyIDIyIDAgMCAxIDItMy45NUExMi44OCAxMi44OCAwIDAgMSAyMiAyYzAgMi43Mi0uNzggNy41LTYgMTFhMjIuMzUgMjIuMzUgMCAwIDEtNCAyelwiLz48cGF0aCBkPVwiTTkgMTJINHMuNTUtMy4wMyAyLTRjMS42Mi0xLjA4IDUgMCA1IDBcIi8+PHBhdGggZD1cIk0xMiAxNXY1czMuMDMtLjU1IDQtMmMxLjA4LTEuNjIgMC01IDAtNVwiLz48L3N2Zz5gO1xufVxuXG4vLyBBZ2VudGljIEJ1aWxkaW5nIGljb24gLSBjb21iaW5hdGlvbiBvZiBidWlsZGluZyBhbmQgQUkvYXV0b21hdGlvblxuZXhwb3J0IGZ1bmN0aW9uIGFnZW50aWNCdWlsZGluZ0ljb24oKSB7XG4gIHJldHVybiBgPHN2ZyB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCIgd2lkdGg9XCIxNlwiIGhlaWdodD1cIjE2XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiIGNsYXNzPVwibHVjaWRlIGx1Y2lkZS1jcHVcIj48cmVjdCB3aWR0aD1cIjE2XCIgaGVpZ2h0PVwiMTZcIiB4PVwiNFwiIHk9XCI0XCIgcng9XCIyXCIvPjxyZWN0IHdpZHRoPVwiNlwiIGhlaWdodD1cIjZcIiB4PVwiOVwiIHk9XCI5XCIgcng9XCIxXCIvPjxwYXRoIGQ9XCJtMTUgMiAwIDRcIi8+PHBhdGggZD1cIm0xNSAxOCAwIDRcIi8+PHBhdGggZD1cIm0yIDE1IDQgMFwiLz48cGF0aCBkPVwibTE4IDE1IDQgMFwiLz48cGF0aCBkPVwibTkgMiAwIDRcIi8+PHBhdGggZD1cIm05IDE4IDAgNFwiLz48cGF0aCBkPVwibTIgOSA0IDBcIi8+PHBhdGggZD1cIm0xOCA5IDQgMFwiLz48L3N2Zz5gO1xufSIsICJjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9kYXRhXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ZpbGVuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2RhdGEvZXhhbXBsZXMuanNcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfaW1wb3J0X21ldGFfdXJsID0gXCJmaWxlOi8vL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9kYXRhL2V4YW1wbGVzLmpzXCI7aW1wb3J0ICogYXMgcGF0aCBmcm9tIFwibm9kZTpwYXRoXCI7XG5pbXBvcnQgZmcgZnJvbSBcImZhc3QtZ2xvYlwiO1xuaW1wb3J0IGZzIGZyb20gXCJub2RlOmZzXCI7XG5cbmNvbnN0IGdsb2IgPSBwYXRoLmpvaW4oaW1wb3J0Lm1ldGEuZGlybmFtZSwgXCIuLi8uLi8uLi9maXh0dXJlcy8qL1JFQURNRS5tZFwiKTtcblxuZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIGxvYWREYXRhKGZpbGVzKSB7XG4gIGlmICghZmlsZXMpIHtcbiAgICBmaWxlcyA9IGZnXG4gICAgICAuc3luYyhnbG9iLCB7XG4gICAgICAgIGFic29sdXRlOiB0cnVlLFxuICAgICAgfSlcbiAgICAgIC5zb3J0KCk7XG4gIH1cbiAgcmV0dXJuIGZpbGVzLm1hcCgoZmlsZSkgPT4ge1xuICAgIGNvbnN0IGNvbnRlbnQgPSBmcy5yZWFkRmlsZVN5bmMoZmlsZSwgXCJ1dGYtOFwiKTtcbiAgICBjb25zdCB0aXRsZVJlZ2V4ID0gL14jXFxzKiguKykvbTtcbiAgICBjb25zdCB0aXRsZU1hdGNoID0gY29udGVudC5tYXRjaCh0aXRsZVJlZ2V4KTtcbiAgICByZXR1cm4ge1xuICAgICAgdGl0bGU6IHRpdGxlTWF0Y2hbMV0sXG4gICAgICBuYW1lOiBwYXRoLmJhc2VuYW1lKHBhdGguZGlybmFtZShmaWxlKSkudG9Mb3dlckNhc2UoKSxcbiAgICAgIGNvbnRlbnQ6IGNvbnRlbnQsXG4gICAgICB1cmw6IGBodHRwczovL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvdHJlZS9tYWluL2ZpeHR1cmVzLyR7cGF0aC5iYXNlbmFtZShcbiAgICAgICAgcGF0aC5kaXJuYW1lKGZpbGUpLFxuICAgICAgKX1gLFxuICAgIH07XG4gIH0pO1xufVxuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gcGF0aHMoKSB7XG4gIHJldHVybiAoYXdhaXQgbG9hZERhdGEoKSkubWFwKChpdGVtKSA9PiB7XG4gICAgcmV0dXJuIHtcbiAgICAgIHBhcmFtczoge1xuICAgICAgICBleGFtcGxlOiBpdGVtLm5hbWUsXG4gICAgICAgIHRpdGxlOiBpdGVtLnRpdGxlLFxuICAgICAgICBkZXNjcmlwdGlvbjogaXRlbS5kZXNjcmlwdGlvbixcbiAgICAgICAgdXJsOiBpdGVtLnVybCxcbiAgICAgIH0sXG4gICAgICBjb250ZW50OiBpdGVtLmNvbnRlbnQsXG4gICAgfTtcbiAgfSk7XG59XG4iLCAiY29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvZGF0YVwiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9maWxlbmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9kYXRhL3Byb2plY3QtZGVzY3JpcHRpb24uanNcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfaW1wb3J0X21ldGFfdXJsID0gXCJmaWxlOi8vL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9kYXRhL3Byb2plY3QtZGVzY3JpcHRpb24uanNcIjtpbXBvcnQgKiBhcyBwYXRoIGZyb20gXCJub2RlOnBhdGhcIjtcbmltcG9ydCBmZyBmcm9tIFwiZmFzdC1nbG9iXCI7XG5pbXBvcnQgZnMgZnJvbSBcIm5vZGU6ZnNcIjtcblxuZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIHBhdGhzKGxvY2FsZSkge1xuICByZXR1cm4gKGF3YWl0IGxvYWREYXRhKCkpLm1hcCgoaXRlbSkgPT4ge1xuICAgIHJldHVybiB7XG4gICAgICBwYXJhbXM6IHtcbiAgICAgICAgdHlwZTogaXRlbS5uYW1lLFxuICAgICAgICB0aXRsZTogaXRlbS50aXRsZSxcbiAgICAgICAgZGVzY3JpcHRpb246IGl0ZW0uZGVzY3JpcHRpb24sXG4gICAgICAgIGlkZW50aWZpZXI6IGl0ZW0uaWRlbnRpZmllcixcbiAgICAgIH0sXG4gICAgICBjb250ZW50OiBpdGVtLmNvbnRlbnQsXG4gICAgfTtcbiAgfSk7XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiBsb2FkRGF0YShsb2NhbGUpIHtcbiAgY29uc3QgZ2VuZXJhdGVkRGlyZWN0b3J5ID0gcGF0aC5qb2luKFxuICAgIGltcG9ydC5tZXRhLmRpcm5hbWUsXG4gICAgXCIuLi8uLi9kb2NzL2dlbmVyYXRlZC9tYW5pZmVzdFwiLFxuICApO1xuICBjb25zdCBmaWxlcyA9IGZnXG4gICAgLnN5bmMoXCIqKi8qLm1kXCIsIHtcbiAgICAgIGN3ZDogZ2VuZXJhdGVkRGlyZWN0b3J5LFxuICAgICAgYWJzb2x1dGU6IHRydWUsXG4gICAgICBpZ25vcmU6IFtcIioqL1JFQURNRS5tZFwiXSxcbiAgICB9KVxuICAgIC5zb3J0KCk7XG4gIHJldHVybiBmaWxlcy5tYXAoKGZpbGUpID0+IHtcbiAgICBjb25zdCBjYXRlZ29yeSA9IHBhdGguYmFzZW5hbWUocGF0aC5kaXJuYW1lKGZpbGUpKTtcbiAgICBjb25zdCBmaWxlTmFtZSA9IHBhdGguYmFzZW5hbWUoZmlsZSkucmVwbGFjZShcIi5tZFwiLCBcIlwiKTtcbiAgICByZXR1cm4ge1xuICAgICAgY2F0ZWdvcnk6IGNhdGVnb3J5LFxuICAgICAgdGl0bGU6IGZpbGVOYW1lLFxuICAgICAgbmFtZTogZmlsZU5hbWUudG9Mb3dlckNhc2UoKSxcbiAgICAgIGlkZW50aWZpZXI6IGNhdGVnb3J5ICsgXCIvXCIgKyBmaWxlTmFtZS50b0xvd2VyQ2FzZSgpLFxuICAgICAgZGVzY3JpcHRpb246IFwiXCIsXG4gICAgICBjb250ZW50OiBmcy5yZWFkRmlsZVN5bmMoZmlsZSwgXCJ1dGYtOFwiKSxcbiAgICB9O1xuICB9KTtcbn1cbiIsICJ7XG4gIFwiYXNpZGVcIjoge1xuICAgIFwidHJhbnNsYXRlXCI6IHtcbiAgICAgIFwidGl0bGVcIjoge1xuICAgICAgICBcInRleHRcIjogXCJUcmFuc2xhdGlvbiBcdUQ4M0NcdURGMERcIlxuICAgICAgfSxcbiAgICAgIFwiZGVzY3JpcHRpb25cIjoge1xuICAgICAgICBcInRleHRcIjogXCJZb3UgY2FuIHRyYW5zbGF0ZSBvciBpbXByb3ZlIHRoZSB0cmFuc2xhdGlvbiBvZiB0aGlzIHBhZ2UuXCJcbiAgICAgIH0sXG4gICAgICBcImN0YVwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIkNvbnRyaWJ1dGVcIlxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzZWFyY2hcIjoge1xuICAgIFwicGxhY2Vob2xkZXJcIjogXCJTZWFyY2hcIixcbiAgICBcInRyYW5zbGF0aW9uc1wiOiB7XG4gICAgICBcImJ1dHRvblwiOiB7XG4gICAgICAgIFwiYnV0dG9uLXRleHRcIjogXCJTZWFyY2ggZG9jdW1lbnRhdGlvblwiLFxuICAgICAgICBcImJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiU2VhcmNoIGRvY3VtZW50YXRpb25cIlxuICAgICAgfSxcbiAgICAgIFwibW9kYWxcIjoge1xuICAgICAgICBcInNlYXJjaC1ib3hcIjoge1xuICAgICAgICAgIFwicmVzZXQtYnV0dG9uLXRpdGxlXCI6IFwiQ2xlYXIgcXVlcnlcIixcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiQ2xlYXIgcXVlcnlcIixcbiAgICAgICAgICBcImNhbmNlbC1idXR0b24tdGV4dFwiOiBcIkNhbmNlbFwiLFxuICAgICAgICAgIFwiY2FuY2VsLWJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiQ2FuY2VsXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJzdGFydC1zY3JlZW5cIjoge1xuICAgICAgICAgIFwicmVjZW50LXNlYXJjaGVzLXRpdGxlXCI6IFwiU2VhcmNoIGhpc3RvcnlcIixcbiAgICAgICAgICBcIm5vLXJlY2VudC1zZWFyY2hlcy10ZXh0XCI6IFwiTm8gc2VhcmNoIGhpc3RvcnlcIixcbiAgICAgICAgICBcInNhdmUtcmVjZW50LXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJTYXZlIHRvIHNlYXJjaCBoaXN0b3J5XCIsXG4gICAgICAgICAgXCJyZW1vdmUtcmVjZW50LXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJSZW1vdmUgZnJvbSBzZWFyY2ggaGlzdG9yeVwiLFxuICAgICAgICAgIFwiZmF2b3JpdGUtc2VhcmNoZXMtdGl0bGVcIjogXCJGYXZvcml0ZXNcIixcbiAgICAgICAgICBcInJlbW92ZS1mYXZvcml0ZS1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiUmVtb3ZlIGZyb20gZmF2b3JpdGVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJlcnJvci1zY3JlZW5cIjoge1xuICAgICAgICAgIFwidGl0bGUtdGV4dFwiOiBcIlVuYWJsZSB0byByZXRyaWV2ZSByZXN1bHRzXCIsXG4gICAgICAgICAgXCJoZWxwLXRleHRcIjogXCJZb3UgbWF5IG5lZWQgdG8gY2hlY2sgeW91ciBuZXR3b3JrIGNvbm5lY3Rpb25cIlxuICAgICAgICB9LFxuICAgICAgICBcImZvb3RlclwiOiB7XG4gICAgICAgICAgXCJzZWxlY3QtdGV4dFwiOiBcIlNlbGVjdFwiLFxuICAgICAgICAgIFwibmF2aWdhdGUtdGV4dFwiOiBcIk5hdmlnYXRlXCIsXG4gICAgICAgICAgXCJjbG9zZS10ZXh0XCI6IFwiQ2xvc2VcIixcbiAgICAgICAgICBcInNlYXJjaC1ieS10ZXh0XCI6IFwiU2VhcmNoIHByb3ZpZGVyXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJuby1yZXN1bHRzLXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJuby1yZXN1bHRzLXRleHRcIjogXCJObyByZWxldmFudCByZXN1bHRzIGZvdW5kXCIsXG4gICAgICAgICAgXCJzdWdnZXN0ZWQtcXVlcnktdGV4dFwiOiBcIllvdSBtaWdodCB0cnkgcXVlcnlpbmdcIixcbiAgICAgICAgICBcInJlcG9ydC1taXNzaW5nLXJlc3VsdHMtdGV4dFwiOiBcIkRvIHlvdSB0aGluayB0aGlzIHF1ZXJ5IHNob3VsZCBoYXZlIHJlc3VsdHM/XCIsXG4gICAgICAgICAgXCJyZXBvcnQtbWlzc2luZy1yZXN1bHRzLWxpbmstdGV4dFwiOiBcIkNsaWNrIHRvIGdpdmUgZmVlZGJhY2tcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9LFxuICBcIm5hdmJhclwiOiB7XG4gICAgXCJndWlkZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiR3VpZGVzXCJcbiAgICB9LFxuICAgIFwiY2xpXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNMSVwiXG4gICAgfSxcbiAgICBcInNlcnZlclwiOiB7XG4gICAgICBcInRleHRcIjogXCJTZXJ2ZXJcIlxuICAgIH0sXG4gICAgXCJyZXNvdXJjZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiUmVzb3VyY2VzXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJyZWZlcmVuY2VzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJSZWZlcmVuY2VzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjb250cmlidXRvcnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNvbnRyaWJ1dG9yc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY2hhbmdlbG9nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDaGFuZ2Vsb2dcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9LFxuICBcInNpZGViYXJzXCI6IHtcbiAgICBcImNsaVwiOiB7XG4gICAgICBcInRleHRcIjogXCJDTElcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImNsaVwiOiB7XG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImxvZ2dpbmdcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJMb2dnaW5nXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInNoZWxsLWNvbXBsZXRpb25zXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU2hlbGwgY29tcGxldGlvbnNcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJjb21tYW5kc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29tbWFuZHNcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcInJlZmVyZW5jZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiUmVmZXJlbmNlc1wiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiZXhhbXBsZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkV4YW1wbGVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJtaWdyYXRpb25zXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJNaWdyYXRpb25zXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImZyb20tdjMtdG8tdjRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJGcm9tIHYzIHRvIHY0XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNvbnRyaWJ1dG9yc1wiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiZ2V0LXN0YXJ0ZWRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkdldCBzdGFydGVkXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJpc3N1ZS1yZXBvcnRpbmdcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIklzc3VlIHJlcG9ydGluZ1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY29kZS1yZXZpZXdzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDb2RlIHJldmlld3NcIlxuICAgICAgICB9LFxuICAgICAgICBcInByaW5jaXBsZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlByaW5jaXBsZXNcIlxuICAgICAgICB9LFxuICAgICAgICBcInRyYW5zbGF0ZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiVHJhbnNsYXRlXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjbGlcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNMSVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJsb2dnaW5nXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTG9nZ2luZ1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcInNlcnZlclwiOiB7XG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJpbnRyb2R1Y3Rpb25cIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkludHJvZHVjdGlvblwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJ3aHktc2VydmVyXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiV2h5IGEgc2VydmVyP1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJhY2NvdW50cy1hbmQtcHJvamVjdHNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJBY2NvdW50cyBhbmQgcHJvamVjdHNcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYXV0aGVudGljYXRpb25cIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJBdXRoZW50aWNhdGlvblwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJpbnRlZ3JhdGlvbnNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnRlZ3JhdGlvbnNcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJvbi1wcmVtaXNlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJPbi1wcmVtaXNlXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImluc3RhbGxcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnN0YWxsXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcIm1ldHJpY3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJNZXRyaWNzXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiYXBpLWRvY3VtZW50YXRpb25cIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkFQSSBkb2N1bWVudGF0aW9uXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJzdGF0dXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlN0YXR1c1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwibWV0cmljcy1kYXNoYm9hcmRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIk1ldHJpY3MgZGFzaGJvYXJkXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJndWlkZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiR3VpZGVzXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJ0dWlzdFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiVHVpc3RcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiYWJvdXRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJBYm91dCBUdWlzdFwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcInF1aWNrLXN0YXJ0XCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJRdWljayBzdGFydFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsLXR1aXN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zdGFsbCBUdWlzdFwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJnZXQtc3RhcnRlZFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkdldCBzdGFydGVkXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiZmVhdHVyZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkZlYXR1cmVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJkZXZlbG9wXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJEZXZlbG9wXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImdlbmVyYXRlZC1wcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkdlbmVyYXRlZCBwcm9qZWN0c1wiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcImFkb3B0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFkb3B0aW9uXCIsXG4gICAgICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgXCJuZXctcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ3JlYXRlIGEgbmV3IHByb2plY3RcIlxuICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlRyeSB3aXRoIGEgU3dpZnQgUGFja2FnZVwiXG4gICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgIFwibWlncmF0ZVwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTWlncmF0ZVwiLFxuICAgICAgICAgICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgXCJ4Y29kZS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQW4gWGNvZGUgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICAgICAgXCJzd2lmdC1wYWNrYWdlXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQSBTd2lmdCBwYWNrYWdlXCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICBcInhjb2RlZ2VuLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBbiBYY29kZUdlbiBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICBcImJhemVsLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBIEJhemVsIHByb2plY3RcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJtYW5pZmVzdHNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTWFuaWZlc3RzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZGlyZWN0b3J5LXN0cnVjdHVyZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJEaXJlY3Rvcnkgc3RydWN0dXJlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZWRpdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJFZGl0aW5nXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZGVwZW5kZW5jaWVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkRlcGVuZGVuY2llc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImNvZGUtc2hhcmluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJDb2RlIHNoYXJpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJzeW50aGVzaXplZC1maWxlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTeW50aGVzaXplZCBmaWxlc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImR5bmFtaWMtY29uZmlndXJhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJEeW5hbWljIGNvbmZpZ3VyYXRpb25cIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0ZW1wbGF0ZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVGVtcGxhdGVzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwicGx1Z2luc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJQbHVnaW5zXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiaGFzaGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJIYXNoaW5nXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiaW5zcGVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnNwZWN0XCIsXG4gICAgICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgXCJpbXBsaWNpdC1pbXBvcnRzXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJJbXBsaWNpdCBpbXBvcnRzXCJcbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0aGUtY29zdC1vZi1jb252ZW5pZW5jZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJUaGUgY29zdCBvZiBjb252ZW5pZW5jZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRtYS1hcmNoaXRlY3R1cmVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTW9kdWxhciBhcmNoaXRlY3R1cmVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJiZXN0LXByYWN0aWNlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJCZXN0IHByYWN0aWNlc1wiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJjYWNoZVwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNhY2hlXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInJlZ2lzdHJ5XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUmVnaXN0cnlcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJyZWdpc3RyeVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJSZWdpc3RyeVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGUgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImdlbmVyYXRlZC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkdlbmVyYXRlZCBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwieGNvZGVwcm9qLWludGVncmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlhjb2RlUHJvai1iYXNlZCBpbnRlZ3JhdGlvblwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU3dpZnQgcGFja2FnZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImNvbnRpbnVvdXMtaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29udGludW91cyBpbnRlZ3JhdGlvblwiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJzZWxlY3RpdmUtdGVzdGluZ1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlNlbGVjdGl2ZSB0ZXN0aW5nXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwic2VsZWN0aXZlLXRlc3RpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU2VsZWN0aXZlIHRlc3RpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlhjb2RlIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJnZW5lcmF0ZWQtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJHZW5lcmF0ZWQgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJpbnNpZ2h0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc2lnaHRzXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImJ1bmRsZS1zaXplXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQnVuZGxlIHNpemVcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJhZ2VudGljLWNvZGluZ1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQWdlbnRpYyBDb2RpbmdcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibWNwXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTUNQXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiaW50ZWdyYXRpb25zXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJJbnRlZ3JhdGlvbnNcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiY29udGludW91cy1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvbnRpbnVvdXMgaW50ZWdyYXRpb25cIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJzaGFyZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiU2hhcmVcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwicHJldmlld3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJQcmV2aWV3c1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9XG59XG4iLCAie1xuICBcImFzaWRlXCI6IHtcbiAgICBcInRyYW5zbGF0ZVwiOiB7XG4gICAgICBcInRpdGxlXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFGXHUwNDM1XHUwNDQwXHUwNDM1XHUwNDMyXHUwNDNFXHUwNDM0IFx1RDgzQ1x1REYwRFwiXG4gICAgICB9LFxuICAgICAgXCJkZXNjcmlwdGlvblwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlx1MDQxMlx1MDQ0QiBcdTA0M0NcdTA0M0VcdTA0MzZcdTA0MzVcdTA0NDJcdTA0MzUgXHUwNDNGXHUwNDM1XHUwNDQwXHUwNDM1XHUwNDMyXHUwNDM1XHUwNDQxXHUwNDQyXHUwNDM4IFx1MDQzOFx1MDQzQlx1MDQzOCBcdTA0NDNcdTA0M0JcdTA0NDNcdTA0NDdcdTA0NDhcdTA0MzhcdTA0NDJcdTA0NEMgXHUwNDNGXHUwNDM1XHUwNDQwXHUwNDM1XHUwNDMyXHUwNDNFXHUwNDM0IFx1MDQ0RFx1MDQ0Mlx1MDQzRVx1MDQzOSBcdTA0NDFcdTA0NDJcdTA0NDBcdTA0MzBcdTA0M0RcdTA0MzhcdTA0NDZcdTA0NEIuXCJcbiAgICAgIH0sXG4gICAgICBcImN0YVwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlx1MDQxMlx1MDQzRFx1MDQzNVx1MDQ0MVx1MDQ0Mlx1MDQzOCBcdTA0MzJcdTA0M0FcdTA0M0JcdTA0MzBcdTA0MzRcIlxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzZWFyY2hcIjoge1xuICAgIFwicGxhY2Vob2xkZXJcIjogXCJcdTA0MUZcdTA0M0VcdTA0MzhcdTA0NDFcdTA0M0FcIixcbiAgICBcInRyYW5zbGF0aW9uc1wiOiB7XG4gICAgICBcImJ1dHRvblwiOiB7XG4gICAgICAgIFwiYnV0dG9uLXRleHRcIjogXCJcdTA0MUZcdTA0M0VcdTA0MzhcdTA0NDFcdTA0M0EgXHUwNDM0XHUwNDNFXHUwNDNBXHUwNDQzXHUwNDNDXHUwNDM1XHUwNDNEXHUwNDQyXHUwNDMwXHUwNDQ2XHUwNDM4XHUwNDM4XCIsXG4gICAgICAgIFwiYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJcdTA0MUZcdTA0M0VcdTA0MzhcdTA0NDFcdTA0M0EgXHUwNDM0XHUwNDNFXHUwNDNBXHUwNDQzXHUwNDNDXHUwNDM1XHUwNDNEXHUwNDQyXHUwNDMwXHUwNDQ2XHUwNDM4XHUwNDM4XCJcbiAgICAgIH0sXG4gICAgICBcIm1vZGFsXCI6IHtcbiAgICAgICAgXCJzZWFyY2gtYm94XCI6IHtcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi10aXRsZVwiOiBcIlx1MDQxRVx1MDQ0N1x1MDQzOFx1MDQ0MVx1MDQ0Mlx1MDQzOFx1MDQ0Mlx1MDQ0QyBcdTA0MzdcdTA0MzBcdTA0M0ZcdTA0NDBcdTA0M0VcdTA0NDFcIixcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiXHUwNDFFXHUwNDQ3XHUwNDM4XHUwNDQxXHUwNDQyXHUwNDM4XHUwNDQyXHUwNDRDIFx1MDQzN1x1MDQzMFx1MDQzRlx1MDQ0MFx1MDQzRVx1MDQ0MVwiLFxuICAgICAgICAgIFwiY2FuY2VsLWJ1dHRvbi10ZXh0XCI6IFwiXHUwNDFFXHUwNDQyXHUwNDNDXHUwNDM1XHUwNDNEXHUwNDM4XHUwNDQyXHUwNDRDXCIsXG4gICAgICAgICAgXCJjYW5jZWwtYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJcdTA0MUVcdTA0NDJcdTA0M0NcdTA0MzVcdTA0M0RcdTA0MzhcdTA0NDJcdTA0NENcIlxuICAgICAgICB9LFxuICAgICAgICBcInN0YXJ0LXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJyZWNlbnQtc2VhcmNoZXMtdGl0bGVcIjogXCJcdTA0MThcdTA0NDFcdTA0NDJcdTA0M0VcdTA0NDBcdTA0MzhcdTA0NEYgXHUwNDNGXHUwNDNFXHUwNDM4XHUwNDQxXHUwNDNBXHUwNDMwXCIsXG4gICAgICAgICAgXCJuby1yZWNlbnQtc2VhcmNoZXMtdGV4dFwiOiBcIlx1MDQxRFx1MDQzNVx1MDQ0MiBcdTA0MzhcdTA0NDFcdTA0NDJcdTA0M0VcdTA0NDBcdTA0MzhcdTA0MzggXHUwNDNGXHUwNDNFXHUwNDM4XHUwNDQxXHUwNDNBXHUwNDMwXCIsXG4gICAgICAgICAgXCJzYXZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiXHUwNDIxXHUwNDNFXHUwNDQ1XHUwNDQwXHUwNDMwXHUwNDNEXHUwNDM4XHUwNDQyXHUwNDRDIFx1MDQzMiBcdTA0MzhcdTA0NDFcdTA0NDJcdTA0M0VcdTA0NDBcdTA0MzhcdTA0NEUgXHUwNDNGXHUwNDNFXHUwNDM4XHUwNDQxXHUwNDNBXHUwNDMwXCIsXG4gICAgICAgICAgXCJyZW1vdmUtcmVjZW50LXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJcdTA0MjNcdTA0MzRcdTA0MzBcdTA0M0JcdTA0MzhcdTA0NDJcdTA0NEMgXHUwNDM4XHUwNDM3IFx1MDQzOFx1MDQ0MVx1MDQ0Mlx1MDQzRVx1MDQ0MFx1MDQzOFx1MDQzOCBcdTA0M0ZcdTA0M0VcdTA0MzhcdTA0NDFcdTA0M0FcdTA0MzBcIixcbiAgICAgICAgICBcImZhdm9yaXRlLXNlYXJjaGVzLXRpdGxlXCI6IFwiXHUwNDE4XHUwNDM3XHUwNDMxXHUwNDQwXHUwNDMwXHUwNDNEXHUwNDNEXHUwNDNFXHUwNDM1XCIsXG4gICAgICAgICAgXCJyZW1vdmUtZmF2b3JpdGUtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlx1MDQyM1x1MDQzNFx1MDQzMFx1MDQzQlx1MDQzOFx1MDQ0Mlx1MDQ0QyBcdTA0MzhcdTA0MzcgXHUwNDM4XHUwNDM3XHUwNDMxXHUwNDQwXHUwNDMwXHUwNDNEXHUwNDNEXHUwNDNFXHUwNDMzXHUwNDNFXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJlcnJvci1zY3JlZW5cIjoge1xuICAgICAgICAgIFwidGl0bGUtdGV4dFwiOiBcIlx1MDQxRFx1MDQzNSBcdTA0NDNcdTA0MzRcdTA0MzBcdTA0MzVcdTA0NDJcdTA0NDFcdTA0NEYgXHUwNDNGXHUwNDNFXHUwNDNCXHUwNDQzXHUwNDQ3XHUwNDM4XHUwNDQyXHUwNDRDIFx1MDQ0MFx1MDQzNVx1MDQzN1x1MDQ0M1x1MDQzQlx1MDQ0Q1x1MDQ0Mlx1MDQzMFx1MDQ0Mlx1MDQ0QlwiLFxuICAgICAgICAgIFwiaGVscC10ZXh0XCI6IFwiXHUwNDEyXHUwNDNFXHUwNDM3XHUwNDNDXHUwNDNFXHUwNDM2XHUwNDNEXHUwNDNFLCBcdTA0MzJcdTA0MzBcdTA0M0MgXHUwNDNEXHUwNDM1XHUwNDNFXHUwNDMxXHUwNDQ1XHUwNDNFXHUwNDM0XHUwNDM4XHUwNDNDXHUwNDNFIFx1MDQzRlx1MDQ0MFx1MDQzRVx1MDQzMlx1MDQzNVx1MDQ0MFx1MDQzOFx1MDQ0Mlx1MDQ0QyBcdTA0NDFcdTA0MzVcdTA0NDJcdTA0MzVcdTA0MzJcdTA0M0VcdTA0MzUgXHUwNDNGXHUwNDNFXHUwNDM0XHUwNDNBXHUwNDNCXHUwNDRFXHUwNDQ3XHUwNDM1XHUwNDNEXHUwNDM4XHUwNDM1XCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJmb290ZXJcIjoge1xuICAgICAgICAgIFwic2VsZWN0LXRleHRcIjogXCJcdTA0MTJcdTA0NEJcdTA0MzFcdTA0NDBcdTA0MzBcdTA0NDJcdTA0NENcIixcbiAgICAgICAgICBcIm5hdmlnYXRlLXRleHRcIjogXCJcdTA0MUZcdTA0MzVcdTA0NDBcdTA0MzVcdTA0MzlcdTA0NDJcdTA0MzhcIixcbiAgICAgICAgICBcImNsb3NlLXRleHRcIjogXCJcdTA0MTdcdTA0MzBcdTA0M0FcdTA0NDBcdTA0NEJcdTA0NDJcdTA0NENcIixcbiAgICAgICAgICBcInNlYXJjaC1ieS10ZXh0XCI6IFwiXHUwNDFGXHUwNDNFXHUwNDM4XHUwNDQxXHUwNDNBXHUwNDNFXHUwNDMyXHUwNDMwXHUwNDRGIFx1MDQ0MVx1MDQzOFx1MDQ0MVx1MDQ0Mlx1MDQzNVx1MDQzQ1x1MDQzMFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwibm8tcmVzdWx0cy1zY3JlZW5cIjoge1xuICAgICAgICAgIFwibm8tcmVzdWx0cy10ZXh0XCI6IFwiXHUwNDIwXHUwNDM1XHUwNDM3XHUwNDQzXHUwNDNCXHUwNDRDXHUwNDQyXHUwNDMwXHUwNDQyXHUwNDRCIFx1MDQzRFx1MDQzNSBcdTA0M0RcdTA0MzBcdTA0MzlcdTA0MzRcdTA0MzVcdTA0M0RcdTA0NEJcIixcbiAgICAgICAgICBcInN1Z2dlc3RlZC1xdWVyeS10ZXh0XCI6IFwiXHUwNDEyXHUwNDRCIFx1MDQzQ1x1MDQzRVx1MDQzNlx1MDQzNVx1MDQ0Mlx1MDQzNSBcdTA0M0ZcdTA0M0VcdTA0M0ZcdTA0NDBcdTA0M0VcdTA0MzFcdTA0M0VcdTA0MzJcdTA0MzBcdTA0NDJcdTA0NEMgXHUwNDM3XHUwNDMwXHUwNDNGXHUwNDQwXHUwNDNFXHUwNDQxXHUwNDM4XHUwNDQyXHUwNDRDXCIsXG4gICAgICAgICAgXCJyZXBvcnQtbWlzc2luZy1yZXN1bHRzLXRleHRcIjogXCJcdTA0MjFcdTA0NDdcdTA0MzhcdTA0NDJcdTA0MzBcdTA0MzVcdTA0NDJcdTA0MzUsIFx1MDQ0N1x1MDQ0Mlx1MDQzRSBcdTA0NERcdTA0NDJcdTA0M0VcdTA0NDIgXHUwNDM3XHUwNDMwXHUwNDNGXHUwNDQwXHUwNDNFXHUwNDQxIFx1MDQzNFx1MDQzRVx1MDQzQlx1MDQzNlx1MDQzNVx1MDQzRCBcdTA0MzhcdTA0M0NcdTA0MzVcdTA0NDJcdTA0NEMgXHUwNDQwXHUwNDM1XHUwNDM3XHUwNDQzXHUwNDNCXHUwNDRDXHUwNDQyXHUwNDMwXHUwNDQyXHUwNDRCP1wiLFxuICAgICAgICAgIFwicmVwb3J0LW1pc3NpbmctcmVzdWx0cy1saW5rLXRleHRcIjogXCJcdTA0MURcdTA0MzBcdTA0MzZcdTA0M0NcdTA0MzhcdTA0NDJcdTA0MzUsIFx1MDQ0N1x1MDQ0Mlx1MDQzRVx1MDQzMVx1MDQ0QiBcdTA0M0VcdTA0NDFcdTA0NDJcdTA0MzBcdTA0MzJcdTA0MzhcdTA0NDJcdTA0NEMgXHUwNDNFXHUwNDQyXHUwNDM3XHUwNDRCXHUwNDMyXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJuYXZiYXJcIjoge1xuICAgIFwiZ3VpZGVzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1MDQyMFx1MDQ0M1x1MDQzQVx1MDQzRVx1MDQzMlx1MDQzRVx1MDQzNFx1MDQ0MVx1MDQ0Mlx1MDQzMlx1MDQzMFwiXG4gICAgfSxcbiAgICBcImNsaVwiOiB7XG4gICAgICBcInRleHRcIjogXCJDTElcIlxuICAgIH0sXG4gICAgXCJzZXJ2ZXJcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIxXHUwNDM1XHUwNDQwXHUwNDMyXHUwNDM1XHUwNDQwXCJcbiAgICB9LFxuICAgIFwicmVzb3VyY2VzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1MDQyMFx1MDQzNVx1MDQ0MVx1MDQ0M1x1MDQ0MFx1MDQ0MVx1MDQ0QlwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwicmVmZXJlbmNlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIxXHUwNDQxXHUwNDRCXHUwNDNCXHUwNDNBXHUwNDM4XCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjb250cmlidXRvcnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQyMVx1MDQzRVx1MDQ0M1x1MDQ0N1x1MDQzMFx1MDQ0MVx1MDQ0Mlx1MDQzRFx1MDQzOFx1MDQzQVx1MDQzOFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY2hhbmdlbG9nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTA0MThcdTA0NDFcdTA0NDJcdTA0M0VcdTA0NDBcdTA0MzhcdTA0NEYgXHUwNDM4XHUwNDM3XHUwNDNDXHUwNDM1XHUwNDNEXHUwNDM1XHUwNDNEXHUwNDM4XHUwNDM5XCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzaWRlYmFyc1wiOiB7XG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJjbGlcIjoge1xuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJsb2dnaW5nXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFCXHUwNDNFXHUwNDMzXHUwNDM4XHUwNDQwXHUwNDNFXHUwNDMyXHUwNDMwXHUwNDNEXHUwNDM4XHUwNDM1XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInNoZWxsLWNvbXBsZXRpb25zXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDEwXHUwNDMyXHUwNDQyXHUwNDNFXHUwNDM3XHUwNDMwXHUwNDMyXHUwNDM1XHUwNDQwXHUwNDQ4XHUwNDM1XHUwNDNEXHUwNDM4XHUwNDRGIFNoZWxsXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiY29tbWFuZHNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxQVx1MDQzRVx1MDQzQ1x1MDQzMFx1MDQzRFx1MDQzNFx1MDQ0QlwiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwicmVmZXJlbmNlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJcdTA0MjFcdTA0NDFcdTA0NEJcdTA0M0JcdTA0M0FcdTA0MzhcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImV4YW1wbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUZcdTA0NDBcdTA0MzhcdTA0M0NcdTA0MzVcdTA0NDBcdTA0NEJcIlxuICAgICAgICB9LFxuICAgICAgICBcIm1pZ3JhdGlvbnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIk1pZ3JhdGlvbnNcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiZnJvbS12My10by12NFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxRVx1MDQ0MiB2MyBcdTA0MzRcdTA0M0UgXHUwNDMyXHUwNDM1XHUwNDQwXHUwNDQxXHUwNDM4XHUwNDM4IHY0XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1MDQyMVx1MDQzRVx1MDQ0M1x1MDQ0N1x1MDQzMFx1MDQ0MVx1MDQ0Mlx1MDQzRFx1MDQzOFx1MDQzQVx1MDQzOFwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiZ2V0LXN0YXJ0ZWRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxRFx1MDQzMFx1MDQ0N1x1MDQzMFx1MDQzQlx1MDQzRSBcdTA0NDBcdTA0MzBcdTA0MzFcdTA0M0VcdTA0NDJcdTA0NEJcIlxuICAgICAgICB9LFxuICAgICAgICBcImlzc3VlLXJlcG9ydGluZ1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFFXHUwNDQyXHUwNDQ3XHUwNDM1XHUwNDQyIFx1MDQzRVx1MDQzMSBcdTA0M0VcdTA0NDhcdTA0MzhcdTA0MzFcdTA0M0FcdTA0MzBcdTA0NDVcIlxuICAgICAgICB9LFxuICAgICAgICBcImNvZGUtcmV2aWV3c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFBXHUwNDNFXHUwNDM0IFx1MDQ0MFx1MDQzNVx1MDQzMlx1MDQ0Q1x1MDQ0RVwiXG4gICAgICAgIH0sXG4gICAgICAgIFwicHJpbmNpcGxlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFGXHUwNDQwXHUwNDM4XHUwNDNEXHUwNDQ2XHUwNDM4XHUwNDNGXHUwNDRCXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlRyYW5zbGF0ZVwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY2xpXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDTElcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibG9nZ2luZ1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxQlx1MDQzRVx1MDQzM1x1MDQzOFx1MDQ0MFx1MDQzRVx1MDQzMlx1MDQzMFx1MDQzRFx1MDQzOFx1MDQzNVwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcInNlcnZlclwiOiB7XG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJpbnRyb2R1Y3Rpb25cIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxMlx1MDQzMlx1MDQzNVx1MDQzNFx1MDQzNVx1MDQzRFx1MDQzOFx1MDQzNVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJ3aHktc2VydmVyXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDE3XHUwNDMwXHUwNDQ3XHUwNDM1XHUwNDNDIFx1MDQ0MVx1MDQzNVx1MDQ0MFx1MDQzMlx1MDQzNVx1MDQ0MD9cIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYWNjb3VudHMtYW5kLXByb2plY3RzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDEwXHUwNDNBXHUwNDNBXHUwNDMwXHUwNDQzXHUwNDNEXHUwNDQyXHUwNDRCIFx1MDQzOCBcdTA0M0ZcdTA0NDBcdTA0M0VcdTA0MzVcdTA0M0FcdTA0NDJcdTA0NEJcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYXV0aGVudGljYXRpb25cIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MTBcdTA0MzJcdTA0NDJcdTA0M0VcdTA0NDBcdTA0MzhcdTA0MzdcdTA0MzBcdTA0NDZcdTA0MzhcdTA0NEZcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiaW50ZWdyYXRpb25zXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDE4XHUwNDNEXHUwNDQyXHUwNDM1XHUwNDMzXHUwNDQwXHUwNDMwXHUwNDQ2XHUwNDM4XHUwNDRGXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwib24tcHJlbWlzZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFCXHUwNDNFXHUwNDNBXHUwNDMwXHUwNDNCXHUwNDRDXHUwNDNEXHUwNDRCXHUwNDM5IFx1MDQ0NVx1MDQzRVx1MDQ0MVx1MDQ0Mlx1MDQzOFx1MDQzRFx1MDQzM1wiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIzXHUwNDQxXHUwNDQyXHUwNDMwXHUwNDNEXHUwNDNFXHUwNDMyXHUwNDNBXHUwNDMwXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcIm1ldHJpY3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUNcdTA0MzVcdTA0NDJcdTA0NDBcdTA0MzhcdTA0M0FcdTA0MzhcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJhcGktZG9jdW1lbnRhdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQVBJIFx1MDQzNFx1MDQzRVx1MDQzQVx1MDQ0M1x1MDQzQ1x1MDQzNVx1MDQzRFx1MDQ0Mlx1MDQzMFx1MDQ0Nlx1MDQzOFx1MDQ0RlwiXG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhdHVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTA0MjFcdTA0NDJcdTA0MzBcdTA0NDJcdTA0NDNcdTA0NDFcIlxuICAgICAgICB9LFxuICAgICAgICBcIm1ldHJpY3MtZGFzaGJvYXJkXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUZcdTA0MzBcdTA0M0RcdTA0MzVcdTA0M0JcdTA0NEMgXHUwNDNGXHUwNDNFXHUwNDNBXHUwNDMwXHUwNDM3XHUwNDMwXHUwNDQyXHUwNDM1XHUwNDNCXHUwNDM1XHUwNDM5XCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJndWlkZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIwXHUwNDQzXHUwNDNBXHUwNDNFXHUwNDMyXHUwNDNFXHUwNDM0XHUwNDQxXHUwNDQyXHUwNDMyXHUwNDMwXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJ0dWlzdFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiVHVpc3RcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiYWJvdXRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUZcdTA0NDBcdTA0M0UgVHVpc3RcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJxdWljay1zdGFydFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDExXHUwNDRCXHUwNDQxXHUwNDQyXHUwNDQwXHUwNDRCXHUwNDM5IFx1MDQ0MVx1MDQ0Mlx1MDQzMFx1MDQ0MFx1MDQ0MlwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJpbnN0YWxsLXR1aXN0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIzXHUwNDQxXHUwNDQyXHUwNDMwXHUwNDNEXHUwNDNFXHUwNDMyXHUwNDNBXHUwNDMwIFR1aXN0XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImdldC1zdGFydGVkXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFEXHUwNDMwXHUwNDQ3XHUwNDMwXHUwNDNCXHUwNDNFIFx1MDQ0MFx1MDQzMFx1MDQzMVx1MDQzRVx1MDQ0Mlx1MDQ0QlwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImZlYXR1cmVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTA0MTJcdTA0M0VcdTA0MzdcdTA0M0NcdTA0M0VcdTA0MzZcdTA0M0RcdTA0M0VcdTA0NDFcdTA0NDJcdTA0MzhcIlxuICAgICAgICB9LFxuICAgICAgICBcImRldmVsb3BcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQyMFx1MDQzMFx1MDQzN1x1MDQ0MFx1MDQzMFx1MDQzMVx1MDQzRVx1MDQ0Mlx1MDQzQVx1MDQzMFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJnZW5lcmF0ZWQtcHJvamVjdHNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MjFcdTA0MzNcdTA0MzVcdTA0M0RcdTA0MzVcdTA0NDBcdTA0MzhcdTA0NDBcdTA0M0VcdTA0MzJcdTA0MzBcdTA0M0RcdTA0M0RcdTA0NEJcdTA0MzUgXHUwNDNGXHUwNDQwXHUwNDNFXHUwNDM1XHUwNDNBXHUwNDQyXHUwNDRCXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwiYWRvcHRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDEyXHUwNDRCXHUwNDMxXHUwNDNFXHUwNDQwXCIsXG4gICAgICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgXCJuZXctcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIxXHUwNDNFXHUwNDM3XHUwNDM0XHUwNDMwXHUwNDNEXHUwNDM4XHUwNDM1IFx1MDQzRFx1MDQzRVx1MDQzMlx1MDQzRVx1MDQzM1x1MDQzRSBcdTA0M0ZcdTA0NDBcdTA0M0VcdTA0MzVcdTA0M0FcdTA0NDJcdTA0MzBcIlxuICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxRlx1MDQzRVx1MDQzRlx1MDQ0MFx1MDQzRVx1MDQzMVx1MDQ0M1x1MDQzOVx1MDQ0Mlx1MDQzNSBcdTA0NDEgU3dpZnQgUGFja2FnZVwiXG4gICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgIFwibWlncmF0ZVwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFDXHUwNDM4XHUwNDMzXHUwNDQwXHUwNDMwXHUwNDQ2XHUwNDM4XHUwNDRGXCIsXG4gICAgICAgICAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUZcdTA0NDBcdTA0M0VcdTA0MzVcdTA0M0FcdTA0NDIgWGNvZGVcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxRlx1MDQzMFx1MDQzQVx1MDQzNVx1MDQ0MiBTd2lmdFwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICAgICAgXCJ4Y29kZWdlbi1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFGXHUwNDQwXHUwNDNFXHUwNDM1XHUwNDNBXHUwNDQyIFhjb2RlR2VuXCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICBcImJhemVsLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUZcdTA0NDBcdTA0M0VcdTA0MzVcdTA0M0FcdTA0NDIgQmF6ZWxcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJtYW5pZmVzdHNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFDXHUwNDMwXHUwNDNEXHUwNDM4XHUwNDQ0XHUwNDM1XHUwNDQxXHUwNDQyXHUwNDRCXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZGlyZWN0b3J5LXN0cnVjdHVyZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MjFcdTA0NDJcdTA0NDBcdTA0NDNcdTA0M0FcdTA0NDJcdTA0NDNcdTA0NDBcdTA0MzAgXHUwNDM0XHUwNDM4XHUwNDQwXHUwNDM1XHUwNDNBXHUwNDQyXHUwNDNFXHUwNDQwXHUwNDM4XHUwNDM5XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZWRpdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MjBcdTA0MzVcdTA0MzRcdTA0MzBcdTA0M0FcdTA0NDJcdTA0MzhcdTA0NDBcdTA0M0VcdTA0MzJcdTA0MzBcdTA0M0RcdTA0MzhcdTA0MzVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkZXBlbmRlbmNpZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDE3XHUwNDMwXHUwNDMyXHUwNDM4XHUwNDQxXHUwNDM4XHUwNDNDXHUwNDNFXHUwNDQxXHUwNDQyXHUwNDM4XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiY29kZS1zaGFyaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQyMVx1MDQzRVx1MDQzMlx1MDQzQ1x1MDQzNVx1MDQ0MVx1MDQ0Mlx1MDQzRFx1MDQzRVx1MDQzNSBcdTA0MzhcdTA0NDFcdTA0M0ZcdTA0M0VcdTA0M0JcdTA0NENcdTA0MzdcdTA0M0VcdTA0MzJcdTA0MzBcdTA0M0RcdTA0MzhcdTA0MzUgXHUwNDNBXHUwNDNFXHUwNDM0XHUwNDMwXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwic3ludGhlc2l6ZWQtZmlsZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIxXHUwNDM4XHUwNDNEXHUwNDQyXHUwNDM1XHUwNDM3XHUwNDM4XHUwNDQwXHUwNDNFXHUwNDMyXHUwNDMwXHUwNDNEXHUwNDNEXHUwNDRCXHUwNDM1IFx1MDQ0NFx1MDQzMFx1MDQzOVx1MDQzQlx1MDQ0QlwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImR5bmFtaWMtY29uZmlndXJhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MTRcdTA0MzhcdTA0M0RcdTA0MzBcdTA0M0NcdTA0MzhcdTA0NDdcdTA0MzVcdTA0NDFcdTA0M0FcdTA0MzBcdTA0NEYgXHUwNDNBXHUwNDNFXHUwNDNEXHUwNDQ0XHUwNDM4XHUwNDMzXHUwNDQzXHUwNDQwXHUwNDMwXHUwNDQ2XHUwNDM4XHUwNDRGXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidGVtcGxhdGVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQyOFx1MDQzMFx1MDQzMVx1MDQzQlx1MDQzRVx1MDQzRFx1MDQ0QlwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInBsdWdpbnNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFGXHUwNDNCXHUwNDMwXHUwNDMzXHUwNDM4XHUwNDNEXHUwNDRCXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiaGFzaGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MjVcdTA0NERcdTA0NDhcdTA0MzhcdTA0NDBcdTA0M0VcdTA0MzJcdTA0MzBcdTA0M0RcdTA0MzhcdTA0MzVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJpbnNwZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxOFx1MDQ0MVx1MDQ0MVx1MDQzQlx1MDQzNVx1MDQzNFx1MDQzRVx1MDQzMlx1MDQzMFx1MDQ0Mlx1MDQ0Q1wiLFxuICAgICAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgICAgIFwiaW1wbGljaXQtaW1wb3J0c1wiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFEXHUwNDM1XHUwNDRGXHUwNDMyXHUwNDNEXHUwNDRCXHUwNDM1IFx1MDQzOFx1MDQzQ1x1MDQzRlx1MDQzRVx1MDQ0MFx1MDQ0Mlx1MDQ0QlwiXG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidGhlLWNvc3Qtb2YtY29udmVuaWVuY2VcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDIxXHUwNDQyXHUwNDNFXHUwNDM4XHUwNDNDXHUwNDNFXHUwNDQxXHUwNDQyXHUwNDRDIFx1MDQ0M1x1MDQzNFx1MDQzRVx1MDQzMVx1MDQ0MVx1MDQ0Mlx1MDQzMlx1MDQzMFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRtYS1hcmNoaXRlY3R1cmVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDFDXHUwNDNFXHUwNDM0XHUwNDQzXHUwNDNCXHUwNDRDXHUwNDNEXHUwNDMwXHUwNDRGIFx1MDQzMFx1MDQ0MFx1MDQ0NVx1MDQzOFx1MDQ0Mlx1MDQzNVx1MDQzQVx1MDQ0Mlx1MDQ0M1x1MDQ0MFx1MDQzMFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImJlc3QtcHJhY3RpY2VzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxQlx1MDQ0M1x1MDQ0N1x1MDQ0OFx1MDQzOFx1MDQzNSBcdTA0M0ZcdTA0NDBcdTA0MzBcdTA0M0FcdTA0NDJcdTA0MzhcdTA0M0FcdTA0MzhcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiY2FjaGVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUFcdTA0NERcdTA0NDhcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwicmVnaXN0cnlcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MjBcdTA0MzVcdTA0MzVcdTA0NDFcdTA0NDJcdTA0NDBcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJyZWdpc3RyeVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MjBcdTA0MzVcdTA0MzVcdTA0NDFcdTA0NDJcdTA0NDBcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxRlx1MDQ0MFx1MDQzRVx1MDQzNVx1MDQzQVx1MDQ0MiBYY29kZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImdlbmVyYXRlZC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQyMVx1MDQzM1x1MDQzNVx1MDQzRFx1MDQzNVx1MDQ0MFx1MDQzOFx1MDQ0MFx1MDQzRVx1MDQzMlx1MDQzMFx1MDQzRFx1MDQzRFx1MDQ0Qlx1MDQzOSBcdTA0M0ZcdTA0NDBcdTA0M0VcdTA0MzVcdTA0M0FcdTA0NDJcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZXByb2otaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDE4XHUwNDNEXHUwNDQyXHUwNDM1XHUwNDMzXHUwNDQwXHUwNDMwXHUwNDQ2XHUwNDM4XHUwNDRGIFx1MDQzRFx1MDQzMCBcdTA0M0VcdTA0NDFcdTA0M0RcdTA0M0VcdTA0MzJcdTA0MzUgWGNvZGVQcm9qXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUZcdTA0MzBcdTA0M0FcdTA0MzVcdTA0NDIgU3dpZnRcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJjb250aW51b3VzLWludGVncmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvbnRpbnVvdXMgaW50ZWdyYXRpb25cIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwic2VsZWN0aXZlLXRlc3RpbmdcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MTJcdTA0NEJcdTA0MzFcdTA0M0VcdTA0NDBcdTA0M0VcdTA0NDdcdTA0M0RcdTA0M0VcdTA0MzUgXHUwNDQyXHUwNDM1XHUwNDQxXHUwNDQyXHUwNDM4XHUwNDQwXHUwNDNFXHUwNDMyXHUwNDMwXHUwNDNEXHUwNDM4XHUwNDM1XCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwic2VsZWN0aXZlLXRlc3RpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUwNDEyXHUwNDRCXHUwNDMxXHUwNDNFXHUwNDQwXHUwNDNFXHUwNDQ3XHUwNDNEXHUwNDNFXHUwNDM1IFx1MDQ0Mlx1MDQzNVx1MDQ0MVx1MDQ0Mlx1MDQzOFx1MDQ0MFx1MDQzRVx1MDQzMlx1MDQzMFx1MDQzRFx1MDQzOFx1MDQzNVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGUgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImdlbmVyYXRlZC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQyMVx1MDQzM1x1MDQzNVx1MDQzRFx1MDQzNVx1MDQ0MFx1MDQzOFx1MDQ0MFx1MDQzRVx1MDQzMlx1MDQzMFx1MDQzRFx1MDQzRFx1MDQ0Qlx1MDQzOSBcdTA0M0ZcdTA0NDBcdTA0M0VcdTA0MzVcdTA0M0FcdTA0NDJcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiaW5zaWdodHNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MTBcdTA0M0RcdTA0MzBcdTA0M0JcdTA0MzhcdTA0NDJcdTA0MzhcdTA0M0FcdTA0MzBcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYnVuZGxlLXNpemVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJCdW5kbGUgc2l6ZVwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImFnZW50aWMtY29kaW5nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTA0MTBcdTA0MzNcdTA0MzVcdTA0M0RcdTA0NDJcdTA0M0RcdTA0M0VcdTA0MzUgXHUwNDFBXHUwNDNFXHUwNDM0XHUwNDM4XHUwNDQwXHUwNDNFXHUwNDMyXHUwNDMwXHUwNDNEXHUwNDM4XHUwNDM1XCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIm1jcFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxRlx1MDQ0MFx1MDQzRVx1MDQ0Mlx1MDQzRVx1MDQzQVx1MDQzRVx1MDQzQiBcdTA0M0FcdTA0M0VcdTA0M0RcdTA0NDJcdTA0MzVcdTA0M0FcdTA0NDFcdTA0NDJcdTA0MzAgXHUwNDNDXHUwNDNFXHUwNDM0XHUwNDM1XHUwNDNCXHUwNDM4IChNQ1ApXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiaW50ZWdyYXRpb25zXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJJbnRlZ3JhdGlvbnNcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiY29udGludW91cy1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDQxRFx1MDQzNVx1MDQzRlx1MDQ0MFx1MDQzNVx1MDQ0MFx1MDQ0Qlx1MDQzMlx1MDQzRFx1MDQzMFx1MDQ0RiBcdTA0MzhcdTA0M0RcdTA0NDJcdTA0MzVcdTA0MzNcdTA0NDBcdTA0MzBcdTA0NDZcdTA0MzhcdTA0NEYgKENJKVwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcInNoYXJlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUZcdTA0M0VcdTA0MzRcdTA0MzVcdTA0M0JcdTA0MzhcdTA0NDJcdTA0NENcdTA0NDFcdTA0NEZcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwicHJldmlld3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTA0MUZcdTA0NDBcdTA0MzVcdTA0MzJcdTA0NENcdTA0NEVcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfVxufVxuIiwgIntcbiAgXCJhc2lkZVwiOiB7XG4gICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgXCJ0aXRsZVwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlRyYW5zbGF0aW9uIFx1RDgzQ1x1REYwRFwiXG4gICAgICB9LFxuICAgICAgXCJkZXNjcmlwdGlvblwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlx1Qzc3NCBcdUQzOThcdUM3NzRcdUM5QzBcdUI5N0MgXHVCQzg4XHVDNUVEXHVENTU4XHVBQzcwXHVCMDk4IFx1QUUzMFx1Qzg3NCBcdUJDODhcdUM1RURcdUM3NDQgXHVBQzFDXHVDMTIwXHVENTYwIFx1QzIxOCBcdUM3ODhcdUMyQjVcdUIyQzhcdUIyRTQuXCJcbiAgICAgIH0sXG4gICAgICBcImN0YVwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlx1QUUzMFx1QzVFQ1wiXG4gICAgICB9XG4gICAgfVxuICB9LFxuICBcInNlYXJjaFwiOiB7XG4gICAgXCJwbGFjZWhvbGRlclwiOiBcIlx1QUM4MFx1QzBDOVwiLFxuICAgIFwidHJhbnNsYXRpb25zXCI6IHtcbiAgICAgIFwiYnV0dG9uXCI6IHtcbiAgICAgICAgXCJidXR0b24tdGV4dFwiOiBcIlx1QkIzOFx1QzExQyBcdUFDODBcdUMwQzlcIixcbiAgICAgICAgXCJidXR0b24tYXJpYS1sYWJlbFwiOiBcIlx1QkIzOFx1QzExQyBcdUFDODBcdUMwQzlcIlxuICAgICAgfSxcbiAgICAgIFwibW9kYWxcIjoge1xuICAgICAgICBcInNlYXJjaC1ib3hcIjoge1xuICAgICAgICAgIFwicmVzZXQtYnV0dG9uLXRpdGxlXCI6IFwiXHVDRkZDXHVCOUFDIFx1Q0QwOFx1QUUzMFx1RDY1NFwiLFxuICAgICAgICAgIFwicmVzZXQtYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJcdUNGRkNcdUI5QUMgXHVDRDA4XHVBRTMwXHVENjU0XCIsXG4gICAgICAgICAgXCJjYW5jZWwtYnV0dG9uLXRleHRcIjogXCJcdUNERThcdUMxOENcIixcbiAgICAgICAgICBcImNhbmNlbC1idXR0b24tYXJpYS1sYWJlbFwiOiBcIlx1Q0RFOFx1QzE4Q1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhcnQtc2NyZWVuXCI6IHtcbiAgICAgICAgICBcInJlY2VudC1zZWFyY2hlcy10aXRsZVwiOiBcIlx1QUM4MFx1QzBDOSBcdUM3NzRcdUI4MjVcIixcbiAgICAgICAgICBcIm5vLXJlY2VudC1zZWFyY2hlcy10ZXh0XCI6IFwiXHVBQzgwXHVDMEM5IFx1Qzc3NFx1QjgyNVx1Qzc3NCBcdUM1QzZcdUM3NENcIixcbiAgICAgICAgICBcInNhdmUtcmVjZW50LXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJcdUFDODBcdUMwQzkgXHVDNzc0XHVCODI1IFx1QzgwMFx1QzdBNVwiLFxuICAgICAgICAgIFwicmVtb3ZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiXHVBQzgwXHVDMEM5IFx1Qzc3NFx1QjgyNSBcdUMwQURcdUM4MUNcIixcbiAgICAgICAgICBcImZhdm9yaXRlLXNlYXJjaGVzLXRpdGxlXCI6IFwiXHVDOTkwXHVBQ0E4XHVDQzNFXHVBRTMwXCIsXG4gICAgICAgICAgXCJyZW1vdmUtZmF2b3JpdGUtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlx1Qzk5MFx1QUNBOFx1Q0MzRVx1QUUzMCBcdUMwQURcdUM4MUNcIlxuICAgICAgICB9LFxuICAgICAgICBcImVycm9yLXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJ0aXRsZS10ZXh0XCI6IFwiXHVBQ0IwXHVBQ0ZDXHVCOTdDIFx1QkMxQlx1Qzc0NCBcdUMyMTggXHVDNUM2XHVDNzRDXCIsXG4gICAgICAgICAgXCJoZWxwLXRleHRcIjogXCJcdUIxMjRcdUQyQjhcdUM2Q0NcdUQwNkMgXHVDNUYwXHVBQ0IwXHVDNzQ0IFx1RDY1NVx1Qzc3OFx1RDU3NFx1QzhGQ1x1QzEzOFx1QzY5NFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiZm9vdGVyXCI6IHtcbiAgICAgICAgICBcInNlbGVjdC10ZXh0XCI6IFwiXHVDMTIwXHVEMEREXCIsXG4gICAgICAgICAgXCJuYXZpZ2F0ZS10ZXh0XCI6IFwiXHVEMEQwXHVDMEM5XCIsXG4gICAgICAgICAgXCJjbG9zZS10ZXh0XCI6IFwiXHVCMkVCXHVBRTMwXCIsXG4gICAgICAgICAgXCJzZWFyY2gtYnktdGV4dFwiOiBcIlx1QUM4MFx1QzBDOSBcdUM4MUNcdUFDRjVcdUM3OTBcIlxuICAgICAgICB9LFxuICAgICAgICBcIm5vLXJlc3VsdHMtc2NyZWVuXCI6IHtcbiAgICAgICAgICBcIm5vLXJlc3VsdHMtdGV4dFwiOiBcIlx1QUQwMFx1QjgyOFx1QjQxQyBcdUFDQjBcdUFDRkNcdUI5N0MgXHVDQzNFXHVDNzQ0IFx1QzIxOCBcdUM1QzZcdUM3NENcIixcbiAgICAgICAgICBcInN1Z2dlc3RlZC1xdWVyeS10ZXh0XCI6IFwiXHVCMkU0XHVCOTc4IFx1QUM4MFx1QzBDOVx1QzVCNFx1Qjk3QyBcdUM3ODVcdUI4MjVcdUQ1NzRcdUJDRjRcdUMxMzhcdUM2OTRcIixcbiAgICAgICAgICBcInJlcG9ydC1taXNzaW5nLXJlc3VsdHMtdGV4dFwiOiBcIlx1QUM4MFx1QzBDOSBcdUFDQjBcdUFDRkNcdUFDMDAgXHVDNzg4XHVDNUI0XHVDNTdDIFx1RDU1Q1x1QjJFNFx1QUNFMCBcdUMwRERcdUFDMDFcdUQ1NThcdUIwOThcdUM2OTQ/XCIsXG4gICAgICAgICAgXCJyZXBvcnQtbWlzc2luZy1yZXN1bHRzLWxpbmstdGV4dFwiOiBcIlx1RDUzQ1x1QjREQ1x1QkMzMVx1RDU1OFx1QUUzMFwiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwibmF2YmFyXCI6IHtcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJcdUM1NDhcdUIwQjRcdUMxMUNcIlxuICAgIH0sXG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCJcbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1QzExQ1x1QkM4NFwiXG4gICAgfSxcbiAgICBcInJlc291cmNlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJcdUI5QUNcdUMxOENcdUMyQTRcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInJlZmVyZW5jZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1Q0MzOFx1QUNFMFx1Qzc5MFx1QjhDQ1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdUFFMzBcdUM1RUNcdUM3OTBcdUI0RTRcIlxuICAgICAgICB9LFxuICAgICAgICBcImNoYW5nZWxvZ1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHVDMjE4XHVDODE1XHVDMEFDXHVENTZEXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzaWRlYmFyc1wiOiB7XG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJjbGlcIjoge1xuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJsb2dnaW5nXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHVCODVDXHVBRTQ1XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInNoZWxsLWNvbXBsZXRpb25zXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU2hlbGwgY29tcGxldGlvbnNcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJjb21tYW5kc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29tbWFuZHNcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcInJlZmVyZW5jZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiUmVmZXJlbmNlc1wiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiZXhhbXBsZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkV4YW1wbGVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJtaWdyYXRpb25zXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJNaWdyYXRpb25zXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImZyb20tdjMtdG8tdjRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJGcm9tIHYzIHRvIHY0XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNvbnRyaWJ1dG9yc1wiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiZ2V0LXN0YXJ0ZWRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkdldCBzdGFydGVkXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJpc3N1ZS1yZXBvcnRpbmdcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIklzc3VlIHJlcG9ydGluZ1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY29kZS1yZXZpZXdzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDb2RlIHJldmlld3NcIlxuICAgICAgICB9LFxuICAgICAgICBcInByaW5jaXBsZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlByaW5jaXBsZXNcIlxuICAgICAgICB9LFxuICAgICAgICBcInRyYW5zbGF0ZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiVHJhbnNsYXRlXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjbGlcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNMSVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJsb2dnaW5nXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHVCODVDXHVBRTQ1XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImludHJvZHVjdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiSW50cm9kdWN0aW9uXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIndoeS1zZXJ2ZXJcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJXaHkgYSBzZXJ2ZXI/XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImFjY291bnRzLWFuZC1wcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFjY291bnRzIGFuZCBwcm9qZWN0c1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJhdXRoZW50aWNhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkF1dGhlbnRpY2F0aW9uXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImludGVncmF0aW9uc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkludGVncmF0aW9uc1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcIm9uLXByZW1pc2VcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIk9uLXByZW1pc2VcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiaW5zdGFsbFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3RhbGxcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwibWV0cmljc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1ldHJpY3NcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJhcGktZG9jdW1lbnRhdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQVBJIGRvY3VtZW50YXRpb25cIlxuICAgICAgICB9LFxuICAgICAgICBcInN0YXR1c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiU3RhdHVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJtZXRyaWNzLWRhc2hib2FyZFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHVEMUI1XHVBQ0M0IFx1RDYwNFx1RDY2OVx1RDMxMFwiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwiZ3VpZGVzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1QzU0OFx1QjBCNFx1QzExQ1wiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwidHVpc3RcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlR1aXN0XCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImFib3V0XCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQWJvdXQgVHVpc3RcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJxdWljay1zdGFydFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiUXVpY2sgc3RhcnRcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiaW5zdGFsbC10dWlzdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3RhbGwgVHVpc3RcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiZ2V0LXN0YXJ0ZWRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJHZXQgc3RhcnRlZFwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImZlYXR1cmVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdUFFMzBcdUIyQTVcIlxuICAgICAgICB9LFxuICAgICAgICBcImRldmVsb3BcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkRldmVsb3BcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiZ2VuZXJhdGVkLXByb2plY3RzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiR2VuZXJhdGVkIHByb2plY3RzXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwiYWRvcHRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQWRvcHRpb25cIixcbiAgICAgICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgICAgICBcIm5ldy1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJDcmVhdGUgYSBuZXcgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVHJ5IHdpdGggYSBTd2lmdCBQYWNrYWdlXCJcbiAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgXCJtaWdyYXRlXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJNaWdyYXRlXCIsXG4gICAgICAgICAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBbiBYY29kZSBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBIFN3aWZ0IHBhY2thZ2VcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwieGNvZGVnZW4tcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFuIFhjb2RlR2VuIHByb2plY3RcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwiYmF6ZWwtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkEgQmF6ZWwgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcIm1hbmlmZXN0c1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJNYW5pZmVzdHNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkaXJlY3Rvcnktc3RydWN0dXJlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkRpcmVjdG9yeSBzdHJ1Y3R1cmVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJlZGl0aW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkVkaXRpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkZXBlbmRlbmNpZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRGVwZW5kZW5jaWVzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiY29kZS1zaGFyaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvZGUgc2hhcmluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInN5bnRoZXNpemVkLWZpbGVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlN5bnRoZXNpemVkIGZpbGVzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZHluYW1pYy1jb25maWd1cmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkR5bmFtaWMgY29uZmlndXJhdGlvblwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRlbXBsYXRlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJUZW1wbGF0ZXNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJwbHVnaW5zXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlBsdWdpbnNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJoYXNoaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkhhc2hpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJpbnNwZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3BlY3RcIixcbiAgICAgICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgICAgICBcImltcGxpY2l0LWltcG9ydHNcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkltcGxpY2l0IGltcG9ydHNcIlxuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRoZS1jb3N0LW9mLWNvbnZlbmllbmNlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlRoZSBjb3N0IG9mIGNvbnZlbmllbmNlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidG1hLWFyY2hpdGVjdHVyZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJNb2R1bGFyIGFyY2hpdGVjdHVyZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImJlc3QtcHJhY3RpY2VzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkJlc3QgcHJhY3RpY2VzXCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImNhY2hlXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ2FjaGVcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwicmVnaXN0cnlcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJSZWdpc3RyeVwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcInJlZ2lzdHJ5XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlJlZ2lzdHJ5XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwieGNvZGUtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJYY29kZSBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZ2VuZXJhdGVkLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiR2VuZXJhdGVkIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZXByb2otaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGVQcm9qLWJhc2VkIGludGVncmF0aW9uXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTd2lmdCBwYWNrYWdlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiY29udGludW91cy1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJDb250aW51b3VzIGludGVncmF0aW9uXCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInNlbGVjdGl2ZS10ZXN0aW5nXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU2VsZWN0aXZlIHRlc3RpbmdcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJzZWxlY3RpdmUtdGVzdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTZWxlY3RpdmUgdGVzdGluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGUgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImdlbmVyYXRlZC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkdlbmVyYXRlZCBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImluc2lnaHRzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zaWdodHNcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYnVuZGxlLXNpemVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJCdW5kbGUgc2l6ZVwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImFnZW50aWMtY29kaW5nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdUM1RDBcdUM3NzRcdUM4MDRcdUQyRjEgXHVDRjU0XHVCNTI5XCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIm1jcFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1vZGVsIENvbnRleHQgUHJvdG9jb2wgKE1DUClcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJpbnRlZ3JhdGlvbnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkludGVncmF0aW9uc1wiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJjb250aW51b3VzLWludGVncmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29udGludW91cyBpbnRlZ3JhdGlvblwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcInNoYXJlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJTaGFyZVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJwcmV2aWV3c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlByZXZpZXdzXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH1cbn1cbiIsICJ7XG4gIFwiYXNpZGVcIjoge1xuICAgIFwidHJhbnNsYXRlXCI6IHtcbiAgICAgIFwidGl0bGVcIjoge1xuICAgICAgICBcInRleHRcIjogXCJcdTdGRkJcdThBMzMgXHVEODNDXHVERjBEXCJcbiAgICAgIH0sXG4gICAgICBcImRlc2NyaXB0aW9uXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMDUzXHUzMDZFXHUzMERBXHUzMEZDXHUzMEI4XHUzMDZFXHU3RkZCXHU4QTMzXHUzMDkyXHU4ODRDXHUzMDYzXHUzMDVGXHUzMDhBXHUzMDAxXHU2NTM5XHU1NTg0XHUzMDU3XHUzMDVGXHUzMDhBXHUzMDU5XHUzMDhCXHUzMDUzXHUzMDY4XHUzMDRDXHUzMDY3XHUzMDREXHUzMDdFXHUzMDU5XHUzMDAyXCJcbiAgICAgIH0sXG4gICAgICBcImN0YVwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlx1MzBCM1x1MzBGM1x1MzBDOFx1MzBFQVx1MzBEM1x1MzBFNVx1MzBGQ1x1MzBDOFx1MzA1OVx1MzA4QlwiXG4gICAgICB9XG4gICAgfVxuICB9LFxuICBcInNlYXJjaFwiOiB7XG4gICAgXCJwbGFjZWhvbGRlclwiOiBcIlx1NjkxQ1x1N0QyMlwiLFxuICAgIFwidHJhbnNsYXRpb25zXCI6IHtcbiAgICAgIFwiYnV0dG9uXCI6IHtcbiAgICAgICAgXCJidXR0b24tdGV4dFwiOiBcIlx1MzBDOVx1MzBBRFx1MzBFNVx1MzBFMVx1MzBGM1x1MzBDOFx1MzA5Mlx1NjkxQ1x1N0QyMlwiLFxuICAgICAgICBcImJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiXHUzMEM5XHUzMEFEXHUzMEU1XHUzMEUxXHUzMEYzXHUzMEM4XHUzMDkyXHU2OTFDXHU3RDIyXCJcbiAgICAgIH0sXG4gICAgICBcIm1vZGFsXCI6IHtcbiAgICAgICAgXCJzZWFyY2gtYm94XCI6IHtcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi10aXRsZVwiOiBcIlx1NjkxQ1x1N0QyMlx1MzBBRFx1MzBGQ1x1MzBFRlx1MzBGQ1x1MzBDOVx1MzA5Mlx1NTI0QVx1OTY2NFwiLFxuICAgICAgICAgIFwicmVzZXQtYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJcdTY5MUNcdTdEMjJcdTMwQURcdTMwRkNcdTMwRUZcdTMwRkNcdTMwQzlcdTMwOTJcdTUyNEFcdTk2NjRcIixcbiAgICAgICAgICBcImNhbmNlbC1idXR0b24tdGV4dFwiOiBcIlx1MzBBRFx1MzBFM1x1MzBGM1x1MzBCQlx1MzBFQlwiLFxuICAgICAgICAgIFwiY2FuY2VsLWJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiXHUzMEFEXHUzMEUzXHUzMEYzXHUzMEJCXHUzMEVCXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJzdGFydC1zY3JlZW5cIjoge1xuICAgICAgICAgIFwicmVjZW50LXNlYXJjaGVzLXRpdGxlXCI6IFwiXHU1QzY1XHU2Qjc0XHUzMDkyXHU2OTFDXHU3RDIyXCIsXG4gICAgICAgICAgXCJuby1yZWNlbnQtc2VhcmNoZXMtdGV4dFwiOiBcIlx1NjkxQ1x1N0QyMlx1NUM2NVx1NkI3NFx1MzA2Rlx1MzA0Mlx1MzA4QVx1MzA3RVx1MzA1Qlx1MzA5M1wiLFxuICAgICAgICAgIFwic2F2ZS1yZWNlbnQtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlx1NjkxQ1x1N0QyMlx1NUM2NVx1NkI3NFx1MzA2Qlx1NEZERFx1NUI1OFwiLFxuICAgICAgICAgIFwicmVtb3ZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiXHU2OTFDXHU3RDIyXHU1QzY1XHU2Qjc0XHUzMDRCXHUzMDg5XHU1MjRBXHU5NjY0XHUzMDU5XHUzMDhCXCIsXG4gICAgICAgICAgXCJmYXZvcml0ZS1zZWFyY2hlcy10aXRsZVwiOiBcIlx1MzA0QVx1NkMxN1x1MzA2Qlx1NTE2NVx1MzA4QVwiLFxuICAgICAgICAgIFwicmVtb3ZlLWZhdm9yaXRlLXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJcdTMwNEFcdTZDMTdcdTMwNkJcdTUxNjVcdTMwOEFcdTMwNEJcdTMwODlcdTUyNEFcdTk2NjRcIlxuICAgICAgICB9LFxuICAgICAgICBcImVycm9yLXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJ0aXRsZS10ZXh0XCI6IFwiXHU3RDUwXHU2NzlDXHUzMDkyXHU1M0Q2XHU1Rjk3XHUzMDY3XHUzMDREXHUzMDdFXHUzMDVCXHUzMDkzXHUzMDY3XHUzMDU3XHUzMDVGXCIsXG4gICAgICAgICAgXCJoZWxwLXRleHRcIjogXCJcdTMwQ0RcdTMwQzNcdTMwQzhcdTMwRUZcdTMwRkNcdTMwQUZcdTYzQTVcdTdEOUFcdTMwOTJcdTc4QkFcdThBOERcdTMwNTdcdTMwNjZcdTMwNEZcdTMwNjBcdTMwNTVcdTMwNDRcIlxuICAgICAgICB9LFxuICAgICAgICBcImZvb3RlclwiOiB7XG4gICAgICAgICAgXCJzZWxlY3QtdGV4dFwiOiBcIlx1OTA3OFx1NjI5RVwiLFxuICAgICAgICAgIFwibmF2aWdhdGUtdGV4dFwiOiBcIlx1NzlGQlx1NTJENVwiLFxuICAgICAgICAgIFwiY2xvc2UtdGV4dFwiOiBcIlx1OTU4OVx1MzA1OFx1MzA4QlwiLFxuICAgICAgICAgIFwic2VhcmNoLWJ5LXRleHRcIjogXCJcdTY5MUNcdTdEMjJcdTMwRDdcdTMwRURcdTMwRDBcdTMwQTRcdTMwQzBcdTMwRkNcIlxuICAgICAgICB9LFxuICAgICAgICBcIm5vLXJlc3VsdHMtc2NyZWVuXCI6IHtcbiAgICAgICAgICBcIm5vLXJlc3VsdHMtdGV4dFwiOiBcIlx1OTVBMlx1OTAyM1x1MzA1OVx1MzA4Qlx1N0Q1MFx1Njc5Q1x1MzA0Q1x1ODk4Qlx1MzA2NFx1MzA0Qlx1MzA4QVx1MzA3RVx1MzA1Qlx1MzA5M1x1MzA2N1x1MzA1N1x1MzA1RlwiLFxuICAgICAgICAgIFwic3VnZ2VzdGVkLXF1ZXJ5LXRleHRcIjogXCJcdTMwQUZcdTMwQThcdTMwRUFcdTMwOTJcdThBNjZcdTMwNTdcdTMwNjZcdTMwN0ZcdTMwOEJcdTMwNTNcdTMwNjhcdTMwNENcdTMwNjdcdTMwNERcdTMwN0VcdTMwNTlcIixcbiAgICAgICAgICBcInJlcG9ydC1taXNzaW5nLXJlc3VsdHMtdGV4dFwiOiBcIlx1MzA1M1x1MzA2RVx1MzBBRlx1MzBBOFx1MzBFQVx1MzA2Qlx1MzA2Rlx1N0Q1MFx1Njc5Q1x1MzA0Q1x1MzA0Mlx1MzA4Qlx1MzA2OFx1NjAxRFx1MzA0NFx1MzA3RVx1MzA1OVx1MzA0Qj9cIixcbiAgICAgICAgICBcInJlcG9ydC1taXNzaW5nLXJlc3VsdHMtbGluay10ZXh0XCI6IFwiXHUzMEFGXHUzMEVBXHUzMEMzXHUzMEFGXHUzMDU3XHUzMDY2XHUzMEQ1XHUzMEEzXHUzMEZDXHUzMEM5XHUzMEQwXHUzMEMzXHUzMEFGXHUzMDU5XHUzMDhCXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJuYXZiYXJcIjoge1xuICAgIFwiZ3VpZGVzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1MzBBQ1x1MzBBNFx1MzBDOVwiXG4gICAgfSxcbiAgICBcImNsaVwiOiB7XG4gICAgICBcInRleHRcIjogXCJDTElcIlxuICAgIH0sXG4gICAgXCJzZXJ2ZXJcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEI1XHUzMEZDXHUzMEQwXHUzMEZDXCJcbiAgICB9LFxuICAgIFwicmVzb3VyY2VzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlx1MzBFQVx1MzBCRFx1MzBGQ1x1MzBCOVwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwicmVmZXJlbmNlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEVBXHUzMEQ1XHUzMEExXHUzMEVDXHUzMEYzXHUzMEI5XCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjb250cmlidXRvcnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBCM1x1MzBGM1x1MzBDOFx1MzBFQVx1MzBEM1x1MzBFNVx1MzBGQ1x1MzBCRlx1MzBGQ1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY2hhbmdlbG9nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTU5MDlcdTY2RjRcdTVDNjVcdTZCNzRcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9LFxuICBcInNpZGViYXJzXCI6IHtcbiAgICBcImNsaVwiOiB7XG4gICAgICBcInRleHRcIjogXCJDTElcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImNsaVwiOiB7XG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImxvZ2dpbmdcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwRURcdTMwQUVcdTMwRjNcdTMwQjBcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwic2hlbGwtY29tcGxldGlvbnNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJTaGVsbCBjb21wbGV0aW9uc1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImNvbW1hbmRzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwQjNcdTMwREVcdTMwRjNcdTMwQzlcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcInJlZmVyZW5jZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEVBXHUzMEQ1XHUzMEExXHUzMEVDXHUzMEYzXHUzMEI5XCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJleGFtcGxlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEI1XHUzMEYzXHUzMEQ3XHUzMEVCXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJtaWdyYXRpb25zXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwREVcdTMwQTRcdTMwQjBcdTMwRUNcdTMwRkNcdTMwQjdcdTMwRTdcdTMwRjNcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiZnJvbS12My10by12NFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcInYzIFx1MzA0Qlx1MzA4OSB2NCBcdTMwNzhcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJjb250cmlidXRvcnNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEIzXHUzMEYzXHUzMEM4XHUzMEVBXHUzMEQzXHUzMEU1XHUzMEZDXHUzMEJGXHUzMEZDXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJnZXQtc3RhcnRlZFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU1OUNCXHUzMDgxXHU2NUI5XCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJpc3N1ZS1yZXBvcnRpbmdcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIklzc3VlXHU1ODMxXHU1NDRBXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjb2RlLXJldmlld3NcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBCM1x1MzBGQ1x1MzBDOVx1MzBFQ1x1MzBEM1x1MzBFNVx1MzBGQ1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwicHJpbmNpcGxlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU1MzlGXHU1MjQ3XCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1N0ZGQlx1OEEzM1x1MzA1OVx1MzA4QlwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY2xpXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDTElcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibG9nZ2luZ1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBFRFx1MzBBRVx1MzBGM1x1MzBCMFwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcInNlcnZlclwiOiB7XG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJpbnRyb2R1Y3Rpb25cIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzA2Rlx1MzA1OFx1MzA4MVx1MzA2QlwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJ3aHktc2VydmVyXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMDZBXHUzMDVDXHUzMEI1XHUzMEZDXHUzMEQwXHUzMEZDXHUzMDRDXHU1RkM1XHU4OTgxXHUzMDZBXHUzMDZFXHUzMDRCXHVGRjFGXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImFjY291bnRzLWFuZC1wcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBBMlx1MzBBQlx1MzBBNlx1MzBGM1x1MzBDOFx1MzA2OFx1MzBEN1x1MzBFRFx1MzBCOFx1MzBBN1x1MzBBRlx1MzBDOFwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJhdXRoZW50aWNhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1OEE4RFx1OEEzQ1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJpbnRlZ3JhdGlvbnNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwQTRcdTMwRjNcdTMwQzZcdTMwQjBcdTMwRUNcdTMwRkNcdTMwQjdcdTMwRTdcdTMwRjNcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJvbi1wcmVtaXNlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwQUFcdTMwRjNcdTMwRDdcdTMwRUNcdTMwREZcdTMwQjlcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiaW5zdGFsbFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBBNFx1MzBGM1x1MzBCOVx1MzBDOFx1MzBGQ1x1MzBFQlwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJtZXRyaWNzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEUxXHUzMEM4XHUzMEVBXHUzMEFGXHUzMEI5XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiYXBpLWRvY3VtZW50YXRpb25cIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkFQSVx1MzBDOVx1MzBBRFx1MzBFNVx1MzBFMVx1MzBGM1x1MzBDOFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwic3RhdHVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwQjlcdTMwQzZcdTMwRkNcdTMwQkZcdTMwQjlcIlxuICAgICAgICB9LFxuICAgICAgICBcIm1ldHJpY3MtZGFzaGJvYXJkXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwRTFcdTMwQzhcdTMwRUFcdTMwQUZcdTMwQjlcdTMwQzBcdTMwQzNcdTMwQjdcdTMwRTVcdTMwRENcdTMwRkNcdTMwQzlcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJcdTMwQUNcdTMwQTRcdTMwQzlcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInR1aXN0XCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJUdWlzdFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJhYm91dFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlR1aXN0IFx1MzA2Qlx1MzA2NFx1MzA0NFx1MzA2NlwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcInF1aWNrLXN0YXJ0XCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwQUZcdTMwQTRcdTMwQzNcdTMwQUZcdTMwQjlcdTMwQkZcdTMwRkNcdTMwQzhcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiaW5zdGFsbC10dWlzdFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlR1aXN0XHUzMDZFXHUzMEE0XHUzMEYzXHUzMEI5XHUzMEM4XHUzMEZDXHUzMEVCXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImdldC1zdGFydGVkXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMDZGXHUzMDU4XHUzMDgxXHUzMDZCXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiZmVhdHVyZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1NkE1Rlx1ODBGRFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiZGV2ZWxvcFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU5NThCXHU3NjdBXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImdlbmVyYXRlZC1wcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBEN1x1MzBFRFx1MzBCOFx1MzBBN1x1MzBBRlx1MzBDOFwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcImFkb3B0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1NUMwRVx1NTE2NVwiLFxuICAgICAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgICAgIFwibmV3LXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1NjVCMFx1ODk4Rlx1MzBEN1x1MzBFRFx1MzBCOFx1MzBBN1x1MzBBRlx1MzBDOFx1MzA2RVx1NEY1Q1x1NjIxMFwiXG4gICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU3dpZnQgXHUzMEQxXHUzMEMzXHUzMEIxXHUzMEZDXHUzMEI4XHUzMDY4XHU0RjdGXHU3NTI4XHUzMDU5XHUzMDhCXCJcbiAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgXCJtaWdyYXRlXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTc5RkJcdTg4NENcdTMwNTlcdTMwOEJcIixcbiAgICAgICAgICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgIFwieGNvZGUtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlhjb2RlIFx1MzBEN1x1MzBFRFx1MzBCOFx1MzBBN1x1MzBBRlx1MzBDOFwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICAgICAgXCJzd2lmdC1wYWNrYWdlXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU3dpZnQgXHUzMEQxXHUzMEMzXHUzMEIxXHUzMEZDXHUzMEI4XCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICBcInhjb2RlZ2VuLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJYY29kZUdlbiBcdTMwRDdcdTMwRURcdTMwQjhcdTMwQTdcdTMwQUZcdTMwQzhcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwiYmF6ZWwtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkJhemVsIFx1MzBEN1x1MzBFRFx1MzBCOFx1MzBBN1x1MzBBRlx1MzBDOFwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcIm1hbmlmZXN0c1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwREVcdTMwQ0JcdTMwRDVcdTMwQTdcdTMwQjlcdTMwQzhcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkaXJlY3Rvcnktc3RydWN0dXJlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBDN1x1MzBBM1x1MzBFQ1x1MzBBRlx1MzBDOFx1MzBFQVx1NjlDQlx1NjIxMFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImVkaXRpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU3REU4XHU5NkM2XHU2NUI5XHU2Q0Q1XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZGVwZW5kZW5jaWVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1NEY5RFx1NUI1OFx1OTVBMlx1NEZDMlwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImNvZGUtc2hhcmluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwQjNcdTMwRkNcdTMwQzlcdTMwNkVcdTUxNzFcdTY3MDlcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJzeW50aGVzaXplZC1maWxlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTgxRUFcdTUyRDVcdTc1MUZcdTYyMTBcdTMwRDVcdTMwQTFcdTMwQTRcdTMwRUJcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkeW5hbWljLWNvbmZpZ3VyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU1MkQ1XHU3Njg0XHUzMEIzXHUzMEYzXHUzMEQ1XHUzMEEzXHUzMEFFXHUzMEU1XHUzMEVDXHUzMEZDXHUzMEI3XHUzMEU3XHUzMEYzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidGVtcGxhdGVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBDNlx1MzBGM1x1MzBEN1x1MzBFQ1x1MzBGQ1x1MzBDOFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInBsdWdpbnNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEQ3XHUzMEU5XHUzMEIwXHUzMEE0XHUzMEYzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiaGFzaGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTMwQ0ZcdTMwQzNcdTMwQjdcdTMwRTVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJpbnNwZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1NjkxQ1x1NjdGQlwiLFxuICAgICAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgICAgIFwiaW1wbGljaXQtaW1wb3J0c1wiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU2Njk3XHU5RUQ5XHUzMDZFXHUzMEE0XHUzMEYzXHUzMEREXHUzMEZDXHUzMEM4XCJcbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0aGUtY29zdC1vZi1jb252ZW5pZW5jZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJcdTUyMjlcdTRGQkZcdTYwMjdcdTMwNkVcdTRFRTNcdTUxMUZcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0bWEtYXJjaGl0ZWN0dXJlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBFMlx1MzBCOFx1MzBFNVx1MzBGQ1x1MzBFOVx1MzBGQ1x1MzBBMlx1MzBGQ1x1MzBBRFx1MzBDNlx1MzBBRlx1MzBDMVx1MzBFM1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImJlc3QtcHJhY3RpY2VzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBEOVx1MzBCOVx1MzBDOFx1MzBEN1x1MzBFOVx1MzBBRlx1MzBDNlx1MzBBM1x1MzBCOVwiXG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJjYWNoZVwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBBRFx1MzBFM1x1MzBDM1x1MzBCN1x1MzBFNVwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJyZWdpc3RyeVwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBFQ1x1MzBCOFx1MzBCOVx1MzBDOFx1MzBFQVwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcInJlZ2lzdHJ5XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBFQ1x1MzBCOFx1MzBCOVx1MzBDOFx1MzBFQVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGUgXHUzMEQ3XHUzMEVEXHUzMEI4XHUzMEE3XHUzMEFGXHUzMEM4XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZ2VuZXJhdGVkLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU3NTFGXHU2MjEwXHUzMDU1XHUzMDhDXHUzMDVGXHUzMEQ3XHUzMEVEXHUzMEI4XHUzMEE3XHUzMEFGXHUzMEM4XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwieGNvZGVwcm9qLWludGVncmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlhjb2RlUHJvaiBcdTMwRDlcdTMwRkNcdTMwQjlcdTMwNkVcdTdENzFcdTU0MDhcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJzd2lmdC1wYWNrYWdlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlN3aWZ0IFx1MzBEMVx1MzBDM1x1MzBCMVx1MzBGQ1x1MzBCOFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImNvbnRpbnVvdXMtaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU3RDk5XHU3RDlBXHU3Njg0XHUzMEE0XHUzMEYzXHUzMEM2XHUzMEIwXHUzMEVDXHUzMEZDXHUzMEI3XHUzMEU3XHUzMEYzXCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInNlbGVjdGl2ZS10ZXN0aW5nXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU5MDc4XHU2MjlFXHU3Njg0XHUzMEM2XHUzMEI5XHUzMEM4XCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwic2VsZWN0aXZlLXRlc3RpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU5MDc4XHU2MjlFXHU3Njg0XHUzMEM2XHUzMEI5XHUzMEM4XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwieGNvZGUtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJYY29kZSBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZ2VuZXJhdGVkLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU3NTFGXHU2MjEwXHUzMDU1XHUzMDhDXHUzMDVGXHUzMEQ3XHUzMEVEXHUzMEI4XHUzMEE3XHUzMEFGXHUzMEM4XCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImluc2lnaHRzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zaWdodHNcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYnVuZGxlLXNpemVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJCdW5kbGUgc2l6ZVwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImFnZW50aWMtY29kaW5nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJcdTMwQThcdTMwRkNcdTMwQjhcdTMwQTdcdTMwRjNcdTMwQzZcdTMwQTNcdTMwQzNcdTMwQUZcdTMwRkJcdTMwQjNcdTMwRkNcdTMwQzdcdTMwQTNcdTMwRjNcdTMwQjBcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibWNwXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHUzMEUyXHUzMEM3XHUzMEVCXHUzMEIzXHUzMEYzXHUzMEM2XHUzMEFEXHUzMEI5XHUzMEM4XHUzMEQ3XHUzMEVEXHUzMEM4XHUzMEIzXHUzMEVCKE1DUClcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJpbnRlZ3JhdGlvbnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkludGVncmF0aW9uc1wiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJjb250aW51b3VzLWludGVncmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiXHU3RDk5XHU3RDlBXHU3Njg0XHUzMEE0XHUzMEYzXHUzMEM2XHUzMEIwXHUzMEVDXHUzMEZDXHUzMEI3XHUzMEU3XHUzMEYzXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwic2hhcmVcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlx1NTE3MVx1NjcwOVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJwcmV2aWV3c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MzBEN1x1MzBFQ1x1MzBEM1x1MzBFNVx1MzBGQ1x1NkE1Rlx1ODBGRFwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9XG59XG4iLCAie1xuICBcImFzaWRlXCI6IHtcbiAgICBcInRyYW5zbGF0ZVwiOiB7XG4gICAgICBcInRpdGxlXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiVHJhZHVjY2lcdTAwRjNuIFx1RDgzQ1x1REYwRFwiXG4gICAgICB9LFxuICAgICAgXCJkZXNjcmlwdGlvblwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlRyYWR1Y2UgbyBtZWpvcmEgbGEgdHJhZHVjY2lcdTAwRjNuIGRlIGVzdGEgcFx1MDBFMWdpbmEuXCJcbiAgICAgIH0sXG4gICAgICBcImN0YVwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIkNvbnRyaWJ1eWVcIlxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzZWFyY2hcIjoge1xuICAgIFwicGxhY2Vob2xkZXJcIjogXCJCdXNjYVwiLFxuICAgIFwidHJhbnNsYXRpb25zXCI6IHtcbiAgICAgIFwiYnV0dG9uXCI6IHtcbiAgICAgICAgXCJidXR0b24tdGV4dFwiOiBcIkJ1c2NhIGVuIGxhIGRvY3VtZW50YWNpXHUwMEYzblwiLFxuICAgICAgICBcImJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiQnVzY2EgZW4gbGEgZG9jdW1lbnRhY2lcdTAwRjNuXCJcbiAgICAgIH0sXG4gICAgICBcIm1vZGFsXCI6IHtcbiAgICAgICAgXCJzZWFyY2gtYm94XCI6IHtcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi10aXRsZVwiOiBcIkxpbXBpYXIgdFx1MDBFOXJtaW5vIGRlIGJcdTAwRkFzcXVlZGFcIixcbiAgICAgICAgICBcInJlc2V0LWJ1dHRvbi1hcmlhLWxhYmVsXCI6IFwiTGltcGlhciB0XHUwMEU5cm1pbm8gZGUgYlx1MDBGQXNxdWVkYVwiLFxuICAgICAgICAgIFwiY2FuY2VsLWJ1dHRvbi10ZXh0XCI6IFwiQ2FuY2VsYXJcIixcbiAgICAgICAgICBcImNhbmNlbC1idXR0b24tYXJpYS1sYWJlbFwiOiBcIkNhbmNlbGFyXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJzdGFydC1zY3JlZW5cIjoge1xuICAgICAgICAgIFwicmVjZW50LXNlYXJjaGVzLXRpdGxlXCI6IFwiSGlzdG9yaWFsIGRlIGJcdTAwRkFzcXVlZGFcIixcbiAgICAgICAgICBcIm5vLXJlY2VudC1zZWFyY2hlcy10ZXh0XCI6IFwiTm8gaGF5IGhpc3RvcmlhbCBkZSBiXHUwMEZBc3F1ZWRhXCIsXG4gICAgICAgICAgXCJzYXZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiR3VhcmRhciBlbiBlbCBoaXN0b3JpYWwgZGUgYlx1MDBGQXNxdWVkYVwiLFxuICAgICAgICAgIFwicmVtb3ZlLXJlY2VudC1zZWFyY2gtYnV0dG9uLXRpdGxlXCI6IFwiRWxpbWluYXIgZGVsIGhpc3RvcmlhbCBkZSBiXHUwMEZBc3F1ZWRhXCIsXG4gICAgICAgICAgXCJmYXZvcml0ZS1zZWFyY2hlcy10aXRsZVwiOiBcIkZhdm9yaXRvc1wiLFxuICAgICAgICAgIFwicmVtb3ZlLWZhdm9yaXRlLXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJFbGltaW5hciBkZSBmYXZvcml0b3NcIlxuICAgICAgICB9LFxuICAgICAgICBcImVycm9yLXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJ0aXRsZS10ZXh0XCI6IFwiSW1wb3NpYmxlIG9idGVuZXIgcmVzdWx0YWRvc1wiLFxuICAgICAgICAgIFwiaGVscC10ZXh0XCI6IFwiQ29tcHJ1ZWJhIHR1IGNvbmV4aVx1MDBGM24gYSBJbnRlcm5ldFwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiZm9vdGVyXCI6IHtcbiAgICAgICAgICBcInNlbGVjdC10ZXh0XCI6IFwiU2VsZWNjaW9uYVwiLFxuICAgICAgICAgIFwibmF2aWdhdGUtdGV4dFwiOiBcIk5hdmVnYXJcIixcbiAgICAgICAgICBcImNsb3NlLXRleHRcIjogXCJDZXJyYXJcIixcbiAgICAgICAgICBcInNlYXJjaC1ieS10ZXh0XCI6IFwiUHJvdmVlZG9yIGRlIGJcdTAwRkFzcXVlZGFcIlxuICAgICAgICB9LFxuICAgICAgICBcIm5vLXJlc3VsdHMtc2NyZWVuXCI6IHtcbiAgICAgICAgICBcIm5vLXJlc3VsdHMtdGV4dFwiOiBcIk5vIHNlIGVuY29udHJhcm9uIHJlc3VsdGFkb3MgcmVsZXZhbnRlc1wiLFxuICAgICAgICAgIFwic3VnZ2VzdGVkLXF1ZXJ5LXRleHRcIjogXCJQb2RyXHUwMEVEYXMgaW50ZW50YXIgY29uc3VsdGFyXCIsXG4gICAgICAgICAgXCJyZXBvcnQtbWlzc2luZy1yZXN1bHRzLXRleHRcIjogXCJcdTAwQkZDcmVlIHF1ZSBlc3RhIGNvbnN1bHRhIGRlYmVyXHUwMEVEYSB0ZW5lciByZXN1bHRhZG9zP1wiLFxuICAgICAgICAgIFwicmVwb3J0LW1pc3NpbmctcmVzdWx0cy1saW5rLXRleHRcIjogXCJIYXogY2xpYyBwYXJhIGRhciB0dSBvcGluaVx1MDBGM25cIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9LFxuICBcIm5hdmJhclwiOiB7XG4gICAgXCJndWlkZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiR3VcdTAwRURhc1wiXG4gICAgfSxcbiAgICBcImNsaVwiOiB7XG4gICAgICBcInRleHRcIjogXCJDTElcIlxuICAgIH0sXG4gICAgXCJzZXJ2ZXJcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiU2Vydmlkb3JcIlxuICAgIH0sXG4gICAgXCJyZXNvdXJjZXNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiUmVjdXJzb3NcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInJlZmVyZW5jZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlJlZmVyZW5jaWFzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjb250cmlidXRvcnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNvbGFib3JhZG9yZXNcIlxuICAgICAgICB9LFxuICAgICAgICBcImNoYW5nZWxvZ1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ2hhbmdlbG9nXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfSxcbiAgXCJzaWRlYmFyc1wiOiB7XG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJjbGlcIjoge1xuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJsb2dnaW5nXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTG9nZ2luZ1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJzaGVsbC1jb21wbGV0aW9uc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlNoZWxsIGNvbXBsZXRpb25zXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiY29tbWFuZHNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNvbWFuZG9zXCJcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJyZWZlcmVuY2VzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlJlZmVyZW5jaWFzXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJleGFtcGxlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiRWplbXBsb3NcIlxuICAgICAgICB9LFxuICAgICAgICBcIm1pZ3JhdGlvbnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIk1pZ3JhY2lvbmVzXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImZyb20tdjMtdG8tdjRcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJEZSB2MyBhIHY0XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwiY29udHJpYnV0b3JzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNvbGFib3JhZG9yZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImdldC1zdGFydGVkXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDb21lbnphclwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiaXNzdWUtcmVwb3J0aW5nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJSZXBvcnRlIGRlIElzc3Vlc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwiY29kZS1yZXZpZXdzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJSZXZpc2lcdTAwRjNuIGRlIGNcdTAwRjNkaWdvXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJwcmluY2lwbGVzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJQcmluY2lwaW9zXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlRyYWR1Y2VcIlxuICAgICAgICB9LFxuICAgICAgICBcImNsaVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImxvZ2dpbmdcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJMb2dnaW5nXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImludHJvZHVjdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiSW50cm9kdWNjaVx1MDBGM25cIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwid2h5LXNlcnZlclwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlx1MDBCRlBvciBxdVx1MDBFOSB1biBzZXJ2aWRvcj9cIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYWNjb3VudHMtYW5kLXByb2plY3RzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ3VlbnRhcyB5IHByb3llY3Rvc1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJhdXRoZW50aWNhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkF1dGVudGlmaWNhY2lcdTAwRjNuXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImludGVncmF0aW9uc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkludGVncmFjaW9uZXNcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJvbi1wcmVtaXNlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJPbi1wcmVtaXNlXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImluc3RhbGxcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnN0YWxhXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcIm1ldHJpY3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJNXHUwMEU5dHJpY2FzXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiYXBpLWRvY3VtZW50YXRpb25cIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkRvY3VtZW50YWNpXHUwMEYzbiBkZSBsYSBBUElcIlxuICAgICAgICB9LFxuICAgICAgICBcInN0YXR1c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiRXN0YWRvXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJtZXRyaWNzLWRhc2hib2FyZFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiUGFuZWwgZGUgbVx1MDBFOXRyaWNhc1wiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwiZ3VpZGVzXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkd1XHUwMEVEYXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInR1aXN0XCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJUdWlzdFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJhYm91dFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFib3V0IFR1aXN0XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwicXVpY2stc3RhcnRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlF1aWNrIFN0YXJ0XCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImluc3RhbGwtdHVpc3RcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnN0YWxhIFR1aXN0XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImdldC1zdGFydGVkXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiR2V0IHN0YXJ0ZWRcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJmZWF0dXJlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ2FyYWN0ZXJcdTAwRURzdGljYXNcIlxuICAgICAgICB9LFxuICAgICAgICBcImRldmVsb3BcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkRlc2Fycm9sbGFcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiZ2VuZXJhdGVkLXByb2plY3RzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUHJveWVjdG9zIGdlbmVyYWRvc1wiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcImFkb3B0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFkb3B0aW9uXCIsXG4gICAgICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgXCJuZXctcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ3JlYXRlIGEgbmV3IHByb2plY3RcIlxuICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlRyeSB3aXRoIGEgU3dpZnQgUGFja2FnZVwiXG4gICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgIFwibWlncmF0ZVwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTWlncmF0ZVwiLFxuICAgICAgICAgICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgXCJ4Y29kZS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQW4gWGNvZGUgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICAgICAgXCJzd2lmdC1wYWNrYWdlXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQSBTd2lmdCBwYWNrYWdlXCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICBcInhjb2RlZ2VuLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBbiBYY29kZUdlbiBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICBcImJhemVsLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBIEJhemVsIHByb2plY3RcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJtYW5pZmVzdHNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRmljaGVyb3MgbWFuaWZlc3RcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkaXJlY3Rvcnktc3RydWN0dXJlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkVzdHJ1Y3R1cmEgZGUgZGlyZWN0b3Jpb3NcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJlZGl0aW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkVkaWNpXHUwMEYzblwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImRlcGVuZGVuY2llc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJEZXBlbmRlbmNpYXNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJjb2RlLXNoYXJpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29tcGFydGlyIGNcdTAwRjNkaWdvXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwic3ludGhlc2l6ZWQtZmlsZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU2ludGV0aXphZG8gZGUgZmljaGVyb3NcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkeW5hbWljLWNvbmZpZ3VyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29uZmlndXJhY2lcdTAwRjNuIGRpblx1MDBFMW1pY2FcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ0ZW1wbGF0ZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUGxhbnRpbGxhc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInBsdWdpbnNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUGx1Z2luc1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImhhc2hpbmdcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSGFzaGVhZG9cIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJpbnNwZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3BlY3RcIixcbiAgICAgICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgICAgICBcImltcGxpY2l0LWltcG9ydHNcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkltcGxpY2l0IGltcG9ydHNcIlxuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRoZS1jb3N0LW9mLWNvbnZlbmllbmNlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkVsIGNvc3RlIGRlIGxhIGNvbnZlbmllbmNpYVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRtYS1hcmNoaXRlY3R1cmVcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQXJjaGl0ZWN0dXJhIG1vZHVsYXJcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJiZXN0LXByYWN0aWNlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJCdWVuYXMgcHJcdTAwRTFjdGljYXNcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiY2FjaGVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJDYWNoZVwiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJyZWdpc3RyeVwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIlJlZ2lzdHJ5XCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwicmVnaXN0cnlcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUmVnaXN0cnlcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZS1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlhjb2RlIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJnZW5lcmF0ZWQtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJHZW5lcmF0ZWQgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInhjb2RlcHJvai1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJYY29kZVByb2otYmFzZWQgaW50ZWdyYXRpb25cIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJzd2lmdC1wYWNrYWdlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlN3aWZ0IHBhY2thZ2VcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJjb250aW51b3VzLWludGVncmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvbnRpbnVvdXMgaW50ZWdyYXRpb25cIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwic2VsZWN0aXZlLXRlc3RpbmdcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJTZWxlY3RpdmUgdGVzdGluZ1wiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcInNlbGVjdGl2ZS10ZXN0aW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlNlbGVjdGl2ZSB0ZXN0aW5nXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwieGNvZGUtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJYY29kZSBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZ2VuZXJhdGVkLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiR2VuZXJhdGVkIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiaW5zaWdodHNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnNpZ2h0c1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJidW5kbGUtc2l6ZVwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkJ1bmRsZSBzaXplXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiYWdlbnRpYy1jb2RpbmdcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNvZGlmaWNhY2lcdTAwRjNuIEFnXHUwMEU5bnRpY2FcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibWNwXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiTW9kZWwgQ29udGV4dCBQcm90b2NvbCAoTUNQKVwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImludGVncmF0aW9uc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiSW50ZWdyYXRpb25zXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImNvbnRpbnVvdXMtaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJDb250aW51b3VzIGludGVncmF0aW9uXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwic2hhcmVcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNvbXBhcnRlXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcInByZXZpZXdzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiUHJldmlld3NcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgfVxufVxuIiwgIntcbiAgXCJhc2lkZVwiOiB7XG4gICAgXCJ0cmFuc2xhdGVcIjoge1xuICAgICAgXCJ0aXRsZVwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIlRyYW5zbGF0aW9uIFx1RDgzQ1x1REYwRFwiXG4gICAgICB9LFxuICAgICAgXCJkZXNjcmlwdGlvblwiOiB7XG4gICAgICAgIFwidGV4dFwiOiBcIllvdSBjYW4gdHJhbnNsYXRlIG9yIGltcHJvdmUgdGhlIHRyYW5zbGF0aW9uIG9mIHRoaXMgcGFnZS5cIlxuICAgICAgfSxcbiAgICAgIFwiY3RhXCI6IHtcbiAgICAgICAgXCJ0ZXh0XCI6IFwiQ29udHJpYnV0ZVwiXG4gICAgICB9XG4gICAgfVxuICB9LFxuICBcInNlYXJjaFwiOiB7XG4gICAgXCJwbGFjZWhvbGRlclwiOiBcIlNlYXJjaFwiLFxuICAgIFwidHJhbnNsYXRpb25zXCI6IHtcbiAgICAgIFwiYnV0dG9uXCI6IHtcbiAgICAgICAgXCJidXR0b24tdGV4dFwiOiBcIlNlYXJjaCBkb2N1bWVudGF0aW9uXCIsXG4gICAgICAgIFwiYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJTZWFyY2ggZG9jdW1lbnRhdGlvblwiXG4gICAgICB9LFxuICAgICAgXCJtb2RhbFwiOiB7XG4gICAgICAgIFwic2VhcmNoLWJveFwiOiB7XG4gICAgICAgICAgXCJyZXNldC1idXR0b24tdGl0bGVcIjogXCJDbGVhciBxdWVyeVwiLFxuICAgICAgICAgIFwicmVzZXQtYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJDbGVhciBxdWVyeVwiLFxuICAgICAgICAgIFwiY2FuY2VsLWJ1dHRvbi10ZXh0XCI6IFwiQ2FuY2VsXCIsXG4gICAgICAgICAgXCJjYW5jZWwtYnV0dG9uLWFyaWEtbGFiZWxcIjogXCJDYW5jZWxcIlxuICAgICAgICB9LFxuICAgICAgICBcInN0YXJ0LXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJyZWNlbnQtc2VhcmNoZXMtdGl0bGVcIjogXCJTZWFyY2ggaGlzdG9yeVwiLFxuICAgICAgICAgIFwibm8tcmVjZW50LXNlYXJjaGVzLXRleHRcIjogXCJObyBzZWFyY2ggaGlzdG9yeVwiLFxuICAgICAgICAgIFwic2F2ZS1yZWNlbnQtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlNhdmUgdG8gc2VhcmNoIGhpc3RvcnlcIixcbiAgICAgICAgICBcInJlbW92ZS1yZWNlbnQtc2VhcmNoLWJ1dHRvbi10aXRsZVwiOiBcIlJlbW92ZSBmcm9tIHNlYXJjaCBoaXN0b3J5XCIsXG4gICAgICAgICAgXCJmYXZvcml0ZS1zZWFyY2hlcy10aXRsZVwiOiBcIkZhdm9yaXRlc1wiLFxuICAgICAgICAgIFwicmVtb3ZlLWZhdm9yaXRlLXNlYXJjaC1idXR0b24tdGl0bGVcIjogXCJSZW1vdmUgZnJvbSBmYXZvcml0ZXNcIlxuICAgICAgICB9LFxuICAgICAgICBcImVycm9yLXNjcmVlblwiOiB7XG4gICAgICAgICAgXCJ0aXRsZS10ZXh0XCI6IFwiVW5hYmxlIHRvIHJldHJpZXZlIHJlc3VsdHNcIixcbiAgICAgICAgICBcImhlbHAtdGV4dFwiOiBcIllvdSBtYXkgbmVlZCB0byBjaGVjayB5b3VyIG5ldHdvcmsgY29ubmVjdGlvblwiXG4gICAgICAgIH0sXG4gICAgICAgIFwiZm9vdGVyXCI6IHtcbiAgICAgICAgICBcInNlbGVjdC10ZXh0XCI6IFwiU2VsZWN0XCIsXG4gICAgICAgICAgXCJuYXZpZ2F0ZS10ZXh0XCI6IFwiTmF2aWdhdGVcIixcbiAgICAgICAgICBcImNsb3NlLXRleHRcIjogXCJDbG9zZVwiLFxuICAgICAgICAgIFwic2VhcmNoLWJ5LXRleHRcIjogXCJTZWFyY2ggcHJvdmlkZXJcIlxuICAgICAgICB9LFxuICAgICAgICBcIm5vLXJlc3VsdHMtc2NyZWVuXCI6IHtcbiAgICAgICAgICBcIm5vLXJlc3VsdHMtdGV4dFwiOiBcIk5vIHJlbGV2YW50IHJlc3VsdHMgZm91bmRcIixcbiAgICAgICAgICBcInN1Z2dlc3RlZC1xdWVyeS10ZXh0XCI6IFwiWW91IG1pZ2h0IHRyeSBxdWVyeWluZ1wiLFxuICAgICAgICAgIFwicmVwb3J0LW1pc3NpbmctcmVzdWx0cy10ZXh0XCI6IFwiRG8geW91IHRoaW5rIHRoaXMgcXVlcnkgc2hvdWxkIGhhdmUgcmVzdWx0cz9cIixcbiAgICAgICAgICBcInJlcG9ydC1taXNzaW5nLXJlc3VsdHMtbGluay10ZXh0XCI6IFwiQ2xpY2sgdG8gZ2l2ZSBmZWVkYmFja1wiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwibmF2YmFyXCI6IHtcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJHdWlkZXNcIlxuICAgIH0sXG4gICAgXCJjbGlcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCJcbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIlNlcnZlclwiXG4gICAgfSxcbiAgICBcInJlc291cmNlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJSZXNvdXJjZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInJlZmVyZW5jZXNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlJlZmVyZW5jZXNcIlxuICAgICAgICB9LFxuICAgICAgICBcImNvbnRyaWJ1dG9yc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ29udHJpYnV0b3JzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjaGFuZ2Vsb2dcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNoYW5nZWxvZ1wiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gIH0sXG4gIFwic2lkZWJhcnNcIjoge1xuICAgIFwiY2xpXCI6IHtcbiAgICAgIFwidGV4dFwiOiBcIkNMSVwiLFxuICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgIFwiY2xpXCI6IHtcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwibG9nZ2luZ1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkxvZ2dpbmdcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwic2hlbGwtY29tcGxldGlvbnNcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJTaGVsbCBjb21wbGV0aW9uc1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImNvbW1hbmRzXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDb21tYW5kc1wiXG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwicmVmZXJlbmNlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJSZWZlcmVuY2VzXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJleGFtcGxlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiRXhhbXBsZXNcIlxuICAgICAgICB9LFxuICAgICAgICBcIm1pZ3JhdGlvbnNcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIk1pZ3JhdGlvbnNcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiZnJvbS12My10by12NFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkZyb20gdjMgdG8gdjRcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG4gICAgXCJjb250cmlidXRvcnNcIjoge1xuICAgICAgXCJ0ZXh0XCI6IFwiQ29udHJpYnV0b3JzXCIsXG4gICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgXCJnZXQtc3RhcnRlZFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiR2V0IHN0YXJ0ZWRcIlxuICAgICAgICB9LFxuICAgICAgICBcImlzc3VlLXJlcG9ydGluZ1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiSXNzdWUgcmVwb3J0aW5nXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJjb2RlLXJldmlld3NcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkNvZGUgcmV2aWV3c1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwicHJpbmNpcGxlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiUHJpbmNpcGxlc1wiXG4gICAgICAgIH0sXG4gICAgICAgIFwidHJhbnNsYXRlXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJUcmFuc2xhdGVcIlxuICAgICAgICB9LFxuICAgICAgICBcImNsaVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQ0xJXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImxvZ2dpbmdcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJMb2dnaW5nXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuICAgIFwic2VydmVyXCI6IHtcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcImludHJvZHVjdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiSW50cm9kdWN0aW9uXCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcIndoeS1zZXJ2ZXJcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJXaHkgYSBzZXJ2ZXI/XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImFjY291bnRzLWFuZC1wcm9qZWN0c1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFjY291bnRzIGFuZCBwcm9qZWN0c1wiXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgXCJhdXRoZW50aWNhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkF1dGhlbnRpY2F0aW9uXCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImludGVncmF0aW9uc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkludGVncmF0aW9uc1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcIm9uLXByZW1pc2VcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIk9uLXByZW1pc2VcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiaW5zdGFsbFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3RhbGxcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwibWV0cmljc1wiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIk1ldHJpY3NcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJhcGktZG9jdW1lbnRhdGlvblwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiQVBJIGRvY3VtZW50YXRpb25cIlxuICAgICAgICB9LFxuICAgICAgICBcInN0YXR1c1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiU3RhdHVzXCJcbiAgICAgICAgfSxcbiAgICAgICAgXCJtZXRyaWNzLWRhc2hib2FyZFwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiTWV0cmljcyBkYXNoYm9hcmRcIlxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcbiAgICBcImd1aWRlc1wiOiB7XG4gICAgICBcInRleHRcIjogXCJHdWlkZXNcIixcbiAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICBcInR1aXN0XCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJUdWlzdFwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJhYm91dFwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFib3V0IFR1aXN0XCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwicXVpY2stc3RhcnRcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIlF1aWNrIHN0YXJ0XCIsXG4gICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICBcImluc3RhbGwtdHVpc3RcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJJbnN0YWxsIFR1aXN0XCJcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImdldC1zdGFydGVkXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiR2V0IHN0YXJ0ZWRcIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJmZWF0dXJlc1wiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiUmVjdXJzb3NcIlxuICAgICAgICB9LFxuICAgICAgICBcImRldmVsb3BcIjoge1xuICAgICAgICAgIFwidGV4dFwiOiBcIkRldmVsb3BcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiZ2VuZXJhdGVkLXByb2plY3RzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiR2VuZXJhdGVkIHByb2plY3RzXCIsXG4gICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgIFwiYWRvcHRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQWRvcHRpb25cIixcbiAgICAgICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgICAgICBcIm5ldy1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJDcmVhdGUgYSBuZXcgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiVHJ5IHdpdGggYSBTd2lmdCBQYWNrYWdlXCJcbiAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgXCJtaWdyYXRlXCI6IHtcbiAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJNaWdyYXRlXCIsXG4gICAgICAgICAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBbiBYY29kZSBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICBcInN3aWZ0LXBhY2thZ2VcIjoge1xuICAgICAgICAgICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJBIFN3aWZ0IHBhY2thZ2VcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwieGNvZGVnZW4tcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkFuIFhjb2RlR2VuIHByb2plY3RcIlxuICAgICAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgICAgIFwiYmF6ZWwtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkEgQmF6ZWwgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcIm1hbmlmZXN0c1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJNYW5pZmVzdHNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkaXJlY3Rvcnktc3RydWN0dXJlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkRpcmVjdG9yeSBzdHJ1Y3R1cmVcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJlZGl0aW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkVkaXRpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJkZXBlbmRlbmNpZXNcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiRGVwZW5kZW5jaWVzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiY29kZS1zaGFyaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvZGUgc2hhcmluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInN5bnRoZXNpemVkLWZpbGVzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlN5bnRoZXNpemVkIGZpbGVzXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZHluYW1pYy1jb25maWd1cmF0aW9uXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkR5bmFtaWMgY29uZmlndXJhdGlvblwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRlbXBsYXRlc1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJUZW1wbGF0ZXNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJwbHVnaW5zXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlBsdWdpbnNcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJoYXNoaW5nXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkhhc2hpbmdcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJpbnNwZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkluc3BlY3RcIixcbiAgICAgICAgICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgICAgICAgICBcImltcGxpY2l0LWltcG9ydHNcIjoge1xuICAgICAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkltcGxpY2l0IGltcG9ydHNcIlxuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInRoZS1jb3N0LW9mLWNvbnZlbmllbmNlXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlRoZSBjb3N0IG9mIGNvbnZlbmllbmNlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwidG1hLWFyY2hpdGVjdHVyZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJNb2R1bGFyIGFyY2hpdGVjdHVyZVwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImJlc3QtcHJhY3RpY2VzXCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkJlc3QgcHJhY3RpY2VzXCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImNhY2hlXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiQ2FjaGVcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwicmVnaXN0cnlcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJSZWdpc3RyeVwiLFxuICAgICAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgICAgICBcInJlZ2lzdHJ5XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIlJlZ2lzdHJ5XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwieGNvZGUtcHJvamVjdFwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJYY29kZSBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiZ2VuZXJhdGVkLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiR2VuZXJhdGVkIHByb2plY3RcIlxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgXCJ4Y29kZXByb2otaW50ZWdyYXRpb25cIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGVQcm9qLWJhc2VkIGludGVncmF0aW9uXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwic3dpZnQtcGFja2FnZVwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTd2lmdCBwYWNrYWdlXCJcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIFwiY29udGludW91cy1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJDb250aW51b3VzIGludGVncmF0aW9uXCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcInNlbGVjdGl2ZS10ZXN0aW5nXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiU2VsZWN0aXZlIHRlc3RpbmdcIixcbiAgICAgICAgICAgICAgXCJpdGVtc1wiOiB7XG4gICAgICAgICAgICAgICAgXCJzZWxlY3RpdmUtdGVzdGluZ1wiOiB7XG4gICAgICAgICAgICAgICAgICBcInRleHRcIjogXCJTZWxlY3RpdmUgdGVzdGluZ1wiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcInhjb2RlLXByb2plY3RcIjoge1xuICAgICAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiWGNvZGUgcHJvamVjdFwiXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICBcImdlbmVyYXRlZC1wcm9qZWN0XCI6IHtcbiAgICAgICAgICAgICAgICAgIFwidGV4dFwiOiBcIkdlbmVyYXRlZCBwcm9qZWN0XCJcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBcImluc2lnaHRzXCI6IHtcbiAgICAgICAgICAgICAgXCJ0ZXh0XCI6IFwiSW5zaWdodHNcIlxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIFwiYnVuZGxlLXNpemVcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJCdW5kbGUgc2l6ZVwiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9LFxuICAgICAgICBcImFnZW50aWMtY29kaW5nXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJDb2RpZmljYVx1MDBFN1x1MDBFM28gQWdcdTAwRUFudGljYVwiLFxuICAgICAgICAgIFwiaXRlbXNcIjoge1xuICAgICAgICAgICAgXCJtY3BcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJNb2RlbCBDb250ZXh0IFByb3RvY29sIChNQ1ApXCJcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG4gICAgICAgIH0sXG4gICAgICAgIFwiaW50ZWdyYXRpb25zXCI6IHtcbiAgICAgICAgICBcInRleHRcIjogXCJJbnRlZ3JhdGlvbnNcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwiY29udGludW91cy1pbnRlZ3JhdGlvblwiOiB7XG4gICAgICAgICAgICAgIFwidGV4dFwiOiBcIkNvbnRpbnVvdXMgaW50ZWdyYXRpb25cIlxuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cbiAgICAgICAgfSxcbiAgICAgICAgXCJzaGFyZVwiOiB7XG4gICAgICAgICAgXCJ0ZXh0XCI6IFwiU2hhcmVcIixcbiAgICAgICAgICBcIml0ZW1zXCI6IHtcbiAgICAgICAgICAgIFwicHJldmlld3NcIjoge1xuICAgICAgICAgICAgICBcInRleHRcIjogXCJQcmV2aWV3c1wiXG4gICAgICAgICAgICB9XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfVxuICB9XG59XG4iLCAiY29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3NcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZmlsZW5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvaTE4bi5tanNcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfaW1wb3J0X21ldGFfdXJsID0gXCJmaWxlOi8vL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9pMThuLm1qc1wiO2ltcG9ydCBlblN0cmluZ3MgZnJvbSBcIi4vc3RyaW5ncy9lbi5qc29uXCI7XG5pbXBvcnQgcnVTdHJpbmdzIGZyb20gXCIuL3N0cmluZ3MvcnUuanNvblwiO1xuaW1wb3J0IGtvU3RyaW5ncyBmcm9tIFwiLi9zdHJpbmdzL2tvLmpzb25cIjtcbmltcG9ydCBqYVN0cmluZ3MgZnJvbSBcIi4vc3RyaW5ncy9qYS5qc29uXCI7XG5pbXBvcnQgZXNTdHJpbmdzIGZyb20gXCIuL3N0cmluZ3MvZXMuanNvblwiO1xuaW1wb3J0IHB0U3RyaW5ncyBmcm9tIFwiLi9zdHJpbmdzL3B0Lmpzb25cIjtcblxuY29uc3Qgc3RyaW5ncyA9IHtcbiAgZW46IGVuU3RyaW5ncyxcbiAgcnU6IHJ1U3RyaW5ncyxcbiAga286IGtvU3RyaW5ncyxcbiAgamE6IGphU3RyaW5ncyxcbiAgZXM6IGVzU3RyaW5ncyxcbiAgcHQ6IHB0U3RyaW5ncyxcbn07XG5cbmV4cG9ydCBmdW5jdGlvbiBsb2NhbGl6ZWRTdHJpbmcobG9jYWxlLCBrZXkpIHtcbiAgY29uc3QgZ2V0U3RyaW5nID0gKGxvY2FsZVN0cmluZ3MsIGtleSkgPT4ge1xuICAgIGNvbnN0IGtleXMgPSBrZXkuc3BsaXQoXCIuXCIpO1xuICAgIGxldCBjdXJyZW50ID0gbG9jYWxlU3RyaW5ncztcblxuICAgIGZvciAoY29uc3QgayBvZiBrZXlzKSB7XG4gICAgICBpZiAoY3VycmVudCAmJiBjdXJyZW50Lmhhc093blByb3BlcnR5KGspKSB7XG4gICAgICAgIGN1cnJlbnQgPSBjdXJyZW50W2tdO1xuICAgICAgfSBlbHNlIHtcbiAgICAgICAgcmV0dXJuIHVuZGVmaW5lZDtcbiAgICAgIH1cbiAgICB9XG4gICAgcmV0dXJuIGN1cnJlbnQ7XG4gIH07XG5cbiAgbGV0IGxvY2FsaXplZFZhbHVlID0gZ2V0U3RyaW5nKHN0cmluZ3NbbG9jYWxlXSwga2V5KTtcblxuICBpZiAobG9jYWxpemVkVmFsdWUgPT09IHVuZGVmaW5lZCAmJiBsb2NhbGUgIT09IFwiZW5cIikge1xuICAgIGxvY2FsaXplZFZhbHVlID0gZ2V0U3RyaW5nKHN0cmluZ3NbXCJlblwiXSwga2V5KTtcbiAgfVxuXG4gIHJldHVybiBsb2NhbGl6ZWRWYWx1ZTtcbn1cbiIsICJjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9maWxlbmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9iYXJzLm1qc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9pbXBvcnRfbWV0YV91cmwgPSBcImZpbGU6Ly8vVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2JhcnMubWpzXCI7aW1wb3J0IHtcbiAgY3ViZTAySWNvbixcbiAgY3ViZTAxSWNvbixcbiAgdHVpc3RJY29uLFxuICBidWlsZGluZzA3SWNvbixcbiAgc2VydmVyMDRJY29uLFxuICBib29rT3BlbjAxSWNvbixcbiAgY29kZUJyb3dzZXJJY29uLFxuICBzdGFyMDZJY29uLFxuICBwbGF5SWNvbixcbiAgY2FjaGVJY29uLFxuICB0ZXN0SWNvbixcbiAgcmVnaXN0cnlJY29uLFxuICBpbnNpZ2h0c0ljb24sXG4gIGJ1bmRsZVNpemVJY29uLFxuICBwcmV2aWV3c0ljb24sXG4gIHByb2plY3RzSWNvbixcbiAgbWNwSWNvbixcbiAgY2lJY29uLFxuICBnaXRodWJJY29uLFxuICBzc29JY29uLFxuICBhY2NvdW50c0ljb24sXG4gIGF1dGhJY29uLFxuICBpbnN0YWxsSWNvbixcbiAgdGVsZW1ldHJ5SWNvbixcbiAgZ2l0Rm9yZ2VzSWNvbixcbiAgc2VsZkhvc3RpbmdJY29uLFxuICBpbnN0YWxsVHVpc3RJY29uLFxuICBnZXRTdGFydGVkSWNvbixcbiAgYWdlbnRpY0J1aWxkaW5nSWNvbixcbn0gZnJvbSBcIi4vaWNvbnMubWpzXCI7XG5pbXBvcnQgeyBsb2FkRGF0YSBhcyBsb2FkRXhhbXBsZXNEYXRhIH0gZnJvbSBcIi4vZGF0YS9leGFtcGxlc1wiO1xuaW1wb3J0IHsgbG9hZERhdGEgYXMgbG9hZFByb2plY3REZXNjcmlwdGlvbkRhdGEgfSBmcm9tIFwiLi9kYXRhL3Byb2plY3QtZGVzY3JpcHRpb25cIjtcbmltcG9ydCB7IGxvY2FsaXplZFN0cmluZyB9IGZyb20gXCIuL2kxOG4ubWpzXCI7XG5cbmFzeW5jIGZ1bmN0aW9uIHByb2plY3REZXNjcmlwdGlvblNpZGViYXIobG9jYWxlKSB7XG4gIGNvbnN0IHByb2plY3REZXNjcmlwdGlvblR5cGVzRGF0YSA9IGF3YWl0IGxvYWRQcm9qZWN0RGVzY3JpcHRpb25EYXRhKCk7XG4gIGNvbnN0IHByb2plY3REZXNjcmlwdGlvblNpZGViYXIgPSB7XG4gICAgdGV4dDogXCJQcm9qZWN0IERlc2NyaXB0aW9uXCIsXG4gICAgY29sbGFwc2VkOiB0cnVlLFxuICAgIGl0ZW1zOiBbXSxcbiAgfTtcbiAgZnVuY3Rpb24gY2FwaXRhbGl6ZSh0ZXh0KSB7XG4gICAgcmV0dXJuIHRleHQuY2hhckF0KDApLnRvVXBwZXJDYXNlKCkgKyB0ZXh0LnNsaWNlKDEpLnRvTG93ZXJDYXNlKCk7XG4gIH1cbiAgW1wic3RydWN0c1wiLCBcImVudW1zXCIsIFwiZXh0ZW5zaW9uc1wiLCBcInR5cGVhbGlhc2VzXCJdLmZvckVhY2goKGNhdGVnb3J5KSA9PiB7XG4gICAgaWYgKFxuICAgICAgcHJvamVjdERlc2NyaXB0aW9uVHlwZXNEYXRhLmZpbmQoKGl0ZW0pID0+IGl0ZW0uY2F0ZWdvcnkgPT09IGNhdGVnb3J5KVxuICAgICkge1xuICAgICAgcHJvamVjdERlc2NyaXB0aW9uU2lkZWJhci5pdGVtcy5wdXNoKHtcbiAgICAgICAgdGV4dDogY2FwaXRhbGl6ZShjYXRlZ29yeSksXG4gICAgICAgIGNvbGxhcHNlZDogdHJ1ZSxcbiAgICAgICAgaXRlbXM6IHByb2plY3REZXNjcmlwdGlvblR5cGVzRGF0YVxuICAgICAgICAgIC5maWx0ZXIoKGl0ZW0pID0+IGl0ZW0uY2F0ZWdvcnkgPT09IGNhdGVnb3J5KVxuICAgICAgICAgIC5tYXAoKGl0ZW0pID0+ICh7XG4gICAgICAgICAgICB0ZXh0OiBpdGVtLnRpdGxlLFxuICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vcmVmZXJlbmNlcy9wcm9qZWN0LWRlc2NyaXB0aW9uLyR7aXRlbS5pZGVudGlmaWVyfWAsXG4gICAgICAgICAgfSkpLFxuICAgICAgfSk7XG4gICAgfVxuICB9KTtcbiAgcmV0dXJuIHByb2plY3REZXNjcmlwdGlvblNpZGViYXI7XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiByZWZlcmVuY2VzU2lkZWJhcihsb2NhbGUpIHtcbiAgcmV0dXJuIFtcbiAgICB7XG4gICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcobG9jYWxlLCBcInNpZGViYXJzLnJlZmVyZW5jZXMudGV4dFwiKSxcbiAgICAgIGl0ZW1zOiBbXG4gICAgICAgIGF3YWl0IHByb2plY3REZXNjcmlwdGlvblNpZGViYXIobG9jYWxlKSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMucmVmZXJlbmNlcy5pdGVtcy5leGFtcGxlcy50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICAgICAgaXRlbXM6IChhd2FpdCBsb2FkRXhhbXBsZXNEYXRhKCkpLm1hcCgoaXRlbSkgPT4ge1xuICAgICAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICAgICAgdGV4dDogaXRlbS50aXRsZSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vcmVmZXJlbmNlcy9leGFtcGxlcy8ke2l0ZW0ubmFtZX1gLFxuICAgICAgICAgICAgfTtcbiAgICAgICAgICB9KSxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMucmVmZXJlbmNlcy5pdGVtcy5taWdyYXRpb25zLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGNvbGxhcHNlZDogdHJ1ZSxcbiAgICAgICAgICBpdGVtczogW1xuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMucmVmZXJlbmNlcy5pdGVtcy5taWdyYXRpb25zLml0ZW1zLmZyb20tdjMtdG8tdjQudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9yZWZlcmVuY2VzL21pZ3JhdGlvbnMvZnJvbS12My10by12NGAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgIF0sXG4gICAgICAgIH0sXG4gICAgICBdLFxuICAgIH0sXG4gIF07XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBuYXZCYXIobG9jYWxlKSB7XG4gIHJldHVybiBbXG4gICAge1xuICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+JHtsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgIGxvY2FsZSxcbiAgICAgICAgXCJuYXZiYXIuZ3VpZGVzLnRleHRcIixcbiAgICAgICl9ICR7Ym9va09wZW4wMUljb24oKX08L3NwYW4+YCxcbiAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2AsXG4gICAgfSxcbiAgICB7XG4gICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj4ke2xvY2FsaXplZFN0cmluZyhcbiAgICAgICAgbG9jYWxlLFxuICAgICAgICBcIm5hdmJhci5jbGkudGV4dFwiLFxuICAgICAgKX0gJHtjb2RlQnJvd3Nlckljb24oKX08L3NwYW4+YCxcbiAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2NsaS9hdXRoYCxcbiAgICB9LFxuICAgIHtcbiAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhsb2NhbGUsIFwibmF2YmFyLnJlc291cmNlcy50ZXh0XCIpLFxuICAgICAgaXRlbXM6IFtcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwibmF2YmFyLnJlc291cmNlcy5pdGVtcy5yZWZlcmVuY2VzLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L3JlZmVyZW5jZXMvcHJvamVjdC1kZXNjcmlwdGlvbi9zdHJ1Y3RzL3Byb2plY3RgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJuYXZiYXIucmVzb3VyY2VzLml0ZW1zLmNvbnRyaWJ1dG9ycy50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jb250cmlidXRvcnMvZ2V0LXN0YXJ0ZWRgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJuYXZiYXIucmVzb3VyY2VzLml0ZW1zLmNoYW5nZWxvZy50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBcImh0dHBzOi8vZ2l0aHViLmNvbS90dWlzdC90dWlzdC9yZWxlYXNlc1wiLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMuYXBpLWRvY3VtZW50YXRpb24udGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogXCJodHRwczovL3R1aXN0LmRldi9hcGkvZG9jc1wiLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKGxvY2FsZSwgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMuc3RhdHVzLnRleHRcIiksXG4gICAgICAgICAgbGluazogXCJodHRwczovL3N0YXR1cy50dWlzdC5pb1wiLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5zZXJ2ZXIuaXRlbXMubWV0cmljcy1kYXNoYm9hcmQudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogXCJodHRwczovL3R1aXN0LmdyYWZhbmEubmV0L3B1YmxpYy1kYXNoYm9hcmRzLzFmODVmMWMzODk1ZTQ4ZmViZDAyY2M3MzUwYWRlMmQ5XCIsXG4gICAgICAgIH0sXG4gICAgICBdLFxuICAgIH0sXG4gIF07XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBjb250cmlidXRvcnNTaWRlYmFyKGxvY2FsZSkge1xuICByZXR1cm4gW1xuICAgIHtcbiAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhsb2NhbGUsIFwic2lkZWJhcnMuY29udHJpYnV0b3JzLnRleHRcIiksXG4gICAgICBpdGVtczogW1xuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5jb250cmlidXRvcnMuaXRlbXMuZ2V0LXN0YXJ0ZWQudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vY29udHJpYnV0b3JzL2dldC1zdGFydGVkYCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuY29udHJpYnV0b3JzLml0ZW1zLmlzc3VlLXJlcG9ydGluZy50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jb250cmlidXRvcnMvaXNzdWUtcmVwb3J0aW5nYCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuY29udHJpYnV0b3JzLml0ZW1zLmNvZGUtcmV2aWV3cy50ZXh0XCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jb250cmlidXRvcnMvY29kZS1yZXZpZXdzYCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuY29udHJpYnV0b3JzLml0ZW1zLnByaW5jaXBsZXMudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vY29udHJpYnV0b3JzL3ByaW5jaXBsZXNgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5jb250cmlidXRvcnMuaXRlbXMudHJhbnNsYXRlLnRleHRcIixcbiAgICAgICAgICApLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2NvbnRyaWJ1dG9ycy90cmFuc2xhdGVgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKGxvY2FsZSwgXCJzaWRlYmFycy5jb250cmlidXRvcnMuaXRlbXMuY2xpLnRleHRcIiksXG4gICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5jb250cmlidXRvcnMuaXRlbXMuY2xpLml0ZW1zLmxvZ2dpbmcudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jb250cmlidXRvcnMvY2xpL2xvZ2dpbmdgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICBdLFxuICAgICAgICB9LFxuICAgICAgXSxcbiAgICB9LFxuICBdO1xufVxuXG5cbmV4cG9ydCBmdW5jdGlvbiBndWlkZXNTaWRlYmFyKGxvY2FsZSkge1xuICByZXR1cm4gW1xuICAgIHtcbiAgICAgIHRleHQ6IFwiVHVpc3RcIixcbiAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2AsXG4gICAgICBpdGVtczogW1xuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMudHVpc3QuaXRlbXMuYWJvdXQudGV4dFwiLFxuICAgICAgICAgICksXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3R1aXN0L2Fib3V0YCxcbiAgICAgICAgfSxcbiAgICAgIF0sXG4gICAgfSxcbiAgICB7XG4gICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgIGxvY2FsZSxcbiAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMucXVpY2stc3RhcnQudGV4dFwiLFxuICAgICAgKSxcbiAgICAgIGl0ZW1zOiBbXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj4ke2luc3RhbGxUdWlzdEljb24oKX0gJHtsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5xdWljay1zdGFydC5pdGVtcy5pbnN0YWxsLXR1aXN0LnRleHRcIixcbiAgICAgICAgICApfTwvc3Bhbj5gLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9xdWljay1zdGFydC9pbnN0YWxsLXR1aXN0YCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7Z2V0U3RhcnRlZEljb24oKX0gJHtsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5xdWljay1zdGFydC5pdGVtcy5nZXQtc3RhcnRlZC50ZXh0XCIsXG4gICAgICAgICAgKX08L3NwYW4+YCxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvcXVpY2stc3RhcnQvZ2V0LXN0YXJ0ZWRgLFxuICAgICAgICB9LFxuICAgICAgXSxcbiAgICB9LFxuICAgIHtcbiAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgbG9jYWxlLFxuICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5mZWF0dXJlcy50ZXh0XCIsXG4gICAgICApLFxuICAgICAgaXRlbXM6IFtcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7cHJvamVjdHNJY29uKCl9ICR7bG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5nZW5lcmF0ZWQtcHJvamVjdHMudGV4dFwiLFxuICAgICAgICAgICl9PC9zcGFuPmAsXG4gICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9wcm9qZWN0c2AsXG4gICAgICAgICAgaXRlbXM6IFtcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5hZG9wdGlvbi50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGNvbGxhcHNlZDogdHJ1ZSxcbiAgICAgICAgICAgICAgaXRlbXM6IFtcbiAgICAgICAgICAgICAgICB7XG4gICAgICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5nZW5lcmF0ZWQtcHJvamVjdHMuaXRlbXMuYWRvcHRpb24uaXRlbXMubmV3LXByb2plY3QudGV4dFwiLFxuICAgICAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9wcm9qZWN0cy9hZG9wdGlvbi9uZXctcHJvamVjdGAsXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICB7XG4gICAgICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5nZW5lcmF0ZWQtcHJvamVjdHMuaXRlbXMuYWRvcHRpb24uaXRlbXMuc3dpZnQtcGFja2FnZS50ZXh0XCIsXG4gICAgICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL2Fkb3B0aW9uL3N3aWZ0LXBhY2thZ2VgLFxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAge1xuICAgICAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLmFkb3B0aW9uLml0ZW1zLm1pZ3JhdGUudGV4dFwiLFxuICAgICAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgICAgIGNvbGxhcHNlZDogdHJ1ZSxcbiAgICAgICAgICAgICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5hZG9wdGlvbi5pdGVtcy5taWdyYXRlLml0ZW1zLnhjb2RlLXByb2plY3QudGV4dFwiLFxuICAgICAgICAgICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL2Fkb3B0aW9uL21pZ3JhdGUveGNvZGUtcHJvamVjdGAsXG4gICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5hZG9wdGlvbi5pdGVtcy5taWdyYXRlLml0ZW1zLnN3aWZ0LXBhY2thZ2UudGV4dFwiLFxuICAgICAgICAgICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL2Fkb3B0aW9uL21pZ3JhdGUvc3dpZnQtcGFja2FnZWAsXG4gICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5hZG9wdGlvbi5pdGVtcy5taWdyYXRlLml0ZW1zLnhjb2RlZ2VuLXByb2plY3QudGV4dFwiLFxuICAgICAgICAgICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL2Fkb3B0aW9uL21pZ3JhdGUveGNvZGVnZW4tcHJvamVjdGAsXG4gICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5hZG9wdGlvbi5pdGVtcy5taWdyYXRlLml0ZW1zLmJhemVsLXByb2plY3QudGV4dFwiLFxuICAgICAgICAgICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL2Fkb3B0aW9uL21pZ3JhdGUvYmF6ZWwtcHJvamVjdGAsXG4gICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICBdLFxuICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgIF0sXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLm1hbmlmZXN0cy50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9wcm9qZWN0cy9tYW5pZmVzdHNgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5kaXJlY3Rvcnktc3RydWN0dXJlLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL2RpcmVjdG9yeS1zdHJ1Y3R1cmVgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5lZGl0aW5nLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL2VkaXRpbmdgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5kZXBlbmRlbmNpZXMudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvZGVwZW5kZW5jaWVzYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5nZW5lcmF0ZWQtcHJvamVjdHMuaXRlbXMuY29kZS1zaGFyaW5nLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL2NvZGUtc2hhcmluZ2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLnN5bnRoZXNpemVkLWZpbGVzLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL3N5bnRoZXNpemVkLWZpbGVzYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5nZW5lcmF0ZWQtcHJvamVjdHMuaXRlbXMuZHluYW1pYy1jb25maWd1cmF0aW9uLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL2R5bmFtaWMtY29uZmlndXJhdGlvbmAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLnRlbXBsYXRlcy50ZXh0XCIsXG4gICAgICAgICAgICAgICksXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9wcm9qZWN0cy90ZW1wbGF0ZXNgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5wbHVnaW5zLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL3BsdWdpbnNgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5oYXNoaW5nLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL2hhc2hpbmdgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5pbnNwZWN0LnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgICAgICBpdGVtczogW1xuICAgICAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0cy5pdGVtcy5pbnNwZWN0Lml0ZW1zLmltcGxpY2l0LWltcG9ydHMudGV4dFwiLFxuICAgICAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9wcm9qZWN0cy9pbnNwZWN0L2ltcGxpY2l0LWRlcGVuZGVuY2llc2AsXG4gICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgXSxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5nZW5lcmF0ZWQtcHJvamVjdHMuaXRlbXMudGhlLWNvc3Qtb2YtY29udmVuaWVuY2UudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvY29zdC1vZi1jb252ZW5pZW5jZWAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLnRtYS1hcmNoaXRlY3R1cmUudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcHJvamVjdHMvdG1hLWFyY2hpdGVjdHVyZWAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3RzLml0ZW1zLmJlc3QtcHJhY3RpY2VzLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL2Jlc3QtcHJhY3RpY2VzYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgXSxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7Y2FjaGVJY29uKCl9ICR7bG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5jYWNoZS50ZXh0XCIsXG4gICAgICAgICAgKX08L3NwYW4+YCxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvY2FjaGVgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+JHt0ZXN0SWNvbigpfSAke2xvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuc2VsZWN0aXZlLXRlc3RpbmcudGV4dFwiLFxuICAgICAgICAgICl9PC9zcGFuPmAsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3NlbGVjdGl2ZS10ZXN0aW5nYCxcbiAgICAgICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICAgICAgaXRlbXM6IFtcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLnNlbGVjdGl2ZS10ZXN0aW5nLml0ZW1zLnhjb2RlLXByb2plY3QudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvc2VsZWN0aXZlLXRlc3RpbmcveGNvZGUtcHJvamVjdGAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgICAgbG9jYWxlLFxuICAgICAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuc2VsZWN0aXZlLXRlc3RpbmcuaXRlbXMuZ2VuZXJhdGVkLXByb2plY3QudGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvc2VsZWN0aXZlLXRlc3RpbmcvZ2VuZXJhdGVkLXByb2plY3RgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICBdLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+JHtyZWdpc3RyeUljb24oKX0gJHtsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLnJlZ2lzdHJ5LnRleHRcIixcbiAgICAgICAgICApfTwvc3Bhbj5gLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9yZWdpc3RyeWAsXG4gICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5yZWdpc3RyeS5pdGVtcy54Y29kZS1wcm9qZWN0LnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3JlZ2lzdHJ5L3hjb2RlLXByb2plY3RgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLnJlZ2lzdHJ5Lml0ZW1zLmdlbmVyYXRlZC1wcm9qZWN0LnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3JlZ2lzdHJ5L2dlbmVyYXRlZC1wcm9qZWN0YCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5yZWdpc3RyeS5pdGVtcy54Y29kZXByb2otaW50ZWdyYXRpb24udGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcmVnaXN0cnkveGNvZGVwcm9qLWludGVncmF0aW9uYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGxvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuZGV2ZWxvcC5pdGVtcy5yZWdpc3RyeS5pdGVtcy5zd2lmdC1wYWNrYWdlLnRleHRcIixcbiAgICAgICAgICAgICAgKSxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL3JlZ2lzdHJ5L3N3aWZ0LXBhY2thZ2VgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLnJlZ2lzdHJ5Lml0ZW1zLmNvbnRpbnVvdXMtaW50ZWdyYXRpb24udGV4dFwiLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvcmVnaXN0cnkvY29udGludW91cy1pbnRlZ3JhdGlvbmAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgIF0sXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj4ke2luc2lnaHRzSWNvbigpfSAke2xvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLmRldmVsb3AuaXRlbXMuaW5zaWdodHMudGV4dFwiLFxuICAgICAgICAgICl9PC9zcGFuPmAsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ZlYXR1cmVzL2luc2lnaHRzYCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7YnVuZGxlU2l6ZUljb24oKX0gJHtsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5kZXZlbG9wLml0ZW1zLmJ1bmRsZS1zaXplLnRleHRcIixcbiAgICAgICAgICApfTwvc3Bhbj5gLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9idW5kbGUtc2l6ZWAsXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj4ke3ByZXZpZXdzSWNvbigpfSAke2xvY2FsaXplZFN0cmluZyhcbiAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgIFwic2lkZWJhcnMuZ3VpZGVzLml0ZW1zLnNoYXJlLml0ZW1zLnByZXZpZXdzLnRleHRcIixcbiAgICAgICAgICApfTwvc3Bhbj5gLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9mZWF0dXJlcy9wcmV2aWV3c2AsXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj4ke2FnZW50aWNCdWlsZGluZ0ljb24oKX0gJHtsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5hZ2VudGljLWNvZGluZy50ZXh0XCIsXG4gICAgICAgICAgKX08L3NwYW4+YCxcbiAgICAgICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICAgICAgaXRlbXM6IFtcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+JHttY3BJY29uKCl9ICR7bG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5hZ2VudGljLWNvZGluZy5pdGVtcy5tY3AudGV4dFwiLFxuICAgICAgICAgICAgICApfTwvc3Bhbj5gLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZmVhdHVyZXMvYWdlbnRpYy1jb2RpbmcvbWNwYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgXSxcbiAgICAgICAgfSxcbiAgICAgIF0sXG4gICAgfSxcbiAgICB7XG4gICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgIGxvY2FsZSxcbiAgICAgICAgXCJzaWRlYmFycy5ndWlkZXMuaXRlbXMuaW50ZWdyYXRpb25zLnRleHRcIixcbiAgICAgICksXG4gICAgICBpdGVtczogW1xuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+JHtjaUljb24oKX0gJHtsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICBcInNpZGViYXJzLmd1aWRlcy5pdGVtcy5pbnRlZ3JhdGlvbnMuaXRlbXMuY29udGludW91cy1pbnRlZ3JhdGlvbi50ZXh0XCIsXG4gICAgICAgICAgKX08L3NwYW4+YCxcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvaW50ZWdyYXRpb25zL2NvbnRpbnVvdXMtaW50ZWdyYXRpb25gLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+JHtzc29JY29uKCl9IFNTTzwvc3Bhbj5gLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9pbnRlZ3JhdGlvbnMvc3NvYCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7Z2l0Rm9yZ2VzSWNvbigpfSBHaXQgZm9yZ2VzPC9zcGFuPmAsXG4gICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7Z2l0aHViSWNvbigpfSBHaXRIdWI8L3NwYW4+YCxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2ludGVncmF0aW9ucy9naXRmb3JnZS9naXRodWJgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICBdLFxuICAgICAgICB9LFxuICAgICAgXSxcbiAgICB9LFxuICAgIHtcbiAgICAgIHRleHQ6IFwiU2VydmVyXCIsXG4gICAgICBpdGVtczogW1xuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+JHthY2NvdW50c0ljb24oKX0gQWNjb3VudHMgYW5kIHByb2plY3RzPC9zcGFuPmAsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3NlcnZlci9hY2NvdW50cy1hbmQtcHJvamVjdHNgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+JHthdXRoSWNvbigpfSBBdXRoZW50aWNhdGlvbjwvc3Bhbj5gLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9zZXJ2ZXIvYXV0aGVudGljYXRpb25gLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+JHtzZWxmSG9zdGluZ0ljb24oKX0gU2VsZi1ob3N0aW5nPC9zcGFuPmAsXG4gICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPiR7aW5zdGFsbEljb24oKX0gSW5zdGFsbGF0aW9uPC9zcGFuPmAsXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9zZXJ2ZXIvc2VsZi1ob3N0L2luc3RhbGxgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+JHt0ZWxlbWV0cnlJY29uKCl9IFRlbGVtZXRyeTwvc3Bhbj5gLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvc2VydmVyL3NlbGYtaG9zdC90ZWxlbWV0cnlgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICBdLFxuICAgICAgICB9LFxuICAgICAgXSxcbiAgICB9LFxuICBdO1xufVxuIiwgImNvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2RhdGFcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZmlsZW5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvZGF0YS9jbGkuanNcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfaW1wb3J0X21ldGFfdXJsID0gXCJmaWxlOi8vL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9kYXRhL2NsaS5qc1wiO2ltcG9ydCB7IGV4ZWNhLCAkIH0gZnJvbSBcImV4ZWNhXCI7XG5pbXBvcnQgeyB0ZW1wb3JhcnlEaXJlY3RvcnlUYXNrIH0gZnJvbSBcInRlbXB5XCI7XG5pbXBvcnQgKiBhcyBwYXRoIGZyb20gXCJub2RlOnBhdGhcIjtcbmltcG9ydCB7IGZpbGVVUkxUb1BhdGggfSBmcm9tIFwibm9kZTp1cmxcIjtcbmltcG9ydCBlanMgZnJvbSBcImVqc1wiO1xuaW1wb3J0IHsgbG9jYWxpemVkU3RyaW5nIH0gZnJvbSBcIi4uL2kxOG4ubWpzXCI7XG5cbi8vIFJvb3QgZGlyZWN0b3J5XG5jb25zdCBfX2Rpcm5hbWUgPSBwYXRoLmRpcm5hbWUoZmlsZVVSTFRvUGF0aChpbXBvcnQubWV0YS51cmwpKTtcbmNvbnN0IHJvb3REaXJlY3RvcnkgPSBwYXRoLmpvaW4oX19kaXJuYW1lLCBcIi4uLy4uLy4uXCIpO1xuXG4vLyBTY2hlbWFcbmF3YWl0IGV4ZWNhKHtcbiAgc3RkaW86IFwiaW5oZXJpdFwiLFxufSlgc3dpZnQgYnVpbGQgLS1wcm9kdWN0IFByb2plY3REZXNjcmlwdGlvbiAtLWNvbmZpZ3VyYXRpb24gZGVidWcgLS1wYWNrYWdlLXBhdGggJHtyb290RGlyZWN0b3J5fWA7XG5hd2FpdCBleGVjYSh7XG4gIHN0ZGlvOiBcImluaGVyaXRcIixcbn0pYHN3aWZ0IGJ1aWxkIC0tcHJvZHVjdCB0dWlzdCAtLWNvbmZpZ3VyYXRpb24gZGVidWcgLS1wYWNrYWdlLXBhdGggJHtyb290RGlyZWN0b3J5fWA7XG52YXIgZHVtcGVkQ0xJU2NoZW1hO1xuYXdhaXQgdGVtcG9yYXJ5RGlyZWN0b3J5VGFzayhhc3luYyAodG1wRGlyKSA9PiB7XG4gIC8vIEknbSBwYXNzaW5nIC0tcGF0aCB0byBzYW5kYm94IHRoZSBleGVjdXRpb24gc2luY2Ugd2UgYXJlIG9ubHkgaW50ZXJlc3RlZCBpbiB0aGUgc2NoZW1hIGFuZCBub3RoaW5nIGVsc2UuXG4gIGR1bXBlZENMSVNjaGVtYSA9IGF3YWl0ICRgJHtwYXRoLmpvaW4oXG4gICAgcm9vdERpcmVjdG9yeSxcbiAgICBcIi5idWlsZC9kZWJ1Zy90dWlzdFwiLFxuICApfSAtLWV4cGVyaW1lbnRhbC1kdW1wLWhlbHAgLS1wYXRoICR7dG1wRGlyfWA7XG59KTtcbmNvbnN0IHsgc3Rkb3V0IH0gPSBkdW1wZWRDTElTY2hlbWE7XG5leHBvcnQgY29uc3Qgc2NoZW1hID0gSlNPTi5wYXJzZShzdGRvdXQpO1xuXG4vLyBQYXRoc1xuZnVuY3Rpb24gdHJhdmVyc2UoY29tbWFuZCwgcGF0aHMpIHtcbiAgcGF0aHMucHVzaCh7XG4gICAgcGFyYW1zOiB7IGNvbW1hbmQ6IGNvbW1hbmQubGluay5zcGxpdChcImNsaS9cIilbMV0gfSxcbiAgICBjb250ZW50OiBjb250ZW50KGNvbW1hbmQpLFxuICB9KTtcbiAgKGNvbW1hbmQuaXRlbXMgPz8gW10pLmZvckVhY2goKHN1YkNvbW1hbmQpID0+IHtcbiAgICB0cmF2ZXJzZShzdWJDb21tYW5kLCBwYXRocyk7XG4gIH0pO1xufVxuXG5jb25zdCB0ZW1wbGF0ZSA9IGVqcy5jb21waWxlKFxuICBgXG4jIDwlPSBjb21tYW5kLmZ1bGxDb21tYW5kICU+XG48JT0gY29tbWFuZC5zcGVjLmFic3RyYWN0ICU+XG48JSBpZiAoY29tbWFuZC5zcGVjLmFyZ3VtZW50cyAmJiBjb21tYW5kLnNwZWMuYXJndW1lbnRzLmxlbmd0aCA+IDApIHsgJT5cbiMjIEFyZ3VtZW50c1xuPCUgY29tbWFuZC5zcGVjLmFyZ3VtZW50cy5mb3JFYWNoKGZ1bmN0aW9uKGFyZykgeyAlPlxuIyMjIDwlLSBhcmcudmFsdWVOYW1lICU+IDwlLSAoYXJnLmlzT3B0aW9uYWwpID8gXCI8QmFkZ2UgdHlwZT0naW5mbycgdGV4dD0nT3B0aW9uYWwnIC8+XCIgOiBcIlwiICU+IDwlLSAoYXJnLmlzRGVwcmVjYXRlZCkgPyBcIjxCYWRnZSB0eXBlPSd3YXJuaW5nJyB0ZXh0PSdEZXByZWNhdGVkJyAvPlwiIDogXCJcIiAlPlxuPCUgaWYgKGFyZy5lbnZWYXIpIHsgJT5cbioqRW52aXJvbm1lbnQgdmFyaWFibGUqKiBcXGA8JS0gYXJnLmVudlZhciAlPlxcYFxuPCUgfSAlPlxuPCUtIGFyZy5hYnN0cmFjdCAlPlxuPCUgaWYgKGFyZy5raW5kID09PSBcInBvc2l0aW9uYWxcIikgeyAtJT5cblxcYFxcYFxcYGJhc2hcbjwlLSBjb21tYW5kLmZ1bGxDb21tYW5kICU+IFs8JS0gYXJnLnZhbHVlTmFtZSAlPl1cblxcYFxcYFxcYFxuPCUgfSBlbHNlIGlmIChhcmcua2luZCA9PT0gXCJmbGFnXCIpIHsgLSU+XG5cXGBcXGBcXGBiYXNoXG48JSBhcmcubmFtZXMuZm9yRWFjaChmdW5jdGlvbihuYW1lKSB7IC0lPlxuPCUgaWYgKG5hbWUua2luZCA9PT0gXCJsb25nXCIpIHsgLSU+XG48JS0gY29tbWFuZC5mdWxsQ29tbWFuZCAlPiAtLTwlLSBuYW1lLm5hbWUgJT5cbjwlIH0gZWxzZSB7IC0lPlxuPCUtIGNvbW1hbmQuZnVsbENvbW1hbmQgJT4gLTwlLSBuYW1lLm5hbWUgJT5cbjwlIH0gLSU+XG48JSB9KSAtJT5cblxcYFxcYFxcYFxuPCUgfSBlbHNlIGlmIChhcmcua2luZCA9PT0gXCJvcHRpb25cIikgeyAtJT5cblxcYFxcYFxcYGJhc2hcbjwlIGFyZy5uYW1lcy5mb3JFYWNoKGZ1bmN0aW9uKG5hbWUpIHsgLSU+XG48JSBpZiAobmFtZS5raW5kID09PSBcImxvbmdcIikgeyAtJT5cbjwlLSBjb21tYW5kLmZ1bGxDb21tYW5kICU+IC0tPCUtIG5hbWUubmFtZSAlPiBbPCUtIGFyZy52YWx1ZU5hbWUgJT5dXG48JSB9IGVsc2UgeyAtJT5cbjwlLSBjb21tYW5kLmZ1bGxDb21tYW5kICU+IC08JS0gbmFtZS5uYW1lICU+IFs8JS0gYXJnLnZhbHVlTmFtZSAlPl1cbjwlIH0gLSU+XG48JSB9KSAtJT5cblxcYFxcYFxcYFxuPCUgfSAtJT5cbjwlIH0pOyAtJT5cbjwlIH0gLSU+XG5gLFxuICB7fSxcbik7XG5cbmZ1bmN0aW9uIGNvbnRlbnQoY29tbWFuZCkge1xuICBjb25zdCBlbnZWYXJSZWdleCA9IC9cXChlbnY6XFxzKihbXildKylcXCkvO1xuICBjb25zdCBjb250ZW50ID0gdGVtcGxhdGUoe1xuICAgIGNvbW1hbmQ6IHtcbiAgICAgIC4uLmNvbW1hbmQsXG4gICAgICBzcGVjOiB7XG4gICAgICAgIC4uLmNvbW1hbmQuc3BlYyxcbiAgICAgICAgYXJndW1lbnRzOiBjb21tYW5kLnNwZWMuYXJndW1lbnRzLm1hcCgoYXJnKSA9PiB7XG4gICAgICAgICAgY29uc3QgZW52VmFyTWF0Y2ggPSBhcmcuYWJzdHJhY3QubWF0Y2goZW52VmFyUmVnZXgpO1xuICAgICAgICAgIHJldHVybiB7XG4gICAgICAgICAgICAuLi5hcmcsXG4gICAgICAgICAgICBlbnZWYXI6IGVudlZhck1hdGNoID8gZW52VmFyTWF0Y2hbMV0gOiB1bmRlZmluZWQsXG4gICAgICAgICAgICBpc0RlcHJlY2F0ZWQ6XG4gICAgICAgICAgICAgIGFyZy5hYnN0cmFjdC5pbmNsdWRlcyhcIltEZXByZWNhdGVkXVwiKSB8fFxuICAgICAgICAgICAgICBhcmcuYWJzdHJhY3QuaW5jbHVkZXMoXCJbZGVwcmVjYXRlZF1cIiksXG4gICAgICAgICAgICBhYnN0cmFjdDogYXJnLmFic3RyYWN0XG4gICAgICAgICAgICAgIC5yZXBsYWNlKGVudlZhclJlZ2V4LCBcIlwiKVxuICAgICAgICAgICAgICAucmVwbGFjZShcIltEZXByZWNhdGVkXVwiLCBcIlwiKVxuICAgICAgICAgICAgICAucmVwbGFjZShcIltkZXByZWNhdGVkXVwiLCBcIlwiKVxuICAgICAgICAgICAgICAudHJpbSgpXG4gICAgICAgICAgICAgIC5yZXBsYWNlKC88KFtePl0rKT4vZywgXCJcXFxcPCQxXFxcXD5cIiksXG4gICAgICAgICAgfTtcbiAgICAgICAgfSksXG4gICAgICB9LFxuICAgIH0sXG4gIH0pO1xuICByZXR1cm4gY29udGVudDtcbn1cblxuZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIHBhdGhzKGxvY2FsZSkge1xuICBsZXQgcGF0aHMgPSBbXTtcbiAgKGF3YWl0IGxvYWREYXRhKGxvY2FsZSkpLml0ZW1zWzBdLml0ZW1zLmZvckVhY2goKGNvbW1hbmQpID0+IHtcbiAgICB0cmF2ZXJzZShjb21tYW5kLCBwYXRocyk7XG4gIH0pO1xuICByZXR1cm4gcGF0aHM7XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiBjbGlTaWRlYmFyKGxvY2FsZSkge1xuICBjb25zdCBzaWRlYmFyID0gYXdhaXQgbG9hZERhdGEobG9jYWxlKTtcbiAgcmV0dXJuIHtcbiAgICAuLi5zaWRlYmFyLFxuICAgIGl0ZW1zOiBbXG4gICAgICB7XG4gICAgICAgIHRleHQ6IFwiQ0xJXCIsXG4gICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAge1xuICAgICAgICAgICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKFxuICAgICAgICAgICAgICBsb2NhbGUsXG4gICAgICAgICAgICAgIFwic2lkZWJhcnMuY2xpLml0ZW1zLmNsaS5pdGVtcy5sb2dnaW5nLnRleHRcIixcbiAgICAgICAgICAgICksXG4gICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jbGkvbG9nZ2luZ2AsXG4gICAgICAgICAgfSxcbiAgICAgICAgICB7XG4gICAgICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcoXG4gICAgICAgICAgICAgIGxvY2FsZSxcbiAgICAgICAgICAgICAgXCJzaWRlYmFycy5jbGkuaXRlbXMuY2xpLml0ZW1zLnNoZWxsLWNvbXBsZXRpb25zLnRleHRcIixcbiAgICAgICAgICAgICksXG4gICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jbGkvc2hlbGwtY29tcGxldGlvbnNgLFxuICAgICAgICAgIH0sXG4gICAgICAgIF0sXG4gICAgICB9LFxuICAgICAgLi4uc2lkZWJhci5pdGVtcyxcbiAgICBdLFxuICB9O1xufVxuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gbG9hZERhdGEobG9jYWxlKSB7XG4gIGZ1bmN0aW9uIHBhcnNlQ29tbWFuZChcbiAgICBjb21tYW5kLFxuICAgIHBhcmVudENvbW1hbmQgPSBcInR1aXN0XCIsXG4gICAgcGFyZW50UGF0aCA9IGAvJHtsb2NhbGV9L2NsaS9gLFxuICApIHtcbiAgICBjb25zdCBvdXRwdXQgPSB7XG4gICAgICB0ZXh0OiBjb21tYW5kLmNvbW1hbmROYW1lLFxuICAgICAgZnVsbENvbW1hbmQ6IHBhcmVudENvbW1hbmQgKyBcIiBcIiArIGNvbW1hbmQuY29tbWFuZE5hbWUsXG4gICAgICBsaW5rOiBwYXRoLmpvaW4ocGFyZW50UGF0aCwgY29tbWFuZC5jb21tYW5kTmFtZSksXG4gICAgICBzcGVjOiBjb21tYW5kLFxuICAgIH07XG4gICAgaWYgKGNvbW1hbmQuc3ViY29tbWFuZHMgJiYgY29tbWFuZC5zdWJjb21tYW5kcy5sZW5ndGggIT09IDApIHtcbiAgICAgIG91dHB1dC5pdGVtcyA9IGNvbW1hbmQuc3ViY29tbWFuZHMubWFwKChzdWJjb21tYW5kKSA9PiB7XG4gICAgICAgIHJldHVybiBwYXJzZUNvbW1hbmQoXG4gICAgICAgICAgc3ViY29tbWFuZCxcbiAgICAgICAgICBwYXJlbnRDb21tYW5kICsgXCIgXCIgKyBjb21tYW5kLmNvbW1hbmROYW1lLFxuICAgICAgICAgIHBhdGguam9pbihwYXJlbnRQYXRoLCBjb21tYW5kLmNvbW1hbmROYW1lKSxcbiAgICAgICAgKTtcbiAgICAgIH0pO1xuICAgIH1cblxuICAgIHJldHVybiBvdXRwdXQ7XG4gIH1cblxuICBjb25zdCB7XG4gICAgY29tbWFuZDogeyBzdWJjb21tYW5kcyB9LFxuICB9ID0gc2NoZW1hO1xuXG4gIHJldHVybiB7XG4gICAgdGV4dDogbG9jYWxpemVkU3RyaW5nKGxvY2FsZSwgXCJzaWRlYmFycy5jbGkudGV4dFwiKSxcbiAgICBpdGVtczogW1xuICAgICAge1xuICAgICAgICB0ZXh0OiBsb2NhbGl6ZWRTdHJpbmcobG9jYWxlLCBcInNpZGViYXJzLmNsaS5pdGVtcy5jb21tYW5kcy50ZXh0XCIpLFxuICAgICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICAgIGl0ZW1zOiBzdWJjb21tYW5kc1xuICAgICAgICAgIC5tYXAoKGNvbW1hbmQpID0+IHtcbiAgICAgICAgICAgIHJldHVybiB7XG4gICAgICAgICAgICAgIC4uLnBhcnNlQ29tbWFuZChjb21tYW5kKSxcbiAgICAgICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgICAgfTtcbiAgICAgICAgICB9KVxuICAgICAgICAgIC5zb3J0KChhLCBiKSA9PiBhLnRleHQubG9jYWxlQ29tcGFyZShiLnRleHQpKSxcbiAgICAgIH0sXG4gICAgXSxcbiAgfTtcbn1cbiIsICJjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9maWxlbmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9saW5rVmFsaWRhdG9yLm1qc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9pbXBvcnRfbWV0YV91cmwgPSBcImZpbGU6Ly8vVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2xpbmtWYWxpZGF0b3IubWpzXCI7aW1wb3J0ICogYXMgZnMgZnJvbSBcIm5vZGU6ZnNcIjtcbmltcG9ydCAqIGFzIHBhdGggZnJvbSBcIm5vZGU6cGF0aFwiO1xuXG5jb25zdCBTVVBQT1JURURfTEFOR1VBR0VTID0gWydlbicsICdlcycsICdqYScsICdrbycsICdwdCcsICdydSddO1xuXG4vKipcbiAqIFZhbGlkYXRlcyBMb2NhbGl6ZWRMaW5rIGhyZWYgdmFsdWVzIGR1cmluZyBidWlsZCB0aW1lXG4gKi9cbmV4cG9ydCBjbGFzcyBMb2NhbGl6ZWRMaW5rVmFsaWRhdG9yIHtcbiAgY29uc3RydWN0b3Ioc3JjRGlyKSB7XG4gICAgdGhpcy5zcmNEaXIgPSBzcmNEaXI7XG4gICAgdGhpcy5saW5rUmVnaXN0cnkgPSBuZXcgTWFwKCk7XG4gICAgdGhpcy5icm9rZW5MaW5rcyA9IFtdO1xuICAgIHRoaXMudmFsaWRhdGVkTGlua3MgPSBuZXcgU2V0KCk7XG4gIH1cblxuICAvKipcbiAgICogU2NhbnMgYWxsIG1hcmtkb3duIGZpbGVzIGFuZCBleHRyYWN0cyBMb2NhbGl6ZWRMaW5rIGhyZWYgdmFsdWVzXG4gICAqL1xuICBhc3luYyBzY2FuRmlsZXMoKSB7XG4gICAgY29uc29sZS5sb2coJ1x1RDgzRFx1REQwRCBTY2FubmluZyBmaWxlcyBmb3IgTG9jYWxpemVkTGluayBjb21wb25lbnRzLi4uJyk7XG4gICAgXG4gICAgZm9yIChjb25zdCBsYW5nIG9mIFNVUFBPUlRFRF9MQU5HVUFHRVMpIHtcbiAgICAgIGNvbnN0IGxhbmdEaXIgPSBwYXRoLmpvaW4odGhpcy5zcmNEaXIsIGxhbmcpO1xuICAgICAgaWYgKGZzLmV4aXN0c1N5bmMobGFuZ0RpcikpIHtcbiAgICAgICAgYXdhaXQgdGhpcy5zY2FuRGlyZWN0b3J5KGxhbmdEaXIsIGxhbmcpO1xuICAgICAgfVxuICAgIH1cbiAgICBcbiAgICBjb25zb2xlLmxvZyhgXHVEODNEXHVEQ0NBIEZvdW5kICR7dGhpcy5saW5rUmVnaXN0cnkuc2l6ZX0gdW5pcXVlIExvY2FsaXplZExpbmsgcmVmZXJlbmNlc2ApO1xuICB9XG5cbiAgLyoqXG4gICAqIFJlY3Vyc2l2ZWx5IHNjYW5zIGEgZGlyZWN0b3J5IGZvciBtYXJrZG93biBmaWxlc1xuICAgKi9cbiAgYXN5bmMgc2NhbkRpcmVjdG9yeShkaXIsIGxhbmcpIHtcbiAgICBjb25zdCBlbnRyaWVzID0gZnMucmVhZGRpclN5bmMoZGlyLCB7IHdpdGhGaWxlVHlwZXM6IHRydWUgfSk7XG4gICAgXG4gICAgZm9yIChjb25zdCBlbnRyeSBvZiBlbnRyaWVzKSB7XG4gICAgICBjb25zdCBmdWxsUGF0aCA9IHBhdGguam9pbihkaXIsIGVudHJ5Lm5hbWUpO1xuICAgICAgXG4gICAgICBpZiAoZW50cnkuaXNEaXJlY3RvcnkoKSkge1xuICAgICAgICBhd2FpdCB0aGlzLnNjYW5EaXJlY3RvcnkoZnVsbFBhdGgsIGxhbmcpO1xuICAgICAgfSBlbHNlIGlmIChlbnRyeS5pc0ZpbGUoKSAmJiBlbnRyeS5uYW1lLmVuZHNXaXRoKCcubWQnKSkge1xuICAgICAgICBhd2FpdCB0aGlzLnNjYW5GaWxlKGZ1bGxQYXRoLCBsYW5nKTtcbiAgICAgIH1cbiAgICB9XG4gIH1cblxuICAvKipcbiAgICogU2NhbnMgYSBtYXJrZG93biBmaWxlIGZvciBMb2NhbGl6ZWRMaW5rIGNvbXBvbmVudHNcbiAgICovXG4gIGFzeW5jIHNjYW5GaWxlKGZpbGVQYXRoLCBsYW5nKSB7XG4gICAgY29uc3QgY29udGVudCA9IGZzLnJlYWRGaWxlU3luYyhmaWxlUGF0aCwgJ3V0ZjgnKTtcbiAgICBjb25zdCBsb2NhbGl6ZWRMaW5rUmVnZXggPSAvPExvY2FsaXplZExpbmtcXHMraHJlZj1cIihbXlwiXSspXCIvZztcbiAgICBcbiAgICBsZXQgbWF0Y2g7XG4gICAgd2hpbGUgKChtYXRjaCA9IGxvY2FsaXplZExpbmtSZWdleC5leGVjKGNvbnRlbnQpKSAhPT0gbnVsbCkge1xuICAgICAgY29uc3QgaHJlZiA9IG1hdGNoWzFdO1xuICAgICAgXG4gICAgICBpZiAoIXRoaXMubGlua1JlZ2lzdHJ5LmhhcyhocmVmKSkge1xuICAgICAgICB0aGlzLmxpbmtSZWdpc3RyeS5zZXQoaHJlZiwgW10pO1xuICAgICAgfVxuICAgICAgXG4gICAgICB0aGlzLmxpbmtSZWdpc3RyeS5nZXQoaHJlZikucHVzaCh7XG4gICAgICAgIGZpbGU6IGZpbGVQYXRoLFxuICAgICAgICBsYW5nOiBsYW5nXG4gICAgICB9KTtcbiAgICB9XG4gIH1cblxuICAvKipcbiAgICogVmFsaWRhdGVzIGFsbCBjb2xsZWN0ZWQgbGlua3NcbiAgICovXG4gIGFzeW5jIHZhbGlkYXRlTGlua3MoKSB7XG4gICAgY29uc29sZS5sb2coJ1x1MjcwNSBWYWxpZGF0aW5nIExvY2FsaXplZExpbmsgaHJlZiB2YWx1ZXMuLi4nKTtcbiAgICBcbiAgICBmb3IgKGNvbnN0IFtocmVmLCBvY2N1cnJlbmNlc10gb2YgdGhpcy5saW5rUmVnaXN0cnkpIHtcbiAgICAgIGNvbnN0IGlzVmFsaWQgPSBhd2FpdCB0aGlzLnZhbGlkYXRlTGluayhocmVmKTtcbiAgICAgIFxuICAgICAgaWYgKCFpc1ZhbGlkKSB7XG4gICAgICAgIHRoaXMuYnJva2VuTGlua3MucHVzaCh7XG4gICAgICAgICAgaHJlZixcbiAgICAgICAgICBvY2N1cnJlbmNlc1xuICAgICAgICB9KTtcbiAgICAgIH1cbiAgICB9XG4gICAgXG4gICAgaWYgKHRoaXMuYnJva2VuTGlua3MubGVuZ3RoID4gMCkge1xuICAgICAgY29uc29sZS5lcnJvcihgXHUyNzRDIEZvdW5kICR7dGhpcy5icm9rZW5MaW5rcy5sZW5ndGh9IGJyb2tlbiBMb2NhbGl6ZWRMaW5rIHJlZmVyZW5jZXM6YCk7XG4gICAgICBcbiAgICAgIGZvciAoY29uc3QgeyBocmVmLCBvY2N1cnJlbmNlcyB9IG9mIHRoaXMuYnJva2VuTGlua3MpIHtcbiAgICAgICAgY29uc29sZS5lcnJvcihgXFxuXHVEODNEXHVERDE3IEJyb2tlbiBsaW5rOiAke2hyZWZ9YCk7XG4gICAgICAgIGNvbnNvbGUuZXJyb3IoYCAgIFVzZWQgaW4gJHtvY2N1cnJlbmNlcy5sZW5ndGh9IGZpbGUocyk6YCk7XG4gICAgICAgIFxuICAgICAgICBmb3IgKGNvbnN0IHsgZmlsZSwgbGFuZyB9IG9mIG9jY3VycmVuY2VzKSB7XG4gICAgICAgICAgY29uc3QgcmVsYXRpdmVQYXRoID0gcGF0aC5yZWxhdGl2ZSh0aGlzLnNyY0RpciwgZmlsZSk7XG4gICAgICAgICAgY29uc29sZS5lcnJvcihgICAgLSBbJHtsYW5nfV0gJHtyZWxhdGl2ZVBhdGh9YCk7XG4gICAgICAgIH1cbiAgICAgICAgXG4gICAgICAgIC8vIFN1Z2dlc3QgY29ycmVjdGlvbnNcbiAgICAgICAgY29uc3Qgc3VnZ2VzdGlvbiA9IHRoaXMuc3VnZ2VzdENvcnJlY3Rpb24oaHJlZik7XG4gICAgICAgIGlmIChzdWdnZXN0aW9uKSB7XG4gICAgICAgICAgY29uc29sZS5lcnJvcihgICAgXHVEODNEXHVEQ0ExIFN1Z2dlc3RlZCBmaXg6ICR7c3VnZ2VzdGlvbn1gKTtcbiAgICAgICAgfVxuICAgICAgfVxuICAgICAgXG4gICAgICB0aHJvdyBuZXcgRXJyb3IoYEJ1aWxkIGZhaWxlZDogJHt0aGlzLmJyb2tlbkxpbmtzLmxlbmd0aH0gYnJva2VuIExvY2FsaXplZExpbmsgcmVmZXJlbmNlcyBmb3VuZGApO1xuICAgIH0gZWxzZSB7XG4gICAgICBjb25zb2xlLmxvZygnXHUyNzA1IEFsbCBMb2NhbGl6ZWRMaW5rIHJlZmVyZW5jZXMgYXJlIHZhbGlkIScpO1xuICAgIH1cbiAgfVxuXG4gIC8qKlxuICAgKiBWYWxpZGF0ZXMgYSBzaW5nbGUgbGluayBocmVmXG4gICAqL1xuICBhc3luYyB2YWxpZGF0ZUxpbmsoaHJlZikge1xuICAgIGlmICh0aGlzLnZhbGlkYXRlZExpbmtzLmhhcyhocmVmKSkge1xuICAgICAgcmV0dXJuIHRydWU7XG4gICAgfVxuXG4gICAgLy8gUmVtb3ZlIGFuY2hvciBpZiBwcmVzZW50XG4gICAgY29uc3QgW3BhdGhQYXJ0XSA9IGhyZWYuc3BsaXQoJyMnKTtcbiAgICBcbiAgICAvLyBTcGVjaWFsIGhhbmRsaW5nIGZvciBkeW5hbWljIHJvdXRlc1xuICAgIGlmICh0aGlzLmlzRHluYW1pY1JvdXRlKHBhdGhQYXJ0KSkge1xuICAgICAgcmV0dXJuIHRoaXMudmFsaWRhdGVEeW5hbWljUm91dGUocGF0aFBhcnQpO1xuICAgIH1cbiAgICBcbiAgICAvLyBDaGVjayBpZiBmaWxlIGV4aXN0cyBpbiBhbnkgbGFuZ3VhZ2VcbiAgICBmb3IgKGNvbnN0IGxhbmcgb2YgU1VQUE9SVEVEX0xBTkdVQUdFUykge1xuICAgICAgY29uc3QgZnVsbFBhdGggPSBwYXRoLmpvaW4odGhpcy5zcmNEaXIsIGxhbmcsIHBhdGhQYXJ0KTtcbiAgICAgIGNvbnN0IG1kUGF0aCA9IGZ1bGxQYXRoLmVuZHNXaXRoKCcubWQnKSA/IGZ1bGxQYXRoIDogYCR7ZnVsbFBhdGh9Lm1kYDtcbiAgICAgIFxuICAgICAgaWYgKGZzLmV4aXN0c1N5bmMobWRQYXRoKSkge1xuICAgICAgICB0aGlzLnZhbGlkYXRlZExpbmtzLmFkZChocmVmKTtcbiAgICAgICAgcmV0dXJuIHRydWU7XG4gICAgICB9XG4gICAgICBcbiAgICAgIC8vIEFsc28gY2hlY2sgZm9yIGluZGV4Lm1kIGluIGRpcmVjdG9yeVxuICAgICAgY29uc3QgaW5kZXhQYXRoID0gcGF0aC5qb2luKGZ1bGxQYXRoLCAnaW5kZXgubWQnKTtcbiAgICAgIGlmIChmcy5leGlzdHNTeW5jKGluZGV4UGF0aCkpIHtcbiAgICAgICAgdGhpcy52YWxpZGF0ZWRMaW5rcy5hZGQoaHJlZik7XG4gICAgICAgIHJldHVybiB0cnVlO1xuICAgICAgfVxuICAgIH1cbiAgICBcbiAgICByZXR1cm4gZmFsc2U7XG4gIH1cblxuICAvKipcbiAgICogQ2hlY2tzIGlmIGEgcGF0aCBpcyBhIGR5bmFtaWMgcm91dGVcbiAgICovXG4gIGlzRHluYW1pY1JvdXRlKHBhdGhQYXJ0KSB7XG4gICAgcmV0dXJuIHBhdGhQYXJ0LmluY2x1ZGVzKCdbJykgJiYgcGF0aFBhcnQuaW5jbHVkZXMoJ10nKTtcbiAgfVxuXG4gIC8qKlxuICAgKiBWYWxpZGF0ZXMgZHluYW1pYyByb3V0ZXMgYnkgY2hlY2tpbmcgaWYgdGhlIHBhdHRlcm4gZXhpc3RzXG4gICAqL1xuICB2YWxpZGF0ZUR5bmFtaWNSb3V0ZShwYXRoUGFydCkge1xuICAgIC8vIEZvciBub3csIGFzc3VtZSBkeW5hbWljIHJvdXRlcyBhcmUgdmFsaWQgaWYgdGhlIHBhdHRlcm4gZXhpc3RzXG4gICAgLy8gVGhpcyBjb3VsZCBiZSBlbmhhbmNlZCB0byBjaGVjayB0aGUgYWN0dWFsIGR5bmFtaWMgZGF0YVxuICAgIGNvbnN0IGR5bmFtaWNQYXR0ZXJuID0gcGF0aFBhcnQucmVwbGFjZSgvXFxbLio/XFxdL2csICdbKl0nKTtcbiAgICBcbiAgICBmb3IgKGNvbnN0IGxhbmcgb2YgU1VQUE9SVEVEX0xBTkdVQUdFUykge1xuICAgICAgY29uc3QgbGFuZ0RpciA9IHBhdGguam9pbih0aGlzLnNyY0RpciwgbGFuZyk7XG4gICAgICBpZiAodGhpcy5maW5kRHluYW1pY1BhdHRlcm4obGFuZ0RpciwgcGF0aFBhcnQpKSB7XG4gICAgICAgIHJldHVybiB0cnVlO1xuICAgICAgfVxuICAgIH1cbiAgICBcbiAgICByZXR1cm4gZmFsc2U7XG4gIH1cblxuICAvKipcbiAgICogUmVjdXJzaXZlbHkgc2VhcmNoZXMgZm9yIGR5bmFtaWMgcm91dGUgcGF0dGVybnNcbiAgICovXG4gIGZpbmREeW5hbWljUGF0dGVybihkaXIsIHBhdHRlcm4pIHtcbiAgICBpZiAoIWZzLmV4aXN0c1N5bmMoZGlyKSkgcmV0dXJuIGZhbHNlO1xuICAgIFxuICAgIGNvbnN0IHBhcnRzID0gcGF0dGVybi5zcGxpdCgnLycpLmZpbHRlcihCb29sZWFuKTtcbiAgICBsZXQgY3VycmVudERpciA9IGRpcjtcbiAgICBcbiAgICBmb3IgKGNvbnN0IHBhcnQgb2YgcGFydHMpIHtcbiAgICAgIGlmIChwYXJ0LnN0YXJ0c1dpdGgoJ1snKSAmJiBwYXJ0LmVuZHNXaXRoKCddJykpIHtcbiAgICAgICAgLy8gRmluZCBhbnkgZmlsZS9kaXJlY3Rvcnkgd2l0aCBzcXVhcmUgYnJhY2tldHNcbiAgICAgICAgY29uc3QgZW50cmllcyA9IGZzLnJlYWRkaXJTeW5jKGN1cnJlbnREaXIsIHsgd2l0aEZpbGVUeXBlczogdHJ1ZSB9KTtcbiAgICAgICAgY29uc3QgZm91bmQgPSBlbnRyaWVzLmZpbmQoZW50cnkgPT4gXG4gICAgICAgICAgZW50cnkubmFtZS5zdGFydHNXaXRoKCdbJykgJiYgZW50cnkubmFtZS5pbmNsdWRlcygnXScpXG4gICAgICAgICk7XG4gICAgICAgIFxuICAgICAgICBpZiAoIWZvdW5kKSByZXR1cm4gZmFsc2U7XG4gICAgICAgIGN1cnJlbnREaXIgPSBwYXRoLmpvaW4oY3VycmVudERpciwgZm91bmQubmFtZSk7XG4gICAgICB9IGVsc2Uge1xuICAgICAgICBjdXJyZW50RGlyID0gcGF0aC5qb2luKGN1cnJlbnREaXIsIHBhcnQpO1xuICAgICAgICBpZiAoIWZzLmV4aXN0c1N5bmMoY3VycmVudERpcikpIHJldHVybiBmYWxzZTtcbiAgICAgIH1cbiAgICB9XG4gICAgXG4gICAgcmV0dXJuIHRydWU7XG4gIH1cblxuICAvKipcbiAgICogU3VnZ2VzdHMgY29ycmVjdGlvbnMgZm9yIGJyb2tlbiBsaW5rc1xuICAgKi9cbiAgc3VnZ2VzdENvcnJlY3Rpb24oaHJlZikge1xuICAgIGNvbnN0IGNvcnJlY3Rpb25zID0gbmV3IE1hcChbXG4gICAgICBbJy9zZXJ2ZXIvaW50cm9kdWN0aW9uL2FjY291bnRzLWFuZC1wcm9qZWN0cycsICcvZ3VpZGVzL3NlcnZlci9hY2NvdW50cy1hbmQtcHJvamVjdHMnXSxcbiAgICAgIFsnL3NlcnZlci9pbnRyb2R1Y3Rpb24vaW50ZWdyYXRpb25zI2dpdC1wbGF0Zm9ybXMnLCAnL2d1aWRlcy9zZXJ2ZXIvYXV0aGVudGljYXRpb24nXSxcbiAgICAgIFsnL3NlcnZlci9pbnRyb2R1Y3Rpb24vd2h5LWEtc2VydmVyJywgJy9ndWlkZXMvdHVpc3QvYWJvdXQnXSxcbiAgICAgIFsnL2d1aWRlcy9hdXRvbWF0ZS9jb250aW51b3VzLWludGVncmF0aW9uJywgJy9ndWlkZXMvaW50ZWdyYXRpb25zL2NvbnRpbnVvdXMtaW50ZWdyYXRpb24nXSxcbiAgICAgIFsnL2d1aWRlcy9mZWF0dXJlcy9hdXRvbWF0ZS9jb250aW51b3VzLWludGVncmF0aW9uJywgJy9ndWlkZXMvaW50ZWdyYXRpb25zL2NvbnRpbnVvdXMtaW50ZWdyYXRpb24nXSxcbiAgICAgIFsnL2d1aWRlcy9mZWF0dXJlcy9idWlsZC9jYWNoZScsICcvZ3VpZGVzL2ZlYXR1cmVzL2NhY2hlJ10sXG4gICAgICBbJy9ndWlkZXMvZmVhdHVyZXMvY2FjaGUuaHRtbCNzdXBwb3J0ZWQtcHJvZHVjdHMnLCAnL2d1aWRlcy9mZWF0dXJlcy9jYWNoZSNzdXBwb3J0ZWQtcHJvZHVjdHMnXSxcbiAgICAgIFsnL2d1aWRlcy9mZWF0dXJlcy9pbnNwZWN0L2ltcGxpY2l0LWRlcGVuZGVuY2llcycsICcvZ3VpZGVzL2ZlYXR1cmVzL3Byb2plY3RzL2luc3BlY3QvaW1wbGljaXQtZGVwZW5kZW5jaWVzJ10sXG4gICAgICBbJy9ndWlkZXMvc3RhcnQvbmV3LXByb2plY3QnLCAnL2d1aWRlcy9mZWF0dXJlcy9wcm9qZWN0cy9hZG9wdGlvbi9uZXctcHJvamVjdCddLFxuICAgICAgWycvZ3VpZGVzL2ZlYXR1cmVzL3Rlc3QnLCAnL2d1aWRlcy9mZWF0dXJlcy9zZWxlY3RpdmUtdGVzdGluZyddLFxuICAgICAgWycvZ3VpZGVzL2ZlYXR1cmVzL3Rlc3Qvc2VsZWN0aXZlLXRlc3RpbmcnLCAnL2d1aWRlcy9mZWF0dXJlcy9zZWxlY3RpdmUtdGVzdGluZyddLFxuICAgICAgWycvZ3VpZGVzL2ZlYXR1cmVzL3NlbGVjdGl2ZS10ZXN0aW5nL3hjb2RlYnVpbGQnLCAnL2d1aWRlcy9mZWF0dXJlcy9zZWxlY3RpdmUtdGVzdGluZy94Y29kZS1wcm9qZWN0J10sXG4gICAgICBbJy9jb250cmlidXRvcnMvcHJpbmNpcGxlcy5odG1sI2RlZmF1bHQtdG8tY29udmVudGlvbnMnLCAnL2NvbnRyaWJ1dG9ycy9wcmluY2lwbGVzI2RlZmF1bHQtdG8tY29udmVudGlvbnMnXVxuICAgIF0pO1xuICAgIFxuICAgIHJldHVybiBjb3JyZWN0aW9ucy5nZXQoaHJlZikgfHwgbnVsbDtcbiAgfVxufVxuXG4vKipcbiAqIFZpdGVQcmVzcyBwbHVnaW4gdG8gdmFsaWRhdGUgTG9jYWxpemVkTGluayBjb21wb25lbnRzXG4gKi9cbmV4cG9ydCBmdW5jdGlvbiBsb2NhbGl6ZWRMaW5rVmFsaWRhdG9yUGx1Z2luKCkge1xuICByZXR1cm4ge1xuICAgIG5hbWU6ICdsb2NhbGl6ZWQtbGluay12YWxpZGF0b3InLFxuICAgIGFzeW5jIGJ1aWxkU3RhcnQoKSB7XG4gICAgICAvLyBXZSdsbCBydW4gdmFsaWRhdGlvbiBkdXJpbmcgYnVpbGRFbmQgaW5zdGVhZFxuICAgIH0sXG4gICAgYXN5bmMgYnVpbGRFbmQoeyBvdXREaXIgfSkge1xuICAgICAgY29uc3Qgc3JjRGlyID0gcGF0aC5qb2luKHBhdGguZGlybmFtZShvdXREaXIpLCAnZG9jcycpO1xuICAgICAgY29uc3QgdmFsaWRhdG9yID0gbmV3IExvY2FsaXplZExpbmtWYWxpZGF0b3Ioc3JjRGlyKTtcbiAgICAgIFxuICAgICAgYXdhaXQgdmFsaWRhdG9yLnNjYW5GaWxlcygpO1xuICAgICAgYXdhaXQgdmFsaWRhdG9yLnZhbGlkYXRlTGlua3MoKTtcbiAgICB9XG4gIH07XG59Il0sCiAgIm1hcHBpbmdzIjogIjtBQUF3VixTQUFTLG9CQUFvQjtBQUNyWCxZQUFZQSxXQUFVO0FBQ3RCLFlBQVlDLFNBQVE7OztBQ21HYixTQUFTLGVBQWUsT0FBTyxJQUFJO0FBQ3hDLFNBQU8sZUFBZSxJQUFJLGFBQWEsSUFBSTtBQUFBO0FBQUE7QUFBQTtBQUk3QztBQUVPLFNBQVMsZ0JBQWdCLE9BQU8sSUFBSTtBQUN6QyxTQUFPLGVBQWUsSUFBSSxhQUFhLElBQUk7QUFBQTtBQUFBO0FBQUE7QUFJN0M7QUFHTyxTQUFTLFlBQVk7QUFDMUIsU0FBTztBQUNUO0FBR08sU0FBUyxXQUFXO0FBQ3pCLFNBQU87QUFD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LHFDQUFxQztBQUFBLE1BQzlEO0FBQUEsUUFDRSxNQUFNO0FBQUEsUUFDTixNQUFNO0FBQUEsTUFDUjtBQUFBLElBQ0Y7QUFBQSxJQUNBLFFBQVE7QUFBQSxNQUNOLFNBQVM7QUFBQSxNQUNULFdBQVc7QUFBQSxJQUNiO0FBQUEsRUFDRjtBQUNGLENBQUM7IiwKICAibmFtZXMiOiBbInBhdGgiLCAiZnMiLCAicGF0aCIsICJmZyIsICJmcyIsICJfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSIsICJsb2FkRGF0YSIsICJfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSIsICJmZyIsICJmcyIsICJrZXkiLCAibG9hZERhdGEiLCAicHJvamVjdERlc2NyaXB0aW9uU2lkZWJhciIsICJwYXRoIiwgImxvYWREYXRhIiwgImZzIiwgInBhdGgiLCAiX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUiLCAiX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUiLCAiJCJdCn0K
