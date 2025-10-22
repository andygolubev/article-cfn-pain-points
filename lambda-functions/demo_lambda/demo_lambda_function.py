import json
import os
from lambda_layer.common_service import get_hello_world
def lambda_handler(event, context):
    """
    Simple Lambda function for article demo that uses common service
    """
    # Get greeting from common service
    greeting = get_hello_world()
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'OK',
            'greeting': greeting,
            'timestamp': context.aws_request_id
        })
    }