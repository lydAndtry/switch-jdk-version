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

const cliDir = path.dirname(fs.realpathSync(__filename));
const projectRoot = path.join(cliDir, '..');
const scriptsDir = path.join(projectRoot, 'scripts');

const platform = os.platform();

// 解析用户参数
const userArgs = process.argv.slice(2);

// -v / --version 直接由 Node.js 处理
if (userArgs.length === 1 && (userArgs[0] === '-v' || userArgs[0] === '--version')) {
    const pkg = require(path.join(projectRoot, 'package.json'));
    console.log(`v${pkg.version}`);
    process.exit(0);
}

let command;
let scriptArgs;
let scriptName;

if (platform === 'win32') {
    scriptName = 'switch-jdk.ps1';
    const scriptPath = path.join(scriptsDir, scriptName);

    if (!fs.existsSync(scriptPath)) {
        console.error(`[ERROR] 找不到脚本文件: ${scriptPath}`);
        process.exit(1);
    }

    command = 'powershell.exe';
    // 使用 -Command 方式传递参数，避免 -File 模式下 -list 等被当作参数名解析
    const escapedPath = scriptPath.replace(/'/g, "''");
    const extraArgs = userArgs.map(a => `'${a.replace(/'/g, "''")}'`).join(' ');
    scriptArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', `& '${escapedPath}' ${extraArgs}`];
} else {
    scriptName = 'switch-jdk.sh';
    const scriptPath = path.join(scriptsDir, scriptName);

    if (!fs.existsSync(scriptPath)) {
        console.error(`[ERROR] 找不到脚本文件: ${scriptPath}`);
        process.exit(1);
    }

    command = 'bash';
    scriptArgs = [scriptPath, ...userArgs];
}

const child = spawn(command, scriptArgs, {
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
