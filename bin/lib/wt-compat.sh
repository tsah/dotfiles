wt_compat_realpath() {
    python3 - "$1" <<'PY'
import os
import sys

print(os.path.realpath(sys.argv[1]))
PY
}


wt_compat_join_path() {
    python3 - "$1" "$2" <<'PY'
import os
import sys

print(os.path.abspath(os.path.join(sys.argv[1], sys.argv[2])))
PY
}


wt_compat_sanitize_branch() {
    printf '%s\n' "$1" | tr '/\\' '-'
}


wt_compat_native_bin() {
    for candidate in "${WT_NATIVE_BIN:-}" "$HOME/.cargo/bin/wt" /usr/bin/wt /usr/local/bin/wt /home/linuxbrew/.linuxbrew/bin/wt; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    echo "Error: Could not find native Worktrunk binary" >&2
    return 1
}


wt_compat_clear_context() {
    WT_COMPAT_MODE=""
    WT_COMPAT_CONTAINER_ROOT=""
    WT_COMPAT_COMMON_DIR=""
    WT_COMPAT_WORKTREE_ROOT=""
    WT_COMPAT_REPO_NAME=""
}


wt_compat_resolve_context() {
    wt_compat_clear_context

    WT_COMPAT_TARGET_PATH=${1:-$PWD}

    WT_COMPAT_INSIDE_WORKTREE=$(git -C "$WT_COMPAT_TARGET_PATH" rev-parse --is-inside-work-tree 2>/dev/null || true)
    if [ "$WT_COMPAT_INSIDE_WORKTREE" = "true" ]; then
        WT_COMPAT_WORKTREE_ROOT=$(git -C "$WT_COMPAT_TARGET_PATH" rev-parse --show-toplevel 2>/dev/null) || return 1
        WT_COMPAT_COMMON_DIR=$(git -C "$WT_COMPAT_TARGET_PATH" rev-parse --git-common-dir 2>/dev/null) || return 1

        case "$WT_COMPAT_COMMON_DIR" in
            /*)
                ;;
            *)
                WT_COMPAT_COMMON_DIR=$(wt_compat_join_path "$WT_COMPAT_WORKTREE_ROOT" "$WT_COMPAT_COMMON_DIR")
                ;;
        esac

        WT_COMPAT_COMMON_DIR=$(wt_compat_realpath "$WT_COMPAT_COMMON_DIR")
        WT_COMPAT_CONTAINER_ROOT=$(dirname "$WT_COMPAT_COMMON_DIR")
        WT_COMPAT_REPO_NAME=$(basename "$WT_COMPAT_CONTAINER_ROOT")

        if [ "$(git --git-dir="$WT_COMPAT_COMMON_DIR" rev-parse --is-bare-repository 2>/dev/null || true)" = "true" ]; then
            WT_COMPAT_MODE="bare"
        else
            WT_COMPAT_MODE="legacy"
        fi

        return 0
    fi

    if [ -d "$WT_COMPAT_TARGET_PATH/.git" ] && [ "$(git --git-dir="$WT_COMPAT_TARGET_PATH/.git" rev-parse --is-bare-repository 2>/dev/null || true)" = "true" ]; then
        WT_COMPAT_MODE="bare"
        WT_COMPAT_CONTAINER_ROOT=$(wt_compat_realpath "$WT_COMPAT_TARGET_PATH")
        WT_COMPAT_COMMON_DIR=$(wt_compat_realpath "$WT_COMPAT_TARGET_PATH/.git")
        WT_COMPAT_WORKTREE_ROOT=""
        WT_COMPAT_REPO_NAME=$(basename "$WT_COMPAT_CONTAINER_ROOT")
        return 0
    fi

    return 1
}


wt_compat_worktrunk_config_path() {
    WT_COMPAT_CONFIG_ROOT=${1:-$WT_COMPAT_CONTAINER_ROOT}
    WT_COMPAT_CONFIG_PATH="$WT_COMPAT_CONFIG_ROOT/.worktrunk-user.toml"

    if [ -f "$WT_COMPAT_CONFIG_PATH" ]; then
        printf '%s\n' "$WT_COMPAT_CONFIG_PATH"
    fi
}


wt_compat_setup_root() {
    WT_COMPAT_SETUP_CONTAINER=${1:-$WT_COMPAT_CONTAINER_ROOT}
    WT_COMPAT_SETUP_FILE="$WT_COMPAT_SETUP_CONTAINER/.wtcompat-setup-root"

    if [ -n "${WT_SETUP_SOURCE_ROOT:-}" ]; then
        wt_compat_realpath "$WT_SETUP_SOURCE_ROOT"
        return 0
    fi

    if [ -f "$WT_COMPAT_SETUP_FILE" ]; then
        WT_COMPAT_SETUP_PATH=$(head -n 1 "$WT_COMPAT_SETUP_FILE")
        if [ -n "$WT_COMPAT_SETUP_PATH" ]; then
            case "$WT_COMPAT_SETUP_PATH" in
                /*)
                    wt_compat_realpath "$WT_COMPAT_SETUP_PATH"
                    ;;
                *)
                    wt_compat_realpath "$(wt_compat_join_path "$WT_COMPAT_SETUP_CONTAINER" "$WT_COMPAT_SETUP_PATH")"
                    ;;
            esac
            return 0
        fi
    fi

    printf '%s\n' "$WT_COMPAT_SETUP_CONTAINER"
}


wt_compat_branch_exists_local() {
    git --git-dir="$1" show-ref --verify --quiet "refs/heads/$2"
}


wt_compat_branch_exists_remote() {
    git --git-dir="$1" show-ref --verify --quiet "refs/remotes/origin/$2"
}


wt_compat_find_worktree_for_branch() {
    git --git-dir="$1" worktree list --porcelain 2>/dev/null | awk -v target="refs/heads/$2" '
        $1 == "worktree" {
            wt = substr($0, 10)
            next
        }
        $1 == "branch" && $2 == target {
            print wt
            exit
        }
    '
}


wt_compat_default_base_ref() {
    WT_COMPAT_COMMON_DIR_INPUT=$1

    WT_COMPAT_HEAD_REF=$(git --git-dir="$WT_COMPAT_COMMON_DIR_INPUT" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
    if [ -n "$WT_COMPAT_HEAD_REF" ]; then
        printf '%s\n' "$WT_COMPAT_HEAD_REF"
        return 0
    fi

    for candidate in refs/remotes/origin/main refs/remotes/origin/master refs/heads/main refs/heads/master; do
        if git --git-dir="$WT_COMPAT_COMMON_DIR_INPUT" show-ref --verify --quiet "$candidate"; then
            case "$candidate" in
                refs/remotes/*)
                    printf '%s\n' "${candidate#refs/remotes/}"
                    ;;
                refs/heads/*)
                    printf '%s\n' "${candidate#refs/heads/}"
                    ;;
            esac
            return 0
        fi
    done

    return 1
}


wt_compat_default_branch_name() {
    WT_COMPAT_BASE_REF=$(wt_compat_default_base_ref "$1" 2>/dev/null || true)

    if [ -n "$WT_COMPAT_BASE_REF" ]; then
        printf '%s\n' "${WT_COMPAT_BASE_REF#origin/}"
    fi
}


wt_compat_set_upstream() {
    git --git-dir="$1" config "branch.$2.remote" "${3:-origin}"
    git --git-dir="$1" config "branch.$2.merge" "refs/heads/$2"
}


wt_compat_session_name() {
    WT_COMPAT_SESSION_ROOT=$1
    WT_COMPAT_SESSION_BRANCH=$2
    WT_COMPAT_SESSION_BRANCH_SAFE=$(wt_compat_sanitize_branch "$WT_COMPAT_SESSION_BRANCH" | tr '@' '-')
    printf '%s@%s\n' "$(basename "$WT_COMPAT_SESSION_ROOT")" "$WT_COMPAT_SESSION_BRANCH_SAFE"
}
