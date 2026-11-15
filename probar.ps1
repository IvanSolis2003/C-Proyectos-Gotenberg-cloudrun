param(
    [Parameter(Mandatory = $true)][string]$Proyecto,
    [string]$Region = "us-east1",
    [string]$Servicio = "gotenberg",
    [string]$ArchivoCredenciales = (Join-Path $env:USERPROFILE ".gotenberg-cloudrun-credenciales.txt")
)

$credenciales = @{}
Get-Content $ArchivoCredenciales | ForEach-Object {
    $partes = $_ -split "=", 2
    if ($partes.Count -eq 2) { $credenciales[$partes[0]] = $partes[1] }
}
$autenticacion = "$($credenciales['usuario']):$($credenciales['clave'])"

$url = (& gcloud run services describe $Servicio --project $Proyecto --region $Region --format="value(status.url)").Trim()
if (-not $url) { throw "No se encontro el servicio $Servicio" }

function Medir {
    param([scriptblock]$Accion)
    $reloj = [System.Diagnostics.Stopwatch]::StartNew()
    $resultado = & $Accion
    $reloj.Stop()
    return @{ Resultado = $resultado; Segundos = [math]::Round($reloj.Elapsed.TotalSeconds, 1) }
}

$carpeta = Join-Path ([System.IO.Path]::GetTempPath()) "gotenberg-prueba"
New-Item -ItemType Directory -Force -Path $carpeta | Out-Null
$html = Join-Path $carpeta "index.html"
[System.IO.File]::WriteAllText($html, '<!doctype html><html><body style="margin:0;width:1080px;height:1350px;background:#0F172A;color:#fff;font:700 80px sans-serif;display:flex;align-items:center;justify-content:center">Prueba de render</body></html>')

Write-Host "1. Render sin credenciales debe dar 401"
$r = Medir { & curl.exe -s -X POST "$url/forms/chromium/screenshot/html" -F "files=@$html;filename=index.html" -F "format=jpeg" -m 120 -o NUL -w "%{http_code}" }
Write-Host "   codigo $($r.Resultado) en $($r.Segundos) s"

Write-Host "2. Salud con credenciales debe dar 200 (incluye arranque en frio)"
$r = Medir { & curl.exe -s -u $autenticacion -o NUL -w "%{http_code}" -m 120 "$url/health" }
Write-Host "   codigo $($r.Resultado) en $($r.Segundos) s"

Write-Host "3. Render de un slide, tres veces"
foreach ($i in 1..3) {
    $salida = Join-Path $carpeta "prueba$i.jpg"
    $r = Medir {
        & curl.exe -s -u $autenticacion -X POST "$url/forms/chromium/screenshot/html" `
            -F "files=@$html;filename=index.html" -F "width=1080" -F "height=1350" `
            -F "format=jpeg" -F "quality=90" -F "clip=true" -m 120 -o $salida -w "%{http_code}"
    }
    $tamano = 0
    if (Test-Path $salida) { $tamano = (Get-Item $salida).Length }
    Write-Host "   intento ${i}: codigo $($r.Resultado), $($r.Segundos) s, $tamano bytes"
}

$plantilla = '<!doctype html><html><body><img src="{0}" onerror="throw new Error(&quot;foto no cargo&quot;)"></body></html>'
$casos = @(
    @{ Nombre = "4. Foto inexistente (404) debe dar 409"; Origen = "https://example.com/no-existe.jpg" },
    @{ Nombre = "5. Dominio inexistente debe dar 409"; Origen = "https://dominio-que-no-existe-iasmtech-xyz.invalid/a.jpg" },
    @{ Nombre = "6. Foto valida debe dar 200"; Origen = "https://www.google.com/favicon.ico" }
)
foreach ($caso in $casos) {
    Write-Host $caso.Nombre
    $archivo = Join-Path $carpeta "foto.html"
    [System.IO.File]::WriteAllText($archivo, ($plantilla -f $caso.Origen))
    $r = Medir {
        & curl.exe -s -u $autenticacion -X POST "$url/forms/chromium/screenshot/html" `
            -F "files=@$archivo;filename=index.html" -F "format=jpeg" -F "failOnConsoleExceptions=true" `
            -F "waitForExpression=Array.from(document.images).every(i => i.complete)" -m 120 -o NUL -w "%{http_code}"
    }
    Write-Host "   codigo $($r.Resultado) en $($r.Segundos) s"
}

Remove-Item $carpeta -Recurse -Force
