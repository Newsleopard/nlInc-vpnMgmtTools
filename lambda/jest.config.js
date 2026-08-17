module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>'],
  testMatch: ['**/__tests__/**/*.test.ts'],
  transform: {
    // ts-jest 29 起，設定放在 transform 這裡；globals['ts-jest'] 是 deprecated 路徑。
    '^.+\\.tsx?$': ['ts-jest', {
      tsconfig: 'tsconfig.json',
      diagnostics: {
        // 三個 handler 的 build tsconfig 自己就是 strict:false
        // （vpn-control/slack-handler/vpn-monitor 各自的 tsconfig.json）。
        // root tsconfig 是 strict:true，而 ts-jest 用的是 root ——
        // 於是任何「載入真 handler」的整合測試，都會拿一個這些檔案從未被
        // 要求符合的標準去檢查它們，然後在 module 載入階段就整個 suite 死掉。
        // 這裡讓測試的型別檢查與 build 對齊；⛔ 不是放寬 shared/ 與測試本身，
        // 那兩者仍然 strict（shared/tsconfig.json 也是 strict:true）。
        // 要把 handler 提升到 strict 是另一件事，不在測試修復的範圍內。
        // glob 是對「完整檔案路徑」比對的，所以一定要帶 **/ 前綴。
        exclude: [
          '**/vpn-control/**',
          '**/slack-handler/**',
          '**/vpn-monitor/**',
        ],
      },
    }],
  },
  moduleFileExtensions: ['ts', 'tsx', 'js', 'jsx', 'json', 'node'],
  collectCoverageFrom: [
    '**/*.ts',
    '!**/*.d.ts',
    '!**/node_modules/**',
    '!**/dist/**',
  ],
  modulePathIgnorePatterns: ['<rootDir>/dist/', '<rootDir>/shared/dist/'],
  testPathIgnorePatterns: ['/node_modules/', '/dist/'],
  moduleNameMapper: {
    '^@shared/(.*)$': '<rootDir>/shared/$1',
    // Lambda Layer 在執行期把 shared/ 掛在 /opt/nodejs/ 底下，所以 handler 一律
    // import '/opt/nodejs/<mod>'。這個對應不是這裡發明的 —— vpn-control /
    // slack-handler / vpn-monitor 三個 tsconfig.json 的 paths 早就這樣宣告了。
    // 少了它，任何載入真 handler 的測試都會在 module resolution 就死掉。
    '^/opt/nodejs/(.*)$': '<rootDir>/shared/$1',
  },
};
