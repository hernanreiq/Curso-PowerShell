# ============================================
# Script: Buscar archivos que importan un archivo específico
# React Native / JavaScript / TypeScript
# ============================================

# 1. CONFIGURA AQUÍ LA RUTA DE TU PROYECTO
$ProjectPath = 'C:\Users\Usuario\Desktop\finanzas-personales\src'   # ← Cambia esta ruta
$OutputPath  = 'C:\Users\Usuario\Desktop\plan refactorizacion' 
# 2. Archivo de salida
$OutputFile = Join-Path $OutputPath "archivos_que_importan.txt"

# ============================================
# No toques nada más a partir de aquí
# ============================================

if (-not (Test-Path $ProjectPath)) {
    Write-Host "ERROR: La ruta del proyecto no existe: $ProjectPath" -ForegroundColor Red
    exit
}

# Pedir el nombre del archivo a buscar
$TargetFile = Read-Host "Escribe el nombre del archivo que quieres buscar (ej: style.jsx)"

if ([string]::IsNullOrWhiteSpace($TargetFile)) {
    Write-Host "No escribiste ningún archivo. Saliendo..." -ForegroundColor Yellow
    exit
}

# Extraemos el nombre sin extensión y la extensión
$TargetName = [System.IO.Path]::GetFileNameWithoutExtension($TargetFile)
$TargetExt = [System.IO.Path]::GetExtension($TargetFile).TrimStart('.')

Write-Host "`nBuscando archivos que importan: $TargetFile ..." -ForegroundColor Cyan
Write-Host "Proyecto: $ProjectPath`n"

# Extensiones que vamos a revisar
$Extensions = @("*.js", "*.jsx", "*.ts", "*.tsx")

# Carpetas que queremos ignorar
$ExcludeDirs = @("node_modules", ".git", "android", "ios", "build", "dist", ".expo", "coverage")

# Buscamos todos los archivos relevantes
$AllFiles = Get-ChildItem -Path $ProjectPath -Include $Extensions -Recurse -File |
            Where-Object {
                $relativePath = $_.FullName.Substring($ProjectPath.Length)
                $shouldExclude = $false
                foreach ($dir in $ExcludeDirs) {
                    if ($relativePath -like "*\$dir\*" -or $relativePath -like "*/$dir/*") {
                        $shouldExclude = $true
                        break
                    }
                }
                -not $shouldExclude
            }

$Results = @()

foreach ($file in $AllFiles) {
    $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }

    # Buscamos patrones comunes de import/require
    # Soporta:
    #   import ... from './style'
    #   import ... from './style.jsx'
    #   import ... from "../styles/style.jsx"
    #   require('./style')
    #   require("./style.jsx")
    $patterns = @(
        "from\s+['\`"].*$([regex]::Escape($TargetName))(\.$TargetExt)?['\`"]",
        "require\s*\(\s*['\`"].*$([regex]::Escape($TargetName))(\.$TargetExt)?['\`"]\s*\)"
    )

    $found = $false
    foreach ($pattern in $patterns) {
        if ($content -match $pattern) {
            $found = $true
            break
        }
    }

    if ($found) {
        $relative = $file.FullName.Substring($ProjectPath.Length).TrimStart('\', '/')
        $Results += $relative
    }
}

# Guardamos el resultado
if ($Results.Count -eq 0) {
    $message = "No se ha encontrado ningun archivo que importe '$TargetFile'."
    $message | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host $message -ForegroundColor Yellow
} else {
    $header = @"
Archivos que importan: $TargetFile
Proyecto: $ProjectPath
Fecha: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Total encontrados: $($Results.Count)

"@
    $header + (($Results | Sort-Object) -join "`n") | Out-File -FilePath $OutputFile -Encoding UTF8

    Write-Host "Se encontraron $($Results.Count) archivo(s) que importan '$TargetFile':" -ForegroundColor Green
    $Results | Sort-Object | ForEach-Object { Write-Host "  → $_" }
    Write-Host "`nResultado guardado en: $OutputFile" -ForegroundColor Cyan
}