param(
    [Parameter(Mandatory = $true)][string]$Proyecto,
    [string]$Region = "us-east1",
    [string]$Servicio = "gotenberg",
    [string]$Imagen = "docker.io/gotenberg/gotenberg:8",
    [string]$Usuario = "iasmtech",
    [string]$Secreto = "gotenberg-clave",
    [string]$Memoria = "2Gi",
    [string]$ArchivoCredenciales = (Join-Path $env:USERPROFILE ".gotenberg-cloudrun-credenciales.txt")
)

$ErrorActionPreference = "Continue"

function Ejecutar {
    & gcloud @args
    if ($LASTEXITCODE -ne 0) { throw "gcloud fallo: $($args -join ' ')" }
}

$numero = (& gcloud projects describe $Proyecto --format="value(projectNumber)").Trim()
if (-not $numero) { throw "No se pudo leer el numero del proyecto $Proyecto" }
$cuentaServicio = "$numero-compute@developer.gserviceaccount.com"

& gcloud secrets describe $Secreto --project $Proyecto --format="value(name)" *> $null
$existe = ($LASTEXITCODE -eq 0)

if (-not $existe) {
    $bytes = New-Object byte[] 24
    $generador = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $generador.GetBytes($bytes)
    $clave = [Convert]::ToBase64String($bytes).Replace("+", "A").Replace("/", "B").Replace("=", "")
    $distintos = ($clave.ToCharArray() | Select-Object -Unique).Count
    if ($clave.Length -lt 30 -or $distintos -lt 12) { throw "La clave generada no es valida" }

    $temporal = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($temporal, $clave)
    try {
        Ejecutar secrets create $Secreto --project $Proyecto --replication-policy automatic --data-file=$temporal
    }
    finally {
        Remove-Item $temporal -Force
    }

    [System.IO.File]::WriteAllText($ArchivoCredenciales, "usuario=$Usuario`nclave=$clave`n")
    & icacls $ArchivoCredenciales /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
    Write-Host "Credenciales guardadas en $ArchivoCredenciales"
}
else {
    Write-Host "El secreto $Secreto ya existe: se reutiliza"
}

Ejecutar secrets add-iam-policy-binding $Secreto --project $Proyecto --member "serviceAccount:$cuentaServicio" --role roles/secretmanager.secretAccessor --condition=None | Out-Null

$argumentos = "--args=gotenberg,--api-enable-basic-auth,--api-timeout=90s,--chromium-restart-after=20,--api-disable-health-check-logging=true,--log-level=info"

Ejecutar run deploy $Servicio `
    --project $Proyecto `
    --region $Region `
    --image $Imagen `
    --port 3000 `
    --cpu 1 `
    --memory $Memoria `
    --min-instances 0 `
    --max-instances 1 `
    --concurrency 2 `
    --timeout 120 `
    --allow-unauthenticated `
    --set-env-vars "GOTENBERG_API_BASIC_AUTH_USERNAME=$Usuario" `
    --set-secrets "GOTENBERG_API_BASIC_AUTH_PASSWORD=${Secreto}:latest" `
    $argumentos `
    --quiet

Write-Host "--- Resumen de limites"
& gcloud run services describe $Servicio --project $Proyecto --region $Region --format="yaml(spec.template.metadata.annotations,spec.template.spec.containerConcurrency,spec.template.spec.timeoutSeconds,spec.template.spec.containers[0].resources)"
Write-Host "--- URL"
& gcloud run services describe $Servicio --project $Proyecto --region $Region --format="value(status.url)"
