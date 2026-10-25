# cboard-rulesets

Cboard 生态的统一分流规则仓库。合并自原先三个独立仓库，产物路径保持不变，仅仓库名变更，便于既有客户端平滑迁移。

| 原仓库 | 本仓路径 | 产物 | 消费者 |
|---|---|---|---|
| [polaris-rules](https://github.com/ipevel/polaris-rules) | `dist/`、`geo/`、`rules/`、`tools/` | 规则 `.list` + geo 数据库（`geosite.dat` / `geoip.metadb` / `ASN.mmdb`）+ `VERSION` / `latest.json` / `SHA256SUMS.txt` | Polaris 客户端、ckbox 的 geo 资源 |
| [clash-rulesets](https://github.com/ipevel/clash-rulesets) | `clashmeta/` | Clash Meta / Mihomo 规则 provider + Xboard 订阅模板 + MRS Bundle | ckbox、Xboard 订阅 |
| [stash-rulesets](https://github.com/ipevel/stash-rulesets) | `stash/` | Stash 规则 provider + `stash-full.yaml` | Xboard stash 订阅模板 |

## 目录

```
clashmeta/            Clash Meta 产物
  providers/*.yaml    RULE-SET 规则集
  clash-full.clash.yaml          完整配置
  clash-xboard-subscription.yaml Xboard 订阅模板
stash/                Stash 产物
  providers/          规则集
  stash-full.yaml     完整配置
dist/rules/*.list     Polaris 规则清单（AI / 地区 / 流媒体等）
dist/geo/             geo 数据库
geo/ rules/ tools/    Polaris 源数据与生成工具
scripts/              三个项目的生成 / 校验 / 同步脚本
docs/                 各项目原 README
```

## 自动更新

| 工作流 | 周期 | 职责 |
|---|---|---|
| `clash-daily.yml` | 每日 02:00 UTC | 拉上游生成 `clashmeta/providers/*.yaml` 并重构 RULE-SET |
| `stash-daily.yml` | 每日 02:00 UTC | 生成 `stash/providers/*` 与 `stash-full.yaml` |
| `polaris-sync.yml` | 每 15 分钟探测 | 上游 meta-rules-dat / ACL4SSR 变更即同步 `dist/` 与版本契约 |
| `clash-mrs-refresh.yml` | 每日 18:30 UTC | 刷新 `mrs` 分支与 `latest` release（`BundleMRS.7z`） |
| `clash-verify.yml` / `stash-verify.yml` | push / PR | 规则集自校验 |
| `polaris-schedule-probe.yml` | 定时 | 探测上游是否值得触发同步 |

三条链路互相独立，任一失败不影响其余产物；失败会留 issue 或步骤摘要。

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

## 本机同步

`scripts/update_and_sync.sh` 由 systemd timer 每日执行：拉取本仓 → 重新生成 providers → 重构 RULE-SET → 同步 `clashmeta/clash-xboard-subscription.yaml` 与 `stash/stash-full.yaml` 到 Xboard 订阅模板（id 2/3/4）并清理节点 Redis 缓存。

密钥从仓库根 `.secrets.json` 读取，已被 `.gitignore` 排除，严禁提交。

## 许可

规则数据遵循各上游许可；仓库代码见 `LICENSE`、`PROVENANCE.md`、`THIRD-PARTY-NOTICES.md`。
