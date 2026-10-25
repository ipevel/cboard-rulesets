#!/usr/bin/env bash
# =============================================================================
# mrs_refresh.sh —— 刷新 MRS Bundle 产物并发布
#
# 流程（顺序刻意如此，任何一步失败都不污染线上资产）：
#   1. 稀疏拉取上游 MetaCubeX/meta-rules-dat@meta 的原生 .mrs
#   2. 与「线上已发布状态」比对：上游 commit 没变 → 直接退出（不更新）
#      线上状态取自 latest release 说明里的机器可读标记（<!-- upstream_commit: … -->），
#      **不是**看分支——否则「分支推成功但发布失败」会被误判成无需更新。
#   3. 组装新树 geo/ + VERSION，打成 BundleMRS.7z
#   4. 完整校验：解包 diff、计数、sha256 —— 任一项不过就退出，**绝不碰线上资产**
#   5. 推进 mrs 分支（普通快进提交，不 force push），拿到本仓新 commit 作为 tag 目标
#   6. 发布：
#      a) 日期 tag  release  mrs-YYYYMMDD   （独立 release，作滚动空窗期的兜底回退点）
#      b) 滚动 tag  release  latest          （替换资产；新资产先传临时名，删旧后改名，空窗最短）
#
# 约定：
#   - `latest` 专属 MRS Bundle；分流规则自身发版用 `rules/vX.Y.Z`（见 README）
#   - 形态与客户端自带 bundle 一致：只有 geo/geosite + geo/geoip + VERSION，不含 asn/ 与 geo-lite/
#
# 环境变量：
#   GITHUB_TOKEN  必需（发布用）      UPSTREAM_REPO / UPSTREAM_BRANCH  可覆盖
#   MRS_BRANCH    默认 mrs            ROLLING_TAG  默认 latest          DATE_TAG 可覆盖（测试用）
#   FORCE_REFRESH =1 忽略「上游无变化」判断强制重建
# =============================================================================
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-MetaCubeX/meta-rules-dat}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-meta}"
MRS_BRANCH="${MRS_BRANCH:-mrs}"
ROLLING_TAG="${ROLLING_TAG:-latest}"
REPO="${GITHUB_REPOSITORY:-ipevel/cboard-rulesets}"
API="https://api.github.com/repos/${REPO}"
WORK="${RUNNER_TEMP:-/tmp}/mrs-refresh"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
die() { log "ERROR: $*"; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "缺少工具 $1"; }
need curl; need git; need tar; need sha256sum
if command -v 7z >/dev/null 2>&1; then SEVENZ="$(command -v 7z)"; elif command -v 7za >/dev/null 2>&1; then SEVENZ="$(command -v 7za)"; else die "缺少 7z"; fi
[ -n "${GITHUB_TOKEN:-}" ] || die "缺少 GITHUB_TOKEN"

rm -rf "$WORK"; mkdir -p "$WORK"

api() { # api <method> <path> [data-file] —— **必须检查 HTTP 状态码**，否则失败请求会被当成成功
  local method="$1" path="$2" data="${3:-}" out code
  if [ -n "$data" ]; then
    out="$(curl -sS -w '\n%{http_code}' -X "$method" -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" \
      -d @"$data" "$API$path")" || { echo "api $method $path 传输失败" >&2; return 1; }
  else
    out="$(curl -sS -w '\n%{http_code}' -X "$method" -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" "$API$path")" || { echo "api $method $path 传输失败" >&2; return 1; }
  fi
  code="$(printf '%s' "$out" | tail -n1)"
  printf '%s' "$out" | sed '$d' > "$WORK/.api-body"
  if [ "$code" -lt 200 ] || [ "$code" -ge 300 ]; then
    echo "api $method $path → HTTP $code：$(head -c 300 "$WORK/.api-body")" >&2
    return 1
  fi
  cat "$WORK/.api-body"
}

# ---- 1. 拉上游 -------------------------------------------------------------
log "拉取上游 ${UPSTREAM_REPO}@${UPSTREAM_BRANCH}（仅 .mrs）"
git clone --depth 1 --branch "$UPSTREAM_BRANCH" --filter=blob:none --sparse \
  "https://github.com/${UPSTREAM_REPO}.git" "$WORK/upstream" >/dev/null 2>&1 || die "克隆上游失败"
( cd "$WORK/upstream" && git sparse-checkout set --no-cone '/geo/geosite/*.mrs' '/geo/geoip/*.mrs' ) >/dev/null 2>&1 \
  || die "sparse-checkout 失败"
UPSTREAM_SHA="$(git -C "$WORK/upstream" rev-parse HEAD)"
UPSTREAM_DATE="$(git -C "$WORK/upstream" log -1 --format=%cI)"
log "上游 commit: $UPSTREAM_SHA（$UPSTREAM_DATE）"

# ---- 2. 变更判定：与线上已发布状态比对 --------------------------------------
PUBLISHED_SHA=""
ROLLING_REL_ID=""
if ROLLING_REL_ID="$(api GET "/releases/tags/${ROLLING_TAG}" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);process.stdout.write(j.id?String(j.id):"")}catch(e){}})')"; then
  PUBLISHED_SHA="$(api GET "/releases/${ROLLING_REL_ID}" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);const m=/<!--\s*upstream_commit:\s*([0-9a-f]{40})\s*-->/.exec(j.body||"");process.stdout.write(m?m[1]:"")}catch(e){}})')"
fi
if [ -n "$PUBLISHED_SHA" ] && [ "$PUBLISHED_SHA" = "$UPSTREAM_SHA" ] && [ "${FORCE_REFRESH:-0}" != "1" ]; then
  log "线上已是上游 $UPSTREAM_SHA，无需更新"
  echo "no_change=true" >> "$GITHUB_OUTPUT"
  exit 0
fi
log "需要更新：线上 ${PUBLISHED_SHA:-（无）} → 上游 $UPSTREAM_SHA"

# ---- 3. 组装新树 ----------------------------------------------------------
TREE="$WORK/tree"; mkdir -p "$TREE/geo"
cp -r "$WORK/upstream/geo/geosite" "$TREE/geo/"
cp -r "$WORK/upstream/geo/geoip" "$TREE/geo/"
GS=$(find "$TREE/geo/geosite" -name '*.mrs' | wc -l | tr -d ' ')
GI=$(find "$TREE/geo/geoip"   -name '*.mrs' | wc -l | tr -d ' ')
[ "$GS" -gt 0 ] || die "geosite 产物为空"
[ "$GI" -gt 0 ] || die "geoip 产物为空"
log "产物：geosite $GS 个 / geoip $GI 个"

PAYLOAD_SHA="$( (cd "$TREE" && find geo -name '*.mrs' -type f | sort | xargs sha256sum) | sha256sum | awk '{print $1}')"
FETCHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$TREE/VERSION" <<EOF
mrs_bundle_version: 1
source: ${UPSTREAM_REPO}@${UPSTREAM_BRANCH}
source_commit: ${UPSTREAM_SHA}
source_date: ${UPSTREAM_DATE}
geosite_files: ${GS}
geoip_files: ${GI}
payload_sha256: ${PAYLOAD_SHA}
fetched_at: ${FETCHED_AT}
built_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
[ -f "mrs-branch/README.md" ] && cp mrs-branch/README.md "$TREE/README.md"

# ---- 4. 打包 + 完整校验（不过就退出，不碰线上）-----------------------------
log "打包 BundleMRS.7z"
(cd "$TREE" && "$SEVENZ" a -t7z -m0=LZMA2 -mx=9 "$WORK/BundleMRS.7z" geo VERSION >/dev/null) || die "打包失败"
BUNDLE_SHA="$(sha256sum "$WORK/BundleMRS.7z" | awk '{print $1}')"
BUNDLE_SIZE="$(stat -c %s "$WORK/BundleMRS.7z")"
log "产物 sha256 $BUNDLE_SHA（$BUNDLE_SIZE B）"

log "校验：解包回环"
rm -rf "$WORK/vfy"; mkdir -p "$WORK/vfy"
"$SEVENZ" x -y "$WORK/BundleMRS.7z" "-o$WORK/vfy" >/dev/null || die "解包失败"
VGS=$(find "$WORK/vfy/geo/geosite" -name '*.mrs' | wc -l | tr -d ' ')
VGI=$(find "$WORK/vfy/geo/geoip"   -name '*.mrs' | wc -l | tr -d ' ')
[ "$VGS" = "$GS" ] || die "解包后 geosite 计数不符：$VGS ≠ $GS"
[ "$VGI" = "$GI" ] || die "解包后 geoip 计数不符：$VGI ≠ $GI"
diff -r "$WORK/vfy/geo" "$TREE/geo" >/dev/null || die "解包内容与源树不一致"
[ -f "$WORK/vfy/VERSION" ] || die "解包后缺 VERSION"
log "校验通过：geosite $VGS / geoip $VGI，内容与源树逐字节一致"

DATE_TAG="${DATE_TAG:-mrs-$(date -u +%Y%m%d)}"

# ---- 5. 推进 mrs 分支（普通快进提交，不 force）→ 得到本仓 commit 作 tag 目标
log "推进 $MRS_BRANCH 分支"
printf '%s  BundleMRS.7z\n' "$BUNDLE_SHA" > "mrs-branch/BUNDLE.sha256"
rm -rf mrs-branch/geo
cp -r "$TREE/geo" mrs-branch/geo
cp "$TREE/VERSION" mrs-branch/VERSION
( cd mrs-branch && git add -A \
  && git -c user.name="mrs-refresh-bot" -c user.email="mrs-refresh-bot@users.noreply.github.com" \
       commit -q -m "chore(mrs): 刷新上游 meta 分支产物（${UPSTREAM_SHA:0:8}）" \
       -m "上游 ${UPSTREAM_REPO}@${UPSTREAM_BRANCH} @ ${UPSTREAM_SHA}" \
       -m "资产 sha256 ${BUNDLE_SHA}（${BUNDLE_SIZE} B）" \
  && git push origin "HEAD:${MRS_BRANCH}" ) || die "推进 $MRS_BRANCH 分支失败"
TARGET_COMMIT="$(git -C mrs-branch rev-parse HEAD)"
log "mrs 分支新 commit: $TARGET_COMMIT（tag 目标）"

# ---- 6. 发布 ---------------------------------------------------------------
MARK="<!-- upstream_commit: ${UPSTREAM_SHA} -->"
BODY_COMMON="上游：${UPSTREAM_REPO}@${UPSTREAM_BRANCH} commit \`${UPSTREAM_SHA}\`（${UPSTREAM_DATE}）
- 资产：\`BundleMRS.7z\`，${BUNDLE_SIZE} B，sha256 \`${BUNDLE_SHA}\`
- 内容：\`geo/geosite/\` ${GS} 个 + \`geo/geoip/\` ${GI} 个 + \`VERSION\`
- 载荷摘要 payload_sha256：\`${PAYLOAD_SHA}\`
- 形态：原生 .mrs（未转码）；不含 asn/ 与 geo-lite/"

upload_asset() { # <release_id> <name> <file>
  curl -sS -X POST -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Content-Type: application/octet-stream" --data-binary @"$3" \
    "https://uploads.github.com/repos/${REPO}/releases/$1/assets?name=$2"
}
delete_asset() { curl -sS -o /dev/null -X DELETE -H "Authorization: Bearer ${GITHUB_TOKEN}" "$API/releases/assets/$1"; }
release_id_of() { # <tag> → release id（空串=不存在；404 是正常情况，不算错误）
  local out code
  out="$(curl -sS -w '\n%{http_code}' -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" "$API/releases/tags/$1" 2>/dev/null)" || { echo ""; return 0; }
  code="$(printf '%s' "$out" | tail -n1)"
  if [ "$code" = "404" ]; then echo ""; return 0; fi
  if [ "$code" -lt 200 ] || [ "$code" -ge 300 ]; then echo ""; return 0; fi
  printf '%s' "$out" | sed '$d' | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);process.stdout.write(j.id?String(j.id):"")}catch(e){}})'
}

publish_date_release() {
  local rid aid
  rid="$(release_id_of "$DATE_TAG")"
  if [ -n "$rid" ]; then
    log "  日期 release 已存在（id=$rid），替换其资产"
    for aid in $(api GET "/releases/$rid/assets" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{JSON.parse(s).forEach(a=>process.stdout.write(a.id+" "))}catch(e){}})'); do
      delete_asset "$aid"
    done
  else
    node -e '
      const fs=require("fs");
      const body=process.argv[1];
      fs.writeFileSync(process.argv[2], JSON.stringify({
        tag_name: process.argv[3], target_commitish: process.argv[4],
        name: "MRS Bundle "+process.argv[3], body, draft:false, prerelease:false }));' \
      "$BODY_COMMON" "$WORK/rel-date.json" "$DATE_TAG" "$TARGET_COMMIT"
    rid="$(api POST "/releases" "$WORK/rel-date.json" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);if(!j.id){console.error(JSON.stringify(j).slice(0,300));process.exit(1)}process.stdout.write(String(j.id))}catch(e){process.exit(1)}})')" \
      || die "创建日期 release 失败"
  fi
  upload_asset "$rid" "BundleMRS.7z" "$WORK/BundleMRS.7z" \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);if(!j.id){console.error(JSON.stringify(j).slice(0,300));process.exit(1)}}catch(e){process.exit(1)}})' \
    || die "上传日期 release 资产失败"
  echo "date_release_id=$rid" >> "$GITHUB_OUTPUT"
}

publish_rolling() {
  local rid aid new_aid
  rid="$(release_id_of "$ROLLING_TAG")"
  if [ -z "$rid" ]; then
    node -e '
      const fs=require("fs");
      fs.writeFileSync(process.argv[2], JSON.stringify({
        tag_name: process.argv[3], target_commitish: process.argv[4],
        name: "MRS Bundle (rolling latest)", body: process.argv[1],
        draft:false, prerelease:false }));' \
      "$BODY_COMMON" "$WORK/rel-roll.json" "$ROLLING_TAG" "$TARGET_COMMIT"
    rid="$(api POST "/releases" "$WORK/rel-roll.json" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);if(!j.id){console.error(JSON.stringify(j).slice(0,300));process.exit(1)}process.stdout.write(String(j.id))}catch(e){process.exit(1)}})')" \
      || die "创建滚动 release 失败"
  fi
  upload_asset "$rid" "BundleMRS.7z.new" "$WORK/BundleMRS.7z" >/dev/null || die "上传临时资产失败"
  new_aid="$(api GET "/releases/$rid/assets" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);const a=j.find(x=>x.name==="BundleMRS.7z.new");process.stdout.write(a?String(a.id):"")}catch(e){}})')"
  [ -n "$new_aid" ] || die "找不到刚上传的临时资产"
  for aid in $(api GET "/releases/$rid/assets" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{JSON.parse(s).forEach(a=>{if(a.name==="BundleMRS.7z")process.stdout.write(a.id+" ")})}catch(e){}})'); do
    delete_asset "$aid"
  done
  printf '{"name":"BundleMRS.7z"}' > "$WORK/rename.json"
  api PATCH "/releases/assets/$new_aid" "$WORK/rename.json" >/dev/null || die "资产改名失败"
  # release 说明更新为本次产物（同时是下次「已发布状态」的判读来源）
  # 显式带上 draft=false：PATCH 只给 body 时 GitHub 可能保留/漂移出 draft 态，
  # 那样资产对公网不可见（下载 404），必须显式钉住。
  node -e '
    const fs=require("fs");
    fs.writeFileSync(process.argv[2], JSON.stringify({body: process.argv[1], draft:false, prerelease:false}));' \
    "$BODY_COMMON
$MARK" "$WORK/body.json"
  api PATCH "/releases/$rid" "$WORK/body.json" >/dev/null || die "更新 release 说明失败"
  # tag 移到本次产物所在 commit：用 PATCH 改 ref（**不要删了再建**——删 tag 会让关联
  # release 的状态漂移，历史上就因此把 latest 弄成过 draft、资产对外不可见）
  printf '{"sha":"%s"}' "$TARGET_COMMIT" > "$WORK/tagmove.json"
  api PATCH "/git/refs/tags/${ROLLING_TAG}" "$WORK/tagmove.json" >/dev/null || die "移动 $ROLLING_TAG tag 失败"
  echo "rolling_release_id=$rid" >> "$GITHUB_OUTPUT"
}

for attempt in 1 2; do
  log "发布（第 $attempt 次尝试）"
  if publish_date_release && publish_rolling; then break; fi
  if [ "$attempt" = 1 ]; then log "首次发布失败，重试一次"; sleep 20; else die "发布连续两次失败，放弃（线上资产保持原状）"; fi
done

# ---- 6b. 发布后可达性断言（公网实际拉一次）--------------------------------
# 资产存在 ≠ 对外可下载：release 若是 draft 态，下载会返回 404 页面。
# 所以这里从公网 URL 实拉，校验 HTTP 200 + 体积 + sha256 三项，任一不符即判定发布失败。
log "校验公网可达性"
DL_URL="https://github.com/${REPO}/releases/download/${ROLLING_TAG}/BundleMRS.7z"
HTTP_CODE="$(curl -sSL -o "$WORK/dl.7z" -w '%{http_code}' "$DL_URL" || echo 000)"
DL_SIZE="$(stat -c %s "$WORK/dl.7z" 2>/dev/null || echo 0)"
DL_SHA="$(sha256sum "$WORK/dl.7z" 2>/dev/null | awk '{print $1}')"
log "  HTTP $HTTP_CODE / $DL_SIZE B / sha256 $DL_SHA"
[ "$HTTP_CODE" = "200" ] || die "公网下载失败：HTTP $HTTP_CODE（release 可能是 draft 态或资产已删）"
[ "$DL_SIZE" = "$BUNDLE_SIZE" ] || die "公网下载体积不符：$DL_SIZE ≠ $BUNDLE_SIZE"
[ "$DL_SHA" = "$BUNDLE_SHA" ] || die "公网下载 sha256 不符"
# 解包计数复核
rm -rf "$WORK/dlchk"; mkdir -p "$WORK/dlchk"
"$SEVENZ" x -y "$WORK/dl.7z" "-o$WORK/dlchk" >/dev/null || die "公网下载件解包失败"
DGS=$(find "$WORK/dlchk/geo/geosite" -name '*.mrs' | wc -l | tr -d ' ')
DGI=$(find "$WORK/dlchk/geo/geoip"   -name '*.mrs' | wc -l | tr -d ' ')
[ "$DGS" = "$GS" ] && [ "$DGI" = "$GI" ] || die "公网下载件计数不符：geosite $DGS / geoip $DGI"
log "公网可达性校验通过（geosite $DGS / geoip $DGI）"

echo "no_change=false" >> "$GITHUB_OUTPUT"
echo "upstream_sha=$UPSTREAM_SHA" >> "$GITHUB_OUTPUT"
echo "bundle_sha256=$BUNDLE_SHA" >> "$GITHUB_OUTPUT"
echo "bundle_size=$BUNDLE_SIZE" >> "$GITHUB_OUTPUT"
echo "geosite_files=$GS" >> "$GITHUB_OUTPUT"
echo "geoip_files=$GI" >> "$GITHUB_OUTPUT"
echo "date_tag=$DATE_TAG" >> "$GITHUB_OUTPUT"
echo "target_commit=$TARGET_COMMIT" >> "$GITHUB_OUTPUT"
log "完成"
