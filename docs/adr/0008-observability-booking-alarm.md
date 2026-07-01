# ADR-0008: Observabilidad para reservas

## Contexto

BookSlot ya emitía logs a CloudWatch, pero los logs por sí solos son un 
mecanismo **reactivo** solo sirven si alguien los está mirando. Ante un fallo, 
nadie se entera hasta que revisa los logs manualmente (o hasta que un usuario 
se queja). Falta un mecanismo **proactivo** que avise automáticamente cuando 
algo va mal, sin depender de que una persona esté vigilando.

## Decisión

Se monta una **alarma de CloudWatch** sobre la métrica de errores de la Lambda 
`bookings`, que notifica a través de un **topic de SNS** cuando se dispara.

### Qué vigilar: solo errores, no invocaciones

Se vigila la métrica `Errors` de la Lambda `bookings`, no el número de 
invocaciones. El número de invocaciones es una métrica de **tráfico** que indica actividad, 
no **salud**, esto se debe a que un pico puede indicar alta demanda legítima (muchas reservas) 
tanto como un problema, por lo que no es accionable por sí solo. Los errores, en 
cambio, son un **síntoma directo** de que el usuario no puede completar su reserva. 

Se eligió `bookings` por ser la ruta crítica del core del negocio, ya que si falla, se rompe la 
funcionalidad central de reserva.

### Umbral: ≥ 1 error en 5 minutos

- **Estadística:** `Sum` (se cuentan los errores del período; para "cosas que 
  fallaron" la suma es la opción correcta, no el promedio).
- **Periodo:** 5 minutos.
- **Umbral:** ≥ 1 error.

Un umbral tan bajo es apropiado **para el MVP** porque no hay tráfico base de 
usuarios reales que genere errores.

En cambio en **producción**, este umbral provocaría una **fatiga de alertas**
atendiendo tráfico real ya que incluiría timeouts, reintentos, etc, y una 
alarma que salta constantemente acaba siendo ignorada, de modo que, el día que haya un problema 
real, nadie le hará caso. Aquí se usaría un umbral **relativo** (error rate > X%) 
o **absoluto más alto** (p. ej. ≥ 5 errores en 5 min), que tolera el ruido de 
fondo y solo salta ante problemas reales.

### Notificaciones mediante SNS: patrón pub/sub desacoplado

La alarma no enviará el email directamente sino que primero **publica en un topic de SNS** y el 
topic reparte el aviso a sus suscriptores (en este caso, mi email). Esto desacopla la detección (la alarma) de la notificación (el canal) ya que se podrían agregar más destinos (SMS, Slack, una Lambda de auto-remediación) 
sin tocar la alarma.

Se configuraron dos disparadores:
- `alarm_actions` → notifica al pasar a **ALARM** (hay errores).
- `ok_actions` → notifica al volver a **OK** (recuperación del sistema), cerrando el ciclo del 
  incidente. Con esto, el equipo sabe que ya está resuelto y no sigue investigando.



## Consecuencias / trade-offs

### Lo que gano

- **Detección activa.** Paso de mirar logs cuando ya 
  sospecho de un problema, o cuando un usuario se queja a uno automatizado donde es el 
  sistema quien me avisa de los errores cuando aparecen.

- **Ciclo de incidente completo.** Con `alarm_actions` y `ok_actions` recibo 
  aviso tanto de la aparición del problema como de su recuperación, sin tener 
  que comprobar manualmente si ya se resolvió.

### Limitaciones

- **Cobertura parcial (un solo punto vigilado).** La alarma cubre únicamente 
  la métrica `Errors` de la Lambda `bookings`. Por lo que quedan puntos ciegos como los errores 
  de la Lambda `resources`, los fallos que ocurran en API Gateway antes de llegar 
  a la Lambda o problemas en DynamoDB 
  (throttling, latencia). Se priorizó la ruta crítica del core del negocio (reservar) 
  sobre una cobertura total debido a que una observabilidad completa requeriría alarmas 
  adicionales por componente y preferí centrarme en el MVP.

- **Solo detecto fallos no problemas de rendimiento** La métrica `Errors` cuenta 
  excepciones no capturadas (el sistema se rompe). No detecta un problema de **rendimiento**: 
  si una reserva tardara por ejemplo 8 segundos en vez de 200 ms, pues al tardar más de la cuenta, la Lambda respondería bien y la alarma no se enteraría. Ese 
  tipo de observación (latencia alta, timeouts cercanos al límite) se vigilaría 
  con una alarma sobre la métrica `Duration`, que no está contemplada en este MVP.

- **Umbral fijo, pendiente de revisión.** El umbral de ≥1 error es una decisión 
  consciente para el contexto actual (MVP sin tráfico real de usuarios). 
  Queda documentado como **deuda técnica conocida** ya que si hubiese tráfico 
  real, deberá recalibrarse a un umbral relativo (error rate) o absoluto más alto 
  para evitar la fatiga de alertas descrita en el apartado **Decisión**.