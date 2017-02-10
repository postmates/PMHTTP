//
//  SSLTests.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 2/9/17.
//  Copyright © 2017 Postmates. All rights reserved.
//

import XCTest
import PMHTTP

final class SSLTests: PMHTTPTestCase {
    static var httpsServer: HTTPServer!
    
    #if os(macOS)
    static var keychain: SecKeychain!
    
    private static func createKeychain(path: String) throws -> SecKeychain {
        let password = "password"
        return try path.withCString { (pathStr) -> SecKeychain in
            try password.withCString({ (passwordStr) -> SecKeychain in
                var keychain: SecKeychain?
                switch SecKeychainCreate(pathStr, UInt32(strlen(password)), UnsafeRawPointer(passwordStr), false, nil, &keychain) {
                case errSecSuccess:
                    return keychain!
                case let status:
                    if let str = SecCopyErrorMessageString(status, nil) {
                        throw KeychainError.error(str as String)
                    } else {
                        throw KeychainError.unknown(status)
                    }
                }
            })
        }
    }
    
    private enum KeychainError: Error {
        case error(String)
        case unknown(OSStatus)
    }
    
    private static func importPKCS12(_ pkcs12: Data, password: String?, into keychain: SecKeychain) throws -> (SecIdentity, certificates: [SecCertificate]) {
        let options: NSMutableDictionary = [:]
        options[kSecImportExportPassphrase] = password as CFString?
        options[kSecImportExportKeychain] = keychain
        var items: CFArray?
        switch SecPKCS12Import(pkcs12 as CFData, options, &items) {
        case errSecSuccess:
            // Find the first SecIdentity in the items, and collect all certificates
            var identity: SecIdentity?
            var certificates: [SecCertificate] = []
            for item in items! as NSArray {
                let item = item as! NSDictionary
                if identity == nil, let ident = item[kSecImportItemIdentity] {
                    identity = (ident as! SecIdentity)
                }
                if let certs = item[kSecImportItemCertChain] {
                    certificates.append(contentsOf: certs as! [SecCertificate])
                }
            }
            if let identity = identity {
                return (identity, certificates: certificates)
            } else {
                throw PKCS12Error.noIdentity
            }
        case errSecDecode:
            throw PKCS12Error.decode
        case errSecAuthFailed:
            throw PKCS12Error.authFailed
        case let status:
            throw PKCS12Error.unknown(status)
        }
    }
    #else
    private static func importPKCS12(_ pkcs12: Data, password: String?) throws -> (SecIdentity, certificates: [SecCertificate]) {
        let options: NSDictionary = password.map({ [kSecImportExportPassphrase: $0] }) ?? [:]
        var items: CFArray?
        switch SecPKCS12Import(pkcs12 as CFData, options, &items) {
        case errSecSuccess:
            // Find the first SecIdentity in the items, and collect all certificates
            var identity: SecIdentity?
            var certificates: [SecCertificate] = []
            for item in items! as NSArray {
                let item = item as! NSDictionary
                if identity == nil, let ident = item[kSecImportItemIdentity] {
                    identity = (ident as! SecIdentity)
                }
                if let certs = item[kSecImportItemCertChain] {
                    certificates.append(contentsOf: certs as! [SecCertificate])
                }
            }
            if let identity = identity {
                return (identity, certificates: certificates)
            } else {
                throw PKCS12Error.noIdentity
            }
        case errSecDecode:
            throw PKCS12Error.decode
        case errSecAuthFailed:
            throw PKCS12Error.authFailed
        case let status:
            throw PKCS12Error.unknown(status)
        }
    }
    #endif
    
    private enum PKCS12Error: Error {
        /// The PKCS #12 blob couldn't be read or was malformed.
        case decode
        /// The password was not correct or the data in the PKCS #12 blob was damaged.
        case authFailed
        /// the PKCS #12 blob did not include an identity.
        case noIdentity
        /// An unknown error was returned.
        case unknown(OSStatus)
    }
    
    override class func setUp() {
        super.setUp()
        let data = try! Data(contentsOf: Bundle(for: SSLTests.self).url(forResource: "PMHTTP Certificates", withExtension: "p12")!)
        #if os(macOS)
            let keychainPath = NSTemporaryDirectory() + "/PMHTTP_Tests.keychain"
            try? FileManager.default.removeItem(atPath: keychainPath)
            keychain = try! createKeychain(path: keychainPath)
            let (identity, certificates) = try! importPKCS12(data, password: "PMHTTP", into: keychain)
        #else
            let (identity, certificates) = try! importPKCS12(data, password: "PMHTTP")
        #endif
        httpsServer = try! HTTPServer(identity: identity, certificates: certificates)
    }
    
    override class func tearDown() {
        httpsServer?.invalidate()
        httpsServer = nil
        #if os(macOS)
            if let keychain = keychain {
                SecKeychainDelete(keychain)
            }
            keychain = nil
        #endif
        super.tearDown()
    }
    
    override func setUp() {
        super.setUp()
        HTTP.environment = HTTPManagerEnvironment(string: "https://\(httpsServer.address)")!
    }
    
    override func tearDown() {
        HTTP.sessionLevelAuthenticationHandler = nil
        super.tearDown()
    }
    
    var httpsServer: HTTPServer! {
        return SSLTests.httpsServer
    }
    
    func testSSLRejection() {
        // If we don't set sessionLevelAuthenticationHandler, the certificate we're using on the server won't pass validation
        expectationForRequestFailure(HTTP.request(GET: "/foo")) { (task, response, error) in
            switch error {
            case URLError.serverCertificateUntrusted: break
            default:
                XCTFail("expected URLError.serverCertificateUntrusted, found \(error) - request error")
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testSSLAuthenticationHandlerAcceptAll() {
        HTTP.sessionLevelAuthenticationHandler = { (httpManager, challenge, completion) in
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust {
                completion(.useCredential, URLCredential(trust: trust))
            } else {
                completion(.performDefaultHandling, nil)
            }
        }
        expectationForHTTPRequest(httpsServer, path: "foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .ok))
        }
        expectationForRequestSuccess(HTTP.request(GET: "/foo"))
        waitForExpectations(timeout: 5, handler: nil)
    }
}
