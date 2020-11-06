//
//  Downloader.swift
//  iCloudDownlader
//
//  Created by Lucas Tarasconi on 09/09/2018.
//  Copyright © 2018 Lucas Tarasconi. All rights reserved.
//

import Foundation

let fm = FileManager.default
let path = fm.currentDirectoryPath

class Downloader {
    let consoleIO = ConsoleIO()

    func getFileAttributes(fileUrl: URL) -> URLResourceValues? {
        do {
            let status = try fileUrl.resourceValues(forKeys: [.isUbiquitousItemKey,
                                                              .ubiquitousItemIsDownloadingKey,
                                                              .ubiquitousItemDownloadingStatusKey]);

            return status
        } catch {
            consoleIO.writeMessage("Can't get attributes for file \(fm.displayName(atPath: fileUrl.lastPathComponent)): \(error)", to: .error)
            return nil
        }

    }

    func fetchFile(fileUrl: URL) {
        let status: URLResourceValues = getFileAttributes(fileUrl: fileUrl)!

        if status.isUbiquitousItem ?? false {
            if status.ubiquitousItemDownloadingStatus == .current {
                consoleIO.writeMessage("\(fm.displayName(atPath: fileUrl.lastPathComponent)) is already downloaded", to: .warning)
            } else if status.ubiquitousItemIsDownloading ?? false {
                consoleIO.writeMessage("\(fm.displayName(atPath: fileUrl.lastPathComponent)) is downloading")
            } else {
                do {
                    try fm.startDownloadingUbiquitousItem(at: fileUrl)
                    consoleIO.writeMessage("Info: \(fileUrl.lastPathComponent) is downloading")
                } catch {
                    consoleIO.writeMessage("Can't download \(fm.displayName(atPath: fileUrl.lastPathComponent)): \(error)", to: .error)
                }
            }
        } else {
            consoleIO.writeMessage("\(fm.displayName(atPath: fileUrl.lastPathComponent)) is not an iCloud file", to: .warning)
        }
    }

    func awaitFile(fileUrl: URL) {
        let semaphore = DispatchSemaphore(value: 0)

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope,
                              NSMetadataQueryUbiquitousDataScope]
        query.valueListAttributes = [NSMetadataUbiquitousItemPercentDownloadedKey]
        query.predicate = NSPredicate(format: "%K LIKE[CD] %@", NSMetadataItemPathKey, fileUrl.path)

        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: nil, queue: .main) { (notification) in
            guard let metadata = (notification.userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem])?.first else {
                return
            }

            if let percent = metadata.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double {
                self.consoleIO.writeMessage("progress: \(Float(percent) / 100)")
            }

            query.stop()
            semaphore.signal()
        }

        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: nil, queue: .main) { (notification) in
            self.consoleIO.writeMessage("notification: \(notification)")
            query.stop()
            semaphore.signal()
        }
        
        self.consoleIO.writeMessage("started: \(query.start())")

        _ = semaphore.wait(wallTimeout: .distantFuture)
    }

    func downloadFile() {
        let file = CommandLine.arguments[1]
        let fileUrl = NSURL.fileURL(withPath: file)
        fetchFile(fileUrl: fileUrl)
        awaitFile(fileUrl: fileUrl)
    }

    func downloadFolder() {
        do {
            let items = try fm.contentsOfDirectory(atPath: path)

            for item in items {
                let itemUrl = NSURL.fileURL(withPath: item)
                fetchFile(fileUrl: itemUrl)
                awaitFile(fileUrl: itemUrl)
            }
        } catch {
            consoleIO.writeMessage("Can't acces the folder", to: .error)
        }
    }
}
