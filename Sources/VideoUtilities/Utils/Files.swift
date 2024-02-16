
import Foundation


enum Files {
    static func videosDirectoryURL() -> URL? {
        guard let videoDirectoryUrl = documentsURL()?
                .appendingPathComponent("videos") else { return nil}
        
        do {
            try
            FileManager.default.createDirectory(at: videoDirectoryUrl, withIntermediateDirectories: true)
            return videoDirectoryUrl
        }
        catch {
            print(error)
            return nil
        }
    }
    
    static func createVideosURL(id:UUID = UUID()) -> URL? {
        let name = id.uuidString + ".mov"
        return videosDirectoryURL()?.appendingPathComponent(name)
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
