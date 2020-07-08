import Foundation

// MARK: - ReaderInterestViewModel
class ReaderInterestViewModel {
    var isSelected: Bool = false

    var title: String {
        return interest.title
    }

    var slug: String {
        return interest.slug
    }

    private var interest: RemoteReaderInterest

    init(interest: RemoteReaderInterest) {
        self.interest = interest
    }

    public func toggleSelected() {
        self.isSelected = !isSelected
    }
}

// MARK: - ReaderInterestsDataDelegate
protocol ReaderInterestsDataDelegate: AnyObject {
    func readerInterestsDidUpdate(_ dataSource: ReaderInterestsDataSource)
}

protocol ReaderInterestsService: AnyObject {
    func fetchInterests(success: @escaping ([RemoteReaderInterest]) -> Void,
                        failure: @escaping (Error) -> Void)
}

// MARK: - ReaderInterestsDataSource
class ReaderInterestsDataSource {
    var delegate: ReaderInterestsDataDelegate?

    private(set) var count: Int = 0
    private(set) var interests: [ReaderInterestViewModel] = [] {
        didSet {
            count = interests.count

            delegate?.readerInterestsDidUpdate(self)
        }
    }

    var selectedInterests: [ReaderInterestViewModel] {
        return interests.filter({ $0.isSelected })
    }

    private var interestsService: ReaderInterestsService

    /// Creates a new instance of the data source
    /// - Parameter topicService: An Optional `ReaderTopicService` to use. If this is `nil` one will be created on the main context
    init(service: ReaderInterestsService? = nil) {
        guard let service = service else {
            let context = ContextManager.sharedInstance().mainContext
            self.interestsService = ReaderTopicService(managedObjectContext: context)

            return
        }

        self.interestsService = service
    }

    /// Fetches the interests from the topic service
    public func reload() {
        interestsService.fetchInterests(success: { interests in
            self.interests = interests.map({ ReaderInterestViewModel(interest: $0)})
        }) { (error: Error) in
            DDLogError("Error: Could not retrieve reader interests: \(String(describing: error))")

            self.interests = []
        }
    }

    /// Toggles the selected state for the item at the specified row
    /// - Parameter row: The row of the interest you want to toggle
    public func toggleSelected(for row: Int) {
        interests[row].toggleSelected()
    }

    /// Returns a reader interest for the specified row
    /// - Parameter row: The index of the item you want to return
    /// - Returns: A reader interest model
    public func interest(for row: Int) -> ReaderInterestViewModel {
        return interests[row]
    }
}
