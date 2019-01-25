@objc enum QuickStartType: Int {
    case customize
    case grow
}

class QuickStartChecklistViewController: UITableViewController {
    private var dataManager: QuickStartChecklistManager? {
        didSet {
            tableView?.dataSource = dataManager
            tableView?.delegate = dataManager
        }
    }
    private var blog: Blog?
    private var type: QuickStartType?
    private var observer: NSObjectProtocol?

    @objc convenience init(blog: Blog, type: QuickStartType) {
        self.init()
        self.blog = blog
        self.type = type

        startObservingForQuickStart()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureTableView()

        guard let blog = blog,
            let type = type else {
            return
        }

        navigationItem.title = type.configuration.title

        dataManager = QuickStartChecklistManager(blog: blog,
                                                 tours: type.configuration.tours,
                                                 didSelectTour: { [weak self] analyticsKey in
            DispatchQueue.main.async {
                WPAnalytics.track(.quickStartChecklistItemTapped, withProperties: ["task_name": analyticsKey])
                self?.navigationController?.popViewController(animated: true)
            }
        }, didTapHeader: { collapse in
            // display/hide congratulation screen
        })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // should display bg and trigger qs notification

        WPAnalytics.track(.quickStartChecklistViewed)
    }
}

private extension QuickStartChecklistViewController {
    func configureTableView() {
        let tableView = UITableView(frame: .zero)

        if #available(iOS 10, *) {
            tableView.estimatedRowHeight = 90.0
        }
        tableView.separatorStyle = .none

        let cellNib = UINib(nibName: "QuickStartChecklistCell", bundle: Bundle(for: QuickStartChecklistCell.self))
        tableView.register(cellNib, forCellReuseIdentifier: QuickStartChecklistCell.reuseIdentifier)

        self.tableView = tableView
    }

    func startObservingForQuickStart() {
        observer = NotificationCenter.default.addObserver(forName: .QuickStartTourElementChangedNotification, object: nil, queue: nil) { [weak self] (notification) in
            guard let userInfo = notification.userInfo,
                let element = userInfo[QuickStartTourGuide.notificationElementKey] as? QuickStartTourElement,
                element == .tourCompleted else {
                    return
            }
            self?.reload()
        }
    }

    func reload() {
        dataManager?.reloadData()
        tableView.reloadData()
    }
}

private extension QuickStartType {
    var tasksCompleteScreen: TasksCompleteScreenConfiguration {
        switch self {
        case .customize:
            return TasksCompleteScreenConfiguration(title: Constants.tasksCompleteScreenTitle,
                                                    subtitle: Constants.tasksCompleteScreenSubtitle,
                                                    imageName: "wp-illustration-tasks-complete-site")
        case .grow:
            return TasksCompleteScreenConfiguration(title: Constants.tasksCompleteScreenTitle,
                                                    subtitle: Constants.tasksCompleteScreenSubtitle,
                                                    imageName: "wp-illustration-tasks-complete-audience")
        }
    }

    var configuration: QuickStartChecklistConfiguration {
        switch self {
        case .customize:
            return QuickStartChecklistConfiguration(title: Constants.customizeYourSite,
                                                    tours: QuickStartTourGuide.customizeListTours)
        case .grow:
            return QuickStartChecklistConfiguration(title: Constants.growYourAudience,
                                                    tours: QuickStartTourGuide.growListTours)
        }
    }
}

private struct TasksCompleteScreenConfiguration {
    var title: String
    var subtitle: String
    var imageName: String
}

private struct QuickStartChecklistConfiguration {
    var title: String
    var tours: [QuickStartTour]
}

private enum Constants {
    static let customizeYourSite = NSLocalizedString("Customize Your Site", comment: "Title of the Quick Start Checklist that guides users through a few tasks to customize their new website.")
    static let growYourAudience = NSLocalizedString("Grow Your Audience", comment: "Title of the Quick Start Checklist that guides users through a few tasks to grow the audience of their new website.")
    static let tasksCompleteScreenTitle = NSLocalizedString("All tasks complete", comment: "Title of the congratulation screen that appears when all the tasks are completed")
    static let tasksCompleteScreenSubtitle = NSLocalizedString("Congratulations on completing your list. A job well done.", comment: "Subtitle of the congratulation screen that appears when all the tasks are completed")
}
