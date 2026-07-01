# ADR-0007: Autenticación y autorización con AWS Cognito

## Contexto

En Bookslot solo los usuarios registrados pueden reservar y solo administradores pueden crear recursos 
y slots. Sin autenticación, cualquiera podría reservar en nombre de otro 
usuario o crear recursos.

## Decisión

Se escoge **AWS Cognito** como proveedor de identidad ya que evita 
implementar login, hash de contraseñas y emisión de tokens manualmente y aplicando una protección en dos niveles:

### Nivel 1 — Autenticación (API Gateway)
Un JWT Authorizer nativo de API Gateway valida el token en cada petición protegida. El token viaja en la cabecera `Authorization: Bearer <token>`, y API Gateway comprueba automáticamente su firma, issuer, audience y expiración:

- **Firma** → que el token lo emitió nuestro User Pool (no es falsificado)
- **Issuer** → que viene de nuestro Cognito concreto
- **Audience** → que es para nuestra App Client
- **Expiración** → que no ha caducado

Si el token no es válido, la petición se rechaza con `401` antes de llegar a la Lambda.

### Nivel 2 — Autorización por rol (Lambda resources)
El JWT Authorizer valida el token, pero no filtra por pertenencia a grupos de Cognito. Por eso, la comprobación de rol se hace dentro de la Lambda:
```py
groups = claims.get("cognito:groups", "")
if "admins" not in groups:
    return {"statusCode": 403, "body": json.dumps({"message": "admin role required"})}
```

De modo que solo los usuarios del grupo **admins** pueden crear recursos y slots.

Diseño de rutas:
```
GET  /resources*   → público (sin authorizer)
POST /resources*   → JWT + check de grupo admins
POST /bookings     → JWT (cualquier usuario autenticado)
DELETE /bookings   → JWT (cualquier usuario autenticado)
```

Esto obligó a separar las rutas de la lambda `resources` en dos recursos de Terraform: 
- `resources_read` (sin autorización) 
- `resources_write` (con JWT authorizer).

### Dónde poner la autorización

- **Opción A (elegida)** — comprobar el grupo dentro de la Lambda de negocio.
- **Opción B** — un Lambda Authorizer dedicado que valide token y grupo antes de invocar la Lambda.

> Se optó por la **Opción A** por su simplicidad y menor fricción, adecuada al contexto académico.

En producción elegiría la **Opción B**, por dos motivos:

- **Responsabilidad única (SRP)** — con la Opción A, la Lambda de `resources` mezcla dos responsabilidades: autorizar y ejecutar la lógica de negocio. La Opción B las separa, la Lambda Authorizer se encarga de autorizar, y la Lambda de negocio (`resourcers`) solo de los recursos.

- **Seguridad reforzada y menor coste** — una Lambda Authorizer rechazaría al usuario no autorizado antes de invocar la Lambda de negocio.

Con la **Opción A**, la Lambda se invoca igualmente y solo después devuelve el `403`, gastando una invocación innecesaria y aumentando la superficie de ataque, ya que **el código de negocio llega a ejecutarse ante peticiones no autorizadas.**

```
Opción A → petición de no-admin → API GW deja pasar → Lambda SE INVOCA → comprueba grupo → 403
           → se paga la invocación aunque no hiciese nada útil

Opción B → petición de no-admin → Lambda Authorizer rechaza → la Lambda de negocio NO se invoca
           → no pagamos esa invocación (ahorro coste)
```

### Lo ideal: Lambda de registro contra Cognito

Lo correcto sería un endpoint propio (`POST /register`) con una Lambda que 
validara el DNI a través de **server-side** antes de crear el usuario en Cognito. Así, ningún DNI mal formado entraría al 
sistema.

Esto se descartó debido a que el rol `studentLambdaExecutionRole` no tiene permisos de Cognito 
(`cognito-idp:SignUp`), y ningún otro rol disponible en la cuenta de estudiante 
los tiene. Por tanto, el registro se hace directamente contra Cognito (CLI en 
las pruebas, SDK en una app real), sin pasar por la API de BookSlot. La 
consecuencia es que **el DNI no pasa por ninguna validación** ya que Cognito acepta 
cualquier string como `custom:dni`. 

De modo que se documenta como una limitación del entorno.


## Consecuencias / trade-offs

### Lo que gano

- Identidad verificada criptográficamente: el token prueba quién es el usuario, en lugar de que el cliente lo declare.

- Control de acceso en dos capas, cada una en su sitio (autenticación y autorización en la lógica).
Lectura pública sin fricción para consultar disponibilidad.

### Limitaciones


- **El registro directo no valida el DNI server-side**: Cognito acepta cualquier 
  valor como `custom:dni` (limitación del entorno).

- **El payload de un JWT va codificado en base64, no cifrado**: los `claims` son 
  legibles por cualquiera que intercepte el token. El `custom:dni` se mantiene 
  por utilidad, pero al ser un dato sensible, en producción debería evaluarse 
  eliminarlo del token y leerlo solo desde DynamoDB cuando se necesite.