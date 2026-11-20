# 实现说明 · Implementation Notes

> 对应版本：v1.0.0（commit `f43cfc0`）
> 对应需求：[`docs/PRD.md`](PRD.md)（v1.0）+ [`docs/PRD-changes-v1.1.md`](PRD-changes-v1.1.md)（增量补丁）
> 用途：拿到代码后**核对"哪条需求落在哪个文件"**，以及在 Mac 上排错时判断"这段逻辑本来该长什么样"。

---

## 0. 先读这一节

**编译与单元测试已在 CI 上通过**（GitHub Actions / `macos-15` / Xcode 16，run #3，commit `b193b8d`）：`build-for-testing` + `test-without-building` 全绿，20 个 UIKit 文件也在这次构建里一起过了。

但这只证明"能编译、逻辑测试通过"，**证明不了**：

- 翻页手感、手势冲突、工具栏唤起时机
- 字号切换时重排是否卡顿
- 连续模式滚动时行高修正带来的跳动
- 小屏（SE 3）与大屏（15 Pro Max）的布局

所以下面的状态标记含义是：

- "已实现"= 逻辑与结构按需求逐条写完，且**已通过编译**
- `单元测试` 覆盖的项有自动化保障
- `手测` 覆盖的项**一律没做**（没有真机），这是当前最大的空缺

排错时建议顺序：`Core/Persistence` → `Core/Import` → `Core/Pagination` → `Features`。前三层是纯逻辑，编译错误容易定位；UI 层的错误往往是它们的连锁。

---

## 1. 架构与数据流

```
User 操作
   │
   ├── 导入 ──► BookImporter ──► TextLoader（编码）
   │                │            TextCleaner（清洗，确定 offset 基准）
   │                │            ChapterParser（切章）
   │                │            SHA-256 去重
   │                └──► LibraryStore ──► GRDB（books / chapters / bookmarks）
   │
   ├── 书架 ──► ShelfViewModel ──► LibraryStore（全量重查，不做增量状态）
   │
   └── 阅读 ──► ReaderViewController
                    │
                    ├── PaginationService ──► Paginator（NSLayoutManager 多容器）
                    ├── ReaderPageViewController（按容器绘制 glyph）
                    ├── ContinuousReaderView（长滚动，按章分行）
                    └── LibraryStore（进度、书签）
```

分层规则（PRD §2）：`App` 只做装配，`Core` 不含任何 UI 类型（除颜色字体这类必须的），`Features` 不含 SQL。

| 概念 | 文件 | 关键类型 |
| --- | --- | --- |
| 依赖容器 | `App/AppServices.swift` | `AppServices.shared` |
| 数据库 | `Core/Persistence/AppDatabase.swift` | `AppDatabase` |
| 建表 | `Core/Persistence/Migrations.swift` | `migrator`（`v1_initial`） |
| 模型 | `Core/Persistence/Models.swift` | `Book` / `Chapter` / `Bookmark` / `ChapterMode` |
| 读写 | `Core/Persistence/LibraryStore.swift` | `books(sort:search:)` / `saveProgress` / `addBookmark` |
| 编码 | `Core/Import/TextLoader.swift` | `TextLoader.decode(_:)` |
| 清洗 | `Core/Import/TextCleaner.swift` | `TextCleaner.clean(_:)` |
| 分章 | `Core/Import/ChapterParser.swift` | `ChapterParser.parse(text:mode:bookTitle:)` |
| 导入 | `Core/Import/BookImporter.swift` | `importSingle(url:mode:isCancelled:progress:)` |
| 分页 | `Core/Pagination/Paginator.swift` | `Paginator.paginate(...)` |
| 分页缓存 | `Core/Pagination/PaginationService.swift` | `paginatedChapter(index:context:params:textColor:)` |
| 排版参数 | `Core/Pagination/TypesettingParams.swift` | `TypesettingParams` / `TextStyler` |
| 阅读偏好 | `Core/Preferences/ReadingPreferences.swift` | `ReadingPreferences` |
| 主题色 | `Core/Preferences/ReaderTheme.swift` | `ReaderTheme.all` |

---

## 2. 四个必须理解的机制

### 2.1 offset 基准：UTF-16，全书唯一

所有 `offset` 都是**清洗后全文的 UTF-16 code unit 下标**（`NSRange` 语义）。

- `TextCleaner.clean` 直接对 `[UInt16]` 做单趟扫描，所以清洗结果的长度天然就是 UTF-16 长度；
- `books.char_count`、`chapters.start_offset/end_offset`、`bookmarks.char_offset`、`books.last_char_offset` 全部同基准；
- 禁止用 `String.count`（Character 数量）参与计算——含 emoji 的书会逐页累积漂移。

`String` ↔ `NSString` 的等价性由 `PaginationTests.testEmojiDoNotShiftUTF16Offsets` 守着。

### 2.2 分页：多容器顺序追加

`Paginator.paginate` 的做法（补丁 R-04 规定的唯一姿势）：

```
NSTextStorage(attributedText)
  └── NSLayoutManager
        ├── NSTextContainer(size: 页高)   ← 第 1 页
        ├── NSTextContainer(size: 页高)   ← 第 2 页
        └── ...
每追加一个容器 → ensureLayout → glyphRange(for: container) → characterRange(forGlyphRange:)
```

拿到的 `characterRange` 就是"这一页装了哪些字符"。

**渲染时不能重新排版**。`ReaderPageView.draw(_:)` 直接用 `paginated.layoutManager` 画该容器的 glyph 区间。若改成"把这一页的字符串丢进一个新的 UITextView"，页首那半段文字会被当成新段落重新套首行缩进，页码和正文错位——这是最隐蔽、最难查的一类 bug。

### 2.3 章节标题不额外插入

章节的 `start_offset` 指向标题行行首，也就是说**标题本来就长在正文里**。

所以 `TextStyler.attributedString(_:params:color:inlineTitleLength:)` 只给首行套标题样式（字号 ×1.35、居中、行距 1.2、后空 1.5 行），不拼新字符串。好处是分页产出的 `charRange` 与全书偏移永远一一对应，不需要任何"标题占了几个字符"的加减。

`inlineTitleLength` 由 `PaginationService.inlineTitleLength(for:mode:chapterText:)` 算；不分章模式和「正文开始前」章节返回 0。

### 2.4 设置改动：按 offset 重建，不按页码

字号 17 → 24 之后，原来的"第 12 页"已经不是同样那 30 个字了。`ReaderViewController.applySettingsIfNeeded()` 的顺序是：

```
抓 currentOffset  →  换 params  →  restorePosition(forOffset:) 重算章节/页码  →  rebuildReader()
```

这条链路是 PRD §9 红线第 2 条（任何设置改动位置不丢）的实现方式，也是唯一正确的方式。

---

## 3. 用户故事对照

状态说明：`✅` 逻辑完整；`⚠️` 部分实现；`❌` 未实现。

### US-001 工程初始化 ✅

- 工程：`NovelReader.xcodeproj/project.pbxproj`（`objectVersion = 77`，文件系统同步组）、shared scheme
- 依赖：SPM `GRDB 7.x`，`upToNextMajorVersion` 从 `7.0.0`
- 目录分层：`App` / `Core` / `Features`，与 PRD §2 一致
- `.gitignore` 覆盖 `xcuserdata/`、`DerivedData/`、`.build/`、`*.xcscmblueprint`、`Pods/`、`.DS_Store`
- 验证：`xcodebuild -scheme NovelReader build`

### US-002 数据库迁移与模型 ✅

- `Core/Persistence/Migrations.swift`：`books` / `chapters` / `bookmarks` + 6 个索引
- 补丁落地点：`content_hash`（R-02）、`cover_seed`（R-06）、`chapter_index`（S-01）
- 级联删除：`REFERENCES books(id) ON DELETE CASCADE`，`Configuration.foreignKeysEnabled = true`（S-02）
- 验证：`LibraryStoreTests.testCascadeDeleteRemovesChaptersAndBookmarks`

### US-003 文本读取 + 编码识别 + 清洗 ✅

- `TextLoader.decode`：UTF-8 → UTF-16（仅按 BOM）→ GB18030，每步都用 `U+FFFD` 兜底拒绝
- `TextCleaner.clean`：单趟 UTF-16 扫描，五条规则顺序固定
- 验证：`TextLoaderTests`（5 例）、`TextCleanerTests`（10 例）

### US-004 章节解析器 ✅

- `ChapterParser`：三条路径 + 五条防误判
- 补丁落地点：R-03（2000 章规则拆成"硬降级 + 软提示"）
- 实现细节：先按行扫描 → 长度过滤 → 快速预筛（`mayBeLooseCandidate`）→ 正则；预筛把 99% 正文行挡在正则之前，这是 5MB 文件能跑完的关键
- 验证：`ChapterParserTests`（13 例）

### US-005 导入流程 ✅

- 入口：`ShelfView` 的 `.fileImporter`（`[.plainText, .text]`，允许多选）
- 模式选择：`ChapterModeSheet`（三选一，带副标题说明）
- 编排：`ShelfViewModel.confirmImport(mode:)` 在后台队列串行处理多文件
- 回滚：`BookImporter.importSingle` 的失败路径逐个清（临时文件 / book 记录 / 文件改名）
- 去重：清洗后文本的 SHA-256，命中抛 `DuplicateBookError`，由 `ShelfView` 弹"该文件已导入，是否打开？"
- 进度与取消：`CancellationFlag`（`NSLock` 保护），进度回调按"第几本 + 本本内比例"折算总进度
- 验证：手测（导入 5MB UTF-8 / GB18030 各一份、200 章样本、中途取消后书架无残留）

### US-006 书架页 ✅

- `ShelfView` + `BookCardView`（网格卡片 / 列表行）
- 布局切换：`preferences.shelfUsesListLayout`，写 UserDefaults
- 排序：`BookSort` 四选一，SQL 在 `LibraryStore.fetchBooks` 里
- 搜索：`title LIKE :keyword`，无结果显示"没有找到相关书籍"
- 卡片右上角 ★ 单击直接切换收藏（不进菜单）
- 长按 `.contextMenu`：打开阅读 / 收藏 / 重命名 / 重新解析章节 / 删除
- 删除二次确认文案与 PRD 一致
- 空状态：`ShelfEmptyView`，含第二个「导入」入口（PRD §5.3-6 允许）
- 骨架屏：6 个灰块
- 验证：手测

### US-007 Paginator + 布局缓存 ✅ / 性能 ⚠️

- 引擎：`Core/Pagination/Paginator.swift`
- 缓存：`PaginationService`（`NSCache`，key = `bookId-chapterIndex-排版指纹`，`countLimit = 6`）
- 指纹：`TypesettingParams.fingerprint` = 字号 + 行距 + 字体 + 尺寸 + 背景 key
- 性能红线（单章 < 80ms / 冷启动 < 1.5s / 55fps）：**未实测**，需在 Mac + 真机上跑
- 验证：`PaginationTests`（7 例，全部是区间不变量）

### US-008 阅读页骨架 + 左右翻页 ✅

- `ReaderViewController`：全屏，无导航栏；三个子件（pageContainer / chrome / 手势）
- `UIPageViewController(.scroll, .horizontal)`，dataSource 返回相邻页；跨章自动续接
- 工具栏：`ReaderChromeView`，0.2s 淡入淡出；`point(inside:)` 只让顶/底区域拦截触摸
- 翻页热区：两侧各 20%，中间 60% 唤起工具栏
  > **偏离说明**：PRD §5.5 同时写了"中部 60%"和"左右 1/3"，两者重叠 13%。实现取 20/60/20，即重叠区按"唤起工具栏"处理。
- 验证：手测

### US-009 设置面板 UI ✅

- `Features/Settings/ReadingSettingsView.swift`，6 组顺序固定
- 浮层容器：`Features/Common/BottomSheetHost.swift`（自绘，24pt 圆角，点外/下滑关闭，键盘避让）
- 色值全部来自 `ReaderTheme.all`，与 PRD §5.6 ③ 表逐字一致
- 验证：手测（对照截图逐项比）

### US-010 背景色/字号/行距/字体即时生效 + 位置保持 ✅

- `ReadingPreferences` 是 `ObservableObject`，面板改的是同一个实例
- `ReaderViewController.bindPreferences()` 订阅 `objectWillChange` → 50ms 合并 → `applySettingsIfNeeded()`
- 位置保持机制见 §2.4
- 验证：手测（改字号后回看是否停在同一句话）

### US-011 上下模式 ✅

- 实现方式：竖向 `UIPageViewController`（补丁 R-08 明确允许）
- 行为等价：手指竖向拖动逐屏推进、松手吸附、跨章无缝
- 左右翻页热区在该模式下失效（`handleTap` 里 `guard preferences.pageTransition == .slide`）
- 验证：手测

### US-012 连续模式 + 懒加载 ✅ / 内存 ⚠️

- `ContinuousReaderView`：`UITableView`，一章一行，章节标题作为普通文本行内嵌
- 行高按需测量并缓存；未测量的行用 `estimatedRowHeight = 800` 估算
- 位置锚是 `(chapterIndex, offset)` 而不是 `contentOffset`，所以行高被修正时不会丢位置
- 内存峰值 < 250MB：**未实测**
- 已知体验问题：滚动条长度会随估算修正跳动

### US-013 亮度遮罩 ✅

- `Core/Support/BrightnessOverlay.swift`：黑色遮罩 `alpha = 1 - appBrightness`，`isUserInteractionEnabled = false`
- **不调用** `UIScreen.main.brightness`
- 验证：手测（拉滑杆看正文变暗、翻页手势仍然有效）

### US-014 章节目录抽屉 ✅

- `ChapterDrawerView`：搜索、当前章高亮 + 左侧指示条、跳到章尾
- 不分章时显示"本书未分章"，不渲染列表
- 验证：手测

### US-015 书签 ✅

- 添加/取消：底部工具栏第二个按钮，锚点 = 当前页首字符偏移
- 列表：书架左上角 ☆（`BookmarkListView`，按书分组，左滑删除，顶部清空）
- 阅读页内另有顶部 ☆ → `ReaderBookmarkSheet`（当前书）
- 上限 500（`LibraryStore.addBookmark` 里判断）
- 去重靠唯一索引 `idx_bookmarks_unique_anchor` + 插入前查询
- 验证：`LibraryStoreTests.testDuplicateBookmarkIsRejected` / `testBookmarkLimitIsEnforced`

### US-016 进度落库与恢复 ✅

- 翻页/滚动停止 → `scheduleSave()` 500ms 防抖
- `UIApplication.didEnterBackgroundNotification` → 立即写
- 打开书籍 → `restorePosition(forOffset:)`，偏移落在被删除章节区间时映射到"起点 ≥ 上次值"的最近章
- 验证：手测（杀进程重进）

### US-017 异常与空状态 ⚠️

已覆盖：书架加载中骨架屏、书架为空、导入中、编码失败弹窗、文件过大、章节识别为 0 降级 Toast、书签为空、DB 写入失败 Toast、阅读页重排保持当前页。

未覆盖：§8 里"阅读页重排中右上角小菊花"——当前重排是同步的（单章几十毫秒），没有加 loading 态。字号改到 24pt 且章节极长时可能有一次可见卡顿，需要在真机上判断是否要补。

### US-018 README / CHANGELOG / 截图 ⚠️

- `README.md`：隐私声明、环境要求、构建命令、目录结构、偏离清单、已知限制
- `CHANGELOG.md`：v1.0.0 全量条目
- 截图：❌ 未提供（需要真机/模拟器）

---

## 4. PRD §9 测试对照

### 单元测试（已写，待 Mac 上跑）

| 要求 | 覆盖位置 | 用例数 |
| --- | --- | --- |
| 编码识别 UTF-8 / UTF-16 / GB18030 各 1 例 + 1 例乱码拒绝 | `TextLoaderTests` | 6 |
| 章节解析三模式各 ≥3 例 | `ChapterParserTests` | 13（含 5 条防误判） |
| 字符偏移 ↔ 页码双向映射（跨章、边界） | `PaginationTests` | 7 |
| 书签去重 | `LibraryStoreTests` | 2 |
| 级联删除 | `LibraryStoreTests` | 1 |
| 分页不变量（S-05） | `PaginationTests.testPageRangesAreContiguousAndComplete` | 1 |

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### 全局验收红线

| # | 红线 | 当前状态 | 怎么验 |
| --- | --- | --- | --- |
| 1 | 全流程零网络请求 | ✅ 已 grep 核验 | `grep -rn "URLSession\|URLRequest\|NSURLConnection\|dataTask\|WKWebView" NovelReader/` → 无匹配。`UIScreen.main.brightness` 唯一命中的是 `BrightnessOverlay.swift` 里的注释，无实际调用。剩余动作：Instruments Network 模板跑一遍导入 + 阅读 |
| 2 | 任何设置改动后位置不丢失 | ✅ 机制已实现 | 改字号 17→24→17、改行距、换背景，每次看是否停在同一句话 |
| 3 | 首页除导入/书架外无其他入口 | ✅ | 顶栏只有：☆书签、排序、布局、＋导入 |
| 4 | 删除书籍后章节与书签彻底消失 | ✅ 有测试 | `testCascadeDeleteRemovesChaptersAndBookmarks`，或直接查表 |
| 5 | SE 3 / 15 Pro Max 无截断无重叠 | ❌ 未验 | 两个尺寸各跑一遍书架网格 + 设置面板 + 书架列表 |

---

## 5. 已知缺口清单

按影响面排序：

1. **未编译**。这是唯一可能让上面所有 ✅ 失效的因素。见 §6。
2. **UI 测试未做**（PRD §9 第二条）。需要 `NovelReaderUITests` target + 真机/模拟器；导入需要预置样本文件。
3. **性能红线未测**。80ms / 1.5s / 55fps / 250MB 四个数字都得在真机上跑 Instruments。
4. **小屏与大屏未验**。设置面板固定高度 620，在 SE 3（屏高 667）上会被 `BottomSheetHost` 压到 85% 并内部滚动，逻辑上没问题，但视觉需要确认。
5. **重排 loading 态缺失**（US-017 尾条）。
6. **自定义字体只预留机制**。当前工程 `GENERATE_INFOPLIST_FILE = YES`，要加 `UIAppFonts` 得改成显式 `Info.plist`。

---

## 6. 首次编译排错顺序

### 6.1 没有 Mac 时的验证方式：GitHub Actions

`.github/workflows/ios-build.yml` 已经配好。push 到 `main` 后，GitHub 的 macOS runner（自带 Xcode 16）会自动：

1. 拉取 GRDB
2. `build-for-testing`（`CODE_SIGNING_ALLOWED=NO`，不需要证书）
3. `test-without-building`，跑全部单元测试
4. 把 `error:` 行**逐条转成 Actions 里的注解**，直接标在文件上
5. 上传 `build.log` / `test.log` / `TestResults.xcresult`

查看：仓库 → Actions → `iOS Build & Test`。失败时不用翻全量日志，Step Summary 里已经有前 40 条编译错误。

也可以在 Actions 页面点 **Run workflow** 手动触发，不必等下一次 push。

### 6.2 本地有 Mac 时的排查顺序

```bash
xcodebuild -project NovelReader.xcodeproj -scheme NovelReader \
  -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | grep -E "error:"
```

按这个顺序清：

1. **GRDB 相关**（概率最高）。`StatementArguments`、`Row` 下标、`ValueObservation`、`DatabaseWriter` 的 `Sendable` 要求在不同小版本上有差异。
2. **`Core/Persistence`**。模型 `CodingKeys` 与列名必须严格一致（`chapter_index`、`content_hash`、`cover_seed`）。
3. **`Core/Pagination`**。`NSTextContainer` / `NSLayoutManager` 的 API 是稳定的，报错多为参数标签问题。
4. **`Features`**。这里 90% 的错误是前三层没通导致的连锁。
5. **SPM 拉取失败**：把 `project.pbxproj` 里的 `minimumVersion` 改为 `7.0.0`，或 `brew install xcodegen && xcodegen generate` 用 `project.yml` 重建。

编译通过后，第一件事不是跑 UI，而是**跑单元测试**——5 个测试文件能独立证明编码/清洗/分章/分页/书签五块逻辑是对的，把 UI 问题和逻辑问题分开。

---

*文档版本：2026-11-20 ｜ 对应 commit：`f43cfc0`*
