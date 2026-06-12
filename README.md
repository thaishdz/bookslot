# BookSlot
> 🎓 Proyecto final del curso de AWS impartido por [Commit Academy](https://www.commitacademy.io/)
## Descripción
[#TODO] Qué es el producto, qué resuelve, el reto de la concurrencia.

## Arquitectura
[#TODO] Diagrama de Excalidraw + breve descripción de serverless.

## Decisiones arquitectónicas (ADRs)

- [ADR-0001: State locking nativo en S3](docs/adr/0001-state-locking-s3-native.md)
- [ADR-0002: Modelo de datos single-table](docs/adr/0002-single-table-design.md)
- [ADR-0003: Rol IAM de ejecución de las Lambdas](docs/adr/0003-lambda-iam-execution-role.md)

## Despliegue
[#TODO] Prerrequisitos, pasos reproducibles, variables de entorno.

## Control de concurrencia
[#TODO] Cómo evitamos overbooking + el script de prueba y su salida.

## Seguridad
### IAM Roles

La cuenta de estudiante no permite crear roles IAM propios, por lo que se reutiliza un rol preexistente.

El **análisis completo de este trade-off** está en el [ADR-0003: Rol IAM de ejecución de las Lambdas](docs/adr/0003-lambda-iam-execution-role.md).

[#TODO] Secrets Manager (Cognito?), HTTPS.

## Observabilidad
[#TODO] Logs, alarmas.

## FinOps
[#TODO] Tags, AWS Budgets, estimación de coste mensual.

## CI/CD
[#TODO] Pipeline de GitHub Actions

## Destrucción
[#TODO] `terraform destroy` + eliminar manualmente el bucket S3 del estado 
(ojo: tiene versionado, vaciar con `--force`).

