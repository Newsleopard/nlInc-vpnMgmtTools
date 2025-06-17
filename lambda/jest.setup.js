// Global test setup

// Mock environment variables
process.env.ENVIRONMENT = 'test';
process.env.IDLE_MINUTES = '60';
process.env.VPN_STATE_PREFIX = '/vpn/';
process.env.SIGNING_SECRET_PARAM = '/vpn/slack/signing_secret';
process.env.WEBHOOK_PARAM = '/vpn/slack/webhook';

// Mock console methods in tests
global.console = {
  ...console,
  // Uncomment to suppress logs during tests
  // log: jest.fn(),
  // error: jest.fn(),
  // warn: jest.fn(),
  // info: jest.fn(),
};