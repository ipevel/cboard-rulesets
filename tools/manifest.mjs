/**
 * polaris-rules 的「产出清单」——同步脚本与校验脚本共用的唯一事实源。
 *
 * 设计原则（与 Polaris 两端 App 的约定）：
 *  1. **只有一套规则体系**：App 侧不再内置 ACL4SSR 原文，改为从本仓库拉「已合并好」的文件。
 *  2. **清单与校验同源**：文件内容与 SHA256SUMS 都由同一次 sync 产出、同一个 commit 承载，
 *     从构造上消灭「新 sum 配旧字节」（jsdelivr 边缘缓存错配那类问题）。
 *  3. **产出文件数封顶**：App 冷启动要加载这些文件，文件越多越慢，所以按「分流组」粒度合并，
 *     不按上游单条 list 粒度铺开。
 *
 * 上游谱系：
 *  - 域名/IP 规则：ACL4SSR/ACL4SSR@master 的 Clash/*.list 与 Clash/Ruleset/*.list
 *  - geo 数据库 ：MetaCubeX/meta-rules-dat 的 latest release（每天重发，资产自带 .sha256sum）
 */

export const UPSTREAM = {
  acl: {
    repo: 'ACL4SSR/ACL4SSR',
    ref: 'master',
    rawBase: 'https://raw.githubusercontent.com/ACL4SSR/ACL4SSR',
  },
  meta: {
    repo: 'MetaCubeX/meta-rules-dat',
    releaseTag: 'latest',
    apiBase: 'https://api.github.com/repos/MetaCubeX/meta-rules-dat/releases/latest',
    downloadBase: 'https://github.com/MetaCubeX/meta-rules-dat/releases/download',
  },
};

/**
 * rules/<产出文件>.list  ←  上游 ACL4SSR 的若干 list 合并
 *
 * dir   : 'Clash'（根目录 list）或 'Clash/Ruleset'（Ruleset 子目录 list）
 * files : 上游文件名（不带 .list）
 * why   : 合并理由，写进 PROVENANCE.md，便于日后解释「这条规则哪来的」
 */
export const RULE_SETS = [
  {
    out: 'social',
    dir: 'Clash/Ruleset',
    files: ['Twitter', 'Instagram', 'Facebook', 'Whatsapp'],
    why: '社交媒体（X / Instagram / Facebook / WhatsApp 合并成一个分流组）',
  },
  {
    out: 'streaming',
    dir: 'Clash/Ruleset',
    files: [
      'YouTube', 'Netflix', 'DisneyPlus', 'HBO', 'Hulu', 'AppleTV',
      'BBCiPlayer', 'AbemaTV', 'DAZN', 'Twitch', 'Spotify', 'Amazon',
    ],
    why: '境外流媒体（原本散在多个组，合并为一个「流媒体」组）',
  },
  {
    out: 'ai',
    dir: 'Clash/Ruleset',
    files: ['AI', 'OpenAi', 'ClaudeAI', 'Gemini'],
    why: 'AI 服务（OpenAI / Claude / Gemini / 通用 AI 分类）',
  },
  {
    out: 'games',
    dir: 'Clash/Ruleset',
    files: ['Steam', 'Epic', 'Sony', 'Nintendo', 'Xbox'],
    why: '游戏平台（Steam / Epic / 主机三家的商店与联机域名）',
  },
  {
    out: 'telegram',
    dir: 'Clash/Ruleset',
    files: ['Telegram'],
    why: '电报消息（单独一组，用户要求保留）',
  },
  {
    out: 'tiktok',
    dir: 'Clash/Ruleset',
    files: ['TikTok'],
    why: 'TikTok（单独一组，用户要求保留）',
  },
  {
    out: 'china-domain',
    dir: 'Clash',
    files: ['ChinaDomain'],
    alsoRuleset: ['Baidu', 'Tencent', 'Alibaba', 'ByteDance', 'Wechat'],
    why: '国内域名（ACL4SSR 主表 + 五家大厂表，兜住主流 App 域名）',
  },
  {
    out: 'china-ip',
    dir: 'Clash',
    files: ['ChinaIp', 'ChinaIpV6', 'ChinaCompanyIp'],
    why: '国内 IP 段（含 IPv6 与企业 IP，配合 GEOIP,CN 兜底）',
  },
  {
    out: 'china-media',
    dir: 'Clash',
    files: ['ChinaMedia'],
    alsoRuleset: ['Bilibili', 'NetEaseMusic'],
    why: '国内流媒体（哔哩哔哩 / 网易音乐并入国内直连）',
  },
  {
    out: 'onedrive',
    dir: 'Clash',
    files: ['OneDrive'],
    alsoRuleset: ['Microsoft'],
    why: '微软云盘 + 微软服务（用户要求默认直连，走代理太费流量）',
  },
  {
    out: 'proxy-gfwlist',
    dir: 'Clash',
    files: ['ProxyGFWlist'],
    why: '国外穿墙兜底（GFWList，上游每 2–4 天自动更新一次）',
  },
  {
    out: 'proxy-media',
    dir: 'Clash',
    files: ['ProxyMedia'],
    why: '境外流媒体兜底（不在上面 streaming 名单里的长尾站点）',
  },
  {
    out: 'banad',
    dir: 'Clash',
    files: ['BanAD'],
    why: '广告拦截（默认打开，用户在 2026-10-13 定的）',
  },
  {
    out: 'banprogramad',
    dir: 'Clash',
    files: ['BanProgramAD'],
    why: '应用净化（拦截 App 内的推广/启动图广告）',
  },
];

/**
 * geo/<产出文件>  ←  MetaCubeX/meta-rules-dat 的 release 资产
 *
 * asset : release 里的资产名（下载 URL 由 downloadBase + releaseTag + asset 拼出）
 * dest  : 本仓库里的落点
 * sha   : release 自带的 .sha256sum 资产名，**必须存在**——它是我们唯一的校验基准
 */
export const GEO_ASSETS = [
  { asset: 'geosite.dat',      dest: 'geo/geosite.dat',   sha: 'geosite.dat.sha256sum' },
  { asset: 'geoip.metadb',     dest: 'geo/geoip.metadb',  sha: 'geoip.metadb.sha256sum' },
  { asset: 'GeoLite2-ASN.mmdb', dest: 'geo/ASN.mmdb',     sha: 'GeoLite2-ASN.mmdb.sha256sum' },
];

/**
 * 人类可读表头：只用在 `rules/*.txt`（人看的形态）。
 * `dist/rules/*.list` 是喂给 mihomo 的形态，**表头必须是 # 注释**（内核会跳过），
 * 且不含「生成时间」这类每次同步都会变的内容 —— 否则每次同步都会产生假变更。
 */
export const TEXT_HEADERS = {
  social: ['# Polaris 分流规则 —— 社交媒体', '# 覆盖 X / Instagram / Facebook / WhatsApp。合并自 ACL4SSR 的 Ruleset 清单。'],
  streaming: ['# Polaris 分流规则 —— 境外流媒体', '# 覆盖 YouTube / Netflix / Disney+ / HBO / Hulu / AppleTV / BBC / Abema / DAZN / Twitch / Spotify / Amazon。'],
  ai: ['# Polaris 分流规则 —— AI 服务', '# 覆盖 OpenAI / Claude / Gemini 及 ACL4SSR 的通用 AI 分类。'],
  games: ['# Polaris 分流规则 —— 游戏平台', '# 覆盖 Steam / Epic / Sony / Nintendo / Xbox。'],
  telegram: ['# Polaris 分流规则 —— 电报消息', '# 只含 Telegram 域名。'],
  tiktok: ['# Polaris 分流规则 —— TikTok', '# 只含 TikTok 域名。'],
  'china-domain': ['# Polaris 分流规则 —— 国内域名', '# ACL4SSR 主表 + 百度 / 腾讯 / 阿里 / 字节 / 微信五家大厂表。'],
  'china-ip': ['# Polaris 分流规则 —— 国内 IP 段', '# 含 IPv4、IPv6 与企业 IP；配合 GEOIP,CN 兜住 HTTPDNS 直连场景。'],
  'china-media': ['# Polaris 分流规则 —— 国内流媒体', '# 哔哩哔哩 / 网易音乐已并入国内直连。'],
  onedrive: ['# Polaris 分流规则 —— 微软云盘与微软服务', '# 默认直连（用户 2026-10-13 确定：云盘走代理太费流量）。'],
  'proxy-gfwlist': ['# Polaris 分流规则 —— 国外穿墙兜底', '# GFWList，ACL4SSR 每 2–4 天自动更新一次。'],
  'proxy-media': ['# Polaris 分流规则 —— 境外流媒体兜底', '# 不在流媒体组名单里的长尾站点。'],
  banad: ['# Polaris 分流规则 —— 广告拦截', '# 默认打开（用户 2026-10-13 确定）。'],
  banprogramad: ['# Polaris 分流规则 —— 应用净化', '# 拦截 App 内推广与启动图广告。'],
};

/**
 * App 消费形态的落点：`dist/…`。
 *
 * 为什么不直接把仓库根的 `rules/` 给 App 用：
 *  - 仓库根保持「人可读」（.txt + 表头 + 分隔注释），便于 review 与 diff；
 *  - `dist/` 是「机可读」的镜像，只有规规矩矩的规则行，mihomo rule-provider 直接吃。
 *  - `dist/` 带独立 SHA256SUMS，App 只跟 `dist/` 打交道，`node tools/verify.mjs`
 *    会把两边比对一遍，防止有人只改了根目录忘了重新生成。
 */
export const DIST_DIR = 'dist';

/** 单文件上限：超过就说明合并逻辑写错了（防止一个手滑把 1MB 的 EasyList 拉进来） */
export const MAX_OUTPUT_BYTES = 2 * 1024 * 1024;
