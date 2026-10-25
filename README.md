# cboard-rulesets

Cboard 生态统一的分流规则仓库：一套源数据、三条产物管线，分别服务 Clash Meta / Mihomo、Stash 与 Polaris 客户端。规则由上游公开清单自动生成，仓库每日自动更新，面板与客户端按固定 URL 直接消费。

## 模块

| 模块 | 路径 | 产物 | 消费者 |
|---|---|---|---|
| Clash Meta | `clashmeta/` | 22 个分类的 RULE-SET 提供者、完整配置 `clash-full.clash.yaml`、Xboard 订阅模板 `clash-xboard-subscription.yaml` | ckbox、Xboard 订阅 |
| Stash | `stash/` | domain / ipcidr 分离的规则提供者、完整配置 `stash-full.yaml` | Xboard stash 订阅 |
| Polaris | `dist/`、`geo/`、`rules/`、`tools/` | 规则 `.list`、geo 数据库（`geosite.dat` / `geoip.metadb` / `ASN.mmdb`）、`VERSION` / `latest.json` / `SHA256SUMS.txt` | Polaris 客户端、ckbox 的 geo 资源 |

## 目录

```
clashmeta/            Clash Meta 产物
  providers/*.yaml    RULE-SET 规则集（22 个分类）
  clash-full.clash.yaml          完整配置
  clash-xboard-subscription.yaml Xboard 订阅模板
stash/                Stash 产物
  providers/          规则集（domain / ipcidr 分离）
  stash-full.yaml     完整配置
dist/rules/*.list     Polaris 规则清单（AI / 地区 / 流媒体等）
dist/geo/             geo 数据库
geo/ rules/ tools/    Polaris 源数据与生成工具
scripts/              三条管线的生成 / 校验 / 面板同步脚本
docs/                 各模块的详细文档
```

## 自动更新

| 工作流 | 周期 | 职责 |
|---|---|---|
| `daily-update.yml` | 每日 UTC 01:00（北京 09:00） | **唯一写 main 的入口**：顺序跑 Polaris 上游同步 → Clash 生成与 RULE-SET 重构 → Stash 生成，各步校验全绿后一次性提交推送 |
| `clash-mrs-refresh.yml` | 每日 UTC 18:30（北京次日 02:30） | 仅刷新 `mrs` 分支与 `latest` release（`.mrs` 产物），不碰 main |
| `clash-verify.yml` / `stash-verify.yml` | PR / 手动 | 只读校验，不生成、不提交 |

三条管线在同一 job 内串行执行、单次提交，不存在并发推送；任何一步校验失败都会让 job 变红，坏规则进不了 main。工作流用 `GITHUB_TOKEN` 推送，不会再次触发自身；`push` 触发只挂在 `tools/**`、`scripts/**` 与本工作流文件上，供改完生成逻辑后即时验证。

## 消费者地址

```
Clash 规则集   https://cdn.jsdelivr.net/gh/ipevel/cboard-rulesets@main/clashmeta/providers/
Stash 规则集   https://cdn.jsdelivr.net/gh/ipevel/cboard-rulesets@main/stash/providers/
Polaris 规则   https://raw.githubusercontent.com/ipevel/cboard-rulesets/main/dist/rules/
Polaris geo    https://cdn.jsdelivr.net/gh/ipevel/cboard-rulesets@main/dist/geo/
版本 / 清单    https://raw.githubusercontent.com/ipevel/cboard-rulesets/main/{VERSION,latest.json,SHA256SUMS.txt}
MRS Bundle     https://raw.githubusercontent.com/ipevel/cboard-rulesets/mrs/
               https://github.com/ipevel/cboard-rulesets/releases/download/latest/BundleMRS.7z
```

## 上游来源

- [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) — geo 数据库与 MRS
- [ACL4SSR/ACL4SSR](https://github.com/ACL4SSR/ACL4SSR) — Polaris 规则谱系
- [blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script) — Clash / Stash 分类规则
- [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules) — release 规则集

## 本机面板同步

面板数据库同步不在 Actions 里做（Actions 无法直连阿里云 RDS），由本机 cron 执行：

```
30 10 * * *  flock -n /var/lock/xboard-rule-sync.lock \
             timeout 900 bash /root/xboard-rule-sync.sh

# wrapper 内部：git fetch --depth 1 + reset --hard origin/main
#              → scripts/sync_to_xboard.py（写 v2_subscribe_templates id 2/3/4）
#              → 清本机 xboard-redis-1 的 template 缓存键
```

时间上比 Actions（北京 09:00）留 90 分钟余量。`scripts/update_and_sync.sh` 作为手动/备用入口保留，它会额外重新生成 providers 与 RULE-SET，日常不需要跑。

数据库凭据由 wrapper 从面板容器 `.env` 注入；也可在仓库根放 `.secrets.json`（已在 `.gitignore` 中，严禁提交）。

## 校验

```bash
# 三条管线重跑后应为零差异，即“提交状态可由上游完整复现”
python3 scripts/clash_generate_providers.py --update-template && python3 scripts/refactor_to_rule_set.py
python3 scripts/stash_generate_providers.py
node tools/verify.mjs

# 规则集校验
python3 scripts/verify_providers.py
python3 scripts/verify_stash.py
```

## 许可

规则数据遵循各上游许可；仓库代码见 `LICENSE`、`PROVENANCE.md`、`THIRD-PARTY-NOTICES.md`。
