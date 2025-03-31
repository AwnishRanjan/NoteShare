import UIKit
import AuthenticationServices
import VisionKit
import FirebaseStorage
import FirebaseFirestore
import PDFKit
import FirebaseAuth

struct SavedFireNote {
    let id: String
    let title: String
    let author: String
    let pdfUrl: String?
    var coverImage: UIImage?
    var isFavorite: Bool
    var pageCount: Int
    let subjectName: String?
    let subjectCode: String?
    let fileSize: String
    let dateAdded: Date
    let college: String?
    let university: String?
    
    init(id: String, title: String, author: String, pdfUrl: String?, coverImage: UIImage? = nil,
         isFavorite: Bool = false, pageCount: Int = 0, subjectName: String? = nil,
         subjectCode: String? = nil, fileSize: String = "Unknown", dateAdded: Date = Date(),
         college: String? = nil, university: String? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.pdfUrl = pdfUrl
        self.coverImage = coverImage
        self.isFavorite = isFavorite
        self.pageCount = pageCount
        self.subjectName = subjectName
        self.subjectCode = subjectCode
        self.fileSize = fileSize
        self.dateAdded = dateAdded
        self.college = college
        self.university = university
    }
    
    var dictionary: [String: Any] {
        return [
            "id": id,
            "fileName": title,
            "category": author,
            "collegeName": college ?? "Unknown",
            "downloadURL": pdfUrl ?? "",
            "uploadDate": dateAdded,
            "pageCount": pageCount,
            "fileSize": fileSize,
            "userId": "userID",
            "isFavorite": isFavorite,
            "subjectCode": subjectCode ?? "",
            "subjectName": subjectName ?? "",
            "privacy": "public"
        ]
    }
}

class PDFCache {
    static let shared = PDFCache()
    
    private let userDefaults = UserDefaults.standard
    private let imageCache = NSCache<NSString, UIImage>()
    private let metadataExpiryTime: TimeInterval = 5 * 60 // 5 minutes
    
    private init() {
        // Configure cache limits
        imageCache.countLimit = 100
        imageCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }
    
    // MARK: - Image Caching
    
    func getCachedImage(for key: String) -> UIImage? {
        return imageCache.object(forKey: key as NSString)
    }
    
    func cacheImage(_ image: UIImage, for key: String) {
        imageCache.setObject(image, forKey: key as NSString)
    }
    
    // MARK: - Metadata Caching
    
    func cacheNotes(curated: [SavedFireNote], favorites: [SavedFireNote]) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let timestamp = Date().timeIntervalSince1970
        
        // Cache curated notes
        let curatedData = curated.map { note -> [String: Any] in
            var data = note.dictionary
            data["cacheTimestamp"] = timestamp
            return data
        }
        
        // Cache favorite notes
        let favoritesData = favorites.map { note -> [String: Any] in
            var data = note.dictionary
            data["cacheTimestamp"] = timestamp
            return data
        }
        
        userDefaults.set(curatedData, forKey: "cached_curated_notes_\(userId)")
        userDefaults.set(favoritesData, forKey: "cached_favorite_notes_\(userId)")
        userDefaults.set(timestamp, forKey: "notes_cache_timestamp_\(userId)")
    }
    
    func getCachedNotes() -> (curated: [SavedFireNote], favorites: [SavedFireNote], isFresh: Bool) {
        guard let userId = Auth.auth().currentUser?.uid else { return ([], [], false) }
        
        // Check if cache is fresh
        let lastUpdated = userDefaults.double(forKey: "notes_cache_timestamp_\(userId)")
        let isFresh = Date().timeIntervalSince1970 - lastUpdated < metadataExpiryTime
        
        // Load cached curated notes
        var curatedNotes: [SavedFireNote] = []
        if let curatedData = userDefaults.array(forKey: "cached_curated_notes_\(userId)") as? [[String: Any]] {
            curatedNotes = curatedData.compactMap { self.createNoteFromDictionary($0) }
        }
        
        // Load cached favorite notes
        var favoriteNotes: [SavedFireNote] = []
        if let favoritesData = userDefaults.array(forKey: "cached_favorite_notes_\(userId)") as? [[String: Any]] {
            favoriteNotes = favoritesData.compactMap { self.createNoteFromDictionary($0) }
        }
        
        return (curatedNotes, favoriteNotes, isFresh)
    }
    
    private func createNoteFromDictionary(_ data: [String: Any]) -> SavedFireNote? {
        guard
            let id = data["id"] as? String,
            let title = data["fileName"] as? String,
            let author = data["category"] as? String,
            let pdfUrl = data["downloadURL"] as? String,
            let fileSize = data["fileSize"] as? String,
            let userId = data["userId"] as? String
        else {
            return nil
        }
        
        // Get image from cache
        let coverImage = getCachedImage(for: pdfUrl)
        
        // Convert date if available
        let dateAdded: Date
        if let timestamp = data["uploadDate"] as? Timestamp {
            dateAdded = timestamp.dateValue()
        } else if let timestamp = data["uploadDate"] as? TimeInterval {
            dateAdded = Date(timeIntervalSince1970: timestamp)
        } else {
            dateAdded = Date()
        }
        
        return SavedFireNote(
            id: id,
            title: title,
            author: author,
            pdfUrl: pdfUrl,
            coverImage: coverImage,
            isFavorite: data["isFavorite"] as? Bool ?? false,
            pageCount: data["pageCount"] as? Int ?? 0,
            subjectName: data["subjectName"] as? String,
            subjectCode: data["subjectCode"] as? String,
            fileSize: fileSize,
            dateAdded: dateAdded,
            college: data["collegeName"] as? String,
            university: data["universityName"] as? String
        )
    }
    
    // MARK: - PDF File Caching
    
    func cachePDFPath(for noteId: String, fileURL: URL) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        var cachedPaths = userDefaults.dictionary(forKey: "cached_pdf_paths_\(userId)") as? [String: String] ?? [:]
        cachedPaths[noteId] = fileURL.path
        userDefaults.set(cachedPaths, forKey: "cached_pdf_paths_\(userId)")
    }
    
    func getCachedPDFPath(for noteId: String) -> URL? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        
        if let cachedPaths = userDefaults.dictionary(forKey: "cached_pdf_paths_\(userId)") as? [String: String],
           let path = cachedPaths[noteId] {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        
        return nil
    }
    
    // MARK: - Clear Cache
    
    func clearCache() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        imageCache.removeAllObjects()
        userDefaults.removeObject(forKey: "cached_curated_notes_\(userId)")
        userDefaults.removeObject(forKey: "cached_favorite_notes_\(userId)")
        userDefaults.removeObject(forKey: "notes_cache_timestamp_\(userId)")
        
        // Delete cached PDFs
        if let cachedPaths = userDefaults.dictionary(forKey: "cached_pdf_paths_\(userId)") as? [String: String] {
            for path in cachedPaths.values {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
            }
        }
        
        userDefaults.removeObject(forKey: "cached_pdf_paths_\(userId)")
    }
}

class FirebaseService1 {
    static let shared = FirebaseService1()
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    private var notesListener: ListenerRegistration?
    
    // Fetch notes for a specific user
    func observeNotes(userId: String, completion: @escaping ([SavedFireNote]) -> Void) {
            // Add this flag to prevent multiple leaves
            var hasLeft = false
            
            self.notesListener = db.collection("pdfs")
                .whereField("userId", isEqualTo: userId)
                .addSnapshotListener { (snapshot, error) in
                    if let error = error {
                        print("Error observing notes: \(error.localizedDescription)")
                        // Only leave once
                        if !hasLeft {
                            completion([])
                            hasLeft = true
                        }
                        return
                    }

                    guard let documents = snapshot?.documents else {
                        // Only leave once
                        if !hasLeft {
                            completion([])
                            hasLeft = true
                        }
                        return
                    }

                    var notes: [SavedFireNote] = []
                    let group = DispatchGroup()

                    for document in documents {
                        group.enter()
                        let data = document.data()
                        let pdfUrl = data["downloadURL"] as? String ?? ""
                        let noteId = document.documentID

                        self.getStorageReference(from: pdfUrl)?.getMetadata { metadata, error in
                            let fileSize = self.formatFileSize(metadata?.size ?? 0)

                            self.fetchPDFCoverImage(from: pdfUrl) { (image, pageCount) in
                                let note = SavedFireNote(
                                    id: noteId,
                                    title: data["fileName"] as? String ?? "Untitled",
                                    author: data["category"] as? String ?? "Unknown Author",
                                    pdfUrl: pdfUrl,
                                    coverImage: image,
                                    isFavorite: false,
                                    pageCount: pageCount,
                                    subjectName: data["subjectName"] as? String,
                                    subjectCode: data["subjectCode"] as? String,
                                    fileSize: fileSize,
                                    dateAdded: (data["uploadDate"] as? Timestamp)?.dateValue() ?? Date(),
                                    college: data["collegeName"] as? String,
                                    university: data["universityName"] as? String
                                )
                                notes.append(note)
                                group.leave()
                            }
                        }
                    }

                    group.notify(queue: .main) {
                        // Only deliver result once per call to prevent multiple leaves in the caller
                        if !hasLeft {
                            completion(notes.sorted { $0.dateAdded > $1.dateAdded })
                            hasLeft = true
                        }
                    }
                }
        }

    
    
    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
     func getStorageReference(from urlString: String) -> StorageReference? {
        guard !urlString.isEmpty else {
            print("Warning: Empty URL string provided to getStorageReference")
            return nil
        }
        
        do {
            if urlString.starts(with: "gs://") {
                return storage.reference(forURL: urlString)
            }
            
            if urlString.contains("firebasestorage.googleapis.com") {
                return storage.reference(forURL: urlString)
            }
            
            if urlString.starts(with: "/") {
                return storage.reference().child(urlString)
            }
            
            return storage.reference().child(urlString)
        } catch {
            print("Error creating storage reference for URL: \(urlString), error: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func fetchPDFCoverImage(from urlString: String, completion: @escaping (UIImage?, Int) -> Void) {
        guard !urlString.isEmpty else {
            print("Empty PDF URL provided")
            completion(nil, 0)
            return
        }

        guard let storageRef = getStorageReference(from: urlString) else {
            print("Invalid storage reference for URL: \(urlString)")
            completion(nil, 0)
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let localURL = tempDir.appendingPathComponent(UUID().uuidString + ".pdf")

        storageRef.write(toFile: localURL) { url, error in
            if let error = error {
                print("Error downloading PDF for cover from \(urlString): \(error.localizedDescription)")
                completion(nil, 0)
                return
            }

            guard let pdfURL = url, FileManager.default.fileExists(atPath: pdfURL.path) else {
                print("Failed to download PDF to \(localURL.path)")
                completion(nil, 0)
                return
            }

            guard let pdfDocument = PDFDocument(url: pdfURL) else {
                print("Failed to create PDFDocument from \(pdfURL.path)")
                completion(nil, 0)
                return
            }

            let pageCount = pdfDocument.pageCount
            guard pageCount > 0, let pdfPage = pdfDocument.page(at: 0) else {
                print("No pages found in PDF at \(pdfURL.path)")
                completion(nil, pageCount)
                return
            }

            let pageRect = pdfPage.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let image = renderer.image { context in
                UIColor.white.set()
                context.fill(pageRect)
                context.cgContext.translateBy(x: 0.0, y: pageRect.size.height)
                context.cgContext.scaleBy(x: 1.0, y: -1.0)
                pdfPage.draw(with: .mediaBox, to: context.cgContext)
            }

            do {
                try FileManager.default.removeItem(at: pdfURL)
            } catch {
                print("Failed to delete temp file: \(error)")
            }

            completion(image, pageCount)
        }
    }
    
    func downloadPDF(from urlString: String, completion: @escaping (Result<URL, Error>) -> Void) {
        guard !urlString.isEmpty else {
            let error = NSError(domain: "PDFDownloadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty PDF URL"])
            print("Download failed: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }

        guard let storageRef = getStorageReference(from: urlString) else {
            let error = NSError(domain: "PDFDownloadError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid storage reference URL: \(urlString)"])
            print("Download failed: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }

        let fileName = UUID().uuidString + ".pdf"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let localURL = documentsPath.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: localURL.path) {
            do {
                try FileManager.default.removeItem(at: localURL)
                print("Removed existing file at \(localURL.path)")
            } catch {
                print("Failed to remove existing file: \(error)")
                completion(.failure(error))
                return
            }
        }

        print("Starting download from \(urlString) to \(localURL.path)")
        let downloadTask = storageRef.write(toFile: localURL) { url, error in
            if let error = error {
                // Enhanced error logging
                if let nsError = error as NSError? {
                    let errorCode = nsError.code
                    let errorDesc = nsError.localizedDescription
                    let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
                    print("Download error for \(urlString): Code \(errorCode) - \(errorDesc)")
                    if let underlyingDesc = underlyingError?.localizedDescription {
                        print("Underlying error: \(underlyingDesc)")
                    }
                } else {
                    print("Download error for \(urlString): \(error.localizedDescription)")
                }
                completion(.failure(error))
                return
            }

            guard let url = url else {
                let error = NSError(domain: "PDFDownloadError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Downloaded file URL is nil"])
                print("Download failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            if FileManager.default.fileExists(atPath: url.path) {
                if let pdfDocument = PDFDocument(url: url) {
                    print("PDF loaded successfully with \(pdfDocument.pageCount) pages at \(url.path)")
                    completion(.success(url))
                } else {
                    let error = NSError(domain: "PDFDownloadError", code: -4, userInfo: [NSLocalizedDescriptionKey: "Invalid PDF at \(url.path)"])
                    print("Download failed: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            } else {
                let error = NSError(domain: "PDFDownloadError", code: -5, userInfo: [NSLocalizedDescriptionKey: "File not found at \(url.path) after download"])
                print("Download failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }

        downloadTask.observe(.progress) { snapshot in
            let percentComplete = 100.0 * Double(snapshot.progress?.completedUnitCount ?? 0) /
                Double(snapshot.progress?.totalUnitCount ?? 1)
            print("Download progress for \(urlString): \(percentComplete)%")
        }
    }
    
    
    //    fav
    // Ensure fetchFavoriteNotes works correctly
    func fetchFavoriteNotes(userId: String, completion: @escaping ([SavedFireNote]) -> Void) {
        self.db.collection("userFavorites")
            .document(userId)
            .collection("favorites")
            .whereField("isFavorite", isEqualTo: true)
            .getDocuments { (snapshot, error) in
                if let error = error {
                    print("Error fetching favorite note IDs: \(error.localizedDescription)")
                    completion([])
                    return
                }

                guard let favoriteDocs = snapshot?.documents, !favoriteDocs.isEmpty else {
                    print("No favorite notes found for user \(userId)")
                    completion([])
                    return
                }

                let favoriteIds = favoriteDocs.map { $0.documentID }
                let group = DispatchGroup()
                var favoriteNotes: [SavedFireNote] = []

                for noteId in favoriteIds {
                    group.enter()
                    self.db.collection("pdfs").document(noteId).getDocument { (document, error) in
                        if let error = error {
                            print("Error fetching note \(noteId): \(error)")
                            group.leave()
                            return
                        }

                        guard let data = document?.data(), document?.exists ?? false else {
                            print("Note \(noteId) not found")
                            group.leave()
                            return
                        }

                        let pdfUrl = data["downloadURL"] as? String ?? ""
                        self.getStorageReference(from: pdfUrl)?.getMetadata { metadata, error in
                            if let error = error { print("Metadata error for \(pdfUrl): \(error)") }
                            let fileSize = self.formatFileSize(metadata?.size ?? 0)

                            self.fetchPDFCoverImage(from: pdfUrl) { (image, pageCount) in
                                let note = SavedFireNote(
                                    id: noteId,
                                    title: data["fileName"] as? String ?? "Untitled",
                                    author: data["category"] as? String ?? "Unknown Author",
                                    pdfUrl: pdfUrl,
                                    coverImage: image,
                                    isFavorite: true,
                                    pageCount: pageCount,
                                    subjectName: data["subjectName"] as? String,
                                    subjectCode: data["subjectCode"] as? String,
                                    fileSize: fileSize,
                                    dateAdded: (data["uploadDate"] as? Timestamp)?.dateValue() ?? Date(),
                                    college: data["collegeName"] as? String,
                                    university: data["universityName"] as? String
                                )
                                favoriteNotes.append(note)
                                group.leave()
                            }
                        }
                    }
                }

                group.notify(queue: .main) {
                    print("Fetched \(favoriteNotes.count) favorite notes for user \(userId)")
                    completion(favoriteNotes.sorted { $0.dateAdded > $1.dateAdded })
                }
            }
    }
    
    // Fetch favorite note IDs for the user
        private func fetchUserFavorites(userId: String, completion: @escaping ([String]) -> Void) {
            db.collection("userFavorites")
                .document(userId)
                .collection("favorites")
                .whereField("isFavorite", isEqualTo: true)
                .getDocuments { snapshot, error in
                    if let error = error {
                        print("Error fetching favorites: \(error)")
                        completion([])
                        return
                    }
                    let favoriteIds = snapshot?.documents.map { $0.documentID } ?? []
                    completion(favoriteIds)
                }
        }
    
    
    // Update favorite status
    func updateFavoriteStatus(for noteId: String, isFavorite: Bool, completion: @escaping (Error?) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "FirebaseService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        let favoriteRef = db.collection("userFavorites").document(userId).collection("favorites").document(noteId)
        
        if isFavorite {
            favoriteRef.setData([
                "isFavorite": true,
                "timestamp": Timestamp(date: Date())
            ]) { error in
                completion(error)
            }
        } else {
            favoriteRef.delete { error in
                completion(error)
            }
        }
    }
}
    // fav end


import PDFKit
import UIKit

class NoteCollectionViewCell1: UICollectionViewCell {
    var noteId: String?
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 16
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let coverImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray6
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subjectLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let detailsLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let pageCountBadge: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1.0)
        view.layer.cornerRadius = 10
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let pageCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let pageIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "doc.text")
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let favoriteButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // Properties
    var isFavorite: Bool = false {
        didSet {
            updateFavoriteButtonImage()
        }
    }
    
    var favoriteButtonTapped: (() -> Void)?
    
    // Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // UI Setup
    private func setupUI() {
        contentView.addSubview(containerView)
        
        // Remove pageCountBadge from this array to prevent it from being added to the view
        [coverImageView, titleLabel, subjectLabel, detailsLabel, favoriteButton].forEach {
            containerView.addSubview($0)
        }
        
        // Remove setup of page count badge
        // pageCountBadge.addSubview(pageIconImageView)
        // pageCountBadge.addSubview(pageCountLabel)
        
        setupConstraints()
        favoriteButton.addTarget(self, action: #selector(favoriteButtonPressed), for: .touchUpInside)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Container view
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 3),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -3),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            
            // Cover image view
            coverImageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            coverImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            coverImageView.heightAnchor.constraint(equalTo: containerView.heightAnchor, multiplier: 0.62),
            
            // Title label
            titleLabel.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            
            // Subject label
            subjectLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subjectLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            subjectLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            
            // Details label
            detailsLabel.topAnchor.constraint(equalTo: subjectLabel.bottomAnchor, constant: 3),
            detailsLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            detailsLabel.trailingAnchor.constraint(equalTo: favoriteButton.leadingAnchor, constant: -8),
            detailsLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -10),
            
            // Favorite button
            favoriteButton.centerYAnchor.constraint(equalTo: detailsLabel.centerYAnchor),
            favoriteButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            favoriteButton.widthAnchor.constraint(equalToConstant: 24),
            favoriteButton.heightAnchor.constraint(equalToConstant: 24)
            
            // Removed page count badge constraints
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Apply more premium card-like shadow effect
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 10
        layer.shadowOpacity = 0.1
        layer.masksToBounds = false
        
        // Add a subtle border
        containerView.layer.borderWidth = 0.5
        containerView.layer.borderColor = UIColor.systemGray5.cgColor
        
        // Add a subtle gradient overlay to the image for more premium look
        if coverImageView.image != nil && coverImageView.subviews.isEmpty {
            let gradientLayer = CAGradientLayer()
            gradientLayer.frame = coverImageView.bounds
            gradientLayer.colors = [
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.15).cgColor
            ]
            gradientLayer.locations = [0.7, 1.0]
            
            let overlayView = UIView(frame: coverImageView.bounds)
            overlayView.backgroundColor = .clear
            overlayView.layer.addSublayer(gradientLayer)
            overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            coverImageView.addSubview(overlayView)
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        coverImageView.image = nil
        titleLabel.text = nil
        subjectLabel.text = nil
        detailsLabel.text = nil
        pageCountLabel.text = nil
        pageCountBadge.isHidden = true
        noteId = nil
        isFavorite = false
        
        // Clear any gradient overlays
        coverImageView.subviews.forEach { $0.removeFromSuperview() }
    }
    
    // Update UI for favorite button
    public func updateFavoriteButtonImage() {
        let image = isFavorite ? UIImage(systemName: "heart.fill") : UIImage(systemName: "heart")
        favoriteButton.setImage(image, for: .normal)
        favoriteButton.tintColor = isFavorite ? .systemBlue : .systemGray
    }
    
    // Favorite button pressed
    @objc private func favoriteButtonPressed() {
        isFavorite.toggle()
        updateFavoriteButtonImage()
        
        guard let noteId = noteId else { return }
        
        // Visual feedback - start slight animation
        UIView.animate(withDuration: 0.1, animations: {
            self.favoriteButton.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        }, completion: { _ in
            UIView.animate(withDuration: 0.1) {
                self.favoriteButton.transform = .identity
            }
        })
        
        // Post notification directly to update other cells immediately
        NotificationCenter.default.post(
            name: NSNotification.Name("FavoriteStatusChanged"),
            object: nil,
            userInfo: ["noteId": noteId, "isFavorite": isFavorite, "pageCount": pageCountLabel.text ?? "", "fileSize": detailsLabel.text?.components(separatedBy: " • ").last ?? ""]
        )
        
        // Also call Firebase service to persist the change
        FirebaseService1.shared.updateFavoriteStatus(for: noteId, isFavorite: isFavorite) { error in
            if let error = error {
                print("Error updating favorite status: \(error.localizedDescription)")
                
                // If there was an error, revert the state and post a notification to update UI
                DispatchQueue.main.async {
                    self.isFavorite.toggle()
                    self.updateFavoriteButtonImage()
                    
                    // Post notification to revert other cells too
                    NotificationCenter.default.post(
                        name: NSNotification.Name("FavoriteStatusChanged"),
                        object: nil,
                        userInfo: ["noteId": noteId, "isFavorite": !self.isFavorite, "pageCount": self.pageCountLabel.text ?? "", "fileSize": self.detailsLabel.text?.components(separatedBy: " • ").last ?? ""]
                    )
                }
            }
        }
    }
    
    // Configure cell with SavedFireNote
    func configure(with note: SavedFireNote) {
        noteId = note.id
        titleLabel.text = note.title
        
        // Display subject information if available, or use author as fallback
        if let subjectInfo = note.subjectName, !subjectInfo.isEmpty {
            subjectLabel.text = subjectInfo
        } else if let subjectCode = note.subjectCode, !subjectCode.isEmpty {
            subjectLabel.text = subjectCode
        } else if let college = note.college, !college.isEmpty {
            subjectLabel.text = college
        } else if let university = note.university, !university.isEmpty {
            subjectLabel.text = university
        } else {
            subjectLabel.text = note.author
        }
        
        // Format the date for better display
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let formattedDate = dateFormatter.string(from: note.dateAdded)
        
        // Display page count and file size in details label with date
        let pageText = note.pageCount > 0 ? "\(note.pageCount) Pages" : "PDF"
        let sizeText = note.fileSize != "Unknown" ? note.fileSize : "\(Int.random(in: 1...10)) MB"
        
        // If college or university is available, show it in details
        var detailText = "\(pageText) • \(sizeText)"
        if let college = note.college, !college.isEmpty, subjectLabel.text != college {
            detailText += " • \(college)"
        } else if let university = note.university, !university.isEmpty, subjectLabel.text != university {
            detailText += " • \(university)"
        } else {
            detailText += " • \(formattedDate)"
        }
        
        detailsLabel.text = detailText
        
        // Always hide the page count badge
        pageCountBadge.isHidden = true
        
        // Set the cover image if available, otherwise use placeholder
        if let coverImage = note.coverImage {
            coverImageView.contentMode = .scaleAspectFill
            coverImageView.image = coverImage
        } else {
            // Use a placeholder while image is loading
            coverImageView.contentMode = .center
            coverImageView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.08)
            let config = UIImage.SymbolConfiguration(pointSize: 45, weight: .regular)
            coverImageView.image = UIImage(systemName: "doc.richtext", withConfiguration: config)
            coverImageView.tintColor = .systemBlue.withAlphaComponent(0.8)
        }
        
        // Ensure the favorite state is correctly set
        isFavorite = note.isFavorite
        updateFavoriteButtonImage()
        
        // Apply shadow and styling to make it consistent with PDFListViewController
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 10
        layer.shadowOpacity = 0.1
        layer.masksToBounds = false
        
        // Add a subtle border
        containerView.layer.borderWidth = 0.5
        containerView.layer.borderColor = UIColor.systemGray5.cgColor
        
        // Set alpha to 0 so we can animate it
        alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.alpha = 1
        }
    }
    
    // Add page count update method to NoteCollectionViewCell1
    func updatePageCount(_ pageCount: Int) {
        // Update page count label
        pageCountLabel.text = "\(pageCount)"
        
        // Adjust badge width based on the number
        let widthMultiplier = pageCount > 99 ? 3.0 : (pageCount > 9 ? 2.5 : 2.0)
        let badgeWidth = 12 + (widthMultiplier * 10)
        
        // Remove previous width constraint if exists
        pageCountBadge.constraints.filter {
            $0.firstAttribute == .width && $0.secondItem == nil
        }.forEach { pageCountBadge.removeConstraint($0) }
        
        // Add new width constraint
        pageCountBadge.widthAnchor.constraint(equalToConstant: badgeWidth).isActive = true
        
        // Make sure the badge is visible
        pageCountBadge.isHidden = false
        
        // Subtle animation to draw attention
        UIView.animate(withDuration: 0.3, animations: {
            self.pageCountBadge.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        }, completion: { _ in
            UIView.animate(withDuration: 0.2) {
                self.pageCountBadge.transform = .identity
            }
        })
    }
    
    // Update details text
    func updateDetailsText(_ text: String) {
        detailsLabel.text = text
    }
}


class PDFCollectionViewCell: UICollectionViewCell {
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGray6
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let coverImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray5
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let authorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.addSubview(containerView)
        
        [coverImageView, titleLabel, authorLabel, descriptionLabel].forEach {
            containerView.addSubview($0)
        }
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            coverImageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            coverImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            coverImageView.heightAnchor.constraint(equalTo: containerView.heightAnchor, multiplier: 0.5),
            
            titleLabel.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            
            authorLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            authorLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            authorLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            
            descriptionLabel.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 4),
            descriptionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            descriptionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            
            // Ensure descriptionLabel doesn't expand uncontrollably
            descriptionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
            
            // Allow some flexibility while ensuring it doesn't overflow
            descriptionLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -8)
        ])
    }

       
    func configure(with note: Note) {
        titleLabel.text = note.title
        authorLabel.text = "By \(note.author)"
        descriptionLabel.text = note.description
        coverImageView.image = note.coverImage
    }
}


class SavedViewController: UIViewController, UIScrollViewDelegate, UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource, VNDocumentCameraViewControllerDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
        let note = searchResults[indexPath.row]
        
        var content = cell.defaultContentConfiguration()
        content.text = note.title
        content.secondaryText = "\(note.subjectName ?? note.author) • Pages: \(note.pageCount) • \(note.fileSize)"
        content.image = note.coverImage ?? UIImage(systemName: "doc.fill")
        content.imageProperties.maximumSize = CGSize(width: 40, height: 40)
        content.imageProperties.cornerRadius = 4
        
        cell.contentConfiguration = content
        return cell
    }
    
    // MARK: - Previously Read Notes Storage
    struct PreviouslyReadNote {
        let id: String
        let title: String
        let pdfUrl: String
        let lastOpened: Date
    }

    // MARK: - Properties
    private var curatedNotes: [SavedFireNote] = []
    private var favoriteNotes: [SavedFireNote] = []
    private var allNotes: [SavedFireNote] = []
    private var searchResults: [SavedFireNote] = []
    
    private var curatedPlaceholderView: PlaceholderView?
    private var favoritePlaceholderView: PlaceholderView?
    
    // Cache for PDF thumbnails
    private let imageCache = NSCache<NSString, UIImage>()
    
    // Firestore listeners
    private var notesListener: ListenerRegistration?
    
    // Loading state
    private var isLoading = false
    
    // Keep existing code, but add a refresh control
    private let refreshControl = UIRefreshControl()
    // Track if we're doing a background refresh
    private var isBackgroundRefreshing = false
    
    // Reference to Firestore
    private let db = Firestore.firestore()
    
    // MARK: - UI Elements
    private let favoriteNotesButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Favourites", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 22, weight: .semibold)
        button.setTitleColor(.label, for: .normal) // Set text color to black
        button.semanticContentAttribute = .forceLeftToRight
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let seeAllFavoritesButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("See All", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.setTitleColor(.systemBlue, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    lazy var favoriteNotesCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 200, height: 280)
        layout.minimumInteritemSpacing = 16
        layout.minimumLineSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 5, left: 16, bottom: 0, right: 16)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(NoteCollectionViewCell1.self, forCellWithReuseIdentifier: "FavoriteNoteCell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "My Notes"
        label.font = .systemFont(ofSize: 32, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let addNoteButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "document.badge.arrow.up"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let scanButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "document.viewfinder.fill"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.searchBarStyle = .prominent
        searchBar.placeholder = "Search"
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    private let curatedNotesButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Uploaded Notes", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 22, weight: .semibold)
        button.setTitleColor(.label, for: .normal) // Set text color to black
        // Remove chevron image
        button.semanticContentAttribute = .forceLeftToRight
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let seeAllUploadedButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("See All", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.setTitleColor(.systemBlue, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    lazy var curatedNotesCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 200, height: 280)
        layout.minimumInteritemSpacing = 16
        layout.minimumLineSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 5, left: 16, bottom: 0, right: 16)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(NoteCollectionViewCell1.self, forCellWithReuseIdentifier: "CuratedNoteCell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Add search results table view
    private lazy var searchResultsTableView: UITableView = {
        let tableView = UITableView()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SearchResultCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.isHidden = true
        tableView.backgroundColor = .systemBackground
        return tableView
    }()
    
    // MARK: - Previously Read Notes Storage
    private func savePreviouslyReadNote(_ note: PreviouslyReadNote) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        var history = loadPreviouslyReadNotes()
        
        history.removeAll { $0.id == note.id }
        history.append(note)
        history.sort { $0.lastOpened > $1.lastOpened }
        if history.count > 5 {
            history = Array(history.prefix(5))
        }
        
        let historyData = history.map { [
            "id": $0.id,
            "title": $0.title,
            "pdfUrl": $0.pdfUrl,
            "lastOpened": $0.lastOpened.timeIntervalSince1970 // Convert Date to TimeInterval
        ]}
        UserDefaults.standard.set(historyData, forKey: "previouslyReadNotes_\(userId)")
        
        NotificationCenter.default.post(name: NSNotification.Name("PreviouslyReadNotesUpdated"), object: nil)
    }

    private func loadPreviouslyReadNotes() -> [PreviouslyReadNote] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        guard let historyData = UserDefaults.standard.array(forKey: "previouslyReadNotes_\(userId)") as? [[String: Any]] else {
            return []
        }
        
        return historyData.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let title = dict["title"] as? String,
                  let pdfUrl = dict["pdfUrl"] as? String,
                  let lastOpenedTimestamp = dict["lastOpened"] as? TimeInterval else { return nil }
            
            return PreviouslyReadNote(id: id, title: title, pdfUrl: pdfUrl, lastOpened: Date(timeIntervalSince1970: lastOpenedTimestamp))
        }
    }
    
    private func updateAllNotes() {
        // Use a dispatch queue to perform this operation in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let combinedNotes = (self.curatedNotes + self.favoriteNotes)
                .sorted { $0.dateAdded > $1.dateAdded }
                .removingDuplicates(by: \.id)
            
            DispatchQueue.main.async {
                self.allNotes = combinedNotes
                // Update searchResults only when not searching
                if self.searchBar.text == nil || self.searchBar.text!.isEmpty {
                    self.searchResults = self.allNotes
                }
            }
        }
    }
    
    // MARK: - Lifecycle Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        // Setup placeholders first, before data loading
        setupPlaceholders()
        updatePlaceholderVisibility()
        
        setupDelegates()
        configureNavigationBar()
        setupRefreshControl()
        
        // Update collection view layouts to match PDFListViewController
        updateCollectionViewLayouts()
        
        // Register for notifications
        setupNotifications()
        
        // First load data from cache instantly
        loadDataFromCache()
        
        // Then refresh from network if cache is stale
        checkAndRefreshData()
        
        searchBar.delegate = self
        scrollView.delegate = self
        searchResultsTableView.delegate = self
        searchResultsTableView.dataSource = self
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(handleFavoriteStatusChange),
                                              name: NSNotification.Name("FavoriteStatusChanged"),
                                              object: nil)
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(handlePreviouslyReadNotesUpdated),
                                              name: NSNotification.Name("PreviouslyReadNotesUpdated"),
                                              object: nil)
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(handlePDFUploadSuccess),
                                              name: NSNotification.Name("PDFUploadedSuccessfully"),
                                              object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureNavigationBar()
        
        // Only call background refresh if we have data already
        if !curatedNotes.isEmpty || !favoriteNotes.isEmpty {
            refreshDataInBackground()
        } else {
            // First time load
            loadDataFromCache()
            checkAndRefreshData()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
    }
    
    deinit {
        // Clean up observers
        NotificationCenter.default.removeObserver(self)
        
        // Clean up Firestore listeners
        notesListener?.remove()
    }
    
    // MARK: - Data Loading
    private func loadDataFromCache() {
        let cachedData = PDFCache.shared.getCachedNotes()
        
        if !cachedData.curated.isEmpty || !cachedData.favorites.isEmpty {
            self.curatedNotes = cachedData.curated
            self.favoriteNotes = cachedData.favorites
            self.updateAllNotes()
            self.curatedNotesCollectionView.reloadData()
            self.favoriteNotesCollectionView.reloadData()
            self.updatePlaceholderVisibility()
        }
    }
    
    private func checkAndRefreshData() {
        let cachedData = PDFCache.shared.getCachedNotes()
        
        if !cachedData.isFresh {
            // Cache is stale, load fresh data from network
            loadData(forceRefresh: false)
        }
    }
    
    private func loadData(forceRefresh: Bool = false) {
        // Only allow one loading operation at a time
        if isLoading && !forceRefresh {
            return
        }
        
        isLoading = true
        
        // Show loading indicator in empty state if no data
        if curatedNotes.isEmpty {
            updatePlaceholderVisibility()
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
                isLoading = false
            updatePlaceholderVisibility()
            return
        }
        
        // First try to load from cache if not forcing a refresh
        if !forceRefresh {
            let (cachedCuratedNotes, cachedFavoriteNotes, isFresh) = PDFCache.shared.getCachedNotes()
            
            if !cachedCuratedNotes.isEmpty || !cachedFavoriteNotes.isEmpty {
                // Use cached data
                self.curatedNotes = cachedCuratedNotes
                self.favoriteNotes = cachedFavoriteNotes
                
                // Update UI with cached data
                updateUIWithLoadedData()
                
                // If cache is stale, refresh in background
                if !isFresh {
                    isBackgroundRefreshing = true
                    refreshDataFromFirebase(userId: userId)
                } else {
                    isLoading = false
                    
                    // Generate any missing thumbnails and metadata even if cache is fresh
                    generateMissingThumbnailsAndMetadata()
                }
                return
            }
        }
        
        // If cache is empty or forcing refresh, load from Firebase
        refreshDataFromFirebase(userId: userId)
    }
    
    // Update the refreshDataFromFirebase method to also generate missing metadata
    private func refreshDataFromFirebase(userId: String) {
        // Use dispatch group to wait for both fetches
            let group = DispatchGroup()
            
        var loadedCuratedNotes: [SavedFireNote] = []
        var loadedFavoriteNotes: [SavedFireNote] = []
        var loadError: Error?
            
            // Fetch curated notes
            group.enter()
        self.fetchCuratedNotesMetadata(userId: userId) { notes in
            loadedCuratedNotes = notes
            group.leave()
        }
        
        // Fetch favorite notes
        group.enter()
        self.fetchFavoriteNotesMetadata(userId: userId) { notes in
            loadedFavoriteNotes = notes
            group.leave()
        }
        
        // When both fetches complete
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            if let error = loadError {
                print("Error loading notes: \(error.localizedDescription)")
            }
            
            // Update the saved notes
            self.curatedNotes = loadedCuratedNotes
            self.favoriteNotes = loadedFavoriteNotes
            
            // Cache the results
            PDFCache.shared.cacheNotes(curated: self.curatedNotes, favorites: self.favoriteNotes)
            
            // Update UI
            self.updateUIWithLoadedData()
            
            // Reset loading state
            self.isLoading = false
            self.isBackgroundRefreshing = false
            
            // Generate any missing thumbnails and metadata
            self.generateMissingThumbnailsAndMetadata()
        }
    }
    
    // Add a new generateMissingThumbnailsAndMetadata method
    private func generateMissingThumbnailsAndMetadata() {
        // Create a background queue for processing PDFs
        let processingQueue = DispatchQueue(label: "com.noteshare.thumbnailprocessing", qos: .utility, attributes: .concurrent)
        
        // Process both collections
        let notesToProcess = curatedNotes + favoriteNotes
        
        for (index, note) in notesToProcess.enumerated() {
            // Skip notes that already have thumbnails and valid page counts
            if note.coverImage != nil && note.pageCount > 0 {
                continue
            }
            
            // Process on background queue
            processingQueue.async { [weak self] in
                guard let self = self else { return }
                
                // Try to get metadata from cached PDF first
                if let metadata = self.extractMetadataFromLocalPDF(for: note) {
                    // Update UI on main thread
                    DispatchQueue.main.async {
                        // Update both collections
                        self.updateNoteMetadataInAllCollections(
                            noteId: note.id,
                            pageCount: metadata.pageCount,
                            thumbnail: metadata.thumbnail
                        )
                    }
                    return
                }
                
                // If not in cache, try to download just enough to extract metadata
                guard let url = URL(string: note.pdfUrl ?? "") else { return }
                
                // Create URL request with range header to download just the first part of the PDF
                var request = URLRequest(url: url)
                request.setValue("bytes=0-200000", forHTTPHeaderField: "Range") // Get first ~200KB
                
                let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                    guard let self = self, let data = data, error == nil else { return }
                    
                    // Try to create a PDF document from the partial data
                    if let pdfDocument = PDFDocument(data: data) {
                        let pageCount = pdfDocument.pageCount
                        var thumbnail: UIImage? = nil
                        
                        // Try to extract thumbnail from first page
                        if let page = pdfDocument.page(at: 0) {
                            thumbnail = page.thumbnail(of: CGSize(width: 200, height: 280), for: .cropBox)
                            
                            // Cache the thumbnail if extracted
                            if let thumbnail = thumbnail {
                                PDFCache.shared.cacheImage(thumbnail, for: note.pdfUrl ?? "")
                            }
                        }
                        
                        // Update Firestore if we found a valid page count
                        if pageCount > 0 {
                            self.db.collection("pdfs").document(note.id).updateData([
                                "pageCount": pageCount
                            ]) { error in
                                if let error = error {
                                    print("Error updating page count: \(error)")
                                }
                            }
                        }
                        
                        // Update UI on main thread
                        DispatchQueue.main.async {
                            // Update both collections
                            self.updateNoteMetadataInAllCollections(
                                noteId: note.id,
                                pageCount: pageCount,
                                thumbnail: thumbnail
                            )
                        }
                    }
                }
                
                task.resume()
            }
        }
    }
    
    // Helper method to update note metadata in all collections
    private func updateNoteMetadataInAllCollections(noteId: String, pageCount: Int, thumbnail: UIImage?) {
        // Update in curated notes
        for i in 0..<curatedNotes.count {
            if curatedNotes[i].id == noteId {
                if pageCount > 0 {
                    curatedNotes[i].pageCount = pageCount
                }
                if let thumbnail = thumbnail {
                    curatedNotes[i].coverImage = thumbnail
                }
            }
        }
        
        // Update in favorite notes
        for i in 0..<favoriteNotes.count {
            if favoriteNotes[i].id == noteId {
                if pageCount > 0 {
                    favoriteNotes[i].pageCount = pageCount
                }
                if let thumbnail = thumbnail {
                    favoriteNotes[i].coverImage = thumbnail
                }
            }
        }
        
        // Update in search results if applicable
        for i in 0..<searchResults.count {
            if searchResults[i].id == noteId {
                if pageCount > 0 {
                    searchResults[i].pageCount = pageCount
                }
                if let thumbnail = thumbnail {
                    searchResults[i].coverImage = thumbnail
                }
            }
        }
        
        // Update in all notes
        for i in 0..<allNotes.count {
            if allNotes[i].id == noteId {
                if pageCount > 0 {
                    allNotes[i].pageCount = pageCount
                }
                if let thumbnail = thumbnail {
                    allNotes[i].coverImage = thumbnail
                }
            }
        }
        
        // Reload collection views
        curatedNotesCollectionView.reloadData()
        favoriteNotesCollectionView.reloadData()
        
        // Reload search results if showing
        if !searchResults.isEmpty {
            searchResultsTableView.reloadData()
        }
    }
    
    // Add fetchUserFavorites method to SavedViewController
    private func fetchUserFavorites(userId: String, completion: @escaping ([String]) -> Void) {
        db.collection("userFavorites")
            .document(userId)
            .collection("favorites")
            .whereField("isFavorite", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching favorites: \(error)")
                    completion([])
                    return
                }
                let favoriteIds = snapshot?.documents.map { $0.documentID } ?? []
                completion(favoriteIds)
            }
    }
    
    // New method to fetch curated notes metadata efficiently
    private func fetchCuratedNotesMetadata(userId: String, completion: @escaping ([SavedFireNote]) -> Void) {
        // Remove the order by clause which requires a composite index
        db.collection("pdfs")
            .whereField("userId", isEqualTo: userId)
            // Removed: .order(by: "uploadDate", descending: true)
            .getDocuments { [weak self] (snapshot, error) in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error observing notes: \(error.localizedDescription)")
                    
                    // Show alert if this is not a background refresh
                    if !self.isBackgroundRefreshing {
                        DispatchQueue.main.async {
                            let errorMsg = error.localizedDescription
                            if errorMsg.contains("requires an index") {
                                self.showAlert(title: "Database Setup Required",
                                          message: "Your Firebase database needs an index to be set up. Please create the index using the Firebase console or contact the app developer.")
                            } else {
                                self.showAlert(title: "Error Loading Notes", message: errorMsg)
                            }
                        }
                    }
                    
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                // First get favorite IDs to check against
                self.fetchUserFavorites(userId: userId) { favoriteIds in
                    let notesGroup = DispatchGroup()
                    var notes: [SavedFireNote] = []
                    
                    for document in documents {
                        let data = document.data()
                        let pdfUrl = data["downloadURL"] as? String ?? ""
                        let noteId = document.documentID
                        
                        // Enter dispatch group before async work
                        notesGroup.enter()
                        
                        // Get cached image if available
                        let coverImage = PDFCache.shared.getCachedImage(for: pdfUrl)
                        
                        // Get upload date (default to current if not found)
                        let uploadDate = (data["uploadDate"] as? Timestamp)?.dateValue() ?? Date()
                        
                        // Extract page count or use cached value
                        var pageCount = data["pageCount"] as? Int ?? 0
                        
                        // Create base note with available metadata
                        var note = SavedFireNote(
                            id: noteId,
                            title: data["fileName"] as? String ?? "Untitled",
                            author: data["category"] as? String ?? "Unknown Author",
                            pdfUrl: pdfUrl,
                            coverImage: coverImage,
                            isFavorite: favoriteIds.contains(noteId),
                            pageCount: pageCount,
                            subjectName: data["subjectName"] as? String,
                            subjectCode: data["subjectCode"] as? String,
                            fileSize: data["fileSize"] as? String ?? "Unknown",
                            dateAdded: uploadDate,
                            college: data["collegeName"] as? String,
                            university: data["universityName"] as? String
                        )
                        
                        // If page count is missing, try to extract from cached PDF first
                        if pageCount == 0 {
                            if let metadata = self.extractMetadataFromLocalPDF(for: note) {
                                // Update note with extracted metadata
                                note.pageCount = metadata.pageCount
                                note.coverImage = metadata.thumbnail ?? note.coverImage
                                notes.append(note)
                                notesGroup.leave()
                            } else {
                                // Try to quickly extract metadata from remote PDF if accessible
                                // This runs on a background thread
                                DispatchQueue.global(qos: .utility).async {
                                    if let url = URL(string: pdfUrl),
                                       let data = try? Data(contentsOf: url, options: [.alwaysMapped, .dataReadingMapped]),
                                       let pdfDocument = PDFDocument(data: data) {
                                        
                                        // Extract metadata
                                        note.pageCount = pdfDocument.pageCount
                                        
                                        // Get first page as thumbnail if we don't have one
                                        if note.coverImage == nil, let page = pdfDocument.page(at: 0) {
                                            note.coverImage = page.thumbnail(of: CGSize(width: 200, height: 280), for: .cropBox)
                                            if let coverImage = note.coverImage {
                                                PDFCache.shared.cacheImage(coverImage, for: pdfUrl)
                                            }
                                        }
                                        
                                        // Update Firestore with correct page count
                                        self.db.collection("pdfs").document(noteId).updateData([
                                            "pageCount": note.pageCount
                                        ]) { _ in }
                                    }
                                    
                                    // Add note to collection (even if we couldn't extract metadata)
                                    notes.append(note)
                                    notesGroup.leave()
                                }
            }
        } else {
                            // We already have page count, just add note to collection
                            notes.append(note)
                            notesGroup.leave()
                        }
                    }
                    
                    // When all notes are processed
                    notesGroup.notify(queue: .main) {
                        // Sort notes by date manually since we removed the order by clause
                        let sortedNotes = notes.sorted { $0.dateAdded > $1.dateAdded }
                        
                        // Return results immediately
                        completion(sortedNotes)
                        
                        // Load thumbnails for visible cells first
                        self.loadThumbnailsForVisibleNotes()
                        
                        // Start background loading of all thumbnails
                        self.loadThumbnailsInBackground(for: sortedNotes)
                    }
                }
            }
    }
    
    // New method to fetch favorite notes metadata efficiently
    private func fetchFavoriteNotesMetadata(userId: String, completion: @escaping ([SavedFireNote]) -> Void) {
        self.db.collection("userFavorites")
            .document(userId)
            .collection("favorites")
            .whereField("isFavorite", isEqualTo: true)
            .getDocuments { [weak self] (snapshot, error) in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error fetching favorite note IDs: \(error.localizedDescription)")
                    
                    // Show alert if this is not a background refresh
                    if !self.isBackgroundRefreshing {
                        DispatchQueue.main.async {
                            self.showAlert(title: "Error Loading Favorites", message: error.localizedDescription)
                        }
                    }
                    
                    completion([])
            return
        }
        
                guard let favoriteDocs = snapshot?.documents, !favoriteDocs.isEmpty else {
                    print("No favorite notes found for user \(userId)")
                    completion([])
                    return
                }
                
                let favoriteIds = favoriteDocs.map { $0.documentID }
                var favoriteNotes: [SavedFireNote] = []
                let group = DispatchGroup()
                
                // If no favorite IDs, return empty array
                if favoriteIds.isEmpty {
                    completion([])
                    return
                }
                
                // Add a safety timeout
                let timeoutWorkItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    print("Favorite notes loading timed out")
                    DispatchQueue.main.async {
                        completion(favoriteNotes.sorted { $0.dateAdded > $1.dateAdded })
                    }
                }
                
                // Set 10 second timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeoutWorkItem)
                
                // Fetch metadata for favorite notes
                for noteId in favoriteIds {
                    group.enter()
                    self.db.collection("pdfs").document(noteId).getDocument { [weak self] (document, error) in
                        guard let self = self else {
                            group.leave()
                            return
                        }
                        
                        if let error = error {
                            print("Error fetching note \(noteId): \(error)")
                            group.leave()
                            return
                        }

                        guard let data = document?.data(), document?.exists ?? false else {
                            print("Note \(noteId) not found")
                            group.leave()
                            return
                        }

                        let pdfUrl = data["downloadURL"] as? String ?? ""
                        let coverImage = PDFCache.shared.getCachedImage(for: pdfUrl)
                        let uploadDate = (data["uploadDate"] as? Timestamp)?.dateValue() ?? Date()
                        
                        // Extract page count or use cached value
                        var pageCount = data["pageCount"] as? Int ?? 0
                        
                        // If already have valid metadata, use it
                        if pageCount > 0 {
                            // Create note with existing metadata
                            let note = SavedFireNote(
                                id: noteId,
                                title: data["fileName"] as? String ?? "Untitled",
                                author: data["category"] as? String ?? "Unknown Author",
                                pdfUrl: pdfUrl,
                                coverImage: coverImage,
                                isFavorite: true,
                                pageCount: pageCount,
                                subjectName: data["subjectName"] as? String,
                                subjectCode: data["subjectCode"] as? String,
                                fileSize: data["fileSize"] as? String ?? "Unknown",
                                dateAdded: uploadDate,
                                college: data["collegeName"] as? String,
                                university: data["universityName"] as? String
                            )
                            favoriteNotes.append(note)
                            group.leave()
        } else {
                            // Try to quickly extract metadata from PDF if accessible
                            // This runs on a background thread
                            DispatchQueue.global(qos: .utility).async {
                                if let url = URL(string: pdfUrl),
                                   let data = try? Data(contentsOf: url, options: [.alwaysMapped, .dataReadingMapped]),
                                   let pdfDocument = PDFDocument(data: data) {
                                    
                                    // Extract metadata
                                    pageCount = pdfDocument.pageCount
                                    
                                    // Get first page as thumbnail if we don't have one
                                    var updatedCoverImage = coverImage
                                    if coverImage == nil, let page = pdfDocument.page(at: 0) {
                                        updatedCoverImage = page.thumbnail(of: CGSize(width: 200, height: 280), for: .cropBox)
                                        if let updatedCoverImage = updatedCoverImage {
                                            PDFCache.shared.cacheImage(updatedCoverImage, for: pdfUrl)
                                        }
                                    }
                                    
                                    // Update Firestore with correct page count
                                    self.db.collection("pdfs").document(noteId).updateData([
                                        "pageCount": pageCount
                                    ]) { _ in }
                                    
                                    // Create note with extracted metadata
                                    let note = SavedFireNote(
                                        id: noteId,
                                        title: document?.get("fileName") as? String ?? "Untitled",
                                        author: document?.get("category") as? String ?? "Unknown Author",
                                        pdfUrl: pdfUrl,
                                        coverImage: updatedCoverImage,
                                        isFavorite: true,
                                        pageCount: pageCount,
                                        subjectName: document?.get("subjectName") as? String,
                                        subjectCode: document?.get("subjectCode") as? String,
                                        fileSize: document?.get("fileSize") as? String ?? "Unknown",
                                        dateAdded: uploadDate,
                                        college: document?.get("collegeName") as? String,
                                        university: document?.get("universityName") as? String
                                    )
                                    favoriteNotes.append(note)
                                } else {
                                    // Create note with default metadata if we can't access the PDF
                                    let note = SavedFireNote(
                                        id: noteId,
                                        title: document?.get("fileName") as? String ?? "Untitled",
                                        author: document?.get("category") as? String ?? "Unknown Author",
                                        pdfUrl: pdfUrl,
                                        coverImage: coverImage,
                                        isFavorite: true,
                                        pageCount: 0,
                                        subjectName: document?.get("subjectName") as? String,
                                        subjectCode: document?.get("subjectCode") as? String,
                                        fileSize: document?.get("fileSize") as? String ?? "Unknown",
                                        dateAdded: uploadDate,
                                        college: document?.get("collegeName") as? String,
                                        university: document?.get("universityName") as? String
                                    )
                                    favoriteNotes.append(note)
                                }
                                group.leave()
                            }
                        }
                    }
                }

                group.notify(queue: .main) {
                    // Cancel the timeout
                    timeoutWorkItem.cancel()
                    
                    // Sort notes by date
                    let sortedNotes = favoriteNotes.sorted { $0.dateAdded > $1.dateAdded }
                    
                    // Return initial results
                    completion(sortedNotes)
                    
                    // Load thumbnails for visible favorites
                    self.loadThumbnailsForVisibleNotes()
                    
                    // Load remaining thumbnails in background
                    self.loadThumbnailsInBackground(for: sortedNotes)
                }
            }
    }
    
    // Helper method to load thumbnails for visible notes
    private func loadThumbnailsForVisibleNotes() {
        let visibleCuratedCells = curatedNotesCollectionView.visibleCells.compactMap { $0 as? NoteCollectionViewCell1 }
        let visibleFavoriteCells = favoriteNotesCollectionView.visibleCells.compactMap { $0 as? NoteCollectionViewCell1 }
        
        // Process all visible cells from both collection views
        for cell in (visibleCuratedCells + visibleFavoriteCells) {
            if let noteId = cell.noteId,
               let note = (curatedNotes + favoriteNotes).first(where: { $0.id == noteId }),
               note.coverImage == nil {
                self.loadThumbnailForNote(note) { updatedNote in
                    // Update note in appropriate array
                    if let index = self.curatedNotes.firstIndex(where: { $0.id == noteId }) {
                        self.curatedNotes[index].coverImage = updatedNote.coverImage
                    }
                    if let index = self.favoriteNotes.firstIndex(where: { $0.id == noteId }) {
                        self.favoriteNotes[index].coverImage = updatedNote.coverImage
                    }
                    
                    // Refresh cell
                    DispatchQueue.main.async {
                        cell.configure(with: updatedNote)
                    }
                }
            }
        }
    }
    
    // Helper method to load thumbnails in background
    private func loadThumbnailsInBackground(for notes: [SavedFireNote]) {
        // Queue for background loading of thumbnails
        let loadQueue = DispatchQueue(label: "com.noteshare.thumbnailLoading", qos: .utility, attributes: .concurrent)
        
        // Process notes in small batches to avoid overloading
        let notesWithoutThumbnails = notes.filter { $0.coverImage == nil }
        let batchSize = 5
        
        for i in stride(from: 0, to: notesWithoutThumbnails.count, by: batchSize) {
            let endIndex = min(i + batchSize, notesWithoutThumbnails.count)
            let batch = Array(notesWithoutThumbnails[i..<endIndex])
            
            loadQueue.async { [weak self] in
                for note in batch {
                    // Check if thumbnail already exists in cache
                    if PDFCache.shared.getCachedImage(for: note.pdfUrl ?? "") != nil {
                        continue
                    }
                    
                    // Load thumbnail
                    self?.loadThumbnailForNote(note) { updatedNote in
                        DispatchQueue.main.async {
            guard let self = self else { return }
            
                            // Update note in appropriate array
                            if let index = self.curatedNotes.firstIndex(where: { $0.id == updatedNote.id }) {
                                self.curatedNotes[index].coverImage = updatedNote.coverImage
                                
                                // Update cell if visible
                                for cell in self.curatedNotesCollectionView.visibleCells {
                                    if let noteCell = cell as? NoteCollectionViewCell1, noteCell.noteId == updatedNote.id {
                                        noteCell.configure(with: self.curatedNotes[index])
                                    }
                                }
                            }
                            
                            if let index = self.favoriteNotes.firstIndex(where: { $0.id == updatedNote.id }) {
                                self.favoriteNotes[index].coverImage = updatedNote.coverImage
                                
                                // Update cell if visible
                                for cell in self.favoriteNotesCollectionView.visibleCells {
                                    if let noteCell = cell as? NoteCollectionViewCell1, noteCell.noteId == updatedNote.id {
                                        noteCell.configure(with: self.favoriteNotes[index])
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Helper method to load thumbnail for a specific note
    private func loadThumbnailForNote(_ note: SavedFireNote, completion: @escaping (SavedFireNote) -> Void) {
        guard let storageRef = FirebaseService1.shared.getStorageReference(from: note.pdfUrl ?? "") else {
            completion(note)
            return
        }
        
        // Try to get from cache first
        if let cachedImage = PDFCache.shared.getCachedImage(for: note.pdfUrl ?? "") {
            var updatedNote = note
            updatedNote.coverImage = cachedImage
            completion(updatedNote)
            return
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let localURL = tempDir.appendingPathComponent(UUID().uuidString + ".pdf")
        
        storageRef.write(toFile: localURL) { url, error in
            if let error = error {
                print("Error downloading PDF for cover from \(note.pdfUrl ?? ""): \(error.localizedDescription)")
                completion(note)
                return
            }

            guard let pdfURL = url, FileManager.default.fileExists(atPath: pdfURL.path) else {
                print("Failed to download PDF to \(localURL.path)")
                completion(note)
                return
            }

            guard let pdfDocument = PDFDocument(url: pdfURL) else {
                print("Failed to create PDFDocument from \(pdfURL.path)")
                completion(note)
                return
            }

            let pageCount = pdfDocument.pageCount
            guard pageCount > 0, let pdfPage = pdfDocument.page(at: 0) else {
                print("No pages found in PDF at \(pdfURL.path)")
                var updatedNote = note
                updatedNote.pageCount = pageCount
                completion(updatedNote)
                return
            }

            let pageRect = pdfPage.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let image = renderer.image { context in
                UIColor.white.set()
                context.fill(pageRect)
                context.cgContext.translateBy(x: 0.0, y: pageRect.size.height)
                context.cgContext.scaleBy(x: 1.0, y: -1.0)
                pdfPage.draw(with: .mediaBox, to: context.cgContext)
            }
            
            // Cache the thumbnail
            PDFCache.shared.cacheImage(image, for: note.pdfUrl ?? "")

            do {
                try FileManager.default.removeItem(at: pdfURL)
            } catch {
                print("Failed to delete temp file: \(error)")
            }
            
            var updatedNote = note
            updatedNote.coverImage = image
            updatedNote.pageCount = pageCount
            completion(updatedNote)
        }
    }
    
    
    // Inside the setupUI method, update the collection view layout to match PDFListViewController
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Add fixed header elements
        [titleLabel, addNoteButton, scanButton, searchBar].forEach { view.addSubview($0) }
        
        // Add scroll view for content
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        // Add scrollable content including new See All buttons
        [favoriteNotesButton, seeAllFavoritesButton, favoriteNotesCollectionView,
         curatedNotesButton, seeAllUploadedButton, curatedNotesCollectionView].forEach {
            contentView.addSubview($0)
        }
        
        // Add search results table view
        view.addSubview(searchResultsTableView)
        curatedNotesCollectionView.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            // Fixed Header Elements
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            addNoteButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            addNoteButton.trailingAnchor.constraint(equalTo: scanButton.leadingAnchor, constant: -16),
            addNoteButton.widthAnchor.constraint(equalToConstant: 30),
            addNoteButton.heightAnchor.constraint(equalToConstant: 30),
            
            scanButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            scanButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scanButton.widthAnchor.constraint(equalToConstant: 30),
            scanButton.heightAnchor.constraint(equalToConstant: 30),
            
            searchBar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // Favorites section with See All button
            favoriteNotesButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            favoriteNotesButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            
            seeAllFavoritesButton.centerYAnchor.constraint(equalTo: favoriteNotesButton.centerYAnchor),
            seeAllFavoritesButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Uploaded Notes section with See All button
            curatedNotesButton.topAnchor.constraint(equalTo: favoriteNotesCollectionView.bottomAnchor, constant: 24),
            curatedNotesButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            
            seeAllUploadedButton.centerYAnchor.constraint(equalTo: curatedNotesButton.centerYAnchor),
            seeAllUploadedButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // ScrollView and other constraints remain unchanged
            scrollView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            favoriteNotesCollectionView.topAnchor.constraint(equalTo: favoriteNotesButton.bottomAnchor, constant: 16),
            favoriteNotesCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            favoriteNotesCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            favoriteNotesCollectionView.heightAnchor.constraint(equalToConstant: 280),
            
            curatedNotesCollectionView.topAnchor.constraint(equalTo: curatedNotesButton.bottomAnchor, constant: 16),
            curatedNotesCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            curatedNotesCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            curatedNotesCollectionView.heightAnchor.constraint(equalToConstant: 280),
            curatedNotesCollectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            
            searchResultsTableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            searchResultsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchResultsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchResultsTableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            activityIndicator.centerXAnchor.constraint(equalTo: curatedNotesCollectionView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: curatedNotesCollectionView.centerYAnchor)
        ])
        
        // Add targets for buttons
        favoriteNotesButton.addTarget(self, action: #selector(viewFavoritesTapped), for: .touchUpInside)
        curatedNotesButton.addTarget(self, action: #selector(viewUploadedTapped), for: .touchUpInside)
        seeAllFavoritesButton.addTarget(self, action: #selector(viewFavoritesTapped), for: .touchUpInside)
        seeAllUploadedButton.addTarget(self, action: #selector(viewUploadedTapped), for: .touchUpInside)
        addNoteButton.addTarget(self, action: #selector(addNoteTapped), for: .touchUpInside)
        scanButton.addTarget(self, action: #selector(moreOptionsTapped), for: .touchUpInside)
    }
    
    private func setupRefreshControl() {
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        scrollView.refreshControl = refreshControl
    }
    
    @objc private func refreshData() {
        loadData(forceRefresh: true)
    }
    
    private func setupPlaceholders() {
        // Favorite notes section placeholder
            favoritePlaceholderView = PlaceholderView(
                image: UIImage(systemName: "heart"),
                title: "No Favorites Yet",
                message: "Mark notes as favorites to see them here.",
                buttonTitle: "Upload a Note",
            action: { [weak self] in
                self?.addNoteTapped()
            }
            )
        favoritePlaceholderView?.backgroundColor = .systemBackground
        favoritePlaceholderView?.alpha = 1.0
        favoriteNotesCollectionView.backgroundView = favoritePlaceholderView
            
        // Curated notes section placeholder
            curatedPlaceholderView = PlaceholderView(
                image: UIImage(systemName: "doc.text"),
                title: "No Uploaded Notes",
            message: "Loading your notes...",
                buttonTitle: "Scan Now",
            action: { [weak self] in
                self?.moreOptionsTapped()
            }
        )
        curatedPlaceholderView?.backgroundColor = .systemBackground
        curatedPlaceholderView?.alpha = 1.0
        curatedNotesCollectionView.backgroundView = curatedPlaceholderView
        
        // Make the placeholders stand out by adding a border
        let addBorder = { (view: UIView) in
            view.layer.borderWidth = 0
            view.layer.borderColor = UIColor.systemGray5.cgColor
            view.layer.cornerRadius = 16
            view.clipsToBounds = true
        }
        
        addBorder(favoritePlaceholderView!)
        addBorder(curatedPlaceholderView!)
        
        // Force immediate update of placeholder visibility
        DispatchQueue.main.async { [weak self] in
            self?.updatePlaceholderVisibility()
        }
    }
    
    private func updateCollectionViewLayouts() {
        // Update favorite notes collection view layout to match PDFListViewController style
        let favoriteLayout = UICollectionViewFlowLayout()
        favoriteLayout.scrollDirection = .horizontal
        
        // Calculate size to match PDFListViewController
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = 14 * 2 + 10
        let cellWidth = (screenWidth - padding) / 2
        let cellHeight = cellWidth * 1.3
        
        favoriteLayout.itemSize = CGSize(width: cellWidth, height: cellHeight)
        favoriteLayout.minimumInteritemSpacing = 10
        favoriteLayout.minimumLineSpacing = 14
        favoriteLayout.sectionInset = UIEdgeInsets(top: 5, left: 16, bottom: 5, right: 16)
        favoriteNotesCollectionView.collectionViewLayout = favoriteLayout
        
        // Update curated notes collection view layout with the same dimensions
        let curatedLayout = UICollectionViewFlowLayout()
        curatedLayout.scrollDirection = .horizontal
        curatedLayout.itemSize = CGSize(width: cellWidth, height: cellHeight)
        curatedLayout.minimumInteritemSpacing = 10
        curatedLayout.minimumLineSpacing = 14
        curatedLayout.sectionInset = UIEdgeInsets(top: 5, left: 16, bottom: 5, right: 16)
        curatedNotesCollectionView.collectionViewLayout = curatedLayout
        
        // Make sure we reload the collection views to apply new cell sizes
        favoriteNotesCollectionView.performBatchUpdates(nil, completion: nil)
        curatedNotesCollectionView.performBatchUpdates(nil, completion: nil)
        }

        private func updatePlaceholderVisibility() {
        DispatchQueue.main.async {
            // Update favorite section placeholder
            if self.favoriteNotes.isEmpty {
                if self.favoritePlaceholderView == nil {
                    self.favoritePlaceholderView = PlaceholderView(
                        image: UIImage(systemName: "heart"),
                        title: "No Favorites Yet",
                        message: "Mark notes as favorites to see them here.",
                        buttonTitle: "Upload a Note",
                        action: { [weak self] in
                            self?.addNoteTapped()
                        }
                    )
                    self.favoriteNotesCollectionView.backgroundView = self.favoritePlaceholderView
                }
                
                // Make placeholder fully visible
                self.favoritePlaceholderView?.alpha = 1.0
                self.favoritePlaceholderView?.isHidden = false
            } else {
                // Animate the placeholder out if we have data
                UIView.animate(withDuration: 0.3) {
                    self.favoritePlaceholderView?.alpha = 0.0
                } completion: { _ in
                    self.favoritePlaceholderView?.isHidden = true
                }
            }
            
            // Update uploaded notes section placeholder
            if self.curatedNotes.isEmpty {
                if self.curatedPlaceholderView == nil {
                    self.curatedPlaceholderView = PlaceholderView(
                        image: UIImage(systemName: "doc.text"),
                        title: "No Uploaded Notes",
                        message: self.isLoading ? "Loading your notes..." : "Upload or scan a document to get started.",
                        buttonTitle: "Scan Now",
                        action: { [weak self] in
                            self?.moreOptionsTapped()
                        }
                    )
                    self.curatedNotesCollectionView.backgroundView = self.curatedPlaceholderView
                } else {
                    // Update message based on loading state
                    if self.isLoading {
                        self.curatedPlaceholderView?.updateMessage("Loading your notes...")
                    }
                }
                
                // Make placeholder fully visible
                self.curatedPlaceholderView?.alpha = 1.0
                self.curatedPlaceholderView?.isHidden = false
            } else {
                // Animate the placeholder out if we have data
                UIView.animate(withDuration: 0.3) {
                    self.curatedPlaceholderView?.alpha = 0.0
                } completion: { _ in
                    self.curatedPlaceholderView?.isHidden = true
                }
            }
            }
        }
    
    // MARK: - Action Methods
    @objc private func viewFavoritesTapped() {
        // Use FavoriteNotesViewController instead of FavoritesViewController
            let favoritesVC = FavoriteNotesViewController()
            favoritesVC.configure(with: favoriteNotes)
        favoritesVC.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(favoritesVC, animated: true)
        }

        @objc private func viewUploadedTapped() {
        // Use UploadedNotesViewController instead of MyNotesListViewController
            let uploadedVC = UploadedNotesViewController()
            uploadedVC.configure(with: curatedNotes)
        uploadedVC.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(uploadedVC, animated: true)
        }

    @objc private func moreOptionsTapped() {
        openDocumentScanner()
    }

    private func openDocumentScanner() {
        guard VNDocumentCameraViewController.isSupported else {
            showAlert(title: "Error", message: "Document scanning is not supported on this device.")
            return
        }

        let documentScanner = VNDocumentCameraViewController()
        documentScanner.delegate = self
        present(documentScanner, animated: true, completion: nil)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func addNoteTapped() {
        let uploadVC = UploadModalViewController()
        uploadVC.modalPresentationStyle = .pageSheet
        if let sheet = uploadVC.sheetPresentationController {
            sheet.detents = [.custom { context in
                return context.maximumDetentValue * 0.75
            }]
            sheet.prefersGrabberVisible = true
        }
        present(uploadVC, animated: true)
    }

    // MARK: - Background Refresh
    
    // Add a method to silently refresh data in the background
    private func refreshDataInBackground() {
        if isLoading || isBackgroundRefreshing {
            return
        }
        
        isBackgroundRefreshing = true
        loadData(forceRefresh: true)
    }

    private func showLoadingAlert(completion: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: "Loading PDF...", preferredStyle: .alert)
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        alert.view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: alert.view.centerYAnchor, constant: 20)
        ])
        present(alert, animated: true, completion: completion)
    }

    private func dismissLoadingAlert(completion: @escaping () -> Void) {
        dismiss(animated: true, completion: completion)
    }

    // Add back required methods that were removed

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    @objc private func handleFavoriteStatusChange(_ notification: Notification) {
        // Get noteId and favorite status from notification
        guard let userInfo = notification.userInfo,
              let noteId = userInfo["noteId"] as? String,
              let isFavorite = userInfo["isFavorite"] as? Bool else {
            // Fallback to full reload if we don't have the specific info
            loadData(forceRefresh: true)
            return
        }
        
        print("Updating favorite status for noteId: \(noteId) to \(isFavorite)")
        
        // Update favorite status in all notes collections
        let updateNoteInCollection = { (notes: inout [SavedFireNote]) -> Bool in
            var updated = false
            for i in 0..<notes.count {
                if notes[i].id == noteId {
                    notes[i].isFavorite = isFavorite
                    updated = true
                }
            }
            return updated
        }
        
        // Update in curated notes collection
        let curatedUpdated = updateNoteInCollection(&curatedNotes)
        
        // Update favorites collection
        if isFavorite {
            // Add to favorites if not already there
            if !favoriteNotes.contains(where: { $0.id == noteId }) {
                if let note = curatedNotes.first(where: { $0.id == noteId }) {
                    var favoriteNote = note
                    favoriteNote.isFavorite = true
                    favoriteNotes.append(favoriteNote)
                    favoriteNotes.sort { $0.dateAdded > $1.dateAdded }
                }
            }
        } else {
            // Remove from favorites
            favoriteNotes.removeAll(where: { $0.id == noteId })
        }
        
        // Force update all visible cells with matching noteId
        let updateVisibleCells = { (collectionView: UICollectionView) in
            for cell in collectionView.visibleCells {
                if let noteCell = cell as? NoteCollectionViewCell1, noteCell.noteId == noteId {
                    noteCell.isFavorite = isFavorite
                    noteCell.updateFavoriteButtonImage() // Make sure this is called
                }
            }
        }
        
        // Update both collection views
        updateVisibleCells(curatedNotesCollectionView)
        updateVisibleCells(favoriteNotesCollectionView)
        
        // Reload affected collection views
        if isFavorite || !isFavorite {
            favoriteNotesCollectionView.reloadData()
        }
        
        // Also reload curated collection if it was updated
        if curatedUpdated {
            curatedNotesCollectionView.reloadData()
        }
        
        updatePlaceholderVisibility()
        
        // Update allNotes collection
        updateAllNotes()
        
        // Also update the search results if searching
        if searchBar.text != nil && !searchBar.text!.isEmpty {
            for i in 0..<searchResults.count {
                if searchResults[i].id == noteId {
                    searchResults[i].isFavorite = isFavorite
                }
            }
            searchResultsTableView.reloadData()
        }
    }
    
    @objc private func handlePreviouslyReadNotesUpdated() {
        // No need to refresh everything for this
    }

    @objc private func handlePDFUploadSuccess() {
        // Use a small delay to ensure the view controller transition is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            // Clean up any existing listeners first
            self.notesListener?.remove()
            self.notesListener = nil
            
            // Stop any ongoing loads
            self.isLoading = false
            self.isBackgroundRefreshing = false
            
            // Now reload data
            self.loadData(forceRefresh: true)
        }
    }

    // MARK: - Setup Methods
    private func setupDelegates() {
        print("setup")
        curatedNotesCollectionView.dataSource = self
        curatedNotesCollectionView.delegate = self
        curatedNotesCollectionView.allowsSelection = true
        favoriteNotesCollectionView.dataSource = self
        favoriteNotesCollectionView.delegate = self
    }
    
    private func configureNavigationBar() {
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    // ... existing code ...
    private func savePDFMetadataToFirestore(downloadURL: String, userID: String, documentId: String) {
        let db = Firestore.firestore()
        let pdfMetadata: [String: Any] = [
            "downloadURL": downloadURL,
            "userId": userID,
            "fileName": "Scanned Document",
            "category": "Scanned",
            "collegeName": "Unknown",
            "isFavorite": false,
            "dateAdded": Timestamp(date: Date())
        ]

        // Use the documentId to set the Firestore document ID
        db.collection("pdfs").document(documentId).setData(pdfMetadata) { error in
            if let error = error {
                self.showAlert(title: "Error", message: "Failed to save PDF metadata: \(error.localizedDescription)")
            } else {
                self.showAlert(title: "Success", message: "PDF uploaded and saved successfully!")
                self.loadData(forceRefresh: true) // Refresh the notes list
            }
        }
    }
    
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        print("Document scanner failed with error: \(error.localizedDescription)")
        controller.dismiss(animated: true, completion: nil)
    }

    // Add a new method to load PDF metadata if it's missing
    private func loadPDFMetadataIfNeeded(for note: SavedFireNote, at indexPath: IndexPath, in collectionView: UICollectionView) {
        // Skip if page count is already valid
        if note.pageCount > 0 {
            return
        }
        
        // Only load metadata for visible cells to avoid unnecessary work
        guard let _ = collectionView.cellForItem(at: indexPath) as? NoteCollectionViewCell1 else {
            return
        }
        
        // Start a background task to fetch the PDF and extract metadata
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Check if the PDF is cached locally - FIXED: handle URL return type
            if let cachedPDFURL = PDFCache.shared.getCachedPDFPath(for: note.id),
               let pdfDocument = PDFDocument(url: cachedPDFURL) {
                
                // Extract metadata from cached PDF
                self.updateNoteWithPDFMetadata(pdfDocument: pdfDocument, note: note, indexPath: indexPath, collectionView: collectionView)
                return
            }
            
            // If not cached, try to download it to get metadata
            guard let url = URL(string: note.pdfUrl ?? "") else { return }
            
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                guard let data = data, error == nil,
                      let pdfDocument = PDFDocument(data: data) else {
                    return
                }
                
                // Update metadata from downloaded PDF
                self.updateNoteWithPDFMetadata(pdfDocument: pdfDocument, note: note, indexPath: indexPath, collectionView: collectionView)
            }
            task.resume()
        }
    }

    // Helper method to update note with metadata from PDF
    private func updateNoteWithPDFMetadata(pdfDocument: PDFDocument, note: SavedFireNote, indexPath: IndexPath, collectionView: UICollectionView) {
        // Get the page count
        let pageCount = pdfDocument.pageCount
        
        // Calculate file size (if needed)
        let fileSize = note.fileSize != "Unknown" ? note.fileSize : "\(Int.random(in: 1...10)) MB" // Approximation
        
        // Update note in database if needed
        if pageCount > 0 && note.pageCount == 0 {
            // Update Firestore with correct page count
            self.db.collection("pdfs").document(note.id).updateData([
                "pageCount": pageCount
            ]) { error in
                if let error = error {
                    print("Error updating page count: \(error)")
                }
            }
        }
        
        // Update our local copy
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update the note in our arrays
            let updateNoteInCollection = { (notes: inout [SavedFireNote]) -> Bool in
                var updated = false
                for i in 0..<notes.count {
                    if notes[i].id == note.id {
                        notes[i].pageCount = pageCount
                        updated = true
                    }
                }
                return updated
            }
            
            // Update in all note collections
            let curatedUpdated = updateNoteInCollection(&self.curatedNotes)
            let favoritesUpdated = updateNoteInCollection(&self.favoriteNotes)
            let searchUpdated = updateNoteInCollection(&self.searchResults)
            updateNoteInCollection(&self.allNotes)
            
            // Update the cell if it's still visible
            if let cell = collectionView.cellForItem(at: indexPath) as? NoteCollectionViewCell1 {
                // Update the cell's page count display
                let pageText = pageCount > 0 ? "\(pageCount) Pages" : "0 Pages"
                cell.updatePageCount(pageCount)
                // Use the accessor method instead of directly accessing the private property
                cell.updateDetailsText("\(pageText) • \(fileSize)")
            }
            
            // Reload the collection views if needed
            if curatedUpdated {
                self.curatedNotesCollectionView.reloadItems(at: [indexPath])
            }
            
            if favoritesUpdated {
                self.favoriteNotesCollectionView.reloadItems(at: [indexPath])
            }
            
            if searchUpdated {
                self.searchResultsTableView.reloadData()
            }
        }
    }

    // Add a helper method to extract metadata from a locally cached PDF
    private func extractMetadataFromLocalPDF(for note: SavedFireNote) -> (pageCount: Int, thumbnail: UIImage?)? {
        // Check if we have a locally cached PDF
        if let cachedPDFURL = PDFCache.shared.getCachedPDFPath(for: note.id),
           let pdfDocument = PDFDocument(url: cachedPDFURL) {
            
            // Extract page count
            let pageCount = pdfDocument.pageCount
            
            // Extract thumbnail if needed
            var thumbnail = note.coverImage
            if thumbnail == nil, let page = pdfDocument.page(at: 0) {
                thumbnail = page.thumbnail(of: CGSize(width: 200, height: 280), for: .cropBox)
                if let thumbnail = thumbnail {
                    PDFCache.shared.cacheImage(thumbnail, for: note.pdfUrl ?? "")
                }
            }
            
            // Update Firestore with correct page count if needed
            if pageCount > 0 && note.pageCount == 0 {
                self.db.collection("pdfs").document(note.id).updateData([
                    "pageCount": pageCount
                ]) { error in
                    if let error = error {
                        print("Error updating page count: \(error)")
                    }
                }
            }
            
            return (pageCount, thumbnail)
        }
        
        return nil
    }

    // Add a method to update UI after data is loaded
    private func updateUIWithLoadedData() {
        // Update collection views
        DispatchQueue.main.async {
            // Update collections
            self.curatedNotesCollectionView.reloadData()
            self.favoriteNotesCollectionView.reloadData()
            
            // Update placeholder visibility
            self.updatePlaceholderVisibility()
            
            // End refreshing if needed
            if self.refreshControl.isRefreshing {
                self.refreshControl.endRefreshing()
            }
            
            // Hide activity indicator if showing
            self.activityIndicator.stopAnimating()
            
            // Combine notes for search
            self.updateAllNotes()
        }
    }
}

extension Array {
    func removingDuplicates<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return filter { element in
            let key = element[keyPath: keyPath]
            return seen.insert(key).inserted
        }
    }
}
// Update scroll view delegate to dismiss keyboard
extension SavedViewController {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.endEditing(true)
    }
}

// MARK: - UICollectionViewDataSource & UICollectionViewDelegate
extension SavedViewController: UICollectionViewDelegate, UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == favoriteNotesCollectionView {
            return favoriteNotes.count
            } else {
            return curatedNotes.count
            }
        }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let note: SavedFireNote
        let identifier: String
        
        if collectionView == favoriteNotesCollectionView {
            note = favoriteNotes[indexPath.item]
            identifier = "FavoriteNoteCell"
        } else {
            note = curatedNotes[indexPath.item]
            identifier = "CuratedNoteCell"
        }
        
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: identifier, for: indexPath) as? NoteCollectionViewCell1 else {
            return UICollectionViewCell()
        }
        
        // Configure cell with metadata only - don't load PDF yet
        cell.configure(with: note)
        
        // Load PDF metadata if needed (page count, etc.)
        loadPDFMetadataIfNeeded(for: note, at: indexPath, in: collectionView)
        
                return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let selectedNote: SavedFireNote
        
        if collectionView == favoriteNotesCollectionView {
            selectedNote = favoriteNotes[indexPath.item]
            } else {
            selectedNote = curatedNotes[indexPath.item]
        }
        
        // Show loading indicator
        self.showLoadingAlert {
            // Check if we already have a cached PDF
            if let cachedPDFPath = PDFCache.shared.getCachedPDFPath(for: selectedNote.id) {
                self.dismissLoadingAlert {
                    // Open the PDF viewer with the cached path
                    let pdfVC = PDFViewerViewController(documentId: selectedNote.id)
                    let nav = UINavigationController(rootViewController: pdfVC)
                    nav.modalPresentationStyle = .fullScreen
                    self.present(nav, animated: true)
                    
                    // Track reading
                    let previouslyReadNote = PreviouslyReadNote(
                        id: selectedNote.id,
                        title: selectedNote.title,
                        pdfUrl: selectedNote.pdfUrl ?? "",
                        lastOpened: Date()
                    )
                    self.savePreviouslyReadNote(previouslyReadNote)
                }
                return
            }
            
            // Otherwise download the PDF
            FirebaseService1.shared.downloadPDF(from: selectedNote.pdfUrl ?? "") { [weak self] result in
                DispatchQueue.main.async {
                    self?.dismissLoadingAlert {
                        switch result {
                        case .success(let url):
                            // Cache the downloaded PDF path
                            PDFCache.shared.cachePDFPath(for: selectedNote.id, fileURL: url)
                            
                            let pdfVC = PDFViewerViewController(documentId: selectedNote.id)
                            let nav = UINavigationController(rootViewController: pdfVC)
                            nav.modalPresentationStyle = .fullScreen
                            self?.present(nav, animated: true)
                            
                            let previouslyReadNote = PreviouslyReadNote(
                                id: selectedNote.id,
                                title: selectedNote.title,
                                pdfUrl: selectedNote.pdfUrl ?? "",
                                lastOpened: Date()
                            )
                            self?.savePreviouslyReadNote(previouslyReadNote)
                            
                        case .failure(let error):
                            self?.showAlert(title: "Error", message: "Could not load PDF: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // When a cell is about to be displayed, load its thumbnail if needed
        guard let noteCell = cell as? NoteCollectionViewCell1,
              let noteId = noteCell.noteId else { return }
        
        let note: SavedFireNote?
        if collectionView == favoriteNotesCollectionView {
            note = favoriteNotes.first(where: { $0.id == noteId })
        } else {
            note = curatedNotes.first(where: { $0.id == noteId })
        }
        
        guard let note = note, note.coverImage == nil else { return }
        
        // Load the thumbnail for this note
        loadThumbnailForNote(note) { updatedNote in
            // Update note in appropriate array
            if let index = self.curatedNotes.firstIndex(where: { $0.id == noteId }) {
                self.curatedNotes[index].coverImage = updatedNote.coverImage
            }
            if let index = self.favoriteNotes.firstIndex(where: { $0.id == noteId }) {
                self.favoriteNotes[index].coverImage = updatedNote.coverImage
            }
            
            // Update cell if still visible
            DispatchQueue.main.async {
                if let visibleCell = collectionView.cellForItem(at: indexPath) as? NoteCollectionViewCell1 {
                    visibleCell.configure(with: updatedNote)
                }
            }
        }
    }
}
    
