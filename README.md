# NovelReader · 本地小说阅读器

一款**纯本地、无账号、无网络**的 iOS TXT 小说阅读器。导入 TXT → 自动切分章节 → 进书架 → 在干净的阅读界面里读书。

## 隐私

- **不发起任何网络请求**，不声明网络权限，不集成任何埋点 / 广告 / 统计 / 崩溃 SDK。
- 所有数据只落在 App 沙盒内（`Documents/books/` 与 `Application Support/novelreader.db`），删除 App 即全部清除。
- 生产依赖只有 [GRDB.swift](https://github.com/groue/GRDB.swift) 一个。

## 环境要求

| 项 | 要求 |
| --- | --- |
| Xcode | 16.0 或更高（工程使用 `objectVersion = 77` 的文件系统同步组） |
| iOS | 16.0+ |
| 设备 | iPhone（V1 不做 iPad / Mac / Watch） |
| Swift | 5.9+ |

## 跑起来

```bash
git clone git@github.com:qiya121/NovelReader.git
cd NovelReader
open NovelReader.xcodeproj
```

Xcode 会自动拉取 GRDB（SPM）。选一个 iPhone 模拟器，`Cmd + R`。

命令行构建与测试：

```bash
xcodebuild -project NovelReader.xcodeproj -scheme NovelReader \
  -destination 'platform=iOS Simulator,name=iPhone 15' build

xcodebuild -project NovelReader.xcodeproj -scheme NovelReader \
  -destination 'platform=iOS Simulator,name=iPhone 15' test
```

### 如果 `.xcodeproj` 打不开

工程文件是手写的（`objectVersion = 77`）。万一你的 Xcode 版本不认这种格式，用 XcodeGen 从 `project.yml` 重新生成一份即可：

```bash
brew install xcodegen
xcodegen generate
```

## 目录结构

```
NovelReader/
├── App/                    应用入口、依赖容器、根视图
├── Core/
│   ├── Persistence/        GRDB 数据库、迁移、模型、读写仓储
│   ├── Import/             编码识别、文本清洗、章节解析、导入管线
│   ├── Pagination/         排版参数、分页引擎、分页缓存
│   ├── Preferences/        阅读偏好、主题色彩
│   └── Support/            路径、时间、Toast、亮度遮罩、UIColor 扩展
├── Features/
│   ├── Shelf/              书架（P1）
│   ├── Reader/             阅读页（P3）、目录抽屉（P7）、连续模式
│   ├── Settings/           阅读设置面板（P5）
│   ├── Bookmarks/          书签列表（P6）
│   └── Common/             底部浮层容器
└── Resources/
```

业务逻辑不进 View：`View` 只做展示，状态在 ViewModel / Store / 引擎里。

## 已实现

- [x] TXT 导入（多选、`UTType.plainText`）
- [x] 编码识别：UTF-8 → UTF-16（按 BOM）→ GB18030，全部失败拒绝入库
- [x] 文本清洗：换行统一、BOM/零宽字符、行尾空格、空行压缩、制表符
- [x] 章节解析：严格 / 宽松 / 不区分 + 5 条防误判
- [x] 导入去重（清洗后文本的 SHA-256）、进度、取消、失败回滚
- [x] 书架：网格 / 列表、排序、搜索、收藏、重命名、删除、重新解析、空状态、骨架屏
- [x] 分页引擎（`NSLayoutManager` + 多 `NSTextContainer`），字符偏移 ↔ 页码双向映射
- [x] 阅读页：左右 / 上下 / 连续三种翻页方式
- [x] 阅读设置：翻页方式、亮度、背景色（6 色）、字号（3 档）、字体、行间距（5 档）
- [x] 设置即时生效且**阅读位置不丢**（按字符偏移恢复）
- [x] 亮度遮罩（不改系统亮度）
- [x] 章节目录抽屉（搜索、当前章高亮、跳到章尾）
- [x] 书签：添加/取消、列表（左上角 ☆）、跳转、左滑删除、清空、500 条上限
- [x] 进度落库（翻页后 500ms / 进后台立即）与杀进程恢复
- [x] 单元测试：编码、清洗、章节解析、分页映射、书签去重、级联删除

## 与 PRD 的偏离

完整清单见 [`docs/PRD-changes-v1.1.md`](docs/PRD-changes-v1.1.md)。摘要：

| 编号 | 偏离 | 原因 |
| --- | --- | --- |
| R-01 | 默认字号 17（原文 19） | 19 不在 17/20/24 三档内，会造成"三个档位都未选中"的死状态 |
| R-02 | `books` 新增 `content_hash` | 原文要求 SHA-256 去重但表里没有字段；哈希输入取**清洗后文本**，让同书不同编码也能判重 |
| R-03 | 2000 章上限拆成"硬降级 + 软提示" | 连载书 2000+ 章是正常形态，按原规则会被整本降级 |
| R-04 | 分页引擎由 TextKit 2 改为 **TextKit 1** | `NSTextLayoutManager` 没有确定性获取"每页字符区间"的接口，而这正是"位置不丢"的地基 |
| R-05 | 导入进度恒显（删掉 >20MB 的触发条件） | 等发现解析超 3 秒时，用户已经干等 3 秒 |
| R-06 | `books` 新增 `cover_seed`，封面底色固定 | 原文"随机底色"会让书架每次启动换色 |
| R-07 | 设置面板自绘 24pt 浮层 | `preferredCornerRadius` 要 iOS 16.4，16.0 上系统 sheet 只有 10pt |
| R-08 | 「上下」模式允许用竖向 `UIPageViewController` | 行为等价，代码量约为手写滚动分页的 1/10 |
| S-01 | `chapters.index` → `chapter_index` | `index` 是 SQL 保留字 |
| S-04 | 页码显示改为"百分比 + 章内页码" | "首尾字符偏移对应页"在连续模式下没有稳定定义 |
| G-01 | 所有 offset 统一 UTF-16 单位 | 用 `Character` 计数会让含 emoji 的书位置漂移 |

## 已知限制

1. **首次编译可能报错**。本仓库的代码是在 Windows 上产出的，没有经过 Xcode 编译验证。逻辑与结构是按 PRD 逐条实现的，但 Swift 的类型细节、个别 API 签名仍可能需要在 Mac 上修一轮。建议按「Core → Features」的顺序看编译错误，核心引擎（`Core/`）先跑通，UI 层的错误通常是连锁反应。
2. **连续模式的行高是估算 + 修正**。行高按需测量，未测量的行用 `estimatedRowHeight` 估算；滚动位置以 `(章节, 偏移)` 为锚而非 `contentOffset`，所以修正行高时位置不会丢，但滚动条长度会跳动。
3. **自定义字体只预留了机制**。V1 只有系统字体；放字体文件到 `Resources/Fonts/` 后需要改用显式 `Info.plist` 并注册 `UIAppFonts`（当前工程用 `GENERATE_INFOPLIST_FILE = YES`）。
4. **未做 UI 测试**。PRD §9 要求的端到端 UI 测试（导入 → 翻页 → 改设置 → 加书签 → 重进）需要真机/模拟器录制，这一步留给在 Mac 上进行。

## 测试

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

覆盖范围：

- 编码识别：UTF-8 / UTF-16 LE·BE（BOM）/ GB18030 / 非法字节拒绝 / 空文件
- 文本清洗：CRLF、CR、BOM、零宽字符、行尾空格、空行压缩、制表符、UTF-16 长度
- 章节解析：三种模式各 ≥3 例，含整行独占、间距过密、章数超限、前言行
- 分页：区间连续无缝隙、偏移往返一致、页边界归属、emoji 不漂移、字号影响页数、空章节
- 数据层：书签去重、级联删除、哈希查重、进度写入、偏移映射、书签上限

## 文档

- [`docs/PRD.md`](docs/PRD.md) — 原始需求（v1.0，未改动）
- [`docs/PRD-changes-v1.1.md`](docs/PRD-changes-v1.1.md) — 增量修订补丁
- [`docs/IMPLEMENTATION.md`](docs/IMPLEMENTATION.md) — 实现说明：每条需求落在哪个文件、怎么验证、还差什么

## License

未授权。保留所有权利。
