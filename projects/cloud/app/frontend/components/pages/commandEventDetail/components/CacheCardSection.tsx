import React from 'react';
import { Card, TextStyle, Stack } from '@shopify/polaris';

interface CacheCardSectionProps {
  cacheableTargets: string[] | null;
  localCacheTargetHits: string[] | null;
  remoteCacheTargetHits: string[] | null;
  cacheTargetMisses: string[];
  cacheTargetHitRate: string;
}

const CacheCardSection = ({
  cacheableTargets,
  localCacheTargetHits,
  remoteCacheTargetHits,
  cacheTargetMisses,
  cacheTargetHitRate,
}: CacheCardSectionProps) => {
  if (
    cacheableTargets === null ||
    localCacheTargetHits === null ||
    remoteCacheTargetHits === null
  ) {
    return null;
  }
  return (
    <Card.Section title="Cache">
      <Stack vertical>
        <Stack>
          <TextStyle variation="subdued">Cacheable targets</TextStyle>
          <TextStyle>{`Total count: ${cacheableTargets.length}`}</TextStyle>
        </Stack>
        <TextStyle variation="code">
          {cacheableTargets.join(' ')}
        </TextStyle>
        <Stack>
          <TextStyle variation="subdued">
            Targets from local cache
          </TextStyle>
          <TextStyle>{`Total count: ${localCacheTargetHits.length}`}</TextStyle>
          {localCacheTargetHits.length > 0 && (
            <TextStyle variation="code">
              {localCacheTargetHits.join(' ')}
            </TextStyle>
          )}
        </Stack>
        <Stack>
          <TextStyle variation="subdued">
            Targets from remote cache
          </TextStyle>
          <TextStyle>{`Total count: ${remoteCacheTargetHits.length}`}</TextStyle>
        </Stack>
        {remoteCacheTargetHits.length > 0 && (
          <TextStyle variation="code">
            {remoteCacheTargetHits.join(' ')}
          </TextStyle>
        )}
        <Stack>
          <TextStyle variation="subdued">
            Cache targets missed
          </TextStyle>
          <TextStyle>{`Total count: ${cacheTargetMisses.length}`}</TextStyle>
        </Stack>
        {cacheTargetMisses.length > 0 && (
          <TextStyle variation="code">
            {cacheTargetMisses.join(' ')}
          </TextStyle>
        )}
        <Stack>
          <TextStyle variation="subdued">
            Total cache hit rate
          </TextStyle>
          <TextStyle>{cacheTargetHitRate}</TextStyle>
        </Stack>
      </Stack>
    </Card.Section>
  );
};

export default CacheCardSection;
