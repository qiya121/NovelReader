# Changelog

本文件记录所有值得注意的变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added

- GitHub Actions 工作流 `iOS Build & Test`：macOS runner 上自动 `build-for-testing` + `test-without-building`，编译错误转成 Actions 注解，日志与 `xcresult` 作为产物上传

### Fixed

- `BookImporter.importSingle` 的 `progress` 参数缺 `@escaping`（下游是可选闭包，隐含逃逸）
- `LibraryStore.book(id:)` 更名为 `book(bookID:)`，与其余 `bookID:` 系列接口一致
- `ChapterParser.filterDenseMatches` 之前与"上一个保留的章节"比距离，会把密集候选稀疏化成每 100 字一章；改为与**相邻候选行**比较，符合 PRD §5.2 防误判第 2 条（整段误命中只保留第一个）
- `ContinuousReaderView` 对非可选的 `UITextView.layoutManager` / `.textContainer` 使用 `guard let` 导致编译失败

### 待办

- 补齐 PRD §9 要求的端到端 UI 测试
- 真机验证：iPhone SE 3 与 iPhone 15 Pro Max 上的排版与控件布局
- 真机测性能红线：单章分页 < 80ms、冷启动 < 1.5s、连续模式内存峰值 < 250MB

## [1.0.0] - 2026-11-20

### Added

- **工程**：Xcode 项目（objectVersion 77）、GRDB 7 通过 SPM 引入并锁定、分层目录、shared scheme、`.gitignore`
- **数据层**：`books` / `chapters` / `bookmarks` 三表 + 索引；`PRAGMA foreign_keys = ON`；级联删除
- **导入**：TXT 多选导入、编码识别（UTF-8 / UTF-16 BOM / GB18030）、文本清洗、SHA-256 去重、进度与取消、失败回滚
- **章节解析**：严格 / 宽松 / 不区分三种模式；五条防误判；前言行补全；重新解析并按偏移映射进度
- **分页**：`NSLayoutManager` 多容器分页，产出每页字符区间；`(book, chapter, 排版指纹)` 缓存
- **阅读**：左右 / 上下 / 连续三种翻页；工具栏唤起与收起；章节自动续接；全书总页数后台计算
- **设置**：翻页方式、亮度遮罩、6 种背景色、3 档字号、字体样式、5 档行间距；改动即时生效且位置不丢
- **书架**：网格 / 列表切换、四种排序、书名搜索、收藏、重命名、删除、重新解析、空状态、骨架屏
- **书签**：添加 / 取消、列表页（按书分组）、跳转、左滑删除、清空、单本 500 条上限
- **进度**：翻页后 500ms 落库、进后台立即落库、启动恢复到字符偏移
- **测试**：编码、清洗、章节解析、分页映射与不变量、书签去重、级联删除、书签上限
- **文档**：README、PRD 原文、PRD v1.1 增量修订补丁

### Changed

- 分页引擎由 PRD 指定的 TextKit 2 改为 TextKit 1（`NSLayoutManager`），见 `docs/PRD-changes-v1.1.md` R-04
- 默认字号由 19 改为 17，`font_size_pt` 改存真实 pt 值（R-01）
- `chapters.index` 列改名为 `chapter_index`（S-01）

### Notes

- 本版本在 Windows 环境下产出，**未经 Xcode 编译验证**
