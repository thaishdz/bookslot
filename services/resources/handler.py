

import boto3
import json 
from boto3.dynamodb.conditions import Key, Attr
from botocore.exceptions import ClientError
from decimal import Decimal

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("bookslot-dev-bookings")

def lambda_handler(event, context):
    # event   → todo lo que envía API Gateway (método, path, body, headers...)
    # context → metadatos de la ejecución (tiempo restante, request id...)

    routeKey = event["routeKey"]

    match routeKey:
        case "GET /resources":
           return get_resources(event)        
        case "POST /resources":
            return create_resource(event)
        case "GET /resources/{id}/slots":
            return get_resource_slots(event)
        case "POST /resources/{id}/slots":
            return create_slot(event)
        case _:
            return {
                "statusCode": 404
            }

def get_resources(event):
    response = table.scan(
        FilterExpression=Attr("SK").eq("INFO")
    )

    return {
        "statusCode": 200,
        "body": json.dumps(response["Items"])
    }

def create_resource(event):
    claims = event["requestContext"]["authorizer"]["jwt"]["claims"]
    groups = claims.get("cognito:groups", "")

    if "admins" not in groups:
        return { "statusCode": 403, "body": json.dumps({"message": "admin role required"}) }
    
    resource_dict = json.loads(event["body"])

    try:
        table.put_item(
            Item={
                'PK': f"RESOURCE#{resource_dict['resource_id']}",
                'SK': 'INFO',
                'name': resource_dict["name"],
                'location': resource_dict["location"]
        },
            ConditionExpression="attribute_not_exists(PK)"
        )

        return {
            "statusCode": 201,
            "body": json.dumps({"message": "Resource Created"})
        }
    except ClientError as error:
        if error.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return { "statusCode": 409, "body": json.dumps({"message": "Resource already exists"}) }
    raise   # si es otro error distinto, que se propague 

def get_resource_slots(event):
    resource_id = event["pathParameters"]["id"]
    response = table.query(
        KeyConditionExpression=Key("PK").eq(f"RESOURCE#{resource_id}") & Key("SK").begins_with("SLOT#")
    )
    slot_items = response["Items"]
    return {
            "statusCode": 200,
            "body": json.dumps(slot_items, default=decimal_default)
        }

def decimal_default(obj):
    if isinstance(obj, Decimal):
        return int(obj)       
    raise TypeError


def create_slot(event):
    claims = event["requestContext"]["authorizer"]["jwt"]["claims"]
    groups = claims.get("cognito:groups", "")

    if "admins" not in groups:
        return { "statusCode": 403, "body": json.dumps({"message": "admin role required"}) }

    resource_id = event["pathParameters"]["id"]
    slot_dict = json.loads(event["body"])
    try:

        table.put_item(
            Item={
                'PK': f"RESOURCE#{resource_id}",
                'SK': f"SLOT#{slot_dict['datetime']}",
                'capacity': slot_dict['capacity'], # capacity is defined by the resource owner
                'booked': 0
        },
            # Single-table: many items share the same PK (resource + its slots).
            # put_item evaluates the condition on the item with the FULL key (PK+SK),
            # so attribute_not_exists(PK) here means "this exact slot (PK+SK) doesn't exist yet".
            ConditionExpression="attribute_not_exists(PK)"
        )

        return {
            "statusCode": 201,
            "body": json.dumps({"message": "Slot Created"})
        }
    except ClientError as error:
        if error.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return { "statusCode": 409, "body": json.dumps({"message": "Slot already exists"}) }
        raise   # si es otro error distinto, que se propague