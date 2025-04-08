const config = {
  baseSettings: {
    apiKey: "119749d76db96b0520e88487e4bf115d215599e0fd84c8c8", // required
    primaryBrandColor: "6F2CFF",
    organizationDisplayName: "Tuist",
  },
  modalSettings: {},
  searchSettings: {},
  label: "Ask Tulsie",
  aiChatSettings: {
    aiAssistantName: "Tulsie",
    aiAssistantAvatar: "/images/tuist_dashboard.png",
    exampleQuestions: [
      "How can I optimize my builds and tests?",
      "What are generated projects and why are they needed?",
      "How can I speed up the resolution of Swift Packages?",
    ],
  },
};

export function setupInkeepChatButton() {
  if (typeof window !== "undefined" && typeof window.Inkeep !== "undefined") {
    window.Inkeep.ChatButton(config);
  }
}
