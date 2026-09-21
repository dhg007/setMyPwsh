[CmdletBinding()]
param(
    [string]$Theme,
    [switch]$Yes,
    [switch]$SkipFont,
    [switch]$DryRun,
    [string]$ProfilePath,
    [string]$TerminalSettingsPath,
    [string]$CommandInstallPath
)

$ErrorActionPreference = 'Stop'
$script:Version = '0.2.0'
$script:StartMarker = '# >>> setMyPwsh managed block >>>'
$script:EndMarker = '# <<< setMyPwsh managed block <<<'
$script:RecommendedThemes = @(
    'jandedobbeleer',
    'atomic',
    'paradox',
    'powerlevel10k_rainbow',
    'tokyo',
    'minimal'
)

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Test-IsPowerShell7 {
    return $PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion.Major -ge 7
}

function Test-IsInteractiveConsole {
    try {
        return $Host.Name -eq 'ConsoleHost' -and
            -not [Console]::IsInputRedirected -and
            -not [Console]::IsOutputRedirected
    } catch {
        return $false
    }
}

function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Find-Executable {
    param([Parameter(Mandatory = $true)][string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) {
        if ($command.Source) { return $command.Source }
        if ($command.Path) { return $command.Path }
    }

    $candidates = @()
    switch ($Name.ToLowerInvariant()) {
        'pwsh.exe' {
            $candidates += Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
            $candidates += Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
        }
        'oh-my-posh.exe' {
            $candidates += Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\bin\oh-my-posh.exe'
            $candidates += Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\oh-my-posh.exe'
        }
        'wt.exe' {
            $candidates += Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
        }
        'winget.exe' {
            $candidates += Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
        }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    return $null
}

function Confirm-Action {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [bool]$DefaultYes = $true
    )

    if ($Yes) { return $true }
    $hint = if ($DefaultYes) { 'Y/n' } else { 'y/N' }
    $answer = Read-Host "$Message [$hint]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
    return $answer -match '^(?i:y|yes|是)$'
}

function Select-Theme {
    if (-not [string]::IsNullOrWhiteSpace($Theme)) {
        return $Theme
    }
    if ($Yes) { return 'jandedobbeleer' }

    Write-Host "`n请选择 Oh My Posh 主题："
    for ($index = 0; $index -lt $script:RecommendedThemes.Count; $index++) {
        Write-Host ('  {0}. {1}' -f ($index + 1), $script:RecommendedThemes[$index])
    }
    Write-Host '  7. 输入其他主题名'
    $choice = Read-Host '选择 [1-7]（默认 1）'
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }

    $number = 0
    if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le 6) {
        return $script:RecommendedThemes[$number - 1]
    }
    if ($choice -eq '7') {
        return Read-Host '请输入主题名'
    }
    throw "无效的主题选择：$choice"
}

function Resolve-ThemeConfig {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -match '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
        return $Value
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($Value)
    try {
        $fullPath = [IO.Path]::GetFullPath($expanded)
    } catch {
        throw "无效的自定义主题路径：$Value"
    }
    if ($fullPath -notmatch '(?i)\.omp\.(json|ya?ml|toml)$') {
        throw '自定义主题文件必须以 .omp.json、.omp.yaml、.omp.yml 或 .omp.toml 结尾。'
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "找不到自定义主题文件：$fullPath"
    }
    return $fullPath
}

function Get-ConfiguredTheme {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    $content = [IO.File]::ReadAllText($Path)
    $start = $content.IndexOf($script:StartMarker, [StringComparison]::Ordinal)
    $end = $content.IndexOf($script:EndMarker, [StringComparison]::Ordinal)
    if ($start -lt 0 -or $end -le $start) {
        return $null
    }

    $managedBlock = $content.Substring($start, $end - $start)
    $match = [regex]::Match(
        $managedBlock,
        "(?m)^\s*oh-my-posh\s+init\s+pwsh\s+--config\s+'(?<theme>(?:''|[^'])*)'"
    )
    if ($match.Success) {
        return $match.Groups['theme'].Value.Replace("''", "'")
    }
    return $null
}

function Get-ComponentStatus {
    $items = @(
        [pscustomobject]@{ Name = 'WinGet'; Command = 'winget.exe'; Package = $null },
        [pscustomobject]@{ Name = 'Windows Terminal'; Command = 'wt.exe'; Package = 'Microsoft.WindowsTerminal' },
        [pscustomobject]@{ Name = 'PowerShell 7'; Command = 'pwsh.exe'; Package = 'Microsoft.PowerShell' },
        [pscustomobject]@{ Name = 'Oh My Posh'; Command = 'oh-my-posh.exe'; Package = 'JanDeDobbeleer.OhMyPosh' }
    )

    foreach ($item in $items) {
        $path = Find-Executable $item.Command
        [pscustomobject]@{
            Name = $item.Name
            Command = $item.Command
            Package = $item.Package
            Installed = -not [string]::IsNullOrWhiteSpace($path)
            Path = $path
        }
    }
}

function Show-ComponentStatus {
    param([Parameter(Mandatory = $true)][array]$Status)
    foreach ($item in $Status) {
        $mark = if ($item.Installed) { '[OK]' } else { '[--]' }
        $detail = if ($item.Installed) { $item.Path } else { '未安装' }
        Write-Host ('{0} {1,-18} {2}' -f $mark, $item.Name, $detail)
    }
}

function Install-WinGetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [Parameter(Mandatory = $true)][string]$WinGetPath
    )

    Write-Step "安装 $DisplayName"
    if ($DryRun) {
        Write-Host "[DryRun] winget install --id $PackageId --exact --source winget"
        return
    }

    $arguments = @(
        'install', '--id', $PackageId, '--exact', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity'
    )
    & $WinGetPath @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "安装 $DisplayName 失败，WinGet 退出代码：$LASTEXITCODE"
    }
    Write-Ok "$DisplayName 安装完成"
}

function Get-ManagedBlock {
    param([Parameter(Mandatory = $true)][string]$ThemeName)

    $template = @'
# >>> setMyPwsh managed block >>>
# 此区块由 setMyPwsh 管理；可修改区块外的其他配置。

if ($Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue
    Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction SilentlyContinue
}

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config '{{THEME}}' | Invoke-Expression
}

# PowerShell 默认将 gp 用作 Get-ItemProperty 的别名。
Remove-Item Alias:gp -Force -ErrorAction SilentlyContinue

function gpr   { git pull --rebase @args }
function gp    { git push @args }
function gst   { git status @args }
function gcmsg { git commit --message @args }
function glog  { git log --oneline --decorate --graph @args }
function ga    { git add @args }
function gco   { git checkout @args }
function gb    { git branch @args }
function gba   { git branch --all @args }

function setMyPwsh { & "$env:LOCALAPPDATA\setMyPwsh\setMyPwsh.ps1" @args }
# <<< setMyPwsh managed block <<<
'@
    $escapedTheme = $ThemeName.Replace("'", "''")
    return $template.Replace('{{THEME}}', $escapedTheme)
}

function Resolve-CommandInstallPath {
    if (-not [string]::IsNullOrWhiteSpace($CommandInstallPath)) {
        return [IO.Path]::GetFullPath($CommandInstallPath)
    }
    return Join-Path $env:LOCALAPPDATA 'setMyPwsh\setMyPwsh.ps1'
}

function Install-ManagementCommand {
    param([Parameter(Mandatory = $true)][string]$Path)

    Write-Step '安装 setMyPwsh 管理命令'
    if ($DryRun) {
        Write-Host "[DryRun] 将安装：$Path"
        return
    }

    $managementScript = @'
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command = 'help',
    [Parameter(Position = 1)][string]$Value
)

$ErrorActionPreference = 'Stop'
$installerUrl = 'https://raw.githubusercontent.com/dhg007/setMyPwsh/main/install.ps1'
$themes = @('jandedobbeleer', 'atomic', 'paradox', 'powerlevel10k_rainbow', 'tokyo', 'minimal')
$customThemesDirectory = Join-Path $PSScriptRoot 'customThemes'

function Get-InstallerBlock {
    Write-Host '正在获取最新版 setMyPwsh...' -ForegroundColor Cyan
    $source = Invoke-RestMethod -Uri $installerUrl -UseBasicParsing
    return [scriptblock]::Create($source.TrimStart([char]0xFEFF))
}

function Invoke-Installer {
    param([string]$ThemeName)
    $installer = Get-InstallerBlock
    if ([string]::IsNullOrWhiteSpace($ThemeName)) {
        & $installer
    } else {
        & $installer -Theme $ThemeName
    }
}

function Select-CustomTheme {
    [void](New-Item -ItemType Directory -Force -Path $customThemesDirectory)
    $customThemes = @(
        Get-ChildItem -LiteralPath $customThemesDirectory -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)\.omp\.(json|ya?ml|toml)$' } |
            Sort-Object Name
    )
    if ($customThemes.Count -eq 0) {
        Write-Host "未找到自定义主题，请先把主题文件放入：$customThemesDirectory" -ForegroundColor Yellow
        return $null
    }

    Write-Host "自定义主题目录：$customThemesDirectory"
    for ($index = 0; $index -lt $customThemes.Count; $index++) {
        Write-Host ('  {0}. {1}' -f ($index + 1), $customThemes[$index].Name)
    }
    $choice = Read-Host "选择 [1-$($customThemes.Count)]（默认 1）"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
    $number = 0
    if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $customThemes.Count) {
        return $customThemes[$number - 1].FullName
    }
    throw "无效的自定义主题选择：$choice"
}

function Select-Theme {
    Write-Host '请选择 Oh My Posh 主题：'
    for ($index = 0; $index -lt $themes.Count; $index++) {
        Write-Host ('  {0}. {1}' -f ($index + 1), $themes[$index])
    }
    Write-Host '  7. 输入其他主题名'
    Write-Host '  8. 选择自定义主题'
    $choice = Read-Host '选择 [1-8]（默认 1）'
    if ([string]::IsNullOrWhiteSpace($choice)) { return $themes[0] }
    $number = 0
    if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $themes.Count) {
        return $themes[$number - 1]
    }
    if ($choice -eq '7') { return Read-Host '请输入主题名' }
    if ($choice -eq '8') { return Select-CustomTheme }
    throw "无效的主题选择：$choice"
}

function Show-Status {
    $commands = @(
        @{ Name = 'WinGet'; Command = 'winget.exe' },
        @{ Name = 'Windows Terminal'; Command = 'wt.exe' },
        @{ Name = 'PowerShell 7'; Command = 'pwsh.exe' },
        @{ Name = 'Oh My Posh'; Command = 'oh-my-posh.exe' }
    )
    foreach ($item in $commands) {
        $found = Get-Command $item.Command -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            Write-Host ('[OK] {0,-18} {1}' -f $item.Name, $found.Source) -ForegroundColor Green
        } else {
            Write-Host ('[--] {0,-18} 未安装' -f $item.Name) -ForegroundColor Yellow
        }
    }
    if ($env:POSH_THEME) {
        Write-Host "当前主题配置：$env:POSH_THEME"
    }
}

switch ($Command.ToLowerInvariant()) {
    'theme' {
        $theme = $Value
        if ([string]::IsNullOrWhiteSpace($theme)) { $theme = Select-Theme }
        if ([string]::IsNullOrWhiteSpace($theme)) { return }
        Invoke-Installer -ThemeName $theme
    }
    'check' {
        Show-Status
    }
    'repair' {
        Invoke-Installer
    }
    'update' {
        Invoke-Installer
    }
    { $_ -in @('help', '-h', '--help') } {
        Write-Host @"
setMyPwsh 管理命令

用法：
  setMyPwsh theme              交互选择并切换主题
  setMyPwsh theme atomic       直接切换到指定主题
  自定义主题目录               $customThemesDirectory
  setMyPwsh check              检查组件状态
  setMyPwsh repair             重新检查并应用配置
  setMyPwsh update             获取最新版并重新应用配置
  setMyPwsh help               显示帮助
"@
    }
    default {
        throw "未知命令：$Command。运行 setMyPwsh help 查看帮助。"
    }
}
'@

    $directory = Split-Path -Parent $Path
    [void](New-Item -ItemType Directory -Force -Path $directory)
    [void](New-Item -ItemType Directory -Force -Path (Join-Path $directory 'customThemes'))
    $tempPath = Join-Path $directory ('.setMyPwsh-command-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($tempPath, $managementScript, [Text.UTF8Encoding]::new($true))
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($tempPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            throw "生成的 setMyPwsh 管理脚本存在语法错误：$($parseErrors[0].Message)"
        }
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Remove-Item -LiteralPath $Path -Force
        }
        [IO.File]::Move($tempPath, $Path)
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
    Write-Ok "管理命令已安装：$Path"
}

function Enable-CurrentShellExperience {
    param(
        [Parameter(Mandatory = $true)][string]$PwshPath,
        [Parameter(Mandatory = $true)][string]$ThemeName,
        [Parameter(Mandatory = $true)][string]$ManagementCommandPath
    )

    if ($DryRun) { return }

    if (Test-IsPowerShell7) {
        $escapedCommandPath = $ManagementCommandPath.Replace("'", "''")
        $commandBody = [scriptblock]::Create("& '$escapedCommandPath' @args")
        Set-Item -Path Function:\global:setMyPwsh -Value $commandBody -Force

        if (Test-IsInteractiveConsole) {
            Import-Module PSReadLine -ErrorAction SilentlyContinue
            Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue
            Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction SilentlyContinue
        }

        $ohMyPosh = Find-Executable 'oh-my-posh.exe'
        if (-not [string]::IsNullOrWhiteSpace($ohMyPosh)) {
            Remove-Module oh-my-posh-core -Force -ErrorAction SilentlyContinue
            & $ohMyPosh init pwsh --config $ThemeName | Invoke-Expression
        }

        Write-Ok '当前 PowerShell 7 会话已立即启用新配置。'
        return
    }

    if (Test-IsInteractiveConsole) {
        Write-Host "`n当前是 Windows PowerShell $($PSVersionTable.PSVersion)。正在为你进入 PowerShell 7..." -ForegroundColor Cyan
        Write-Host '进入后可直接运行：setMyPwsh help' -ForegroundColor Cyan
        & $PwshPath
        return
    }

    Write-Warn '当前不是 PowerShell 7，且此环境不能自动启动交互会话。请运行 pwsh 进入 PowerShell 7。'
}

function Merge-ManagedBlock {
    param(
        [AllowEmptyString()][string]$Existing,
        [Parameter(Mandatory = $true)][string]$Block
    )

    $start = $Existing.IndexOf($script:StartMarker, [StringComparison]::Ordinal)
    $end = $Existing.IndexOf($script:EndMarker, [StringComparison]::Ordinal)
    if (($start -ge 0) -xor ($end -ge 0)) {
        throw 'Profile 中的 setMyPwsh 标记不完整，请修复后重试。'
    }
    if ($start -ge 0) {
        if ($end -lt $start) { throw 'Profile 中的 setMyPwsh 标记顺序无效。' }
        $end += $script:EndMarker.Length
        return $Existing.Substring(0, $start) + $Block + $Existing.Substring($end)
    }
    if ([string]::IsNullOrWhiteSpace($Existing)) {
        return $Block + "`r`n"
    }
    return $Existing.TrimEnd("`r", "`n") + "`r`n`r`n" + $Block + "`r`n"
}

function Resolve-ProfilePath {
    param([Parameter(Mandatory = $true)][string]$PwshPath)
    if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
        return [IO.Path]::GetFullPath($ProfilePath)
    }
    $resolved = & $PwshPath -NoLogo -NoProfile -NonInteractive -Command '[Console]::Out.Write($PROFILE.CurrentUserCurrentHost)'
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resolved)) {
        throw '无法获取 PowerShell 7 的 Profile 路径。'
    }
    return [IO.Path]::GetFullPath(([string]$resolved).Trim())
}

function Set-PowerShellProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ThemeName
    )

    Write-Step '配置 PowerShell Profile'
    $existing = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        [IO.File]::ReadAllText($Path)
    } else {
        ''
    }
    $updated = Merge-ManagedBlock -Existing $existing -Block (Get-ManagedBlock -ThemeName $ThemeName)
    if ($existing -ceq $updated) {
        Write-Ok "Profile 已是最新状态：$Path"
        return
    }
    if ($DryRun) {
        Write-Host "[DryRun] 将更新：$Path"
        Write-Host "`n---------- Profile 受管区块预览 ----------"
        Write-Host (Get-ManagedBlock -ThemeName $ThemeName)
        Write-Host '------------------------------------------'
        return
    }

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        [void](New-Item -ItemType Directory -Force -Path $directory)
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $tempPath = Join-Path $directory ('.setMyPwsh-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($tempPath, $updated, $utf8NoBom)
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $backupPath = $Path + '.setMyPwsh-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss.fff')
            [IO.File]::Replace($tempPath, $Path, $backupPath, $true)
            Write-Ok "Profile 已更新：$Path"
            Write-Ok "原文件已备份：$backupPath"
        } else {
            [IO.File]::Move($tempPath, $Path)
            Write-Ok "Profile 已创建：$Path"
        }
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
}

function Test-NerdFontInstalled {
    param(
        [Parameter(Mandatory = $true)][string]$OhMyPoshPath,
        [Parameter(Mandatory = $true)][string]$FontName
    )

    # 新版 Oh My Posh 能直接报告由它安装的字体状态。
    try {
        $fontStateOutput = & $OhMyPoshPath font dsc get 2>$null
        if ($LASTEXITCODE -eq 0 -and $fontStateOutput) {
            $fontState = ($fontStateOutput -join [Environment]::NewLine) | ConvertFrom-Json
            if (@($fontState.states | ForEach-Object { $_.name }) -contains $FontName) {
                return $true
            }
        }
    } catch {
        # 兼容尚未支持 font dsc 的旧版本，继续检查 Windows 字体注册表。
    }

    $fontRegistryPaths = @(
        'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    )
    foreach ($registryPath in $fontRegistryPaths) {
        try {
            $fontKey = Get-Item -LiteralPath $registryPath -ErrorAction Stop
            if (@($fontKey.GetValueNames() | Where-Object { $_ -like 'Meslo*Nerd Font*' }).Count -gt 0) {
                return $true
            }
        } catch {
            # 当前用户可能没有权限读取某些系统级注册表项。
        }
    }
    return $false
}

function Install-NerdFont {
    param([Parameter(Mandatory = $true)][string]$OhMyPoshPath)
    if ($SkipFont) {
        Write-Warn '已跳过 Nerd Font 安装。'
        return
    }
    if (Test-NerdFontInstalled -OhMyPoshPath $OhMyPoshPath -FontName 'Meslo') {
        Write-Ok 'Meslo Nerd Font 已安装，跳过字体安装。'
        return
    }
    if (-not (Confirm-Action -Message '是否安装 Meslo Nerd Font？' -DefaultYes $true)) {
        return
    }
    Write-Step '安装 Meslo Nerd Font'
    if ($DryRun) {
        Write-Host '[DryRun] oh-my-posh font install meslo'
        return
    }
    & $OhMyPoshPath font install meslo
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "字体安装失败，退出代码：$LASTEXITCODE"
        return
    }
    Write-Ok 'Meslo Nerd Font 安装完成。'
}

function Resolve-WindowsTerminalSettingsPath {
    if (-not [string]::IsNullOrWhiteSpace($TerminalSettingsPath)) {
        return [IO.Path]::GetFullPath($TerminalSettingsPath)
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    # setMyPwsh 安装的是稳定版 Windows Terminal。首次启动前 settings.json 可能尚不存在。
    return $candidates[0]
}

function Set-WindowsTerminalDefaults {
    param(
        [Parameter(Mandatory = $true)][string]$PwshPath,
        [Parameter(Mandatory = $true)][string]$SettingsPath
    )

    Write-Step '配置 Windows Terminal'
    if ($DryRun) {
        Write-Host "[DryRun] 将更新：$SettingsPath"
        Write-Host '[DryRun] 默认 Profile：PowerShell 7'
        Write-Host '[DryRun] 默认字体：MesloLGM Nerd Font'
        return
    }

    $editor = @'
$ErrorActionPreference = 'Stop'
$path = $env:SETMYPWSH_TERMINAL_SETTINGS
$powerShellGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'

if (Test-Path -LiteralPath $path -PathType Leaf) {
    $original = [IO.File]::ReadAllText($path)
    $settings = $original | ConvertFrom-Json -AsHashtable
} else {
    $original = ''
    $settings = [ordered]@{
        '$help' = 'https://aka.ms/terminal-documentation'
        '$schema' = 'https://aka.ms/terminal-profiles-schema'
    }
}

$settings['defaultProfile'] = $powerShellGuid

if (-not $settings.Contains('profiles') -or $null -eq $settings['profiles']) {
    $settings['profiles'] = [ordered]@{
        'defaults' = [ordered]@{}
        'list' = @()
    }
} elseif ($settings['profiles'] -is [System.Collections.IList]) {
    $oldList = $settings['profiles']
    $settings['profiles'] = [ordered]@{
        'defaults' = [ordered]@{}
        'list' = $oldList
    }
}

$profiles = $settings['profiles']
if (-not $profiles.Contains('defaults') -or $null -eq $profiles['defaults']) {
    $profiles['defaults'] = [ordered]@{}
}
$defaults = $profiles['defaults']
if (-not $defaults.Contains('font') -or $null -eq $defaults['font']) {
    $defaults['font'] = [ordered]@{}
}
$defaults['font']['face'] = 'MesloLGM Nerd Font'

$json = $settings | ConvertTo-Json -Depth 100
if ($original.TrimEnd() -ceq $json.TrimEnd()) {
    Write-Output 'unchanged'
    exit 0
}

$directory = Split-Path -Parent $path
[void](New-Item -ItemType Directory -Force -Path $directory)
$tempPath = Join-Path $directory ('.setMyPwsh-terminal-' + [Guid]::NewGuid().ToString('N') + '.tmp')
try {
    [IO.File]::WriteAllText($tempPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $null = [IO.File]::ReadAllText($tempPath) | ConvertFrom-Json
    [IO.File]::Move($tempPath, $path, $true)
} finally {
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Force
    }
}
Write-Output 'updated'
'@

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($editor))
    $previousPath = $env:SETMYPWSH_TERMINAL_SETTINGS
    try {
        $env:SETMYPWSH_TERMINAL_SETTINGS = $SettingsPath
        $result = & $PwshPath -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded
        if ($LASTEXITCODE -ne 0) {
            throw "更新 Windows Terminal 配置失败，退出代码：$LASTEXITCODE"
        }
    } finally {
        $env:SETMYPWSH_TERMINAL_SETTINGS = $previousPath
    }

    if (($result | Select-Object -Last 1) -eq 'unchanged') {
        Write-Ok "Windows Terminal 已是目标配置：$SettingsPath"
    } else {
        Write-Ok "Windows Terminal 已更新：$SettingsPath"
    }
    Write-Ok '默认 Profile：PowerShell 7'
    Write-Ok '默认字体：MesloLGM Nerd Font'
}

function Invoke-SetMyPwsh {
    if ($env:OS -ne 'Windows_NT') {
        throw 'setMyPwsh 目前仅支持 Windows。'
    }

    Write-Host "setMyPwsh 一键安装脚本 v$script:Version" -ForegroundColor Cyan
    if ($DryRun) { Write-Warn 'Dry Run 模式：不会安装软件或修改文件。' }

    Write-Step '检查环境'
    $status = @(Get-ComponentStatus)
    Show-ComponentStatus -Status $status

    $missing = @($status | Where-Object { -not $_.Installed -and $null -ne $_.Package })
    if ($missing.Count -gt 0) {
        $wingetItem = $status | Where-Object { $_.Name -eq 'WinGet' } | Select-Object -First 1
        if (-not $wingetItem.Installed) {
            throw '未找到 WinGet。请先从 Microsoft Store 安装“应用安装程序”，然后重新运行。'
        }
        Write-Host "`n将安装以下组件："
        foreach ($item in $missing) { Write-Host "  - $($item.Name)" }
        if (-not (Confirm-Action -Message '继续安装？' -DefaultYes $true)) {
            Write-Warn '用户取消操作。'
            return
        }
        foreach ($item in $missing) {
            Install-WinGetPackage -PackageId $item.Package -DisplayName $item.Name -WinGetPath $wingetItem.Path
        }
    } else {
        Write-Ok '所有核心组件均已安装。'
    }

    if ($DryRun) {
        $pwshPath = Find-Executable 'pwsh.exe'
        if ([string]::IsNullOrWhiteSpace($pwshPath) -and [string]::IsNullOrWhiteSpace($ProfilePath)) {
            $ProfilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
            Write-Warn 'Dry Run 中未找到 pwsh，使用默认路径生成预览。'
        }
        if ([string]::IsNullOrWhiteSpace($pwshPath)) {
            $pwshPath = 'pwsh.exe'
        }
    } else {
        $pwshPath = Find-Executable 'pwsh.exe'
        if ([string]::IsNullOrWhiteSpace($pwshPath)) {
            throw '安装完成后仍找不到 pwsh.exe。请重新打开终端后再次运行脚本。'
        }
    }

    $resolvedProfile = if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
        [IO.Path]::GetFullPath($ProfilePath)
    } else {
        Resolve-ProfilePath -PwshPath $pwshPath
    }

    if (-not [string]::IsNullOrWhiteSpace($Theme)) {
        $selectedTheme = $Theme
    } else {
        $selectedTheme = Get-ConfiguredTheme -Path $resolvedProfile
        if (-not [string]::IsNullOrWhiteSpace($selectedTheme)) {
            Write-Ok "已配置 Oh My Posh 主题：$selectedTheme"
        } else {
            $selectedTheme = Select-Theme
        }
    }
    $selectedTheme = Resolve-ThemeConfig -Value $selectedTheme
    $managementCommandPath = Resolve-CommandInstallPath
    Install-ManagementCommand -Path $managementCommandPath
    Set-PowerShellProfile -Path $resolvedProfile -ThemeName $selectedTheme

    $ompPath = Find-Executable 'oh-my-posh.exe'
    if (-not [string]::IsNullOrWhiteSpace($ompPath)) {
        Install-NerdFont -OhMyPoshPath $ompPath
    } elseif (-not $DryRun) {
        Write-Warn '未找到 oh-my-posh.exe，已跳过字体安装。重新打开终端后可以运行：oh-my-posh font install meslo'
    }

    $terminalSettings = Resolve-WindowsTerminalSettingsPath
    Set-WindowsTerminalDefaults -PwshPath $pwshPath -SettingsPath $terminalSettings

    Write-Host "`n完成！主题：$selectedTheme" -ForegroundColor Green
    Write-Host 'Windows Terminal 的默认 Profile 和字体将在新标签页中生效。'
    Enable-CurrentShellExperience -PwshPath $pwshPath -ThemeName $selectedTheme -ManagementCommandPath $managementCommandPath
}

try {
    Invoke-SetMyPwsh
} catch {
    Write-Host "`n安装失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host '没有完成的步骤可以在修复问题后安全地重新运行；Profile 更新是可重复的。' -ForegroundColor Yellow
    throw
}
