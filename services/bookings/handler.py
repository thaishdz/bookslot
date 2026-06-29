

import boto3
import json 
from botocore.exceptions import ClientError

dynamodb_client = boto3.client("dynamodb")

def lambda_handler(event, context):

    route = event["routeKey"]
    match route:
        case "POST /bookings":
            return create_booking(event)
        case "DELETE /bookings":
            return delete_booking(event)
    

def create_booking(event):
    booking_payload = json.loads(event["body"]) # datos de la reserva
    user_id = event["requestContext"]["authorizer"]["jwt"]["claims"]["sub"] # quien hace la reserva
    
    try:
        dynamodb_client.transact_write_items( 
            TransactItems=[
                {
                    'Update': {
                        'TableName': "bookslot-dev-bookings",
                        # En la tabla bookslot-dev-bookings, sobre el slot con esta PK+SK
                        'Key': {
                            'PK': {'S': f"RESOURCE#{booking_payload['resource_id']}"},
                            'SK': {'S': f"SLOT#{booking_payload['datetime']}"}
                        },
                        'UpdateExpression': 'SET #booked = #booked + :inc', # suma 1 a booked  
                        'ConditionExpression': '#booked < #capacity', # pero solo si booked < capacity,
                        'ExpressionAttributeNames' : {
                            '#booked' : 'booked',
                            '#capacity': 'capacity'
                        },
                        'ExpressionAttributeValues': {':inc': {'N': '1'}} # donde el incremento vale 1
                    }
                },
                {
                    'Put': {
                        'TableName': "bookslot-dev-bookings",
                        'Item': {
                           'PK': {'S': f"USER#{user_id}"},
                           'SK': {'S': f"BOOKING#{booking_payload['datetime']}"},
                           'resource_id': {'S': f"RESOURCE#{booking_payload['resource_id']}"},
                           'status': {'S': 'CONFIRMED'}
                        },
                        'ConditionExpression': 'attribute_not_exists(PK)'
                    }
                }
            ]
        )
        return { 
            "statusCode": 201, 
            "body": json.dumps({"message": "Booking confirmed"}) 
        }
    except ClientError as error:
        if error.response["Error"]["Code"] == "TransactionCanceledException": # Tipo de error generado por Transacciones
            reasons = error.response["CancellationReasons"] # Devuelve una lista con todas las operaciones de transaccion y te chiva la culpable
            if reasons[0]["Code"] == "ConditionalCheckFailed": # La posición en el array es la que identifica la operación culpable, no el código de error!!!
                return { 
                    "statusCode": 409, 
                    "body": json.dumps({"message": "Slot not available"}) 
                }
            if reasons[1]["Code"] == "ConditionalCheckFailed":
                return { 
                    "statusCode": 409, 
                    "body": json.dumps({"message": "Booking already exists"}) 
                }
        raise


def delete_booking(event):
    booking_payload = json.loads(event["body"])
    user_id = event["requestContext"]["authorizer"]["jwt"]["claims"]["sub"]

    try:
        dynamodb_client.transact_write_items(
            TransactItems=[
                {
                    'Update': {
                        'TableName': "bookslot-dev-bookings",
                        'Key': {
                            'PK': {'S': f"USER#{user_id}"},
                            'SK': {'S': f"BOOKING#{booking_payload['datetime']}"}
                        },
                    'UpdateExpression': 'SET #status = :cancelled', # pon status a CANCELLED SOLO SI
                    'ConditionExpression': '#status = :confirmed', # el status actual es CONFIRMED
                    'ExpressionAttributeNames': {'#status': 'status'},
                    'ExpressionAttributeValues': {
                        ':confirmed': {'S': 'CONFIRMED'},
                        ':cancelled': {'S': 'CANCELLED'},
                        }
                    },
                },
                {
                    'Update': {
                        'TableName': "bookslot-dev-bookings",
                        'Key': {
                            'PK': {'S': f"RESOURCE#{booking_payload['resource_id']}"},
                            'SK': {'S': f"SLOT#{booking_payload['datetime']}"}
                        },
                    'UpdateExpression': 'SET #booked = #booked - :decrement', 
                    'ConditionExpression': '#booked > :zero', # lo dejo como validacion defensiva aunque es muy improbable que se dé
                    'ExpressionAttributeNames' : {
                        '#booked' : 'booked',
                    },
                    'ExpressionAttributeValues': {
                        ':decrement': {'N': '1'},
                        ':zero': {'N': '0'}
                        } 
                    },  
                }
            ]
        )
        return { 
                "statusCode": 201, 
                "body": json.dumps({"message": "Booking cancelled"}) 
            }
    except ClientError as error:
        if error.response["Error"]["Code"] == "TransactionCanceledException":
            reasons = error.response["CancellationReasons"] 
            if reasons[0]["Code"] == "ConditionalCheckFailed": 
                return { 
                    "statusCode": 404, 
                    "body": json.dumps({"message": "Booking not found or already cancelled"}) 
                }
            if reasons[1]["Code"] == "ConditionalCheckFailed": 
                return {"statusCode": 404, "body": json.dumps({"message": "Slot not found"})}
        raise