// .vitepress/config.mjs
import { defineConfig } from "file:///Users/pepicrft/src/github.com/tuist/tuist/docs/node_modules/.pnpm/vitepress@1.3.4_@algolia+client-search@4.24.0_search-insights@2.15.0/node_modules/vitepress/dist/node/index.js";
import * as path4 from "node:path";
import * as fs3 from "node:fs/promises";

// .vitepress/badges.mjs
function comingSoonBadge() {
  return `<span style="background: var(--vp-custom-block-tip-code-bg); color: var(--vp-c-tip-1); font-size: 11px; display: inline-block; padding-left: 5px; padding-right: 5px; border-radius: 10%;">Coming soon</span>`;
}
function xcodeProjCompatibleBadge() {
  return `<span style="background: var(--vp-badge-warning-bg); color: var(--vp-badge-warning-text); font-size: 11px; display: inline-block; padding-left: 5px; padding-right: 5px; border-radius: 10%;">XcodeProj Compatible</span>`;
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
function code02Icon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M17 17L22 12L17 7M7 7L2 12L7 17M14 3L10 21" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
`;
}
function dataIcon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M21.2 22C21.48 22 21.62 22 21.727 21.9455C21.8211 21.8976 21.8976 21.8211 21.9455 21.727C22 21.62 22 21.48 22 21.2V10.8C22 10.52 22 10.38 21.9455 10.273C21.8976 10.1789 21.8211 10.1024 21.727 10.0545C21.62 10 21.48 10 21.2 10L18.8 10C18.52 10 18.38 10 18.273 10.0545C18.1789 10.1024 18.1024 10.1789 18.0545 10.273C18 10.38 18 10.52 18 10.8V13.2C18 13.48 18 13.62 17.9455 13.727C17.8976 13.8211 17.8211 13.8976 17.727 13.9455C17.62 14 17.48 14 17.2 14H14.8C14.52 14 14.38 14 14.273 14.0545C14.1789 14.1024 14.1024 14.1789 14.0545 14.273C14 14.38 14 14.52 14 14.8V17.2C14 17.48 14 17.62 13.9455 17.727C13.8976 17.8211 13.8211 17.8976 13.727 17.9455C13.62 18 13.48 18 13.2 18H10.8C10.52 18 10.38 18 10.273 18.0545C10.1789 18.1024 10.1024 18.1789 10.0545 18.273C10 18.38 10 18.52 10 18.8V21.2C10 21.48 10 21.62 10.0545 21.727C10.1024 21.8211 10.1789 21.8976 10.273 21.9455C10.38 22 10.52 22 10.8 22L21.2 22Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M10 6.8C10 6.51997 10 6.37996 10.0545 6.273C10.1024 6.17892 10.1789 6.10243 10.273 6.0545C10.38 6 10.52 6 10.8 6H13.2C13.48 6 13.62 6 13.727 6.0545C13.8211 6.10243 13.8976 6.17892 13.9455 6.273C14 6.37996 14 6.51997 14 6.8V9.2C14 9.48003 14 9.62004 13.9455 9.727C13.8976 9.82108 13.8211 9.89757 13.727 9.9455C13.62 10 13.48 10 13.2 10H10.8C10.52 10 10.38 10 10.273 9.9455C10.1789 9.89757 10.1024 9.82108 10.0545 9.727C10 9.62004 10 9.48003 10 9.2V6.8Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M3 12.8C3 12.52 3 12.38 3.0545 12.273C3.10243 12.1789 3.17892 12.1024 3.273 12.0545C3.37996 12 3.51997 12 3.8 12H6.2C6.48003 12 6.62004 12 6.727 12.0545C6.82108 12.1024 6.89757 12.1789 6.9455 12.273C7 12.38 7 12.52 7 12.8V15.2C7 15.48 7 15.62 6.9455 15.727C6.89757 15.8211 6.82108 15.8976 6.727 15.9455C6.62004 16 6.48003 16 6.2 16H3.8C3.51997 16 3.37996 16 3.273 15.9455C3.17892 15.8976 3.10243 15.8211 3.0545 15.727C3 15.62 3 15.48 3 15.2V12.8Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M2 2.8C2 2.51997 2 2.37996 2.0545 2.273C2.10243 2.17892 2.17892 2.10243 2.273 2.0545C2.37996 2 2.51997 2 2.8 2H5.2C5.48003 2 5.62004 2 5.727 2.0545C5.82108 2.10243 5.89757 2.17892 5.9455 2.273C6 2.37996 6 2.51997 6 2.8V5.2C6 5.48003 6 5.62004 5.9455 5.727C5.89757 5.82108 5.82108 5.89757 5.727 5.9455C5.62004 6 5.48003 6 5.2 6H2.8C2.51997 6 2.37996 6 2.273 5.9455C2.17892 5.89757 2.10243 5.82108 2.0545 5.727C2 5.62004 2 5.48003 2 5.2V2.8Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;
}
function checkCircleIcon(size = 15) {
  return `<svg width="${15}" height="${15}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M7.5 12L10.5 15L16.5 9M22 12C22 17.5228 17.5228 22 12 22C6.47715 22 2 17.5228 2 12C2 6.47715 6.47715 2 12 2C17.5228 2 22 6.47715 22 12Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
`;
}
function tuistIcon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M21 16V7.2C21 6.0799 21 5.51984 20.782 5.09202C20.5903 4.71569 20.2843 4.40973 19.908 4.21799C19.4802 4 18.9201 4 17.8 4H6.2C5.07989 4 4.51984 4 4.09202 4.21799C3.71569 4.40973 3.40973 4.71569 3.21799 5.09202C3 5.51984 3 6.0799 3 7.2V16M4.66667 20H19.3333C19.9533 20 20.2633 20 20.5176 19.9319C21.2078 19.7469 21.7469 19.2078 21.9319 18.5176C22 18.2633 22 17.9533 22 17.3333C22 17.0233 22 16.8683 21.9659 16.7412C21.8735 16.3961 21.6039 16.1265 21.2588 16.0341C21.1317 16 20.9767 16 20.6667 16H3.33333C3.02334 16 2.86835 16 2.74118 16.0341C2.39609 16.1265 2.12654 16.3961 2.03407 16.7412C2 16.8683 2 17.0233 2 17.3333C2 17.9533 2 18.2633 2.06815 18.5176C2.25308 19.2078 2.79218 19.7469 3.48236 19.9319C3.73669 20 4.04669 20 4.66667 20Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;
}
function cloudBlank02Icon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M9.5 19C5.35786 19 2 15.6421 2 11.5C2 7.35786 5.35786 4 9.5 4C12.3827 4 14.8855 5.62634 16.141 8.01153C16.2597 8.00388 16.3794 8 16.5 8C19.5376 8 22 10.4624 22 13.5C22 16.5376 19.5376 19 16.5 19C13.9485 19 12.1224 19 9.5 19Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
`;
}
function server04Icon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M22 10.5L21.5256 6.70463C21.3395 5.21602 21.2465 4.47169 20.8961 3.9108C20.5875 3.41662 20.1416 3.02301 19.613 2.77804C19.013 2.5 18.2629 2.5 16.7626 2.5H7.23735C5.73714 2.5 4.98704 2.5 4.38702 2.77804C3.85838 3.02301 3.4125 3.41662 3.10386 3.9108C2.75354 4.47169 2.6605 5.21601 2.47442 6.70463L2 10.5M5.5 14.5H18.5M5.5 14.5C3.567 14.5 2 12.933 2 11C2 9.067 3.567 7.5 5.5 7.5H18.5C20.433 7.5 22 9.067 22 11C22 12.933 20.433 14.5 18.5 14.5M5.5 14.5C3.567 14.5 2 16.067 2 18C2 19.933 3.567 21.5 5.5 21.5H18.5C20.433 21.5 22 19.933 22 18C22 16.067 20.433 14.5 18.5 14.5M6 11H6.01M6 18H6.01M12 11H18M12 18H18" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
`;
}
function microscopeIcon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M3 22H12M11 6.25204C11.6392 6.08751 12.3094 6 13 6C17.4183 6 21 9.58172 21 14C21 17.3574 18.9318 20.2317 16 21.4185M5.5 13H9.5C9.96466 13 10.197 13 10.3902 13.0384C11.1836 13.1962 11.8038 13.8164 11.9616 14.6098C12 14.803 12 15.0353 12 15.5C12 15.9647 12 16.197 11.9616 16.3902C11.8038 17.1836 11.1836 17.8038 10.3902 17.9616C10.197 18 9.96466 18 9.5 18H5.5C5.03534 18 4.80302 18 4.60982 17.9616C3.81644 17.8038 3.19624 17.1836 3.03843 16.3902C3 16.197 3 15.9647 3 15.5C3 15.0353 3 14.803 3.03843 14.6098C3.19624 13.8164 3.81644 13.1962 4.60982 13.0384C4.80302 13 5.03534 13 5.5 13ZM4 5.5V13H11V5.5C11 3.567 9.433 2 7.5 2C5.567 2 4 3.567 4 5.5Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
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

// .vitepress/sidebars.mjs
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
      text: "Reference",
      items: [
        await projectDescriptionSidebar(locale),
        {
          text: "Examples",
          collapsed: true,
          items: (await loadData()).map((item) => {
            return {
              text: item.title,
              link: `/${locale}/references/examples/${item.name}`
            };
          })
        },
        {
          text: "Migrations",
          collapsed: true,
          items: [
            {
              text: "From v3 to v4",
              link: "/references/migrations/from-v3-to-v4"
            }
          ]
        }
      ]
    }
  ];
}
function contributorsSidebar(locale) {
  return [
    {
      text: "Contributors",
      items: [
        {
          text: "Get started",
          link: `/${locale}/contributors/get-started`
        },
        {
          text: "Issue reporting",
          link: `/${locale}/contributors/issue-reporting`
        },
        {
          text: "Code reviews",
          link: `/${locale}/contributors/code-reviews`
        },
        {
          text: "Principles",
          link: `/${locale}/contributors/principles`
        }
      ]
    }
  ];
}
function serverSidebar(locale) {
  return [
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Introduction ${server04Icon()}</span>`,
      items: [
        {
          text: "Why a server?",
          link: `/${locale}/server/introduction/why-a-server`
        },
        {
          text: "Accounts and projects",
          link: `/${locale}/server/introduction/accounts-and-projects`
        },
        {
          text: "Authentication",
          link: `/${locale}/server/introduction/authentication`
        },
        {
          text: "Integrations",
          link: `/${locale}/server/introduction/integrations`
        }
      ]
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">On-premise ${building07Icon()}</span>`,
      collapsed: true,
      items: [
        {
          text: "Install",
          link: `/${locale}/server/on-premise/install`
        },
        {
          text: "Metrics",
          link: `/${locale}/server/on-premise/metrics`
        }
      ]
    },
    {
      text: "API Documentation",
      link: "https://cloud.tuist.io/api/docs"
    },
    {
      text: "Status",
      link: "https://status.tuist.io"
    },
    {
      text: "Metrics Dashboard",
      link: "https://tuist.grafana.net/public-dashboards/1f85f1c3895e48febd02cc7350ade2d9"
    }
  ];
}
function guidesSidebar(locale) {
  return [
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Quick start ${tuistIcon()}</span>`,
      link: "/",
      items: [
        {
          text: "Install Tuist",
          link: `/${locale}/guides/quick-start/install-tuist`
        },
        {
          text: "Create a project",
          link: `/${locale}/guides/quick-start/create-a-project`
        },
        {
          text: "Add dependencies",
          link: `/${locale}/guides/quick-start/add-dependencies`
        },
        {
          text: "Gather insights",
          link: `/${locale}/guides/quick-start/gather-insights`
        },
        {
          text: "Optimize workflows",
          link: `/${locale}/guides/quick-start/optimize-workflows`
        }
      ]
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Start ${cubeOutlineIcon()}</span>`,
      items: [
        {
          text: "Create a new project",
          link: `/${locale}/guides/start/new-project`
        },
        {
          text: "Try with a Swift Package",
          link: `/${locale}/guides/start/swift-package`
        },
        {
          text: "Migrate",
          collapsed: true,
          items: [
            {
              text: "An Xcode project",
              link: `/${locale}/guides/start/migrate/xcode-project`
            },
            {
              text: "A Swift Package",
              link: `/${locale}/guides/start/migrate/swift-package`
            },
            {
              text: "An XcodeGen project",
              link: `/${locale}/guides/start/migrate/xcodegen-project`
            },
            {
              text: "A Bazel project",
              link: `/${locale}/guides/start/migrate/bazel-project`
            }
          ]
        }
      ]
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Develop ${cube02Icon()}</span>`,
      items: [
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Projects ${code02Icon()}</span>`,
          collapsed: true,
          link: `/${locale}/guides/develop/projects`,
          items: [
            {
              text: "Manifests",
              link: `/${locale}/guides/develop/projects/manifests`
            },
            {
              text: "Directory structure",
              link: `/${locale}/guides/develop/projects/directory-structure`
            },
            {
              text: "Editing",
              link: `/${locale}/guides/develop/projects/editing`
            },
            {
              text: "Dependencies",
              link: `/${locale}/guides/develop/projects/dependencies`
            },
            {
              text: "Code sharing",
              link: `/${locale}/guides/develop/projects/code-sharing`
            },
            {
              text: "Synthesized files",
              link: `/${locale}/guides/develop/projects/synthesized-files`
            },
            {
              text: "Dynamic configuration",
              link: `/${locale}/guides/develop/projects/dynamic-configuration`
            },
            {
              text: "Templates",
              link: `/${locale}/guides/develop/projects/templates`
            },
            {
              text: "Plugins",
              link: `/${locale}/guides/develop/projects/plugins`
            },
            {
              text: "Hashing",
              link: `/${locale}/guides/develop/projects/hashing`
            },
            {
              text: "The cost of convenience",
              link: `/${locale}/guides/develop/projects/cost-of-convenience`
            },
            {
              text: "Modular architecture",
              link: `/${locale}/guides/develop/projects/tma-architecture`
            },
            {
              text: "Best practices",
              link: `/${locale}/guides/develop/projects/best-practices`
            }
          ]
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Build ${dataIcon()}</span>`,
          link: `/${locale}/guides/develop/build`,
          collapsed: true,
          items: [
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Cache</span>`,
              link: `/${locale}/guides/develop/build/cache`
            }
          ]
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Test ${checkCircleIcon()}</span>`,
          link: `/${locale}/guides/develop/test`,
          collapsed: true,
          items: [
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Smart runner</span>`,
              link: `/${locale}/guides/develop/test/smart-runner`
            },
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Flakiness</span>`,
              link: `/${locale}/guides/develop/test/flakiness`
            }
          ]
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Inspect ${microscopeIcon()}</span>`,
          collapsed: true,
          items: [
            {
              text: "Implicit dependencies",
              link: `/${locale}/guides/develop/inspect/implicit-dependencies`
            }
          ]
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Automate ${cloudBlank02Icon()}</span>`,
          collapsed: true,
          items: [
            {
              text: `Continuous Integration`,
              link: `/${locale}/guides/develop/automate/continuous-integration`
            },
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Workflows ${comingSoonBadge()}</span>`,
              link: `/${locale}/guides/develop/automate/workflows`
            }
          ]
        }
      ]
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Share ${cube01Icon()}</span>`,
      items: [
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Previews ${xcodeProjCompatibleBadge()}</span>`,
          link: `/${locale}/guides/share/previews`
        }
      ]
    }
  ];
}

// .vitepress/data/cli.js
import { $ } from "file:///Users/pepicrft/src/github.com/tuist/tuist/docs/node_modules/.pnpm/execa@9.3.1/node_modules/execa/index.js";
import { temporaryDirectoryTask } from "file:///Users/pepicrft/src/github.com/tuist/tuist/docs/node_modules/.pnpm/tempy@3.1.0/node_modules/tempy/index.js";
import * as path3 from "node:path";
import { fileURLToPath } from "node:url";
import ejs from "file:///Users/pepicrft/src/github.com/tuist/tuist/docs/node_modules/.pnpm/ejs@3.1.10/node_modules/ejs/lib/ejs.js";
var __vite_injected_original_import_meta_url = "file:///Users/pepicrft/src/github.com/tuist/tuist/docs/.vitepress/data/cli.js";
var __dirname = path3.dirname(fileURLToPath(__vite_injected_original_import_meta_url));
var rootDirectory = path3.join(__dirname, "../../..");
await $`swift build --product ProjectDescription --configuration debug --package-path ${rootDirectory}`;
await $`swift build --product tuist --configuration debug --package-path ${rootDirectory}`;
var dumpedCLISchema;
await temporaryDirectoryTask(async (tmpDir) => {
  dumpedCLISchema = await $`${path3.join(rootDirectory, ".build/debug/tuist")} --experimental-dump-help --path ${tmpDir}`;
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
    text: "CLI",
    items: subcommands.map((command) => {
      return {
        ...parseCommand(command),
        collapsed: true
      };
    }).sort((a, b) => a.text.localeCompare(b.text))
  };
}

// .vitepress/config.mjs
import { fileURLToPath as fileURLToPath2 } from "node:url";
var __vite_injected_original_dirname3 = "/Users/pepicrft/src/github.com/tuist/tuist/docs/.vitepress";
var __vite_injected_original_import_meta_url2 = "file:///Users/pepicrft/src/github.com/tuist/tuist/docs/.vitepress/config.mjs";
var __dirname2 = path4.dirname(fileURLToPath2(__vite_injected_original_import_meta_url2));
var paths = path4.join(__dirname2, "../../paths.txt");
var config_default = defineConfig({
  title: "Tuist",
  titleTemplate: ":title | Tuist",
  description: "Scale your Xcode app development",
  srcDir: "docs",
  lastUpdated: true,
  locales: {
    en: {
      label: "English",
      lang: "en",
      themeConfig: {
        nav: [
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Guides ${bookOpen01Icon()}</span>`,
            link: "/en/"
          },
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">CLI ${codeBrowserIcon()}</span>`,
            link: "/en/cli/auth"
          },
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Server ${server04Icon()}</span>`,
            link: "/en/server/introduction/why-a-server"
          },
          {
            text: "Resources",
            items: [
              {
                text: "References",
                link: "/en/references/project-description/structs/project"
              },
              { text: "Contributors", link: "/en/contributors/get-started" },
              {
                text: "Changelog",
                link: "https://github.com/tuist/tuist/releases"
              }
            ]
          }
        ],
        sidebar: {
          "/en/contributors": contributorsSidebar("en"),
          "/en/guides/": guidesSidebar("en"),
          "/en/server/": serverSidebar("en"),
          "/en/": guidesSidebar("en"),
          "/en/cli/": await loadData3("en"),
          "/en/references/": await referencesSidebar("en")
        }
      }
    },
    ko: {
      label: "Korean",
      lang: "ko",
      themeConfig: {
        nav: [
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Guides ${bookOpen01Icon()}</span>`,
            link: "/ko/"
          },
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">CLI ${codeBrowserIcon()}</span>`,
            link: "/ko/cli/auth"
          },
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Server ${server04Icon()}</span>`,
            link: "/ko/server/introduction/why-a-server"
          },
          {
            text: "Resources",
            items: [
              {
                text: "References",
                link: "/ko/references/project-description/structs/project"
              },
              { text: "Contributors", link: "/ko/contributors/get-started" },
              {
                text: "Changelog",
                link: "https://github.com/tuist/tuist/releases"
              }
            ]
          }
        ],
        sidebar: {
          "/ko/contributors": contributorsSidebar("ko"),
          "/ko/guides/": guidesSidebar("ko"),
          "/ko/server/": serverSidebar("ko"),
          "/ko/": guidesSidebar("ko"),
          "/ko/cli/": await loadData3("ko"),
          "/ko/references/": await referencesSidebar("ko")
        }
      }
    },
    ja: {
      label: "Korean",
      lang: "ja",
      themeConfig: {
        nav: [
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Guides ${bookOpen01Icon()}</span>`,
            link: "/ja/"
          },
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">CLI ${codeBrowserIcon()}</span>`,
            link: "/ja/cli/auth"
          },
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Server ${server04Icon()}</span>`,
            link: "/ja/server/introduction/why-a-server"
          },
          {
            text: "Resources",
            items: [
              {
                text: "References",
                link: "/ja/references/project-description/structs/project"
              },
              { text: "Contributors", link: "/ja/contributors/get-started" },
              {
                text: "Changelog",
                link: "https://github.com/tuist/tuist/releases"
              }
            ]
          }
        ],
        sidebar: {
          "/ja/contributors": contributorsSidebar("ja"),
          "/ja/guides/": guidesSidebar("ja"),
          "/ja/server/": serverSidebar("ja"),
          "/ja/": guidesSidebar("ja"),
          "/ja/cli/": await loadData3("ja"),
          "/ja/references/": await referencesSidebar("ja")
        }
      }
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
/documentation/tuist/* / 301
${await fs3.readFile(path4.join(__vite_injected_original_dirname3, "locale-redirects.txt"), { encoding: "utf-8" })}
    `;
    fs3.writeFile(redirectsPath, redirects);
  },
  themeConfig: {
    logo: "/logo.png",
    search: {
      provider: "local"
    },
    editLink: {
      pattern: "https://github.com/tuist/tuist/edit/main/docs/docs/:path"
    },
    socialLinks: [
      { icon: "github", link: "https://github.com/tuist/tuist" },
      { icon: "x", link: "https://x.com/tuistio" },
      { icon: "mastodon", link: "https://fosstodon.org/@tuist" },
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
//# sourceMappingURL=data:application/json;base64,ewogICJ2ZXJzaW9uIjogMywKICAic291cmNlcyI6IFsiLnZpdGVwcmVzcy9jb25maWcubWpzIiwgIi52aXRlcHJlc3MvYmFkZ2VzLm1qcyIsICIudml0ZXByZXNzL2ljb25zLm1qcyIsICIudml0ZXByZXNzL2RhdGEvZXhhbXBsZXMuanMiLCAiLnZpdGVwcmVzcy9kYXRhL3Byb2plY3QtZGVzY3JpcHRpb24uanMiLCAiLnZpdGVwcmVzcy9zaWRlYmFycy5tanMiLCAiLnZpdGVwcmVzcy9kYXRhL2NsaS5qcyJdLAogICJzb3VyY2VzQ29udGVudCI6IFsiY29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3NcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZmlsZW5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvY29uZmlnLm1qc1wiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9pbXBvcnRfbWV0YV91cmwgPSBcImZpbGU6Ly8vVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2NvbmZpZy5tanNcIjtpbXBvcnQgeyBkZWZpbmVDb25maWcgfSBmcm9tIFwidml0ZXByZXNzXCI7XG5pbXBvcnQgKiBhcyBwYXRoIGZyb20gXCJub2RlOnBhdGhcIjtcbmltcG9ydCAqIGFzIGZzIGZyb20gXCJub2RlOmZzL3Byb21pc2VzXCI7XG5pbXBvcnQge1xuICBndWlkZXNTaWRlYmFyLFxuICBjb250cmlidXRvcnNTaWRlYmFyLFxuICByZWZlcmVuY2VzU2lkZWJhcixcbiAgc2VydmVyU2lkZWJhcixcbn0gZnJvbSBcIi4vc2lkZWJhcnMubWpzXCI7XG5pbXBvcnQgeyBsb2FkRGF0YSBhcyBsb2FkQ0xJRGF0YSB9IGZyb20gXCIuL2RhdGEvY2xpXCI7XG5cbmltcG9ydCB7IHNlcnZlcjA0SWNvbiwgYm9va09wZW4wMUljb24sIGNvZGVCcm93c2VySWNvbiB9IGZyb20gXCIuL2ljb25zLm1qc1wiO1xuXG5pbXBvcnQgeyBmaWxlVVJMVG9QYXRoIH0gZnJvbSBcIm5vZGU6dXJsXCI7XG5jb25zdCBfX2Rpcm5hbWUgPSBwYXRoLmRpcm5hbWUoZmlsZVVSTFRvUGF0aChpbXBvcnQubWV0YS51cmwpKTtcbmNvbnN0IHBhdGhzID0gcGF0aC5qb2luKF9fZGlybmFtZSwgXCIuLi8uLi9wYXRocy50eHRcIik7XG5cbmV4cG9ydCBkZWZhdWx0IGRlZmluZUNvbmZpZyh7XG4gIHRpdGxlOiBcIlR1aXN0XCIsXG4gIHRpdGxlVGVtcGxhdGU6IFwiOnRpdGxlIHwgVHVpc3RcIixcbiAgZGVzY3JpcHRpb246IFwiU2NhbGUgeW91ciBYY29kZSBhcHAgZGV2ZWxvcG1lbnRcIixcbiAgc3JjRGlyOiBcImRvY3NcIixcbiAgbGFzdFVwZGF0ZWQ6IHRydWUsXG4gIGxvY2FsZXM6IHtcbiAgICBlbjoge1xuICAgICAgbGFiZWw6IFwiRW5nbGlzaFwiLFxuICAgICAgbGFuZzogXCJlblwiLFxuICAgICAgdGhlbWVDb25maWc6IHtcbiAgICAgICAgbmF2OiBbXG4gICAgICAgICAge1xuICAgICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+R3VpZGVzICR7Ym9va09wZW4wMUljb24oKX08L3NwYW4+YCxcbiAgICAgICAgICAgIGxpbms6IFwiL2VuL1wiLFxuICAgICAgICAgIH0sXG4gICAgICAgICAge1xuICAgICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+Q0xJICR7Y29kZUJyb3dzZXJJY29uKCl9PC9zcGFuPmAsXG4gICAgICAgICAgICBsaW5rOiBcIi9lbi9jbGkvYXV0aFwiLFxuICAgICAgICAgIH0sXG4gICAgICAgICAge1xuICAgICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+U2VydmVyICR7c2VydmVyMDRJY29uKCl9PC9zcGFuPmAsXG4gICAgICAgICAgICBsaW5rOiBcIi9lbi9zZXJ2ZXIvaW50cm9kdWN0aW9uL3doeS1hLXNlcnZlclwiLFxuICAgICAgICAgIH0sXG4gICAgICAgICAge1xuICAgICAgICAgICAgdGV4dDogXCJSZXNvdXJjZXNcIixcbiAgICAgICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgICB0ZXh0OiBcIlJlZmVyZW5jZXNcIixcbiAgICAgICAgICAgICAgICBsaW5rOiBcIi9lbi9yZWZlcmVuY2VzL3Byb2plY3QtZGVzY3JpcHRpb24vc3RydWN0cy9wcm9qZWN0XCIsXG4gICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgIHsgdGV4dDogXCJDb250cmlidXRvcnNcIiwgbGluazogXCIvZW4vY29udHJpYnV0b3JzL2dldC1zdGFydGVkXCIgfSxcbiAgICAgICAgICAgICAge1xuICAgICAgICAgICAgICAgIHRleHQ6IFwiQ2hhbmdlbG9nXCIsXG4gICAgICAgICAgICAgICAgbGluazogXCJodHRwczovL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvcmVsZWFzZXNcIixcbiAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIF0sXG4gICAgICAgICAgfSxcbiAgICAgICAgXSxcbiAgICAgICAgc2lkZWJhcjoge1xuICAgICAgICAgIFwiL2VuL2NvbnRyaWJ1dG9yc1wiOiBjb250cmlidXRvcnNTaWRlYmFyKFwiZW5cIiksXG4gICAgICAgICAgXCIvZW4vZ3VpZGVzL1wiOiBndWlkZXNTaWRlYmFyKFwiZW5cIiksXG4gICAgICAgICAgXCIvZW4vc2VydmVyL1wiOiBzZXJ2ZXJTaWRlYmFyKFwiZW5cIiksXG4gICAgICAgICAgXCIvZW4vXCI6IGd1aWRlc1NpZGViYXIoXCJlblwiKSxcbiAgICAgICAgICBcIi9lbi9jbGkvXCI6IGF3YWl0IGxvYWRDTElEYXRhKFwiZW5cIiksXG4gICAgICAgICAgXCIvZW4vcmVmZXJlbmNlcy9cIjogYXdhaXQgcmVmZXJlbmNlc1NpZGViYXIoXCJlblwiKSxcbiAgICAgICAgfSxcbiAgICAgIH0sXG4gICAgfSxcbiAgICBrbzoge1xuICAgICAgbGFiZWw6IFwiS29yZWFuXCIsXG4gICAgICBsYW5nOiBcImtvXCIsXG4gICAgICB0aGVtZUNvbmZpZzoge1xuICAgICAgICBuYXY6IFtcbiAgICAgICAgICB7XG4gICAgICAgICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj5HdWlkZXMgJHtib29rT3BlbjAxSWNvbigpfTwvc3Bhbj5gLFxuICAgICAgICAgICAgbGluazogXCIva28vXCIsXG4gICAgICAgICAgfSxcbiAgICAgICAgICB7XG4gICAgICAgICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj5DTEkgJHtjb2RlQnJvd3Nlckljb24oKX08L3NwYW4+YCxcbiAgICAgICAgICAgIGxpbms6IFwiL2tvL2NsaS9hdXRoXCIsXG4gICAgICAgICAgfSxcbiAgICAgICAgICB7XG4gICAgICAgICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj5TZXJ2ZXIgJHtzZXJ2ZXIwNEljb24oKX08L3NwYW4+YCxcbiAgICAgICAgICAgIGxpbms6IFwiL2tvL3NlcnZlci9pbnRyb2R1Y3Rpb24vd2h5LWEtc2VydmVyXCIsXG4gICAgICAgICAgfSxcbiAgICAgICAgICB7XG4gICAgICAgICAgICB0ZXh0OiBcIlJlc291cmNlc1wiLFxuICAgICAgICAgICAgaXRlbXM6IFtcbiAgICAgICAgICAgICAge1xuICAgICAgICAgICAgICAgIHRleHQ6IFwiUmVmZXJlbmNlc1wiLFxuICAgICAgICAgICAgICAgIGxpbms6IFwiL2tvL3JlZmVyZW5jZXMvcHJvamVjdC1kZXNjcmlwdGlvbi9zdHJ1Y3RzL3Byb2plY3RcIixcbiAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgeyB0ZXh0OiBcIkNvbnRyaWJ1dG9yc1wiLCBsaW5rOiBcIi9rby9jb250cmlidXRvcnMvZ2V0LXN0YXJ0ZWRcIiB9LFxuICAgICAgICAgICAgICB7XG4gICAgICAgICAgICAgICAgdGV4dDogXCJDaGFuZ2Vsb2dcIixcbiAgICAgICAgICAgICAgICBsaW5rOiBcImh0dHBzOi8vZ2l0aHViLmNvbS90dWlzdC90dWlzdC9yZWxlYXNlc1wiLFxuICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgXSxcbiAgICAgICAgICB9LFxuICAgICAgICBdLFxuICAgICAgICBzaWRlYmFyOiB7XG4gICAgICAgICAgXCIva28vY29udHJpYnV0b3JzXCI6IGNvbnRyaWJ1dG9yc1NpZGViYXIoXCJrb1wiKSxcbiAgICAgICAgICBcIi9rby9ndWlkZXMvXCI6IGd1aWRlc1NpZGViYXIoXCJrb1wiKSxcbiAgICAgICAgICBcIi9rby9zZXJ2ZXIvXCI6IHNlcnZlclNpZGViYXIoXCJrb1wiKSxcbiAgICAgICAgICBcIi9rby9cIjogZ3VpZGVzU2lkZWJhcihcImtvXCIpLFxuICAgICAgICAgIFwiL2tvL2NsaS9cIjogYXdhaXQgbG9hZENMSURhdGEoXCJrb1wiKSxcbiAgICAgICAgICBcIi9rby9yZWZlcmVuY2VzL1wiOiBhd2FpdCByZWZlcmVuY2VzU2lkZWJhcihcImtvXCIpLFxuICAgICAgICB9LFxuICAgICAgfSxcbiAgICB9LFxuICAgIGphOiB7XG4gICAgICBsYWJlbDogXCJLb3JlYW5cIixcbiAgICAgIGxhbmc6IFwiamFcIixcbiAgICAgIHRoZW1lQ29uZmlnOiB7XG4gICAgICAgIG5hdjogW1xuICAgICAgICAgIHtcbiAgICAgICAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPkd1aWRlcyAke2Jvb2tPcGVuMDFJY29uKCl9PC9zcGFuPmAsXG4gICAgICAgICAgICBsaW5rOiBcIi9qYS9cIixcbiAgICAgICAgICB9LFxuICAgICAgICAgIHtcbiAgICAgICAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPkNMSSAke2NvZGVCcm93c2VySWNvbigpfTwvc3Bhbj5gLFxuICAgICAgICAgICAgbGluazogXCIvamEvY2xpL2F1dGhcIixcbiAgICAgICAgICB9LFxuICAgICAgICAgIHtcbiAgICAgICAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPlNlcnZlciAke3NlcnZlcjA0SWNvbigpfTwvc3Bhbj5gLFxuICAgICAgICAgICAgbGluazogXCIvamEvc2VydmVyL2ludHJvZHVjdGlvbi93aHktYS1zZXJ2ZXJcIixcbiAgICAgICAgICB9LFxuICAgICAgICAgIHtcbiAgICAgICAgICAgIHRleHQ6IFwiUmVzb3VyY2VzXCIsXG4gICAgICAgICAgICBpdGVtczogW1xuICAgICAgICAgICAgICB7XG4gICAgICAgICAgICAgICAgdGV4dDogXCJSZWZlcmVuY2VzXCIsXG4gICAgICAgICAgICAgICAgbGluazogXCIvamEvcmVmZXJlbmNlcy9wcm9qZWN0LWRlc2NyaXB0aW9uL3N0cnVjdHMvcHJvamVjdFwiLFxuICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICB7IHRleHQ6IFwiQ29udHJpYnV0b3JzXCIsIGxpbms6IFwiL2phL2NvbnRyaWJ1dG9ycy9nZXQtc3RhcnRlZFwiIH0sXG4gICAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgICB0ZXh0OiBcIkNoYW5nZWxvZ1wiLFxuICAgICAgICAgICAgICAgIGxpbms6IFwiaHR0cHM6Ly9naXRodWIuY29tL3R1aXN0L3R1aXN0L3JlbGVhc2VzXCIsXG4gICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBdLFxuICAgICAgICAgIH0sXG4gICAgICAgIF0sXG4gICAgICAgIHNpZGViYXI6IHtcbiAgICAgICAgICBcIi9qYS9jb250cmlidXRvcnNcIjogY29udHJpYnV0b3JzU2lkZWJhcihcImphXCIpLFxuICAgICAgICAgIFwiL2phL2d1aWRlcy9cIjogZ3VpZGVzU2lkZWJhcihcImphXCIpLFxuICAgICAgICAgIFwiL2phL3NlcnZlci9cIjogc2VydmVyU2lkZWJhcihcImphXCIpLFxuICAgICAgICAgIFwiL2phL1wiOiBndWlkZXNTaWRlYmFyKFwiamFcIiksXG4gICAgICAgICAgXCIvamEvY2xpL1wiOiBhd2FpdCBsb2FkQ0xJRGF0YShcImphXCIpLFxuICAgICAgICAgIFwiL2phL3JlZmVyZW5jZXMvXCI6IGF3YWl0IHJlZmVyZW5jZXNTaWRlYmFyKFwiamFcIiksXG4gICAgICAgIH0sXG4gICAgICB9LFxuICAgIH0sXG4gIH0sXG4gIGNsZWFuVXJsczogdHJ1ZSxcbiAgaGVhZDogW1xuICAgIFtcbiAgICAgIFwic2NyaXB0XCIsXG4gICAgICB7fSxcbiAgICAgIGBcbiAgICAgICFmdW5jdGlvbih0LGUpe3ZhciBvLG4scCxyO2UuX19TVnx8KHdpbmRvdy5wb3N0aG9nPWUsZS5faT1bXSxlLmluaXQ9ZnVuY3Rpb24oaSxzLGEpe2Z1bmN0aW9uIGcodCxlKXt2YXIgbz1lLnNwbGl0KFwiLlwiKTsyPT1vLmxlbmd0aCYmKHQ9dFtvWzBdXSxlPW9bMV0pLHRbZV09ZnVuY3Rpb24oKXt0LnB1c2goW2VdLmNvbmNhdChBcnJheS5wcm90b3R5cGUuc2xpY2UuY2FsbChhcmd1bWVudHMsMCkpKX19KHA9dC5jcmVhdGVFbGVtZW50KFwic2NyaXB0XCIpKS50eXBlPVwidGV4dC9qYXZhc2NyaXB0XCIscC5hc3luYz0hMCxwLnNyYz1zLmFwaV9ob3N0LnJlcGxhY2UoXCIuaS5wb3N0aG9nLmNvbVwiLFwiLWFzc2V0cy5pLnBvc3Rob2cuY29tXCIpK1wiL3N0YXRpYy9hcnJheS5qc1wiLChyPXQuZ2V0RWxlbWVudHNCeVRhZ05hbWUoXCJzY3JpcHRcIilbMF0pLnBhcmVudE5vZGUuaW5zZXJ0QmVmb3JlKHAscik7dmFyIHU9ZTtmb3Iodm9pZCAwIT09YT91PWVbYV09W106YT1cInBvc3Rob2dcIix1LnBlb3BsZT11LnBlb3BsZXx8W10sdS50b1N0cmluZz1mdW5jdGlvbih0KXt2YXIgZT1cInBvc3Rob2dcIjtyZXR1cm5cInBvc3Rob2dcIiE9PWEmJihlKz1cIi5cIithKSx0fHwoZSs9XCIgKHN0dWIpXCIpLGV9LHUucGVvcGxlLnRvU3RyaW5nPWZ1bmN0aW9uKCl7cmV0dXJuIHUudG9TdHJpbmcoMSkrXCIucGVvcGxlIChzdHViKVwifSxvPVwiY2FwdHVyZSBpZGVudGlmeSBhbGlhcyBwZW9wbGUuc2V0IHBlb3BsZS5zZXRfb25jZSBzZXRfY29uZmlnIHJlZ2lzdGVyIHJlZ2lzdGVyX29uY2UgdW5yZWdpc3RlciBvcHRfb3V0X2NhcHR1cmluZyBoYXNfb3B0ZWRfb3V0X2NhcHR1cmluZyBvcHRfaW5fY2FwdHVyaW5nIHJlc2V0IGlzRmVhdHVyZUVuYWJsZWQgb25GZWF0dXJlRmxhZ3MgZ2V0RmVhdHVyZUZsYWcgZ2V0RmVhdHVyZUZsYWdQYXlsb2FkIHJlbG9hZEZlYXR1cmVGbGFncyBncm91cCB1cGRhdGVFYXJseUFjY2Vzc0ZlYXR1cmVFbnJvbGxtZW50IGdldEVhcmx5QWNjZXNzRmVhdHVyZXMgZ2V0QWN0aXZlTWF0Y2hpbmdTdXJ2ZXlzIGdldFN1cnZleXMgb25TZXNzaW9uSWRcIi5zcGxpdChcIiBcIiksbj0wO248by5sZW5ndGg7bisrKWcodSxvW25dKTtlLl9pLnB1c2goW2kscyxhXSl9LGUuX19TVj0xKX0oZG9jdW1lbnQsd2luZG93LnBvc3Rob2d8fFtdKTtcbiAgICAgIHBvc3Rob2cuaW5pdCgncGhjX3N0dmE2TkppOExHNkVtUjZSQTZ1UWNSZHJtZlRRY0FWTG9PM3ZHZ1dtTlonLHthcGlfaG9zdDonaHR0cHM6Ly9ldS5pLnBvc3Rob2cuY29tJ30pXG4gICAgYCxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwic2NyaXB0XCIsXG4gICAgICB7fSxcbiAgICAgIGBcbiAgICAgICFmdW5jdGlvbih0KXtpZih3aW5kb3cua28pcmV0dXJuO3dpbmRvdy5rbz1bXSxbXCJpZGVudGlmeVwiLFwidHJhY2tcIixcInJlbW92ZUxpc3RlbmVyc1wiLFwib3BlblwiLFwib25cIixcIm9mZlwiLFwicXVhbGlmeVwiLFwicmVhZHlcIl0uZm9yRWFjaChmdW5jdGlvbih0KXtrb1t0XT1mdW5jdGlvbigpe3ZhciBuPVtdLnNsaWNlLmNhbGwoYXJndW1lbnRzKTtyZXR1cm4gbi51bnNoaWZ0KHQpLGtvLnB1c2gobiksa299fSk7dmFyIG49ZG9jdW1lbnQuY3JlYXRlRWxlbWVudChcInNjcmlwdFwiKTtuLmFzeW5jPSEwLG4uc2V0QXR0cmlidXRlKFwic3JjXCIsXCJodHRwczovL2Nkbi5nZXRrb2FsYS5jb20vdjEvcGtfM2Y4MGEzNTI5ZWMyOTE0YjcxNGEzZjc0MGQxMGIxMjY0MmI5L3Nkay5qc1wiKSwoZG9jdW1lbnQuYm9keSB8fCBkb2N1bWVudC5oZWFkKS5hcHBlbmRDaGlsZChuKX0oKTtcbiAgICBgLFxuICAgIF0sXG4gIF0sXG4gIHNpdGVtYXA6IHtcbiAgICBob3N0bmFtZTogXCJodHRwczovL2RvY3MudHVpc3QuaW9cIixcbiAgfSxcbiAgYXN5bmMgYnVpbGRFbmQoeyBvdXREaXIgfSkge1xuICAgIGNvbnN0IHJlZGlyZWN0c1BhdGggPSBwYXRoLmpvaW4ob3V0RGlyLCBcIl9yZWRpcmVjdHNcIik7XG4gICAgY29uc3QgcmVkaXJlY3RzID0gYFxuL2RvY3VtZW50YXRpb24vdHVpc3QvaW5zdGFsbGF0aW9uIC9ndWlkZS9pbnRyb2R1Y3Rpb24vaW5zdGFsbGF0aW9uIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvcHJvamVjdC1zdHJ1Y3R1cmUgL2d1aWRlL3Byb2plY3QvZGlyZWN0b3J5LXN0cnVjdHVyZSAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L2NvbW1hbmQtbGluZS1pbnRlcmZhY2UgL2d1aWRlL2F1dG9tYXRpb24vZ2VuZXJhdGUgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9kZXBlbmRlbmNpZXMgL2d1aWRlL3Byb2plY3QvZGVwZW5kZW5jaWVzIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3Qvc2hhcmluZy1jb2RlLWFjcm9zcy1tYW5pZmVzdHMgL2d1aWRlL3Byb2plY3QvY29kZS1zaGFyaW5nIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3Qvc3ludGhlc2l6ZWQtZmlsZXMgL2d1aWRlL3Byb2plY3Qvc3ludGhlc2l6ZWQtZmlsZXMgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9taWdyYXRpb24tZ3VpZGVsaW5lcyAvZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L21pZ3JhdGUtZnJvbS14Y29kZXByb2ogMzAxXG4vdHV0b3JpYWxzL3R1aXN0LXR1dG9yaWFscyAvZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L25ldy1wcm9qZWN0IDMwMVxuL3R1dG9yaWFscy90dWlzdC9pbnN0YWxsICAvZ3VpZGUvaW50cm9kdWN0aW9uL2Fkb3B0aW5nLXR1aXN0L25ldy1wcm9qZWN0IDMwMVxuL3R1dG9yaWFscy90dWlzdC9jcmVhdGUtcHJvamVjdCAgL2d1aWRlL2ludHJvZHVjdGlvbi9hZG9wdGluZy10dWlzdC9uZXctcHJvamVjdCAzMDFcbi90dXRvcmlhbHMvdHVpc3QvZXh0ZXJuYWwtZGVwZW5kZW5jaWVzIC9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3QvbmV3LXByb2plY3QgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9nZW5lcmF0aW9uLWVudmlyb25tZW50IC9ndWlkZS9wcm9qZWN0L2R5bmFtaWMtY29uZmlndXJhdGlvbiAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3VzaW5nLXBsdWdpbnMgL2d1aWRlL3Byb2plY3QvcGx1Z2lucyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L2NyZWF0aW5nLXBsdWdpbnMgL2d1aWRlL3Byb2plY3QvcGx1Z2lucyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3Rhc2sgL2d1aWRlL3Byb2plY3QvcGx1Z2lucyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3R1aXN0LWNsb3VkIC9jbG91ZC93aGF0LWlzLWNsb3VkIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvdHVpc3QtY2xvdWQtZ2V0LXN0YXJ0ZWQgL2Nsb3VkL2dldC1zdGFydGVkIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvYmluYXJ5LWNhY2hpbmcgL2Nsb3VkL2JpbmFyeS1jYWNoaW5nIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3Qvc2VsZWN0aXZlLXRlc3RpbmcgL2Nsb3VkL3NlbGVjdGl2ZS10ZXN0aW5nIDMwMVxuL3R1dG9yaWFscy90dWlzdC1jbG91ZC10dXRvcmlhbHMgL2Nsb3VkL29uLXByZW1pc2UgMzAxXG4vdHV0b3JpYWxzL3R1aXN0L2VudGVycHJpc2UtaW5mcmFzdHJ1Y3R1cmUtcmVxdWlyZW1lbnRzIC9jbG91ZC9vbi1wcmVtaXNlIDMwMVxuL3R1dG9yaWFscy90dWlzdC9lbnRlcnByaXNlLWVudmlyb25tZW50IC9jbG91ZC9vbi1wcmVtaXNlIDMwMVxuL3R1dG9yaWFscy90dWlzdC9lbnRlcnByaXNlLWRlcGxveW1lbnQgL2Nsb3VkL29uLXByZW1pc2UgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC9nZXQtc3RhcnRlZC1hcy1jb250cmlidXRvciAvY29udHJpYnV0b3JzL2dldC1zdGFydGVkIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvbWFuaWZlc3RvIC9jb250cmlidXRvcnMvcHJpbmNpcGxlcyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L2NvZGUtcmV2aWV3cyAvY29udHJpYnV0b3JzL2NvZGUtcmV2aWV3cyAzMDFcbi9kb2N1bWVudGF0aW9uL3R1aXN0L3JlcG9ydGluZy1idWdzIC9jb250cmlidXRvcnMvaXNzdWUtcmVwb3J0aW5nIDMwMVxuL2RvY3VtZW50YXRpb24vdHVpc3QvY2hhbXBpb25pbmctcHJvamVjdHMgL2NvbnRyaWJ1dG9ycy9nZXQtc3RhcnRlZCAzMDFcbi9ndWlkZS9zY2FsZS91ZmVhdHVyZXMtYXJjaGl0ZWN0dXJlLmh0bWwgL2d1aWRlL3NjYWxlL3RtYS1hcmNoaXRlY3R1cmUuaHRtbCAzMDFcbi9ndWlkZS9zY2FsZS91ZmVhdHVyZXMtYXJjaGl0ZWN0dXJlIC9ndWlkZS9zY2FsZS90bWEtYXJjaGl0ZWN0dXJlIDMwMVxuL2d1aWRlL2ludHJvZHVjdGlvbi9jb3N0LW9mLWNvbnZlbmllbmNlIC9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9jb3N0LW9mLWNvbnZlbmllbmNlIDMwMVxuL2d1aWRlL2ludHJvZHVjdGlvbi9pbnN0YWxsYXRpb24gL2d1aWRlcy9xdWljay1zdGFydC9pbnN0YWxsLXR1aXN0IDMwMVxuL2d1aWRlL2ludHJvZHVjdGlvbi9hZG9wdGluZy10dWlzdC9uZXctcHJvamVjdCAvZ3VpZGVzL3N0YXJ0L25ldy1wcm9qZWN0IDMwMVxuL2d1aWRlL2ludHJvZHVjdGlvbi9hZG9wdGluZy10dWlzdC9zd2lmdC1wYWNrYWdlIC9ndWlkZXMvc3RhcnQvc3dpZnQtcGFja2FnZSAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3QvbWlncmF0ZS1mcm9tLXhjb2RlcHJvaiAvZ3VpZGVzL3N0YXJ0L21pZ3JhdGUveGNvZGUtcHJvamVjdCAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3QvbWlncmF0ZS1sb2NhbC1zd2lmdC1wYWNrYWdlcyAvZ3VpZGVzL3N0YXJ0L21pZ3JhdGUvc3dpZnQtcGFja2FnZSAzMDFcbi9ndWlkZS9pbnRyb2R1Y3Rpb24vYWRvcHRpbmctdHVpc3QvbWlncmF0ZS1mcm9tLXhjb2RlZ2VuIC9ndWlkZXMvc3RhcnQvbWlncmF0ZS94Y29kZWdlbi1wcm9qZWN0IDMwMVxuL2d1aWRlL2ludHJvZHVjdGlvbi9hZG9wdGluZy10dWlzdC9taWdyYXRlLWZyb20tYmF6ZWwgL2d1aWRlcy9zdGFydC9taWdyYXRlL2JhemVsLXByb2plY3QgMzAxXG4vZ3VpZGUvaW50cm9kdWN0aW9uL2Zyb20tdjMtdG8tdjQgL3JlZmVyZW5jZXMvbWlncmF0aW9ucy9mcm9tLXYzLXRvLXY0IDMwMVxuL2d1aWRlL3Byb2plY3QvbWFuaWZlc3RzIC9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9tYW5pZmVzdHMgMzAxXG4vZ3VpZGUvcHJvamVjdC9kaXJlY3Rvcnktc3RydWN0dXJlIC9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9kaXJlY3Rvcnktc3RydWN0dXJlIDMwMVxuL2d1aWRlL3Byb2plY3QvZWRpdGluZyAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvZWRpdGluZyAzMDFcbi9ndWlkZS9wcm9qZWN0L2RlcGVuZGVuY2llcyAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvZGVwZW5kZW5jaWVzIDMwMVxuL2d1aWRlL3Byb2plY3QvY29kZS1zaGFyaW5nIC9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9jb2RlLXNoYXJpbmcgMzAxXG4vZ3VpZGUvcHJvamVjdC9zeW50aGVzaXplZC1maWxlcyAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvc3ludGhlc2l6ZWQtZmlsZXMgMzAxXG4vZ3VpZGUvcHJvamVjdC9keW5hbWljLWNvbmZpZ3VyYXRpb24gL2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2R5bmFtaWMtY29uZmlndXJhdGlvbiAzMDFcbi9ndWlkZS9wcm9qZWN0L3RlbXBsYXRlcyAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvdGVtcGxhdGVzIDMwMVxuL2d1aWRlL3Byb2plY3QvcGx1Z2lucyAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvcGx1Z2lucyAzMDFcbi9ndWlkZS9hdXRvbWF0aW9uL2dlbmVyYXRlIC8gMzAxXG4vZ3VpZGUvYXV0b21hdGlvbi9idWlsZCAvZ3VpZGVzL2RldmVsb3AvYnVpbGQgMzAxXG4vZ3VpZGUvYXV0b21hdGlvbi90ZXN0IC9ndWlkZXMvZGV2ZWxvcC90ZXN0IDMwMVxuL2d1aWRlL2F1dG9tYXRpb24vcnVuIC8gMzAxXG4vZ3VpZGUvYXV0b21hdGlvbi9ncmFwaCAvIDMwMVxuL2d1aWRlL2F1dG9tYXRpb24vY2xlYW4gLyAzMDFcbi9ndWlkZS9zY2FsZS90bWEtYXJjaGl0ZWN0dXJlIC9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy90bWEtYXJjaGl0ZWN0dXJlIDMwMVxuL2Nsb3VkL3doYXQtaXMtY2xvdWQgLyAzMDFcbi9jbG91ZC9nZXQtc3RhcnRlZCAvIDMwMVxuL2Nsb3VkL2JpbmFyeS1jYWNoaW5nIC9ndWlkZXMvZGV2ZWxvcC9idWlsZC9jYWNoZSAzMDFcbi9jbG91ZC9zZWxlY3RpdmUtdGVzdGluZyAvZ3VpZGVzL2RldmVsb3AvdGVzdC9zbWFydC1ydW5uZXIgMzAxXG4vY2xvdWQvaGFzaGluZyAvZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvaGFzaGluZyAzMDFcbi9jbG91ZC9vbi1wcmVtaXNlIC9ndWlkZXMvZGFzaGJvYXJkL29uLXByZW1pc2UvaW5zdGFsbCAzMDFcbi9jbG91ZC9vbi1wcmVtaXNlL21ldHJpY3MgL2d1aWRlcy9kYXNoYm9hcmQvb24tcHJlbWlzZS9tZXRyaWNzIDMwMVxuL3JlZmVyZW5jZS9wcm9qZWN0LWRlc2NyaXB0aW9uLyogL3JlZmVyZW5jZXMvcHJvamVjdC1kZXNjcmlwdGlvbi86c3BsYXQgMzAxXG4vcmVmZXJlbmNlL2V4YW1wbGVzLyogL3JlZmVyZW5jZXMvZXhhbXBsZXMvOnNwbGF0IDMwMVxuL2d1aWRlcy9kZXZlbG9wL3dvcmtmbG93cyAvZ3VpZGVzL2RldmVsb3AvY29udGludW91cy1pbnRlZ3JhdGlvbi93b3JrZmxvd3MgMzAxXG4vZ3VpZGVzL2Rhc2hib2FyZC9vbi1wcmVtaXNlL2luc3RhbGwgL3NlcnZlci9vbi1wcmVtaXNlL2luc3RhbGwgMzAxXG4vZ3VpZGVzL2Rhc2hib2FyZC9vbi1wcmVtaXNlL21ldHJpY3MgL3NlcnZlci9vbi1wcmVtaXNlL21ldHJpY3MgMzAxXG4vZG9jdW1lbnRhdGlvbi90dWlzdC8qIC8gMzAxXG4ke2F3YWl0IGZzLnJlYWRGaWxlKHBhdGguam9pbihpbXBvcnQubWV0YS5kaXJuYW1lLCBcImxvY2FsZS1yZWRpcmVjdHMudHh0XCIpLCB7IGVuY29kaW5nOiBcInV0Zi04XCIgfSl9XG4gICAgYDtcbiAgICBmcy53cml0ZUZpbGUocmVkaXJlY3RzUGF0aCwgcmVkaXJlY3RzKTtcbiAgfSxcbiAgdGhlbWVDb25maWc6IHtcbiAgICBsb2dvOiBcIi9sb2dvLnBuZ1wiLFxuICAgIHNlYXJjaDoge1xuICAgICAgcHJvdmlkZXI6IFwibG9jYWxcIixcbiAgICB9LFxuICAgIGVkaXRMaW5rOiB7XG4gICAgICBwYXR0ZXJuOiBcImh0dHBzOi8vZ2l0aHViLmNvbS90dWlzdC90dWlzdC9lZGl0L21haW4vZG9jcy9kb2NzLzpwYXRoXCIsXG4gICAgfSxcbiAgICBzb2NpYWxMaW5rczogW1xuICAgICAgeyBpY29uOiBcImdpdGh1YlwiLCBsaW5rOiBcImh0dHBzOi8vZ2l0aHViLmNvbS90dWlzdC90dWlzdFwiIH0sXG4gICAgICB7IGljb246IFwieFwiLCBsaW5rOiBcImh0dHBzOi8veC5jb20vdHVpc3Rpb1wiIH0sXG4gICAgICB7IGljb246IFwibWFzdG9kb25cIiwgbGluazogXCJodHRwczovL2Zvc3N0b2Rvbi5vcmcvQHR1aXN0XCIgfSxcbiAgICAgIHtcbiAgICAgICAgaWNvbjogXCJzbGFja1wiLFxuICAgICAgICBsaW5rOiBcImh0dHBzOi8vam9pbi5zbGFjay5jb20vdC90dWlzdGFwcC9zaGFyZWRfaW52aXRlL3p0LTF5NjY3bWpiay1zMkxUUlgxWUJ5YjlFSUlUamRMY0x3XCIsXG4gICAgICB9LFxuICAgIF0sXG4gICAgZm9vdGVyOiB7XG4gICAgICBtZXNzYWdlOiBcIlJlbGVhc2VkIHVuZGVyIHRoZSBNSVQgTGljZW5zZS5cIixcbiAgICAgIGNvcHlyaWdodDogXCJDb3B5cmlnaHQgXHUwMEE5IDIwMjQtcHJlc2VudCBUdWlzdCBHbWJIXCIsXG4gICAgfSxcbiAgfSxcbn0pO1xuIiwgImNvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ZpbGVuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2JhZGdlcy5tanNcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfaW1wb3J0X21ldGFfdXJsID0gXCJmaWxlOi8vL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9iYWRnZXMubWpzXCI7ZXhwb3J0IGZ1bmN0aW9uIGNvbWluZ1Nvb25CYWRnZSgpIHtcbiAgcmV0dXJuIGA8c3BhbiBzdHlsZT1cImJhY2tncm91bmQ6IHZhcigtLXZwLWN1c3RvbS1ibG9jay10aXAtY29kZS1iZyk7IGNvbG9yOiB2YXIoLS12cC1jLXRpcC0xKTsgZm9udC1zaXplOiAxMXB4OyBkaXNwbGF5OiBpbmxpbmUtYmxvY2s7IHBhZGRpbmctbGVmdDogNXB4OyBwYWRkaW5nLXJpZ2h0OiA1cHg7IGJvcmRlci1yYWRpdXM6IDEwJTtcIj5Db21pbmcgc29vbjwvc3Bhbj5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24geGNvZGVQcm9qQ29tcGF0aWJsZUJhZGdlKCkge1xuICByZXR1cm4gYDxzcGFuIHN0eWxlPVwiYmFja2dyb3VuZDogdmFyKC0tdnAtYmFkZ2Utd2FybmluZy1iZyk7IGNvbG9yOiB2YXIoLS12cC1iYWRnZS13YXJuaW5nLXRleHQpOyBmb250LXNpemU6IDExcHg7IGRpc3BsYXk6IGlubGluZS1ibG9jazsgcGFkZGluZy1sZWZ0OiA1cHg7IHBhZGRpbmctcmlnaHQ6IDVweDsgYm9yZGVyLXJhZGl1czogMTAlO1wiPlhjb2RlUHJvaiBDb21wYXRpYmxlPC9zcGFuPmA7XG59XG4iLCAiY29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3NcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZmlsZW5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvaWNvbnMubWpzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ltcG9ydF9tZXRhX3VybCA9IFwiZmlsZTovLy9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvaWNvbnMubWpzXCI7ZXhwb3J0IGZ1bmN0aW9uIGN1YmVPdXRsaW5lSWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTkuNzUgMjAuNzUwMUwxMS4yMjMgMjEuNTY4NEMxMS41MDY2IDIxLjcyNiAxMS42NDg0IDIxLjgwNDcgMTEuNzk4NiAyMS44MzU2QzExLjkzMTUgMjEuODYzIDEyLjA2ODUgMjEuODYzIDEyLjIwMTUgMjEuODM1NkMxMi4zNTE2IDIxLjgwNDcgMTIuNDkzNCAyMS43MjYgMTIuNzc3IDIxLjU2ODRMMTQuMjUgMjAuNzUwMU01LjI1IDE4LjI1MDFMMy44MjI5NyAxNy40NTczQzMuNTIzNDYgMTcuMjkwOSAzLjM3MzY4IDE3LjIwNzcgMy4yNjQ2MyAxNy4wODkzQzMuMTY4MTYgMTYuOTg0NyAzLjA5NTE1IDE2Ljg2MDYgMy4wNTA0OCAxNi43MjU0QzMgMTYuNTcyNiAzIDE2LjQwMTMgMyAxNi4wNTg2VjE0LjUwMDFNMyA5LjUwMDA5VjcuOTQxNTNDMyA3LjU5ODg5IDMgNy40Mjc1NyAzLjA1MDQ4IDcuMjc0NzdDMy4wOTUxNSA3LjEzOTU5IDMuMTY4MTYgNy4wMTU1MSAzLjI2NDYzIDYuOTEwODJDMy4zNzM2OCA2Ljc5MjQ4IDMuNTIzNDUgNi43MDkyOCAzLjgyMjk3IDYuNTQyODhMNS4yNSA1Ljc1MDA5TTkuNzUgMy4yNTAwOEwxMS4yMjMgMi40MzE3N0MxMS41MDY2IDIuMjc0MjEgMTEuNjQ4NCAyLjE5NTQzIDExLjc5ODYgMi4xNjQ1NEMxMS45MzE1IDIuMTM3MjEgMTIuMDY4NSAyLjEzNzIxIDEyLjIwMTUgMi4xNjQ1NEMxMi4zNTE2IDIuMTk1NDMgMTIuNDkzNCAyLjI3NDIxIDEyLjc3NyAyLjQzMTc3TDE0LjI1IDMuMjUwMDhNMTguNzUgNS43NTAwOEwyMC4xNzcgNi41NDI4OEMyMC40NzY2IDYuNzA5MjggMjAuNjI2MyA2Ljc5MjQ4IDIwLjczNTQgNi45MTA4MkMyMC44MzE4IDcuMDE1NTEgMjAuOTA0OSA3LjEzOTU5IDIwLjk0OTUgNy4yNzQ3N0MyMSA3LjQyNzU3IDIxIDcuNTk4ODkgMjEgNy45NDE1M1Y5LjUwMDA4TTIxIDE0LjUwMDFWMTYuMDU4NkMyMSAxNi40MDEzIDIxIDE2LjU3MjYgMjAuOTQ5NSAxNi43MjU0QzIwLjkwNDkgMTYuODYwNiAyMC44MzE4IDE2Ljk4NDcgMjAuNzM1NCAxNy4wODkzQzIwLjYyNjMgMTcuMjA3NyAyMC40NzY2IDE3LjI5MDkgMjAuMTc3IDE3LjQ1NzNMMTguNzUgMTguMjUwMU05Ljc1IDEwLjc1MDFMMTIgMTIuMDAwMU0xMiAxMi4wMDAxTDE0LjI1IDEwLjc1MDFNMTIgMTIuMDAwMVYxNC41MDAxTTMgNy4wMDAwOEw1LjI1IDguMjUwMDhNMTguNzUgOC4yNTAwOEwyMSA3LjAwMDA4TTEyIDE5LjUwMDFWMjIuMDAwMVwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5cbmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBjdWJlMDJJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNMTIgMi41MDAwOFYxMi4wMDAxTTEyIDEyLjAwMDFMMjAuNSA3LjI3Nzc5TTEyIDEyLjAwMDFMMy41IDcuMjc3NzlNMTIgMTIuMDAwMVYyMS41MDAxTTIwLjUgMTYuNzIyM0wxMi43NzcgMTIuNDMxOEMxMi40OTM0IDEyLjI3NDIgMTIuMzUxNiAxMi4xOTU0IDEyLjIwMTUgMTIuMTY0NUMxMi4wNjg1IDEyLjEzNzIgMTEuOTMxNSAxMi4xMzcyIDExLjc5ODYgMTIuMTY0NUMxMS42NDg0IDEyLjE5NTQgMTEuNTA2NiAxMi4yNzQyIDExLjIyMyAxMi40MzE4TDMuNSAxNi43MjIzTTIxIDE2LjA1ODZWNy45NDE1M0MyMSA3LjU5ODg5IDIxIDcuNDI3NTcgMjAuOTQ5NSA3LjI3NDc3QzIwLjkwNDkgNy4xMzk1OSAyMC44MzE4IDcuMDE1NTEgMjAuNzM1NCA2LjkxMDgyQzIwLjYyNjMgNi43OTI0OCAyMC40NzY2IDYuNzA5MjggMjAuMTc3IDYuNTQyODhMMTIuNzc3IDIuNDMxNzdDMTIuNDkzNCAyLjI3NDIxIDEyLjM1MTYgMi4xOTU0MyAxMi4yMDE1IDIuMTY0NTRDMTIuMDY4NSAyLjEzNzIxIDExLjkzMTUgMi4xMzcyMSAxMS43OTg2IDIuMTY0NTRDMTEuNjQ4NCAyLjE5NTQzIDExLjUwNjYgMi4yNzQyMSAxMS4yMjMgMi40MzE3N0wzLjgyMjk3IDYuNTQyODhDMy41MjM0NSA2LjcwOTI4IDMuMzczNjkgNi43OTI0OCAzLjI2NDYzIDYuOTEwODJDMy4xNjgxNiA3LjAxNTUxIDMuMDk1MTUgNy4xMzk1OSAzLjA1MDQ4IDcuMjc0NzdDMyA3LjQyNzU3IDMgNy41OTg4OSAzIDcuOTQxNTNWMTYuMDU4NkMzIDE2LjQwMTMgMyAxNi41NzI2IDMuMDUwNDggMTYuNzI1NEMzLjA5NTE1IDE2Ljg2MDYgMy4xNjgxNiAxNi45ODQ3IDMuMjY0NjMgMTcuMDg5M0MzLjM3MzY5IDE3LjIwNzcgMy41MjM0NSAxNy4yOTA5IDMuODIyOTcgMTcuNDU3M0wxMS4yMjMgMjEuNTY4NEMxMS41MDY2IDIxLjcyNiAxMS42NDg0IDIxLjgwNDcgMTEuNzk4NiAyMS44MzU2QzExLjkzMTUgMjEuODYzIDEyLjA2ODUgMjEuODYzIDEyLjIwMTUgMjEuODM1NkMxMi4zNTE2IDIxLjgwNDcgMTIuNDkzNCAyMS43MjYgMTIuNzc3IDIxLjU2ODRMMjAuMTc3IDE3LjQ1NzNDMjAuNDc2NiAxNy4yOTA5IDIwLjYyNjMgMTcuMjA3NyAyMC43MzU0IDE3LjA4OTNDMjAuODMxOCAxNi45ODQ3IDIwLjkwNDkgMTYuODYwNiAyMC45NDk1IDE2LjcyNTRDMjEgMTYuNTcyNiAyMSAxNi40MDEzIDIxIDE2LjA1ODZaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGN1YmUwMUljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuPHBhdGggZD1cIk0yMC41IDcuMjc3ODNMMTIgMTIuMDAwMU0xMiAxMi4wMDAxTDMuNDk5OTcgNy4yNzc4M00xMiAxMi4wMDAxTDEyIDIxLjUwMDFNMjEgMTYuMDU4NlY3Ljk0MTUzQzIxIDcuNTk4ODkgMjEgNy40Mjc1NyAyMC45NDk1IDcuMjc0NzdDMjAuOTA0OSA3LjEzOTU5IDIwLjgzMTggNy4wMTU1MSAyMC43MzU0IDYuOTEwODJDMjAuNjI2MyA2Ljc5MjQ4IDIwLjQ3NjYgNi43MDkyOCAyMC4xNzcgNi41NDI4OEwxMi43NzcgMi40MzE3N0MxMi40OTM0IDIuMjc0MjEgMTIuMzUxNiAyLjE5NTQzIDEyLjIwMTUgMi4xNjQ1NEMxMi4wNjg1IDIuMTM3MjEgMTEuOTMxNSAyLjEzNzIxIDExLjc5ODYgMi4xNjQ1NEMxMS42NDg0IDIuMTk1NDMgMTEuNTA2NiAyLjI3NDIxIDExLjIyMyAyLjQzMTc3TDMuODIyOTcgNi41NDI4OEMzLjUyMzQ1IDYuNzA5MjggMy4zNzM2OSA2Ljc5MjQ4IDMuMjY0NjMgNi45MTA4MkMzLjE2ODE2IDcuMDE1NTEgMy4wOTUxNSA3LjEzOTU5IDMuMDUwNDggNy4yNzQ3N0MzIDcuNDI3NTcgMyA3LjU5ODg5IDMgNy45NDE1M1YxNi4wNTg2QzMgMTYuNDAxMyAzIDE2LjU3MjYgMy4wNTA0OCAxNi43MjU0QzMuMDk1MTUgMTYuODYwNiAzLjE2ODE2IDE2Ljk4NDcgMy4yNjQ2MyAxNy4wODkzQzMuMzczNjkgMTcuMjA3NyAzLjUyMzQ1IDE3LjI5MDkgMy44MjI5NyAxNy40NTczTDExLjIyMyAyMS41Njg0QzExLjUwNjYgMjEuNzI2IDExLjY0ODQgMjEuODA0NyAxMS43OTg2IDIxLjgzNTZDMTEuOTMxNSAyMS44NjMgMTIuMDY4NSAyMS44NjMgMTIuMjAxNSAyMS44MzU2QzEyLjM1MTYgMjEuODA0NyAxMi40OTM0IDIxLjcyNiAxMi43NzcgMjEuNTY4NEwyMC4xNzcgMTcuNDU3M0MyMC40NzY2IDE3LjI5MDkgMjAuNjI2MyAxNy4yMDc3IDIwLjczNTQgMTcuMDg5M0MyMC44MzE4IDE2Ljk4NDcgMjAuOTA0OSAxNi44NjA2IDIwLjk0OTUgMTYuNzI1NEMyMSAxNi41NzI2IDIxIDE2LjQwMTMgMjEgMTYuMDU4NlpcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuPC9zdmc+XG5cbiAgYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGJhckNoYXJ0U3F1YXJlMDJJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNOCAxNVYxN00xMiAxMVYxN00xNiA3VjE3TTcuOCAyMUgxNi4yQzE3Ljg4MDIgMjEgMTguNzIwMiAyMSAxOS4zNjIgMjAuNjczQzE5LjkyNjUgMjAuMzg1NCAyMC4zODU0IDE5LjkyNjUgMjAuNjczIDE5LjM2MkMyMSAxOC43MjAyIDIxIDE3Ljg4MDIgMjEgMTYuMlY3LjhDMjEgNi4xMTk4NCAyMSA1LjI3OTc2IDIwLjY3MyA0LjYzODAzQzIwLjM4NTQgNC4wNzM1NCAxOS45MjY1IDMuNjE0NiAxOS4zNjIgMy4zMjY5OEMxOC43MjAyIDMgMTcuODgwMiAzIDE2LjIgM0g3LjhDNi4xMTk4NCAzIDUuMjc5NzYgMyA0LjYzODAzIDMuMzI2OThDNC4wNzM1NCAzLjYxNDYgMy42MTQ2IDQuMDczNTQgMy4zMjY5OCA0LjYzODAzQzMgNS4yNzk3NiAzIDYuMTE5ODQgMyA3LjhWMTYuMkMzIDE3Ljg4MDIgMyAxOC43MjAyIDMuMzI2OTggMTkuMzYyQzMuNjE0NiAxOS45MjY1IDQuMDczNTQgMjAuMzg1NCA0LjYzODAzIDIwLjY3M0M1LjI3OTc2IDIxIDYuMTE5ODQgMjEgNy44IDIxWlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5cbiAgICBgO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY29kZTAySWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTE3IDE3TDIyIDEyTDE3IDdNNyA3TDIgMTJMNyAxN00xNCAzTDEwIDIxXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGRhdGFJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNMjEuMiAyMkMyMS40OCAyMiAyMS42MiAyMiAyMS43MjcgMjEuOTQ1NUMyMS44MjExIDIxLjg5NzYgMjEuODk3NiAyMS44MjExIDIxLjk0NTUgMjEuNzI3QzIyIDIxLjYyIDIyIDIxLjQ4IDIyIDIxLjJWMTAuOEMyMiAxMC41MiAyMiAxMC4zOCAyMS45NDU1IDEwLjI3M0MyMS44OTc2IDEwLjE3ODkgMjEuODIxMSAxMC4xMDI0IDIxLjcyNyAxMC4wNTQ1QzIxLjYyIDEwIDIxLjQ4IDEwIDIxLjIgMTBMMTguOCAxMEMxOC41MiAxMCAxOC4zOCAxMCAxOC4yNzMgMTAuMDU0NUMxOC4xNzg5IDEwLjEwMjQgMTguMTAyNCAxMC4xNzg5IDE4LjA1NDUgMTAuMjczQzE4IDEwLjM4IDE4IDEwLjUyIDE4IDEwLjhWMTMuMkMxOCAxMy40OCAxOCAxMy42MiAxNy45NDU1IDEzLjcyN0MxNy44OTc2IDEzLjgyMTEgMTcuODIxMSAxMy44OTc2IDE3LjcyNyAxMy45NDU1QzE3LjYyIDE0IDE3LjQ4IDE0IDE3LjIgMTRIMTQuOEMxNC41MiAxNCAxNC4zOCAxNCAxNC4yNzMgMTQuMDU0NUMxNC4xNzg5IDE0LjEwMjQgMTQuMTAyNCAxNC4xNzg5IDE0LjA1NDUgMTQuMjczQzE0IDE0LjM4IDE0IDE0LjUyIDE0IDE0LjhWMTcuMkMxNCAxNy40OCAxNCAxNy42MiAxMy45NDU1IDE3LjcyN0MxMy44OTc2IDE3LjgyMTEgMTMuODIxMSAxNy44OTc2IDEzLjcyNyAxNy45NDU1QzEzLjYyIDE4IDEzLjQ4IDE4IDEzLjIgMThIMTAuOEMxMC41MiAxOCAxMC4zOCAxOCAxMC4yNzMgMTguMDU0NUMxMC4xNzg5IDE4LjEwMjQgMTAuMTAyNCAxOC4xNzg5IDEwLjA1NDUgMTguMjczQzEwIDE4LjM4IDEwIDE4LjUyIDEwIDE4LjhWMjEuMkMxMCAyMS40OCAxMCAyMS42MiAxMC4wNTQ1IDIxLjcyN0MxMC4xMDI0IDIxLjgyMTEgMTAuMTc4OSAyMS44OTc2IDEwLjI3MyAyMS45NDU1QzEwLjM4IDIyIDEwLjUyIDIyIDEwLjggMjJMMjEuMiAyMlpcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuPHBhdGggZD1cIk0xMCA2LjhDMTAgNi41MTk5NyAxMCA2LjM3OTk2IDEwLjA1NDUgNi4yNzNDMTAuMTAyNCA2LjE3ODkyIDEwLjE3ODkgNi4xMDI0MyAxMC4yNzMgNi4wNTQ1QzEwLjM4IDYgMTAuNTIgNiAxMC44IDZIMTMuMkMxMy40OCA2IDEzLjYyIDYgMTMuNzI3IDYuMDU0NUMxMy44MjExIDYuMTAyNDMgMTMuODk3NiA2LjE3ODkyIDEzLjk0NTUgNi4yNzNDMTQgNi4zNzk5NiAxNCA2LjUxOTk3IDE0IDYuOFY5LjJDMTQgOS40ODAwMyAxNCA5LjYyMDA0IDEzLjk0NTUgOS43MjdDMTMuODk3NiA5LjgyMTA4IDEzLjgyMTEgOS44OTc1NyAxMy43MjcgOS45NDU1QzEzLjYyIDEwIDEzLjQ4IDEwIDEzLjIgMTBIMTAuOEMxMC41MiAxMCAxMC4zOCAxMCAxMC4yNzMgOS45NDU1QzEwLjE3ODkgOS44OTc1NyAxMC4xMDI0IDkuODIxMDggMTAuMDU0NSA5LjcyN0MxMCA5LjYyMDA0IDEwIDkuNDgwMDMgMTAgOS4yVjYuOFpcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuPHBhdGggZD1cIk0zIDEyLjhDMyAxMi41MiAzIDEyLjM4IDMuMDU0NSAxMi4yNzNDMy4xMDI0MyAxMi4xNzg5IDMuMTc4OTIgMTIuMTAyNCAzLjI3MyAxMi4wNTQ1QzMuMzc5OTYgMTIgMy41MTk5NyAxMiAzLjggMTJINi4yQzYuNDgwMDMgMTIgNi42MjAwNCAxMiA2LjcyNyAxMi4wNTQ1QzYuODIxMDggMTIuMTAyNCA2Ljg5NzU3IDEyLjE3ODkgNi45NDU1IDEyLjI3M0M3IDEyLjM4IDcgMTIuNTIgNyAxMi44VjE1LjJDNyAxNS40OCA3IDE1LjYyIDYuOTQ1NSAxNS43MjdDNi44OTc1NyAxNS44MjExIDYuODIxMDggMTUuODk3NiA2LjcyNyAxNS45NDU1QzYuNjIwMDQgMTYgNi40ODAwMyAxNiA2LjIgMTZIMy44QzMuNTE5OTcgMTYgMy4zNzk5NiAxNiAzLjI3MyAxNS45NDU1QzMuMTc4OTIgMTUuODk3NiAzLjEwMjQzIDE1LjgyMTEgMy4wNTQ1IDE1LjcyN0MzIDE1LjYyIDMgMTUuNDggMyAxNS4yVjEyLjhaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjxwYXRoIGQ9XCJNMiAyLjhDMiAyLjUxOTk3IDIgMi4zNzk5NiAyLjA1NDUgMi4yNzNDMi4xMDI0MyAyLjE3ODkyIDIuMTc4OTIgMi4xMDI0MyAyLjI3MyAyLjA1NDVDMi4zNzk5NiAyIDIuNTE5OTcgMiAyLjggMkg1LjJDNS40ODAwMyAyIDUuNjIwMDQgMiA1LjcyNyAyLjA1NDVDNS44MjEwOCAyLjEwMjQzIDUuODk3NTcgMi4xNzg5MiA1Ljk0NTUgMi4yNzNDNiAyLjM3OTk2IDYgMi41MTk5NyA2IDIuOFY1LjJDNiA1LjQ4MDAzIDYgNS42MjAwNCA1Ljk0NTUgNS43MjdDNS44OTc1NyA1LjgyMTA4IDUuODIxMDggNS44OTc1NyA1LjcyNyA1Ljk0NTVDNS42MjAwNCA2IDUuNDgwMDMgNiA1LjIgNkgyLjhDMi41MTk5NyA2IDIuMzc5OTYgNiAyLjI3MyA1Ljk0NTVDMi4xNzg5MiA1Ljg5NzU3IDIuMTAyNDMgNS44MjEwOCAyLjA1NDUgNS43MjdDMiA1LjYyMDA0IDIgNS40ODAwMyAyIDUuMlYyLjhaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBjaGVja0NpcmNsZUljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7MTV9XCIgaGVpZ2h0PVwiJHsxNX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTcuNSAxMkwxMC41IDE1TDE2LjUgOU0yMiAxMkMyMiAxNy41MjI4IDE3LjUyMjggMjIgMTIgMjJDNi40NzcxNSAyMiAyIDE3LjUyMjggMiAxMkMyIDYuNDc3MTUgNi40NzcxNSAyIDEyIDJDMTcuNTIyOCAyIDIyIDYuNDc3MTUgMjIgMTJaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIHR1aXN0SWNvbihzaXplID0gMTUpIHtcbiAgcmV0dXJuIGA8c3ZnIHdpZHRoPVwiJHtzaXplfVwiIGhlaWdodD1cIiR7c2l6ZX1cIiB2aWV3Qm94PVwiMCAwIDI0IDI0XCIgZmlsbD1cIm5vbmVcIiB4bWxucz1cImh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnXCI+XG48cGF0aCBkPVwiTTIxIDE2VjcuMkMyMSA2LjA3OTkgMjEgNS41MTk4NCAyMC43ODIgNS4wOTIwMkMyMC41OTAzIDQuNzE1NjkgMjAuMjg0MyA0LjQwOTczIDE5LjkwOCA0LjIxNzk5QzE5LjQ4MDIgNCAxOC45MjAxIDQgMTcuOCA0SDYuMkM1LjA3OTg5IDQgNC41MTk4NCA0IDQuMDkyMDIgNC4yMTc5OUMzLjcxNTY5IDQuNDA5NzMgMy40MDk3MyA0LjcxNTY5IDMuMjE3OTkgNS4wOTIwMkMzIDUuNTE5ODQgMyA2LjA3OTkgMyA3LjJWMTZNNC42NjY2NyAyMEgxOS4zMzMzQzE5Ljk1MzMgMjAgMjAuMjYzMyAyMCAyMC41MTc2IDE5LjkzMTlDMjEuMjA3OCAxOS43NDY5IDIxLjc0NjkgMTkuMjA3OCAyMS45MzE5IDE4LjUxNzZDMjIgMTguMjYzMyAyMiAxNy45NTMzIDIyIDE3LjMzMzNDMjIgMTcuMDIzMyAyMiAxNi44NjgzIDIxLjk2NTkgMTYuNzQxMkMyMS44NzM1IDE2LjM5NjEgMjEuNjAzOSAxNi4xMjY1IDIxLjI1ODggMTYuMDM0MUMyMS4xMzE3IDE2IDIwLjk3NjcgMTYgMjAuNjY2NyAxNkgzLjMzMzMzQzMuMDIzMzQgMTYgMi44NjgzNSAxNiAyLjc0MTE4IDE2LjAzNDFDMi4zOTYwOSAxNi4xMjY1IDIuMTI2NTQgMTYuMzk2MSAyLjAzNDA3IDE2Ljc0MTJDMiAxNi44NjgzIDIgMTcuMDIzMyAyIDE3LjMzMzNDMiAxNy45NTMzIDIgMTguMjYzMyAyLjA2ODE1IDE4LjUxNzZDMi4yNTMwOCAxOS4yMDc4IDIuNzkyMTggMTkuNzQ2OSAzLjQ4MjM2IDE5LjkzMTlDMy43MzY2OSAyMCA0LjA0NjY5IDIwIDQuNjY2NjcgMjBaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBjbG91ZEJsYW5rMDJJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbjxwYXRoIGQ9XCJNOS41IDE5QzUuMzU3ODYgMTkgMiAxNS42NDIxIDIgMTEuNUMyIDcuMzU3ODYgNS4zNTc4NiA0IDkuNSA0QzEyLjM4MjcgNCAxNC44ODU1IDUuNjI2MzQgMTYuMTQxIDguMDExNTNDMTYuMjU5NyA4LjAwMzg4IDE2LjM3OTQgOCAxNi41IDhDMTkuNTM3NiA4IDIyIDEwLjQ2MjQgMjIgMTMuNUMyMiAxNi41Mzc2IDE5LjUzNzYgMTkgMTYuNSAxOUMxMy45NDg1IDE5IDEyLjEyMjQgMTkgOS41IDE5WlwiIHN0cm9rZT1cImN1cnJlbnRDb2xvclwiIHN0cm9rZS13aWR0aD1cIjJcIiBzdHJva2UtbGluZWNhcD1cInJvdW5kXCIgc3Ryb2tlLWxpbmVqb2luPVwicm91bmRcIi8+XG48L3N2Zz5cbmA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBzZXJ2ZXIwNEljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuPHBhdGggZD1cIk0yMiAxMC41TDIxLjUyNTYgNi43MDQ2M0MyMS4zMzk1IDUuMjE2MDIgMjEuMjQ2NSA0LjQ3MTY5IDIwLjg5NjEgMy45MTA4QzIwLjU4NzUgMy40MTY2MiAyMC4xNDE2IDMuMDIzMDEgMTkuNjEzIDIuNzc4MDRDMTkuMDEzIDIuNSAxOC4yNjI5IDIuNSAxNi43NjI2IDIuNUg3LjIzNzM1QzUuNzM3MTQgMi41IDQuOTg3MDQgMi41IDQuMzg3MDIgMi43NzgwNEMzLjg1ODM4IDMuMDIzMDEgMy40MTI1IDMuNDE2NjIgMy4xMDM4NiAzLjkxMDhDMi43NTM1NCA0LjQ3MTY5IDIuNjYwNSA1LjIxNjAxIDIuNDc0NDIgNi43MDQ2M0wyIDEwLjVNNS41IDE0LjVIMTguNU01LjUgMTQuNUMzLjU2NyAxNC41IDIgMTIuOTMzIDIgMTFDMiA5LjA2NyAzLjU2NyA3LjUgNS41IDcuNUgxOC41QzIwLjQzMyA3LjUgMjIgOS4wNjcgMjIgMTFDMjIgMTIuOTMzIDIwLjQzMyAxNC41IDE4LjUgMTQuNU01LjUgMTQuNUMzLjU2NyAxNC41IDIgMTYuMDY3IDIgMThDMiAxOS45MzMgMy41NjcgMjEuNSA1LjUgMjEuNUgxOC41QzIwLjQzMyAyMS41IDIyIDE5LjkzMyAyMiAxOEMyMiAxNi4wNjcgMjAuNDMzIDE0LjUgMTguNSAxNC41TTYgMTFINi4wMU02IDE4SDYuMDFNMTIgMTFIMThNMTIgMThIMThcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuPC9zdmc+XG5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gbWljcm9zY29wZUljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuPHBhdGggZD1cIk0zIDIySDEyTTExIDYuMjUyMDRDMTEuNjM5MiA2LjA4NzUxIDEyLjMwOTQgNiAxMyA2QzE3LjQxODMgNiAyMSA5LjU4MTcyIDIxIDE0QzIxIDE3LjM1NzQgMTguOTMxOCAyMC4yMzE3IDE2IDIxLjQxODVNNS41IDEzSDkuNUM5Ljk2NDY2IDEzIDEwLjE5NyAxMyAxMC4zOTAyIDEzLjAzODRDMTEuMTgzNiAxMy4xOTYyIDExLjgwMzggMTMuODE2NCAxMS45NjE2IDE0LjYwOThDMTIgMTQuODAzIDEyIDE1LjAzNTMgMTIgMTUuNUMxMiAxNS45NjQ3IDEyIDE2LjE5NyAxMS45NjE2IDE2LjM5MDJDMTEuODAzOCAxNy4xODM2IDExLjE4MzYgMTcuODAzOCAxMC4zOTAyIDE3Ljk2MTZDMTAuMTk3IDE4IDkuOTY0NjYgMTggOS41IDE4SDUuNUM1LjAzNTM0IDE4IDQuODAzMDIgMTggNC42MDk4MiAxNy45NjE2QzMuODE2NDQgMTcuODAzOCAzLjE5NjI0IDE3LjE4MzYgMy4wMzg0MyAxNi4zOTAyQzMgMTYuMTk3IDMgMTUuOTY0NyAzIDE1LjVDMyAxNS4wMzUzIDMgMTQuODAzIDMuMDM4NDMgMTQuNjA5OEMzLjE5NjI0IDEzLjgxNjQgMy44MTY0NCAxMy4xOTYyIDQuNjA5ODIgMTMuMDM4NEM0LjgwMzAyIDEzIDUuMDM1MzQgMTMgNS41IDEzWk00IDUuNVYxM0gxMVY1LjVDMTEgMy41NjcgOS40MzMgMiA3LjUgMkM1LjU2NyAyIDQgMy41NjcgNCA1LjVaXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbjwvc3ZnPlxuYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGJ1aWxkaW5nMDdJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbiAgPHBhdGggZD1cIk03LjUgMTFINC42QzQuMDM5OTUgMTEgMy43NTk5MiAxMSAzLjU0NjAxIDExLjEwOUMzLjM1Nzg1IDExLjIwNDkgMy4yMDQ4NyAxMS4zNTc4IDMuMTA4OTkgMTEuNTQ2QzMgMTEuNzU5OSAzIDEyLjAzOTkgMyAxMi42VjIxTTE2LjUgMTFIMTkuNEMxOS45NjAxIDExIDIwLjI0MDEgMTEgMjAuNDU0IDExLjEwOUMyMC42NDIyIDExLjIwNDkgMjAuNzk1MSAxMS4zNTc4IDIwLjg5MSAxMS41NDZDMjEgMTEuNzU5OSAyMSAxMi4wMzk5IDIxIDEyLjZWMjFNMTYuNSAyMVY2LjJDMTYuNSA1LjA3OTkgMTYuNSA0LjUxOTg0IDE2LjI4MiA0LjA5MjAyQzE2LjA5MDMgMy43MTU2OSAxNS43ODQzIDMuNDA5NzMgMTUuNDA4IDMuMjE3OTlDMTQuOTgwMiAzIDE0LjQyMDEgMyAxMy4zIDNIMTAuN0M5LjU3OTg5IDMgOS4wMTk4NCAzIDguNTkyMDIgMy4yMTc5OUM4LjIxNTY5IDMuNDA5NzMgNy45MDk3MyAzLjcxNTY5IDcuNzE3OTkgNC4wOTIwMkM3LjUgNC41MTk4NCA3LjUgNS4wNzk5IDcuNSA2LjJWMjFNMjIgMjFIMk0xMSA3SDEzTTExIDExSDEzTTExIDE1SDEzXCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbiAgPC9zdmc+XG5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gYm9va09wZW4wMUljb24oc2l6ZSA9IDE1KSB7XG4gIHJldHVybiBgPHN2ZyB3aWR0aD1cIiR7c2l6ZX1cIiBoZWlnaHQ9XCIke3NpemV9XCIgdmlld0JveD1cIjAgMCAyNCAyNFwiIGZpbGw9XCJub25lXCIgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPlxuICA8cGF0aCBkPVwiTTEyIDIxTDExLjg5OTkgMjAuODQ5OUMxMS4yMDUzIDE5LjgwOCAxMC44NTggMTkuMjg3IDEwLjM5OTEgMTguOTA5OEM5Ljk5Mjg2IDE4LjU3NTkgOS41MjQ3NiAxOC4zMjU0IDkuMDIxNjEgMTguMTcyNkM4LjQ1MzI1IDE4IDcuODI3MTEgMTggNi41NzQ4MiAxOEg1LjJDNC4wNzk4OSAxOCAzLjUxOTg0IDE4IDMuMDkyMDIgMTcuNzgyQzIuNzE1NjkgMTcuNTkwMyAyLjQwOTczIDE3LjI4NDMgMi4yMTc5OSAxNi45MDhDMiAxNi40ODAyIDIgMTUuOTIwMSAyIDE0LjhWNi4yQzIgNS4wNzk4OSAyIDQuNTE5ODQgMi4yMTc5OSA0LjA5MjAyQzIuNDA5NzMgMy43MTU2OSAyLjcxNTY5IDMuNDA5NzMgMy4wOTIwMiAzLjIxNzk5QzMuNTE5ODQgMyA0LjA3OTg5IDMgNS4yIDNINS42QzcuODQwMjEgMyA4Ljk2MDMxIDMgOS44MTU5NiAzLjQzNTk3QzEwLjU2ODYgMy44MTk0NyAxMS4xODA1IDQuNDMxMzkgMTEuNTY0IDUuMTg0MDRDMTIgNi4wMzk2OCAxMiA3LjE1OTc5IDEyIDkuNE0xMiAyMVY5LjRNMTIgMjFMMTIuMTAwMSAyMC44NDk5QzEyLjc5NDcgMTkuODA4IDEzLjE0MiAxOS4yODcgMTMuNjAwOSAxOC45MDk4QzE0LjAwNzEgMTguNTc1OSAxNC40NzUyIDE4LjMyNTQgMTQuOTc4NCAxOC4xNzI2QzE1LjU0NjcgMTggMTYuMTcyOSAxOCAxNy40MjUyIDE4SDE4LjhDMTkuOTIwMSAxOCAyMC40ODAyIDE4IDIwLjkwOCAxNy43ODJDMjEuMjg0MyAxNy41OTAzIDIxLjU5MDMgMTcuMjg0MyAyMS43ODIgMTYuOTA4QzIyIDE2LjQ4MDIgMjIgMTUuOTIwMSAyMiAxNC44VjYuMkMyMiA1LjA3OTg5IDIyIDQuNTE5ODQgMjEuNzgyIDQuMDkyMDJDMjEuNTkwMyAzLjcxNTY5IDIxLjI4NDMgMy40MDk3MyAyMC45MDggMy4yMTc5OUMyMC40ODAyIDMgMTkuOTIwMSAzIDE4LjggM0gxOC40QzE2LjE1OTggMyAxNS4wMzk3IDMgMTQuMTg0IDMuNDM1OTdDMTMuNDMxNCAzLjgxOTQ3IDEyLjgxOTUgNC40MzEzOSAxMi40MzYgNS4xODQwNEMxMiA2LjAzOTY4IDEyIDcuMTU5NzkgMTIgOS40XCIgc3Ryb2tlPVwiY3VycmVudENvbG9yXCIgc3Ryb2tlLXdpZHRoPVwiMlwiIHN0cm9rZS1saW5lY2FwPVwicm91bmRcIiBzdHJva2UtbGluZWpvaW49XCJyb3VuZFwiLz5cbiAgPC9zdmc+XG5gO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY29kZUJyb3dzZXJJY29uKHNpemUgPSAxNSkge1xuICByZXR1cm4gYDxzdmcgd2lkdGg9XCIke3NpemV9XCIgaGVpZ2h0PVwiJHtzaXplfVwiIHZpZXdCb3g9XCIwIDAgMjQgMjRcIiBmaWxsPVwibm9uZVwiIHhtbG5zPVwiaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmdcIj5cbiAgPHBhdGggZD1cIk0yMiA5SDJNMTQgMTcuNUwxNi41IDE1TDE0IDEyLjVNMTAgMTIuNUw3LjUgMTVMMTAgMTcuNU0yIDcuOEwyIDE2LjJDMiAxNy44ODAyIDIgMTguNzIwMiAyLjMyNjk4IDE5LjM2MkMyLjYxNDYgMTkuOTI2NSAzLjA3MzU0IDIwLjM4NTQgMy42MzgwMyAyMC42NzNDNC4yNzk3NiAyMSA1LjExOTg0IDIxIDYuOCAyMUgxNy4yQzE4Ljg4MDIgMjEgMTkuNzIwMiAyMSAyMC4zNjIgMjAuNjczQzIwLjkyNjUgMjAuMzg1NCAyMS4zODU0IDE5LjkyNjUgMjEuNjczIDE5LjM2MkMyMiAxOC43MjAyIDIyIDE3Ljg4MDIgMjIgMTYuMlY3LjhDMjIgNi4xMTk4NCAyMiA1LjI3OTc3IDIxLjY3MyA0LjYzODAzQzIxLjM4NTQgNC4wNzM1NCAyMC45MjY1IDMuNjE0NiAyMC4zNjIgMy4zMjY5OEMxOS43MjAyIDMgMTguODgwMiAzIDE3LjIgM0w2LjggM0M1LjExOTg0IDMgNC4yNzk3NiAzIDMuNjM4MDMgMy4zMjY5OEMzLjA3MzU0IDMuNjE0NiAyLjYxNDYgNC4wNzM1NCAyLjMyNjk4IDQuNjM4MDNDMiA1LjI3OTc2IDIgNi4xMTk4NCAyIDcuOFpcIiBzdHJva2U9XCJjdXJyZW50Q29sb3JcIiBzdHJva2Utd2lkdGg9XCIyXCIgc3Ryb2tlLWxpbmVjYXA9XCJyb3VuZFwiIHN0cm9rZS1saW5lam9pbj1cInJvdW5kXCIvPlxuICA8L3N2Zz5cbmA7XG59XG4iLCAiY29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvZGF0YVwiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9maWxlbmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9kYXRhL2V4YW1wbGVzLmpzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ltcG9ydF9tZXRhX3VybCA9IFwiZmlsZTovLy9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvZGF0YS9leGFtcGxlcy5qc1wiO2ltcG9ydCAqIGFzIHBhdGggZnJvbSBcIm5vZGU6cGF0aFwiO1xuaW1wb3J0IGZnIGZyb20gXCJmYXN0LWdsb2JcIjtcbmltcG9ydCBmcyBmcm9tIFwibm9kZTpmc1wiO1xuXG5jb25zdCBnbG9iID0gcGF0aC5qb2luKGltcG9ydC5tZXRhLmRpcm5hbWUsIFwiLi4vLi4vLi4vZml4dHVyZXMvKi9SRUFETUUubWRcIik7XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiBsb2FkRGF0YShmaWxlcykge1xuICBpZiAoIWZpbGVzKSB7XG4gICAgZmlsZXMgPSBmZ1xuICAgICAgLnN5bmMoZ2xvYiwge1xuICAgICAgICBhYnNvbHV0ZTogdHJ1ZSxcbiAgICAgIH0pXG4gICAgICAuc29ydCgpO1xuICB9XG4gIHJldHVybiBmaWxlcy5tYXAoKGZpbGUpID0+IHtcbiAgICBjb25zdCBjb250ZW50ID0gZnMucmVhZEZpbGVTeW5jKGZpbGUsIFwidXRmLThcIik7XG4gICAgY29uc3QgdGl0bGVSZWdleCA9IC9eI1xccyooLispL207XG4gICAgY29uc3QgdGl0bGVNYXRjaCA9IGNvbnRlbnQubWF0Y2godGl0bGVSZWdleCk7XG4gICAgcmV0dXJuIHtcbiAgICAgIHRpdGxlOiB0aXRsZU1hdGNoWzFdLFxuICAgICAgbmFtZTogcGF0aC5iYXNlbmFtZShwYXRoLmRpcm5hbWUoZmlsZSkpLnRvTG93ZXJDYXNlKCksXG4gICAgICBjb250ZW50OiBjb250ZW50LFxuICAgICAgdXJsOiBgaHR0cHM6Ly9naXRodWIuY29tL3R1aXN0L3R1aXN0L3RyZWUvbWFpbi9maXh0dXJlcy8ke3BhdGguYmFzZW5hbWUoXG4gICAgICAgIHBhdGguZGlybmFtZShmaWxlKSxcbiAgICAgICl9YCxcbiAgICB9O1xuICB9KTtcbn1cblxuZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIHBhdGhzKCkge1xuICByZXR1cm4gKGF3YWl0IGxvYWREYXRhKCkpLm1hcCgoaXRlbSkgPT4ge1xuICAgIHJldHVybiB7XG4gICAgICBwYXJhbXM6IHtcbiAgICAgICAgZXhhbXBsZTogaXRlbS5uYW1lLFxuICAgICAgICB0aXRsZTogaXRlbS50aXRsZSxcbiAgICAgICAgZGVzY3JpcHRpb246IGl0ZW0uZGVzY3JpcHRpb24sXG4gICAgICAgIHVybDogaXRlbS51cmwsXG4gICAgICB9LFxuICAgICAgY29udGVudDogaXRlbS5jb250ZW50LFxuICAgIH07XG4gIH0pO1xufVxuIiwgImNvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2RhdGFcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZmlsZW5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvZGF0YS9wcm9qZWN0LWRlc2NyaXB0aW9uLmpzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ltcG9ydF9tZXRhX3VybCA9IFwiZmlsZTovLy9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvZGF0YS9wcm9qZWN0LWRlc2NyaXB0aW9uLmpzXCI7aW1wb3J0ICogYXMgcGF0aCBmcm9tIFwibm9kZTpwYXRoXCI7XG5pbXBvcnQgZmcgZnJvbSBcImZhc3QtZ2xvYlwiO1xuaW1wb3J0IGZzIGZyb20gXCJub2RlOmZzXCI7XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiBwYXRocyhsb2NhbGUpIHtcbiAgcmV0dXJuIChhd2FpdCBsb2FkRGF0YSgpKS5tYXAoKGl0ZW0pID0+IHtcbiAgICByZXR1cm4ge1xuICAgICAgcGFyYW1zOiB7XG4gICAgICAgIHR5cGU6IGl0ZW0ubmFtZSxcbiAgICAgICAgdGl0bGU6IGl0ZW0udGl0bGUsXG4gICAgICAgIGRlc2NyaXB0aW9uOiBpdGVtLmRlc2NyaXB0aW9uLFxuICAgICAgICBpZGVudGlmaWVyOiBpdGVtLmlkZW50aWZpZXIsXG4gICAgICB9LFxuICAgICAgY29udGVudDogaXRlbS5jb250ZW50LFxuICAgIH07XG4gIH0pO1xufVxuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gbG9hZERhdGEobG9jYWxlKSB7XG4gIGNvbnN0IGdlbmVyYXRlZERpcmVjdG9yeSA9IHBhdGguam9pbihcbiAgICBpbXBvcnQubWV0YS5kaXJuYW1lLFxuICAgIFwiLi4vLi4vZG9jcy9nZW5lcmF0ZWQvbWFuaWZlc3RcIixcbiAgKTtcbiAgY29uc3QgZmlsZXMgPSBmZ1xuICAgIC5zeW5jKFwiKiovKi5tZFwiLCB7XG4gICAgICBjd2Q6IGdlbmVyYXRlZERpcmVjdG9yeSxcbiAgICAgIGFic29sdXRlOiB0cnVlLFxuICAgICAgaWdub3JlOiBbXCIqKi9SRUFETUUubWRcIl0sXG4gICAgfSlcbiAgICAuc29ydCgpO1xuICByZXR1cm4gZmlsZXMubWFwKChmaWxlKSA9PiB7XG4gICAgY29uc3QgY2F0ZWdvcnkgPSBwYXRoLmJhc2VuYW1lKHBhdGguZGlybmFtZShmaWxlKSk7XG4gICAgY29uc3QgZmlsZU5hbWUgPSBwYXRoLmJhc2VuYW1lKGZpbGUpLnJlcGxhY2UoXCIubWRcIiwgXCJcIik7XG4gICAgcmV0dXJuIHtcbiAgICAgIGNhdGVnb3J5OiBjYXRlZ29yeSxcbiAgICAgIHRpdGxlOiBmaWxlTmFtZSxcbiAgICAgIG5hbWU6IGZpbGVOYW1lLnRvTG93ZXJDYXNlKCksXG4gICAgICBpZGVudGlmaWVyOiBjYXRlZ29yeSArIFwiL1wiICsgZmlsZU5hbWUudG9Mb3dlckNhc2UoKSxcbiAgICAgIGRlc2NyaXB0aW9uOiBcIlwiLFxuICAgICAgY29udGVudDogZnMucmVhZEZpbGVTeW5jKGZpbGUsIFwidXRmLThcIiksXG4gICAgfTtcbiAgfSk7XG59XG4iLCAiY29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3NcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZmlsZW5hbWUgPSBcIi9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3Mvc2lkZWJhcnMubWpzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ltcG9ydF9tZXRhX3VybCA9IFwiZmlsZTovLy9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3Mvc2lkZWJhcnMubWpzXCI7aW1wb3J0IHsgY29taW5nU29vbkJhZGdlLCB4Y29kZVByb2pDb21wYXRpYmxlQmFkZ2UgfSBmcm9tIFwiLi9iYWRnZXMubWpzXCI7XG5pbXBvcnQge1xuICBjdWJlT3V0bGluZUljb24sXG4gIGN1YmUwMkljb24sXG4gIGN1YmUwMUljb24sXG4gIG1pY3Jvc2NvcGVJY29uLFxuICBjb2RlMDJJY29uLFxuICBkYXRhSWNvbixcbiAgY2hlY2tDaXJjbGVJY29uLFxuICB0dWlzdEljb24sXG4gIGJ1aWxkaW5nMDdJY29uLFxuICBjbG91ZEJsYW5rMDJJY29uLFxuICBzZXJ2ZXIwNEljb24sXG59IGZyb20gXCIuL2ljb25zLm1qc1wiO1xuaW1wb3J0IHsgbG9hZERhdGEgYXMgbG9hZEV4YW1wbGVzRGF0YSB9IGZyb20gXCIuL2RhdGEvZXhhbXBsZXNcIjtcbmltcG9ydCB7IGxvYWREYXRhIGFzIGxvYWRQcm9qZWN0RGVzY3JpcHRpb25EYXRhIH0gZnJvbSBcIi4vZGF0YS9wcm9qZWN0LWRlc2NyaXB0aW9uXCI7XG5cbmFzeW5jIGZ1bmN0aW9uIHByb2plY3REZXNjcmlwdGlvblNpZGViYXIobG9jYWxlKSB7XG4gIGNvbnN0IHByb2plY3REZXNjcmlwdGlvblR5cGVzRGF0YSA9IGF3YWl0IGxvYWRQcm9qZWN0RGVzY3JpcHRpb25EYXRhKCk7XG4gIGNvbnN0IHByb2plY3REZXNjcmlwdGlvblNpZGViYXIgPSB7XG4gICAgdGV4dDogXCJQcm9qZWN0IERlc2NyaXB0aW9uXCIsXG4gICAgY29sbGFwc2VkOiB0cnVlLFxuICAgIGl0ZW1zOiBbXSxcbiAgfTtcbiAgZnVuY3Rpb24gY2FwaXRhbGl6ZSh0ZXh0KSB7XG4gICAgcmV0dXJuIHRleHQuY2hhckF0KDApLnRvVXBwZXJDYXNlKCkgKyB0ZXh0LnNsaWNlKDEpLnRvTG93ZXJDYXNlKCk7XG4gIH1cbiAgW1wic3RydWN0c1wiLCBcImVudW1zXCIsIFwiZXh0ZW5zaW9uc1wiLCBcInR5cGVhbGlhc2VzXCJdLmZvckVhY2goKGNhdGVnb3J5KSA9PiB7XG4gICAgaWYgKFxuICAgICAgcHJvamVjdERlc2NyaXB0aW9uVHlwZXNEYXRhLmZpbmQoKGl0ZW0pID0+IGl0ZW0uY2F0ZWdvcnkgPT09IGNhdGVnb3J5KVxuICAgICkge1xuICAgICAgcHJvamVjdERlc2NyaXB0aW9uU2lkZWJhci5pdGVtcy5wdXNoKHtcbiAgICAgICAgdGV4dDogY2FwaXRhbGl6ZShjYXRlZ29yeSksXG4gICAgICAgIGNvbGxhcHNlZDogdHJ1ZSxcbiAgICAgICAgaXRlbXM6IHByb2plY3REZXNjcmlwdGlvblR5cGVzRGF0YVxuICAgICAgICAgIC5maWx0ZXIoKGl0ZW0pID0+IGl0ZW0uY2F0ZWdvcnkgPT09IGNhdGVnb3J5KVxuICAgICAgICAgIC5tYXAoKGl0ZW0pID0+ICh7XG4gICAgICAgICAgICB0ZXh0OiBpdGVtLnRpdGxlLFxuICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vcmVmZXJlbmNlcy9wcm9qZWN0LWRlc2NyaXB0aW9uLyR7aXRlbS5pZGVudGlmaWVyfWAsXG4gICAgICAgICAgfSkpLFxuICAgICAgfSk7XG4gICAgfVxuICB9KTtcbiAgcmV0dXJuIHByb2plY3REZXNjcmlwdGlvblNpZGViYXI7XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiByZWZlcmVuY2VzU2lkZWJhcihsb2NhbGUpIHtcbiAgcmV0dXJuIFtcbiAgICB7XG4gICAgICB0ZXh0OiBcIlJlZmVyZW5jZVwiLFxuICAgICAgaXRlbXM6IFtcbiAgICAgICAgYXdhaXQgcHJvamVjdERlc2NyaXB0aW9uU2lkZWJhcihsb2NhbGUpLFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogXCJFeGFtcGxlc1wiLFxuICAgICAgICAgIGNvbGxhcHNlZDogdHJ1ZSxcbiAgICAgICAgICBpdGVtczogKGF3YWl0IGxvYWRFeGFtcGxlc0RhdGEoKSkubWFwKChpdGVtKSA9PiB7XG4gICAgICAgICAgICByZXR1cm4ge1xuICAgICAgICAgICAgICB0ZXh0OiBpdGVtLnRpdGxlLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9yZWZlcmVuY2VzL2V4YW1wbGVzLyR7aXRlbS5uYW1lfWAsXG4gICAgICAgICAgICB9O1xuICAgICAgICAgIH0pLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogXCJNaWdyYXRpb25zXCIsXG4gICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IFwiRnJvbSB2MyB0byB2NFwiLFxuICAgICAgICAgICAgICBsaW5rOiBcIi9yZWZlcmVuY2VzL21pZ3JhdGlvbnMvZnJvbS12My10by12NFwiLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICBdLFxuICAgICAgICB9LFxuICAgICAgXSxcbiAgICB9LFxuICBdO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY29udHJpYnV0b3JzU2lkZWJhcihsb2NhbGUpIHtcbiAgcmV0dXJuIFtcbiAgICB7XG4gICAgICB0ZXh0OiBcIkNvbnRyaWJ1dG9yc1wiLFxuICAgICAgaXRlbXM6IFtcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IFwiR2V0IHN0YXJ0ZWRcIixcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jb250cmlidXRvcnMvZ2V0LXN0YXJ0ZWRgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogXCJJc3N1ZSByZXBvcnRpbmdcIixcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jb250cmlidXRvcnMvaXNzdWUtcmVwb3J0aW5nYCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IFwiQ29kZSByZXZpZXdzXCIsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vY29udHJpYnV0b3JzL2NvZGUtcmV2aWV3c2AsXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBcIlByaW5jaXBsZXNcIixcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9jb250cmlidXRvcnMvcHJpbmNpcGxlc2AsXG4gICAgICAgIH0sXG4gICAgICBdLFxuICAgIH0sXG4gIF07XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBzZXJ2ZXJTaWRlYmFyKGxvY2FsZSkge1xuICByZXR1cm4gW1xuICAgIHtcbiAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPkludHJvZHVjdGlvbiAke3NlcnZlcjA0SWNvbigpfTwvc3Bhbj5gLFxuICAgICAgaXRlbXM6IFtcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IFwiV2h5IGEgc2VydmVyP1wiLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L3NlcnZlci9pbnRyb2R1Y3Rpb24vd2h5LWEtc2VydmVyYCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IFwiQWNjb3VudHMgYW5kIHByb2plY3RzXCIsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vc2VydmVyL2ludHJvZHVjdGlvbi9hY2NvdW50cy1hbmQtcHJvamVjdHNgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogXCJBdXRoZW50aWNhdGlvblwiLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L3NlcnZlci9pbnRyb2R1Y3Rpb24vYXV0aGVudGljYXRpb25gLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogXCJJbnRlZ3JhdGlvbnNcIixcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9zZXJ2ZXIvaW50cm9kdWN0aW9uL2ludGVncmF0aW9uc2AsXG4gICAgICAgIH0sXG4gICAgICBdLFxuICAgIH0sXG4gICAge1xuICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+T24tcHJlbWlzZSAke2J1aWxkaW5nMDdJY29uKCl9PC9zcGFuPmAsXG4gICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICBpdGVtczogW1xuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogXCJJbnN0YWxsXCIsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vc2VydmVyL29uLXByZW1pc2UvaW5zdGFsbGAsXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBcIk1ldHJpY3NcIixcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9zZXJ2ZXIvb24tcHJlbWlzZS9tZXRyaWNzYCxcbiAgICAgICAgfSxcbiAgICAgIF0sXG4gICAgfSxcbiAgICB7XG4gICAgICB0ZXh0OiBcIkFQSSBEb2N1bWVudGF0aW9uXCIsXG4gICAgICBsaW5rOiBcImh0dHBzOi8vY2xvdWQudHVpc3QuaW8vYXBpL2RvY3NcIixcbiAgICB9LFxuICAgIHtcbiAgICAgIHRleHQ6IFwiU3RhdHVzXCIsXG4gICAgICBsaW5rOiBcImh0dHBzOi8vc3RhdHVzLnR1aXN0LmlvXCIsXG4gICAgfSxcbiAgICB7XG4gICAgICB0ZXh0OiBcIk1ldHJpY3MgRGFzaGJvYXJkXCIsXG4gICAgICBsaW5rOiBcImh0dHBzOi8vdHVpc3QuZ3JhZmFuYS5uZXQvcHVibGljLWRhc2hib2FyZHMvMWY4NWYxYzM4OTVlNDhmZWJkMDJjYzczNTBhZGUyZDlcIixcbiAgICB9LFxuICBdO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gZ3VpZGVzU2lkZWJhcihsb2NhbGUpIHtcbiAgcmV0dXJuIFtcbiAgICB7XG4gICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj5RdWljayBzdGFydCAke3R1aXN0SWNvbigpfTwvc3Bhbj5gLFxuICAgICAgbGluazogXCIvXCIsXG4gICAgICBpdGVtczogW1xuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogXCJJbnN0YWxsIFR1aXN0XCIsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3F1aWNrLXN0YXJ0L2luc3RhbGwtdHVpc3RgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogXCJDcmVhdGUgYSBwcm9qZWN0XCIsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3F1aWNrLXN0YXJ0L2NyZWF0ZS1hLXByb2plY3RgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogXCJBZGQgZGVwZW5kZW5jaWVzXCIsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3F1aWNrLXN0YXJ0L2FkZC1kZXBlbmRlbmNpZXNgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogXCJHYXRoZXIgaW5zaWdodHNcIixcbiAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvcXVpY2stc3RhcnQvZ2F0aGVyLWluc2lnaHRzYCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IFwiT3B0aW1pemUgd29ya2Zsb3dzXCIsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3F1aWNrLXN0YXJ0L29wdGltaXplLXdvcmtmbG93c2AsXG4gICAgICAgIH0sXG4gICAgICBdLFxuICAgIH0sXG4gICAge1xuICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+U3RhcnQgJHtjdWJlT3V0bGluZUljb24oKX08L3NwYW4+YCxcbiAgICAgIGl0ZW1zOiBbXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBcIkNyZWF0ZSBhIG5ldyBwcm9qZWN0XCIsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3N0YXJ0L25ldy1wcm9qZWN0YCxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IFwiVHJ5IHdpdGggYSBTd2lmdCBQYWNrYWdlXCIsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3N0YXJ0L3N3aWZ0LXBhY2thZ2VgLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogXCJNaWdyYXRlXCIsXG4gICAgICAgICAgY29sbGFwc2VkOiB0cnVlLFxuICAgICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IFwiQW4gWGNvZGUgcHJvamVjdFwiLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvc3RhcnQvbWlncmF0ZS94Y29kZS1wcm9qZWN0YCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IFwiQSBTd2lmdCBQYWNrYWdlXCIsXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9zdGFydC9taWdyYXRlL3N3aWZ0LXBhY2thZ2VgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogXCJBbiBYY29kZUdlbiBwcm9qZWN0XCIsXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9zdGFydC9taWdyYXRlL3hjb2RlZ2VuLXByb2plY3RgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogXCJBIEJhemVsIHByb2plY3RcIixcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3N0YXJ0L21pZ3JhdGUvYmF6ZWwtcHJvamVjdGAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgIF0sXG4gICAgICAgIH0sXG4gICAgICBdLFxuICAgIH0sXG4gICAge1xuICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+RGV2ZWxvcCAke2N1YmUwMkljb24oKX08L3NwYW4+YCxcbiAgICAgIGl0ZW1zOiBbXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj5Qcm9qZWN0cyAke2NvZGUwMkljb24oKX08L3NwYW4+YCxcbiAgICAgICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvcHJvamVjdHNgLFxuICAgICAgICAgIGl0ZW1zOiBbXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IFwiTWFuaWZlc3RzXCIsXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL21hbmlmZXN0c2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBcIkRpcmVjdG9yeSBzdHJ1Y3R1cmVcIixcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvZGlyZWN0b3J5LXN0cnVjdHVyZWAsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBcIkVkaXRpbmdcIixcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvZWRpdGluZ2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBcIkRlcGVuZGVuY2llc1wiLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy9kZXBlbmRlbmNpZXNgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogXCJDb2RlIHNoYXJpbmdcIixcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvY29kZS1zaGFyaW5nYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IFwiU3ludGhlc2l6ZWQgZmlsZXNcIixcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvc3ludGhlc2l6ZWQtZmlsZXNgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogXCJEeW5hbWljIGNvbmZpZ3VyYXRpb25cIixcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvZHluYW1pYy1jb25maWd1cmF0aW9uYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IFwiVGVtcGxhdGVzXCIsXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL3RlbXBsYXRlc2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBcIlBsdWdpbnNcIixcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvcGx1Z2luc2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBcIkhhc2hpbmdcIixcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvaGFzaGluZ2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBcIlRoZSBjb3N0IG9mIGNvbnZlbmllbmNlXCIsXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL3Byb2plY3RzL2Nvc3Qtb2YtY29udmVuaWVuY2VgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogXCJNb2R1bGFyIGFyY2hpdGVjdHVyZVwiLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZGV2ZWxvcC9wcm9qZWN0cy90bWEtYXJjaGl0ZWN0dXJlYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IFwiQmVzdCBwcmFjdGljZXNcIixcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvcHJvamVjdHMvYmVzdC1wcmFjdGljZXNgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICBdLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+QnVpbGQgJHtkYXRhSWNvbigpfTwvc3Bhbj5gLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL2J1aWxkYCxcbiAgICAgICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICAgICAgaXRlbXM6IFtcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+Q2FjaGU8L3NwYW4+YCxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvYnVpbGQvY2FjaGVgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICBdLFxuICAgICAgICB9LFxuICAgICAgICB7XG4gICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+VGVzdCAke2NoZWNrQ2lyY2xlSWNvbigpfTwvc3Bhbj5gLFxuICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL3Rlc3RgLFxuICAgICAgICAgIGNvbGxhcHNlZDogdHJ1ZSxcbiAgICAgICAgICBpdGVtczogW1xuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj5TbWFydCBydW5uZXI8L3NwYW4+YCxcbiAgICAgICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL2RldmVsb3AvdGVzdC9zbWFydC1ydW5uZXJgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogYDxzcGFuIHN0eWxlPVwiZGlzcGxheTogZmxleDsgZmxleC1kaXJlY3Rpb246IHJvdzsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA3cHg7XCI+Rmxha2luZXNzPC9zcGFuPmAsXG4gICAgICAgICAgICAgIGxpbms6IGAvJHtsb2NhbGV9L2d1aWRlcy9kZXZlbG9wL3Rlc3QvZmxha2luZXNzYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgXSxcbiAgICAgICAgfSxcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPkluc3BlY3QgJHttaWNyb3Njb3BlSWNvbigpfTwvc3Bhbj5gLFxuICAgICAgICAgIGNvbGxhcHNlZDogdHJ1ZSxcbiAgICAgICAgICBpdGVtczogW1xuICAgICAgICAgICAge1xuICAgICAgICAgICAgICB0ZXh0OiBcIkltcGxpY2l0IGRlcGVuZGVuY2llc1wiLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZGV2ZWxvcC9pbnNwZWN0L2ltcGxpY2l0LWRlcGVuZGVuY2llc2AsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgIF0sXG4gICAgICAgIH0sXG4gICAgICAgIHtcbiAgICAgICAgICB0ZXh0OiBgPHNwYW4gc3R5bGU9XCJkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogcm93OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDdweDtcIj5BdXRvbWF0ZSAke2Nsb3VkQmxhbmswMkljb24oKX08L3NwYW4+YCxcbiAgICAgICAgICBjb2xsYXBzZWQ6IHRydWUsXG4gICAgICAgICAgaXRlbXM6IFtcbiAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgdGV4dDogYENvbnRpbnVvdXMgSW50ZWdyYXRpb25gLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZGV2ZWxvcC9hdXRvbWF0ZS9jb250aW51b3VzLWludGVncmF0aW9uYCxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPldvcmtmbG93cyAke2NvbWluZ1Nvb25CYWRnZSgpfTwvc3Bhbj5gLFxuICAgICAgICAgICAgICBsaW5rOiBgLyR7bG9jYWxlfS9ndWlkZXMvZGV2ZWxvcC9hdXRvbWF0ZS93b3JrZmxvd3NgLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICBdLFxuICAgICAgICB9LFxuICAgICAgXSxcbiAgICB9LFxuICAgIHtcbiAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPlNoYXJlICR7Y3ViZTAxSWNvbigpfTwvc3Bhbj5gLFxuICAgICAgaXRlbXM6IFtcbiAgICAgICAge1xuICAgICAgICAgIHRleHQ6IGA8c3BhbiBzdHlsZT1cImRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiByb3c7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogN3B4O1wiPlByZXZpZXdzICR7eGNvZGVQcm9qQ29tcGF0aWJsZUJhZGdlKCl9PC9zcGFuPmAsXG4gICAgICAgICAgbGluazogYC8ke2xvY2FsZX0vZ3VpZGVzL3NoYXJlL3ByZXZpZXdzYCxcbiAgICAgICAgfSxcbiAgICAgIF0sXG4gICAgfSxcbiAgXTtcbn1cbiIsICJjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSA9IFwiL1VzZXJzL3BlcGljcmZ0L3NyYy9naXRodWIuY29tL3R1aXN0L3R1aXN0L2RvY3MvLnZpdGVwcmVzcy9kYXRhXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ZpbGVuYW1lID0gXCIvVXNlcnMvcGVwaWNyZnQvc3JjL2dpdGh1Yi5jb20vdHVpc3QvdHVpc3QvZG9jcy8udml0ZXByZXNzL2RhdGEvY2xpLmpzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ltcG9ydF9tZXRhX3VybCA9IFwiZmlsZTovLy9Vc2Vycy9wZXBpY3JmdC9zcmMvZ2l0aHViLmNvbS90dWlzdC90dWlzdC9kb2NzLy52aXRlcHJlc3MvZGF0YS9jbGkuanNcIjtpbXBvcnQgeyAkIH0gZnJvbSBcImV4ZWNhXCI7XG5pbXBvcnQgeyB0ZW1wb3JhcnlEaXJlY3RvcnlUYXNrIH0gZnJvbSBcInRlbXB5XCI7XG5pbXBvcnQgKiBhcyBwYXRoIGZyb20gXCJub2RlOnBhdGhcIjtcbmltcG9ydCB7IGZpbGVVUkxUb1BhdGggfSBmcm9tIFwibm9kZTp1cmxcIjtcbmltcG9ydCBlanMgZnJvbSBcImVqc1wiO1xuXG4vLyBSb290IGRpcmVjdG9yeVxuY29uc3QgX19kaXJuYW1lID0gcGF0aC5kaXJuYW1lKGZpbGVVUkxUb1BhdGgoaW1wb3J0Lm1ldGEudXJsKSk7XG5jb25zdCByb290RGlyZWN0b3J5ID0gcGF0aC5qb2luKF9fZGlybmFtZSwgXCIuLi8uLi8uLlwiKTtcblxuLy8gU2NoZW1hXG5hd2FpdCAkYHN3aWZ0IGJ1aWxkIC0tcHJvZHVjdCBQcm9qZWN0RGVzY3JpcHRpb24gLS1jb25maWd1cmF0aW9uIGRlYnVnIC0tcGFja2FnZS1wYXRoICR7cm9vdERpcmVjdG9yeX1gO1xuYXdhaXQgJGBzd2lmdCBidWlsZCAtLXByb2R1Y3QgdHVpc3QgLS1jb25maWd1cmF0aW9uIGRlYnVnIC0tcGFja2FnZS1wYXRoICR7cm9vdERpcmVjdG9yeX1gO1xudmFyIGR1bXBlZENMSVNjaGVtYTtcbmF3YWl0IHRlbXBvcmFyeURpcmVjdG9yeVRhc2soYXN5bmMgKHRtcERpcikgPT4ge1xuICAvLyBJJ20gcGFzc2luZyAtLXBhdGggdG8gc2FuZGJveCB0aGUgZXhlY3V0aW9uIHNpbmNlIHdlIGFyZSBvbmx5IGludGVyZXN0ZWQgaW4gdGhlIHNjaGVtYSBhbmQgbm90aGluZyBlbHNlLlxuICBkdW1wZWRDTElTY2hlbWEgPVxuICAgIGF3YWl0ICRgJHtwYXRoLmpvaW4ocm9vdERpcmVjdG9yeSwgXCIuYnVpbGQvZGVidWcvdHVpc3RcIil9IC0tZXhwZXJpbWVudGFsLWR1bXAtaGVscCAtLXBhdGggJHt0bXBEaXJ9YDtcbn0pO1xuY29uc3QgeyBzdGRvdXQgfSA9IGR1bXBlZENMSVNjaGVtYTtcbmV4cG9ydCBjb25zdCBzY2hlbWEgPSBKU09OLnBhcnNlKHN0ZG91dCk7XG5cbi8vIFBhdGhzXG5mdW5jdGlvbiB0cmF2ZXJzZShjb21tYW5kLCBwYXRocykge1xuICBwYXRocy5wdXNoKHtcbiAgICBwYXJhbXM6IHsgY29tbWFuZDogY29tbWFuZC5saW5rLnNwbGl0KFwiY2xpL1wiKVsxXSB9LFxuICAgIGNvbnRlbnQ6IGNvbnRlbnQoY29tbWFuZCksXG4gIH0pO1xuICAoY29tbWFuZC5pdGVtcyA/PyBbXSkuZm9yRWFjaCgoc3ViQ29tbWFuZCkgPT4ge1xuICAgIHRyYXZlcnNlKHN1YkNvbW1hbmQsIHBhdGhzKTtcbiAgfSk7XG59XG5cbmNvbnN0IHRlbXBsYXRlID0gZWpzLmNvbXBpbGUoXG4gIGBcbiMgPCU9IGNvbW1hbmQuZnVsbENvbW1hbmQgJT5cbjwlPSBjb21tYW5kLnNwZWMuYWJzdHJhY3QgJT5cbjwlIGlmIChjb21tYW5kLnNwZWMuYXJndW1lbnRzICYmIGNvbW1hbmQuc3BlYy5hcmd1bWVudHMubGVuZ3RoID4gMCkgeyAlPlxuIyMgQXJndW1lbnRzXG48JSBjb21tYW5kLnNwZWMuYXJndW1lbnRzLmZvckVhY2goZnVuY3Rpb24oYXJnKSB7ICU+XG4jIyMgPCUtIGFyZy52YWx1ZU5hbWUgJT4gPCUtIChhcmcuaXNPcHRpb25hbCkgPyBcIjxCYWRnZSB0eXBlPSdpbmZvJyB0ZXh0PSdPcHRpb25hbCcgLz5cIiA6IFwiXCIgJT4gPCUtIChhcmcuaXNEZXByZWNhdGVkKSA/IFwiPEJhZGdlIHR5cGU9J3dhcm5pbmcnIHRleHQ9J0RlcHJlY2F0ZWQnIC8+XCIgOiBcIlwiICU+XG48JSBpZiAoYXJnLmVudlZhcikgeyAlPlxuKipFbnZpcm9ubWVudCB2YXJpYWJsZSoqIFxcYDwlLSBhcmcuZW52VmFyICU+XFxgXG48JSB9ICU+XG48JS0gYXJnLmFic3RyYWN0ICU+XG48JSBpZiAoYXJnLmtpbmQgPT09IFwicG9zaXRpb25hbFwiKSB7IC0lPlxuXFxgXFxgXFxgYmFzaFxuPCUtIGNvbW1hbmQuZnVsbENvbW1hbmQgJT4gWzwlLSBhcmcudmFsdWVOYW1lICU+XVxuXFxgXFxgXFxgXG48JSB9IGVsc2UgaWYgKGFyZy5raW5kID09PSBcImZsYWdcIikgeyAtJT5cblxcYFxcYFxcYGJhc2hcbjwlIGFyZy5uYW1lcy5mb3JFYWNoKGZ1bmN0aW9uKG5hbWUpIHsgLSU+XG48JSBpZiAobmFtZS5raW5kID09PSBcImxvbmdcIikgeyAtJT5cbjwlLSBjb21tYW5kLmZ1bGxDb21tYW5kICU+IC0tPCUtIG5hbWUubmFtZSAlPlxuPCUgfSBlbHNlIHsgLSU+XG48JS0gY29tbWFuZC5mdWxsQ29tbWFuZCAlPiAtPCUtIG5hbWUubmFtZSAlPlxuPCUgfSAtJT5cbjwlIH0pIC0lPlxuXFxgXFxgXFxgXG48JSB9IGVsc2UgaWYgKGFyZy5raW5kID09PSBcIm9wdGlvblwiKSB7IC0lPlxuXFxgXFxgXFxgYmFzaFxuPCUgYXJnLm5hbWVzLmZvckVhY2goZnVuY3Rpb24obmFtZSkgeyAtJT5cbjwlIGlmIChuYW1lLmtpbmQgPT09IFwibG9uZ1wiKSB7IC0lPlxuPCUtIGNvbW1hbmQuZnVsbENvbW1hbmQgJT4gLS08JS0gbmFtZS5uYW1lICU+IFs8JS0gYXJnLnZhbHVlTmFtZSAlPl1cbjwlIH0gZWxzZSB7IC0lPlxuPCUtIGNvbW1hbmQuZnVsbENvbW1hbmQgJT4gLTwlLSBuYW1lLm5hbWUgJT4gWzwlLSBhcmcudmFsdWVOYW1lICU+XVxuPCUgfSAtJT5cbjwlIH0pIC0lPlxuXFxgXFxgXFxgXG48JSB9IC0lPlxuPCUgfSk7IC0lPlxuPCUgfSAtJT5cbmAsXG4gIHt9LFxuKTtcblxuZnVuY3Rpb24gY29udGVudChjb21tYW5kKSB7XG4gIGNvbnN0IGVudlZhclJlZ2V4ID0gL1xcKGVudjpcXHMqKFteKV0rKVxcKS87XG4gIGNvbnN0IGNvbnRlbnQgPSB0ZW1wbGF0ZSh7XG4gICAgY29tbWFuZDoge1xuICAgICAgLi4uY29tbWFuZCxcbiAgICAgIHNwZWM6IHtcbiAgICAgICAgLi4uY29tbWFuZC5zcGVjLFxuICAgICAgICBhcmd1bWVudHM6IGNvbW1hbmQuc3BlYy5hcmd1bWVudHMubWFwKChhcmcpID0+IHtcbiAgICAgICAgICBjb25zdCBlbnZWYXJNYXRjaCA9IGFyZy5hYnN0cmFjdC5tYXRjaChlbnZWYXJSZWdleCk7XG4gICAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICAgIC4uLmFyZyxcbiAgICAgICAgICAgIGVudlZhcjogZW52VmFyTWF0Y2ggPyBlbnZWYXJNYXRjaFsxXSA6IHVuZGVmaW5lZCxcbiAgICAgICAgICAgIGlzRGVwcmVjYXRlZDpcbiAgICAgICAgICAgICAgYXJnLmFic3RyYWN0LmluY2x1ZGVzKFwiW0RlcHJlY2F0ZWRdXCIpIHx8XG4gICAgICAgICAgICAgIGFyZy5hYnN0cmFjdC5pbmNsdWRlcyhcIltkZXByZWNhdGVkXVwiKSxcbiAgICAgICAgICAgIGFic3RyYWN0OiBhcmcuYWJzdHJhY3RcbiAgICAgICAgICAgICAgLnJlcGxhY2UoZW52VmFyUmVnZXgsIFwiXCIpXG4gICAgICAgICAgICAgIC5yZXBsYWNlKFwiW0RlcHJlY2F0ZWRdXCIsIFwiXCIpXG4gICAgICAgICAgICAgIC5yZXBsYWNlKFwiW2RlcHJlY2F0ZWRdXCIsIFwiXCIpXG4gICAgICAgICAgICAgIC50cmltKClcbiAgICAgICAgICAgICAgLnJlcGxhY2UoLzwoW14+XSspPi9nLCBcIlxcXFw8JDFcXFxcPlwiKSxcbiAgICAgICAgICB9O1xuICAgICAgICB9KSxcbiAgICAgIH0sXG4gICAgfSxcbiAgfSk7XG4gIHJldHVybiBjb250ZW50O1xufVxuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gcGF0aHMobG9jYWxlKSB7XG4gIGxldCBwYXRocyA9IFtdO1xuICAoYXdhaXQgbG9hZERhdGEobG9jYWxlKSkuaXRlbXMuZm9yRWFjaCgoY29tbWFuZCkgPT4ge1xuICAgIHRyYXZlcnNlKGNvbW1hbmQsIHBhdGhzKTtcbiAgfSk7XG4gIHJldHVybiBwYXRocztcbn1cblxuZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIGxvYWREYXRhKGxvY2FsZSkge1xuICBmdW5jdGlvbiBwYXJzZUNvbW1hbmQoXG4gICAgY29tbWFuZCxcbiAgICBwYXJlbnRDb21tYW5kID0gXCJ0dWlzdFwiLFxuICAgIHBhcmVudFBhdGggPSBgLyR7bG9jYWxlfS9jbGkvYCxcbiAgKSB7XG4gICAgY29uc3Qgb3V0cHV0ID0ge1xuICAgICAgdGV4dDogY29tbWFuZC5jb21tYW5kTmFtZSxcbiAgICAgIGZ1bGxDb21tYW5kOiBwYXJlbnRDb21tYW5kICsgXCIgXCIgKyBjb21tYW5kLmNvbW1hbmROYW1lLFxuICAgICAgbGluazogcGF0aC5qb2luKHBhcmVudFBhdGgsIGNvbW1hbmQuY29tbWFuZE5hbWUpLFxuICAgICAgc3BlYzogY29tbWFuZCxcbiAgICB9O1xuICAgIGlmIChjb21tYW5kLnN1YmNvbW1hbmRzICYmIGNvbW1hbmQuc3ViY29tbWFuZHMubGVuZ3RoICE9PSAwKSB7XG4gICAgICBvdXRwdXQuaXRlbXMgPSBjb21tYW5kLnN1YmNvbW1hbmRzLm1hcCgoc3ViY29tbWFuZCkgPT4ge1xuICAgICAgICByZXR1cm4gcGFyc2VDb21tYW5kKFxuICAgICAgICAgIHN1YmNvbW1hbmQsXG4gICAgICAgICAgcGFyZW50Q29tbWFuZCArIFwiIFwiICsgY29tbWFuZC5jb21tYW5kTmFtZSxcbiAgICAgICAgICBwYXRoLmpvaW4ocGFyZW50UGF0aCwgY29tbWFuZC5jb21tYW5kTmFtZSksXG4gICAgICAgICk7XG4gICAgICB9KTtcbiAgICB9XG5cbiAgICByZXR1cm4gb3V0cHV0O1xuICB9XG5cbiAgY29uc3Qge1xuICAgIGNvbW1hbmQ6IHsgc3ViY29tbWFuZHMgfSxcbiAgfSA9IHNjaGVtYTtcblxuICByZXR1cm4ge1xuICAgIHRleHQ6IFwiQ0xJXCIsXG4gICAgaXRlbXM6IHN1YmNvbW1hbmRzXG4gICAgICAubWFwKChjb21tYW5kKSA9PiB7XG4gICAgICAgIHJldHVybiB7XG4gICAgICAgICAgLi4ucGFyc2VDb21tYW5kKGNvbW1hbmQpLFxuICAgICAgICAgIGNvbGxhcHNlZDogdHJ1ZSxcbiAgICAgICAgfTtcbiAgICAgIH0pXG4gICAgICAuc29ydCgoYSwgYikgPT4gYS50ZXh0LmxvY2FsZUNvbXBhcmUoYi50ZXh0KSksXG4gIH07XG59XG4iXSwKICAibWFwcGluZ3MiOiAiO0FBQXdW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QUFRLENBQUMsQ0FBQztBQUFBO0FBRTlGLElBQUcsY0FBVSxlQUFlLFNBQVM7QUFBQSxFQUN2QztBQUFBLEVBQ0EsYUFBYTtBQUFBLElBQ1gsTUFBTTtBQUFBLElBQ04sUUFBUTtBQUFBLE1BQ04sVUFBVTtBQUFBLElBQ1o7QUFBQSxJQUNBLFVBQVU7QUFBQSxNQUNSLFNBQVM7QUFBQSxJQUNYO0FBQUEsSUFDQSxhQUFhO0FBQUEsTUFDWCxFQUFFLE1BQU0sVUFBVSxNQUFNLGlDQUFpQztBQUFBLE1BQ3pELEVBQUUsTUFBTSxLQUFLLE1BQU0sd0JBQXdCO0FBQUEsTUFDM0MsRUFBRSxNQUFNLFlBQVksTUFBTSwrQkFBK0I7QUFBQSxNQUN6RDtBQUFBLFFBQ0UsTUFBTTtBQUFBLFFBQ04sTUFBTTtBQUFBLE1BQ1I7QUFBQSxJQUNGO0FBQUEsSUFDQSxRQUFRO0FBQUEsTUFDTixTQUFTO0FBQUEsTUFDVCxXQUFXO0FBQUEsSUFDYjtBQUFBLEVBQ0Y7QUFDRixDQUFDOyIsCiAgIm5hbWVzIjogWyJwYXRoIiwgImZzIiwgInBhdGgiLCAiZmciLCAiZnMiLCAiX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUiLCAibG9hZERhdGEiLCAiX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUiLCAiZmciLCAiZnMiLCAibG9hZERhdGEiLCAicHJvamVjdERlc2NyaXB0aW9uU2lkZWJhciIsICJwYXRoIiwgImxvYWREYXRhIiwgImZpbGVVUkxUb1BhdGgiLCAiX192aXRlX2luamVjdGVkX29yaWdpbmFsX2Rpcm5hbWUiLCAiX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ltcG9ydF9tZXRhX3VybCIsICJfX2Rpcm5hbWUiLCAiZmlsZVVSTFRvUGF0aCIsICJsb2FkRGF0YSIsICJfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSJdCn0K
