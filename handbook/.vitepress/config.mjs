import { defineConfig } from "vitepress";
import {
  atom01Icon,
  codeBrowserIcon,
  heartIcon,
  target04Icon,
  cubeOutlineIcon,
  lifeBuoy02Icon,
  faceIdIcon,
  intersectCircleIcon,
} from "./icons.mjs";
import * as path from "node:path";
import * as fs from "node:fs/promises";
import llmstxtPlugin from "vitepress-plugin-llmstxt";

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: "Tuist Handbook",
  titleTemplate: ":title | Tuist Handbook",
  description: "Tuist company handbook",
  srcDir: "./handbook",
  cleanUrls: true,
  vite: {
    plugins: [llmstxtPlugin()],
  },
  sitemap: {
    hostname: "https://handbook.tuist.io",
  },
  async buildEnd({ outDir }) {
    // Copy functions directory to dist
    const functionsSource = path.join(path.dirname(outDir), "functions");
    const functionsDest = path.join(outDir, "functions");
    await fs.cp(functionsSource, functionsDest, { recursive: true });

    const redirectsPath = path.join(outDir, "_redirects");
    const redirects = `
/security/information-security-policy /security/information-security-framework/information-security-policy 301
/security/information-security-roles-and-responsibilities /security/information-security-framework/information-security-roles-and-responsibilities 301
/security/access-control-policy /security/access-and-risk-management/access-control-policy 301
/security/risk-management-policy /security/access-and-risk-management/risk-management-policy 301
/security/third-party-risk-management-policy /security/access-and-risk-management/third-party-risk-management-policy 301
/security/human-resource-security-policy /security/human-and-incident-management/human-resource-security-policy 301
/security/incident-response-management /security/human-and-incident-management/incident-response-management 301
/security/secure-development-policy /security/secure-development-and-operations/secure-development-policy 301
/security/penetration-testing-policy /security/secure-development-and-operations/penetration-testing-policy 301
/security/vulnerability-scanning-policy /security/secure-development-and-operations/vulnerability-scanning-policy 301
/pdfs/operations-security-policy-bsi.pdf /pdfs/security/secure-development-and-operations/operations-security-policy-bsi.pdf 301
/security/physical-security-policy /security/physical-and-asset-security/physical-security-policy 301
/security/asset-management-policy /security/physical-and-asset-security/asset-management-policy 301
/security/business-continuity-and-disaster-recovery-plan /security/business-continuity-and-data-protection/business-continuity-and-disaster-recovery-plan 301
/security/cryptography-policy /security/business-continuity-and-data-protection/cryptography-policy 301
/security/network-traffic-management-policy /security/business-continuity-and-data-protection/network-traffic-management-policy 301
/pdfs/security/data-management-policy-bsi.pdf /pdfs/security/business-continuity-and-data-protection/data-management-policy-bsi.pdf 301
      `;
    fs.writeFile(redirectsPath, redirects);
  },
  head: [
    [
      "script",
      {},
      `
      (function(d, script) {
        script = d.createElement('script');
        script.async = false;
        script.onload = function(){
          Plain.init({
            appId: 'liveChatApp_01JSH4NJ6DQ2P66NQ798EW1ZXZ',
          });
        };
        script.src = 'https://chat.cdn-plain.com/index.js';
        d.getElementsByTagName('head')[0].appendChild(script);
      }(document));
    `,
    ],
  ],
  themeConfig: {
    editLink: {
      pattern: "https://github.com/tuist/handbook/edit/main/handbook/:path",
    },
    logo: "/logo.png",
    search: {
      provider: "local",
    },
    nav: [{ text: "Home", link: "/" }],

    sidebar: [
      {
        text: `<div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Company ${atom01Icon()}</div>`,
        collapsed: true,
        items: [
          { text: "Handbook", link: "/" },
          { text: "Mission", link: "/company/mission" },
          { text: "Vision", link: "/company/vision" },
          { text: "Principles", link: "/company/principles" },
          { text: "Services and tools", link: "/company/services-and-tools" },
          { text: "Leadership", link: "/company/leadership" },
          { text: "6-week cycles", link: "/company/6-week-cycles" },
        ],
      },
      {
        text: `<div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Product ${cubeOutlineIcon()}</div>`,
        collapsed: true,
        items: [{ text: "Needs pool", link: "/product/needs-pool" }],
      },
      {
        text: `<div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Engineering ${codeBrowserIcon()}</div>`,
        collapsed: true,
        items: [
          { text: "Technologies", link: "/engineering/technologies" },
          { text: "Open Source", link: "/engineering/open-source" },
          { text: "Standards", link: "/engineering/standards" },
          {
            text: "Standard practices",
            link: "/engineering/standard-practices",
          },
          {
            text: "Scheduled maintenance",
            link: "/engineering/scheduled-maintenance",
          },
          {
            text: "Server",
            items: [
              {
                text: "Error handling",
                link: "/engineering/server/error-handling",
              },
            ],
          },
        ],
      },
      {
        text: `<div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Community ${intersectCircleIcon()}</div>`,
        collapsed: true,
        items: [
          {
            text: "Tuist Digest Newsletter",
            link: "/community/tuist-digest",
          },
        ],
      },
      {
        text: `<div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Support ${lifeBuoy02Icon()}</div>`,
        collapsed: true,
        items: [{ text: "Process", link: "/support/process" }],
      },
      {
        text: `<div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">People ${heartIcon()}</div>`,
        collapsed: true,
        items: [
          { text: "Values", link: "/people/values" },
          { text: "How we work", link: "/people/how-we-work" },
          { text: "Code of conduct", link: "/people/code-of-conduct" },
          { text: "Benefits", link: "/people/benefits" },
        ],
      },
      {
        text: `<div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Marketing ${target04Icon()}</div>`,
        collapsed: true,
        items: [
          { text: "Guidelines", link: "/marketing/guidelines" },
          { text: "Case Studies", link: "/marketing/case-studies" },
        ],
      },
      {
        text: `<div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Security ${faceIdIcon()}</div>`,
        collapsed: true,
        items: [
          {
            text: "Shared responsibility model",
            link: "/security/shared-responsibility-model",
          },
          {
            text: "Employee termination security policy",
            link: "/security/employee-termination-security-policy",
          },
          {
            text: "Information security framework",
            collapsed: true,
            items: [
              {
                text: "Information Security Policy (AUP)",
                link: "/security/information-security-framework/information-security-policy",
              },
              {
                text: "Information Security Roles and Responsibilities",
                link: "/security/information-security-framework/information-security-roles-and-responsibilities",
              },
            ],
          },
          {
            text: "Access and risk management",
            collapsed: true,
            items: [
              {
                text: "Access control policy",
                link: "/security/access-and-risk-management/access-control-policy",
              },
              {
                text: "Risk management policy",
                link: "/security/access-and-risk-management/risk-management-policy",
              },
              {
                text: "Third-party risk management policy",
                link: "/security/access-and-risk-management/third-party-risk-management-policy",
              },
            ],
          },
          {
            text: "Human and incident management",
            collapsed: true,
            items: [
              {
                text: "Human resource security policy",
                link: "/security/human-and-incident-management/human-resource-security-policy",
              },
              {
                text: "Incident response management",
                link: "/security/human-and-incident-management/incident-response-management",
              },
            ],
          },
          {
            text: "Secure development and operations",
            collapsed: true,
            items: [
              {
                text: "Secure development policy",
                link: "/security/secure-development-and-operations/secure-development-policy",
              },
              {
                text: "Penetration testing policy",
                link: "/security/secure-development-and-operations/penetration-testing-policy",
              },
              {
                text: "Vulnerability scanning policy",
                link: "/security/secure-development-and-operations/vulnerability-scanning-policy",
              },
              {
                text: "Operations security policy",
                link: "/pdfs/security/secure-development-and-operations/operations-security-policy-bsi.pdf",
              },
            ],
          },
          {
            text: "Physical and asset security",
            collapsed: true,
            items: [
              {
                text: "Physical security policy",
                link: "/security/physical-and-asset-security/physical-security-policy",
              },
              {
                text: "Asset management policy",
                link: "/security/physical-and-asset-security/asset-management-policy",
              },
            ],
          },
          {
            text: "Business continuity and data protection",
            collapsed: true,
            items: [
              {
                text: "Data-loss prevention",
                link: "/security/business-continuity-and-data-protection/data-loss-prevention",
              },
              {
                text: "Business continuity and disaster recovery plan",
                link: "/security/business-continuity-and-data-protection/business-continuity-and-disaster-recovery-plan",
              },
              {
                text: "Cryptography policy",
                link: "/security/business-continuity-and-data-protection/cryptography-policy",
              },
              {
                text: "Network traffic management policy",
                link: "/security/business-continuity-and-data-protection/network-traffic-management-policy",
              },
              {
                text: "Data management policy",
                link: "/pdfs/security/business-continuity-and-data-protection/data-management-policy-bsi.pdf",
              },
            ],
          },
        ],
      },
    ],

    socialLinks: [
      { icon: "github", link: "https://github.com/tuist" },
      {
        icon: "slack",
        link: "https://join.slack.com/t/tuistapp/shared_invite/zt-1y667mjbk-s2LTRX1YByb9EIITjdLcLw",
      },
      {
        icon: "bluesky",
        link: "https://bsky.app/profile/tuist.dev",
      },
      { icon: "mastodon", link: "https://fosstodon.org/@tuist" },
    ],
  },
});
