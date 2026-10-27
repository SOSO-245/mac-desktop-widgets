import Foundation

enum CalendarCloudIO {
    static func read(_ folder:URL) throws ->[CalendarSyncDocument] {
        let files=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.isRegularFileKey])
        let candidates=files.filter { $0.lastPathComponent.hasPrefix("mac-") && $0.pathExtension=="json" }
        guard candidates.count<=64 else {throw SyncModelError.invalid}
        var result:[CalendarSyncDocument]=[]
        var total=0
        for file in candidates {
            var coordinationError:NSError?;var failure:Error?
            NSFileCoordinator().coordinate(readingItemAt:file,options:[],error:&coordinationError) {url in
                do {
                    let urls=[url]+(NSFileVersion.unresolvedConflictVersionsOfItem(at:url) ?? []).map(\.url)
                    for item in urls {
                        let size=try item.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                        guard size<4_000_000,total+size<20_000_000 else {throw SyncModelError.invalid}
                        let bytes=try Data(contentsOf:item);total+=bytes.count
                        result.append(try JSONDecoder().decode(CalendarSyncDocument.self,from:bytes).validated())
                    }
                } catch {failure=error}
            }
            if let error=coordinationError ?? failure as NSError? {throw error}
        }
        // A not-yet-downloaded document must never be mistaken for an empty account.
        for file in files where file.lastPathComponent.hasPrefix(".mac-") && file.pathExtension=="icloud" {
            let name=String(file.lastPathComponent.dropFirst().dropLast(7))
            try? FileManager.default.startDownloadingUbiquitousItem(at:folder.appendingPathComponent(name))
            throw CocoaError(.fileReadUnknown)
        }
        return result
    }
    static func write(_ document:CalendarSyncDocument,device:String,folder:URL) throws ->Bool {
        let bytes=try CalendarSyncDocument.bytes(document.validated())
        guard bytes.count<4_000_000 else {throw SyncModelError.invalid}
        let file=folder.appendingPathComponent("mac-"+device+".json")
        var coordinationError:NSError?;var failure:Error?;var uploaded=false
        NSFileCoordinator().coordinate(writingItemAt:file,options:.forReplacing,error:&coordinationError) {url in
            do {
                if (try? Data(contentsOf:url)) != bytes {try bytes.write(to:url,options:.atomic)}
                uploaded=(try? url.resourceValues(forKeys:[.ubiquitousItemIsUploadedKey]).ubiquitousItemIsUploaded)==true
            } catch {failure=error}
        }
        if let error=coordinationError ?? failure as NSError? {throw error}
        return uploaded
    }
}
