import React, { useContext, useEffect, useRef } from 'react';
import {
  Card,
  Page,
  Pagination,
  ResourceItem,
  ResourceList,
  TextStyle,
} from '@shopify/polaris';
import { HomeStoreContext } from '@/stores/HomeStore';
import DashboardPageStore from './DashboardPageStore';
import { useApolloClient } from '@apollo/client';
import { CommandEventDetail } from '@/models/CommandEventDetail';
import { observer } from 'mobx-react-lite';
import { useNavigate } from 'react-router-dom';
import AverageCommandDurationCard from './AverageCommandDurationCard';
import CacheHitRateAveragesCard from './CacheHitRateAveragesCard';
import { CommandEventDetailItem } from './CommandEventDetailItem';

const DashboardPage = observer(() => {
  const { projectStore } = useContext(HomeStoreContext);
  const client = useApolloClient();
  const dashboardPageStore = useRef(
    new DashboardPageStore(client),
  ).current;
  const navigate = useNavigate();

  useEffect(() => {
    if (projectStore.project?.id == null) {
      return;
    }
    dashboardPageStore.loadNextPage(projectStore.project.id);
    dashboardPageStore.loadCommandAverages(projectStore.project.id);
    dashboardPageStore.loadCacheHitRateAverages(
      projectStore.project.id,
    );
  }, [projectStore.project]);

  const renderItem = (item: CommandEventDetail) => {
    return (
      <ResourceItem
        id={item.id}
        onClick={() => {
          navigate(`command_event/${item.id}`);
        }}
      >
        <CommandEventDetailItem item={item} />
      </ResourceItem>
    );
  };

  const RunsList = () => {
    return (
      <>
        <ResourceList
          loading={dashboardPageStore.isLoading}
          items={dashboardPageStore.commandEvents}
          renderItem={renderItem}
        />
        <Pagination
          hasPrevious={dashboardPageStore.hasPreviousPage}
          onPrevious={() => {
            if (projectStore.project?.id == null) {
              return;
            }
            dashboardPageStore.loadPreviousPage(
              projectStore.project.id,
            );
          }}
          hasNext={dashboardPageStore.hasNextPage}
          onNext={() => {
            if (projectStore.project?.id == null) {
              return;
            }
            dashboardPageStore.loadNextPage(projectStore.project.id);
          }}
        />
      </>
    );
  };

  return (
    <Page>
      <AverageCommandDurationCard
        projectStore={projectStore}
        dashboardPageStore={dashboardPageStore}
      />
      <CacheHitRateAveragesCard
        projectStore={projectStore}
        dashboardPageStore={dashboardPageStore}
      />
      <Card title="Runs">
        <Card.Section>
          {dashboardPageStore.commandEvents.length > 0 ||
          dashboardPageStore.isLoading ? (
            <RunsList />
          ) : (
            <TextStyle>
              You currently have no runs. Login to tuist cloud in your
              CLI and run a command.
            </TextStyle>
          )}
        </Card.Section>
      </Card>
    </Page>
  );
});

export default DashboardPage;
