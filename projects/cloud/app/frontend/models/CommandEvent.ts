import { CommandEventFragment } from '@/graphql/types';

export interface CommandEvent {
  id: string;
  commandArguments: string;
  duration: number;
  createdAt: Date;
  cacheHitRate?: number | null;
}

export const mapCommandEvent = ({
  id,
  commandArguments,
  duration,
  createdAt,
  cacheHitRate,
}: CommandEventFragment) => {
  return {
    id,
    commandArguments,
    duration,
    createdAt: new Date(createdAt),
    cacheHitRate,
  } as CommandEvent;
};
