param([string]$Compiler = 'c++')
$ErrorActionPreference = 'Stop'
$testBinary = Join-Path ([IO.Path]::GetTempPath()) ('fireguard-firmware-' + [Guid]::NewGuid().ToString('N') + '.exe')
$compilerArgs = @()
if ([IO.Path]::GetFileNameWithoutExtension($Compiler) -eq 'zig') {
    $compilerArgs += 'c++'
}
$compilerArgs += @('-std=c++17', '-Wall', '-Wextra', '-Werror', "-I$PSScriptRoot/stubs", "$PSScriptRoot/firmware_test.cpp", '-o', $testBinary)
try {
    & $Compiler @compilerArgs
    if ($LASTEXITCODE -ne 0) { throw 'Firmware simulation compilation failed.' }
    & $testBinary
    if ($LASTEXITCODE -ne 0) { throw 'Firmware simulation failed.' }
} finally {
    if (Test-Path -LiteralPath $testBinary) { Remove-Item -LiteralPath $testBinary -Force }
}
