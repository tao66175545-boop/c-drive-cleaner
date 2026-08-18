# GitHub 仓库补充上传说明

目标仓库：[tao66175545-boop/c-drive-cleaner](https://github.com/tao66175545-boop/c-drive-cleaner)

## 当前已核实状态

- 仓库为公开仓库，默认分支为 `main`。
- `v1.0.0` Release 已发布，下载资产为 `C.zip`。
- `C.zip` SHA-256：`3C97F05A9771EBA724592004579C823108BD47EA1C176BE253AFC12E6039B47A`。
- Release ZIP 内含运行所需的 `assets`，但 GitHub 源码目录尚未上传 `assets/`，因此从 Code 页面下载源码不能直接运行。

## 需要上传到仓库根目录

```text
README.md
.gitignore
version.json
release.json
RELEASE_NOTES_v1.0.0.md
OTA-在线升级方案.md
```

## 需要上传的目录

```text
assets/
.github/workflows/validate.yml
```

`assets/` 必须保持目录结构，其中包含 Logo 动画、Logo 序列帧和清理动效资源。

## GitHub 网页上传步骤

1. 打开仓库首页，点击 `Add file` → `Upload files`。
2. 将根目录文件拖入上传区并提交到 `main`。
3. 进入 `assets` 目录，点击 `Add file` → `Upload files`，上传本地 `assets` 文件夹中的四个资源文件。
4. 点击 `Add file` → `Create new file`，创建 `.github/workflows/validate.yml`；可先创建 `.github` 与 `workflows` 目录，或使用 GitHub Desktop/命令行一次上传目录。
5. 提交后打开 `Actions`，确认 `Validate C Drive Cleaner` 工作流通过。

## 许可证待决事项

仓库当前没有 LICENSE。公开仓库默认不授予第三方复用权限。

- 希望他人可自由使用、修改和分发：选择 MIT License。
- 希望专利条款更明确：选择 Apache-2.0 License。
- 暂不希望第三方复用：不添加 LICENSE，但仍需在 README 中保留版权/使用说明。

请由仓库所有者在 GitHub 的 `Add file` → `Create new file` → `Choose a license template` 中作出选择。
