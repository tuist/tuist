import React, { useContext, useEffect, useRef } from 'react';
import {
  Card,
  Icon,
  Page,
  Pagination,
  ResourceItem,
  ResourceList,
  Stack,
  TextStyle,
} from '@shopify/polaris';
import { ClockMinor, CalendarMinor } from '@shopify/polaris-icons';
import { HomeStoreContext } from '@/stores/HomeStore';
import DashboardPageStore from './DashboardPageStore';
import { useApolloClient } from '@apollo/client';
import { CommandEventDetail } from '@/models/CommandEventDetail';
import { observer } from 'mobx-react-lite';
import { useNavigate } from 'react-router-dom';
import relativeDate from '@/utilities/relativeDate';

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
  }, [projectStore.project]);

  const renderItem = (item: CommandEventDetail) => {
    return (
      <ResourceItem
        id={item.id}
        onClick={() => {
          navigate(`command_event/${item.id}`);
        }}
      >
        <Stack vertical={true}>
          <TextStyle variation="code">
            {item.commandArguments}
          </TextStyle>
          <Stack vertical={false} spacing={'loose'}>
            <Stack vertical={false} spacing={'baseTight'}>
              <Icon source={ClockMinor} />
              <TextStyle>
                {Math.ceil(item.duration / 1000)} s
              </TextStyle>
            </Stack>
            <Stack vertical={false} spacing={'baseTight'}>
              <Icon source={CalendarMinor} />
              <TextStyle>{relativeDate(item.createdAt)}</TextStyle>
            </Stack>
          </Stack>
        </Stack>
      </ResourceItem>
    );
  };

  return (
    <Page>
      <Card title="Runs">
        <Card.Section>
          <ResourceList
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
              dashboardPageStore.loadNextPage(
                projectStore.project.id,
              );
            }}
          />
        </Card.Section>
      </Card>
    </Page>
  );
});

export default DashboardPage;
