# AD User Lifecycle Automation

Proyecto de automatización con PowerShell para gestionar y supervisar tareas habituales del ciclo de vida de usuarios en Microsoft Active Directory.

El proyecto está basado en situaciones reales de administración de sistemas y fue desarrollado y probado en un entorno de laboratorio de Active Directory.

---

## Descripción

`AD-User-Lifecycle-Automation` nace de una necesidad habitual en la administración de Active Directory: gestionar de forma eficiente el ciclo de vida de los usuarios cuando el número de cuentas comienza a crecer.

En un entorno pequeño, crear, revisar o deshabilitar algunas cuentas manualmente puede ser una tarea sencilla. Sin embargo, en organizaciones con cientos o miles de usuarios, estas operaciones pueden convertirse rápidamente en procesos repetitivos, lentos y propensos a errores.

Por ejemplo, el área de Recursos Humanos puede solicitar el alta de 100 nuevos trabajadores o comunicar la baja de 50 empleados. También puede ser necesario identificar cuentas que llevan mucho tiempo sin utilizarse, detectar usuarios que nunca han iniciado sesión o generar un informe mensual con las altas y bajas realizadas.

Realizar estas tareas manualmente requiere tiempo y dificulta mantener un proceso uniforme y trazable.

Este proyecto utiliza PowerShell y Active Directory para automatizar parte de ese trabajo mediante cuatro componentes relacionados:

- Alta masiva de usuarios desde archivos CSV.
- Detección de cuentas inactivas o sin primer inicio de sesión.
- Proceso controlado de baja de usuarios.
- Generación de informes mensuales del ciclo de vida.

El objetivo no es sustituir las decisiones del administrador, sino reducir tareas manuales repetitivas, aplicar validaciones consistentes y proporcionar información que facilite la administración y revisión de Active Directory.

---

## Flujo del ciclo de vida

El proceso comienza normalmente con una solicitud del área de Recursos Humanos.

Para las nuevas incorporaciones, Recursos Humanos proporciona un archivo CSV con los usuarios que deben crearse. `New-BulkADUsers.ps1` procesa la información, valida los datos necesarios y realiza las altas en Active Directory.

Durante la operación diaria, `Get-ADInactiveUsers.ps1` permite revisar las cuentas habilitadas e identificar usuarios que llevan un periodo determinado sin iniciar sesión o cuentas antiguas que nunca han realizado su primer inicio de sesión. Estos usuarios se consideran candidatos a revisión; el script no los deshabilita automáticamente.

Cuando Recursos Humanos comunica las bajas, `Disable-BulkADUsers.ps1` procesa la lista correspondiente, deshabilita las cuentas, retira sus grupos secundarios de Active Directory, las mueve a la OU destinada a bajas y registra el resultado de cada operación.

Finalmente, `Get-ADMonthlyLifecycleReport.ps1` combina información actual de Active Directory con el histórico generado por el proceso de bajas para proporcionar un resumen mensual de usuarios habilitados, altas realizadas y resultados de los procesos de baja.

```text
                  Recursos Humanos
                  /              \
                 /                \
        Nuevas incorporaciones    Bajas
                |                  |
                v                  v
     New-BulkADUsers.ps1   Disable-BulkADUsers.ps1
                |                  |
                v                  v
          Active Directory    Histórico de bajas
                |                  |
                v                  |
    Get-ADInactiveUsers.ps1        |
                |                  |
                v                  |
       Candidatos a revisión       |
                |                  |
                +--------+---------+
                         |
                         v
          Get-ADMonthlyLifecycleReport.ps1
                         |
                         v
                  Informe mensual
```

---

## Scripts incluidos

### `New-BulkADUsers.ps1`

Automatiza la creación de múltiples usuarios de Active Directory a partir de un archivo CSV.

Entre sus funciones se encuentran:

- Validación del módulo Active Directory.
- Detección automática del dominio mediante `Get-ADDomain`.
- Validación de la OU base.
- Validación de las columnas obligatorias del CSV.
- Validación de la OU y grupo correspondientes a cada usuario.
- Generación de `SamAccountName` y UPN.
- Comprobación de cuentas existentes.
- Creación de usuarios.
- Asignación al grupo correspondiente.
- Verificación del resultado final.
- Generación de un informe de ejecución.

El departamento indicado en cada fila determina la OU de destino según la estructura utilizada en el laboratorio.

---

### `Get-ADInactiveUsers.ps1`

Permite localizar cuentas habilitadas que requieren revisión por falta de actividad.

Distingue entre:

- **Inactivo:** usuario que ha iniciado sesión anteriormente, pero cuya última actividad supera el periodo configurado.
- **Sin primer inicio de sesión:** cuenta que nunca ha iniciado sesión y cuya antigüedad supera un segundo umbral configurable.

Los valores predeterminados son:

- 90 días para usuarios inactivos.
- 30 días para cuentas sin primer inicio de sesión.

El script únicamente genera candidatos para revisión.

**No deshabilita ni elimina usuarios automáticamente.**

---

### `Disable-BulkADUsers.ps1`

Automatiza un proceso controlado de offboarding a partir de una lista de `SamAccountName`.

Para cada cuenta:

1. Valida que el usuario exista.
2. Captura su estado, OU y grupos anteriores.
3. Deshabilita la cuenta.
4. Retira las membresías de grupos secundarios de Active Directory.
5. Conserva `Domain Users`.
6. Mueve la cuenta a la OU configurada para bajas.
7. Comprueba el estado final.
8. Registra el resultado.

Los resultados permiten distinguir entre:

- `Baja completada`
- `Baja parcial`
- `Error`

El script no elimina las cuentas de Active Directory.

---

### `Get-ADMonthlyLifecycleReport.ps1`

Genera un resumen mensual utilizando dos fuentes de información.

**Active Directory**

Se utiliza para obtener:

- Número actual de usuarios habilitados.
- Cuentas creadas durante el mes mediante `whenCreated`.

**Histórico de bajas**

Se utiliza el archivo mensual generado por `Disable-BulkADUsers.ps1` para obtener:

- Bajas completadas.
- Bajas parciales.
- Errores durante procesos de baja.

El informe resultante permite obtener una visión resumida del movimiento mensual de cuentas.

---

## Estructura del repositorio

```text
AD-User-Lifecycle-Automation/
|
|-- Scripts/
|   |-- New-BulkADUsers.ps1
|   |-- Get-ADInactiveUsers.ps1
|   |-- Disable-BulkADUsers.ps1
|   `-- Get-ADMonthlyLifecycleReport.ps1
|
|-- Examples/
|   |-- onboarding-example.csv
|   `-- offboarding-example.csv
|
|-- README.md
`-- .gitignore
```

Los reportes y logs generados durante las ejecuciones no se incluyen en el repositorio.

---

## Requisitos

- Windows Server con Active Directory Domain Services.
- PowerShell.
- Módulo `ActiveDirectory`.
- Permisos adecuados para consultar y modificar los objetos correspondientes.
- Una estructura de OUs y grupos compatible con los parámetros utilizados.

Los scripts fueron desarrollados y probados en un entorno de laboratorio.

---

## Ejemplos de entrada

### Alta de usuarios

`Examples/onboarding-example.csv`

```csv
Nombre,Apellido,Departamento,Grupo
Carlos,Lab01,RRHH,GG-RRHH
Elena,Lab02,Finanzas,GG-Finanzas
Mario,Lab03,IT,GG-IT
Sofia,Lab04,Finanzas,GG-Finanzas
```

El script espera las columnas:

- `Nombre`
- `Apellido`
- `Departamento`
- `Grupo`

---

### Baja de usuarios

`Examples/offboarding-example.csv`

```csv
SamAccountName
clab01
elab02
mlab03
```

El proceso de baja utiliza `SamAccountName` como identificador de la cuenta.

---

## Ejemplos de uso

### Alta masiva

```powershell
.\Scripts\New-BulkADUsers.ps1 `
    -CsvPath ".\Examples\onboarding-example.csv"
```

### Revisión de usuarios inactivos

Valores predeterminados:

```powershell
.\Scripts\Get-ADInactiveUsers.ps1
```

Personalizando los umbrales:

```powershell
.\Scripts\Get-ADInactiveUsers.ps1 `
    -DiasInactividad 90 `
    -DiasSinPrimerInicio 30
```

### Baja masiva

```powershell
.\Scripts\Disable-BulkADUsers.ps1 `
    -CsvPath ".\Examples\offboarding-example.csv"
```

### Informe mensual

```powershell
.\Scripts\Get-ADMonthlyLifecycleReport.ps1
```

Cuando el histórico de bajas se encuentra en otra ubicación puede especificarse mediante `-OffboardingReportPath`.

---

## Patrón utilizado

Los scripts siguen, cuando corresponde, un patrón administrativo común:

```text
Validar
   |
   v
Ejecutar
   |
   v
Verificar
   |
   v
Registrar
```

La intención es evitar que una operación sea considerada correcta únicamente porque un cmdlet terminó sin mostrar un error.

Siempre que resulta aplicable, el script consulta posteriormente Active Directory para verificar el estado obtenido y genera información de trazabilidad.

---

## Pruebas realizadas

Los scripts fueron probados en un dominio de laboratorio con diferentes escenarios.

### Alta

Se probaron:

- Alta correcta.
- Usuario ya existente.
- Error durante la asignación de grupo.
- Alta parcial.
- Procesamiento de múltiples departamentos y grupos desde un único CSV.
- Verificación posterior de OU, departamento, estado y grupo.

### Inactividad

Se probaron:

- Usuarios activos sin superar el umbral.
- Usuarios con última sesión anterior al periodo configurado.
- Usuarios que nunca iniciaron sesión.
- Diferentes umbrales para inactividad y primer inicio de sesión.

### Baja

Se probaron:

- Baja completa.
- Usuario inexistente.
- Fallo controlado durante una etapa intermedia.
- Baja parcial.
- Retirada de grupos secundarios.
- Conservación de `Domain Users`.
- Reprocesamiento de una cuenta que había quedado parcialmente procesada.
- Verificación posterior del estado, OU y grupos.

### Informe mensual

Se verificaron:

- Usuarios habilitados.
- Altas obtenidas desde `whenCreated`.
- Bajas completadas.
- Bajas parciales.
- Errores de baja.
- Correspondencia entre los resultados del informe, Active Directory y el histórico mensual de bajas.

---

## Consideraciones de seguridad

El proyecto fue preparado para publicación utilizando información ficticia de laboratorio.

Los archivos de ejemplo no contienen usuarios ni credenciales reales.

Los reportes y logs generados durante la ejecución están excluidos mediante `.gitignore`.

El script de altas utiliza una contraseña temporal generada durante la ejecución y obliga al cambio de contraseña en el primer inicio de sesión.

> **Importante:** el mecanismo de generación de contraseña utilizado en este proyecto tiene fines exclusivamente de laboratorio. En un entorno de producción deben utilizarse las políticas y mecanismos seguros de gestión y entrega de credenciales definidos por la organización.

Las contraseñas temporales no se almacenan en los informes CSV generados por el script.

---

## Limitaciones conocidas

- El informe mensual obtiene las bajas a partir del histórico generado por `Disable-BulkADUsers.ps1`. Las bajas realizadas manualmente fuera del flujo automatizado pueden no aparecer en el informe.

- El proceso de altas depende de un archivo CSV con la estructura esperada. Datos incompletos, incorrectos o recursos inexistentes pueden impedir el procesamiento de una fila.

- El proceso de bajas identifica las cuentas mediante `SamAccountName`. El archivo de entrada debe contener este identificador.

- La detección de inactividad identifica candidatos para revisión, pero no determina si un empleado realmente debe ser dado de baja.

- La retirada de grupos durante el offboarding afecta a membresías de grupos secundarios de Active Directory. No debe interpretarse como la revocación automática de todos los posibles accesos del usuario en otros sistemas, aplicaciones o servicios.

- Los scripts han sido desarrollados y validados en un entorno de laboratorio. Antes de utilizarlos en producción deben revisarse y adaptarse a la estructura, políticas y controles de la organización.

---

## Mejoras futuras

Posibles evoluciones del proyecto:

- Soporte para múltiples grupos por usuario durante el onboarding.
- Integración con mecanismos corporativos de gestión segura de credenciales.
- Mayor correlación entre solicitudes de Recursos Humanos y operaciones realizadas.
- Ampliación de los informes históricos.
- Integración futura con servicios de identidad y administración cloud.

---

## Tecnologías utilizadas

- PowerShell
- Active Directory Domain Services
- ActiveDirectory PowerShell Module
- CSV
- Git
- GitHub

---

## Contexto

Este proyecto forma parte de un laboratorio práctico de administración de infraestructura Microsoft orientado a automatización, troubleshooting y construcción de procedimientos reproducibles mediante PowerShell.