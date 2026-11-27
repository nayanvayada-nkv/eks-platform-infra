"""Short-lived IAM login tokens for Aurora and ElastiCache (Valkey).

No passwords: the pod's identity (EKS Pod Identity) signs a token locally with SigV4.
The token is valid for 15 minutes and only for the database user / cache user that the
pod's IAM role allows. Nothing to store, rotate or leak.
"""

from urllib.parse import urlencode

import boto3
from botocore.model import ServiceId
from botocore.signers import RequestSigner

TOKEN_TTL_SECONDS = 900


def aurora_token(host: str, port: int, user: str, region: str, session=None) -> str:
    session = session or boto3.Session()
    rds = session.client("rds", region_name=region)
    return rds.generate_db_auth_token(DBHostname=host, Port=port, DBUsername=user, Region=region)


def elasticache_token(cache_name: str, user_id: str, region: str, session=None) -> str:
    """Presigned 'connect' request for a serverless cache, used as the AUTH password."""
    session = session or boto3.Session()
    signer = RequestSigner(
        ServiceId("elasticache"),
        region,
        "elasticache",
        "v4",
        session.get_credentials(),
        session.events,
    )
    query = urlencode({"Action": "connect", "User": user_id, "ResourceType": "ServerlessCache"})
    request = {
        "method": "GET",
        "url": f"https://{cache_name}/?{query}",
        "body": {},
        "headers": {},
        "context": {},
    }
    signed = signer.generate_presigned_url(
        request, operation_name="connect", expires_in=TOKEN_TTL_SECONDS, region_name=region
    )
    return signed.removeprefix("https://")
