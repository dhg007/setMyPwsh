$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$scriptPath = Join-Path $root 'install.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('setMyPwsh-test-' + [Guid]::NewGuid().ToString('N'))
$profilePath = Join-Path $testRoot 'Microsoft.PowerShell_profile.ps1'

try {
    [void](New-Item -ItemType Directory -Force -Path $testRoot)
    [IO.File]::WriteAllText($profilePath, "function UserConfig { 'preserve me' }`r`n")

    & $scriptPath -Yes -Theme atomic -SkipFont -ProfilePath $profilePath

    $first = [IO.File]::ReadAllText($profilePath)
    if ($first -notmatch 'function UserConfig') { throw '原有 Profile 内容丢失。' }
    if ($first -notmatch "--config 'atomic'") { throw '主题未写入。' }
    if (($first.Split(@('# >>> setMyPwsh managed block >>>'), [StringSplitOptions]::None).Count - 1) -ne 1) {
        throw '受管区块数量不正确。'
    }

    & $scriptPath -Yes -Theme paradox -SkipFont -ProfilePath $profilePath

    $second = [IO.File]::ReadAllText($profilePath)
    if ($second -match "--config 'atomic'") { throw '旧主题仍然存在。' }
    if ($second -notmatch "--config 'paradox'") { throw '新主题未写入。' }
    if (($second.Split(@('# >>> setMyPwsh managed block >>>'), [StringSplitOptions]::None).Count - 1) -ne 1) {
        throw '重复运行产生了重复区块。'
    }

    $backups = @(Get-ChildItem -LiteralPath $testRoot -Filter '*.setMyPwsh-backup-*')
    if ($backups.Count -lt 2) { throw '没有按预期创建 Profile 备份。' }

    & $scriptPath -Yes -Theme paradox -SkipFont -ProfilePath $profilePath
    $third = [IO.File]::ReadAllText($profilePath)
    $backupsAfterNoChange = @(Get-ChildItem -LiteralPath $testRoot -Filter '*.setMyPwsh-backup-*')
    if ($third -cne $second) { throw '相同配置重复运行后文件发生变化。' }
    if ($backupsAfterNoChange.Count -ne $backups.Count) { throw '无变化时不应创建新备份。' }

    Write-Host 'All tests passed.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
