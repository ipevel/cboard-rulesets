# 第三方声明（Third-Party Notices）

本仓库是 **Polaris** 的规则数据分发仓库：内容全部由 `tools/sync.mjs` 从下列上游自动同步生成，
本仓库自身的脚本以根目录 `LICENSE`（GPL-3.0）发布。

## 1. 分流清单

- **ACL4SSR/ACL4SSR** — https://github.com/ACL4SSR/ACL4SSR
  - 许可证：GPL-3.0
  - 取用：`Clash/*.list` 与 `Clash/Ruleset/*.list`，按 `tools/manifest.mjs` 的 `RULE_SETS` 合并
  - 对应产出：`rules/*.txt`、`dist/rules/*.list`
  - 其中 `Clash/ProxyGFWlist.list` 由上游每 2–4 天自动更新一次（来源为 GFWList 项目，
    许可证：CC-BY-SA-4.0 — https://github.com/gfwlist/gfwlist ）

## 2. geo 数据库

- **MetaCubeX/meta-rules-dat** — https://github.com/MetaCubeX/meta-rules-dat
  - 许可证：GPL-3.0
  - 取用：`latest` release 的 `geosite.dat`、`geoip.metadb`、`GeoLite2-ASN.mmdb`，
    每个资产都对着它自带的 `.sha256sum` 校验（校验不过则拒绝同步）
  - 对应产出：`geo/*`、`dist/geo/*`
  - `GeoLite2-ASN.mmdb` 的上游数据来自 **MaxMind GeoLite2** —
    https://www.maxmind.com/en/geolite2/eula （CC BY-SA 4.0）

## 3. Bett Rules 模块

- **appshubcc/bett-rules** — https://github.com/appshubcc/bett-rules
  - 许可证：GPL-3.0
  - 取用：`master` 分支源码与规则源数据镜像到 `bett/`；`release` 分支产物镜像到 `bett-release` 分支
  - 对应产出：`bett/`、`bett-release` 分支
  - 该模块由其自身的 Go 程序从多个来源构建，其中 MaxMind 系数据库数据来自
    **MaxMind GeoLite2** — https://www.maxmind.com/en/geolite2/eula （CC BY-SA 4.0）
  - 本仓库对其规则内容不做修改，只做版本追踪与镜像，详见 `bett/UPSTREAM.md`

## 4. 运行环境（非随包分发）

- **Node.js** — https://nodejs.org （MIT）— 只在同步脚本与 CI 中使用
- **Go** — https://go.dev （BSD-3-Clause）— 仅在需要本地重建 `bett/` 的 geo 数据库时使用

## 5. 数据准确性

所有文件均为**上游内容的机械合并与去重**，本仓库不对规则的正确性、完整性或时效性作任何担保。
`PROVENANCE.md` 与 `latest.json` 记录了每次同步的上游 commit / release 坐标，便于逐次溯源。
