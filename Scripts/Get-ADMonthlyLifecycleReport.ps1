<#
.SYNOPSIS
    Genera un informe mensual del ciclo de vida de usuarios
    en Active Directory.

.DESCRIPTION
    Genera un resumen mensual con:

    - Usuarios habilitados actualmente.
    - Usuarios creados durante el mes.
    - Bajas completadas durante el mes.
    - Bajas parciales.
    - Errores durante procesos de baja.

    Las altas se obtienen directamente desde Active Directory
    utilizando el atributo whenCreated.

    Las bajas se obtienen del registro mensual generado por
    Disable-BulkADUsers.ps1.

    IMPORTANTE:
    Las bajas realizadas manualmente fuera del flujo automatizado
    pueden no aparecer en este informe.

.NOTES
    Proyecto de laboratorio - TechSolutions Global
    PowerShell + Active Directory
#>


# ============================================================
# 1. PARAMETROS
# ============================================================

param(
    [string]$UsersOU = "Usuarios",

    [string]$OffboardingReportPath = (
        Join-Path $PSScriptRoot "Reportes"
    ),

    [string]$ReportPath = (
        Join-Path $PSScriptRoot "InformesMensuales"
    )
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
# 5. PREPARAR DIRECTORIO DEL INFORME
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
# 6. CALCULAR PERIODO DEL MES
# ============================================================

$Ahora = Get-Date

$InicioMes = Get-Date `
    -Year $Ahora.Year `
    -Month $Ahora.Month `
    -Day 1 `
    -Hour 0 `
    -Minute 0 `
    -Second 0

$InicioMesSiguiente = $InicioMes.AddMonths(1)

$Mes = $Ahora.ToString("yyyy-MM")


# ============================================================
# 7. CONSULTAR ACTIVE DIRECTORY
# ============================================================

try {

    $Usuarios = @(
        Get-ADUser `
            -SearchBase $BaseOU `
            -Filter * `
            -Properties Enabled, whenCreated, Department `
            -ErrorAction Stop
    )
}
catch {

    Write-Error "No se pudieron consultar los usuarios de Active Directory."
    return
}


# ============================================================
# 8. CALCULAR USUARIOS HABILITADOS
# ============================================================

$UsuariosHabilitados = @(
    $Usuarios | Where-Object {
        $_.Enabled -eq $true
    }
)

$TotalUsuariosHabilitados = $UsuariosHabilitados.Count


# ============================================================
# 9. CALCULAR ALTAS DEL MES
# ============================================================

$AltasMes = @(
    $Usuarios | Where-Object {

        $_.whenCreated -ge $InicioMes -and
        $_.whenCreated -lt $InicioMesSiguiente
    }
)

$TotalAltas = $AltasMes.Count


# ============================================================
# 10. LEER REGISTRO DE BAJAS
# ============================================================

$ArchivoBajas = Join-Path `
    $OffboardingReportPath `
    "Bajas-$Mes.csv"


$BajasMes = @()


if (Test-Path $ArchivoBajas) {

    try {

        $BajasMes = @(
            Import-Csv `
                -Path $ArchivoBajas `
                -ErrorAction Stop
        )
    }
    catch {

        Write-Error "No se pudo leer el registro mensual de bajas: $($_.Exception.Message)"
        return
    }
}
else {

    Write-Host ""
    Write-Host "No existe registro de bajas para el mes: $Mes"
}


# ============================================================
# 11. CLASIFICAR RESULTADOS DE BAJAS
# ============================================================

$BajasCompletadas = @(
    $BajasMes | Where-Object {
        $_.Estado -eq "Baja completada"
    }
)

$BajasParciales = @(
    $BajasMes | Where-Object {
        $_.Estado -eq "Baja parcial"
    }
)

$ErroresBaja = @(
    $BajasMes | Where-Object {
        $_.Estado -eq "Error"
    }
)


$TotalBajasCompletadas = $BajasCompletadas.Count
$TotalBajasParciales = $BajasParciales.Count
$TotalErroresBaja = $ErroresBaja.Count


# ============================================================
# 12. CONSTRUIR RESUMEN MENSUAL
# ============================================================

$Resumen = [PSCustomObject]@{

    Mes                  = $Mes
    UsuariosHabilitados  = $TotalUsuariosHabilitados
    Altas                = $TotalAltas
    BajasCompletadas     = $TotalBajasCompletadas
    BajasParciales       = $TotalBajasParciales
    ErroresBaja          = $TotalErroresBaja
    FechaGeneracion      = Get-Date
}


# ============================================================
# 13. MOSTRAR RESUMEN
# ============================================================

Write-Host ""
Write-Host "===== INFORME MENSUAL DE ACTIVE DIRECTORY ====="
Write-Host ""

Write-Host "Mes                       : $Mes"
Write-Host "Usuarios habilitados      : $TotalUsuariosHabilitados"
Write-Host "Altas del mes             : $TotalAltas"
Write-Host "Bajas completadas         : $TotalBajasCompletadas"
Write-Host "Bajas parciales           : $TotalBajasParciales"
Write-Host "Errores de baja           : $TotalErroresBaja"


# ============================================================
# 14. EXPORTAR RESUMEN
# ============================================================

$ArchivoResumen = Join-Path `
    $ReportPath `
    "AD-Monthly-Lifecycle-$Mes.csv"


try {

    $Resumen |
        Export-Csv `
            -Path $ArchivoResumen `
            -NoTypeInformation `
            -Encoding UTF8 `
            -ErrorAction Stop

    Write-Host ""
    Write-Host "Informe mensual generado:"
    Write-Host $ArchivoResumen
}
catch {

    Write-Error "No se pudo generar el informe mensual: $($_.Exception.Message)"
}