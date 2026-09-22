param(
    [Parameter(Mandatory = $true)][string]$MetaEditor,
    [switch]$IncludeTests
)
$ErrorActionPreference = 'Stop'
$compilerPath = (Resolve-Path -LiteralPath $MetaEditor).Path
$projectPath = Split-Path -Parent $PSScriptRoot
$sources = @((Join-Path $projectPath 'ImpulseGrid.mq5'))
if ($IncludeTests) { $sources += Join-Path $projectPath 'tests\ImpulseGridTests.mq5' }
foreach ($source in $sources) {
    $compileLog = [System.IO.Path]::ChangeExtension($source, '.compile.log')
    if (Test-Path -LiteralPath $compileLog) { Remove-Item -LiteralPath $compileLog }
    $compileArgs = @('/compile:"' + $source + '"', '/log:"' + $compileLog + '"')
    Start-Process -FilePath $compilerPath -ArgumentList $compileArgs -WindowStyle Hidden -Wait
    if (!(Test-Path -LiteralPath $compileLog)) { throw "MetaEditor nao gerou log: $compileLog" }
    $logText = Get-Content -LiteralPath $compileLog -Raw
    Write-Output $logText
    if ($logText -notmatch '0 errors, 0 warnings') {
        throw "Compilacao precisa de revisao. Consulte $compileLog"
    }
}
