<#
.SYNOPSIS
    Alta masiva de usuarios en Active Directory desde un archivo CSV.

.DESCRIPTION
    Procesa solicitudes de alta de usuarios desde un archivo CSV.

    Para cada usuario:
    - Valida los datos de entrada.
    - Utiliza el departamento para determinar la OU de destino.
    - Valida que la OU y el grupo indicados existan.
    - Genera SamAccountName y UPN.
    - Comprueba que el usuario no exista.
    - Genera una contraseña temporal para el laboratorio.
    - Crea la cuenta en Active Directory.
    - Obliga al cambio de contraseña en el primer inicio de sesión.
    - Agrega al usuario al grupo indicado.
    - Valida el estado final.
    - Registra el resultado del proceso.

    El dominio DNS y el DistinguishedName del dominio se obtienen
    automáticamente desde Active Directory mediante Get-ADDomain.

    En este laboratorio existe una correspondencia entre el atributo
    Departamento y la OU donde se almacena el usuario.

    Ejemplo:

        Departamento = IT

        OU destino:
        OU=IT,OU=Usuarios,DC=example,DC=local

.NOTES
    Proyecto de laboratorio - TechSolutions Global
    PowerShell + Active Directory

    La contraseña temporal se utiliza únicamente durante la ejecución
    y no se almacena en el informe CSV.

    La generación y entrega de contraseñas temporales utilizada en este
    laboratorio no representa una estrategia de gestión de credenciales
    para un entorno de producción.
#>


# ============================================================
# 1. PARAMETROS
# ============================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

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

    $DomainUPN = $Dominio.DNSRoot
    $DomainDN  = $Dominio.DistinguishedName

    Write-Host "Dominio detectado: $DomainUPN"
}
catch {

    Write-Error "No se pudo obtener la informacion del dominio."
    return
}


# ============================================================
# 4. CONSTRUIR Y VALIDAR OU BASE
# ============================================================

$BaseOU = "OU=$UsersOU,$DomainDN"

try {

    Get-ADOrganizationalUnit `
        -Identity $BaseOU `
        -ErrorAction Stop |
        Out-Null
}
catch {

    Write-Error "La OU base no existe: $BaseOU"
    return
}


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

    $Usuarios = @(
        Import-Csv `
            -Path $CsvPath `
            -ErrorAction Stop
    )
}
catch {

    Write-Error "No se pudo importar el archivo CSV: $($_.Exception.Message)"
    return
}


# Validar que existan registros

if ($Usuarios.Count -eq 0) {

    Write-Error "El CSV no contiene usuarios para procesar."
    return
}


# Validar estructura del CSV

$ColumnasObligatorias = @(
    "Nombre",
    "Apellido",
    "Departamento",
    "Grupo"
)

$ColumnasCSV = $Usuarios[0].PSObject.Properties.Name


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

foreach ($Usuario in $Usuarios) {

    # --------------------------------------------------------
    # LIMPIAR VARIABLES DE LA ITERACION
    # --------------------------------------------------------

    $Nombre = ""
    $Apellido = ""
    $Departamento = ""
    $Grupo = ""

    $TargetOU = ""
    $SamAccountName = ""
    $UPN = ""
    $PasswordTemporal = ""

    $Estado = ""
    $Etapa = ""
    $Detalle = ""


    try {

        # ====================================================
        # 8.1 VALIDAR DATOS DE ENTRADA
        # ====================================================

        $Etapa = "Validacion"

        $Nombre = $Usuario.Nombre.Trim()
        $Apellido = $Usuario.Apellido.Trim()
        $Departamento = $Usuario.Departamento.Trim()
        $Grupo = $Usuario.Grupo.Trim()


        if (
            [string]::IsNullOrWhiteSpace($Nombre) -or
            [string]::IsNullOrWhiteSpace($Apellido) -or
            [string]::IsNullOrWhiteSpace($Departamento) -or
            [string]::IsNullOrWhiteSpace($Grupo)
        ) {

            throw "Nombre, apellido, departamento o grupo vacio."
        }


        # ====================================================
        # 8.2 DETERMINAR OU DESTINO
        # ====================================================

        $TargetOU = "OU=$Departamento,$BaseOU"


        # ====================================================
        # 8.3 VALIDAR OU DEL USUARIO
        # ====================================================

        try {

            Get-ADOrganizationalUnit `
                -Identity $TargetOU `
                -ErrorAction Stop |
                Out-Null
        }
        catch {

            throw "La OU correspondiente al departamento '$Departamento' no existe."
        }


        # ====================================================
        # 8.4 VALIDAR GRUPO DEL USUARIO
        # ====================================================

        try {

            Get-ADGroup `
                -Identity $Grupo `
                -ErrorAction Stop |
                Out-Null
        }
        catch {

            throw "El grupo '$Grupo' no existe."
        }


        # ====================================================
        # 8.5 GENERAR IDENTIDAD
        # ====================================================

        $SamAccountName = (
            $Nombre.Substring(0,1) + $Apellido
        ).ToLower()

        $UPN = "$SamAccountName@$DomainUPN"


        # ====================================================
        # 8.6 COMPROBAR SI EL USUARIO YA EXISTE
        # ====================================================

        $UsuarioExistente = Get-ADUser `
            -Filter "SamAccountName -eq '$SamAccountName'"


        if ($UsuarioExistente) {

            $Estado = "Ya existe"
            $Etapa = "Validacion"
            $Detalle = "Usuario omitido porque el SamAccountName ya existe."

            continue
        }


        # ====================================================
        # 8.7 GENERAR PASSWORD TEMPORAL
        # ====================================================
        # NOTA DE SEGURIDAD:
        # Este generador se utiliza exclusivamente en el laboratorio.
        # En produccion deben utilizarse los mecanismos y politicas
        # de gestion segura de credenciales definidos por la organizacion.

        $PasswordTemporal = "Ts!" +
            (Get-Random -Minimum 100000 -Maximum 999999) +
            "#Lab2026"


        $SecurePassword = ConvertTo-SecureString `
            $PasswordTemporal `
            -AsPlainText `
            -Force


        # ====================================================
        # 8.8 CREAR USUARIO
        # ====================================================

        try {

            New-ADUser `
                -Name "$Nombre $Apellido" `
                -GivenName $Nombre `
                -Surname $Apellido `
                -SamAccountName $SamAccountName `
                -UserPrincipalName $UPN `
                -Department $Departamento `
                -Path $TargetOU `
                -AccountPassword $SecurePassword `
                -Enabled $true `
                -ChangePasswordAtLogon $true `
                -ErrorAction Stop
        }
        catch {

            $Estado = "Error"
            $Etapa = "New-ADUser"
            $Detalle = $_.Exception.Message

            continue
        }


        # ====================================================
        # 8.9 AGREGAR USUARIO AL GRUPO
        # ====================================================

        try {

            Add-ADGroupMember `
                -Identity $Grupo `
                -Members $SamAccountName `
                -ErrorAction Stop
        }
        catch {

            $Estado = "Alta parcial"
            $Etapa = "Add-ADGroupMember"
            $Detalle = $_.Exception.Message

            continue
        }


        # ====================================================
        # 8.10 VALIDAR ESTADO FINAL
        # ====================================================

        $Etapa = "Validacion final"


        $CuentaFinal = Get-ADUser `
            -Identity $SamAccountName `
            -Properties Enabled, Department `
            -ErrorAction Stop


        $GruposFinales = @(
            Get-ADPrincipalGroupMembership `
                -Identity $SamAccountName `
                -ErrorAction Stop
        )


        if (
            $CuentaFinal.Enabled -eq $true -and
            $CuentaFinal.DistinguishedName -like "*,$TargetOU" -and
            $CuentaFinal.Department -eq $Departamento -and
            $GruposFinales.Name -contains $Grupo
        ) {

            $Estado = "Alta completa"
            $Etapa = "Finalizado"
            $Detalle = "Usuario creado, habilitado y agregado a $Grupo."
        }
        else {

            $Estado = "Alta parcial"
            $Etapa = "Validacion final"
            $Detalle = "El estado final no coincide con lo esperado."
        }
    }
    catch {

        # Si el usuario llego a crearse antes del error,
        # se considera un alta parcial.
        #
        # Si no existe en AD, se considera un error.

        if ($SamAccountName) {

            $UsuarioCreado = Get-ADUser `
                -Filter "SamAccountName -eq '$SamAccountName'" `
                -ErrorAction SilentlyContinue


            if ($UsuarioCreado) {

                $Estado = "Alta parcial"
            }
            else {

                $Estado = "Error"
            }
        }
        else {

            $Estado = "Error"
        }


        $Detalle = $_.Exception.Message
    }
    finally {

        # ====================================================
        # 8.11 REGISTRAR RESULTADO
        # ====================================================

        $Resultados += [PSCustomObject]@{

            Nombre         = $Nombre
            Apellido       = $Apellido
            SamAccountName = $SamAccountName
            Departamento   = $Departamento
            Grupo          = $Grupo
            Estado         = $Estado
            Etapa          = $Etapa
            Detalle        = $Detalle
            Fecha          = Get-Date
        }
    }
}


# ============================================================
# 9. MOSTRAR RESUMEN
# ============================================================

Write-Host ""
Write-Host "===== RESUMEN DE ALTAS ====="


$Resultados |
    Group-Object Estado |
    Select-Object Count, Name |
    Format-Table -AutoSize


# ============================================================
# 10. EXPORTAR INFORME
# ============================================================

$Fecha = Get-Date -Format "yyyyMMdd-HHmmss"


$RutaInforme = Join-Path `
    $ReportPath `
    "Resultado-Altas-$Fecha.csv"


try {

    $Resultados |
        Export-Csv `
            -Path $RutaInforme `
            -NoTypeInformation `
            -Encoding UTF8 `
            -ErrorAction Stop


    Write-Host ""
    Write-Host "Informe generado en:"
    Write-Host $RutaInforme
}
catch {

    Write-Error "No se pudo generar el informe: $($_.Exception.Message)"
}