import Flutter
import UIKit
import JavaScriptCore

public class SwiftFlutterProxyPlugin: NSObject, FlutterPlugin {
  static var proxyCache : [String: [String: Any]] = [:]
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_system_proxy", binaryMessenger: registrar.messenger())
    let instance = SwiftFlutterProxyPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getDeviceProxy":
        do {
        let args = call.arguments as! NSDictionary
        let url = args.value(forKey:"url") as! String
        var dict:[String:Any] = [:]
        if(SwiftFlutterProxyPlugin.proxyCache[url] != nil){
            let res = SwiftFlutterProxyPlugin.proxyCache[url]
            if(res != nil){
                dict = res as! [String:Any]
            }
        } 
        else 
        {
            let res = try SwiftFlutterProxyPlugin.resolve(url: url)
            if(res != nil){
                dict = res as! [String:Any]
            }
        }
        result(dict)
        } catch let error {
            print("Unexpected Proxy Error: \(error).")
            result(error)
        }
        break
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func resolve(url:String)->[String:Any]?{
        if(SwiftFlutterProxyPlugin.proxyCache[url] != nil){
            return SwiftFlutterProxyPlugin.proxyCache[url]
        }
        let proxConfigDict = CFNetworkCopySystemProxySettings()?.takeUnretainedValue() as NSDictionary?
        if(proxConfigDict != nil){
            if(proxConfigDict!["ProxyAutoConfigEnable"] as? Int == 1){
                let pacUrl = proxConfigDict!["ProxyAutoConfigURLString"] as? String
                let pacContent = proxConfigDict!["ProxyAutoConfigJavaScript"] as? String
                if(pacContent != nil){
                    self.handlePacContent(pacContent: pacContent! as String, url: url)
                }else if(pacUrl != nil){
                    self.handlePacUrl(pacUrl: pacUrl!,url: url)
                }
            } else if (proxConfigDict!["HTTPEnable"] as? Int == 1){
                var dict: [String: Any] = [:]
                dict["host"] = proxConfigDict!["HTTPProxy"] as? String
                dict["port"] = proxConfigDict!["HTTPPort"] as? Int
                SwiftFlutterProxyPlugin.proxyCache[url] = dict
                
            } else if ( proxConfigDict!["HTTPSEnable"] as? Int == 1){
                var dict: [String: Any] = [:]
                dict["host"] = proxConfigDict!["HTTPSProxy"] as? String
                dict["port"] = proxConfigDict!["HTTPSPort"] as? Int
                SwiftFlutterProxyPlugin.proxyCache[url] = dict
            }
        }
        return SwiftFlutterProxyPlugin.proxyCache[url]
    }
    
    static func handlePacContent(pacContent: String,url: String){
        let proxies = CFNetworkCopyProxiesForAutoConfigurationScript(pacContent as CFString, CFURLCreateWithString(kCFAllocatorDefault, url as CFString, nil), nil)!.takeUnretainedValue() as? [[CFString: Any]] ?? [];
        if(proxies.count > 0){
            let proxy = proxies.first{$0[kCFProxyTypeKey] as! CFString == kCFProxyTypeHTTP || $0[kCFProxyTypeKey] as! CFString == kCFProxyTypeHTTPS}
            if(proxy != nil){
                let host = proxy?[kCFProxyHostNameKey] ?? nil
                let port = proxy?[kCFProxyPortNumberKey] ?? nil
                var dict:[String: Any] = [:]
                dict["host"] = host
                dict["port"] = port
                SwiftFlutterProxyPlugin.proxyCache[url] = dict
            }
        }
    }

    static func handlePacUrl(pacUrl: String, url: String){
        var _pacUrl = CFURLCreateWithString(kCFAllocatorDefault,  pacUrl as CFString?,nil)
        var targetUrl = CFURLCreateWithString(kCFAllocatorDefault, url as CFString?, nil)
        var info = url;
        if(pacUrl != nil && targetUrl != nil){
            var context:CFStreamClientContext = CFStreamClientContext.init(version: 0, info: &info, retain: nil, release: nil, copyDescription: nil)
            let runLoopSource = CFNetworkExecuteProxyAutoConfigurationURL(_pacUrl!,targetUrl!,  { client, proxies, error in
                let _proxies = proxies as? [[CFString: Any]] ?? [];
                if(_proxies != nil){
                    if(_proxies.count > 0){
                    let proxy = _proxies.first{$0[kCFProxyTypeKey] as! CFString == kCFProxyTypeHTTP || $0[kCFProxyTypeKey] as! CFString == kCFProxyTypeHTTPS}
                    if(proxy != nil){
                        let host = proxy?[kCFProxyHostNameKey] ?? nil
                        let port = proxy?[kCFProxyPortNumberKey] ?? nil
                        var dict:[String: Any] = [:]
                        dict["host"] = host
                        dict["port"] = port
                        let url = client.assumingMemoryBound(to: String.self).pointee
                        SwiftFlutterProxyPlugin.proxyCache[url] = dict
                    }     
                }
            }
                CFRunLoopStop(CFRunLoopGetCurrent());
            }, &context).takeUnretainedValue()
            let runLoop = CFRunLoopGetCurrent();
            CFRunLoopAddSource(runLoop, runLoopSource, CFRunLoopMode.defaultMode);
            CFRunLoopRun();
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.defaultMode);
        }
    }
    
}

