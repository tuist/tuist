import React, { useContext } from 'react';
import { Frame, Loading, EmptyState, Card } from '@shopify/polaris';
import { useMeQuery } from '../graphql/types';
import type { User } from '../graphql/types';

type Environment = {
  user: Pick<User, 'email' | 'avatarUrl'>;
};

const EnvironmentContext = React.createContext<
  Environment | undefined
>(undefined);

const EnvironmentProvider = ({
  children,
}: {
  children: React.ReactNode;
}) => {
  const { data, loading } = useMeQuery();
  if (loading) {
    return (
      <Frame>
        <Loading />
      </Frame>
    );
  }
  if (data) {
    const environment = {
      user: data.me,
    };
    return (
      <EnvironmentContext.Provider value={environment}>
        {children}
      </EnvironmentContext.Provider>
    );
  }
  return (
    <Frame>
      <Card sectioned>
        <EmptyState
          heading="Manage your inventory transfers"
          action={{ content: 'Add transfer' }}
          secondaryAction={{
            content: 'Learn more',
            url: 'https://help.shopify.com',
          }}
          image="https://cdn.shopify.com/s/files/1/0262/4071/2726/files/emptystate-files.png"
        >
          <p>
            Track and receive your incoming inventory from suppliers.
          </p>
        </EmptyState>
      </Card>
    </Frame>
  );
};

export const useEnvironment = (): Environment =>
  useContext(EnvironmentContext);

export default EnvironmentProvider;
