
import Foundation


enum Files {
    static func createVideosURL() -> URL? {
        
        guard let videoDirectoryUrl = documentsURL()?
                .appendingPathComponent("videos") else { return nil}
        
        do {
            try
            FileManager.default.createDirectory(at: videoDirectoryUrl, withIntermediateDirectories: true)
        }
        catch {
            print(error)
            return nil
        }
        
        let name = UUID().uuidString + ".mov"
        
        return videoDirectoryUrl.appendingPathComponent(name)
    }
    
    static func documentsURL()  -> URL? {
        try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
}
