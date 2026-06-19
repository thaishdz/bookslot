#!/usr/bin/env bash

API_URL="https://fs8r8hnmu0.execute-api.eu-west-1.amazonaws.com/dev"

# 1. resetear el slot con booked=0
aws dynamodb update-item \
  --table-name bookslot-dev-bookings \
  --key '{"PK": {"S": "RESOURCE#gym-01"}, "SK": {"S": "SLOT#2026-12-25T18:00"}}' \
  --update-expression "SET booked = :zero" \
  --expression-attribute-values '{":zero": {"N": "0"}}' \
  --region eu-west-1 > /dev/null


# 2. función que hace UNA reserva con un dni basado en el número que recibe
reservar() {
  curl -s -o /dev/null -w "%{http_code}\n" -X POST "$API_URL/bookings" \
    -H "Content-Type: application/json" \
    -d "{\"resource_id\": \"gym-01\", \"datetime\": \"2026-12-25T18:00\", \"dni\": \"user-$1\"}"
}

# 3. xargs ejecuta shubshells pero los hijos no conocen lo que hay en el script padre, por eso:

export -f reservar # los hijos de xargs podrán ver la función reservar
export API_URL # los hijos podrán ver API_URL


# Lanza 5 reservas en paralelo (-P 5), cada una con un dni (user-número) distinto.
# El paralelismo simula las reservas simultáneas que provocan la race condition.
results=$(seq 5 | xargs -P 5 -I {} bash -c 'reservar {}')
#                 ↑ arranca un bash nuevo que ejecuta "reservar {}"


# sin bash -c:  xargs intenta ejecutar "reservar()" -> no es un comando/programa -> falla
# con bash -c:  xargs lanza un bash -> el bash SÍ sabe ejecutar funciones -> funciona 

confirmed=$(echo "$results" | grep -c "201")
denied=$(echo "$results" | grep -c "409")

CAPACITY=2
if [ "$confirmed" -eq "$CAPACITY" ]; then
  echo "✅ TEST OK: $confirmed reservas fueron confirmadas y $denied fueron rechazadas, sin overbooking"
else
  echo "❌ TEST FAIL: se esperaban $CAPACITY, se confirmaron $confirmed y rechazadas $denied"
fi