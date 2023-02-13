import React from 'react';
import { Card, Stack, Select } from '@shopify/polaris';
import { LineChart } from '@shopify/polaris-viz';
import { observer } from 'mobx-react-lite';
import ProjectStore from '@/stores/ProjectStore';
import DashboardPageStore from './DashboardPageStore';

interface AverageCommandDurationCardProps {
  projectStore: ProjectStore;
  dashboardPageStore: DashboardPageStore;
}

const AverageCommandDurationCard = observer(
  ({
    projectStore,
    dashboardPageStore,
  }: AverageCommandDurationCardProps) => {
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
                  name: 'Average duration',
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
  },
);

export default AverageCommandDurationCard;
