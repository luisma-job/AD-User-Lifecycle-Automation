<#
.SYNOPSIS
    Baja masiva de usuarios en Active Directory desde un archivo CSV.

.DESCRIPTION
    Procesa solicitudes de baja de usuarios desde un archivo CSV.

    Para cada usuario:
    - Comprueba que exista en Active Directory.
    - Captura su información y grupos antes de modificarlo.
    - Deshabilita la cuenta.
    - Retira los grupos secundarios del usuario.
    - Conserva Domain Users como grupo primario.
    - Mueve la cuenta a la OU de bajas.
    - Valida el estado final.
    - Registra el resultado del proceso.

    El DistinguishedName del dominio se obtiene automáticamente
    desde Active Directory mediante Get-ADDomain.

    Al finalizar actualiza el informe mensual de bajas.

.NOTES
    Proyecto de laboratorio - TechSolutions Global
    PowerShell + Active Directory

    El script retira membresías de grupos secundarios de Active Directory.
    Esto no implica necesariamente la retirada de accesos externos
    como Microsoft 365, VPN, aplicaciones o permisos directos.
#>


# ============================================================
# 1. PARAMETROS
# ============================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [string]$OffboardingOU = "Bajas",

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
# 4. LOCALIZAR Y VALIDAR OU DE BAJAS
# ============================================================

$BaseOU = "OU=Usuarios,$DomainDN"

try {

    $OUEncontrada = @(
        Get-ADOrganizationalUnit `
            -SearchBase $BaseOU `
            -Filter "Name -eq '$OffboardingOU'" `
            -ErrorAction Stop
    )
}
catch {

    Write-Error "No se pudo buscar la OU de bajas dentro de: $BaseOU"
    return
}


if ($OUEncontrada.Count -eq 0) {

    Write-Error "No se encontro la OU '$OffboardingOU' dentro de '$BaseOU'."
    return
}


if ($OUEncontrada.Count -gt 1) {

    Write-Error "Se encontro mas de una OU llamada '$OffboardingOU'. No se puede determinar el destino de forma segura."
    return
}


$TargetOU = $OUEncontrada[0].DistinguishedName

Write-Host "OU de bajas detectada: $TargetOU"

# ============================================================
# 5. VALIDAR ARCHIVO CSV
# ============================================================

if (-not (Test-Path $CsvPath)) {

    Write-Error "El archivo CSV no existe: $CsvPath"
    return
}


# ============================================================
# 6. PREPARAR DIRECTORIO DE INFORMES
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
# 7. IMPORTAR Y VALIDAR SOLICITUDES
# ============================================================

try {

    $BajasRRHH = @(
        Import-Csv `
            -Path $CsvPath `
            -ErrorAction Stop
    )
}
catch {

    Write-Error "No se pudo importar el archivo CSV: $($_.Exception.Message)"
    return
}


# Validar que existan solicitudes

if ($BajasRRHH.Count -eq 0) {

    Write-Error "El archivo CSV no contiene solicitudes de baja."
    return
}


# Validar estructura del CSV

$ColumnasObligatorias = @(
    "SamAccountName"
)

$ColumnasCSV = $BajasRRHH[0].PSObject.Properties.Name


foreach ($Columna in $ColumnasObligatorias) {

    if ($Columna -notin $ColumnasCSV) {

        Write-Error "Falta la columna obligatoria '$Columna' en el archivo CSV."
        return
    }
}


$Resultados = @()


# ============================================================
# 8. PROCESAMIENTO MASIVO
# ============================================================

foreach ($Usuario in $BajasRRHH) {

    # --------------------------------------------------------
    # LIMPIAR VARIABLES DE LA ITERACION
    # --------------------------------------------------------

    $SamAccountName = ""

    $NombreAnterior = ""
    $EstadoAnterior = ""
    $OUAnterior = ""
    $GruposAnteriores = ""
    $OUFinal = ""

    $Estado = ""
    $Etapa = ""
    $Detalle = ""


    # --------------------------------------------------------
    # VARIABLES DE CONTROL
    # --------------------------------------------------------

    $CuentaDeshabilitada = $false
    $GruposRetirados = $false
    $CuentaMovida = $false


    try {

        # ====================================================
        # 8.1 VALIDAR DATOS DE ENTRADA
        # ====================================================

        $Etapa = "Validacion"

        $SamAccountName = $Usuario.SamAccountName.Trim()


        if ([string]::IsNullOrWhiteSpace($SamAccountName)) {

            throw "SamAccountName vacio."
        }


        # ====================================================
        # 8.2 VALIDAR USUARIO
        # ====================================================

        $CuentaAD = Get-ADUser `
            -Identity $SamAccountName `
            -Properties Enabled `
            -ErrorAction Stop


        $NombreAnterior = $CuentaAD.Name
        $EstadoAnterior = $CuentaAD.Enabled
        $OUAnterior = $CuentaAD.DistinguishedName


        # ====================================================
        # 8.3 CAPTURAR GRUPOS ANTERIORES
        # ====================================================

        $Etapa = "Captura de grupos"


        $Grupos = @(
            Get-ADPrincipalGroupMembership `
                -Identity $SamAccountName `
                -ErrorAction Stop
        )


        $GruposAnteriores = ($Grupos.Name) -join "; "


        # ====================================================
        # 8.4 DESHABILITAR CUENTA
        # ====================================================

        $Etapa = "Deshabilitacion"


        Disable-ADAccount `
            -Identity $SamAccountName `
            -ErrorAction Stop


        $CuentaDeshabilitada = $true


        # ====================================================
        # 8.5 RETIRAR GRUPOS SECUNDARIOS
        # ====================================================

        $Etapa = "Retirada de grupos"


        $GruposARetirar = @(
            $Grupos | Where-Object {
                $_.Name -ne "Domain Users"
            }
        )


        foreach ($Grupo in $GruposARetirar) {

            Remove-ADGroupMember `
                -Identity $Grupo.DistinguishedName `
                -Members $SamAccountName `
                -Confirm:$false `
                -ErrorAction Stop
        }


        $GruposRetirados = $true


        # ====================================================
        # 8.6 MOVER CUENTA A OU DE BAJAS
        # ====================================================

        $Etapa = "Movimiento a OU destino"


        $CuentaActual = Get-ADUser `
            -Identity $SamAccountName `
            -ErrorAction Stop


        Move-ADObject `
            -Identity $CuentaActual.DistinguishedName `
            -TargetPath $TargetOU `
            -ErrorAction Stop


        $CuentaMovida = $true


        # ====================================================
        # 8.7 VALIDAR ESTADO FINAL
        # ====================================================

        $Etapa = "Validacion final"


        $CuentaFinal = Get-ADUser `
            -Identity $SamAccountName `
            -Properties Enabled `
            -ErrorAction Stop


        $OUFinal = $CuentaFinal.DistinguishedName


        $GruposFinales = @(
            Get-ADPrincipalGroupMembership `
                -Identity $SamAccountName `
                -ErrorAction Stop
        )


        $GruposSecundariosRestantes = @(
            $GruposFinales | Where-Object {
                $_.Name -ne "Domain Users"
            }
        )


        # Para considerar la baja completada:
        #
        # 1. La cuenta debe estar deshabilitada.
        # 2. Debe encontrarse en la OU de bajas.
        # 3. No debe conservar grupos secundarios.

        if (
            $CuentaFinal.Enabled -eq $false -and
            $OUFinal -like "*,$TargetOU" -and
            $GruposSecundariosRestantes.Count -eq 0
        ) {

            $Estado = "Baja completada"
            $Etapa = "Finalizado"
            $Detalle = "Cuenta deshabilitada, grupos secundarios retirados y movida a la OU de bajas."
        }
        else {

            $Estado = "Baja parcial"
            $Etapa = "Validacion final"
            $Detalle = "El estado final no coincide con lo esperado."
        }
    }


    # ========================================================
    # 8.8 MANEJO DE ERRORES
    # ========================================================

    catch {

        if (
            $CuentaDeshabilitada -or
            $GruposRetirados -or
            $CuentaMovida
        ) {

            $Estado = "Baja parcial"
        }
        else {

            $Estado = "Error"
        }


        $Detalle = $_.Exception.Message
    }


    # ========================================================
    # 8.9 REGISTRAR RESULTADO
    # ========================================================

    $Resultados += [PSCustomObject]@{

        Nombre           = $NombreAnterior
        SamAccountName   = $SamAccountName
        EstadoAnterior   = $EstadoAnterior
        OUAnterior       = $OUAnterior
        GruposAnteriores = $GruposAnteriores
        Estado           = $Estado
        Etapa            = $Etapa
        Detalle          = $Detalle
        OUFinal           = $OUFinal
        FechaBaja         = Get-Date
    }
}


# ============================================================
# 9. MOSTRAR RESUMEN
# ============================================================

Write-Host ""
Write-Host "===== RESUMEN DE BAJAS ====="


$Resultados |
    Group-Object Estado |
    Select-Object Count, Name |
    Format-Table -AutoSize


Write-Host "===== DETALLE ====="


$Resultados |
    Format-Table `
        SamAccountName,
        Estado,
        Etapa `
        -AutoSize


# ============================================================
# 10. EXPORTAR INFORME
# ============================================================

$Mes = Get-Date -Format "yyyy-MM"


$ArchivoBajas = Join-Path `
    $ReportPath `
    "Bajas-$Mes.csv"


try {

    $Resultados |
        Export-Csv `
            -Path $ArchivoBajas `
            -NoTypeInformation `
            -Encoding UTF8 `
            -Append `
            -ErrorAction Stop


    Write-Host ""
    Write-Host "Informe actualizado:"
    Write-Host $ArchivoBajas
}
catch {

    Write-Error "No se pudo actualizar el informe: $($_.Exception.Message)"
}