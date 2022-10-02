import React from 'react';
import relativeDate from '@/utilities/relativeDate';
import { CommandEventDetail } from '@/models/CommandEventDetail';
import {
  Stack,
  TextStyle,
  Icon,
  Text,
  TextProps,
} from '@shopify/polaris';
import { ClockMinor, CalendarMinor } from '@shopify/polaris-icons';

export const CommandEventDetailItem = ({
  item,
}: {
  item: CommandEventDetail;
}) => {
  const color: TextProps['color'] | undefined = (() => {
    if (item.cacheHitRate == null) {
      return undefined;
    } else if (item.cacheHitRate < 0.5) {
      return 'critical';
    } else if (item.cacheHitRate < 0.75) {
      return 'warning';
    } else {
      return 'success';
    }
  })();
  const cacheHitRateText =
    item.cacheHitRate == null ? null : (
      <Text variant="headingLg" as="h3" color={color} alignment="end">
        {`${item.cacheHitRate * 100} %`}
      </Text>
    );
  return (
    <Stack alignment="center" distribution="fill">
      <Stack vertical>
        <TextStyle variation="code">
          {item.commandArguments}
        </TextStyle>
        <Stack spacing={'loose'}>
          <Stack spacing={'baseTight'}>
            <Icon source={ClockMinor} />
            <TextStyle>{Math.ceil(item.duration / 1000)} s</TextStyle>
          </Stack>
          <Stack spacing={'baseTight'}>
            <Icon source={CalendarMinor} />
            <TextStyle>{relativeDate(item.createdAt)}</TextStyle>
          </Stack>
        </Stack>
      </Stack>
      {cacheHitRateText}
    </Stack>
  );
};
