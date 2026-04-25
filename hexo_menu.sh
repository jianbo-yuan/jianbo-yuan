#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
HEXO_CLI="$PROJECT_DIR/node_modules/hexo/bin/hexo"
PROXY_VARS=(http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY)

if command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold)"
  RED="$(tput setaf 1)"
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  BLUE="$(tput setaf 4)"
  MAGENTA="$(tput setaf 5)"
  CYAN="$(tput setaf 6)"
  RESET="$(tput sgr0)"
else
  BOLD=""
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  MAGENTA=""
  CYAN=""
  RESET=""
fi

log_info() {
  printf "%s[INFO]%s %s\n" "$CYAN" "$RESET" "$1"
}

log_success() {
  printf "%s[SUCCESS]%s %s\n" "$GREEN" "$RESET" "$1"
}

log_warn() {
  printf "%s[WARN]%s %s\n" "$YELLOW" "$RESET" "$1"
}

log_error() {
  printf "%s[ERROR]%s %s\n" "$RED" "$RESET" "$1"
}

pause() {
  printf "\n按回车继续..."
  read -r _
}

ensure_project_dir() {
  cd "$PROJECT_DIR" || {
    log_error "无法进入项目目录: $PROJECT_DIR"
    exit 1
  }

  if [[ ! -f "package.json" || ! -f "_config.yml" ]]; then
    log_error "当前目录不是有效的 Hexo 项目根目录"
    exit 1
  fi

  if [[ ! -f "$HEXO_CLI" ]]; then
    log_error "未找到本地 Hexo CLI: $HEXO_CLI"
    log_info "请先执行菜单中的“安装依赖”，或手动运行 npm install"
    exit 1
  fi

  warn_missing_theme_renderer
}

run_cmd() {
  local description="$1"
  shift

  printf "\n%s>> %s%s\n" "$BOLD" "$description" "$RESET"
  "$@"
  local status=$?

  if [[ $status -eq 0 ]]; then
    log_success "$description 完成"
  else
    log_error "$description 失败，退出码: $status"
  fi

  return $status
}

prompt_non_empty() {
  local prompt="$1"

  while true; do
    printf "%s" "$prompt"
    read -r REPLY
    if [[ -n "$REPLY" ]]; then
      return 0
    fi
    log_warn "输入不能为空，请重新输入。"
  done
}

run_hexo() {
  node "$HEXO_CLI" "$@"
}

run_without_proxy() {
  env \
    -u http_proxy \
    -u https_proxy \
    -u all_proxy \
    -u HTTP_PROXY \
    -u HTTPS_PROXY \
    -u ALL_PROXY \
    "$@"
}

get_current_theme() {
  local theme_name
  theme_name="$(awk -F': ' '/^theme:/ {print $2}' _config.yml | tail -n 1 | tr -d '\r')"
  printf "%s" "${theme_name:-}"
}

warn_missing_theme_renderer() {
  local theme_name theme_dir
  theme_name="$(get_current_theme)"
  theme_dir="$PROJECT_DIR/themes/$theme_name"

  if [[ -z "$theme_name" || ! -d "$theme_dir" ]]; then
    return 0
  fi

  if find "$theme_dir/layout" -type f -name '*.pug' | read -r _; then
    if [[ ! -d "$PROJECT_DIR/node_modules/hexo-renderer-pug" ]]; then
      log_warn "当前主题 $theme_name 使用 Pug 模板，但未安装 hexo-renderer-pug。"
      log_warn "否则生成结果可能直接输出模板源码，而不是正常 HTML。"
      log_info "请先执行: npm install"
    fi
  fi
}

get_site_root() {
  local root_path
  root_path="$(awk -F': ' '/^root:/ {print $2}' _config.yml | tail -n 1 | tr -d '\r')"
  root_path="${root_path:-/}"

  if [[ "$root_path" != /* ]]; then
    root_path="/$root_path"
  fi

  if [[ "$root_path" != */ ]]; then
    root_path="$root_path/"
  fi

  printf "%s" "$root_path"
}

has_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

ensure_git_repo() {
  if has_git_repo; then
    return 0
  fi

  log_error "当前目录不是 Git 仓库，无法执行源码同步操作。"
  return 1
}

get_git_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || printf "unknown"
}

get_git_remote_url() {
  git remote get-url origin 2>/dev/null || true
}

get_repo_slug() {
  local remote_url
  remote_url="$(get_git_remote_url)"

  if [[ "$remote_url" =~ ^https://github\.com/([^/]+)/([^/.]+)(\.git)?$ ]]; then
    printf "%s/%s" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  if [[ "$remote_url" =~ ^git@github\.com:([^/]+)/([^/.]+)(\.git)?$ ]]; then
    printf "%s/%s" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  return 1
}

get_git_dirty_count() {
  if ! has_git_repo; then
    printf "0"
    return 0
  fi

  git status --porcelain 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' '
}

get_git_status_label() {
  local dirty_count

  if ! has_git_repo; then
    printf "not-a-repo"
    return 0
  fi

  dirty_count="$(get_git_dirty_count)"
  if [[ "$dirty_count" == "0" ]]; then
    printf "clean"
  else
    printf "dirty (%s)" "$dirty_count"
  fi
}

has_pages_workflow() {
  [[ -f "$PROJECT_DIR/.github/workflows/pages.yml" ]]
}

get_pages_mode_label() {
  if has_pages_workflow; then
    printf "GitHub Actions -> Pages"
  else
    printf "local deploy or legacy flow"
  fi
}

prompt_with_default() {
  local prompt="$1"
  local default_value="$2"

  printf "%s [%s]: " "$prompt" "$default_value"
  read -r REPLY
  REPLY="${REPLY:-$default_value}"
}

has_proxy_env() {
  local var_name=""

  for var_name in "${PROXY_VARS[@]}"; do
    if [[ -n "${!var_name:-}" ]]; then
      return 0
    fi
  done

  return 1
}

has_local_proxy_env() {
  local var_name=""
  local value=""

  for var_name in "${PROXY_VARS[@]}"; do
    value="${!var_name:-}"
    if [[ "$value" =~ ^[[:alpha:]][[:alnum:]+.-]*://(127\.0\.0\.1|localhost):[0-9]+/? ]] || [[ "$value" =~ ^(127\.0\.0\.1|localhost):[0-9]+/? ]]; then
      return 0
    fi
  done

  return 1
}

get_first_proxy_value() {
  local var_name=""

  for var_name in "${PROXY_VARS[@]}"; do
    if [[ -n "${!var_name:-}" ]]; then
      printf "%s" "${!var_name}"
      return 0
    fi
  done

  return 1
}

extract_local_proxy_host_port() {
  local value
  value="$(get_first_proxy_value 2>/dev/null || true)"

  if [[ "$value" =~ ^[[:alpha:]][[:alnum:]+.-]*://(127\.0\.0\.1|localhost):([0-9]+)/*$ ]]; then
    printf "%s %s" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  if [[ "$value" =~ ^(127\.0\.0\.1|localhost):([0-9]+)/*$ ]]; then
    printf "%s %s" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  return 1
}

is_local_proxy_reachable() {
  local host_port host port

  host_port="$(extract_local_proxy_host_port 2>/dev/null || true)"
  if [[ -z "$host_port" ]]; then
    return 1
  fi

  host="${host_port%% *}"
  port="${host_port##* }"

  if [[ -z "$host" || -z "$port" ]]; then
    return 1
  fi

  bash -c "exec 3<>/dev/tcp/$host/$port" >/dev/null 2>&1
}

has_dead_local_proxy() {
  has_local_proxy_env && ! is_local_proxy_reachable
}

show_proxy_envs() {
  local var_name=""

  for var_name in "${PROXY_VARS[@]}"; do
    if [[ -n "${!var_name:-}" ]]; then
      printf "  - %s=%s\n" "$var_name" "${!var_name}"
    fi
  done
}

run_cmd_without_proxy() {
  local description="$1"
  shift

  printf "\n%s>> %s%s\n" "$BOLD" "$description" "$RESET"
  run_without_proxy "$@"
  local status=$?

  if [[ $status -eq 0 ]]; then
    log_success "$description 完成"
  else
    log_error "$description 失败，退出码: $status"
  fi

  return $status
}

run_network_cmd() {
  local description="$1"
  shift

  if has_dead_local_proxy; then
    log_warn "检测到本地代理环境变量，但代理端口不可达："
    show_proxy_envs
    log_info "本次将临时禁用代理执行网络命令。"
    run_cmd_without_proxy "$description" "$@"
    return $?
  fi

  run_cmd "$description" "$@"
  local status=$?

  if [[ $status -ne 0 ]] && has_proxy_env; then
    retry_command_without_proxy "$description" "$@"
    status=$?
  fi

  return $status
}

retry_command_without_proxy() {
  local description="$1"
  shift
  local answer=""
  local default_hint="y/N"

  log_warn "检测到当前终端存在代理环境变量："
  show_proxy_envs

  if has_local_proxy_env; then
    log_warn "当前代理指向本机地址，若本地代理程序未启动，请求会失败。"
    default_hint="Y/n"
  fi

  printf "是否本次临时禁用代理后重试%s？(%s): " "$description" "$default_hint"
  read -r answer

  if has_local_proxy_env; then
    if [[ "$answer" =~ ^[Nn]$ ]]; then
      return 1
    fi
  else
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
      return 1
    fi
  fi

  run_cmd_without_proxy "$description（临时禁用代理）" "$@"
}

fix_hexo_permissions() {
  local fixed=false

  if [[ -f "node_modules/.bin/hexo" && ! -x "node_modules/.bin/hexo" ]]; then
    chmod +x "node_modules/.bin/hexo"
    fixed=true
  fi

  if [[ -f "$HEXO_CLI" && ! -x "$HEXO_CLI" ]]; then
    chmod +x "$HEXO_CLI"
    fixed=true
  fi

  if [[ "$fixed" == true ]]; then
    log_info "已修复本地 Hexo 可执行文件权限"
  fi
}

show_header() {
  clear 2>/dev/null || true
  local theme_name branch_name repo_slug status_label pages_mode status_color

  theme_name="$(get_current_theme)"
  branch_name="$(get_git_branch)"
  repo_slug="$(get_repo_slug 2>/dev/null || printf "not-configured")"
  status_label="$(get_git_status_label)"
  pages_mode="$(get_pages_mode_label)"
  status_color="$GREEN"

  if [[ "$status_label" != "clean" ]]; then
    status_color="$YELLOW"
  fi

  printf "%sHexo Workspace Console%s\n" "$BOLD" "$RESET"
  printf '%s\n' "------------------------------------------------------------"
  printf "%sProject%s : %s\n" "$BLUE" "$RESET" "$PROJECT_DIR"
  printf "%sTheme%s   : %s\n" "$MAGENTA" "$RESET" "${theme_name:-unknown}"
  printf "%sBranch%s  : %s\n" "$CYAN" "$RESET" "$branch_name"
  printf "%sRepo%s    : %s\n" "$CYAN" "$RESET" "$repo_slug"
  printf "%sStatus%s  : %s%s%s\n" "$YELLOW" "$RESET" "$status_color" "$status_label" "$RESET"
  printf "%sPages%s   : %s%s%s\n" "$GREEN" "$RESET" "$GREEN" "$pages_mode" "$RESET"
  printf "%sSync%s    : %shexo clean -> hexo generate -> git push source%s\n" "$GREEN" "$RESET" "$BOLD" "$RESET"
  printf '%s\n\n' "------------------------------------------------------------"
}

show_menu() {
  printf "%s[Build]%s\n" "$BLUE" "$RESET"
  printf "  %s1.%s 安装依赖 npm install\n" "$BLUE" "$RESET"
  printf "  %s2.%s 清理缓存 hexo clean\n" "$BLUE" "$RESET"
  printf "  %s3.%s 生成静态文件 hexo generate\n" "$BLUE" "$RESET"
  printf "  %s4.%s 本地预览 hexo server\n\n" "$BLUE" "$RESET"
  printf "%s[Hexo Sync]%s\n" "$GREEN" "$RESET"
  printf "  %s5.%s 查看 Hexo / GitHub 同步状态\n" "$GREEN" "$RESET"
  printf "  %s6.%s 仅同步当前分支到 GitHub\n" "$GREEN" "$RESET"
  printf "  %s7.%s Hexo 一键同步 clean + generate + push\n" "$GREEN" "$RESET"
  printf "  %s8.%s 创建或生成 Pull Request\n\n" "$GREEN" "$RESET"
  printf "%s[Content]%s\n" "$YELLOW" "$RESET"
  printf "  %s9.%s 新建文章 post\n" "$YELLOW" "$RESET"
  printf " %s10.%s 新建页面 page\n" "$YELLOW" "$RESET"
  printf " %s11.%s 新建草稿 draft\n" "$YELLOW" "$RESET"
  printf " %s12.%s 发布草稿 publish\n\n" "$YELLOW" "$RESET"
  printf "%s[Project]%s\n" "$MAGENTA" "$RESET"
  printf " %s13.%s 查看项目概况\n" "$MAGENTA" "$RESET"
  printf "  %s0.%s 退出\n\n" "$MAGENTA" "$RESET"
  printf "请输入选项 [0-13]: "
}

install_deps() {
  run_network_cmd "安装依赖" npm install || return $?
  fix_hexo_permissions
}

hexo_clean() {
  run_cmd "清理缓存" run_hexo clean
}

hexo_generate() {
  run_cmd "生成静态文件" run_hexo generate
}

hexo_server() {
  printf "端口号（默认 4000）: "
  read -r port
  port="${port:-4000}"
  local root_path
  root_path="$(get_site_root)"

  printf "\n本地预览地址: http://localhost:%s%s\n" "$port" "$root_path"
  printf "不要直接打开 http://localhost:%s/ ，当前站点配置了仓库页根路径。\n" "$port"
  printf "按 Ctrl+C 停止本地服务并返回菜单。\n\n"
  run_hexo server -p "$port"
}

create_post() {
  local title
  prompt_non_empty "请输入文章标题: "
  title="$REPLY"
  run_cmd "新建文章" run_hexo new post "$title"
}

create_page() {
  local title
  prompt_non_empty "请输入页面名称: "
  title="$REPLY"
  run_cmd "新建页面" run_hexo new page "$title"
}

create_draft() {
  local title
  prompt_non_empty "请输入草稿标题: "
  title="$REPLY"
  run_cmd "新建草稿" run_hexo new draft "$title"
}

publish_draft() {
  local title
  prompt_non_empty "请输入草稿标题: "
  title="$REPLY"
  run_cmd "发布草稿" run_hexo publish "$title"
}

show_git_repo_status() {
  ensure_git_repo || return $?

  local repo_slug branch_name
  repo_slug="$(get_repo_slug 2>/dev/null || printf "not-configured")"
  branch_name="$(get_git_branch)"

  printf "\n%s源码仓库状态%s\n" "$BOLD" "$RESET"
  printf "仓库: %s\n" "$repo_slug"
  printf "分支: %s\n" "$branch_name"
  printf "远程: %s\n\n" "$(get_git_remote_url)"

  git status --short
  printf "\n最近提交:\n"
  git log --oneline -5
}

ensure_origin_remote() {
  if git remote get-url origin >/dev/null 2>&1; then
    return 0
  fi

  prompt_non_empty "请输入 GitHub 远程仓库地址: "
  run_cmd "添加 origin 远程仓库" git remote add origin "$REPLY"
}

sync_current_branch() {
  ensure_git_repo || return $?
  ensure_origin_remote || return $?

  local branch_name commit_message dirty_count
  branch_name="$(get_git_branch)"

  if [[ -z "$branch_name" || "$branch_name" == "HEAD" ]]; then
    log_error "当前处于游离 HEAD 状态，请先切换到命名分支。"
    return 1
  fi

  dirty_count="$(get_git_dirty_count)"
  printf "\n当前分支: %s\n" "$branch_name"

  if [[ "$dirty_count" != "0" ]]; then
    printf "检测到 %s 个未同步改动，以下内容将被纳入本次提交：\n\n" "$dirty_count"
    git status --short
    printf "\n"

    prompt_with_default "请输入提交信息" "chore: sync workspace $(date '+%Y-%m-%d %H:%M:%S')"
    commit_message="$REPLY"

    run_cmd "暂存当前工作区改动" git add -A || return $?

    if git diff --cached --quiet; then
      log_warn "暂存区为空，本次只执行推送。"
    else
      run_cmd "提交当前工作区改动" git commit -m "$commit_message" || return $?
    fi
  else
    log_info "工作区已干净，直接推送当前分支。"
  fi

  run_network_cmd "推送分支 $branch_name 到 GitHub" git push -u origin "$branch_name"
}

build_and_sync() {
  run_hexo clean || return $?
  run_hexo generate || return $?
  sync_current_branch
}

get_default_pr_base_branch() {
  local current_branch
  current_branch="$(get_git_branch)"

  if [[ "$current_branch" == "source" ]]; then
    printf "main"
  else
    printf "source"
  fi
}

get_default_pr_title() {
  local current_branch default_base latest_subject
  current_branch="$(get_git_branch)"
  default_base="$(get_default_pr_base_branch)"
  latest_subject="$(git log -1 --pretty=%s 2>/dev/null || printf "Update workspace")"

  if [[ "$current_branch" == "source" ]]; then
    printf "Source branch sync: %s" "$latest_subject"
  else
    printf "%s -> %s: %s" "$current_branch" "$default_base" "$latest_subject"
  fi
}

build_pr_compare_url() {
  local base_branch="$1"
  local head_branch="$2"
  local repo_slug
  repo_slug="$(get_repo_slug 2>/dev/null || true)"

  if [[ -z "$repo_slug" ]]; then
    return 1
  fi

  printf "https://github.com/%s/compare/%s...%s?expand=1" "$repo_slug" "$base_branch" "$head_branch"
}

create_pull_request() {
  ensure_git_repo || return $?
  ensure_origin_remote || return $?

  local current_branch default_base base_branch title body compare_url
  current_branch="$(get_git_branch)"
  default_base="$(get_default_pr_base_branch)"

  if [[ "$current_branch" == "source" ]]; then
    log_warn "当前位于 source 分支。标准流程通常是 feature branch -> source。"
    log_warn "如果你现在要发迁移 PR，请将目标分支保持为 main。"
  fi

  prompt_with_default "目标分支" "$default_base"
  base_branch="$REPLY"

  if [[ "$base_branch" == "$current_branch" ]]; then
    log_error "PR 的目标分支不能和当前分支相同。"
    return 1
  fi

  prompt_with_default "PR 标题" "$(get_default_pr_title)"
  title="$REPLY"

  prompt_with_default "PR 简述" "Automated PR created from $current_branch"
  body="$REPLY"

  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    run_network_cmd \
      "创建 Pull Request" \
      gh pr create \
      --base "$base_branch" \
      --head "$current_branch" \
      --title "$title" \
      --body "$body"
    return $?
  fi

  compare_url="$(build_pr_compare_url "$base_branch" "$current_branch" 2>/dev/null || true)"
  if [[ -n "$compare_url" ]]; then
    printf "\n未检测到可用的 gh CLI，已生成 GitHub PR 链接：\n%s\n" "$compare_url"
    log_info "打开该链接后即可在浏览器中完成 Pull Request 创建。"
    return 0
  fi

  log_error "无法解析 GitHub 仓库地址，未能生成 Pull Request 链接。"
  return 1
}

show_project_summary() {
  printf "\n%s当前项目概况%s\n" "$BOLD" "$RESET"
  printf "站点配置: _config.yml\n"
  printf "文章目录: source/_posts\n"
  printf "页面目录: source/\n"
  printf "当前主题: "
  awk -F': ' '/^theme:/ {print $2}' _config.yml
  printf "当前 Git 分支: %s\n" "$(get_git_branch)"
  printf "源码仓库: %s\n" "$(get_git_remote_url)"
  printf "Pages 发布: %s\n" "$(get_pages_mode_label)"
  printf "Hexo 同步链路: clean -> generate -> push source -> Actions deploy\n"
  printf "可用 npm 脚本:\n"
  printf "  - npm run clean\n"
  printf "  - npm run build\n"
  printf "  - npm run server\n"
  printf "  - npm run sync\n"
}

main() {
  ensure_project_dir
  fix_hexo_permissions

  while true; do
    show_header
    show_menu

    local choice
    read -r choice

    case "$choice" in
      1)
        install_deps
        pause
        ;;
      2)
        hexo_clean
        pause
        ;;
      3)
        hexo_generate
        pause
        ;;
      4)
        hexo_server
        pause
        ;;
      5)
        show_git_repo_status
        pause
        ;;
      6)
        sync_current_branch
        pause
        ;;
      7)
        run_cmd "一键构建并同步" build_and_sync
        pause
        ;;
      8)
        create_pull_request
        pause
        ;;
      9)
        create_post
        pause
        ;;
      10)
        create_page
        pause
        ;;
      11)
        create_draft
        pause
        ;;
      12)
        publish_draft
        pause
        ;;
      13)
        show_project_summary
        pause
        ;;
      0)
        log_info "已退出。"
        exit 0
        ;;
      *)
        log_warn "无效选项，请重新输入。"
        pause
        ;;
    esac
  done
}

main "$@"
