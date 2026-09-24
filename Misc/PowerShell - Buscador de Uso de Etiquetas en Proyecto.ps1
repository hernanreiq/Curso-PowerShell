param(
    [Parameter(Mandatory = $true)]
    [string]$Ruta,

    [Parameter(Mandatory = $true)]
    [string]$Etiqueta
)

# Validar que la ruta exista
if (-not (Test-Path -Path $Ruta -PathType Container)) {
    Write-Error "La ruta '$Ruta' no existe o no es una carpeta."
    exit 1
}

# Limpiar el nombre de la etiqueta (quitar < > si el usuario los pone)
$Etiqueta = $Etiqueta.Trim().TrimStart('<').TrimEnd('>').Trim()

if ([string]::IsNullOrWhiteSpace($Etiqueta)) {
    Write-Error "Debes indicar un nombre de etiqueta válido."
    exit 1
}

Write-Host "Buscando la etiqueta <$Etiqueta> en archivos .js, .jsx y .tsx..." -ForegroundColor Cyan
Write-Host "Ruta: $Ruta" -ForegroundColor Cyan
Write-Host ""

# Patrón para encontrar la etiqueta (ej: <View, <View>, <View prop=..., <View/>, etc.)
$patron = "<\s*$([regex]::Escape($Etiqueta))\b"

$resultados = @()

# Buscar todos los archivos .js, .jsx y .tsx de forma recursiva
$archivos = Get-ChildItem -Path $Ruta -Recurse -Include *.js,*.jsx,*.tsx -File -ErrorAction SilentlyContinue

foreach ($archivo in $archivos) {
    try {
        $contenido = Get-Content -Path $archivo.FullName -Raw -ErrorAction Stop
        if ($null -eq $contenido) { continue }

        $matches = [regex]::Matches($contenido, $patron, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $cantidad = $matches.Count

        if ($cantidad -gt 0) {
            $resultados += [PSCustomObject]@{
                Archivo = $archivo.FullName
                Usos    = $cantidad
            }
        }
    }
    catch {
        Write-Warning "No se pudo leer el archivo: $($archivo.FullName)"
    }
}

# Generar el archivo de reporte
$fecha = Get-Date -Format "yyyyMMdd_HHmmss"
$nombreReporte = "reporte_etiqueta_${Etiqueta}_$fecha.txt"
$rutaReporte = Join-Path -Path (Get-Location) -ChildPath $nombreReporte

if ($resultados.Count -eq 0) {
    $contenidoReporte = @"
========================================
REPORTE DE BÚSQUEDA DE ETIQUETA
========================================
Etiqueta buscada : <$Etiqueta>
Ruta analizada   : $Ruta
Fecha            : $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")

No se encontró ningún uso de la etiqueta <$Etiqueta>.
"@
}
else {
    $totalUsos = ($resultados | Measure-Object -Property Usos -Sum).Sum
    $lineas = @()
    $lineas += "========================================"
    $lineas += "REPORTE DE BÚSQUEDA DE ETIQUETA"
    $lineas += "========================================"
    $lineas += "Etiqueta buscada : <$Etiqueta>"
    $lineas += "Ruta analizada   : $Ruta"
    $lineas += "Fecha            : $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")"
    $lineas += "Archivos con usos: $($resultados.Count)"
    $lineas += "Total de usos    : $totalUsos"
    $lineas += "========================================"
    $lineas += ""

    foreach ($item in $resultados | Sort-Object Usos -Descending) {
        $lineas += "Archivo : $($item.Archivo)"
        $lineas += "Usos    : $($item.Usos)"
        $lineas += "----------------------------------------"
    }

    $contenidoReporte = $lineas -join "`r`n"
}

# Guardar el reporte
$contenidoReporte | Out-File -FilePath $rutaReporte -Encoding UTF8

Write-Host "Búsqueda finalizada." -ForegroundColor Green
Write-Host "Se encontraron $($resultados.Count) archivos que usan la etiqueta <$Etiqueta>." -ForegroundColor Green
Write-Host "Reporte generado en: $rutaReporte" -ForegroundColor Yellow