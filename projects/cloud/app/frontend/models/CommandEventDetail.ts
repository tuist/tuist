import { CommandEventDetailFragment } from '@/graphql/types';

export interface CommandEventDetail {
  id: string;
  name: string;
  subcommand: string | null;
  commandArguments: string;
  duration: number;
  clientId: string;
  tuistVersion: string;
  swiftVersion: string;
  macosVersion: string;
  createdAt: Date;
  cacheableTargets: string[] | null;
  localCacheTargetHits: string[] | null;
  remoteCacheTargetHits: string[] | null;
  cacheHitRate: number | null;
}

export const mapCommandEventDetail = ({
  id,
  name,
  subcommand,
  commandArguments,
  duration,
  clientId,
  tuistVersion,
  swiftVersion,
  macosVersion,
  createdAt,
  cacheableTargets,
  localCacheTargetHits,
  remoteCacheTargetHits,
  cacheHitRate,
}: CommandEventDetailFragment) => {
  return {
    id,
    name,
    subcommand,
    commandArguments,
    duration,
    clientId,
    tuistVersion,
    swiftVersion,
    macosVersion,
    createdAt: new Date(createdAt),
    cacheableTargets,
    localCacheTargetHits,
    remoteCacheTargetHits,
    cacheHitRate,
  } as CommandEventDetail;
};
