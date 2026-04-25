# Jianbo.Yuan Hexo Blog Workspace

这是一个基于 Hexo 的个人科研博客源码仓库，当前用于维护机器人、灵巧手、模仿学习、强化学习与相关技术笔记。项目主语言为 `zh-CN`，时区为 `Asia/Shanghai`，当前启用主题为 `matery`。

## 当前实际状态

- 站点名称：`Jianbo.Yuan`
- 作者：`Jianbo.Yuan`
- Hexo 版本：`8.1.1`
- 当前主题：`matery`
- 源码分支：`source`
- 站点地址：`https://jianbo-yuan.github.io/jianbo-yuan`
- GitHub Pages 发布方式：`GitHub Actions`

## 分支与发布流程

当前仓库采用“源码分支 + 自动部署 Pages”的标准流程：

1. 所有源码维护都在 `source` 分支进行。
2. 本地修改完成后，将 `source` 分支推送到 GitHub。
3. GitHub Actions 工作流 [`.github/workflows/pages.yml`](/home/dex-yjb/Documents/git_pages/.github/workflows/pages.yml:1) 自动执行：
   - `npm ci`
   - `npx hexo generate`
   - 上传 `public/` 为 Pages 构建产物
   - 发布到 GitHub Pages

这意味着本地不再依赖 `hexo deploy` 推送静态文件到仓库分支。

## 目录结构

| 路径 | 作用 |
|------|------|
| `_config.yml` | Hexo 主配置，包含站点地址、主题和生成规则 |
| `source/` | 文章与独立页面源码 |
| `source/_posts/` | 博客文章 |
| `themes/` | 主题目录，当前启用 `themes/matery` |
| `scaffolds/` | 文章、页面、草稿模板 |
| `.github/workflows/pages.yml` | GitHub Pages 自动部署工作流 |
| `hexo_menu.sh` | 统一的本地工作台菜单，包含构建、预览、GitHub 同步和 PR 辅助 |
| `public/` | 本地生成的静态产物，已忽略，不直接提交 |
| `.deploy_git/` | 旧的本地部署目录，已不再作为主流程使用 |

## 当前主题与页面

当前站点启用主题：

```yml
theme: matery
```

已包含的主要页面：

- `source/index.md`
- `source/about/index.md`
- `source/contact/index.md`
- `source/friends/index.md`
- `source/categories/index.md`
- `source/archives/index.md`
- `source/tags/index.md`

留言板页已经接入 GitHub Issues 驱动的评论系统，配置位于：

- [themes/matery/_config.yml](/home/dex-yjb/Documents/git_pages/themes/matery/_config.yml:283)
- [themes/matery/layout/_partial/utterances.ejs](/home/dex-yjb/Documents/git_pages/themes/matery/layout/_partial/utterances.ejs:1)

## 本地开发

首次安装依赖：

```bash
npm install
```

常用命令：

```bash
npm run clean
npm run build
npm run server
npm run sync
```

说明：

- `npm run build`：执行 `hexo generate`
- `npm run server`：本地预览
- `npm run sync`：打开 [hexo_menu.sh](/home/dex-yjb/Documents/git_pages/hexo_menu.sh:1) 菜单
- `npm run deploy`：只输出说明文字，提醒当前仓库使用 GitHub Actions 自动发布

## 推荐工作流

推荐直接使用：

```bash
./hexo_menu.sh
```

当前菜单已经整合这些能力：

- 安装依赖
- 清理缓存
- 生成静态文件
- 本地预览
- 查看源码仓库状态
- 同步当前分支到 GitHub
- 一键构建并同步
- 创建或生成 Pull Request 链接
- 新建文章、页面、草稿

## GitHub Pages 设置

为了让自动发布生效，仓库侧还需要确认：

1. GitHub Pages 的 Source 设置为 `GitHub Actions`
2. 默认开发分支建议为 `source`
3. 如需代码评审，建议采用 `feature branch -> source` 的 PR 模式

## 注意事项

- `node_modules/`、`public/`、`.deploy_git/`、`db.json` 已在 `.gitignore` 中排除
- `themes/` 目录中保留多个备用主题，可用于后续切换和对比
- 旧脚本 `sync_to_git.sh` 已由 `hexo_menu.sh` 的 GitHub 同步功能替代
- 不要手动修改 `public/` 中的生成产物，应始终改源码后重新构建

## 快速命令

```bash
# 本地预览
npm run server

# 重新生成
npm run clean
npm run build

# 进入菜单工作台
./hexo_menu.sh

# 新建文章
npx hexo new post "文章标题"

# 新建页面
npx hexo new page "页面名称"
```
