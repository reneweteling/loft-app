---
title: SigV4 Signing
tags: [reference, sigv4, aws, signing, security]
project: Loft
created: 2026-04-23
---

# SigV4 Signing

AWS Signature Version 4 (SigV4) is the authentication scheme used for all AWS API requests, including S3 `PutObject` and presigned GET URLs. Loft delegates signing to AWS SDK Swift, but understanding the algorithm helps when debugging authentication failures or implementing custom signing (e.g. for non-SDK endpoints).

## Overview

SigV4 works by computing an HMAC-SHA256 signature over a canonical representation of the HTTP request, then attaching it either in an `Authorization` header (standard requests) or in query string parameters (presigned URLs). The signing key is derived from the secret access key combined with the date, region, and service — so it is time- and scope-limited.

## Four-step algorithm

### Step 1 — Canonical request

Construct a single string representing the request in a normalized form:

```
CanonicalRequest =
    HTTPMethod + "\n" +
    CanonicalURI + "\n" +
    CanonicalQueryString + "\n" +
    CanonicalHeaders + "\n" +
    SignedHeaders + "\n" +
    HexEncode(Hash(RequestPayload))
```

- **HTTPMethod**: uppercase verb (`PUT`, `GET`, etc.)
- **CanonicalURI**: URI-encoded path with `/` separators preserved; each path segment percent-encoded (spaces → `%20`)
- **CanonicalQueryString**: query parameters sorted lexicographically by key, then by value; each key and value URI-encoded; joined as `key=value&key2=value2`
- **CanonicalHeaders**: lowercase header name + `:` + trimmed value + `\n` for each signed header, sorted by header name
- **SignedHeaders**: semicolon-separated sorted lowercase header names (e.g. `host;x-amz-content-sha256;x-amz-date`)
- **HexEncode(Hash(RequestPayload))**: lowercase hex SHA-256 of the request body; use the literal string `UNSIGNED-PAYLOAD` for presigned GET URLs

```
# Example canonical request for PutObject:
PUT
/pub/2026/04/23/aB3xY7mNqP-file.png

content-type:image/png
host:my-bucket.s3.us-east-1.amazonaws.com
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date:20260423T120000Z
x-amz-tagging:app%3Dloft%26ttl%3Dnone%26uploaded_at%3D1745400000

content-type;host;x-amz-content-sha256;x-amz-date;x-amz-tagging
<sha256-of-file-body>
```

### Step 2 — String to sign

```
StringToSign =
    "AWS4-HMAC-SHA256" + "\n" +
    ISO8601BasicDateTime + "\n" +
    CredentialScope + "\n" +
    HexEncode(Hash(CanonicalRequest))
```

- **ISO8601BasicDateTime**: current UTC time as `YYYYMMDDTHHMMSSZ` (e.g. `20260423T120000Z`)
- **CredentialScope**: `YYYYMMDD/region/s3/aws4_request` (e.g. `20260423/us-east-1/s3/aws4_request`)
- **HexEncode(Hash(CanonicalRequest))**: lowercase hex SHA-256 of the canonical request string from Step 1

```
AWS4-HMAC-SHA256
20260423T120000Z
20260423/us-east-1/s3/aws4_request
<sha256-of-canonical-request>
```

### Step 3 — Signing key

Derive a signing key by chaining HMAC-SHA256 operations. This is the "key derivation" that scopes the secret to a specific date, region, and service:

```
kSecret  = "AWS4" + SecretAccessKey          (as UTF-8 bytes)
kDate    = HMAC-SHA256(kSecret,  "20260423")
kRegion  = HMAC-SHA256(kDate,    "us-east-1")
kService = HMAC-SHA256(kRegion,  "s3")
kSigning = HMAC-SHA256(kService, "aws4_request")
```

> [!tip] Key caching
> The signing key is stable for a given (secret, date, region, service) tuple. Compute it once per day and reuse it across requests to avoid redundant HMAC operations. AWS SDK Swift handles this internally.

### Step 4 — Signature

```
Signature = HexEncode(HMAC-SHA256(kSigning, StringToSign))
```

The result is a 64-character lowercase hex string.

## Attaching the signature

### Standard request (Authorization header)

```
Authorization: AWS4-HMAC-SHA256
  Credential=AKIAIOSFODNN7EXAMPLE/20260423/us-east-1/s3/aws4_request,
  SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date;x-amz-tagging,
  Signature=<64-hex-chars>
```

Also include:
- `x-amz-date: 20260423T120000Z`
- `x-amz-content-sha256: <payload-sha256>` (required for S3)

### Presigned URL (query string)

Move credentials into query parameters instead of the Authorization header. See [[Presigned URL Notes]] for the full parameter list.

## Pseudo-code summary

```
function signRequest(method, uri, headers, body, accessKeyId, secretKey, region, service, datetime):
    date = datetime[0:8]                          // "20260423"

    canonicalRequest = buildCanonicalRequest(method, uri, headers, body)
    credentialScope  = date + "/" + region + "/" + service + "/aws4_request"
    stringToSign     = "AWS4-HMAC-SHA256" + "\n"
                     + datetime + "\n"
                     + credentialScope + "\n"
                     + sha256hex(canonicalRequest)

    kDate    = hmacSHA256("AWS4" + secretKey, date)
    kRegion  = hmacSHA256(kDate,  region)
    kService = hmacSHA256(kRegion, service)
    kSigning = hmacSHA256(kService, "aws4_request")
    signature = hmacSHA256hex(kSigning, stringToSign)

    return "AWS4-HMAC-SHA256 "
         + "Credential=" + accessKeyId + "/" + credentialScope + ", "
         + "SignedHeaders=" + signedHeaderNames + ", "
         + "Signature=" + signature
```

## Common signing mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Unsigned `x-amz-tagging` header | `SignatureDoesNotMatch` | Include `x-amz-tagging` in `SignedHeaders` |
| Wrong payload hash | `SignatureDoesNotMatch` | Re-read file before hashing; confirm no transfer encoding |
| Clock skew > 15 minutes | `RequestTimeTooSkewed` | Sync system clock; AWS rejects requests more than 15 min from server time |
| Percent-encoding mismatch | `SignatureDoesNotMatch` | URI-encode path segments exactly as AWS specifies (RFC 3986, uppercase hex) |
| Wrong region | `AuthorizationHeaderMalformed` | Credential scope region must match the bucket's actual region |
| Signing `content-length` | `UnsignedPayload` or extra signature mismatch | Do not include `content-length` in `SignedHeaders` for S3 |

> [!info] AWS SDK Swift handles all of this
> You will not need to implement SigV4 manually. AWS SDK Swift signs every request automatically using the configured credentials. This page exists to explain what happens under the hood when debugging authentication errors (e.g. inspecting a raw HTTP request in a proxy like Proxyman).

## Related

- [[Presigned URL Notes]]
- [[S3 Multipart Notes]]
- [[Upload Pipeline]]
- [[Settings]]
- [[Glossary]]
- [[Loft Overview]]
