$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$scriptPath = Join-Path $root 'install.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('setMyPwsh-test-' + [Guid]::NewGuid().ToString('N'))
$profilePath = Join-Path $testRoot 'Microsoft.PowerShell_profile.ps1'
$terminalSettingsPath = Join-Path $testRoot 'settings.json'

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

    & $scriptPath -Yes -Theme atomic -SkipFont -ProfilePath $profilePath -TerminalSettingsPath $terminalSettingsPath

    $first = [IO.File]::ReadAllText($profilePath)
    if ($first -notmatch 'function UserConfig') { throw '原有 Profile 内容丢失。' }
    if ($first -notmatch "--config 'atomic'") { throw '主题未写入。' }
    if (($first.Split(@('# >>> setMyPwsh managed block >>>'), [StringSplitOptions]::None).Count - 1) -ne 1) {
        throw '受管区块数量不正确。'
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

    & $scriptPath -Yes -Theme paradox -SkipFont -ProfilePath $profilePath -TerminalSettingsPath $terminalSettingsPath

    $second = [IO.File]::ReadAllText($profilePath)
    if ($second -match "--config 'atomic'") { throw '旧主题仍然存在。' }
    if ($second -notmatch "--config 'paradox'") { throw '新主题未写入。' }
    if (($second.Split(@('# >>> setMyPwsh managed block >>>'), [StringSplitOptions]::None).Count - 1) -ne 1) {
        throw '重复运行产生了重复区块。'
    }

    $backups = @(Get-ChildItem -LiteralPath $testRoot -Filter '*.setMyPwsh-backup-*')
    if ($backups.Count -lt 2) { throw '没有按预期创建 Profile 备份。' }

    & $scriptPath -Yes -SkipFont -ProfilePath $profilePath -TerminalSettingsPath $terminalSettingsPath
    $third = [IO.File]::ReadAllText($profilePath)
    $backupsAfterNoChange = @(Get-ChildItem -LiteralPath $testRoot -Filter '*.setMyPwsh-backup-*')
    if ($third -cne $second) { throw '未指定主题重复运行后，已有主题或文件内容发生变化。' }
    if ($third -notmatch "--config 'paradox'") { throw '重复运行时没有沿用已有主题。' }
    if ($backupsAfterNoChange.Count -ne $backups.Count) { throw '无变化时不应创建新备份。' }

    Write-Host 'All tests passed.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
