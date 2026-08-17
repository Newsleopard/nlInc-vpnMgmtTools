module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>'],
  testMatch: ['**/__tests__/**/*.test.ts'],
  // 🔴 在任何測試模組被 require 之前把 AWS 環境中和掉。理由與實際事故見該檔案開頭。
  // ⛔ 不可改成 setupFilesAfterEnv —— 那會晚於測試檔 top-level 建立的 SDK client。
  setupFiles: ['<rootDir>/__tests__/setup/aws-sandbox.ts'],
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
        //
        // glob 是對「完整絕對路徑」比對的，所以一定要帶 **/ 前綴 ——
        // 但也**只**列出三個 tsconfig 的 include 實際涵蓋的那一個檔案，
        // ⛔ 不是整個目錄。目錄型 glob（'**/vpn-control/**'）有兩個 fail-open 缺口：
        //   ① 日後若有人把測試放進 vpn-control/__tests__/，那些測試會靜默失去型別檢查；
        //   ② 只要 repo 被 clone 到任何一層剛好叫 vpn-monitor / vpn-control /
        //      slack-handler 的目錄底下，整棵樹（含 shared/ 與 __tests__/）的
        //      型別檢查就會全部消失，而且沒有任何訊號。
        // 單檔形式兩個缺口一起關掉，語意也更誠實：排除的就是 build 用
        // strict:false 編的那三個檔案，一個不多。
        //
        // TODO(刪除條件，明確可驗證)：當這三個檔案在 root tsconfig 的 strict:true 下
        // `npx tsc --noEmit -p tsconfig.json` 為零錯誤時（2026-08-17 量到 27 個，
        // 全是 TS18046 catch-變數為 unknown 與 TS2345 string|null），
        // 把整個 `diagnostics` 區塊刪掉。⚠️ 這是刻意留的技術債：`exclude` 會讓這三個
        // 檔案的**所有** diagnostics 靜音，不只是 strict 才有的那些 —— 日後在裡面寫出
        // 一個連 strict:false 都抓得到的錯（參數個數、property 打錯字），`npm test`
        // 不會紅，而這個 repo 沒有 CI，npm test 幾乎是唯一的閘。
        exclude: [
          '**/vpn-control/index.ts',
          '**/slack-handler/index.ts',
          '**/vpn-monitor/index.ts',
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
