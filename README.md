# setMyPwsh 一键安装脚本

setMyPwsh 是一个面向 Windows 的 PowerShell 7 环境一键配置脚本，适合在新电脑上快速搭建现代化命令行环境。只需运行一条命令，它就会安装所需组件、配置终端和 PowerShell Profile，并启用主题、命令预测与常用 Git 快捷命令。

脚本支持重复执行，不会重复追加配置；安装完成后还可以通过 `setMyPwsh` 命令检查环境、修复配置或随时切换 Oh My Posh 主题。

[仓库地址](https://github.com/dhg007/setMyPwsh)

支持在 Windows PowerShell 5.1 或 PowerShell 7 中一键安装。

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
- 支持从固定目录选择本地 Oh My Posh 自定义主题
- Git 快捷函数（不安装 Git）
- 安装后的 `setMyPwsh` 本地管理命令

## 一行远程安装

在 Windows PowerShell 5.1 或 PowerShell 7 中运行：

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
setMyPwsh uninstall
```

其中 `setMyPwsh theme` 会显示主题菜单，菜单第 8 项用于选择本地自定义主题；
`setMyPwsh theme atomic` 会直接切换到指定官方主题。
`update` 会获取最新版 setMyPwsh 并重新应用配置。

### 自定义主题

将自定义主题文件放入：

```text
%LOCALAPPDATA%\setMyPwsh\customThemes
```

然后运行：

```powershell
setMyPwsh theme
```

选择第 8 项后，脚本会列出目录中的主题文件供用户选择。支持 `.omp.json`、`.omp.yaml`、`.omp.yml` 和 `.omp.toml`，更新 setMyPwsh 时不会删除这些文件。

### 卸载

普通卸载会移除 PowerShell Profile 中的 setMyPwsh 受管区块和本地管理脚本，但保留自定义主题：

```powershell
setMyPwsh uninstall
```

如果还要删除 `%LOCALAPPDATA%\setMyPwsh\customThemes` 中的全部自定义主题：

```powershell
setMyPwsh uninstall --purge-data
```

两种卸载方式都会先要求确认并备份当前 Profile。卸载不会删除 PowerShell 7、Windows Terminal、Oh My Posh、Meslo Nerd Font，也不会还原 Windows Terminal 的默认 Profile 和字体设置。

运行前可以先[查看安装脚本](https://github.com/dhg007/setMyPwsh/blob/main/install.ps1)。

## Profile 安全策略

脚本只维护以下标记之间的内容：

```powershell
# >>> setMyPwsh managed block >>>
# ...
# <<< setMyPwsh managed block <<<
```

已有 Profile 会先生成带时间戳的备份。区块之外的用户配置不会被覆盖，重复运行也不会重复追加受管内容。

`gp` 默认是 PowerShell 的 `Get-ItemProperty` 别名。为了让 `gp` 执行 `git push`，受管区块会移除该别名。

## 本地运行

```powershell
git clone https://github.com/dhg007/setMyPwsh
cd setMyPwsh
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

以下参数在本地执行 `install.ps1` 时可以直接使用。

## 参数

| 参数 | 作用 |
| --- | --- |
| `-Theme NAME_OR_PATH` | 指定 Oh My Posh 官方主题名或本地自定义主题文件路径 |
| `-Yes` | 自动接受安装步骤并使用默认选项 |
| `-SkipFont` | 不安装 Meslo Nerd Font |
| `-DryRun` | 只检查和预览，不产生更改 |
| `-ProfilePath PATH` | 指定 Profile 路径，主要用于测试 |
| `-TerminalSettingsPath PATH` | 指定 Windows Terminal 配置路径，主要用于测试 |
| `-CommandInstallPath PATH` | 指定管理脚本安装路径，主要用于测试 |

## 关键目录说明

为了方便检查和清理，下面列出 setMyPwsh 会读取或写入的主要位置。`%LOCALAPPDATA%` 和 `%USERPROFILE%` 都表示当前用户自己的目录。

| 位置 | 用途 |
| --- | --- |
| `%LOCALAPPDATA%\setMyPwsh\setMyPwsh.ps1` | setMyPwsh 本地管理命令的实际脚本，会保留在本机 |
| `%LOCALAPPDATA%\setMyPwsh\customThemes` | 用户自定义主题目录，setMyPwsh 更新时不会删除其中的文件 |
| PowerShell 7 的 `$PROFILE.CurrentUserCurrentHost` | 写入受管配置区块；常见位置为 `%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`，实际路径由 PowerShell 7 决定 |
| `<Profile路径>.setMyPwsh-backup-时间戳` | 修改已有 Profile 前生成的备份文件，与 Profile 放在同一目录 |
| `<Profile路径>.setMyPwsh-uninstall-backup-时间戳` | 卸载前生成的 Profile 备份文件，与 Profile 放在同一目录 |
| `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` | Windows Terminal 稳定版配置；设置默认 Profile 和字体 |
| `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json` | Windows Terminal Preview 配置，仅在检测到该版本时使用 |
| `%LOCALAPPDATA%\Microsoft\Windows Terminal\settings.json` | 非商店版 Windows Terminal 的候选配置路径 |

更新 Profile、管理脚本或 Terminal 配置时，脚本会在目标文件旁创建名称以 `.setMyPwsh-` 开头的临时文件；写入完成后会自动删除。通过远程一行命令执行时，下载的 `install.ps1` 只在当前 PowerShell 进程中运行，不会另外保存到磁盘。

Windows Terminal、PowerShell 7 和 Oh My Posh 由 WinGet 安装，Meslo Nerd Font 由 Oh My Posh 安装；它们的最终安装目录由 WinGet、Oh My Posh 和 Windows 决定，setMyPwsh 不会自行指定其他隐藏目录。
