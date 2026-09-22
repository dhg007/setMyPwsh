$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$scriptPath = Join-Path $root 'install.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('setMyPwsh-test-' + [Guid]::NewGuid().ToString('N'))
$profilePath = Join-Path $testRoot 'Microsoft.PowerShell_profile.ps1'
$terminalSettingsPath = Join-Path $testRoot 'settings.json'
$commandPath = Join-Path $testRoot 'setMyPwsh.ps1'

try {
    [void](New-Item -ItemType Directory -Force -Path $testRoot)
    [IO.File]::WriteAllText($profilePath, "function UserConfig { 'preserve me' }`r`n")
    [IO.File]::WriteAllText($terminalSettingsPath, @'
{
    // Existing user setting must be preserved.
    "copyOnSelect": true,
    "profiles": {
        "defaults": {
            "opacity": 90
        },
        "list": [],
    },
}
'@)

    & $scriptPath -Yes -Theme atomic -SkipFont -ProfilePath $profilePath -TerminalSettingsPath $terminalSettingsPath -CommandInstallPath $commandPath

    $first = [IO.File]::ReadAllText($profilePath)
    if ($first -notmatch 'function UserConfig') { throw '原有 Profile 内容丢失。' }
    if ($first -notmatch "--config 'atomic'") { throw '主题未写入。' }
    if (($first.Split(@('# >>> setMyPwsh managed block >>>'), [StringSplitOptions]::None).Count - 1) -ne 1) {
        throw '受管区块数量不正确。'
    }
    if ($first -notmatch 'function setMyPwsh') { throw 'Profile 中缺少 setMyPwsh 管理命令。' }
    if (-not (Test-Path -LiteralPath $commandPath -PathType Leaf)) { throw '管理脚本未安装。' }
    $commandHelp = & pwsh.exe -NoLogo -NoProfile -File $commandPath help | Out-String
    if ($commandHelp -notmatch 'setMyPwsh theme') { throw '管理命令帮助输出不正确。' }

    $themeForwardingTestPath = Join-Path $testRoot 'theme-forwarding-test.ps1'
    $themeCapturePath = Join-Path $testRoot 'forwarded-theme.txt'
    [IO.File]::WriteAllText($themeForwardingTestPath, @'
param(
    [string]$ManagementCommandPath,
    [string]$CapturePath
)

$env:SETMYPWSH_THEME_CAPTURE = $CapturePath
function Invoke-RestMethod {
    return @"
param([string]`$Theme)
[IO.File]::WriteAllText(`$env:SETMYPWSH_THEME_CAPTURE, `$Theme)
"@
}
& $ManagementCommandPath theme atomic
'@, [Text.UTF8Encoding]::new($true))
    & pwsh.exe -NoLogo -NoProfile -File $themeForwardingTestPath -ManagementCommandPath $commandPath -CapturePath $themeCapturePath
    if ($LASTEXITCODE -ne 0) { throw '管理命令主题参数转发测试失败。' }
    if ([IO.File]::ReadAllText($themeCapturePath) -ne 'atomic') {
        throw '管理命令没有把 atomic 正确绑定到安装脚本的 Theme 参数。'
    }

    $customThemesPath = Join-Path (Split-Path -Parent $commandPath) 'customThemes'
    if (-not (Test-Path -LiteralPath $customThemesPath -PathType Container)) {
        throw '自定义主题目录未创建。'
    }
    $customThemePath = Join-Path $customThemesPath "one'dark.omp.json"
    [IO.File]::WriteAllText($customThemePath, '{"version":4,"blocks":[]}', [Text.UTF8Encoding]::new($false))

    $customMenuTestPath = Join-Path $testRoot 'custom-theme-menu-test.ps1'
    $customThemeCapturePath = Join-Path $testRoot 'forwarded-custom-theme.txt'
    [IO.File]::WriteAllText($customMenuTestPath, @'
param(
    [string]$ManagementCommandPath,
    [string]$CapturePath
)

$env:SETMYPWSH_THEME_CAPTURE = $CapturePath
$global:setMyPwshTestAnswers = [Collections.Generic.Queue[string]]::new()
$global:setMyPwshTestAnswers.Enqueue('8')
$global:setMyPwshTestAnswers.Enqueue('1')
function Read-Host { return $global:setMyPwshTestAnswers.Dequeue() }
function Invoke-RestMethod {
    return @"
param([string]`$Theme)
[IO.File]::WriteAllText(`$env:SETMYPWSH_THEME_CAPTURE, `$Theme)
"@
}
& $ManagementCommandPath theme
'@, [Text.UTF8Encoding]::new($true))
    & pwsh.exe -NoLogo -NoProfile -File $customMenuTestPath -ManagementCommandPath $commandPath -CapturePath $customThemeCapturePath
    if ($LASTEXITCODE -ne 0) { throw '自定义主题菜单测试失败。' }
    if ([IO.File]::ReadAllText($customThemeCapturePath) -ne $customThemePath) {
        throw '菜单第 8 项没有正确转发自定义主题路径。'
    }

    $terminal = [IO.File]::ReadAllText($terminalSettingsPath) | ConvertFrom-Json
    if ($terminal.defaultProfile -ne '{574e775e-4f2a-5b96-ac1e-a2962a402336}') {
        throw 'Windows Terminal 默认 Profile 未设置为 PowerShell 7。'
    }
    if ($terminal.profiles.defaults.font.face -ne 'MesloLGM Nerd Font') {
        throw 'Windows Terminal 字体未正确设置。'
    }
    if (-not $terminal.copyOnSelect -or $terminal.profiles.defaults.opacity -ne 90) {
        throw 'Windows Terminal 原有配置未被保留。'
    }

    & $scriptPath -Yes -Theme paradox -SkipFont -ProfilePath $profilePath -TerminalSettingsPath $terminalSettingsPath -CommandInstallPath $commandPath

    $second = [IO.File]::ReadAllText($profilePath)
    if ($second -match "--config 'atomic'") { throw '旧主题仍然存在。' }
    if ($second -notmatch "--config 'paradox'") { throw '新主题未写入。' }
    if (($second.Split(@('# >>> setMyPwsh managed block >>>'), [StringSplitOptions]::None).Count - 1) -ne 1) {
        throw '重复运行产生了重复区块。'
    }

    $backups = @(Get-ChildItem -LiteralPath $testRoot -Filter '*.setMyPwsh-backup-*')
    if ($backups.Count -lt 2) { throw '没有按预期创建 Profile 备份。' }

    & $scriptPath -Yes -SkipFont -ProfilePath $profilePath -TerminalSettingsPath $terminalSettingsPath -CommandInstallPath $commandPath
    $third = [IO.File]::ReadAllText($profilePath)
    $backupsAfterNoChange = @(Get-ChildItem -LiteralPath $testRoot -Filter '*.setMyPwsh-backup-*')
    if ($third -cne $second) { throw '未指定主题重复运行后，已有主题或文件内容发生变化。' }
    if ($third -notmatch "--config 'paradox'") { throw '重复运行时没有沿用已有主题。' }
    if ($backupsAfterNoChange.Count -ne $backups.Count) { throw '无变化时不应创建新备份。' }

    & $scriptPath -Yes -Theme $customThemePath -SkipFont -ProfilePath $profilePath -TerminalSettingsPath $terminalSettingsPath -CommandInstallPath $commandPath
    $customProfile = [IO.File]::ReadAllText($profilePath)
    $escapedCustomTheme = $customThemePath.Replace("'", "''")
    if ($customProfile -notmatch [regex]::Escape("--config '$escapedCustomTheme'")) {
        throw '自定义主题路径没有安全写入 Profile。'
    }

    & $scriptPath -Yes -SkipFont -ProfilePath $profilePath -TerminalSettingsPath $terminalSettingsPath -CommandInstallPath $commandPath
    $customProfileRepeated = [IO.File]::ReadAllText($profilePath)
    if ($customProfileRepeated -cne $customProfile) {
        throw '重复运行时没有保留自定义主题配置。'
    }

    $activationTestPath = Join-Path $testRoot 'activation-test.ps1'
    [IO.File]::WriteAllText($activationTestPath, @'
param(
    [string]$InstallerPath,
    [string]$TestProfilePath,
    [string]$TestTerminalSettingsPath,
    [string]$TestCommandPath
)

& $InstallerPath -Yes -Theme atomic -SkipFont -ProfilePath $TestProfilePath -TerminalSettingsPath $TestTerminalSettingsPath -CommandInstallPath $TestCommandPath
if (-not (Get-Command setMyPwsh -CommandType Function -ErrorAction SilentlyContinue)) {
    throw 'PowerShell 7 当前会话没有立即注册 setMyPwsh 命令。'
}
setMyPwsh help
if ([string]::IsNullOrWhiteSpace($env:POSH_CONFIG)) {
    throw 'PowerShell 7 当前会话没有立即加载 Oh My Posh 主题。'
}
'@, [Text.UTF8Encoding]::new($true))

    & pwsh.exe -NoLogo -NoProfile -File $activationTestPath -InstallerPath $scriptPath -TestProfilePath $profilePath -TestTerminalSettingsPath $terminalSettingsPath -TestCommandPath $commandPath
    if ($LASTEXITCODE -ne 0) { throw 'PowerShell 7 当前会话激活测试失败。' }

    $uninstallHarnessPath = Join-Path $testRoot 'uninstall-harness.ps1'
    [IO.File]::WriteAllText($uninstallHarnessPath, @'
param(
    [string]$ManagementCommandPath,
    [string]$Option
)
function Read-Host { return 'y' }
if ([string]::IsNullOrWhiteSpace($Option)) {
    & $ManagementCommandPath uninstall
} else {
    & $ManagementCommandPath uninstall $Option
}
'@, [Text.UTF8Encoding]::new($true))

    $normalUninstallRoot = Join-Path $testRoot 'normal-uninstall'
    $normalInstallRoot = Join-Path $normalUninstallRoot 'setMyPwsh'
    $normalCommandPath = Join-Path $normalInstallRoot 'setMyPwsh.ps1'
    $normalProfilePath = Join-Path $normalUninstallRoot 'Microsoft.PowerShell_profile.ps1'
    $normalTerminalPath = Join-Path $normalUninstallRoot 'settings.json'
    [void](New-Item -ItemType Directory -Force -Path $normalUninstallRoot)
    [IO.File]::WriteAllText($normalProfilePath, "function KeepAfterUninstall { 'keep' }`r`n")
    [IO.File]::WriteAllText($normalTerminalPath, '{}')
    & $scriptPath -Yes -Theme atomic -SkipFont -ProfilePath $normalProfilePath -TerminalSettingsPath $normalTerminalPath -CommandInstallPath $normalCommandPath
    $normalCustomTheme = Join-Path $normalInstallRoot 'customThemes\keep.omp.json'
    [IO.File]::WriteAllText($normalCustomTheme, '{"version":4,"blocks":[]}', [Text.UTF8Encoding]::new($false))

    & pwsh.exe -NoLogo -NoProfile -File $uninstallHarnessPath -ManagementCommandPath $normalCommandPath
    if ($LASTEXITCODE -ne 0) { throw '普通卸载测试失败。' }
    $normalProfileAfter = [IO.File]::ReadAllText($normalProfilePath)
    if ($normalProfileAfter -notmatch 'KeepAfterUninstall') { throw '普通卸载删除了用户 Profile 内容。' }
    if ($normalProfileAfter -match 'setMyPwsh managed block') { throw '普通卸载没有移除 Profile 受管区块。' }
    if (Test-Path -LiteralPath $normalCommandPath) { throw '普通卸载没有删除管理脚本。' }
    if (-not (Test-Path -LiteralPath $normalCustomTheme -PathType Leaf)) { throw '普通卸载不应删除自定义主题。' }
    if (@(Get-ChildItem -LiteralPath $normalUninstallRoot -Filter '*.setMyPwsh-uninstall-backup-*').Count -ne 1) {
        throw '普通卸载没有备份 Profile。'
    }

    $purgeUninstallRoot = Join-Path $testRoot 'purge-uninstall'
    $purgeInstallRoot = Join-Path $purgeUninstallRoot 'setMyPwsh'
    $purgeCommandPath = Join-Path $purgeInstallRoot 'setMyPwsh.ps1'
    $purgeProfilePath = Join-Path $purgeUninstallRoot 'Microsoft.PowerShell_profile.ps1'
    $purgeTerminalPath = Join-Path $purgeUninstallRoot 'settings.json'
    [void](New-Item -ItemType Directory -Force -Path $purgeUninstallRoot)
    [IO.File]::WriteAllText($purgeProfilePath, "function KeepAfterPurge { 'keep' }`r`n")
    [IO.File]::WriteAllText($purgeTerminalPath, '{}')
    & $scriptPath -Yes -Theme atomic -SkipFont -ProfilePath $purgeProfilePath -TerminalSettingsPath $purgeTerminalPath -CommandInstallPath $purgeCommandPath
    $purgeCustomTheme = Join-Path $purgeInstallRoot 'customThemes\remove.omp.json'
    [IO.File]::WriteAllText($purgeCustomTheme, '{"version":4,"blocks":[]}', [Text.UTF8Encoding]::new($false))

    & pwsh.exe -NoLogo -NoProfile -File $uninstallHarnessPath -ManagementCommandPath $purgeCommandPath -Option '--purge-data'
    if ($LASTEXITCODE -ne 0) { throw '彻底删除本地数据测试失败。' }
    $purgeProfileAfter = [IO.File]::ReadAllText($purgeProfilePath)
    if ($purgeProfileAfter -notmatch 'KeepAfterPurge') { throw '--purge-data 删除了用户 Profile 内容。' }
    if ($purgeProfileAfter -match 'setMyPwsh managed block') { throw '--purge-data 没有移除 Profile 受管区块。' }
    if (Test-Path -LiteralPath $purgeInstallRoot) { throw '--purge-data 没有删除 setMyPwsh 本地数据目录。' }
    if (@(Get-ChildItem -LiteralPath $purgeUninstallRoot -Filter '*.setMyPwsh-uninstall-backup-*').Count -ne 1) {
        throw '--purge-data 没有备份 Profile。'
    }

    Write-Host 'All tests passed.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
