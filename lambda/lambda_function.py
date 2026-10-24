import os
import json
import time
import base64
import boto3

s3 = boto3.client("s3")

FILES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
    "/cv.pdf": ("cv.pdf", "application/pdf"),
}


def lambda_handler(event, context):
    start = time.time()
    path = event.get("rawPath", "/")

    if path in FILES:
        name, ctype = FILES[path]
        try:
            body = s3.get_object(
                Bucket=os.environ["BUCKET"],
                Key=os.environ["PREFIX"] + name,
            )["Body"].read()
            headers = {"Content-Type": ctype}
            if name == "index.html":
                text = body.decode("utf-8").replace(
                    "{{HOSTED_ON}}", "Lambda " + context.function_name
                )
                headers["Cache-Control"] = "max-age=60"
                resp = {"statusCode": 200, "headers": headers, "body": text}
            elif name.endswith(".pdf"):
                resp = {
                    "statusCode": 200,
                    "headers": headers,
                    "body": base64.b64encode(body).decode("ascii"),
                    "isBase64Encoded": True,
                }
            else:
                resp = {"statusCode": 200, "headers": headers, "body": body.decode("utf-8")}
        except Exception as e:
            print("ERROR", repr(e))
            resp = {
                "statusCode": 500,
                "headers": {"Content-Type": "text/html"},
                "body": "<h1>500 Server Error</h1>",
            }
    else:
        resp = {
            "statusCode": 404,
            "headers": {"Content-Type": "text/html"},
            "body": "<h1>404 Not Found</h1><p>No such page.</p>",
        }

    print(json.dumps({
        "fn": context.function_name,
        "path": path,
        "status": resp["statusCode"],
        "ms": int((time.time() - start) * 1000),
    }))
    return resp
