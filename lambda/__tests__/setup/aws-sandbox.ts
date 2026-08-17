/**
 * 🔴 測試絕對不可以打到真實 AWS。
 *
 * 這個檔案由 jest.config.js 的 `setupFiles` 載入 —— 那是**在任何測試模組被 require
 * 之前**執行的階段，所以 SDK client 建構時看到的一定是下面這組值。
 * ⛔ 不可以改成 `setupFilesAfterEnv`：那會在測試檔（含它 top-level 建立的 client）
 * 之後才跑，圍籬就晚了一步。
 *
 * 為什麼需要它（2026-08-17 實際踩到，不是預防性假設）：
 *   - vpn-control / slack-handler / vpn-monitor 三個 handler 用的是 **SDK v3**
 *     （`@aws-sdk/client-cloudwatch`、`@aws-sdk/client-lambda` 等）。
 *   - 但四個 integration suite mock 的是 **v2 的 `aws-sdk`**（`jest.mock('aws-sdk')`），
 *     兩者是完全不同的套件 —— mock 攔不到任何東西。
 *   - 於是 SDK v3 走了開發者本機的真實 credential chain，對
 *     `arn:aws:iam::677089019267:user/ct` 發出簽章過的請求，
 *     並且真的把 27 筆假 metric 寫進 `VPN/Automation` namespace ——
 *     那正是 cdklib/lib/vpn-automation-stack.ts 的 dashboard 在讀的 namespace。
 *     CloudWatch metric 寫進去就刪不掉。
 *
 * 這裡做的是**縱深防禦的外層**：就算未來又有哪個 client 沒被 mock 到，
 * 請求也出不了這台機器。⚠️ 它不是「所以可以不用 mock」的藉口 ——
 * 個別 suite 仍然要 mock 對的套件，否則斷言會打在一個從沒被呼叫的 mock 上。
 */

// 假憑證：讓 credential chain 立刻解析成功，不會去翻 ~/.aws 或 IMDS。
process.env.AWS_ACCESS_KEY_ID = 'testing';
process.env.AWS_SECRET_ACCESS_KEY = 'testing';
process.env.AWS_SESSION_TOKEN = 'testing';

// profile 若留著，SDK 仍可能改讀 ~/.aws/credentials 裡的真憑證。
delete process.env.AWS_PROFILE;
delete process.env.AWS_DEFAULT_PROFILE;

// SDK v3 沒有 region 會直接 throw，跟「打不出去」是不同的失敗模式；給一個固定值。
process.env.AWS_REGION = 'us-east-1';
process.env.AWS_DEFAULT_REGION = 'us-east-1';

// 關掉 EC2/ECS metadata 探測，否則在某些環境會卡住數秒才逾時。
process.env.AWS_EC2_METADATA_DISABLED = 'true';

// 🔴 真正的圍籬：把所有 AWS endpoint 導到一個必然 connection-refused 的位址。
// port 1 上不會有東西在聽，所以請求是「立刻被拒」而不是「逾時等待」——
// 既擋住外流，也不會讓測試慢下來。SDK v3 自 3.379 起支援這個全域變數
// （本 repo 裝的是 @aws-sdk/client-* 3.x，遠高於該版本）。
process.env.AWS_ENDPOINT_URL = 'http://127.0.0.1:1';

// ⚠️ 這行是刻意的最後一道保險：若哪天上面某一項被移除或被某個 setup 覆寫，
// 至少讓「測試跑在什麼身分下」在 log 裡看得見，而不是靜默地用真帳號。
if (!process.env.AWS_ENDPOINT_URL || !process.env.AWS_ACCESS_KEY_ID) {
  throw new Error(
    'AWS sandbox 圍籬沒有生效 —— 拒絕在可能連到真實 AWS 的狀態下跑測試。'
  );
}
