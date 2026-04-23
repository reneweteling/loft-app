---
title: S3 Multipart Notes
tags: [reference, s3, multipart, aws]
project: Loft
created: 2026-04-23
---

# S3 Multipart Notes

Gotchas, constraints, and operational notes for S3 multipart upload, as relevant to Loft's [[Upload Pipeline]].

## Core constraints

| Constraint | Value | Notes |
|---|---|---|
| Minimum part size | 5 MiB (5,242,880 bytes) | Applies to every part **except the last**. AWS returns `EntityTooSmall` on `CompleteMultipartUpload` if violated. |
| Maximum part count | 10,000 parts | Part numbers are 1-indexed. Exceeding this limit causes the upload to fail. |
| Maximum object size | 5 TiB (5,497,558,138,880 bytes) | Hard limit for a single S3 object regardless of method. |
| Minimum file size to use multipart | 5 MB (Loft threshold) | Below this, Loft uses a single `PutObject`. AWS itself allows multipart for any size but single `PutObject` is simpler and cheaper for small files. |
| Maximum part size | 5 GiB | No real-world constraint — Loft's 8 MB parts are far below this. |
| Upload ID lifetime | 7 days by default | Incomplete multipart uploads accumulate storage costs. Always abort on failure. |

> [!warning] The 5 MiB floor is per-part, not per-file
> The constraint is that each part (except the last) must be at least 5 MiB. A 6 MiB file split into two 3 MiB parts will fail. Loft uses 8 MB parts to satisfy this floor with margin.

> [!warning] Abort on failure — always
> An incomplete multipart upload leaves all uploaded parts in storage, accruing S3 costs, until either `AbortMultipartUpload` is called or an abort lifecycle rule fires. Loft calls `abortMultipartUpload` before any retry attempt and on final failure. Configure a bucket-level lifecycle rule to abort incomplete multipart uploads after 1 day as a safety net:
> ```json
> {
>   "Rules": [{
>     "ID": "abort-incomplete-multipart",
>     "Status": "Enabled",
>     "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 1 }
>   }]
> }
> ```

## Part numbering

- Part numbers are integers from **1 to 10,000** (inclusive).
- Parts can be uploaded in any order.
- The final `CompleteMultipartUpload` request includes a list of `(partNumber, eTag)` pairs. AWS reassembles the object in part number order, not upload order.
- Loft uploads parts in sequential part-number order within a `TaskGroup` but AWS does not require this.

## ETag behaviour

- Each `UploadPart` response includes an `ETag` header — this is the MD5 of the part data (quoted string).
- `CompleteMultipartUpload` requires these ETags to be passed back exactly.
- The `ETag` of the assembled object returned by `CompleteMultipartUpload` is **not** an MD5 of the full file. It is computed as `MD5(concatenated-part-MD5s)-{partCount}` (e.g. `"d8e8fca2dc0f896fd7cb4cb0031ba249-3"`). Do not use this ETag to verify file integrity end-to-end.

> [!info] Integrity verification
> For end-to-end integrity verification on multipart uploads, use the `x-amz-checksum-*` headers (CRC32, CRC32C, SHA-1, or SHA-256) introduced in 2022. AWS SDK Swift supports these. Loft v1 does not use them (uploads are verified by the success response from `CompleteMultipartUpload`), but they are worth adding in a polish pass.

## CRC / MD5 considerations

- `PutObject` for single uploads: AWS verifies the `Content-MD5` header if supplied. AWS SDK Swift computes and sends it automatically.
- Multipart `UploadPart`: SDK also handles per-part MD5 automatically.
- Do not attempt to manually set `Content-MD5` on the `CompleteMultipartUpload` request — that API call has no body to hash.

## Cost implications

- Each part upload is billed as an S3 API request (`PUT`).
- Storage for in-progress parts is billed at the standard S3 storage rate.
- Aborting cleans up part storage immediately.
- Rule of thumb: multipart is cost-neutral to single `PutObject` for the same file; the extra part requests are small compared to data transfer costs for large files.

## Relevant AWS SDK Swift calls

```swift
// 1. Initiate
let createOutput = try await s3.createMultipartUpload(input: .init(
    bucket: bucket,
    key: key,
    acl: pane.visibility == .public ? .publicRead : nil,
    tagging: "app=loft&ttl=\(pane.ttlTag)&uploaded_at=\(Int(Date().timeIntervalSince1970))"
))
let uploadId = createOutput.uploadId!

// 2. Upload parts concurrently
var completedParts: [S3ClientTypes.CompletedPart] = []
try await withThrowingTaskGroup(of: S3ClientTypes.CompletedPart.self) { group in
    for (index, partData) in parts.enumerated() {
        group.addTask {
            let partOutput = try await s3.uploadPart(input: .init(
                body: .data(partData),
                bucket: bucket,
                key: key,
                partNumber: index + 1,
                uploadId: uploadId
            ))
            return .init(eTag: partOutput.eTag, partNumber: index + 1)
        }
        if group.count >= 4 { completedParts.append(try await group.next()!) }
    }
    for try await part in group { completedParts.append(part) }
}

// 3. Complete
_ = try await s3.completeMultipartUpload(input: .init(
    bucket: bucket,
    key: key,
    multipartUpload: .init(parts: completedParts.sorted { $0.partNumber! < $1.partNumber! }),
    uploadId: uploadId
))

// On any failure:
_ = try? await s3.abortMultipartUpload(input: .init(
    bucket: bucket, key: key, uploadId: uploadId
))
```

## Related

- [[Upload Pipeline]]
- [[Presigned URL Notes]]
- [[SigV4 Signing]]
- [[Architecture Overview]]
- [[Loft Overview]]
