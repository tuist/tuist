import { CommandEventFragment } from '@/graphql/types';

export interface CommandEvent {
  id: string;
  commandArguments: string;
  duration: number;
  createdAt: Date;
}

export const mapCommandEvent = ({
  id,
  commandArguments,
  duration,
  createdAt,
}: CommandEventFragment) => {
  return {
    id,
    commandArguments,
    duration,
    createdAt: new Date(createdAt),
  } as CommandEvent;
};
