/**
 * 🔴 測試絕對不可以打到真實 AWS。
 *
 * 這個檔案由 jest.config.js 的 `setupFiles` 載入 —— 那是**在任何測試模組被 require
 * 之前**執行的階段，所以任何 SDK client 建構、任何請求送出時，下面兩層都已經就位。
 * ⛔ 不可以改成 `setupFilesAfterEnv`：那會在測試檔（含它 top-level 建立的 client）
 * 之後才跑，圍籬就晚了一步。
 *
 * 為什麼需要它（2026-08-17 實際踩到，不是預防性假設）：
 *   - vpn-control / slack-handler / vpn-monitor 三個 handler 用的是 **SDK v3**
 *     （`@aws-sdk/client-cloudwatch`、`@aws-sdk/client-lambda` 等）。
 *   - 但四個 integration suite mock 的是 **v2 的 `aws-sdk`**（`jest.mock('aws-sdk')`），
 *     兩者是完全不同的套件 —— mock 攔不到任何東西。
 *   - 於是 SDK v3 走了開發者本機的真實 credential chain，對開發者自己的 AWS 帳號
 *     發出簽章過的請求，並且真的把假 metric 寫進 `VPN/Automation` namespace ——
 *     那正是 cdklib/lib/vpn-automation-stack.ts 的 dashboard 在讀的 namespace。
 *     CloudWatch metric 寫進去就刪不掉。
 *
 * ⚠️ 這裡是**縱深防禦的外層**，不是「所以可以不用 mock」的藉口 —— 個別 suite 仍然要
 * mock 對的套件，否則斷言會打在一個從沒被呼叫的 mock 上。
 */

import http from 'node:http';
import https from 'node:https';

// ---------------------------------------------------------------------------
// 第 1 層：把 AWS 環境中和掉（快、訊息清楚，但**不是**保證 —— 見第 2 層）
// ---------------------------------------------------------------------------

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

// 把所有 AWS endpoint 導到一個必然 connection-refused 的位址（port 1 上不會有東西在聽，
// 所以是「立刻被拒」而不是「逾時等待」）。
//
// ⚠️ 這一行**單獨不足以構成保證**，這是 @ct-codex-agent 在 PR #22 抓到的：
// `AWS_ENDPOINT_URL` 是 SDK v3 較新版本才實作的（實作在 `@smithy/core`），而本 repo 的
// 四個 package.json 宣告的下限是 `^3.350.0`，且 repo **沒有 package-lock.json**。
// 也就是說「解析到一個不支援這個變數的合法版本」是可能的 —— 屆時這行會被靜默忽略，
// 未被 mock 的 v3 client 就會拿假憑證去連**真實** AWS endpoint。
// 所以下面第 2 層才是真正的保證，它完全不依賴 SDK 的任何行為。
process.env.AWS_ENDPOINT_URL = 'http://127.0.0.1:1';

// ---------------------------------------------------------------------------
// 第 2 層：版本無關的硬阻斷 —— 任何非 loopback 的 HTTP(S) 連線一律拒絕
// ---------------------------------------------------------------------------
//
// 這一層攔在 Node 的 http/https 之上，所以**不管** SDK 是哪個版本、有沒有實作
// AWS_ENDPOINT_URL、有沒有被 mock 到，封包都出不了這台機器。
// AWS SDK v3 在 Node 下是透過 `@smithy/node-http-handler` 呼叫 `https.request`，
// 所以這裡蓋得到；v2 的 `aws-sdk` 同樣走這兩個模組。
//
// ⚠️ `require('node:https')` 與 `require('https')` 回傳的是**同一個** builtin 模組物件，
// 所以只 patch 一次就同時涵蓋兩種寫法。

const LOOPBACK = /^(127\.\d+\.\d+\.\d+|localhost|\[?::1\]?)$/i;

/** 從 http.request 的多型參數裡取出目標 host（取不到就回 null → 保守放行給 Node 自己報錯）。 */
function targetHost(a?: unknown, b?: unknown): string | null {
  for (const arg of [a, b]) {
    if (typeof arg === 'string') {
      try { return new URL(arg).hostname; } catch { /* 不是完整 URL，往下試 */ }
    } else if (arg instanceof URL) {
      return arg.hostname;
    } else if (arg && typeof arg === 'object') {
      const o = arg as { hostname?: unknown; host?: unknown };
      const h = o.hostname ?? o.host;
      // `host` 可能帶 port（example.com:443），要切掉才比得對。
      if (typeof h === 'string') return h.replace(/:\d+$/, '').replace(/^\[|\]$/g, '');
    }
  }
  return null;
}

type AnyFn = (...args: any[]) => any;

function guard<T extends AnyFn>(original: T, label: string): T {
  const patched = function (this: unknown, ...args: any[]) {
    const host = targetHost(args[0], args[1]);
    if (host !== null && !LOOPBACK.test(host)) {
      // ⛔ 故意 throw 而不是回一個會 emit 'error' 的 socket：throw 讓失敗立刻、
      // 同步地出現在呼叫端的 stack 上，指出是**哪一個測試**想連出去。
      throw new Error(
        `[aws-sandbox] 測試被阻止連線到 ${host}（經由 ${label}）。\n` +
        `測試絕對不可以打到真實服務。請 mock 對應的 client —— ` +
        `注意 handler 用的是 SDK v3（@aws-sdk/client-*），mock 'aws-sdk'（v2）攔不到它。`
      );
    }
    return original.apply(this, args);
  };
  return patched as T;
}

http.request = guard(http.request, 'http.request');
http.get = guard(http.get, 'http.get');
https.request = guard(https.request, 'https.request');
https.get = guard(https.get, 'https.get');

// ---------------------------------------------------------------------------
// 第 2b 層：fetch —— 它**不會**經過上面那四個 function
// ---------------------------------------------------------------------------
//
// 🔴 @ct-codex-agent 在 PR #22 round 2 抓到的：Node 18+ 的 `globalThis.fetch` 走
// undici，完全不碰 node:http / node:https。本地探針實測：patch 過的四個 function
// 在一次 fetch() 期間被呼叫 **0** 次。
//
// 而這個 repo 真的有 fetch 出站 —— slack-handler/index.ts:674 與 :786 都是
// `await fetch(productionAPIEndpoint, …)`，shared/slack.ts 也用 fetch 送 Slack
// webhook。全 18 個測試檔中只有 3 個 mock 了 fetch，其餘一個都沒有。
// 所以在補上這一段之前，上面那句「封包都出不了這台機器」是**假的**：
// 一個沒 mock 到的 fetch 可以打到真的 Slack / production API。
//
// ⚠️ 這裡回 rejected promise 而不是同步 throw —— fetch 的契約是回 Promise，
// 同步 throw 會讓 `fetch(...).catch(...)` 這種寫法直接炸在呼叫端而不是進 catch。
// 訊息一樣認得出來是誰擋的。
// ⚠️ 測試若自己 `global.fetch = jest.fn()`，會蓋掉這個包裝 —— 那是正確的，
// 它就是在 mock；圍籬只負責「沒人 mock 時不要打出去」。

/** 從 fetch 的 input（string | URL | Request）取出 host；取不到回 null。 */
function fetchHost(input: unknown): string | null {
  if (typeof input === 'string') {
    try { return new URL(input).hostname; } catch { return null; }
  }
  if (input instanceof URL) return input.hostname;
  if (input && typeof input === 'object' && 'url' in input) {
    const u = (input as { url?: unknown }).url;
    if (typeof u === 'string') { try { return new URL(u).hostname; } catch { return null; } }
  }
  return null;
}

const realFetch = globalThis.fetch;
if (typeof realFetch === 'function') {
  globalThis.fetch = function patchedFetch(this: unknown, ...args: any[]) {
    const host = fetchHost(args[0]);
    if (host !== null && !LOOPBACK.test(host)) {
      return Promise.reject(new Error(
        `[aws-sandbox] 測試被阻止連線到 ${host}（經由 fetch）。\n` +
        `測試絕對不可以打到真實服務（Slack webhook / production API 都走 fetch）。` +
        `請在該 suite 裡 mock fetch，例如 global.fetch = jest.fn()。`
      ));
    }
    return (realFetch as (...a: unknown[]) => unknown).apply(this, args) as Promise<Response>;
  } as typeof fetch;
}
