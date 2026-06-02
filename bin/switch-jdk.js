#!/usr/bin/env node
// ============================================================
// switch-jdk CLI 入口 — Node.js 薄封装层
// 检测操作系统，委托执行对应平台的 shell 脚本
// ============================================================

'use strict';

const os = require('os');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');

// 解析当前脚本的真实路径（处理 npm 全局安装的符号链接）
const cliDir = path.dirname(fs.realpathSync(__filename));
const scriptsDir = path.join(cliDir, '..', 'scripts');

const platform = os.platform(); // 'win32' | 'darwin' | 'linux'

let command;
let args;
let scriptName;

if (platform === 'win32') {
    scriptName = 'switch-jdk.ps1';
    const scriptPath = path.join(scriptsDir, scriptName);

    if (!fs.existsSync(scriptPath)) {
        console.error(`[ERROR] 找不到脚本文件: ${scriptPath}`);
        process.exit(1);
    }

    command = 'powershell.exe';
    args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath];
} else {
    // macOS (darwin) 或 Linux
    scriptName = 'switch-jdk.sh';
    const scriptPath = path.join(scriptsDir, scriptName);

    if (!fs.existsSync(scriptPath)) {
        console.error(`[ERROR] 找不到脚本文件: ${scriptPath}`);
        process.exit(1);
    }

    command = 'bash';
    args = [scriptPath];
}

// 透传执行：stdio 完全继承，保留交互式菜单和彩色输出
const child = spawn(command, args, {
    stdio: 'inherit',
    shell: false,
});

child.on('close', (code) => {
    process.exit(code);
});

child.on('error', (err) => {
    console.error(`[ERROR] 无法执行 ${command}: ${err.message}`);
    process.exit(1);
});
