import { CommandEventDetailFragment } from '@/graphql/types';

export interface CommandEventDetail {
  name: string;
  subcommand: string | null;
  commandArguments: string;
  duration: number;
  clientId: string;
  tuistVersion: string;
  swiftVersion: string;
  macosVersion: string;
}

export const mapCommandEventDetail = ({
  name,
  subcommand,
  commandArguments,
  duration,
  clientId,
  tuistVersion,
  swiftVersion,
  macosVersion,
}: CommandEventDetailFragment) => {
  return {
    name,
    subcommand,
    commandArguments,
    duration,
    clientId,
    tuistVersion,
    swiftVersion,
    macosVersion,
  } as CommandEventDetail;
};
