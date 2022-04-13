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
  } as CommandEventDetail;
};
