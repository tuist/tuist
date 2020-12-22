module.exports = {
    distDir: 'build',
    target: 'serverless',
    publicRuntimeConfig: {
        // add your public runtime environment variables here with NEXT_PUBLIC_*** prefix
    },
    excludeFile: (str) => {
        console.log(str);
        return /\*.{spec,test}.{ts,tsx}/.test(str);
    },
    webpack: (config, { isServer }) => {
        // Fixes npm packages that depend on `fs` module
        if (!isServer) {
            config.node = { fs: 'empty' };
        }
        return config;
    },
};
