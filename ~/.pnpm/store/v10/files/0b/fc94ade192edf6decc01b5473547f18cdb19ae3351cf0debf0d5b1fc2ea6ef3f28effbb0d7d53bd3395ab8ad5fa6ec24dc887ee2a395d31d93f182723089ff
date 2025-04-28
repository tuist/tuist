const safeJSON = {
    parse(v) {
        try {
            return {
                error: false,
                data: JSON.parse(v),
            };
        }
        catch (e) {
            return {
                error: true,
                message: e.message ? String(e.message) : 'Unknown Error',
            };
        }
    },
};

export { safeJSON };
