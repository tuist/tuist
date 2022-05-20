import relativeDate from '@/utilities/relativeDate';
import { useApolloClient } from '@apollo/client';
import { Card, Page, Stack, TextStyle } from '@shopify/polaris';
import { observer } from 'mobx-react-lite';
import React, { useEffect, useRef, useState } from 'react';
import { useParams } from 'react-router-dom';
import CommandEventDetailPageStore from './CommandEventDetailPageStore';
import CacheCardSection from './components/CacheCardSection';

const CommandEventDetailPage = observer(() => {
  const client = useApolloClient();
  const commandEventDetailPageStore = useRef(
    new CommandEventDetailPageStore(client),
  ).current;

  const { commandEventId } = useParams();
  useEffect(() => {
    if (commandEventId == null) {
      return;
    }
    commandEventDetailPageStore.load(commandEventId);
  }, [commandEventId]);

  if (commandEventDetailPageStore.commandEventDetail == null) {
    return null;
  }
  return (
    <Page>
      <Card
        title={`${
          commandEventDetailPageStore.commandEventDetail.name
            .charAt(0)
            .toUpperCase() +
          commandEventDetailPageStore.commandEventDetail.name.slice(1)
        } run`}
      >
        <Card.Section title="General information">
          <Stack vertical={true}>
            <Stack>
              <TextStyle variation="subdued">Command run</TextStyle>
              <TextStyle variation="code">
                {
                  commandEventDetailPageStore.commandEventDetail
                    .commandArguments
                }
              </TextStyle>
            </Stack>
            <Stack>
              <TextStyle variation="subdued">Date</TextStyle>
              <TextStyle>
                {relativeDate(
                  commandEventDetailPageStore.commandEventDetail
                    .createdAt,
                )}
              </TextStyle>
            </Stack>
            <Stack>
              <TextStyle variation="subdued">Duration</TextStyle>
              <TextStyle>
                {Math.ceil(
                  commandEventDetailPageStore.commandEventDetail
                    .duration / 1000,
                )}{' '}
                s
              </TextStyle>
            </Stack>
          </Stack>
        </Card.Section>
        <CacheCardSection
          cacheableTargets={
            commandEventDetailPageStore.commandEventDetail
              .cacheableTargets
          }
          localCacheTargetHits={
            commandEventDetailPageStore.commandEventDetail
              .localCacheTargetHits
          }
          remoteCacheTargetHits={
            commandEventDetailPageStore.commandEventDetail
              .remoteCacheTargetHits
          }
          cacheTargetMisses={
            commandEventDetailPageStore.cacheTargetMisses
          }
          cacheTargetHitRate={
            commandEventDetailPageStore.cacheTargetHitRate
          }
        />
        <Card.Section title="Environment">
          <Stack vertical>
            <Stack>
              <TextStyle variation="subdued">Tuist version</TextStyle>
              <TextStyle>
                {
                  commandEventDetailPageStore.commandEventDetail
                    .tuistVersion
                }
              </TextStyle>
            </Stack>
            <Stack>
              <TextStyle variation="subdued">macOS version</TextStyle>
              <TextStyle>
                {
                  commandEventDetailPageStore.commandEventDetail
                    .macosVersion
                }
              </TextStyle>
            </Stack>
            <Stack>
              <TextStyle variation="subdued">Swift version</TextStyle>
              <TextStyle>
                {
                  commandEventDetailPageStore.commandEventDetail
                    .swiftVersion
                }
              </TextStyle>
            </Stack>
          </Stack>
        </Card.Section>
      </Card>
    </Page>
  );
});

export default CommandEventDetailPage;
