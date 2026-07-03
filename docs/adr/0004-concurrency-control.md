# ADR-0004: Control de concurrencia

## Contexto

El problema surge cuando varias reservas llegan de forma **simultánea**.

Un enfoque simple gestionaría cada reserva en dos pasos:
1. **Leer** el contador de plazas ocupadas y comprobar si queda hueco.
2. **Escribir** el contador incrementado en uno.

Bajo concurrencia, este enfoque "leer-comprobar-escribir" falla, porque entre 
el paso 1 y el paso 2 hay una ventana de tiempo. Si dos peticiones leen el 
contador **antes** de que la otra lo haya actualizado, ambas ven el mismo valor 
"viejo", ambas creen que queda sitio, y ambas reservan. Esto se conoce como 
**condición de carrera** (*race condition*), es decir, el resultado depende del orden 
en que se entrelazan las operaciones.

![problema-concurrencia](../assets/problema-concurrencia.png)

Ejemplo: una actividad con 3 plazas libres recibe 7 peticiones a la vez. Si 
todas leen "quedan plazas" antes de que ninguna haya escrito, el sistema 
confirma las 7 reservas para 3 plazas. El sistema no se entera de que se 
agotaron, porque cada petición tomó su decisión con información obsoleta.

El reto, es garantizar que la comprobación de disponibilidad y la 
actualización del contador ocurran de forma **atómica**, sin que 
ninguna otra operación pueda colarse entre ambas.

## Opciones consideradas

### Opción 1: Bloqueo (locking)
Consiste en bloquear el slot mientras se procesa una reserva, de modo que 
las demás peticiones esperen su turno y se atiendan de una en una de forma serializada. 
Esto elimina la "race condition", pero tiene un alto coste a nivel de:
- **Rendimiento:** las reservas se procesan secuencialmente, creando un cuello 
  de botella bajo alta demanda (justo cuando más reservas simultáneas llegan).
- **Complejidad:** hay que gestionar manualmente el ciclo de vida del bloqueo (obtenerlo y 
  liberarlo) y manejar casos problemáticos, como qué ocurre si el proceso que 
  tiene el bloqueo falla y nunca lo libera (deadlock).

### Opción 2: Operación atómica condicional
DynamoDB permite ejecutar una escritura condicional (`ConditionExpression`) de 
forma **atómica**, esto quiere decir que comprueba una condición y solo si se cumple, escribe todo
en una única operación. Esto elimina la gestión manual del bloqueo que requería 
la Opción 1. No se bloquea a nadie ni se hace esperar,
esto elimina la ventana de tiempo que antes comentábamos entre el comprobar y el escribir donde 
ocurría la race condition.

Para la reserva, la condición es `booked < capacity`, esto es, incrementa el contador 
solo si queda hueco. Si dos peticiones concurrentes intentan reservar la última 
plaza, DynamoDB serializa internamente las operaciones atómicas y solo una pasa 
la condición; la otra la ve ya incumplida y es rechazada.


## Decisión

Se opta por la **operación atómica condicional** (Opción 2), descartando el 
locking por su coste en rendimiento y complejidad.

![problema-concurrencia](../assets/solucion-concurrencia.png)

Sin embargo, una reserva no implica una única escritura, sino **dos** que deben 
ocurrir juntas:

1. **Incrementar el contador `booked`** del slot, con la condición 
   `booked < capacity` (solo si queda hueco).
2. **Crear la reserva** (`USER#{dni}` / `BOOKING#{datetime}`) con su estado 
   `CONFIRMED`.

Si estas dos escrituras fueran independientes, podrían quedar **descuadradas**: 
por ejemplo, que el contador suba pero la creación de la reserva falle, dejando 
una plaza ocupada sin reserva real que la respalde.

Para evitarlo, ambas escrituras se agrupan en una **transacción** 
(`transact_write_items`), que garantiza la atomicidad, es decir, o se aplican 
las dos, o ninguna. Si cualquiera de las condiciones falla, toda la transacción 
se cancela y el estado queda intacto.

Además, la escritura de la reserva incluye la condición `attribute_not_exists(PK)`, 
que aporta **idempotencia**, si un usuario reintenta la misma reserva (por un 
fallo de red, le dió dos veces al botón de reservar, etc.), la segunda no se duplica ni vuelve a 
incrementar el contador, porque la reserva ya existe y la condición la rechaza.

En resumen, el control de concurrencia se apoya en tres garantías de DynamoDB:
- **Atomicidad condicional** (`booked < capacity`) → previene el overbooking.
- **Transaccionalidad** (`transact_write_items`) → evita estados descuadrados.
- **Idempotencia** (`attribute_not_exists`) → evita reservas duplicadas.

## Consecuencias

### Ventajas
- **Sin overbooking bajo concurrencia:** la condición atómica garantiza que 
  nunca se confirman más reservas que la capacidad, sin importar cuántas 
  peticiones lleguen a la vez.
- **Sin gestión de bloqueos:** al no usar locking, no hay que administrar 
  manualmente los locks ni manejar deadlocks. DynamoDB serializa las 
  operaciones internamente.
- **Datos siempre consistentes:** la transacción asegura que el contador y las 
  reservas nunca quedan descuadrados.

### Limitaciones y trade-offs
- **Coste de las transacciones:** `transact_write_items` consume más capacidad 
  (aproximadamente el doble) y es algo más lento que escrituras sueltas. Se 
  asume este coste porque la consistencia es la promesa central del sistema.

- **Mensaje de error genérico:** "slot fully" y "Slot not found" producen el 
  mismo `ConditionalCheckFailed` en la misma operación de la transacción, por lo 
  que no se distinguen sin una lectura previa. Se optó por un mensaje genérico 
  ("Slot not available") en lugar de añadir un `get_item` de validación previa, 
  ya que esa lectura añadiría latencia y se volvería a una race 
  condition (el slot podría llenarse entre la lectura y la transacción). 
  Mantener la operación en un solo paso atómico era preferible.

## Validación mediante script

Para probar que el control de concurrencia funciona, se creó un 
script de prueba (`scripts/test-concurrency.sh`) que lanza múltiples reservas 
**en paralelo** sobre un mismo slot, usando `xargs -P` para forzar la 
simultaneidad y un DNI distinto por petición (de modo que compitan como usuarios 
reales y no se bloqueen por idempotencia).

Sobre un slot con `capacity = 2`, lanzando 5 reservas simultáneas, el resultado 
es:
- **2 reservas confirmadas** (HTTP 201) — exactamente la capacidad.
- **3 reservas rechazadas** (HTTP 409) — las que llegan sin plazas disponibles.

El contador `booked` queda en 2, que coincide con las reservas confirmadas. El 
script verifica que el número de confirmadas es igual a la 
capacidad, lo que se traducirá en éxito o fallo.

Esto confirma que el sistema reparte las plazas de forma correcta bajo 
concurrencia "real" y garantiza que se confirman **exactamente** las plazas 
disponibles, independientemente del orden imprevisible en que se procesan las 
peticiones paralelas.