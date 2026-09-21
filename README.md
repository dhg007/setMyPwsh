# setMyPwsh 一键安装脚本

兼容 Windows PowerShell 5.1 和 PowerShell 7。

它会安装或配置：

- Windows Terminal
- PowerShell 7
- Oh My Posh
- 可选的 Meslo Nerd Font
- 重复运行时检测已安装的 Meslo 字体，不会再次提示安装
- 将 PowerShell 7 设置为 Windows Terminal 默认 Profile
- 将 Windows Terminal 默认字体设置为 MesloLGM Nerd Font
- PSReadLine 历史预测和列表视图
- Oh My Posh 主题
- 重复运行时自动沿用已配置主题；通过 `-Theme NAME` 可以主动切换
- Git 快捷函数（不安装 Git）
- 安装后的 `setMyPwsh` 本地管理命令

## 本地运行

```powershell
.\install.ps1
```

如果执行策略阻止本地脚本，可以只对这一次进程放行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

无人值守模式：

```powershell
.\install.ps1 -Yes -Theme atomic -SkipFont
```

仅预览，不安装软件、不修改文件：

```powershell
.\install.ps1 -DryRun -Yes -Theme atomic -SkipFont
```

## 一行远程安装

在 Windows PowerShell 中运行：

```powershell
iex ((irm https://raw.githubusercontent.com/dhg007/setMyPwsh/main/install.ps1).TrimStart([char]0xFEFF))
```

这里显式移除 UTF-8 BOM，以兼容系统自带的 Windows PowerShell 5.1。不要简写成 `irm URL | iex`。

首次安装完成后：

- 如果当前是 PowerShell 7，脚本会立即启用主题和 `setMyPwsh` 命令。
- 如果当前是交互式 Windows PowerShell 5.1，脚本会自动执行 `pwsh`，进入已经配置好的 PowerShell 7。
- Windows Terminal 的默认 Profile 和字体会在新标签页中生效。

随后可以直接使用本地管理命令：

```powershell
setMyPwsh theme
setMyPwsh theme atomic
setMyPwsh check
setMyPwsh repair
setMyPwsh update
```

其中 `setMyPwsh theme` 会显示主题菜单，`setMyPwsh theme atomic` 会直接切换到指定主题。`update` 会获取最新版 setMyPwsh 并重新应用配置。

高级用户如需在首次远程安装时传递参数，可以把下载内容转换成 ScriptBlock：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/dhg007/setMyPwsh/main/install.ps1).TrimStart([char]0xFEFF))) -Yes -Theme atomic -SkipFont
```

建议在发布文档中同时提供“先查看脚本”的链接，不要使用会随意指向不同内容的短网址。

## Profile 安全策略

脚本只维护以下标记之间的内容：

```powershell
# >>> setMyPwsh managed block >>>
# ...
# <<< setMyPwsh managed block <<<
```

已有 Profile 会先生成带时间戳的备份。区块之外的用户配置不会被覆盖，重复运行也不会重复追加受管内容。

`gp` 默认是 PowerShell 的 `Get-ItemProperty` 别名。为了让 `gp` 执行 `git push`，受管区块会移除该别名。

## 参数

以下参数在本地执行 `install.ps1` 时可以直接使用。远程执行时，请使用上面的 ScriptBlock 写法传递参数；不能把参数直接追加到 `irm ... | iex` 后面。

| 参数 | 作用 |
| --- | --- |
| `-Theme NAME` | 指定 Oh My Posh 主题 |
| `-Yes` | 自动接受安装步骤并使用默认选项 |
| `-SkipFont` | 不安装 Meslo Nerd Font |
| `-DryRun` | 只检查和预览，不产生更改 |
| `-ProfilePath PATH` | 指定 Profile 路径，主要用于测试 |
| `-TerminalSettingsPath PATH` | 指定 Windows Terminal 配置路径，主要用于测试 |
| `-CommandInstallPath PATH` | 指定管理脚本安装路径，主要用于测试 |
