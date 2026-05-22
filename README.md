# JDK 版本一键切换工具

在 Windows 系统上快速切换 JDK 版本，自动扫描已安装的 JDK、更新系统 PATH 和 JAVA_HOME，无需手动操作环境变量。

## 核心功能

- **自动扫描** — 在常见目录（`C:\Program Files\Java`、`D:\Java` 等）中自动发现已安装的 JDK
- **手动输入** — 支持直接粘贴任意 JDK 根目录路径
- **精确更新 PATH** — 仅替换 Machine 级别的旧 JDK/JRE 条目，不会误删其他 PATH 配置，User PATH 完整保留
- **一键设置 JAVA_HOME** — 自动更新系统级 JAVA_HOME 环境变量
- **即时生效** — 当前会话立即生效，新开终端窗口也会自动读取新的系统 PATH
- **安全校验** — 切换前验证路径是否存在、bin\java.exe 是否可用，切换后执行 java -version 确认结果

## 文件说明

| 文件 | 作用 |
|------|------|
| `switch-jdk.bat` | 启动器，自动申请管理员权限并调用 PowerShell 脚本 |
| `switch-jdk.ps1` | 主脚本，负责扫描、选择、更新 PATH 和 JAVA_HOME |

## 使用方式

1. **右键** `switch-jdk.bat`，选择 **"以管理员身份运行"**（脚本也会自动请求提权）
2. 脚本会列出扫描到的 JDK 版本，输入序号选择；也可以直接粘贴 JDK 根目录路径
3. 脚本自动完成 PATH 更新、JAVA_HOME 设置，并显示 java -version 验证结果

```
[18:30:01] [INFO]    当前系统 PATH 中的 Java 相关路径：
[18:30:01] [INFO]      -> C:\Program Files\Java\jdk1.8.0_202\bin
[18:30:02] [SUCCESS] 扫描到以下 JDK 版本：
  [1] C:\Program Files\Java\jdk1.8.0_202
  [2] D:\Java\jdk-17.0.5
  [3] D:\Java\jdk-21.0.1

输入序号选择上方 JDK，或直接粘贴完整 JDK 根目录路径：
>>> 2
```

## 关键设计

- **只改 Machine PATH** — 不触碰 User PATH，避免影响用户级配置
- **精确匹配 JDK 条目** — 通过正则匹配 `\jdk*\bin`、`\jre*\bin` 等路径特征，不会误删其他包含 "java" 字样的 PATH 条目
- **新条目前置** — 新 JDK 的 bin 路径插入 PATH 最前面，确保优先被系统找到
- **需要管理员权限** — 修改系统级环境变量（Machine PATH、JAVA_HOME）需要管理员身份运行
