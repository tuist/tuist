export const site = {
  description:
    "Once makes project automation cacheable, observable, and remotely executable.",
  nav: [
    { text: "Docs", link: "/" },
    {
      text: "Links",
      items: [
        {
          text: "Releases",
          link: "https://github.com/tuist/tuist/releases?q=once%40&expanded=true",
        },
        {
          text: "Issues",
          link: "https://github.com/tuist/tuist/issues?q=is%3Aissue+is%3Aopen+label%3Aonce",
        },
      ],
    },
  ],
  sidebar: {
    "/": [
      { text: "Why", link: "/guide/why" },
      {
        text: "Scripts",
        collapsed: false,
        items: [
          { text: "Overview", link: "/guide/scripts/" },
          { text: "Caching", link: "/guide/scripts/caching" },
          { text: "Runtime", link: "/guide/scripts/runtime" },
        ],
      },
    ],
  },
  footer: {
    message: "Released under the MIT License.",
    copyright: "Copyright © Tuist GmbH",
  },
};
