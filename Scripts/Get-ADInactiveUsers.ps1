<#
.SYNOPSIS
    Detecta usuarios inactivos en Active Directory.

.DESCRIPTION
    Busca cuentas habilitadas que requieren revision por inactividad.

    El script diferencia dos situaciones:

    1. Usuarios que iniciaron sesion anteriormente, pero cuyo ultimo
       inicio de sesion supera el limite de inactividad configurado.

    2. Usuarios que nunca han iniciado sesion y cuya cuenta fue creada
       hace mas dias que el limite configurado para el primer inicio.

    El script:
    - Valida el modulo ActiveDirectory.
    - Detecta automaticamente el dominio.
    - Localiza la OU de usuarios.
    - Consulta solamente cuentas habilitadas.
    - Identifica cuentas que requieren revision.
    - Muestra Department y OU como datos independientes.
    - Genera un informe CSV.
    - No modifica ninguna cuenta de Active Directory.

.NOTES
    Proyecto de laboratorio - TechSolutions Global
    PowerShell + Active Directory
#>


# ============================================================
# 1. PARAMETROS
# ============================================================

param(
    [int]$DiasInactividad = 90,

    [int]$DiasSinPrimerInicio = 30,

    [string]$UsersOU = "Usuarios",

    [string]$ReportPath = (Join-Path $PSScriptRoot "Reportes")
)


# ============================================================
# 2. VALIDAR DEPENDENCIAS
# ============================================================

try {

    Import-Module ActiveDirectory -ErrorAction Stop

    Write-Host "Modulo ActiveDirectory cargado correctamente."
}
catch {

    Write-Error "No se pudo cargar el modulo ActiveDirectory."
    return
}


# ============================================================
# 3. OBTENER INFORMACION DEL DOMINIO
# ============================================================

try {

    $Dominio = Get-ADDomain -ErrorAction Stop

    $DomainDN = $Dominio.DistinguishedName
    $DomainDNS = $Dominio.DNSRoot

    Write-Host "Dominio detectado: $DomainDNS"
}
catch {

    Write-Error "No se pudo obtener la informacion del dominio."
    return
}


# ============================================================
# 4. VALIDAR OU DE USUARIOS
# ============================================================

$BaseOU = "OU=$UsersOU,$DomainDN"


try {

    Get-ADOrganizationalUnit `
        -Identity $BaseOU `
        -ErrorAction Stop |
        Out-Null
}
catch {

    Write-Error "La OU de usuarios no existe: $BaseOU"
    return
}


# ============================================================
# 5. PREPARAR DIRECTORIO DE INFORMES
# ============================================================

if (-not (Test-Path $ReportPath)) {

    try {

        New-Item `
            -ItemType Directory `
            -Path $ReportPath `
            -Force `
            -ErrorAction Stop |
            Out-Null
    }
    catch {

        Write-Error "No se pudo crear el directorio de informes: $ReportPath"
        return
    }
}


# ============================================================
# 6. CONSULTAR USUARIOS
# ============================================================

try {

    $Usuarios = @(
        Get-ADUser `
            -SearchBase $BaseOU `
            -Filter 'Enabled -eq $true' `
            -Properties `
                LastLogonDate,
                Department,
                Enabled,
                whenCreated `
            -ErrorAction Stop
    )
}
catch {

    Write-Error "No se pudieron consultar los usuarios de Active Directory."
    return
}


# ============================================================
# 7. CALCULAR LIMITES DE INACTIVIDAD
# ============================================================

$FechaActual = Get-Date


$FechaLimiteInactividad = $FechaActual.AddDays(
    -$DiasInactividad
)


$FechaLimiteSinPrimerInicio = $FechaActual.AddDays(
    -$DiasSinPrimerInicio
)


# ============================================================
# 8. DETECTAR USUARIOS PARA REVISION
# ============================================================

$Resultados = @()


foreach ($Usuario in $Usuarios) {

    # --------------------------------------------------------
    # LIMPIAR VARIABLES DE LA ITERACION
    # --------------------------------------------------------

    $Estado = ""
    $OUActual = ""


    # --------------------------------------------------------
    # OBTENER OU ACTUAL
    # --------------------------------------------------------

    # DistinguishedName:
    #
    # Ejemplo: CN=Usuario Demo,OU=IT,OU=Usuarios,DC=example,DC=local
    #
    # Obtenemos la primera OU:
    #
    # IT

    if ($Usuario.DistinguishedName -match ',OU=([^,]+)') {

        $OUActual = $Matches[1]
    }


    # --------------------------------------------------------
    # CASO 1: NUNCA HA INICIADO SESION
    # --------------------------------------------------------

    if ($null -eq $Usuario.LastLogonDate) {

        if ($Usuario.whenCreated -lt $FechaLimiteSinPrimerInicio) {

            $Estado = "Sin primer inicio de sesion"
        }
        else {

            continue
        }
    }


    # --------------------------------------------------------
    # CASO 2: USUARIO INACTIVO
    # --------------------------------------------------------

    elseif ($Usuario.LastLogonDate -lt $FechaLimiteInactividad) {

        $Estado = "Inactivo"
    }


    # --------------------------------------------------------
    # CUENTA SIN INCIDENCIAS
    # --------------------------------------------------------

    else {

        continue
    }


    # --------------------------------------------------------
    # REGISTRAR RESULTADO
    # --------------------------------------------------------

    $Resultados += [PSCustomObject]@{

        Nombre         = $Usuario.Name
        SamAccountName = $Usuario.SamAccountName
        Departamento   = $Usuario.Department
        OU              = $OUActual
        Enabled        = $Usuario.Enabled
        FechaCreacion  = $Usuario.whenCreated
        LastLogonDate  = $Usuario.LastLogonDate
        Estado         = $Estado
        FechaRevision  = Get-Date
    }
}


# ============================================================
# 9. MOSTRAR RESUMEN
# ============================================================

Write-Host ""
Write-Host "===== REVISION DE INACTIVIDAD ====="

Write-Host "Inactividad permitida             : $DiasInactividad dias"
Write-Host "Sin primer inicio permitido       : $DiasSinPrimerInicio dias"
Write-Host "Usuarios habilitados revisados    : $($Usuarios.Count)"
Write-Host "Usuarios detectados               : $($Resultados.Count)"


if ($Resultados.Count -gt 0) {

    Write-Host ""
    Write-Host "===== RESUMEN ====="


    $Resultados |
        Group-Object Estado |
        Select-Object Count, Name |
        Format-Table -AutoSize


    Write-Host "===== DETALLE ====="


    $Resultados |
        Format-Table `
            SamAccountName,
            Departamento,
            OU,
            FechaCreacion,
            LastLogonDate,
            Estado `
            -AutoSize
}


# ============================================================
# 10. EXPORTAR INFORME
# ============================================================

if ($Resultados.Count -gt 0) {

    $Fecha = Get-Date -Format "yyyyMMdd-HHmmss"


    $ArchivoInforme = Join-Path `
        $ReportPath `
        "AD-Inactive-Users-$Fecha.csv"


    try {

        $Resultados |
            Export-Csv `
                -Path $ArchivoInforme `
                -NoTypeInformation `
                -Encoding UTF8 `
                -ErrorAction Stop


        Write-Host ""
        Write-Host "Informe generado:"
        Write-Host $ArchivoInforme
    }
    catch {

        Write-Error "No se pudo generar el informe: $($_.Exception.Message)"
    }
}
else {

    Write-Host ""
    Write-Host "No se detectaron usuarios que requieran revision."
}