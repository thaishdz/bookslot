
# ADR-0001: State locking nativo en S3

## Contexto

La problemática que buscamos resolver con el **State Locking** es evitar que se lancen applies concurrentes en Terraform y una corrupción del **`tfstate`**, ya que es la fuente de la verdad de Terraform y podría comprometer toda la infraestructura.

Sin un mecanismo de bloqueo, dos **`terraform apply`** simultáneos podrían escribir el **`tfstate`** a la vez, dejándolo en un estado inconsistente y haciendo que Terraform pierda esa fiabilidad al no saber qué recursos existen realmente.

## Opciones consideradas  
- ### Opción A: tabla DynamoDB externa 

Al contrario que los gestores SQL (MySQL, PostgreSQL), que poseen un lock nativo a nivel de base de datos, el backend de Terraform en S3 (hasta la versión v1.11) no dispone de ningún mecanismo de bloqueo propio. Por eso Terraform recomendaba usar una tabla DynamoDB externa, pero no para bloquear datos de la aplicación, sino para registrar un **lock** que impidiera que dos procesos de Terraform escribieran el `tfstate` a la vez. La tabla actuaría como un semáforo del proceso de despliegue, no como un mecanismo de bloqueo para la lógica de negocio (en nuestro caso, las reservas).

- ### Opción B: S3-native locking

Esta es la alternativa que Terraform a partir de la v1.11 presenta a la tabla externa. En vez de delegar en una tabla, el **lock** vive como un fichero temporal dentro del propio bucket de S3. Este fichero se crea mientras el apply está en curso y se elimina al terminar. 

Fuente: [DynamoDB not needed for Terraform State locking in S3 anymore](https://medium.com/aws-specialists/dynamodb-not-needed-for-terraform-state-locking-in-s3-anymore-29a8054fc0e9) 

## Decisión

En primera instancia llegué a crear la tabla en DynamoDB, pero no me terminó de convencer ya que me resultaba bastante engorroso tener que gestionar esos locks de modo que busqué una alternativa. Encontré el artículo de Medium que cité anteriormente **sobre** S3-native locking, y me terminó de convencer de aplicar esa decisión, ya que mi versión de Terraform era adecuada (v1.14) para migrar a ese cambio.

## Trade-offs

- **Lo que gano**: Una infraestructura más simple con menos recursos que mantener y menos gestión de permisos IAM. Con el enfoque de DynamoDB necesitábamos un rol con permisos extra para leer/escribir/borrar ítems en la tabla de locks; al migrar a **`S3-native locking`** esos permisos sobran por completo, ya que el lock reside en el mismo S3 que ya tiene acceso al `tfstate`.

- **Limitación**: El artículo de Medium destaca que si un apply se interrumpe a media ejecución, el **lockfile** puede quedarse atascado en S3 y bloquear futuros applies hasta que se borre a mano.  
