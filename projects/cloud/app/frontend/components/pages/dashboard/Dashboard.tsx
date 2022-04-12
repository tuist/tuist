import React, { useContext, useEffect, useRef } from 'react';
import {
  Card,
  Page,
  ResourceList,
  TextStyle,
} from '@shopify/polaris';
import { HomeStoreContext } from '@/stores/HomeStore';
import DashboardPageStore from './DashboardPageStore';
import { useApolloClient } from '@apollo/client';
import { CommandEventDetail } from '@/models/CommandEventDetail';
import { observer } from 'mobx-react-lite';

const Dashboard = observer(() => {
  const { projectStore } = useContext(HomeStoreContext);
  const client = useApolloClient();
  const dashboardPageStore = useRef(
    new DashboardPageStore(client),
  ).current;

  useEffect(() => {
    console.log(projectStore.project?.id);
    if (projectStore.project?.id == null) {
      return;
    }
    dashboardPageStore.load(projectStore.project.id);
  }, [projectStore.project]);

  const renderItem = (item: CommandEventDetail) => {
    return <TextStyle>{item.commandArguments}</TextStyle>;
  };

  return (
    <Page>
      <Card title="Runs">
        <Card.Section>
          <ResourceList
            items={dashboardPageStore.commandEvents}
            renderItem={renderItem}
          />
        </Card.Section>
      </Card>
    </Page>
  );
});

export default Dashboard;
