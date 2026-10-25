# MRS 规则产物（MetaCubeX `.mrs` 格式）

本分支是 `ipevel/clash-rulesets` 的 **MRS 产物分支**，只承载按分类拆分的
`.mrs` 文件，供客户端「MRS 查询」功能按需下载单个分类用。

## 目录结构

```
geo/geosite/<name>.mrs    域名分类（1924 个）
geo/geoip/<name>.mrs      IP 段分类（260 个）
VERSION                   本次产物的来源坐标与统计
```

## Raw 访问

```
https://raw.githubusercontent.com/ipevel/clash-rulesets/mrs/geo/geosite/openai.mrs
https://raw.githubusercontent.com/ipevel/clash-rulesets/mrs/geo/geoip/cn.mrs
```

客户端拼接方式：`baseUrl` + `geo/<kind>/<name>.mrs`，其中 `baseUrl` 为

```
https://raw.githubusercontent.com/ipevel/clash-rulesets/mrs/
```

## 打包下载

完整包见仓库 Release（tag `latest`）：

```
https://github.com/ipevel/clash-rulesets/releases/download/latest/BundleMRS.7z
```

包内结构与本分支一致（`geo/geosite/` + `geo/geoip/`），另附 `VERSION` 便于判断新旧。

## 来源

产物取自 [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) 的
`meta` 分支 `geo/geosite/*.mrs` 与 `geo/geoip/*.mrs`（**原生 .mrs，非转换生成**），
具体 commit 与日期记录在 `VERSION` 文件里。

`.mrs` 格式定义见 [MetaCubeX/mrs](https://github.com/MetaCubeX/mrs)。

## 用途边界

本分支只放 `.mrs`，不放 `.list` / `.yaml` / `.dat`：
分流规则产物在 `main` 分支，geo 聚合库（`geosite.dat` / `geoip.metadb` / `ASN.mmdb`）
由 `ipevel/polaris-rules` 维护。
