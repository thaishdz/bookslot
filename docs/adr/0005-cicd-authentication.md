# ADR-0005: Autenticación del pipeline CI/CD con AWS

## Contexto

El pipeline de CI/CD (GitHub Actions) se ejecuta en runners de GitHub, es decir, 
**fuera** de nuestra máquina y fuera de AWS. Para poder ejecutar `terraform apply` 
y desplegar la infraestructura, necesita autenticarse contra la cuenta de AWS.

Esto plantea una cuestión de seguridad ya que las credenciales viven en GitHub y
si se gestionan mal y se filtran, un atacante podría obtener
acceso a la cuenta de AWS.

## Opciones consideradas

### Opción 1: OIDC (OpenID Connect) — la recomendada
GitHub Actions puede autenticarse con AWS mediante OIDC, este establece una relación 
de confianza entre el repositorio y un IAM role, de modo que GitHub obtiene 
**credenciales temporales** en cada ejecución, sin necesidad de almacenar claves 
permanentes. Es el enfoque más seguro y la práctica recomendada, porque no hay 
secretos de larga duración que puedan filtrarse.

Requiere crear un **proveedor de identidad OIDC** y un **IAM role** con una 
trust policy que confíe en GitHub.

### Opción 2: Credenciales de acceso permanentes (IAM user)
Crear un usuario de IAM con `access key` + `secret key` permanentes y guardarlas 
como secretos de GitHub. Funciona de forma estable, pero las claves son de larga 
duración y si se filtran, el riesgo persiste hasta que se revocan manualmente.

### Opción 3: Credenciales temporales (sesión SSO) como secretos
Usar las credenciales temporales de la cuenta (access key + secret + session token) 
como secretos de GitHub. Funciona, pero **caducan** a las pocas horas, por lo que 
hay que renovarlas con frecuencia.

## Decisión

Se opta por la **Opción 3** (credenciales temporales SSO como secretos), no por ser la 
mejor, sino por ser la **única viable en el entorno académico** donde nos encontramos.

La cuenta de estudiante (`StudentLabAccess`) tiene los 
permisos de IAM restringidos:
- No permite crear el proveedor OIDC ni roles (`iam:CreateOpenIDConnectProvider`, 
  `iam:CreateRole` denegados), lo que descarta la **Opción 1**.
- No permite crear usuarios de IAM con claves permanentes, lo que descarta la 
  **Opción 2**.

Las únicas credenciales disponibles son las temporales de sesión SSO, que se 
configuran como los tres secretos de GitHub: 
- `AWS_ACCESS_KEY_ID`, 
- `AWS_SECRET_ACCESS_KEY` 
- `AWS_SESSION_TOKEN`.

## Consecuencias

- **El pipeline funciona, pero con credenciales perecederas.** Las credenciales 
  temporales caducan a las pocas horas, por lo que el despliegue automático solo 
  funciona mientras estén vigentes. Para cada despliegue hay que renovar las 
  credenciales SSO y actualizar los secretos de GitHub.
- **Menor seguridad que OIDC.** Aunque las credenciales son temporales (lo que 
  reduce el riesgo frente a claves permanentes), siguen almacenándose como secretos 
  en un sistema externo, en lugar de obtenerse dinámicamente vía OIDC.
- **En un entorno con permisos completos**, la solución correcta sería la Opción 1 
  (OIDC) ya que el workflow está escrito para poder migrarse a ese enfoque cambiando 
  únicamente el paso de autenticación, sin tocar el resto del pipeline.

Esta limitación es una restricción del entorno académico, no una decisión de 
diseño. Se documenta para dejar constancia de cuál sería la implementación ideal 
en producción.