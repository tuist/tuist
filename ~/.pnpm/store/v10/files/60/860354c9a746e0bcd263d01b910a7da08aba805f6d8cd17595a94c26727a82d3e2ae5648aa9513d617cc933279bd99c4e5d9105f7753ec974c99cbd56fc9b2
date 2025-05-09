const t = {
  apiKeyCookie: {
    label: "API Key in Cookies",
    payload: {
      type: "apiKey",
      in: "cookie",
      nameKey: "apiKeyCookie"
    }
  },
  apiKeyHeader: {
    label: "API Key in Headers",
    payload: {
      type: "apiKey",
      in: "header",
      nameKey: "apiKeyHeader"
    }
  },
  apiKeyQuery: {
    label: "API Key in Query Params",
    payload: {
      type: "apiKey",
      in: "query",
      nameKey: "apiKeyQuery"
    }
  },
  httpBasic: {
    label: "HTTP Basic",
    payload: {
      type: "http",
      scheme: "basic",
      nameKey: "httpBasic"
    }
  },
  httpBearer: {
    label: "HTTP Bearer",
    payload: {
      type: "http",
      scheme: "bearer",
      nameKey: "httpBearer"
    }
  },
  oauth2Implicit: {
    label: "Oauth2 Implicit Flow",
    payload: {
      type: "oauth2",
      nameKey: "oauth2Implicit",
      flows: {
        implicit: {
          type: "implicit"
        }
      }
    }
  },
  oauth2Password: {
    label: "Oauth2 Password Flow",
    payload: {
      type: "oauth2",
      nameKey: "oauth2Password",
      flows: {
        password: {
          type: "password"
        }
      }
    }
  },
  oauth2ClientCredentials: {
    label: "Oauth2 Client Credentials",
    payload: {
      type: "oauth2",
      nameKey: "oauth2ClientCredentials",
      flows: {
        clientCredentials: {
          type: "clientCredentials"
        }
      }
    }
  },
  oauth2AuthorizationFlow: {
    label: "Oauth2 Authorization Code",
    payload: {
      type: "oauth2",
      nameKey: "oauth2AuthorizationFlow",
      flows: {
        authorizationCode: {
          type: "authorizationCode"
        }
      }
    }
  }
}, o = Object.entries(t), i = o.map(
  ([e, a]) => ({
    id: e,
    isDeletable: !1,
    ...a
  })
);
export {
  t as ADD_AUTH_DICT,
  i as ADD_AUTH_OPTIONS
};
