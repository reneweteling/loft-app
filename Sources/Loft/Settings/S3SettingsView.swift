import SwiftUI

struct S3SettingsView: View {
    @EnvironmentObject var config: AppConfig
    @State private var accessKey: String = ""
    @State private var secretKey: String = ""
    @State private var testResult: String = ""
    @State private var testing: Bool = false

    var body: some View {
        Form {
            Section {
                Text("Loft works with any S3-compatible storage: AWS S3, Cloudflare R2, MinIO, Backblaze B2, DigitalOcean Spaces, Wasabi, Hetzner, Scaleway and more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Credentials") {
                TextField("Access Key ID", text: $accessKey)
                    .textFieldStyle(.roundedBorder)
                SecureField("Secret Access Key", text: $secretKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save to Keychain") {
                        KeychainStore.setAccessKey(accessKey)
                        KeychainStore.setSecretKey(secretKey)
                        config.refreshKeychainStatus()
                        testResult = "Saved."
                    }
                    Button("Clear") {
                        KeychainStore.clear()
                        accessKey = ""
                        secretKey = ""
                        config.refreshKeychainStatus()
                        testResult = "Cleared."
                    }
                }
            }

            Section("Bucket") {
                TextField("Region", text: $config.region)
                    .textFieldStyle(.roundedBorder)
                TextField("Bucket name", text: $config.bucket)
                    .textFieldStyle(.roundedBorder)
                TextField("Endpoint (optional)", text: $config.endpoint,
                          prompt: Text("https://... — leave blank for AWS S3"))
                    .textFieldStyle(.roundedBorder)
                Text("Using something other than AWS S3? Enter your provider's endpoint URL here, e.g. https://<account-id>.r2.cloudflarestorage.com for Cloudflare R2 or https://s3.eu-central-1.wasabisys.com for Wasabi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Force path-style URLs (required for MinIO)",
                       isOn: $config.forcePathStyle)
                if config.bucket.contains(".") {
                    Text("Bucket name contains dots — path-style will be used automatically to avoid a TLS wildcard mismatch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Public URL") {
                TextField("CDN base URL (optional)", text: $config.cdnBaseURL,
                          prompt: Text("https://cdn.example.com"))
                    .textFieldStyle(.roundedBorder)
                Text("When set, Public-pane URLs use this prefix instead of the raw S3 URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button(action: test) {
                        if testing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(testing || config.bucket.isEmpty)
                    Spacer()
                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.lowercased().contains("ok") ? .green : .secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            let (ak, sk) = await Task.detached(priority: .userInitiated) {
                (KeychainStore.accessKey() ?? "", KeychainStore.secretKey() ?? "")
            }.value
            accessKey = ak
            secretKey = sk
        }
    }

    private func test() {
        testing = true
        testResult = "Testing..."
        Task {
            defer { Task { @MainActor in testing = false } }
            do {
                guard let ak = KeychainStore.accessKey(),
                      let sk = KeychainStore.secretKey() else {
                    await MainActor.run { testResult = "No credentials saved." }
                    return
                }
                let creds = SigV4Credentials(accessKeyId: ak, secretAccessKey: sk)
                let builder = URLBuilder(region: config.region,
                                         bucket: config.bucket,
                                         endpointOverride: config.endpoint.isEmpty ? nil : config.endpoint,
                                         forcePathStyle: config.forcePathStyle || !config.endpoint.isEmpty,
                                         cdnBaseURL: nil)
                let url = builder.apiBaseURL()
                let signed = try SigV4Signer.sign(method: "HEAD",
                                                  url: url,
                                                  region: config.region,
                                                  credentials: creds,
                                                  bodyHash: SigV4Signer.hexSHA256(""))
                var req = URLRequest(url: url)
                req.httpMethod = "HEAD"
                for (k, v) in signed { req.setValue(v, forHTTPHeaderField: k) }
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse {
                    await MainActor.run {
                        testResult = (200..<300).contains(http.statusCode)
                            ? "OK (HTTP \(http.statusCode))"
                            : "Failed: HTTP \(http.statusCode)"
                    }
                } else {
                    await MainActor.run { testResult = "Invalid response" }
                }
            } catch {
                await MainActor.run { testResult = "Error: \(error.localizedDescription)" }
            }
        }
    }
}

