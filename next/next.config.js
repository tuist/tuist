module.exports = {
    distDir: 'build',
    publicRuntimeConfig: {
        // add your public runtime environment variables here with NEXT_PUBLIC_*** prefix
    },
    excludeFile: (str) => {
        console.log(str);
        return /\*.{spec,test}.{ts,tsx}/.test(str);
    },
    webpack: (config) => {
        // extend your webpack configuration here
        return config;
    },
};
