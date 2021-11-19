import React from 'react';
import {
  ApolloClient,
  InMemoryCache,
  ApolloProvider,
  useQuery,
  gql,
} from '@apollo/client';
import graphqlClient from './graphqlClient';

interface GraphqlProviderProps {
  children?: React.ReactNode;
}

const GraphqlProvider = ({ children }: GraphqlProviderProps) => {
  return (
    <ApolloProvider client={graphqlClient}>{children}</ApolloProvider>
  );
};

export default GraphqlProvider;
