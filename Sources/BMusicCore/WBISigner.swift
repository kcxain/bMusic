import Foundation
import CryptoKit

public enum WBISigner {
    private static let table = [46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,33,9,42,19,29,28,14,39,12,38,41,13,37,48,7,16,24,55,40,61,26,17,0,1,60,51,30,4,22,25,54,21,56,59,6,63,57,62,11,36,20,34,44,52]
    public static func query(_ parameters: [String: String], imageKey: String, subKey: String, timestamp: Int = Int(Date().timeIntervalSince1970)) throws -> String {
        let chars = Array(imageKey + subKey)
        guard chars.count == 64 else { throw BMusicError.invalidResponse }
        let key = String(table.prefix(32).map { chars[$0] })
        var values = parameters
        values["wts"] = String(timestamp)
        let forbidden = CharacterSet(charactersIn: "!'()*")
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let query = values.keys.sorted().map { name in
            let value = values[name]!.components(separatedBy: forbidden).joined()
            return name.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&")
        let digest = Insecure.MD5.hash(data: Data((query + key).utf8)).map { String(format: "%02x", $0) }.joined()
        return query + "&w_rid=" + digest
    }
}
