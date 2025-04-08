const config = {
  baseSettings: {
    apiKey: "a69a199522db7a7376521080120f3633468e87babbbc12e4",
    primaryBrandColor: "#6F2CFF",
    organizationDisplayName: "Tuist",
    // ...optional settings
    colorMode: {
      sync: {
        target: document.documentElement,
        attributes: ["class"],
        isDarkMode: (attributes) => !!attributes.class?.includes("dark"),
      },
    },
    theme: {},
  },
  modalSettings: {
    // optional settings
  },
  searchSettings: {
    // optional settings
  },
  label: "Ask Tulsie",
  aiChatSettings: {
    aiAssistantName: "Tulsie",
    aiAssistantAvatar: "/logo.png",
    exampleQuestions: [
      "How can I optimize my builds and tests?",
      "What are generated projects and why are they needed?",
      "How can speed up the resolution of Swift Packages?",
    ],
  },
};

Inkeep.SearchBar(".search", config);
Inkeep.ChatButton(config);
