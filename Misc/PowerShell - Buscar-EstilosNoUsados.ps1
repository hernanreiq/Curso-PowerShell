<#
.SYNOPSIS
    Detecta estilos usados y no usados en TODOS los StyleSheet.create del proyecto (React Native).

.DESCRIPTION
    - Recorre .js .jsx .ts .tsx (ignora node_modules, .git, dist, build, android, ios).
    - Encuentra cada StyleSheet.create({...}) de cada archivo (no solo el primero).
    - Detecta el nombre de la variable (const styles = ...) y como la importa cada archivo
      (import styles from, import { styles as s }, import * as S, require).
    - Cuenta como uso: styles.x, styles?.x, styles['x'], const { x } = styles.
    - Ignora comentarios. Reporta accesos dinamicos (styles[variable]) aparte.

.PARAMETER ProjectPath
    Carpeta raiz donde buscar.

.PARAMETER OutputPath
    Carpeta donde se guardan los reportes .txt.
#>

param(
    [string]$ProjectPath = 'C:\Users\Usuario\Desktop\finanzas-personales\src',
    [string]$OutputPath  = 'C:\Users\Usuario\Desktop\plan refactorizacion'
)

$ErrorActionPreference = 'Stop'
$excludeRegex = '[\\/](node_modules|\.git|dist|build|\.expo|android|ios|coverage)[\\/]'

# ---------------------------------------------------------------------------
# Comentarios -> espacios. Si $Mask, el contenido de strings -> 'x' (misma longitud).
# ---------------------------------------------------------------------------
function Get-Masked {
    param([string]$T, [bool]$Mask)
    $n = $T.Length
    $sb = New-Object System.Text.StringBuilder $n
    $i = 0
    while ($i -lt $n) {
        $c = $T[$i]
        $nx = if ($i + 1 -lt $n) { $T[$i + 1] } else { [char]0 }

        if ($c -eq '/' -and $nx -eq '/') {
            while ($i -lt $n -and $T[$i] -ne "`n") {
                [void]$sb.Append($(if ($T[$i] -eq "`r") { "`r" } else { ' ' })); $i++
            }
            continue
        }
        if ($c -eq '/' -and $nx -eq '*') {
            [void]$sb.Append('  '); $i += 2
            while ($i -lt $n -and -not ($T[$i] -eq '*' -and $i + 1 -lt $n -and $T[$i + 1] -eq '/')) {
                $ch = $T[$i]
                [void]$sb.Append($(if ($ch -eq "`n" -or $ch -eq "`r") { $ch } else { ' ' })); $i++
            }
            if ($i -lt $n) { [void]$sb.Append('  '); $i += 2 }
            continue
        }
        if ($c -eq "'" -or $c -eq '"' -or $c -eq '`') {
            $q = $c
            [void]$sb.Append($q); $i++
            while ($i -lt $n -and $T[$i] -ne $q) {
                if ($T[$i] -eq '\' -and $i + 1 -lt $n) {
                    if ($Mask) { [void]$sb.Append('xx') } else { [void]$sb.Append($T[$i]).Append($T[$i + 1]) }
                    $i += 2; continue
                }
                if ($T[$i] -eq "`n" -and $q -ne '`') { break }
                if ($Mask) { [void]$sb.Append('x') } else { [void]$sb.Append($T[$i]) }
                $i++
            }
            if ($i -lt $n -and $T[$i] -eq $q) { [void]$sb.Append($q); $i++ }
            continue
        }
        [void]$sb.Append($c); $i++
    }
    return $sb.ToString()
}

# ---------------------------------------------------------------------------
# Claves de primer nivel del objeto de estilos.
# ---------------------------------------------------------------------------
function Get-StyleKeys {
    param([string]$Orig, [string]$Mask)
    $keys = New-Object System.Collections.Generic.List[string]
    $spreads = New-Object System.Collections.Generic.List[string]
    $len = $Mask.Length
    $depth = 0; $expect = $true; $i = 0
    while ($i -lt $len) {
        $ch = $Mask[$i]
        if ($depth -eq 0 -and $expect) {
            if ([char]::IsWhiteSpace($ch)) { $i++; continue }
            $expect = $false
            $word = $null
            if ([char]::IsLetterOrDigit($ch) -or $ch -eq '_' -or $ch -eq '$') {
                $s = $i
                while ($i -lt $len -and ([char]::IsLetterOrDigit($Mask[$i]) -or $Mask[$i] -eq '_' -or $Mask[$i] -eq '$')) { $i++ }
                $word = $Orig.Substring($s, $i - $s)
            }
            elseif ($ch -eq '"' -or $ch -eq "'") {
                $j = $i + 1
                while ($j -lt $len -and $Mask[$j] -ne $ch) { $j++ }
                $word = $Orig.Substring($i + 1, $j - $i - 1)
                $i = $j + 1
            }
            elseif ($ch -eq '.' -and $i + 2 -lt $len -and $Mask[$i + 1] -eq '.' -and $Mask[$i + 2] -eq '.') {
                $i += 3
                while ($i -lt $len -and [char]::IsWhiteSpace($Mask[$i])) { $i++ }
                $s = $i
                while ($i -lt $len -and ([char]::IsLetterOrDigit($Mask[$i]) -or $Mask[$i] -eq '_' -or $Mask[$i] -eq '$')) { $i++ }
                if ($i -gt $s -and ($i -ge $len -or ($Mask[$i] -ne '.' -and $Mask[$i] -ne '('))) { $spreads.Add($Orig.Substring($s, $i - $s)) }
                continue
            }
            if ($word) {
                $j = $i
                while ($j -lt $len -and [char]::IsWhiteSpace($Mask[$j])) { $j++ }
                if ($j -lt $len -and $Mask[$j] -eq ':') { $keys.Add($word) }
            }
            continue
        }
        if ($ch -eq '{' -or $ch -eq '[' -or $ch -eq '(') { $depth++ }
        elseif ($ch -eq '}' -or $ch -eq ']' -or $ch -eq ')') { $depth-- }
        elseif ($ch -eq ',' -and $depth -eq 0) { $expect = $true }
        $i++
    }
    return [PSCustomObject]@{ Keys = @($keys | Select-Object -Unique); Spreads = @($spreads | Select-Object -Unique) }
}

# ---------------------------------------------------------------------------
# Todos los StyleSheet.create de un archivo.
# ---------------------------------------------------------------------------
function Get-Sheets {
    param($F, $Warnings)
    $found = New-Object System.Collections.Generic.List[object]
    $t = $F.Clean
    $m = $F.Masked
    $pos = 0
    while (($idx = $m.IndexOf('StyleSheet.create', $pos)) -ge 0) {
        $pos = $idx + 17

        $s0 = [Math]::Max(0, $idx - 250)
        $pre = $t.Substring($s0, $idx - $s0)
        $varName = $null
        $vm = [regex]::Match($pre, '(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*(?::[^=;{}]{1,150}?)?\s*=\s*(?:\(\s*)?$')
        if ($vm.Success) { $varName = $vm.Groups[1].Value }
        $anonDefault = [regex]::IsMatch($pre, 'export\s+default\s*$')
        $exportedInline = [regex]::IsMatch($pre, 'export\s+(?:const|let|var)\s+[\w$]+\s*(?::[^=;]{1,150}?)?\s*=\s*$')

        $p = $m.IndexOf('(', $idx)
        if ($p -lt 0) { continue }
        $b = $p + 1
        while ($b -lt $m.Length -and [char]::IsWhiteSpace($m[$b])) { $b++ }
        if ($b -ge $m.Length -or $m[$b] -ne '{') {
            $Warnings.Add("No analizado (argumento no es objeto literal): $($F.Path)")
            continue
        }

        $depth = 0; $end = -1
        for ($i = $b; $i -lt $m.Length; $i++) {
            $ch = $m[$i]
            if ($ch -eq '{') { $depth++ }
            elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { $end = $i; break } }
        }
        if ($end -eq -1) { $Warnings.Add("Sin cierre de objeto: $($F.Path)"); continue }

        if (-not $varName -and -not $anonDefault) {
            $Warnings.Add("No analizado (StyleSheet.create sin variable, ej. dentro de funcion): $($F.Path)")
            continue
        }

        $len = $end - $b - 1
        $res = Get-StyleKeys -Orig $t.Substring($b + 1, $len) -Mask $m.Substring($b + 1, $len)

        $found.Add([PSCustomObject]@{
                File     = $F
                Var      = $varName
                Names    = $res.Keys
                Spreads  = $res.Spreads
                Exported = ($exportedInline -or $anonDefault)
                IsDefault = $false
            })
    }

    foreach ($sh in $found) {
        $isDef = $false
        if (-not $sh.Var) { $isDef = $true }
        elseif ($found.Count -eq 1) { $isDef = $true }
        elseif ([regex]::IsMatch($t, 'export\s+default\s+' + [regex]::Escape($sh.Var) + '(?![\w$])')) { $isDef = $true }
        $sh.IsDefault = $isDef
        if ($sh.Var -and [regex]::IsMatch($t, 'export\s*\{[^}]*\b' + [regex]::Escape($sh.Var) + '\b')) { $sh.Exported = $true }
        if ($sh.Var -and [regex]::IsMatch($t, 'export\s+default\s+' + [regex]::Escape($sh.Var) + '(?![\w$])')) { $sh.Exported = $true }
    }
    return $found
}

# ---------------------------------------------------------------------------
# imports / require de un archivo
# ---------------------------------------------------------------------------
function Get-Imports {
    param($F)
    $list = New-Object System.Collections.Generic.List[object]
    $t = $F.Clean

    function New-Imp($spec, $def, $named, $ns) {
        $base = $null; $last = $null
        if ($spec.StartsWith('.')) {
            try { $base = [IO.Path]::GetFullPath((Join-Path $F.Dir $spec)).TrimEnd('\', '/') } catch { }
        }
        else {
            $last = ($spec.Split('/')[-1]) -replace '\.(js|jsx|ts|tsx)$', ''
        }
        [PSCustomObject]@{ Spec = $spec; Base = $base; Last = $last; Default = $def; Named = $named; Namespace = $ns }
    }

    foreach ($mt in [regex]::Matches($t, 'import\s+((?:[\w$\s,{}*])+?)\s+from\s+[''"]([^''"]+)[''"]')) {
        $clause = $mt.Groups[1].Value.Trim()
        if ($clause -match '^type\s') { continue }
        $def = $null; $ns = $null
        $named = New-Object System.Collections.Generic.List[object]

        if ($clause -match '\*\s*as\s+([\w$]+)') { $ns = $Matches[1] }
        if ($clause -match '\{([^}]*)\}') {
            foreach ($part in $Matches[1].Split(',')) {
                $q = $part.Trim()
                if (-not $q) { continue }
                if ($q -match '^(?:type\s+)?([\w$]+)\s+as\s+([\w$]+)$') {
                    $named.Add(@{ Imported = $Matches[1]; Local = $Matches[2] })
                }
                elseif ($q -match '^(?:type\s+)?([\w$]+)$') {
                    $named.Add(@{ Imported = $Matches[1]; Local = $Matches[1] })
                }
            }
        }
        $head = ($clause -replace '\{[^}]*\}', '' -replace '\*\s*as\s+[\w$]+', '').Trim().TrimEnd(',').Trim()
        if ($head -match '^[\w$]+$') { $def = $head }
        $list.Add((New-Imp $mt.Groups[2].Value $def $named $ns))
    }

    foreach ($mt in [regex]::Matches($t, '(?:const|let|var)\s+(\{[^}]*\}|[\w$]+)\s*=\s*require\(\s*[''"]([^''"]+)[''"]\s*\)')) {
        $lhs = $mt.Groups[1].Value.Trim()
        $named = New-Object System.Collections.Generic.List[object]
        $def = $null; $ns = $null
        if ($lhs.StartsWith('{')) {
            foreach ($part in $lhs.Trim('{', '}').Split(',')) {
                $q = $part.Trim()
                if (-not $q) { continue }
                if ($q -match '^([\w$]+)\s*:\s*([\w$]+)') { $named.Add(@{ Imported = $Matches[1]; Local = $Matches[2] }) }
                elseif ($q -match '^([\w$]+)') { $named.Add(@{ Imported = $Matches[1]; Local = $Matches[1] }) }
            }
        }
        else { $def = $lhs; $ns = $lhs }
        $list.Add((New-Imp $mt.Groups[2].Value $def $named $ns))
    }
    return $list
}

function Get-Target {
    param($File)
    $baseName = [IO.Path]::GetFileNameWithoutExtension($File.Path)
    [PSCustomObject]@{
        Path     = $File.Path
        NoExt    = [IO.Path]::ChangeExtension($File.Path, $null).TrimEnd('.')
        Dir      = $File.Dir
        BaseName = $baseName
        IsIndex  = ($baseName -ieq 'index')
        DirName  = Split-Path -Leaf $File.Dir
    }
}

function Test-Resolves {
    param($Imp, $Target)
    if ($Imp.Base) {
        return ($Imp.Base -ieq $Target.NoExt) -or ($Imp.Base -ieq $Target.Path) -or ($Target.IsIndex -and $Imp.Base -ieq $Target.Dir)
    }
    return ($Imp.Last -ieq $Target.BaseName) -or ($Target.IsIndex -and $Imp.Last -ieq $Target.DirName)
}

# ===========================================================================
# 1. Cargar archivos
# ===========================================================================
$root = (Resolve-Path $ProjectPath).Path
Write-Host "Leyendo proyecto: $root"

$files = New-Object System.Collections.Generic.List[object]
$candidates = Get-ChildItem -Path $root -Recurse -Include *.js, *.jsx, *.ts, *.tsx -File |
    Where-Object { $_.FullName -notmatch $excludeRegex }

foreach ($fi in $candidates) {
    $raw = Get-Content -Raw -Path $fi.FullName -Encoding UTF8
    if ([string]::IsNullOrEmpty($raw)) { continue }
    $clean = Get-Masked -T $raw -Mask $false
    $masked = $null
    if ($clean.Contains('StyleSheet.create')) { $masked = Get-Masked -T $clean -Mask $true }
    $f = [PSCustomObject]@{
        Path    = $fi.FullName
        Name    = $fi.Name
        Dir     = $fi.DirectoryName
        Folder  = $fi.Directory.Name
        Clean   = $clean
        Masked  = $masked
        Imports = $null
    }
    $f.Imports = Get-Imports -F $f
    $files.Add($f)
}
Write-Host "Archivos: $($files.Count)"

# ===========================================================================
# 2. Encontrar TODOS los StyleSheet.create
# ===========================================================================
$warnings = New-Object System.Collections.Generic.List[string]
$sheets = New-Object System.Collections.Generic.List[object]
foreach ($f in $files) {
    if (-not $f.Masked) { continue }
    foreach ($sh in (Get-Sheets -F $f -Warnings $warnings)) { $sheets.Add($sh) }
}
$totalStyles = ($sheets | ForEach-Object { $_.Names.Count } | Measure-Object -Sum).Sum
Write-Host "StyleSheet.create: $($sheets.Count) | Estilos: $totalStyles"

# ===========================================================================
# 3. Buscar uso de cada estilo por hoja
# ===========================================================================
foreach ($sh in $sheets) {
    $target = Get-Target -File $sh.File

    # alias por archivo
    $aliases = @{}
    if ($sh.Var) { $aliases[$sh.File.Path] = New-Object System.Collections.Generic.List[string]; $aliases[$sh.File.Path].Add($sh.Var) }

    $externalImporters = 0
    foreach ($f in $files) {
        if ($f.Path -eq $sh.File.Path) { continue }
        foreach ($imp in $f.Imports) {
            if (-not (Test-Resolves -Imp $imp -Target $target)) { continue }
            $local = New-Object System.Collections.Generic.List[string]
            if ($imp.Default -and $sh.IsDefault) { $local.Add($imp.Default) }
            foreach ($n in $imp.Named) {
                if (($sh.Var -and $n.Imported -eq $sh.Var) -or ($n.Imported -eq 'default' -and $sh.IsDefault)) { $local.Add($n.Local) }
            }
            if ($imp.Namespace) {
                if ($sh.Var) { $local.Add("$($imp.Namespace).$($sh.Var)") }
                if ($sh.IsDefault) { $local.Add("$($imp.Namespace).default") }
            }
            if ($local.Count -gt 0) {
                if (-not $aliases.ContainsKey($f.Path)) { $aliases[$f.Path] = New-Object System.Collections.Generic.List[string] }
                foreach ($a in $local) { if (-not $aliases[$f.Path].Contains($a)) { $aliases[$f.Path].Add($a) } }
                $externalImporters++
            }
        }
    }


    $usedFiles = @{}     # nombre -> hashtable(path -> objeto)
    $dynamic = New-Object System.Collections.Generic.List[string]
    $fileByPath = @{}
    foreach ($f in $files) { $fileByPath[$f.Path] = $f }

    foreach ($path in $aliases.Keys) {
        $f = $fileByPath[$path]
        foreach ($A in $aliases[$path]) {
            $pre = '(?<![\w$])(?:(?<!\.)|(?<=\.\.\.))' + [regex]::Escape($A)
            $hits = New-Object System.Collections.Generic.List[string]

            foreach ($mt in [regex]::Matches($f.Clean, $pre + '\s*\??\.\s*([A-Za-z_$][\w$]*)')) { $hits.Add($mt.Groups[1].Value) }
            foreach ($mt in [regex]::Matches($f.Clean, $pre + '\s*\[\s*[''"]([^''"]+)[''"]\s*\]')) { $hits.Add($mt.Groups[1].Value) }
            foreach ($mt in [regex]::Matches($f.Clean, '\{([^{}]*)\}\s*=\s*' + [regex]::Escape($A) + '(?![\w$.\[])')) {
                foreach ($part in $mt.Groups[1].Value.Split(',')) {
                    $q = $part.Trim()
                    if (-not $q -or $q.StartsWith('...')) { continue }
                    $q = ($q -split '=')[0]
                    $q = ($q -split ':')[0].Trim()
                    if ($q) { $hits.Add($q) }
                }
            }
            if ([regex]::IsMatch($f.Clean, $pre + '\s*\[\s*(?![''"\s])')) {
                if (-not $dynamic.Contains($f.Path)) { $dynamic.Add($f.Path) }
            }

            foreach ($h in $hits) {
                if (-not $usedFiles.ContainsKey($h)) { $usedFiles[$h] = @{} }
                $usedFiles[$h][$f.Path] = [PSCustomObject]@{ Folder = $f.Folder; File = $f.Name }
            }
        }
    }

    $sh | Add-Member -NotePropertyName UsedFiles -NotePropertyValue $usedFiles
    $sh | Add-Member -NotePropertyName Dynamic -NotePropertyValue $dynamic
    $sh | Add-Member -NotePropertyName ExternalImporters -NotePropertyValue $externalImporters
}

# ---------------------------------------------------------------------------
# Spreads: ...Commons dentro de otra hoja. Lo que se usa via la hoja compuesta
# cuenta como uso en la hoja origen.
# ---------------------------------------------------------------------------
foreach ($a in $sheets) {
    $targets = New-Object System.Collections.Generic.List[object]
    foreach ($x in $a.Spreads) {
        foreach ($b in $sheets) {
            if ($b -eq $a) { continue }
            if ($b.File.Path -eq $a.File.Path -and $b.Var -eq $x) { $targets.Add($b) }
        }
        foreach ($imp in $a.File.Imports) {
            $imported = $null
            foreach ($n in $imp.Named) { if ($n.Local -eq $x) { $imported = $n.Imported } }
            if (-not $imported -and $imp.Default -ne $x) { continue }
            foreach ($b in $sheets) {
                if ($b -eq $a -or $b.File.Path -eq $a.File.Path) { continue }
                if (-not (Test-Resolves -Imp $imp -Target (Get-Target -File $b.File))) { continue }
                if (($imported -and $b.Var -eq $imported) -or (-not $imported -and $b.IsDefault)) { $targets.Add($b) }
            }
        }
    }
    $a | Add-Member -NotePropertyName SpreadTargets -NotePropertyValue $targets
    $a | Add-Member -NotePropertyName Overridden -NotePropertyValue @{}
}

$changed = $true; $guard = 0
while ($changed -and $guard -lt 20) {
    $changed = $false; $guard++
    foreach ($a in $sheets) {
        foreach ($b in $a.SpreadTargets) {
            foreach ($d in $a.Dynamic) { if (-not $b.Dynamic.Contains($d)) { $b.Dynamic.Add($d); $changed = $true } }
            foreach ($n in $b.Names) {
                if ($a.Names -contains $n) {
                    if ($a.UsedFiles.ContainsKey($n)) {
                        if (-not $b.Overridden.ContainsKey($n)) { $b.Overridden[$n] = New-Object System.Collections.Generic.List[string] }
                        if (-not $b.Overridden[$n].Contains($a.Var)) { $b.Overridden[$n].Add($a.Var) }
                    }
                    continue
                }
                if (-not $a.UsedFiles.ContainsKey($n)) { continue }
                if (-not $b.UsedFiles.ContainsKey($n)) { $b.UsedFiles[$n] = @{} }
                foreach ($k in $a.UsedFiles[$n].Keys) {
                    if (-not $b.UsedFiles[$n].ContainsKey($k)) { $b.UsedFiles[$n][$k] = $a.UsedFiles[$n][$k]; $changed = $true }
                }
            }
        }
    }
}

$spreadUsed = @{}
foreach ($a in $sheets) { foreach ($b in $a.SpreadTargets) { $spreadUsed[$b.File.Path + '|' + $b.Var] = $true } }

foreach ($sh in $sheets) {
    $usage = @{}
    foreach ($name in $sh.Names) {
        $usage[$name] = if ($sh.UsedFiles.ContainsKey($name)) { @($sh.UsedFiles[$name].Values) } else { @() }
    }
    $sh | Add-Member -NotePropertyName Usage -NotePropertyValue $usage
    if ($sh.Exported -and $sh.ExternalImporters -eq 0 -and -not $spreadUsed.ContainsKey($sh.File.Path + '|' + $sh.Var)) {
        $warnings.Add("Hoja exportada sin importadores detectados (barrel/alias raro?): $($sh.Var) en $($sh.File.Path)")
    }
}

# ===========================================================================
# 4. Reportes
# ===========================================================================
if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath | Out-Null }
$noUsadosPath = Join-Path $OutputPath 'estilos_no_usados.txt'
$usadosPath   = Join-Path $OutputPath 'estilos_usados.txt'

function Get-Rel([string]$p) { $p.Substring($root.Length).TrimStart('\', '/') }

$sbNo = New-Object System.Text.StringBuilder
$sbSi = New-Object System.Text.StringBuilder
$totalNo = 0

foreach ($sh in $sheets) {
    $head = "=== $(if ($sh.Var) { $sh.Var } else { '(default)' })  [$(Get-Rel $sh.File.Path)] ==="
    $no = @($sh.Names | Where-Object { $sh.Usage[$_].Count -eq 0 })
    $totalNo += $no.Count

    if ($no.Count -gt 0) {
        [void]$sbNo.AppendLine($head)
        foreach ($name in ($no | Where-Object { -not $sh.Overridden.ContainsKey($_) })) { [void]$sbNo.AppendLine("style $name") }
        $ovNames = @($no | Where-Object { $sh.Overridden.ContainsKey($_) })
        if ($ovNames.Count -gt 0) {
            [void]$sbNo.AppendLine('-- Sobreescritos: la hoja hija define el mismo nombre y ese si se usa. La version de esta hoja no se aplica.')
            foreach ($name in $ovNames) { [void]$sbNo.AppendLine("style $name  (sobreescrito en: $($sh.Overridden[$name] -join ', '))") }
        }
        if ($sh.Dynamic.Count -gt 0) {
            [void]$sbNo.AppendLine("(!) Acceso dinamico styles[variable] en: " + (($sh.Dynamic | ForEach-Object { Get-Rel $_ }) -join ', '))
            [void]$sbNo.AppendLine("(!) Revisar a mano antes de borrar.")
        }
        [void]$sbNo.AppendLine('')
    }

    [void]$sbSi.AppendLine($head)
    foreach ($name in $sh.Names) {
        if ($sh.Usage[$name].Count -eq 0) { continue }
        [void]$sbSi.AppendLine("style $name")
        foreach ($grupo in ($sh.Usage[$name] | Group-Object Folder)) {
            [void]$sbSi.AppendLine("Carpeta: $($grupo.Name)")
            [void]$sbSi.AppendLine('Archivos:')
            foreach ($fn in ($grupo.Group.File | Select-Object -Unique)) { [void]$sbSi.AppendLine($fn) }
        }
        [void]$sbSi.AppendLine('')
    }
}

if ($warnings.Count -gt 0) {
    [void]$sbNo.AppendLine('=== ADVERTENCIAS ===')
    foreach ($w in $warnings) { [void]$sbNo.AppendLine($w) }
}

Set-Content -Path $noUsadosPath -Value $sbNo.ToString() -Encoding UTF8
Set-Content -Path $usadosPath   -Value $sbSi.ToString() -Encoding UTF8

Write-Host 'Listo.'
Write-Host "Hojas: $($sheets.Count) | Estilos: $totalStyles | No usados: $totalNo | Advertencias: $($warnings.Count)"
Write-Host "No usados: $noUsadosPath"
Write-Host "Usados:    $usadosPath"