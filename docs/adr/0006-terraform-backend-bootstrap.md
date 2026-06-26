# ADR-0006: Bootstrap manual del backend de Terraform

## Contexto

Terraform almacena su estado (`tfstate`) en un bucket de S3, configurado como 
backend remoto [ver ADR-0001: State locking nativo en S3](docs/adr/0001-state-locking-s3-native.md). Este bucket es un prerrequisito para que Terraform 
funcione bajo el comando `terraform init` y necesita que el bucket exista para poder 
conectarse a él y guardar/leer el estado.

Surge entonces la paradoja: ¿puede Terraform crear el bucket donde él mismo 
guarda su estado?

## El problema

Existe una dependencia circular:

- Para usar el bucket como backend, el bucket debe existir **antes** del 
  `terraform init`.
- Pero si fuera Terraform quien crea el bucket, lo haría durante el `terraform 
  apply`, que ocurre **después** del `init`.
- En ese primer arranque, Terraform no tendría dónde guardar su estado, porque el 
  bucket que lo almacenaría todavía no existe.

Es importante matizar que esto **solo afecta al bucket del backend**. Cualquier 
otro bucket de S3 (por ejemplo, uno para archivos estáticos) sí se gestiona con 
Terraform sin problema, porque no es donde vive el estado.

## Decisión

El bucket del backend se crea **fuera de Terraform**, mediante un script de 
bootstrap (`scripts/bootstrap.sh`) que usa la AWS CLI para crearlo y activar el 
versionado. Este script se ejecuta una sola vez, de forma manual, antes del primer 
`terraform init`.

El resto de la infraestructura (tabla, Lambdas, API Gateway, etc.) sí se gestiona 
íntegramente con Terraform. El bucket del estado es la única excepción, por la 
paradoja descrita.

> **Nota:** El script `bootstrap.sh` surgió como solución de despliegue rápido 
> tras un borrado de los recursos de mi cuenta de estudiante. Al montar el 
> pipeline de CI/CD se confirmó que tenía sentido mantenerlo, ya que el bucket 
> del backend es un prerrequisito del propio pipeline.

## Consecuencias / trade-offs

- **Un paso manual previo, inevitable por diseño.** Es una paradoja tener que 
  crear primero el bucket S3 donde se almacenará el `tfstate`, pero es un paso 
  manual asumible y que solo se ejecuta una vez.
- **Reproducibilidad mantenida.** Al encapsular el bootstrap en un script, el 
  proceso sigue siendo reproducible: tras un reseteo de la infra desplegada en la cuenta, basta con ejecutar `./scripts/bootstrap.sh` y luego
  `git push origin main` para recrear todo desde cero.
- **Alternativa considerada:** se podría usar una configuración de Terraform 
  separada con backend local para crear el bucket, pero seguiría siendo un paso 
  previo. El script es más simple y directo para este caso.