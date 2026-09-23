<#
.SYNOPSIS
    Extrae propiedades CSS específicas de todos los archivos de una carpeta y subcarpetas.

.DESCRIPTION
    Recorre recursivamente una carpeta, busca las propiedades CSS que indiques
    (ej: margin, padding, fontSize, font-size, etc.) y genera un archivo de inventario
    con todas las ocurrencias encontradas (o solo las únicas).

.PARAMETER Path
    Ruta de la carpeta a analizar.

.PARAMETER Properties
    Array de nombres de propiedades a buscar (acepta camelCase y kebab-case).
    Ejemplo: @("margin", "padding", "fontSize", "font-size", "gap")

.PARAMETER Extensions
    Extensiones de archivo a incluir. Por defecto: .css, .scss, .less, .tsx, .jsx, .ts, .js, .vue, .html, .svelte

.PARAMETER Unique
    Si se especifica, solo guarda valores únicos (sin duplicados).

.PARAMETER OutputFile
    Ruta del archivo de salida. Por defecto: "css-inventory.txt" en la carpeta actual.

.EXAMPLE
    .\Get-CssPropertiesInventory.ps1 -Path "C:\proyecto\src" -Properties @("margin", "padding", "fontSize") -Unique

.EXAMPLE
    .\Get-CssPropertiesInventory.ps1 -Path ".\src" -Properties @("marginTop", "marginBottom", "paddingHorizontal") -OutputFile "inventario-margin-padding.txt"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string[]]$Properties,

    [string[]]$Extensions = @(".css", ".scss", ".less", ".tsx", ".jsx", ".ts", ".js", ".vue", ".html", ".svelte"),

    [switch]$Unique,

    [string]$OutputFile = "css-inventory.txt"
)

# Validar que la carpeta existe
if (-not (Test-Path -Path $Path -PathType Container)) {
    Write-Error "La carpeta '$Path' no existe."
    exit 1
}

Write-Host "Analizando: $Path" -ForegroundColor Cyan
Write-Host "Propiedades a buscar: $($Properties -join ', ')" -ForegroundColor Cyan
Write-Host "Extensiones: $($Extensions -join ', ')" -ForegroundColor Cyan
Write-Host ""

# Construir el patrón regex flexible
# Soporta: marginTop: 10, margin-top: 10px, marginTop:10, "marginTop": 10, etc.
$propertyPatterns = $Properties | ForEach-Object {
    $prop = [regex]::Escape($_)
    # Acepta camelCase y kebab-case automáticamente
    $kebab = $prop -creplace '([a-z])([A-Z])', '$1-$2'
    $kebab = $kebab.ToLower()
    
    # Patrón que captura: propiedad + separador + valor
    "(?:$prop|$kebab)\s*[:=]\s*['`"]?([^'`";,\}\)\s]+)"
}

$combinedPattern = "(?i)(" + ($propertyPatterns -join "|") + ")"

$results = [System.Collections.Generic.List[string]]::new()
$filesProcessed = 0
$matchesFound = 0

# Obtener todos los archivos
$files = Get-ChildItem -Path $Path -Recurse -File | Where-Object {
    $Extensions -contains $_.Extension.ToLower()
}

Write-Host "Archivos a procesar: $($files.Count)" -ForegroundColor Yellow

foreach ($file in $files) {
    $filesProcessed++
    
    try {
        $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
        
        if ([string]::IsNullOrWhiteSpace($content)) { continue }

        # Buscar todas las coincidencias
        $matches = [regex]::Matches($content, $combinedPattern)
        
        foreach ($match in $matches) {
            # Reconstruir la línea limpia: propiedad: valor
            $fullMatch = $match.Value.Trim()
            
            # Normalizar a formato "propiedad: valor"
            if ($fullMatch -match "(?i)([a-zA-Z0-9\-]+)\s*[:=]\s*['`"]?([^'`";,\}\)\s]+)") {
                $propName = $Matches[1]
                $propValue = $Matches[2].Trim("'`"")
                
                $cleanLine = "$propName`: $propValue"
                $results.Add($cleanLine)
                $matchesFound++
            }
        }
    }
    catch {
        Write-Warning "No se pudo leer: $($file.FullName) - $($_.Exception.Message)"
    }
}

# Eliminar duplicados si se pidió
if ($Unique) {
    $results = $results | Sort-Object -Unique
    Write-Host "Valores únicos: $($results.Count)" -ForegroundColor Green
} else {
    Write-Host "Total de coincidencias: $matchesFound" -ForegroundColor Green
}

# Generar el archivo de salida
$header = "Inventario de propiedades CSS encontradas"
$outputLines = @($header) + $results

$outputLines | Out-File -FilePath $OutputFile -Encoding UTF8

Write-Host ""
Write-Host "Archivos procesados : $filesProcessed" -ForegroundColor White
Write-Host "Coincidencias       : $matchesFound" -ForegroundColor White
Write-Host "Archivo generado    : $((Resolve-Path $OutputFile).Path)" -ForegroundColor Green