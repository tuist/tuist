const DEFAULT_TITLE = 'API';
const DEFAULT_VERSION = '1.0';
const addInfoObject = (definition) => ({
    ...definition,
    info: {
        ...definition.info,
        title: definition.info?.title ?? DEFAULT_TITLE,
        version: definition.info?.version ?? DEFAULT_VERSION,
    },
});

export { DEFAULT_TITLE, DEFAULT_VERSION, addInfoObject };
