import { CommandEventItem } from '@/components/pages/dashboard/CommandEventItem';
import { CommandEvent } from '@/models/CommandEvent';
import { Card, Stack, Text } from '@shopify/polaris';
import React from 'react';
import styles from './CommandEventItemShowcase.module.scss';

interface MockDetailItemProps {
  commandArguments: string;
  duration: number;
  createdAt: Date;
  cacheHitRate?: number;
}

export const CommandEventItemShowcase = () => {
  const items: CommandEvent[] = [
    {
      id: '1',
      commandArguments: 'generate MyApp',
      createdAt: new Date(),
      duration: 1240,
      cacheHitRate: 0.95,
    },
    {
      id: '2',
      commandArguments: 'generate MyApp2',
      createdAt: new Date(),
      duration: 1240,
    },
    {
      id: '3',
      commandArguments: 'generate MyApp3',
      createdAt: new Date(),
      duration: 1240,
      cacheHitRate: 0.74,
    },
    {
      id: '4',
      commandArguments: 'generate MyApp4',
      createdAt: new Date(),
      duration: 1240,
      cacheHitRate: 0.84,
    },
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
                <CommandEventItem
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
