import React from 'react';
import { Card, Stack, Select } from '@shopify/polaris';
import { LineChart } from '@shopify/polaris-viz';
import { observer } from 'mobx-react-lite';
import ProjectStore from '@/stores/ProjectStore';
import DashboardPageStore from './DashboardPageStore';

interface CacheHitRateAveragesCardProps {
  projectStore: ProjectStore;
  dashboardPageStore: DashboardPageStore;
}

const CacheHitRateAveragesCard = observer(
  ({
    projectStore,
    dashboardPageStore,
  }: CacheHitRateAveragesCardProps) => {
    return (
      <Card title="Average cache hit rate">
        <Card.Section>
          <Stack vertical distribution="center">
            <Stack>
              <Select
                label=""
                options={[
                  { label: 'cache warm', value: 'cache warm' },
                  { label: 'generate', value: 'generate' },
                ]}
                onChange={(newValue) => {
                  if (projectStore.project?.id == null) {
                    return;
                  }
                  dashboardPageStore.cacheHitRateCommandName =
                    newValue;
                  dashboardPageStore.loadCacheHitRateAverages(
                    projectStore.project.id,
                  );
                }}
                value={dashboardPageStore.cacheHitRateCommandName}
              />
            </Stack>
            <LineChart
              isAnimated
              theme="Light"
              data={[
                {
                  data: dashboardPageStore.cacheHitRateAveragesData,
                  name: `${dashboardPageStore.cacheHitRateCommandName} average cache hit rate`,
                },
              ]}
              showLegend
              xAxisOptions={{
                hide: true,
              }}
              yAxisOptions={{
                labelFormatter: (value) => `${value} %`,
              }}
            />
          </Stack>
        </Card.Section>
      </Card>
    );
  },
);

export default CacheHitRateAveragesCard;
