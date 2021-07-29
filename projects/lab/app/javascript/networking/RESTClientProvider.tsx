import React, { useEffect, useContext } from 'react';
import type { AxiosInstance } from 'axios';
import restClient from './restClient';

const HTTPClientContext =
  React.createContext<AxiosInstance>(restClient);

const RESTClientProvider = ({ children }) => {
  useEffect(() => {
    restClient.interceptors.request.use((config) => {
      const csrfToken = document
        .querySelector('meta[name=csrf-token]')
        .getAttribute('content');
      /* eslint-disable no-param-reassign */
      config.headers['X-CSRF-Token'] = csrfToken;
      config.headers['Content-Type'] = 'application/json';
      config.withCredentials = true;
      /* eslint-enable no-param-reassign */
      return config;
    });
  }, [restClient]);

  return (
    <HTTPClientContext.Provider value={restClient}>
      {children}
    </HTTPClientContext.Provider>
  );
};
const useRestClient = () => useContext(HTTPClientContext);

export { useRestClient, restClient };
export default RESTClientProvider;
