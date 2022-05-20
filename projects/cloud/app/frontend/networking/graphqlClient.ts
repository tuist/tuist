import { ApolloClient, InMemoryCache, concat } from '@apollo/client';
import { baseURL } from '@/shared/constants';

import { ApolloLink } from 'apollo-link';
import { createHttpLink } from 'apollo-link-http';
import logoutLink from './logoutLink';
import csrfToken from '@/utilities/csrfToken';

const httpLink = createHttpLink({ uri: '/graphql' });
const middlewareLink = new ApolloLink((operation, forward) => {
  operation.setContext({
    credentials: 'same-origin',
    headers: { 'X-CSRF-Token': csrfToken },
  });
  return forward(operation);
});

const hasSubscriptionOperation = ({ query: { definitions } }) => {
  return definitions.some(
    ({ kind, operation }) =>
      kind === 'OperationDefinition' && operation === 'subscription',
  );
};

const link = ApolloLink.split(
  hasSubscriptionOperation,
  // @ts-ignore
  concat(
    logoutLink,
    // @ts-ignore
    middlewareLink,
  ),
  // @ts-ignore
  concat(logoutLink, concat(middlewareLink, httpLink)),
);

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

const graphqlClient = new ApolloClient({
  // @ts-ignore
  link,
  uri: `${baseURL}/graphql`,
  cache: new InMemoryCache(),
  // @ts-ignore
  defaultOptions: defaultOptions,
});

export default graphqlClient;
