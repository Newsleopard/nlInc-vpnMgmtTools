// Simple test file to satisfy Jest requirements
import { handler } from './vpn-monitor.test-handler';

describe('VPN Monitor Test Handler', () => {
  it('should export handler function', () => {
    expect(typeof handler).toBe('function');
  });
});