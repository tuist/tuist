/* eslint-disable global-require */
// only needed if you want to purge
module.exports = {
  plugins: [
    require("postcss-import"),
    require("postcss-flexbugs-fixes"),
    require("tailwindcss")("./app/javascript/styles/tailwind.config.js"),
    require("autoprefixer"),
    require("postcss-preset-env")({
      autoprefixer: {
        flexbox: "no-2009",
      },
      stage: 3,
    }),
  ],
};
