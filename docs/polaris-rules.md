# polaris-rules

[Polaris](https://github.com/ipevel/polaris) 的**分流规则与 geo 数据库**，从上游自动同步。

App 两端（Windows / 安卓）**不再内置 ACL4SSR 原文**，改为从这里拉「已经合并好」的文件。
随包内置的那份只作首次安装与断网时的兜底。

## 它解决什么问题

旧方案里，规则数据源依赖多个远程 `type: http` 的 rule-provider，具体有四个坑：

1. **清单永不更新** —— 内置的 ACL4SSR 原文随包固定，上游改了 App 也看不到。
2. **静默失效** —— 拉取失败、被中间盒改写、上游格式变化，规则就悄悄不生效了。
3. **「新 sum 配旧字节」** —— jsdelivr 各边缘缓存寿命不同（`s-maxage=43200`，最长 12 小时），
   二进制与 `.sha256sum` 分开缓存，校验必然随机失败。
4. **协议错配** —— 上游是 `text` 形态，mihomo 里配成 `yaml` 也不报错，只是匹配不上。

本仓库的应对：

| 坑 | 应对 |
|---|---|
| 永不更新 | GitHub Actions 每 15 分钟**轻量探测**上游坐标，变了就全量同步 |
| 静默失效 | 同步产物过 `tools/verify.mjs` 自洽性门禁，不自洽**绝不提交** |
| 新 sum 配旧字节 | 文件与校验值都由**同一次 sync、同一个 commit** 产出；App 用 `@<commit>` 取 |
| 协议错配 | `dist/rules/*.list` 只含规则行，`format: text` 逐行都是规则 |

### 什么时候会同步

三个触发方式，任一命中就跑（`.github/workflows/sync.yml`）：

| 触发 | 说明 |
|---|---|
| `schedule` | 每 15 分钟一次**轻量探测**（cron `9,24,39,54 * * * *`）：只问上游「变了吗」，不变就秒退，不下载任何内容 |
| `push` | 改 `tools/**` 或这个 workflow 本身时跑一次 |
| `workflow_dispatch` | 手动：`gh workflow run sync.yml --repo ipevel/cboard-rulesets` |

> ⚠️ **`schedule` 是「尽力而为」，不是保证。** 本仓库 2026-10-13 建起来后的头 4 小时里，
> `event=schedule` 的 run 数一直是 **0**（同期 push / `workflow_dispatch` 都正常、
> workflow `state=active`、默认分支 `main` 上也确实有这段 schedule），所以已把 cron 从
> `*/15`（落在 :00 / :15 / :30 / :45 这四个 GitHub 全站最挤的刻度）错开成 `9,24,39,54`。
>
> 想知道「定时到底有没有在跑」：
>
> ```bash
> gh api 'repos/ipevel/cboard-rulesets/actions/workflows/sync.yml/runs?event=schedule&per_page=1' --jq .total_count
> ```
>
> 这个数长期不涨 = 定时没生效，规则会停在最后一次同步的版本上。此时手动 dispatch 一次，
> 或换成外部定时器打 `workflow_dispatch`（API 需要一个 fine-grained token，权限只要 Actions: write）。

## 目录

```
rules/*.txt            人可读形态：带表头、按分流组合并好，用来 review 与 diff
dist/rules/*.list      机可读形态：只有规则行。App 只跟这份打交道
geo/                   根目录的 geo 数据库（geosite.dat / geoip.metadb / ASN.mmdb）
dist/geo/*             同上，App 消费形态
latest.json            版本清单：文件列表 + 字节数 + SHA-256 + 上游坐标
SHA256SUMS.txt         校验清单（根目录与 dist/ 各一份，内容一致）
VERSION                单调递增整数，方便做「比数字」的廉价判断
last-upstream.json     上一次同步时的上游坐标，供 --check 比对
PROVENANCE.md          产出谱系（自动生成）：每个文件的来源与条数
tools/manifest.mjs     产出清单（唯一事实源：合并哪些上游文件、geo 取哪些资产）
tools/sync.mjs         同步器
tools/verify.mjs       自洽性校验器
```

### 为什么分 `rules/` 与 `dist/rules/`

`rules/*.txt` 给人看：有中文表头、写明来源与去重条数。
`dist/rules/*.list` 给内核看：**一个注释都不带**，避免任何解析歧义。

两者由 `tools/verify.mjs` 的「规则行集合必须一致」卡住 —— 只改一边会被 CI 拒。

## 怎么用

```
latest.json                     -> 拿版本号与全部文件的 SHA-256
dist/rules/<name>.list          -> 规则清单（机读形态）
dist/geo/geosite.dat            -> geo 数据库
dist/geo/geoip.metadb
dist/geo/ASN.mmdb
```

**必须从同一个 commit 取文件和校验值**：

```
https://cdn.jsdelivr.net/gh/ipevel/cboard-rulesets@<commit-sha>/dist/rules/social.list
https://raw.githubusercontent.com/ipevel/cboard-rulesets/<commit-sha>/dist/rules/social.list
```

用 `<commit-sha>` 而不是 `main` 的原因见上面第 3 条：`main` 会漂，`@<sha>` 不可变。

## 上游

| 内容 | 来源 |
|---|---|
| 分流清单 | [ACL4SSR/ACL4SSR](https://github.com/ACL4SSR/ACL4SSR) `master` 的 `Clash/*.list` 与 `Clash/Ruleset/*.list` |
| geo 数据库 | [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) 的 `latest` release 资产（每天重发，资产自带 `.sha256sum`） |

geo 取 release 而不是仓库分支，原因：它是真正的上游源头、资产自带校验基准、
且每天重发（而该仓库的 `master` 分支自 2026-06 起几乎没有代码变更）。

## 产出的分流组

| 文件 | 条数级 | 上游来源 |
|---|---|---|
| `social` | 53 | Twitter / Instagram / Facebook / Whatsapp |
| `streaming` | 175 | YouTube / Netflix / DisneyPlus / HBO / Hulu / AppleTV / BBCiPlayer / AbemaTV / DAZN / Twitch / Spotify / Amazon |
| `ai` | 62 | AI / OpenAi / ClaudeAI / Gemini |
| `games` | 51 | Steam / Epic / Sony / Nintendo / Xbox |
| `telegram` | 14 | Telegram |
| `tiktok` | 10 | TikTok |
| `china-domain` | 652 | ChinaDomain + Baidu / Tencent / Alibaba / ByteDance / Wechat |
| `china-ip` | 9114 | ChinaIp / ChinaIpV6 / ChinaCompanyIp |
| `china-media` | 77 | ChinaMedia + Bilibili / NetEaseMusic |
| `onedrive` | 92 | OneDrive + Microsoft |
| `proxy-gfwlist` | 6883 | ProxyGFWlist |
| `proxy-media` | 357 | ProxyMedia |
| `banad` | 588 | BanAD |
| `banprogramad` | 1010 | BanProgramAD |

条数是 2026-10-13 的快照，实际以 `latest.json` 为准。

## 本地跑

```bash
node tools/sync.mjs --check   # 只探测，退出码 2 = 上游无变化
node tools/sync.mjs           # 全量同步
node tools/verify.mjs         # 自洽性校验
```

无网络时需要代理就设 `POLARIS_SYNC_PROXY`（同时装了 `undici` 才会生效；直连可用则不必）。

## 许可

同步产物来自上述两个上游项目，各自的许可与署名见 `THIRD-PARTY-NOTICES.md`。
本仓库自身的脚本以 MIT 发布。
