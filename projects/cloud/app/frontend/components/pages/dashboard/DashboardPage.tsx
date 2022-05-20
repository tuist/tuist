import React, { useContext, useEffect, useRef } from 'react';
import {
  Card,
  Icon,
  Page,
  Pagination,
  ResourceItem,
  ResourceList,
  Select,
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
import { LineChart } from '@shopify/polaris-viz';

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

  const AverageCommandDurationCard = observer(() => {
    return (
      <Card title="Average command duration">
        <Card.Section>
          <Stack vertical distribution="center">
            <Stack>
              <Select
                label=""
                options={[
                  { label: 'build', value: 'build' },
                  { label: 'cache warm', value: 'cache warm' },
                  { label: 'fetch', value: 'fetch' },
                  { label: 'generate', value: 'generate' },
                  { label: 'test', value: 'test' },
                ]}
                onChange={(newValue) => {
                  if (projectStore.project?.id == null) {
                    return;
                  }
                  dashboardPageStore.commandName = newValue;
                  dashboardPageStore.loadCommandAverages(
                    projectStore.project.id,
                  );
                }}
                value={dashboardPageStore.commandName}
              />
            </Stack>
            <LineChart
              isAnimated
              theme="Light"
              data={[
                {
                  data: dashboardPageStore.commandAveragesData,
                  name: `${dashboardPageStore.commandName} average duration`,
                },
              ]}
              showLegend
              xAxisOptions={{
                hide: true,
              }}
              yAxisOptions={{
                labelFormatter: (value) => `${value} s`,
              }}
            />
          </Stack>
        </Card.Section>
      </Card>
    );
  });

  return (
    <Page>
      <AverageCommandDurationCard />
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
