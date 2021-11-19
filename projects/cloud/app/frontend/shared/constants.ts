import { Environment } from '@/shared/Environment';

export const baseURL: string = process.env.BASE_URL as string;
export const bugsnagFrontendKey: string = process.env
  .BUGSNAG_FRONTEND_KEY as string;

let environment: Environment;
if (process.env.ENVIRONMENT === 'production') {
  environment = Environment.Production;
} else {
  environment = Environment.Development;
}

export { environment };
