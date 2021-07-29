/* eslint-disable @typescript-eslint/ban-ts-comment */
// @ts-nocheck

import React from 'react';
import {
  ApolloClient,
  InMemoryCache,
  ApolloProvider,
  concat,
} from '@apollo/client';
import { ApolloLink } from 'apollo-link';
import { createHttpLink } from 'apollo-link-http';

const httpLink = createHttpLink({ uri: '/graphql' });

const middlewareLink = new ApolloLink((operation, forward) => {
  const csrfToken = document
    .querySelector('meta[name=csrf-token]')
    .getAttribute('content');
  operation.setContext({
    credentials: 'same-origin',
    headers: { 'X-CSRF-Token': csrfToken },
  });
  return forward(operation);
});

const defaultOptions = {
  watchQuery: {
    fetchPolicy: 'no-cache',
    errorPolicy: 'ignore',
  },
  query: {
    fetchPolicy: 'no-cache',
    errorPolicy: 'all',
  },
};

const client = new ApolloClient({
  link: concat(middlewareLink, httpLink),
  uri: `${BASE_URL}/graphql`,
  cache: new InMemoryCache(),
  defaultOptions,
});

const ClientProvider = ({
  children,
}: {
  children: React.ReactNode;
}) => <ApolloProvider client={client}>{children}</ApolloProvider>;

export default ClientProvider;
