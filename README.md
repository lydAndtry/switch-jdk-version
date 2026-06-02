<h1 align="center">JDK 版本一键切换工具</h1>

---

快速切换 JDK 版本，自动扫描已安装的 JDK、更新系统 PATH 和 JAVA_HOME，无需手动操作环境变量。**支持 Windows、macOS、Linux 三平台。**

## 快速安装（推荐）

```bash
npm install -g switch-jdk-version
```

安装完成后，在终端输入 `switch-jdk` 即可使用。

> **需要管理员/sudo 权限** — 切换 JDK 时会修改系统环境变量，Windows 需要以管理员身份运行终端，macOS/Linux 会在需要时请求 sudo。

---

## 文件说明

## 功能特性

- **主菜单交互** — 启动后进入主菜单，选择管理扫描路径或直接切换 JDK
- **自定义扫描根目录** — 支持添加/删除自定义扫描路径，永久缓存到本地，下次启动自动读取
- **自动扫描 JDK** — 在内置目录和自定义目录中自动发现所有已安装的 JDK
- **手动输入路径** — 扫描不到时，支持直接粘贴任意 JDK 根目录路径
- **精确更新 PATH / JAVA_HOME** — 自动更新环境变量，不影响其他已有配置
- **即时生效** — 当前会话立即生效，新开终端也会自动加载
- **安全校验** — 切换前验证路径和 java 可执行文件是否存在，切换后执行 `java -version` 确认

---

## 文件说明

| 文件 | 平台 | 作用 |
|------|------|------|
| `package.json` | 全平台 | npm 包配置，定义 CLI 命令 `switch-jdk` |
| `bin/switch-jdk.js` | 全平台 | Node.js CLI 入口，检测 OS 并委托执行对应脚本 |
| `scripts/switch-jdk.ps1` | Windows | 主脚本，负责扫描、选择、更新 PATH 和 JAVA_HOME |
| `scripts/switch-jdk.sh` | macOS / Linux | 主脚本，功能与 Windows 版完全对等 |
| `switch-jdk.bat` | Windows | 启动器，自动申请管理员权限并调用 PowerShell 脚本（双击运行方式） |
| `build.ps1` | Windows | 打包脚本，将 ps1 编译为可双击运行的 exe |
| `build-unix.sh` | macOS / Linux | 打包脚本，支持 shc 编译为二进制或打包为 tar.gz |
| `icon.ico` | Windows | 程序图标（编译 exe 时嵌入） |
| `DEPLOY.md` | — | npm 发布部署指南 |

> **Windows** 缓存文件：`%APPDATA%\switch-jdk\jdk-roots-cache.json`
> **macOS/Linux** 缓存文件：`~/.config/switch-jdk/custom-roots.txt`

---

## Windows 使用方式

### 方式一：npm 全局安装（推荐）

```powershell
npm install -g switch-jdk-version
```

安装后在 **管理员身份运行的** PowerShell 或 CMD 中输入：

```powershell
switch-jdk
```

### 方式二：直接运行脚本

右键 `switch-jdk.bat`，选择 **"以管理员身份运行"**（脚本也会自动请求提权）。

### 方式三：编译为 EXE 运行

```powershell
# 以管理员身份在 PowerShell 中执行
.\build.ps1
```

生成 `dist\switch-jdk.exe`，双击即可运行，自动弹出 UAC 管理员授权。

---

## macOS 使用方式

### 方式一：npm 全局安装（推荐）

```bash
npm install -g switch-jdk-version
```

安装后直接输入：

```bash
switch-jdk
```

### 方式二：直接运行脚本

```bash
bash scripts/switch-jdk.sh
```

切换 JDK 时会请求 `sudo` 权限（用于写入 `/etc/profile.d/switch-jdk.sh`），同时也会更新 `~/.zshrc` 或 `~/.bashrc`。

### 方式三：打包为可执行文件

```bash
# 安装 shc（可选，用于编译为二进制）
brew install shc

# 执行打包
bash build-unix.sh
```

- 若已安装 `shc`：生成 `dist/switch-jdk-mac`（二进制，直接双击或 `./switch-jdk-mac` 运行）
- 同时生成 `dist/switch-jdk-mac-v1.3.tar.gz`（压缩包，包含脚本和二进制，可直接分发）

### macOS 内置扫描目录

| 目录 | 说明 |
|------|------|
| `/Library/Java/JavaVirtualMachines` | Oracle / Adoptium / Temurin 等标准安装位置 |
| `~/Library/Java/JavaVirtualMachines` | 用户级 JDK |
| `/usr/local/opt` | Homebrew（Intel Mac） |
| `/opt/homebrew/opt` | Homebrew（Apple Silicon） |
| `~/.sdkman/candidates/java` | SDKMAN 安装的 JDK |
| `~/.jdks` | IntelliJ IDEA 下载的 JDK |

---

## Linux 使用方式

### 方式一：npm 全局安装（推荐）

```bash
npm install -g switch-jdk-version
```

安装后直接输入：

```bash
switch-jdk
```

### 方式二：直接运行脚本

```bash
bash scripts/switch-jdk.sh
```

### 方式三：打包为可执行文件

```bash
# 安装 shc（可选）
sudo apt install shc      # Debian / Ubuntu
sudo yum install shc      # CentOS / RHEL

# 执行打包
bash build-unix.sh
```

- 若已安装 `shc`：生成 `dist/switch-jdk-linux`
- 同时生成 `dist/switch-jdk-linux-v1.3.tar.gz`

### Linux 内置扫描目录

| 目录 | 说明 |
|------|------|
| `/usr/lib/jvm` | 包管理器安装（apt/yum）的 JDK |
| `/usr/local/java` | 手动解压安装 |
| `/usr/local/jdk` | 手动解压安装 |
| `/opt/java` | 企业级安装惯例 |
| `/opt/jdk` | 企业级安装惯例 |
| `~/.sdkman/candidates/java` | SDKMAN 安装的 JDK |
| `~/.jdks` | IntelliJ IDEA 下载的 JDK |

### Linux PATH 生效方式

脚本会同时修改以下两处，确保所有场景生效：

1. `/etc/profile.d/switch-jdk.sh`（系统级，对所有用户生效，需要 sudo）
2. `~/.zshrc` 或 `~/.bashrc`（用户级，当前用户生效）

> **注意**：切换完成后，当前终端已立即生效（`export` 已执行）。新开终端也会自动加载。

---

## 操作步骤（Windows 截图示例）

### Step 1 — 启动主菜单

启动后显示主菜单，提示当前内置扫描根目录数量和自定义数量。

![step1-start](pictures/step1-start.png)

选择操作：
- 输入 `1` — 进入扫描根目录管理
- 输入 `2` — 直接开始扫描并切换 JDK
- 输入 `Q` — 退出

---

### Step 2 — 管理扫描根目录

进入后可查看内置默认路径（只读）和当前已缓存的自定义路径。

![step2-manager-root-path](pictures/step2-manager-root-path.png)

操作说明：

| 输入 | 操作 |
|------|------|
| `A`  | 添加新的扫描根目录 |
| `D`  | 按序号删除已有的自定义路径 |
| `Q`  | 返回主菜单 |

---

### Step 3 — 添加自定义扫描路径

输入 `A` 后，粘贴或输入你的 JDK 安装根目录（不是 JDK 本身，而是存放多个 JDK 的父目录）。

![step3-save-your-path](pictures/step3-save-your-path.png)

例如你的 JDK 安装在 `E:\Holdwell\devEnv\java\jdk8`，则添加 `E:\Holdwell\devEnv\java`。

路径会立即持久化到本地缓存，下次启动自动加载。

---

### Step 4 — 扫描并选择 JDK 版本

在主菜单选择 `2`，脚本扫描所有根目录（内置 + 自定义），列出发现的所有 JDK。

![step4-choose-your-version](pictures/step4-choose-your-version.png)

- `[Y]` 表示该根目录存在，`[N]` 表示不存在（跳过）
- 输入序号选择对应 JDK，或直接粘贴完整 JDK 根目录路径

脚本将自动完成：
1. 移除旧 JDK 的 PATH 条目
2. 将新 JDK 的 `bin` 插入 PATH 最前面
3. 更新系统 `JAVA_HOME`
4. 执行 `java -version` 验证切换结果

---

## Windows 内置扫描目录

| 目录 |
|------|
| `C:\Program Files\Java` |
| `C:\Program Files (x86)\Java` |
| `D:\Java` |
| `D:\ProgramFiles\Java` |
| `E:\Java` |
| `%USERPROFILE%\.jdks` |

如果你的 JDK 安装在其他位置，通过主菜单 **[1] 管理扫描根目录** 添加即可。

## 注意事项

- **Windows**：修改系统环境变量需要 **管理员权限**，启动时会自动申请；脚本只操作 Machine 级别 PATH，User PATH 完整保留
- **macOS / Linux**：切换时会请求 sudo 权限；同时更新系统级和用户级配置文件；新开终端自动生效，当前终端已立即生效
- 扫描逻辑：在根目录下查找名称含 `jdk` 且包含 `bin/java`（或 `bin\java.exe`）的子目录
- 切换后新开的命令窗口自动生效；当前窗口也会立即同步