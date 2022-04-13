import React, { useContext, useEffect, useRef } from 'react';
import {
  Card,
  Icon,
  Page,
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

const Dashboard = observer(() => {
  const { projectStore } = useContext(HomeStoreContext);
  const client = useApolloClient();
  const dashboardPageStore = useRef(
    new DashboardPageStore(client),
  ).current;

  useEffect(() => {
    if (projectStore.project?.id == null) {
      return;
    }
    dashboardPageStore.load(projectStore.project.id);
  }, [projectStore.project]);

  const relativeTimeFormatter = new Intl.RelativeTimeFormat('en-GB', {
    numeric: 'auto',
  });

  const getRelativeDate = (date: Date) => {
    const currentDate = new Date();
    if (date.getUTCDate() === currentDate.getUTCDate()) {
      if (date.getUTCHours() === currentDate.getUTCHours()) {
        return relativeTimeFormatter.format(
          date.getUTCMinutes() - currentDate.getUTCMinutes(),
          'minutes',
        );
      }
      return relativeTimeFormatter.format(
        date.getUTCHours() - currentDate.getUTCHours(),
        'hours',
      );
    }
    return date.toDateString();
  };

  const renderItem = (item: CommandEventDetail) => {
    return (
      <ResourceItem id={item.id} onClick={() => {}}>
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
              <TextStyle>{getRelativeDate(item.createdAt)}</TextStyle>
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
        </Card.Section>
      </Card>
    </Page>
  );
});

export default Dashboard;
