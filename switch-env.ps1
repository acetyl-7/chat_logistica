param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("logichat", "cisterpor")]
    [string]$EnvName
)

$targetJson = "android/app/google-services.json"
$targetDart = "lib/firebase_options.dart"

$sourceJson = "firebase_configs/$EnvName/google-services.json"
$sourceDart = "firebase_configs/$EnvName/firebase_options.dart"

if (!(Test-Path $sourceJson)) {
    Write-Error "Configuracao de $EnvName para google-services.json nao encontrada em $sourceJson"
    exit 1
}
if (!(Test-Path $sourceDart)) {
    Write-Error "Configuracao de $EnvName para firebase_options.dart nao encontrada em $sourceDart"
    exit 1
}

Copy-Item -Path $sourceJson -Destination $targetJson -Force
Copy-Item -Path $sourceDart -Destination $targetDart -Force

Write-Host "Ambiente de Firebase alterado com sucesso para: $EnvName" -ForegroundColor Green
