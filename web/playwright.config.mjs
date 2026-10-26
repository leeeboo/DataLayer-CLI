import { defineConfig } from '@playwright/test';

const externalURL = process.env.WEB_EDITOR_URL;
export default defineConfig({
  testDir: './tests',
  testMatch: '**/*.spec.mjs',
  timeout: 30000,
  workers: 2,
  fullyParallel: true,
  retries: 0,
  reporter: 'list',
  use: {
    baseURL: externalURL || 'http://127.0.0.1:8876/',
    viewport: { width: 1440, height: 1000 },
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [
    { name: 'firefox', use: { browserName: 'firefox' } },
    { name: 'webkit', use: { browserName: 'webkit' } },
  ],
  webServer: externalURL ? undefined : {
    command: 'python3 -m http.server 8876 --bind 127.0.0.1 --directory ../.build/gauge-pages',
    url: 'http://127.0.0.1:8876/',
    reuseExistingServer: false,
    timeout: 60000,
  },
});
