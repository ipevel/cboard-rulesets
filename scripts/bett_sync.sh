#!/usr/bin/env bash
# 同步 bett-rules 源码与产物。
#
#   scripts/bett_sync.sh source     # 只同步源码到 bett/
#   scripts/bett_sync.sh release    # 只同步产物到 bett-release 分支
#   scripts/bett_sync.sh both       # 两者都同步（默认）
#
# 设计约定：
#   - 只有对方分支 commit SHA 变化才动作；无变化打印 unchanged 并 exit 0
#   - 源码同步是镜像语义：删除本地已不存在于对方仓库的文件
#   - 产物同步整体替换 bett-release 分支，绝不触碰主分支工作区
#   - 任何一步失败立即退出非零，由调用方决定重试或告警
set -euo pipefail

UPSTREAM_SLUG="appshubcc/bett-rules"
SRC_SUBDIR="bett"
UPSTREAM_BRANCH="master"
UPSTREAM_RELEASE_BRANCH="release"
RELEASE_BRANCH="bett-release"
SHA_FILE="${SRC_SUBDIR}/.upstream-sha"
REL_SHA_FILE=".bett-release-sha"
MODE="${1:-both}"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

api_sha() {
    local ref="$1" body
    body="$(curl -fsSL --max-time 30 \
        "https://api.github.com/repos/${UPSTREAM_SLUG}/commits/${ref}" 2>/dev/null)" || return 1
    printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])' 2>/dev/null || return 1
}

fetch_tarball() {
    local ref="$1" dest="$2"
    curl -fsSL --max-time 180 \
        "https://codeload.github.com/${UPSTREAM_SLUG}/tar.gz/refs/heads/${ref}" \
        -o "$dest" || die "下载 ${ref} 失败"
    [ -s "$dest" ] || die "下载 ${ref} 为空"
}

sync_source() {
    local want have
    want="$(api_sha "$UPSTREAM_BRANCH")" || die "取 ${UPSTREAM_BRANCH} SHA 失败"
    have="$(cat "$SHA_FILE" 2>/dev/null || echo none)"
    if [ "$want" = "$have" ]; then
        log "source: unchanged (${want:0:8})"
        return 0
    fi
    log "source: ${have:0:8} -> ${want:0:8}"

    local tmp; tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    fetch_tarball "$UPSTREAM_BRANCH" "$tmp/src.tar.gz"
    tar xzf "$tmp/src.tar.gz" -C "$tmp"
    local root; root="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'bett-rules-*' | head -1)"
    [ -n "$root" ] || die "解包后找不到源码根目录"

    # 镜像：先清空（保留本仓库自有的 UPSTREAM.md 与 SHA 记录），再复制
    find "$SRC_SUBDIR" -mindepth 1 -maxdepth 1 \
        ! -name 'UPSTREAM.md' ! -name '.upstream-sha' -exec rm -rf {} +
    cp -a "$root/." "$SRC_SUBDIR/"
    printf '%s\n' "$want" > "$SHA_FILE"
    log "source: synced ($(find "$SRC_SUBDIR" -type f | wc -l) files)"
}

sync_release() {
    local want have
    want="$(api_sha "$UPSTREAM_RELEASE_BRANCH")" || { log "release: 上游无 ${UPSTREAM_RELEASE_BRANCH} 分支，跳过"; return 0; }
    have="$(cat "$REL_SHA_FILE" 2>/dev/null || echo none)"
    if [ "$want" = "$have" ]; then
        log "release: unchanged (${want:0:8})"
        return 0
    fi
    log "release: ${have:0:8} -> ${want:0:8}"

    local tmp; tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    fetch_tarball "$UPSTREAM_RELEASE_BRANCH" "$tmp/rel.tar.gz"
    tar xzf "$tmp/rel.tar.gz" -C "$tmp"
    local root; root="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'bett-rules-*' | head -1)"
    [ -n "$root" ] || die "解包后找不到产物根目录"

    # 在独立 worktree 里替换该分支内容
    local wt; wt="$(mktemp -d)"
    trap 'rm -rf "$tmp" "$wt"' RETURN
    if git show-ref --verify --quiet "refs/heads/$RELEASE_BRANCH"; then
        git worktree add --force "$wt" "$RELEASE_BRANCH" >/dev/null
    else
        git worktree add --force --detach "$wt" >/dev/null
        git -C "$wt" checkout --orphan "$RELEASE_BRANCH" >/dev/null 2>&1
    fi
    find "$wt" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
    cp -a "$root/." "$wt/"
    printf '%s\n' "$want" > "${wt}/.upstream-release-sha"

    git -C "$wt" add -A
    if git -C "$wt" diff --cached --quiet; then
        log "release: 内容无差异，跳过提交"
    else
        git -C "$wt" -c user.name="ipevel" \
                      -c user.email="-ipevel@users.noreply.github.com" \
            commit -q -m "chore(bett): sync release artifacts ${want:0:8}"
        log "release: committed ${want:0:8}"
    fi
    printf '%s\n' "$want" > "$REL_SHA_FILE"
    # 推送由调用方负责（CI 里统一 push，本地运行时手动）
}

case "$MODE" in
    source)  sync_source ;;
    release) sync_release ;;
    both)    sync_source; sync_release ;;
    *)       die "用法: $0 [source|release|both]" ;;
esac
log "done"
