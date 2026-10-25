#!/usr/bin/env bash
# ============================================================
# update_and_sync.sh — 本机定时任务:
#   1. git pull 拉取 cboard-rulesets 最新 main
#   2. 重新生成 providers（双保险，与 Actions 一致）
#   3. 同步 clash-xboard-subscription.yaml 到 xboard DB (clash + clashmeta)
#   4. 若有本地改动（生成器更新源）则 commit & push
#
# 手动/备用入口。线上每日同步由 cron(北京 10:30) 调 /root/xboard-rule-sync.sh 完成;
# 该 wrapper 只做 fetch+reset+sync, 不重新生成 providers。
# ============================================================
set -euo pipefail

REPO_DIR="${REPO_DIR:-/root/cboard-rulesets}"
LOG_FILE="${LOG_FILE:-/var/log/clash-rule-sync.log}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "=== 开始规则同步 ==="

cd "$REPO_DIR"

# 1. 拉取最新
log "git pull..."
git pull --ff-only origin main 2>&1 | tee -a "$LOG_FILE" || log "WARN: git pull 失败（网络或冲突），继续用本地版本"

# 2. 生成 providers（更新源规则）
log "生成 providers..."
python3 scripts/clash_generate_providers.py --update-template 2>&1 | tail -5 | tee -a "$LOG_FILE"

# 2b. 重构为 RULE-SET（与 CI 一致，避免 generate 覆盖 CI 的 refactor 输出）
log "重构 RULE-SET..."
python3 scripts/refactor_to_rule_set.py 2>&1 | tail -5 | tee -a "$LOG_FILE"

# 2c. stash 模板已在本仓内（stash/stash-full.yaml），不再跨仓拉取；
#     但 stash 产物由 Actions 生成，这里只确保本地与远端一致（第 1 步已 pull）。
log "stash 模板: 同仓 stash/stash-full.yaml"

# 3. 若有本地生成改动则提交
if ! git diff --quiet; then
    log "检测到本地改动，commit & push..."
    git add -A
    git -c user.name="cboard-rulesets-bot" -c user.email="ipevel@users.noreply.github.com" \
        commit -m "chore: local rule regeneration $(date -u +%Y-%m-%d)" || true
    git push origin main 2>&1 | tee -a "$LOG_FILE" || log "WARN: push 失败"
fi

# 4. 同步到 xboard DB
log "同步到 xboard DB..."
python3 scripts/sync_to_xboard.py 2>&1 | tee -a "$LOG_FILE"

log "=== 同步完成 ==="
