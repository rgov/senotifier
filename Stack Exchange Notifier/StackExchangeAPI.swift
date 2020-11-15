//
//  StackExchangeAPI.swift
//  Stack Exchange Notifier
//
//  Created by Ryan Govostes on 11/15/20.
//

import Foundation

import p2_OAuth2


class OAuth2CodeGrantStackExchange: OAuth2ImplicitGrant {
    // Copied from OAuth2CodeGrantNoTokenType
    override open func assureCorrectBearerType(_ params: OAuth2JSON) throws {
    }
    
    // Do not check the 'state' parameter
    override open func assureAccessTokenParamsAreValid(_ params: OAuth2JSON) throws {
    }
}


class OAuth2DataLoaderStackExchange: OAuth2DataLoader {
    /// The OAuth2 library does not understand StackExchange's error messages, so unfortunately we
    /// need to re-implement part of the library to know when to automatically attempt authentication.
    override func perform(request: URLRequest, retry: Bool, callback: @escaping ((OAuth2Response) -> Void)) {
        // Modify the request to include the access token and key parameters
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "access_token", value: oauth2.accessToken ?? ""),
            URLQueryItem(name: "key", value: oauth2.clientSecret ?? ""),
        ]
        let modifiedRequest = URLRequest(url: components.url!)
        
        // Allow the superclass to attempt the modified request, and then let us
        // interpret the response.
        super.perform(request: modifiedRequest, retry: retry) { response in
            // If we succeded, return to caller
            if response.response.statusCode == 200 {
                callback(response)
                return
            }
            
            // Stop here if we do not want to attempt a retry
            if !retry { return }
            
            // Enqueue the original request and attempt it again after auth
            self.enqueue(request: request, callback: callback)
            self.oauth2.forgetTokens()
            self.attemptToAuthorize() { json, error in
                // We do not have access to retryAll() or throwAllAway(), so we
                // have to re-implement them to re-process the queue.
                self.dequeueAndApply() { req in
                    if json != nil {
                        var request = req.request
                        do {
                            try request.sign(with: self.oauth2)
                            self.perform(request: request, retry: false, callback: req.callback)
                        }
                        catch let error {
                            NSLog("OAuth2.DataLoader.retryAll(): \(error)")
                        }
                    } else {
                        let res = OAuth2Response(data: nil, request: req.request, response: HTTPURLResponse(), error: error ?? OAuth2Error.requestCancelled)
                        req.callback(res)
                    }
                }
            }
            
        }
    }
}


@objc
public class StackExchangeAPI: NSObject {
    private var oauth2: OAuth2CodeGrantStackExchange
    private var loader: OAuth2DataLoaderStackExchange

    @objc
    public override init() {
        oauth2 = OAuth2CodeGrantStackExchange(settings: [
            // These are specific to Stack Exchange Notifier. Please don't use them in
            // other apps, register to get your own at:
            //     http://stackapps.com/apps/oauth/register
            "client_id": "81",
            "client_secret": "JBpdN2wRVnHTq9E*uuyTPQ((",
            
            "authorize_uri": "https://stackexchange.com/oauth/dialog",
            "token_uri": "https://stackexchange.com/oauth/access_token",
            "scope": "read_inbox no_expiry",

            // We do not have a custom URL handler, so we need to run the flow
            // inside an embedded web browser and catch the successful login.
            "redirect_uris": ["https://stackexchange.com/oauth/login_success"],
        ] as OAuth2JSON)
        
        // This loader will be used to request URLs
        loader = OAuth2DataLoaderStackExchange(oauth2: oauth2)
        
        // Use an embedded browser window for authentication
        oauth2.authConfig.authorizeEmbedded = true
        
        // Trace requests when running a debug build
        //#if DEBUG
            oauth2.logger = OAuth2DebugLogger(.trace)
        //#endif
    }
    
    private var urlForUnreadMessages: URL? {
        get {
            return URL(string: "https://api.stackexchange.com/2.0/inbox/unread?filter=withbody")
        }
    }
    
    private var urlForInvalidateToken: URL? {
        guard (oauth2.accessToken != nil) else { return nil }
        return URL(string: "https://api.stackexchange.com/2.0/access-tokens/\(oauth2.accessToken!)/invalidate")
    }
    
    @objc
    public func getUnreadMessages() {
        let req = oauth2.request(forURL: urlForUnreadMessages!)
        loader.perform(request: req) { response in
            do {
                let dict = try response.responseJSON()
                DispatchQueue.main.async {
                    print("lol \(dict)")
                }
            }
            catch let error {
                DispatchQueue.main.async {
                    print("wtf \(error)")
                }
            }
        }
    }
    
    @objc
    public func invalidateAccessToken() {
        let task = URLSession.shared.dataTask(with: urlForInvalidateToken!) {(data, response, error) in
            self.oauth2.forgetTokens()
        }
        task.resume()
    }
}
