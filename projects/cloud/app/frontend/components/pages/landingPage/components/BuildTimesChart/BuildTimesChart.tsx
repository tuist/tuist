import React from 'react';
import { LineChart } from '@shopify/polaris-viz';
import styles from './BuildTimesChart.module.scss';

export const BuildTimesChart = () => {
  return (
    <span className={styles.BuildTimesChart}>
      <LineChart
        theme="Light"
        data={[
          {
            data: [
              {
                key: '1',
                value: 3,
              },
              {
                key: '2',
                value: 7,
              },
              {
                key: '3',
                value: 5,
              },
              {
                key: '4',
                value: 12,
              },
              {
                key: '2020-04-05T12:00:00',
                value: 16,
              },
              {
                key: '2020-04-06T12:00:00',
                value: 22,
              },
              {
                key: '2020-04-07T12:00:00',
                value: 28,
              },
              {
                key: '2020-04-08T12:00:00',
                value: 24,
              },
              {
                key: '2020-04-09T12:00:00',
                value: 32,
              },
              {
                key: '2020-04-10T12:00:00',
                value: 39,
              },
              {
                key: '2020-04-11T12:00:00',
                value: 45,
              },
              {
                key: '2020-04-12T12:00:00',
                value: 43,
              },
              {
                key: '2020-04-13T12:00:00',
                value: 50,
              },
              {
                key: '2020-04-14T12:00:00',
                value: 52,
              },
            ],
            isComparison: true,
            name: 'Build times as you scale',
          },
          {
            data: [
              {
                key: '1',
                value: 3,
              },
              {
                key: '2',
                value: 5,
              },
              {
                key: '3',
                value: 4,
              },
              {
                key: '4',
                value: 5,
              },
              {
                key: '2020-04-05T12:00:00',
                value: 7,
              },
              {
                key: '2020-04-06T12:00:00',
                value: 4,
              },
              {
                key: '2020-04-07T12:00:00',
                value: 3,
              },
              {
                key: '2020-04-08T12:00:00',
                value: 5,
              },
              {
                key: '2020-04-09T12:00:00',
                value: 6,
              },
              {
                key: '2020-04-10T12:00:00',
                value: 5,
              },
              {
                key: '2020-04-11T12:00:00',
                value: 4,
              },
              {
                key: '2020-04-12T12:00:00',
                value: 3,
              },
              {
                key: '2020-04-13T12:00:00',
                value: 5,
              },
              {
                key: '2020-04-14T12:00:00',
                value: 6,
              },
            ],
            name: 'Build times with Tuist Cloud',
          },
        ]}
        xAxisOptions={{
          labelFormatter: () => {
            return '';
          },
        }}
        yAxisOptions={{
          labelFormatter: () => {
            return '';
          },
        }}
      />
    </span>
  );
};
