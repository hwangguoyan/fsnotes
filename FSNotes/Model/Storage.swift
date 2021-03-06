//
//  NotesCollection.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 8/9/17.
//  Copyright © 2017 Oleksandr Glushchenko. All rights reserved.
//

import Foundation
import Highlightr
import CloudKit

class Storage {
    static let instance = Storage()
    
    weak var delegate : CloudKitManagerDelegate?
    var noteList = [Note]()
    var notesDict: [String: Note] = [:]
    
    static var generalUrl: URL?
    static var pinned: Int = 0
    static var allowedExtensions = ["md", "markdown", "txt", "rtf", "fountain", UserDefaultsManagement.storageExtension]
    
    public static var fsImportIsAvailable = true
    
#if os(iOS)
    let initialFiles = [
        "FSNotes - Readme.md",
        "FSNotes - Code Highlighting.md"
    ]
#else
    let initialFiles = [
        "FSNotes - Readme.md",
        "FSNotes - Release Notes.md",
        "FSNotes - Shortcuts.md",
        "FSNotes - Code Highlighting.md"
    ]
#endif
    
    func loadDocuments(tryCount: Int = 0) {
        noteList.removeAll()
        
        let storageItemList = CoreDataManager.instance.fetchStorageList()
        
        for item in storageItemList {
            loadLabel(item)
        }

        if let list = sortNotes(noteList: noteList) {
            noteList = list
        }
        
        guard !checkFirstRun() else {
            if tryCount == 0 {
                loadDocuments(tryCount: 1)
            }
            
            #if os(OSX)
                cacheMarkdown()
            #endif
            
            return
        }
        
        #if os(OSX)
            cacheMarkdown()
        #endif
    }
    
    func sortNotes(noteList: [Note]?) -> [Note]? {
        guard let list = noteList else {
            return nil
        }
        
        let sortDirection = UserDefaultsManagement.sortDirection
        
        switch UserDefaultsManagement.sort {
        case .CreationDate:
            return list.sorted(by: {
                if $0.isPinned == $1.isPinned, let prevDate = $0.creationDate, let nextDate = $1.creationDate {
                    return sortDirection && prevDate > nextDate || !sortDirection && prevDate < nextDate
                }
                return $0.isPinned && !$1.isPinned
            })
        
        case .ModificationDate:
            return list.sorted(by: {
                if $0.isPinned == $1.isPinned, let prevDate = $0.modifiedLocalAt, let nextDate = $1.modifiedLocalAt {
                    return sortDirection && prevDate > nextDate || !sortDirection && prevDate < nextDate
                }
                return $0.isPinned && !$1.isPinned
            })
        
        case .Title:
            return list.sorted(by: {
                if $0.isPinned == $1.isPinned {
                    return sortDirection && $0.title < $1.title || !sortDirection && $0.title > $1.title
                }
                return $0.isPinned && !$1.isPinned
            })
        }
    }
    
    func loadLabel(_ item: StorageItem) {
        guard let url = item.getUrl() else {
            return
        }
        
        let documents = readDirectory(url)
        let existNotes = CoreDataManager.instance.fetchAll()
        
        for note in existNotes {
            var path: String = ""
            if let storage = note.storage, let unwrappedPath = storage.path {
                path = unwrappedPath
            }
            notesDict[note.name + path] = note
        }
        
        for document in documents {
            var note: Note
            
            let url = document.0
            let date = document.1
            let name = url.pathComponents.last!
            let uniqName = name + item.path!
            
            if (url.pathComponents.count == 0) {
                continue
            }
            
            if notesDict[uniqName] == nil {
                note = CoreDataManager.instance.make()
                note.isSynced = false
            } else {
                note = notesDict[uniqName]!
                note.checkLocalSyncState(date)
            }
            
            note.creationDate = document.2
            note.storage = item
            note.load(url)
            
            if !note.isSynced {
                note.modifiedLocalAt = date
            }
            
            if note.isPinned {
                Storage.pinned += 1
            }
            
            noteList.append(note)
        }
        
        CoreDataManager.instance.save()
    }
    
    func readDirectory(_ url: URL) -> [(URL, Date, Date)] {
        do {
            let directoryFiles =
                try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey], options:.skipsHiddenFiles)
            
            return
                directoryFiles.filter {Storage.allowedExtensions.contains($0.pathExtension)}.map{
                    url in (
                        url,
                        (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                            )?.contentModificationDate ?? Date.distantPast,
                        (try? url.resourceValues(forKeys: [.creationDateKey])
                            )?.creationDate ?? Date.distantPast
                    )
                }
        } catch {
            print("Storage not found, url: \(url)")
        }
        
        return []
    }
    
    func add(_ note: Note) {
        if !noteList.contains(where: { $0.name == note.name && $0.storage == note.storage }) {
           noteList.append(note)
        }
    }
    
    func removeBy(note: Note) {
        if let i = noteList.index(of: note) {
            note.isRemoved = true
            noteList.remove(at: i)
        }
    }
    
    func remove(id: Int) {
        noteList[id].isRemoved = true
    }
    
    func getNextId() -> Int {
        return noteList.count
    }
    
    func checkFirstRun() -> Bool {
        let destination = Storage.instance.getBaseURL()
        let path = destination.path
        
        if !FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("General storage not found: \(error)")
            }
        }
        
        guard noteList.isEmpty, let resourceURL = Bundle.main.resourceURL else {
            return false
        }
        
        let initialPath = resourceURL.appendingPathComponent("Initial").path
        
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: initialPath)
            for file in files {
                guard initialFiles.contains(file) else {
                    continue
                }
                try? FileManager.default.copyItem(atPath: "\(initialPath)/\(file)", toPath: "\(path)/\(file)")
            }
        } catch {
            print("Initial copy error: \(error)")
        }

        return true
    }
    
    func getOrCreate(name: String) -> Note {
        var note: Note?
        
        note = noteList.first(where: {
            return ($0.name == name && $0.isGeneral())
        })
        
        if note == nil {
            note = Note(context: CoreDataManager.instance.context)
            note?.name = name
            CoreDataManager.instance.context.insert(note!)
            add(note!)
        }
        
        return note!
    }
    
    func getModified() -> Note? {
        return
            noteList.first(where: {
                return (
                    !$0.isSynced && $0.isGeneral()
                )
            })
    }
    
    func getBy(url: URL) -> Note? {
        return
            noteList.first(where: {
                return (
                    $0.url == url
                )
            })
    }
    
    func getBy(name: String) -> Note? {
        return
            noteList.first(where: {
                return (
                    $0.name == name && $0.isGeneral()
                )
            })
    }
    
    func getBy(title: String) -> Note? {
        return
            noteList.first(where: {
                return (
                    $0.title == title
                )
            })
    }
    
    func getBy(startWith: String) -> [Note]? {
        return
            noteList.filter{
                $0.title.starts(with: startWith)
            }
    }
    
    func getBaseURL() -> URL {
#if os(OSX)
        if let gu = Storage.generalUrl {
            return gu
        }
    
        guard let storage = CoreDataManager.instance.fetchGeneralStorage(), let path = storage.path, let url = URL(string: path) else {
            return UserDefaultsManagement.storageUrl
        }
    
        Storage.generalUrl = url
    
        return url
#else
        return UserDefaultsManagement.documentDirectory
#endif
    }
    
    func countSynced() -> Int {
        return
            noteList.filter{
                !$0.cloudKitRecord.isEmpty
                && $0.isGeneral()
                && $0.isSynced
            }.count
    }
    
    func countTotal() -> Int {
        return
            noteList.filter{
                $0.isGeneral()
            }.count
    }
        
    var isActiveCaching = false
    var terminateBusyQueue = false
    
    func cacheMarkdown() {
        guard !self.isActiveCaching else {
            self.terminateBusyQueue = true
            return
        }
        
        DispatchQueue.global(qos: .background).async {
            self.isActiveCaching = true
            
            let markdownDocuments = self.noteList.filter{
                $0.isMarkdown()
            }
            
            for note in markdownDocuments {
                note.markdownCache()
                
                if note == EditTextView.note {
                    DispatchQueue.main.async {
                        self.delegate?.refillEditArea(cursor: nil, previewOnly: false)
                    }
                }
                
                if self.terminateBusyQueue {
                    print("Caching data obsolete, restart caching initiated.")
                    self.terminateBusyQueue = false
                    self.isActiveCaching = false
                    self.loadDocuments()
                    break
                }
            }
            
            self.isActiveCaching = false
        }
    }
    
    func removeNotes(notes: [Note], fsRemove: Bool = true, completion: @escaping () -> Void) {
        guard notes.count > 0 else {
            completion()
            return
        }
        
        for note in notes {
            removeBy(note: note)
        }
        
        #if CLOUDKIT
            if UserDefaultsManagement.cloudKitSync {
                var recordIds: [CKRecordID] = []
                
                for note in notes {
                    if let record = CKRecord(archivedData: note.cloudKitRecord) {
                        recordIds.append(record.recordID)
                    }
                }
                
                CloudKitManager.sharedInstance().removeRecords(records: recordIds) {
                    CoreDataManager.instance.removeNotes(notes: notes, fsRemove: fsRemove)
                    completion()
                }
            } else {
                CoreDataManager.instance.removeNotes(notes: notes, fsRemove: fsRemove)
                completion()
            }
        #else
            CoreDataManager.instance.removeNotes(notes: notes, fsRemove: fsRemove)
            completion()
        #endif
    }
    
    func saveNote(note: Note, userInitiated: Bool = false, cloudSync: Bool = true) {
        add(note)
        
        #if CLOUDKIT
            if UserDefaultsManagement.cloudKitSync && note.isGeneral() && cloudSync {
                if userInitiated {
                    NotificationsController.onStartSync()
                }
                
                // save state to core database
                note.isSynced = false
                CoreDataManager.instance.save()
                
                // save cloudkit
                CloudKitManager.sharedInstance().saveNote(note) {}
            }
        #endif
    }
}
