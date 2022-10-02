import { CommandEventDetailItem } from '@/components/pages/dashboard/CommandEventDetailItem';
import { CommandEventDetail } from '@/models/CommandEventDetail';
import { Card, Stack, Text } from '@shopify/polaris';
import React from 'react';
import styles from './CommandEventDetailItemShowcase.module.scss';

interface MockDetailItemProps {
  commandArguments: string;
  duration: number;
  createdAt: Date;
  cacheHitRate?: number;
}

const mockDetailItem: (
  props: MockDetailItemProps,
) => CommandEventDetail = ({
  commandArguments,
  duration,
  createdAt,
  cacheHitRate,
}) => {
  return {
    clientId: 'client-id',
    commandArguments: commandArguments,
    createdAt,
    duration: duration,
    macosVersion: '13.3.0',
    tuistVersion: '3.3.0',
    swiftVersion: '5.4.0',
    id: 'command-event-id',
    name: '',
    subcommand: null,
    cacheableTargets: [],
    localCacheTargetHits: [],
    remoteCacheTargetHits: [],
    cacheHitRate: cacheHitRate ?? null,
  };
};

export const CommandEventDetailItemShowcase = () => {
  const items: CommandEventDetail[] = [
    mockDetailItem({
      commandArguments: 'generate MyApp',
      createdAt: new Date(),
      duration: 1240,
      cacheHitRate: 0.95,
    }),
    mockDetailItem({
      commandArguments: 'generate MyApp2',
      createdAt: new Date(),
      duration: 1240,
    }),
    mockDetailItem({
      commandArguments: 'generate MyApp3',
      createdAt: new Date(),
      duration: 1240,
      cacheHitRate: 0.74,
    }),
    mockDetailItem({
      commandArguments: 'generate MyApp4',
      createdAt: new Date(),
      duration: 1240,
      cacheHitRate: 0.84,
    }),
  ];

  return (
    <span className={styles.CommandEventDetailItemShowcase}>
      <Card>
        <div className={styles.Header}>
          <span className={styles.RunsText}>
            <Text variant="headingLg" as="h3">
              Runs
            </Text>
          </span>
          <Text variant="headingMd" as="h3" color="subdued">
            Cache hit rate
          </Text>
        </div>
        <div className={styles.CommandEventDetailItemsList}>
          <Stack vertical>
            {items.map((item) => {
              return (
                <CommandEventDetailItem
                  key={item.commandArguments}
                  item={item}
                />
              );
            })}
          </Stack>
        </div>
      </Card>
    </span>
  );
};
